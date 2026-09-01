#!/usr/bin/env python3
"""The detached speaker: the whole of the speech path below the Stop hook.

`speak.sh` drops a job and forks this, detached, then exits 0. Everything that
can take time lives here, which is what makes §6's non-blocking guarantee a
property of the shape rather than of a timeout:

  1. os.setsid() -- macOS ships no setsid(1) in the base install, so
     detachment has to be done in-process. It also makes this process a
     process-group leader, so the players it spawns share its group and one
     signal reaches all of them.
  2. THE EXCLUSIVE CONSUMER CLAIM (§3.5.1 clause 5, §5.1).  See `claim()`.
  3. §3.5.1's BOUNDED WAIT for `speak/rw.<hash>` to appear. This is the piece
     the spec puts in the resident worker; there is no worker here, so it is
     here instead -- never in the hook. `Stop` fires a median 6.7 ms BEFORE the
     final `MessageDisplay` chunk and the buffer was stale 29 of 30 times, so
     without the wait the feature is silent on nearly every turn.
  4. §5.1's dedup, at the moment text goes to synthesis (§3.5.1 clause 6).
  5. the settled sanitizer, then sentence splitting, then Kokoro sentence by
     sentence with playback overlapped so audio starts on sentence one.
  6. the runtime mute, RE-CHECKED before every synthesis, before every play,
     and while a play is in flight (§3.5.1 clause 7, the [inferred] clause that
     is actually user-visible: `touch ~/.claude/claudish-speak-off` must stop
     audio that is already sounding).

WHAT IS REUSED RATHER THAN REWRITTEN.  `speech/` at the plugin root owns both
pieces and `bench/` is now their second caller:

  * `speech.sanitize(text)` is `sanitizers.REGISTRY['settled']`, the spec's
    locked sanitizer set (§4.2) -- the one variant that was auditioned as a
    whole, preferred on all nine blind pairs it appeared in. No sanitizer is
    written here and the runtime gets no knobs.
  * `speech.split_sentences(text)` walks `speech/split.py`'s `_SENT_END`, the
    same boundary rule `first_sentence()` uses and the same code
    `bench/first-sentence.py` measured 12/12 under the 3 s line with.

  Order is normative: SANITIZE FIRST, SPLIT SECOND (§4). In `r10` the first
  full stop sits inside `**...find.**`, so splitting raw text yields a 219-char
  "first sentence" (3.58 s, FAIL) where splitting sanitized text yields 32
  chars (0.50 s, PASS).

WHAT IS DEFERRED (docs/decisions/speak-cold-path.md is the collected list):
  * §10.5's resident worker. This process is forked per turn and exits when the
    utterance ends. No generation election, no kqueue wake, no
    start-time-validated owner records, no retirement protocol, no idle timer.
  * §10.6's anchored player-record preemption protocol. See `claim()`.
  * §10.5 clause 1's job claim by rename to `job.taken.<pid>`. There is no
    shared worker, so each child owns its own job file outright.

Nothing here can affect the hook's exit status: by the time this runs, the hook
has exited 0 and the prompt is long released. Failure is silence.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import signal
import subprocess
import sys
import time

POLL = 0.2            # §3.5.1's wake interval for the bounded wait
PLAY_POLL = 0.15      # how often a play in flight re-checks the mute files
CLAIM_DEADLINE = 5.0  # give up rather than risk a second consumer
CLAIM_GRACE = 1.5     # TERM -> this long -> KILL, the providers.sh idiom
OWNER_GRACE = 1.0     # how long a lock with no owner record yet is respected


# --------------------------------------------------------------------------
# plumbing
# --------------------------------------------------------------------------

def dbg(buf_root: str, msg: str) -> None:
    """CLAUDISH_DEBUG's only sink is $BUF_ROOT/debug.log (§10.1)."""
    if os.environ.get("CLAUDISH_DEBUG", "0") != "1":
        return
    try:
        with open(os.path.join(buf_root, "debug.log"), "a", encoding="utf-8") as fh:
            fh.write("%s [%d] speak-child: %s\n"
                     % (time.strftime("%H:%M:%S"), os.getpid(), msg))
    except OSError:
        pass


