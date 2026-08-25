#!/usr/bin/env python3
"""Row 20: instrumented resident worker. A PROBE, not shippable code.

Implements spec section 10.5's worker shape (file-drop job address, mkdir election
with a pid inside, kqueue wake, claim by rename) plus the three preemption hooks of
clause 7, each independently switchable so the mechanism can be falsified as well as
confirmed:

  (i)   --pid-write  on|off   write the player's pid to speak/pid after Popen
  (ii)  --prespawn-recheck on|off   re-stat speak/job after create(), before Popen
  (iii) --claim-kill off|handle|pidfile   kill the current player at job-CLAIM time
                                          `handle`  = the earlier probe's _PREV_PLAYER.kill()
                                          `pidfile` = read speak/pid and kill that

and a settable --prespawn-delay-ms between (ii)'s stat and the Popen, so the
6-38 ms real window can be widened to something a shell script can hit reliably.

Timestamps recorded, named as spec section 13 row 20 names them:
  S  claim  (rename job -> job.taken.<pid>)
  S2 prespawn recheck stat
  P  player Popen
  W  speak/pid write
(R and K -- the hook's rename and its speak/pid read+kill -- are stamped by the hook.)

Kill sites use DISTINCT signals so attribution is exact (Darwin numbering):
  SIGTERM (15) hook-side pid kill          <- sent by hook_probe.sh
  SIGUSR1 (30) worker claim-time kill      <- clause (iii)
  SIGUSR2 (31) newly-elected-worker sweep  <- the proposed repair
The shipped design would use TERM for all three; the substitution changes nothing
about the mechanism, only about what the trace can prove.
"""
import argparse
import os
import select
import signal
import subprocess
import sys
import threading
import time
import uuid

ap = argparse.ArgumentParser()
ap.add_argument("--speak-dir", required=True)
ap.add_argument("--trace", required=True)
ap.add_argument("--player-log", required=True)
ap.add_argument("--claim-kill", choices=["off", "handle", "pidfile"], default="pidfile")
ap.add_argument("--prespawn-recheck", choices=["on", "off"], default="on")
ap.add_argument("--pid-write", choices=["on", "off"], default="on")
ap.add_argument("--prespawn-delay-ms", type=float, default=0.0)
ap.add_argument("--synth-ms", type=float, default=1500.0)
ap.add_argument("--load-ms", type=float, default=900.0)
ap.add_argument("--player-secs", type=float, default=6.0)
ap.add_argument("--real-kokoro", action="store_true")
ap.add_argument("--voice", default="bf_emma")
ap.add_argument("--idle-exit-s", type=float, default=120.0)
ap.add_argument("--reap", choices=["on", "off"], default="on",
                help="off reproduces a worker that never wait()s its player: the pid "
                     "file then points at a ZOMBIE and kill(2) on it SUCCEEDS.")
ap.add_argument("--die-after", choices=["none", "popen", "pid"], default="none",
                help="stage a worker that dies inside the P->W window (popen) or just "
                     "after it (pid). Nothing in the pid-file design covers the first.")
ap.add_argument("--ledger", choices=["on", "off"], default="off",
                help="proposed repair: the PLAYER appends its own pid to speak/players, "
                     "so the record survives the worker.")
ap.add_argument("--sweep-on-election", choices=["on", "off"], default="off",
                help="proposed repair: a newly elected worker kills every still-live pid "
                     "in the ledger (SIGUSR2/31), closing the orphan case.")
ap.add_argument("--real-player", action="store_true",
                help="play the synthesised wav with afplay instead of the stub player. "
                     "Turns `never_started` into `confirmed silent`.")
ap.add_argument("--generation", default="1")
A = ap.parse_args()

D = A.speak_dir
LOCK = os.path.join(D, "worker.lock")
LOCK_PID = os.path.join(LOCK, "pid")
JOB = os.path.join(D, "job")
PIDF = os.path.join(D, "pid")
READY = os.path.join(D, "ready")
LEDGER = os.path.join(D, "players")
HERE = os.path.dirname(os.path.abspath(__file__))
PLAYER = os.path.join(HERE, "player_probe.py")


def rec(kind, **kw):
    fields = " ".join(f"{k}={v}" for k, v in kw.items())
    with open(A.trace, "a") as fh:
        fh.write(f"{time.time():.6f}\tworker\t{os.getpid()}\tgen{A.generation}\t"
                 f"{kind}\t{fields}\n")
        fh.flush()
        os.fsync(fh.fileno())


# ------------------------------------------------------------------ election
# Election protocol here is the CORRECTED one from row 21 -- row 20 is not about
# the election, and using the broken one would let a second worker confound it.
def elect():
    for _ in range(50):
        try:
            os.mkdir(LOCK)
        except FileExistsError:
            pid = -1
            for _i in range(20):
                try:
                    pid = int(open(LOCK_PID).read().strip())
                    break
                except (OSError, ValueError):
                    time.sleep(0.002)
            if pid > 0:
                try:
                    os.kill(pid, 0)
                    rec("election_lost", held_by=pid)
                    return False
                except OSError:
                    pass
            q = f"{LOCK}.dead.{os.getpid()}.{uuid.uuid4().hex[:8]}"
            try:
                os.rename(LOCK, q)
            except OSError:
                continue
            try:
                os.unlink(os.path.join(q, "pid"))
            except OSError:
                pass
            try:
                os.rmdir(q)
            except OSError:
                pass
            continue
        with open(LOCK_PID, "w") as fh:
            fh.write(f"{os.getpid()}\n")
        rec("election_won")
        return True
    return False


os.setsid()
t_exec = time.time()
if not elect():
    sys.exit(0)

# --------------------------------------------- proposed repair: orphan sweep
if A.sweep_on_election == "on":
    try:
        rows = open(LEDGER).read().split("\n")
    except OSError:
        rows = []
    swept = 0
    for row in rows:
        if not row.strip():
            continue
        try:
            opid = int(row.split("\t")[0])
        except ValueError:
            continue
        if opid == os.getpid():
            continue
        try:
            os.kill(opid, signal.SIGUSR2)
            rec("kill_attempt", by="election-sweep", site="ledger", target=opid,
                sig=int(signal.SIGUSR2), result="sent")
            swept += 1
        except OSError:
            pass
    rec("election_sweep", swept=swept, ledger_rows=len([r for r in rows if r.strip()]))
    try:
        open(LEDGER, "w").close()
    except OSError:
        pass

# ------------------------------------------------------------------- load
kok = None
if A.real_kokoro:
    root = os.path.expanduser("~/.local/share/kokoro")
    sys.path.insert(0, os.path.join(root, "venv/lib/python3.11/site-packages"))
    from kokoro_onnx import Kokoro
    kok = Kokoro(os.path.join(root, "kokoro-v1.0.onnx"),
                 os.path.join(root, "voices-v1.0.bin"))
    kok.create("Warming up.", voice=A.voice, speed=1.0, lang="en-gb",
               is_phonemes=False)
else:
    time.sleep(A.load_ms / 1000.0)
rec("ready", after=round(time.time() - t_exec, 4))
with open(READY, "w") as fh:
    fh.write(f"{os.getpid()}\n")

player = None            # in-memory handle: what --claim-kill handle uses
player_pid = None


def reap(proc, jid, t_popen):
    """Attribution comes from the player's EXIT STATUS, read by its parent.

    The player's own log cannot do this job: a kill that lands inside the player's
    own interpreter startup terminates it by the signal's default action before any
    handler is installed, so the log stays empty and "killed at once" is
    indistinguishable from "never started". The returncode is exact:
      -15  SIGTERM   -> hook-side pid kill
      -30  SIGUSR1   -> worker claim-time kill (SIGUSR1 is 30 on Darwin)
        0            -> played to completion; NOTHING killed it
    It also removes the zombie, which matters: kill(2) on an unreaped zombie
    SUCCEEDS, so a worker that does not reap makes the hook-side kill report
    success while killing nothing.
    """
    rc = proc.wait()
    rec("player_exit", job=jid, player_pid=proc.pid, rc=rc,
        killed_by_sig=(-rc if rc < 0 else 0),
        alive_s=round(time.time() - t_popen, 4))