def atomic_write(path: str, data: str) -> bool:
    """temp-write + rename, inside the same directory. The idiom §3.1 uses."""
    tmp = "%s.tmp.%d" % (path, os.getpid())
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(data)
        os.rename(tmp, path)
        return True
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        return False


def read_file(path: str) -> str | None:
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return None


# --------------------------------------------------------------------------
# process identity: a pid alone is not one
# --------------------------------------------------------------------------

UNVERIFIABLE = "unverifiable"


def lstart(pid: int):
    """Canonical start time of `pid`: five whitespace-separated `ps` fields
    joined by single spaces -- e.g. "Wed Aug 26 23:58:12 2026".

    Returns the string, None for a CONFIRMED absence, or UNVERIFIABLE when the
    lookup itself failed. Those are three different answers and §10.3 step 6 is
    explicit that the third is not the second: treating "I could not ask" as
    "nothing is there" is how a signal reaches a stranger.

    `speak.sh` builds the identical string with
    `ps -p <pid> -o lstart= | awk '{printf "%s %s %s %s %s", $1,$2,$3,$4,$5}'`,
    so the two sides compare the same bytes.
    """
    try:
        r = subprocess.run(["ps", "-p", str(pid), "-o", "lstart="],
                           capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return UNVERIFIABLE
    if r.returncode != 0:
        return None                      # ps exits non-zero: no such process
    parts = r.stdout.split()
    if len(parts) < 5:
        return None
    return " ".join(parts[:5])


def is_speaker(pid: int) -> bool:
    try:
        r = subprocess.run(["ps", "-p", str(pid), "-o", "command="],
                           capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return False
    return "speak-child.py" in r.stdout


def my_record() -> str:
    ls = lstart(os.getpid())
    return "%d\n%s\n" % (os.getpid(), ls if isinstance(ls, str) and ls != UNVERIFIABLE else "")


def parse_record(text: str | None):
    if not text:
        return None
    lines = text.splitlines()
    if not lines:
        return None
    try:
        pid = int(lines[0].strip())
    except ValueError:
        return None
    if pid <= 1:
        return None
    return pid, (lines[1].strip() if len(lines) > 1 else "")


# --------------------------------------------------------------------------
# the two off-files, re-checked constantly
# --------------------------------------------------------------------------

def off_files() -> tuple[str, str]:
    home = os.path.expanduser("~")
    return (
        os.environ.get("CLAUDISH_OFF_FILE",
                       os.path.join(home, ".claude", "claudish-off")),
        os.environ.get("CLAUDISH_SPEAK_OFF_FILE",
                       os.path.join(home, ".claude", "claudish-speak-off")),
    )


def muted(paths: tuple[str, str]) -> bool:
    """§3.5.1 clause 7. The hook's stat of these can be the whole 50 s wait
    older than the sound, so this is asked again before every synthesis, before
    every play, and every PLAY_POLL seconds while a play is in flight. Either
    file stops speech: `claudish-speak-off` stops speech and keeps rewriting,
    `claudish-off` stops both."""
    return os.path.exists(paths[0]) or os.path.exists(paths[1])


# --------------------------------------------------------------------------
# THE EXCLUSIVE CONSUMER CLAIM  -- §3.5.1 clause 5 and §5.1
# --------------------------------------------------------------------------
#
# WHY THIS EXISTS, and it is the single largest correctness risk in the cold
# path.  §3.5.1 clause 5 ("at most one wait is ever outstanding per session")
# and §5.1's lock-free dedup against `speak/spoken` both rest on the resident
# worker being the sole consumer BY ELECTION.  There is no election here: every
# `Stop` forks its own speaker.  So the invariant has to be re-established, and
# if it is not, TWO forked speakers finish their waits and SPEAK THE SAME TURN
# OVER EACH OTHER -- two voices, out of phase, saying the same words.  That is
# what a missed claim sounds like.
#
# The mechanism is `mkdir(2)` on `speak/consumer`, which is atomic on every
# filesystem this plugin can run on and needs none of §10.5's symlink
# generation protocol.  Inside it, `owner` holds `<pid>\n<lstart>` -- a pid
# alone is not an identity, and the start time is what tells a live predecessor
# from a recycled pid.  Newer turn wins (§10.6): an incumbent that validates is
# TERMed, then KILLed after CLAIM_GRACE, and only then is its lock broken.
#
# WHAT IT IS NOT: §10.6's anchored player-record protocol.  There is no
# `playerdir/`, no per-player `<pid>.<nonce>` record matched on an anchored
# `^[0-9]+\.[0-9a-f]{8}$`, no `.pending` markers, no generation prefix.  One
# lock, one owner record, one process group.
#
# WHAT IT STILL DOES NOT GUARANTEE, said plainly rather than implied away:
#   * an incumbent that survives SIGKILL (uninterruptible sleep) holds the lock
#     until CLAIM_DEADLINE, after which this process EXITS SILENTLY rather than
#     breaking the lock.  The turn is lost, not doubled -- the safe direction.
#   * `lstart` has one-second resolution, so a pid recycled inside the same
#     second as its predecessor's start reads as a match.  §10.6 has the same
#     residual and says so.
#   * a lock directory whose `owner` never appears is broken after OWNER_GRACE.
#     A predecessor stalled for longer than that between `mkdir` and its own
#     `owner` write would be double-consumed.  Nothing has been observed doing
#     that; the window is two syscalls wide.

def break_lock(lockdir: str, owner: str) -> None:
    try:
        os.unlink(owner)
    except OSError:
        pass
    try:
        os.rmdir(lockdir)
    except OSError:
        pass


def claim(speak_dir: str, buf_root: str) -> bool:
    """Become the session's one consumer, or return False and say nothing."""
    lockdir = os.path.join(speak_dir, "consumer")
    owner = os.path.join(lockdir, "owner")
    record = my_record()
    deadline = time.time() + CLAIM_DEADLINE
    termed_at = None
    no_owner_since = None

    while True:
        try:
            os.mkdir(lockdir)
        except FileExistsError:
            pass
        except OSError as exc:
            dbg(buf_root, "cannot create consumer lock: %r" % (exc,))
            return False
        else:
            # The mkdir is the claim; the owner record is what lets the NEXT
            # turn tell a live incumbent from a corpse. If it never lands, the
            # "lock with no owner record" branch below is no longer a
            # two-syscall window -- it is permanent: the next speaker waits
            # OWNER_GRACE, breaks a lock we are still holding, and both of us
            # speak the session. Two voices, which is the one failure this
            # whole function exists to prevent. So an unwritable owner record
            # gives the lock back and loses the turn instead: the safe
            # direction, and the one CLAIM_DEADLINE already chooses below.
            if not atomic_write(owner, record):
                dbg(buf_root, "cannot write consumer owner record -> silent")
                break_lock(lockdir, owner)
                return False
            return True

        rec = parse_record(read_file(owner))
        if rec is None:
            # Either a predecessor between its mkdir and its owner write, or a
            # lock left behind by one that died in that two-syscall window.
            if no_owner_since is None:
                no_owner_since = time.time()
            elif time.time() - no_owner_since > OWNER_GRACE:
                dbg(buf_root, "consumer lock has no owner record -> breaking")
                break_lock(lockdir, owner)
                no_owner_since = None
        else:
            no_owner_since = None
            pid, want = rec
            if pid == os.getpid():
                return True                      # already ours
            cur = lstart(pid)
            if cur is None:
                dbg(buf_root, "consumer %d is gone -> breaking its lock" % pid)
                break_lock(lockdir, owner)
            elif cur is UNVERIFIABLE:
                # Could not ask. Do NOT signal and do NOT break -- the pid may
                # now name a stranger. Wait it out; the deadline is the escape.
                pass
            elif want and cur != want:
                dbg(buf_root, "consumer record %d is a recycled pid -> breaking" % pid)
                break_lock(lockdir, owner)
            elif not is_speaker(pid):
                dbg(buf_root, "consumer %d is not one of ours -> breaking" % pid)
                break_lock(lockdir, owner)
            else:
                # A live predecessor. Newer turn wins: TERM its whole process
                # group so its player dies with it, then KILL, then break.
                if termed_at is None:
                    dbg(buf_root, "preempting live consumer %d" % pid)
                    try:
                        os.killpg(pid, signal.SIGTERM)
                    except OSError:
                        pass
                    termed_at = time.time()
                elif time.time() - termed_at > CLAIM_GRACE:
                    try:
                        os.killpg(pid, signal.SIGKILL)
                    except OSError:
                        pass
                    break_lock(lockdir, owner)
                    termed_at = None

        if time.time() > deadline:
            dbg(buf_root, "could not claim the consumer lock -> silent")
            return False
        time.sleep(0.1)


def release(speak_dir: str) -> None:
    """Drop the claim, but only if it is still ours."""
    lockdir = os.path.join(speak_dir, "consumer")
    owner = os.path.join(lockdir, "owner")
    rec = parse_record(read_file(owner))
    if rec is None or rec[0] == os.getpid():
        break_lock(lockdir, owner)


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def parse_job(raw: str) -> tuple[dict, str]:
    head, _, text = raw.partition("\n--TEXT--\n")
    meta = {}
    for line in head.splitlines():
        k, _, v = line.partition("=")
        meta[k.strip()] = v
    return meta, text


def _on_term(signum, frame):
    # A preemptor TERMs our whole group. Turn it into a SystemExit so main's
    # `finally` runs and the claim is released instead of being left behind.
    raise SystemExit(0)


def main(argv: list[str]) -> int:
    try:
        os.setsid()
    except OSError:
        pass
    signal.signal(signal.SIGTERM, _on_term)
    signal.signal(signal.SIGINT, _on_term)

    buf_root = os.path.join(os.environ.get("TMPDIR", "/tmp"),
                            "claudish-to-english")
    if len(argv) < 2:
        return 0
    job_path = argv[1]
    speak_dir = os.path.dirname(os.path.abspath(job_path))

    raw = read_file(job_path)
    try:
        os.unlink(job_path)          # our job, ours to consume
    except OSError:
        pass
    if not raw:
        return 0
    meta, payload_text = parse_job(raw)

    off = off_files()
    root = meta.get("root") or os.path.dirname(os.path.abspath(__file__))
    mode = meta.get("mode", "buffered")
    want = meta.get("hash", "")
    voice = meta.get("voice") or "bf_emma"
    player_cmd = meta.get("player") or "afplay"

    def num(key, default):
        try:
            return float(meta.get(key, default))
        except ValueError:
            return float(default)

    fire = num("fire", 0)
    wait_budget = num("wait", 0)
    synth_budget = num("synth_timeout", 30)

    t_fork = time.time()
    if not claim(speak_dir, buf_root):
        return 0
    try:
        return speak(buf_root, speak_dir, root, off, mode, want, payload_text,
                     voice, player_cmd, fire, wait_budget, synth_budget, t_fork)
    finally:
        release(speak_dir)


def speak(buf_root, speak_dir, root, off, mode, want, payload_text,
          voice, player_cmd, fire, wait_budget, synth_budget, t_fork) -> int:
    # §3.5.1's BOUNDED WAIT. Wall clock, not time.monotonic(): monotonic stops
    # while the machine sleeps, and a machine that slept through the turn
    # should not get a longer window. The deadline is measured from the HOOK's
    # fire time, not from here, so a slow fork cannot silently extend it.
    if mode == "buffered":
        target = os.path.join(speak_dir, "rw." + want)
        deadline = (fire or t_fork) + wait_budget
        while True:
            if muted(off):
                dbg(buf_root, "muted during wait -> silent")
                return 0
            if os.path.exists(target):
                break
            if time.time() >= deadline:
                # §3.5.1 clause 4: give up, stay silent, exit 0. A rewrite was
                # due above the threshold and did not arrive; #1's out-of-scope
                # rule bans speaking raw text on that path.
                dbg(buf_root, "wait deadline passed for rw.%s -> silent" % want[:12])
                return 0
            time.sleep(POLL)
        # The path is computed from our own expected hash and can hold no
        # rewrite of any other text, so there is nothing to compare (§3.1
        # draft 3). No re-read, no mutable marker, no read ordering.
        text = read_file(target)
        if not text or not text.strip():
            return 0
        source = "rw.%s" % want[:12]
    else:
        text = payload_text
        source = "raw"

    # §5.1's dedup, on the RESOLVED text, at the point of synthesis. Not a
    # `stop_hook_active` check. A Stop block ladder can fire the hook nine
    # times; text that does not change is spoken at most once. It needs no
    # locking because `claim()` above keeps exactly one consumer.
    dedup = hashlib.sha256(text.strip().encode("utf-8")).hexdigest()
    spoken_path = os.path.join(speak_dir, "spoken")
    prev = read_file(spoken_path)
    if prev and prev.strip() == dedup:
        dbg(buf_root, "already spoken -> silent")
        return 0

    # The settled sanitizer, then split. Order is normative (§4).
    sys.path.insert(0, root)
    try:
        import speech
    except Exception as exc:                                   # noqa: BLE001
        dbg(buf_root, "cannot import speech/: %r" % (exc,))
        return 0
    try:
        clean = speech.sanitize(text)
    except Exception as exc:                                   # noqa: BLE001
        dbg(buf_root, "sanitizer failed: %r" % (exc,))
        return 0
    sentences = speech.split_sentences(clean)
    if not sentences:
        return 0

    player_bin = shutil.which(player_cmd)
    if not player_bin:
        dbg(buf_root, "no player %r -> silent" % player_cmd)
        return 0

    kroot = os.environ.get("KOKORO_ROOT",
                           os.path.join(os.path.expanduser("~"),
                                        ".local", "share", "kokoro"))
    model = os.path.join(kroot, "kokoro-v1.0.onnx")
    voices = os.path.join(kroot, "voices-v1.0.bin")
    if not (os.path.exists(model) and os.path.exists(voices)):
        dbg(buf_root, "no Kokoro model under %s -> silent" % kroot)
        return 0

    if muted(off):
        return 0
    atomic_write(spoken_path, dedup + "\n")

    # DEFERRED (§10.5): this load is paid per turn instead of once per session,
    # because there is no resident worker. The measured cost is in
    # docs/decisions/speak-cold-path.md, with both endpoints named.
    t0 = time.time()
    try:
        from kokoro_onnx import Kokoro
        import soundfile as sf
        t_import = time.time()
        kok = Kokoro(model, voices)
        t_model = time.time()
    except Exception as exc:                                   # noqa: BLE001
        dbg(buf_root, "kokoro load failed: %r" % (exc,))
        return 0

    wav_dir = os.path.join(speak_dir, "wav")
    try:
        os.makedirs(wav_dir, exist_ok=True)
    except OSError:
        return 0

    state = {"idx": 0, "n": 0, "synth_spent": 0.0, "first_wav": None}

    def synth_next():
        """Next playable wav, or None when the run is over.

        `CLAUDISH_SPEAK_TIMEOUT` bounds CUMULATIVE SYNTHESIS and is checked
        BETWEEN sentences. DEVIATION from §10.7's `providers.sh:146-172`
        TERM -> sleep 2 -> KILL watchdog: there is no separate synthesis
        process to signal in the cold path -- this process IS the synthesiser
        -- and `Kokoro.create()` spends its time inside onnxruntime, where a
        Python signal handler cannot land promptly. Audio already playing is
        never cut by this budget; only further synthesis stops."""
        while state["idx"] < len(sentences):
            i = state["idx"]
            state["idx"] += 1
            sent = sentences[i]
            if muted(off):                    # clause 7: before create()
                dbg(buf_root, "muted before synthesis of sentence %d" % i)
                return None
            if state["synth_spent"] >= synth_budget:
                dbg(buf_root, "synthesis budget %.0fs spent at sentence %d"
                    % (synth_budget, i))
                return None
            s = time.time()
            try:
                samples, sr = kok.create(sent, voice=voice, speed=1.0,
                                         lang="en-us")
            except Exception as exc:          # incl. the 510-phoneme IndexError
                state["synth_spent"] += time.time() - s
                dbg(buf_root, "create() failed on sentence %d: %r" % (i, exc))
                continue
            wav = os.path.join(wav_dir, "s%d.%d.wav" % (os.getpid(), i))
            try:
                sf.write(wav, samples, sr)
            except Exception as exc:                           # noqa: BLE001
                state["synth_spent"] += time.time() - s
                dbg(buf_root, "wav write failed: %r" % (exc,))
                continue
            state["synth_spent"] += time.time() - s
            state["n"] += 1
            if state["first_wav"] is None:
                state["first_wav"] = wav
            return wav
        return None

    def spawn(wav):
        if muted(off):                        # clause 7: before Popen
            return None
        try:
            return subprocess.Popen([player_bin, wav],
                                    stdin=subprocess.DEVNULL,
                                    stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL)
        except OSError as exc:
            dbg(buf_root, "player spawn failed: %r" % (exc,))
            return None

    def stop_playback(proc) -> None:
        """Kill the sound, whatever shape the player turned out to be.

        `proc.terminate()` alone is not enough: `CLAUDISH_PLAYER` may be a
        wrapper script, and terminating the wrapper leaves the real player
        running as its child -- measured, on this repo's own test harness,
        where afplay kept sounding for seconds after the wrapper died.

        The players live in THIS process's group (that is what makes §10.6's
        stand-in a single signal), so signalling the group reaches the wrapper
        and its child alike. It also reaches us -- which is correct: being
        muted means we are done. `_on_term` turns that into a SystemExit so
        `main`'s `finally` still releases the consumer claim.

        Only ever done when we are the group LEADER. If `os.setsid()` failed we
        are still in the hook's group, and signalling that would reach
        processes that are none of our business."""
        if os.getpgrp() == os.getpid():
            try:
                os.killpg(os.getpgrp(), signal.SIGTERM)
                return
            except OSError:
                pass
        try:
            proc.terminate()
        except OSError:
            pass

    def wait_player(proc, wav) -> bool:
        """Wait for a play, polling the mute files. This is what makes
        `touch ~/.claude/claudish-speak-off` stop audio ALREADY IN FLIGHT
        rather than only the next sentence. False means muted."""
        ok = True
        try:
            while proc.poll() is None:
                if muted(off):
                    dbg(buf_root, "muted mid-play -> stopping playback")
                    stop_playback(proc)
                    ok = False
                    break
                time.sleep(PLAY_POLL)
        finally:
            try:
                proc.wait(timeout=5)
            except Exception:                                  # noqa: BLE001
                pass
            try:
                os.unlink(wav)
            except OSError:
                pass
        return ok

    # Play sentence by sentence with synthesis of sentence N+1 overlapped onto
    # playback of N. §4: "first-sentence pipelining: required, not optional" --
    # whole-message TTFA fails the 3 s line 12/12 where sentence one passes
    # 12/12 at a 0.86 s median, and without it r11/r12 exceed the 30 s ceiling
    # and never speak at all.
    pending = synth_next()
    if pending is None:
        return 0
    t_first = time.time()
    dbg(buf_root, "TTFA %.3fs from fork (import %.3f model %.3f synth1 %.3f) "
                  "src=%s sentences=%d"
        % (t_first - t_fork, t_import - t0, t_model - t_import,
           t_first - t_model, source, len(sentences)))

    player = None
    playing = None
    try:
        while pending is not None:
            if player is not None:
                if not wait_player(player, playing):
                    break
                player = None
            if muted(off):
                break
            player = spawn(pending)
            playing = pending
            if player is None:
                break
            pending = synth_next()
        if player is not None:
            wait_player(player, playing)
    finally:
        # Leftovers from an interrupted run; rewrite.sh:117's 30-minute sweep
        # reclaims the directory either way.
        try:
            for name in os.listdir(wav_dir):
                if name.startswith("s%d." % os.getpid()):
                    try:
                        os.unlink(os.path.join(wav_dir, name))
                    except OSError:
                        pass
        except OSError:
            pass
    dbg(buf_root, "done: %d/%d sentences, %.2fs total"
        % (state["n"], len(sentences), time.time() - t_fork))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except SystemExit:
        raise
    except BaseException:                                      # noqa: BLE001
        # Silence is the failure mode. Nothing reaches the screen and nothing
        # reaches the model: the hook exited 0 long ago.
        sys.exit(0)