def kill_player(site, sig):
    """One of the two kill sites. Returns what actually happened."""
    target = None
    if site == "handle":
        target = player.pid if player is not None else None
    elif site == "pidfile":
        try:
            target = int(open(PIDF).read().strip())
        except (OSError, ValueError):
            target = None
    if target is None:
        rec("kill_attempt", by="worker-claim", site=site, target="none", result="no_target")
        return
    try:
        os.kill(target, sig)
        rec("kill_attempt", by="worker-claim", site=site, target=target,
            sig=sig, result="sent")
    except ProcessLookupError:
        rec("kill_attempt", by="worker-claim", site=site, target=target,
            sig=sig, result="ESRCH")
    except OSError as e:
        rec("kill_attempt", by="worker-claim", site=site, target=target,
            sig=sig, result=type(e).__name__)


# ------------------------------------------------------------------- kqueue
dfd = os.open(D, os.O_RDONLY)
kq = select.kqueue()
ev = select.kevent(dfd, filter=select.KQ_FILTER_VNODE,
                   flags=select.KQ_EV_ADD | select.KQ_EV_CLEAR,
                   fflags=select.KQ_NOTE_WRITE | select.KQ_NOTE_EXTEND)
kq.control([ev], 0, 0)
last_work = time.time()

while True:
    if time.time() - last_work > A.idle_exit_s:
        rec("idle_exit")
        break
    kq.control(None, 1, 0.25)

    # --- claim: rename(job, job.taken.<pid>) -- the consumer's own atomic step
    taken = f"{JOB}.taken.{os.getpid()}.{uuid.uuid4().hex[:6]}"
    try:
        os.rename(JOB, taken)
    except OSError:
        continue
    t_S = time.time()
    body = open(taken).read()
    os.unlink(taken)
    jid = body.split("\n", 1)[0].strip()
    rec("S_claim", job=jid)
    last_work = time.time()

    # --- clause (iii): kill the current player the moment we claim a newer job
    if A.claim_kill != "off":
        kill_player(A.claim_kill, signal.SIGUSR1)
    else:
        rec("kill_attempt", by="worker-claim", site="off", target="none",
            result="disabled")

    # --- synthesis
    wav = None
    if kok is not None:
        samples, sr = kok.create(body, voice=A.voice, speed=1.0, lang="en-gb",
                                 is_phonemes=False)
        if A.real_player:
            import wave
            import numpy as np
            wav = os.path.join(D, f"out.{jid}.wav")
            with wave.open(wav, "wb") as wf:
                wf.setnchannels(1)
                wf.setsampwidth(2)
                wf.setframerate(sr)
                wf.writeframes((np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes())
    else:
        time.sleep(A.synth_ms / 1000.0)
    rec("synth_done", job=jid, wav=(os.path.basename(wav) if wav else "-"))

    # --- clause (ii): re-stat speak/job after create(), before Popen
    if A.prespawn_recheck == "on":
        newer = os.path.exists(JOB)
        rec("S2_prespawn_stat", job=jid, newer_waiting=int(newer))
        if newer:
            rec("discarded", job=jid, by="prespawn_recheck")
            continue
    else:
        rec("S2_prespawn_stat", job=jid, newer_waiting="skipped")

    # --- the widened window
    if A.prespawn_delay_ms:
        time.sleep(A.prespawn_delay_ms / 1000.0)

    # --- P: spawn the player
    t_popen = time.time()
    if A.real_player and wav:
        # a real player, so "was it audible" is answered by ear and not by proxy
        argv = ["/usr/bin/afplay", wav]
    else:
        argv = [sys.executable, PLAYER, str(A.player_secs), A.player_log, jid]
        if A.ledger == "on":
            argv.append(LEDGER)
    player = subprocess.Popen(argv)
    player_pid = player.pid
    rec("P_popen", job=jid, player_pid=player_pid)
    if A.reap == "on":
        threading.Thread(target=reap, args=(player, jid, t_popen), daemon=True).start()
    if A.die_after == "popen":
        rec("worker_die", where="between_P_and_W")
        os._exit(9)

    # --- W: write speak/pid  (clause (i))
    if A.pid_write == "on":
        with open(PIDF, "w") as fh:
            fh.write(f"{player_pid}\n")
        rec("W_pid_write", job=jid, player_pid=player_pid)
    else:
        rec("W_pid_write", job=jid, player_pid=player_pid, result="disabled")
    if A.die_after == "pid":
        rec("worker_die", where="after_W")
        os._exit(9)
