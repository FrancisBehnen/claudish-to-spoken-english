#!/usr/bin/env python3
"""Row 20: instrumented resident worker. A PROBE, not shippable code.

Implements spec section 10.5's worker shape (file-drop job address, election with the
owner pid recorded, kqueue wake, claim by rename) plus every preemption clause under
test, each independently switchable so a clause can be FALSIFIED as well as confirmed.

Round 1 clauses (spec 10.5 clause 7):
  (i)   --pid-mode worker      the WORKER writes speak/pid after Popen
  (ii)  --prespawn-recheck     re-stat speak/job after create(), before Popen
  (iii) --claim-kill           kill the current player at job-CLAIM time
                               off | handle | pidfile | both

Round 2, added after review of PR #28 found the round-1 repair still racy:
  --pid-mode shared      the PLAYER publishes its own pid to the one shared
                         speak/pid path, before exec. This is what the round-1
                         replacement text actually specified, as opposed to the
                         append-only ledger that C9 measured.
  --pid-mode perplayer   the PLAYER publishes to a UNIQUE path,
                         speak/playerdir/<pid>.<nonce>, and removes only that name.
                         No shared path, so no clobbering and no truncation.
  --publish-delay-ms N   the wrapper sleeps N ms BEFORE publishing. This is what
                         stages "the shell wrapper stays descheduled after Popen
                         returns", so a replacement worker can sweep BEFORE the
                         publication instead of always after it.
  --sweep-mode           what a newly elected worker kills:
                           off      nothing
                           record   whatever the pid record(s) name  (round 1)
                           pgid     the PROCESS GROUP of each superseded owner
                           both     pgid then record
                         pgid is the repair: process-group membership is established
                         by fork(2), before the child runs a single instruction, so
                         it cannot be missed by a sweep that happens to run before
                         the child publishes anything.
  --sweep-gap-ms N       gap between READING the ledger and TRUNCATING it, to stage
                         the concurrent-append loss the review found.
  --reap-delay-ms N      delay inside the reaper before it unlinks the pid record, to
                         stage the read-then-unlink TOCTOU: an older player's reap
                         completing after a newer player has replaced the shared
                         record.
  --unlink-on-reap       whether the reaper unlinks the record at all.

Round 15, added after review found the FOURTH distinct defect in the `.pending` bound:
  --owner-identity on|off
                         the generation record's target is `<pid>.<starttime>` rather
                         than a bare pid, and every use of a recorded owner pid -- the
                         election's liveness test and clause 7(iv)'s killpg -- re-reads
                         the pid's current start time. A MISMATCH means the owner is
                         gone and its pid has been handed to a stranger, so the record
                         authorises nothing and the marker that named its generation is
                         EXPIRED rather than acted on. `off` is the round-14 bare-pid
                         shape, kept as the falsification arm. Same instrument as the
                         spec's §10.5 clause 2, deliberately: the two documents describe
                         one scheme rather than two.
                         ROUND 16: under `on`, a record that carries NO start time --
                         written by an `off` worker or by one predating the option --
                         is UNVERIFIABLE, not verified. Round 15 let it degrade to the
                         pid-existence test, which reopened the whole hazard from the
                         one input the falsification arm produces. The degradation now
                         keys on the OPTION and never on the record's shape.

Round 21, after review found the SAME defect one record over:
  --player-identity on|off
                         the PLAYER record's CONTENT is `<pid>.<starttime>` rather than
                         a bare pid, and every site that signals a pid read from a
                         player record -- the hook (`hook_probe.sh`), the election-time
                         record sweep, and the worker's claim-time kill -- re-reads the
                         pid's current start time and SKIPS IN SILENCE on a mismatch.
                         Round 15 gave the OWNER record an identity and left the player
                         records a bare number. That is not a smaller hole, it is the
                         same hole: a player record outlives its player indefinitely --
                         the committed C12b warm-up record `94309.c8debde7` is still in
                         the sweep's target list on 24 of its 25 elections, ESRCH every
                         time -- so after pid reuse the sweep's `os.kill` and the hook's
                         `SIGTERM` both land on a stranger. The anchored `<pid>.<8-hex>`
                         NAME shape added in round 20 stops a `.pending` marker being
                         parsed as a pid; it does not make the pid an identity, and it
                         was read as though it had.
                         THE NAME SHAPE IS UNCHANGED and the start time rides in the
                         record's CONTENT, because PR #27's §10.5 clause 7(i) specifies
                         it that way and the two documents must describe ONE scheme.
                         `off` is the bare-pid falsification arm, and the degradation
                         keys on the OPTION and never on the record -- round 16's lesson,
                         applied here before it could be learned twice.

Round 26, after review found the site round 21 deliberately SKIPPED:
  --claim-kill handle    the in-memory `Popen` handle was exempted from the identity
                         test because "the pid is reserved until this process reaps it".
                         Reaping is what RELEASES the pid, `reap()` reaped, and nothing
                         cleared the handle -- so 12 of C10b's 24 `via=handle` kills
                         already signalled a released pid, ESRCH, ~2.6 s after that
                         player exited. The premise is now MADE TRUE rather than tested
                         for: `waitid(P_PID, pid, WEXITED|WNOWAIT)` waits for the child
                         without consuming it, the handle is retired and the child reaped
                         under `player_lock`, and `kill_player` holds that same lock
                         across its `os.kill`. So a handle is signalled only while its
                         pid is reserved -- live, or an unreaped zombie. Without
                         `waitid(WNOWAIT)` there is no safe handle kill, so the option
                         REFUSES TO START rather than degrade. See `reap()`.

Timestamps recorded, named as spec 13 row 20 names them:
  S  claim (rename job -> job.taken.<pid>)   S2 prespawn recheck stat
  P  player Popen                            W  pid record published
(R and K -- the hook's rename and its pid read+kill -- are stamped by the hook.)

Kill sites use DISTINCT signals so attribution is exact (Darwin numbering):
  SIGTERM (15) hook-side kill              SIGUSR1 (30) worker claim-time kill
  SIGUSR2 (31) newly-elected-worker sweep by record
  SIGALRM (14) newly-elected-worker sweep by PROCESS GROUP
SIGHUP was used for the pgid sweep at first and had to be abandoned: `nohup` sets it
to SIG_IGN, and that disposition is inherited across fork AND exec, so every worker and
every player silently ignored it and the sweep was a no-op that looked like a design
failure. Hence the startup guard below.
The shipped design would use TERM for all of them; the substitution changes nothing
about the mechanism, only about what the trace can prove.
"""
import argparse
import errno
import os
import re
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
ap.add_argument("--claim-kill", choices=["off", "handle", "pidfile", "both"],
                default="pidfile")
ap.add_argument("--prespawn-recheck", choices=["on", "off"], default="on")
ap.add_argument("--pid-mode", choices=["worker", "shared", "perplayer"],
                default="worker")
ap.add_argument("--pid-write", choices=["on", "off"], default="on",
                help="pid-mode worker only: whether the worker writes the record")
ap.add_argument("--prespawn-delay-ms", type=float, default=0.0)
ap.add_argument("--publish-delay-ms", type=float, default=0.0)
ap.add_argument("--synth-ms", type=float, default=1500.0)
ap.add_argument("--load-ms", type=float, default=900.0)
ap.add_argument("--player-secs", type=float, default=6.0)
ap.add_argument("--real-kokoro", action="store_true")
ap.add_argument("--real-player", action="store_true")
ap.add_argument("--voice", default="bf_emma")
ap.add_argument("--idle-exit-s", type=float, default=120.0)
ap.add_argument("--reap", choices=["on", "off"], default="on")
ap.add_argument("--die-after", choices=["none", "popen", "pid"], default="none")
ap.add_argument("--ledger", choices=["on", "off"], default="off")
ap.add_argument("--sweep-on-election", choices=["on", "off"], default="off",
                help="round-1 name, kept so C9 reruns unchanged; equivalent to "
                     "--sweep-mode record")
ap.add_argument("--sweep-mode", choices=["off", "record", "pgid", "both"],
                default="off")
ap.add_argument("--sweep-gap-ms", type=float, default=0.0)
ap.add_argument("--reap-delay-ms", type=float, default=0.0)
ap.add_argument("--unlink-on-reap", choices=["on", "off"], default="off")
ap.add_argument("--pending-marker", choices=["off", "on"], default="off",
                help="perplayer only. The worker creates playerdir/<gen>.<nonce>.pending "
                     "BEFORE forking, and the wrapper RENAMES it to <pid>.<nonce> as "
                     "its first act. So the existence of a .pending entry is an "
                     "observable 'an unnamed player may exist right now', and the "
                     "process-group sweep is used ONLY then -- which bounds the "
                     "pgid-reuse blast radius to the same narrow window as the orphan "
                     "it exists to catch, instead of killpg-ing on every election.")
ap.add_argument("--player-setsid", choices=["off", "on"], default="off",
                help="spawn the player with start_new_session=True, so it LEAVES the "
                     "worker process group. This is the one line that defeats clause "
                     "7(iv) entirely, and it is the line an implementer is most likely "
                     "to add for unrelated reasons -- so the arm exists to show the "
                     "failure rather than to assert the constraint.")
ap.add_argument("--owner-identity", choices=["off", "on"], default="on",
                help="the generation record's target is `<pid>.<starttime>` rather than "
                     "a bare pid, and every use of a recorded owner pid -- the election's "
                     "liveness test AND clause 7(iv)'s killpg -- re-reads the pid's "
                     "current start time and treats a MISMATCH as 'that owner is gone, "
                     "this record is stale' rather than as authorisation. `off` restores "
                     "the round-14 bare-pid shape, which is the arm this exists to "
                     "falsify: with it, a `.pending` marker whose owner pid has been "
                     "recycled as an unrelated group leader authorises killpg on that "
                     "stranger's group. Under `on` a record with NO start time is "
                     "UNVERIFIABLE and never degrades to the pid test: the sweep "
                     "refuses to signal it and leaves its marker standing, the election "
                     "refuses to supersede it while a process still holds its pid.")
ap.add_argument("--player-identity", choices=["off", "on"], default="on",
                help="the PLAYER record's CONTENT is `<pid>.<starttime>` rather than a "
                     "bare pid, and every site that signals a pid read from a player "
                     "record -- the hook, the election-time record sweep, and the "
                     "worker's claim-time kill -- re-reads that pid's current start "
                     "time and SKIPS IN SILENCE on a mismatch. The record NAME is "
                     "unchanged, `<pid>.<8-hex-nonce>`, matched anchored as before: PR "
                     "#27's clause 7(i) carries the identity in the content and the two "
                     "documents must specify one scheme. `off` is the bare-pid arm this "
                     "exists to falsify. Under `on` a record carrying no start time is "
                     "UNVERIFIABLE and never degrades to the pid-existence test; every "
                     "signaller refuses it.")
ap.add_argument("--generation", default="1")
A = ap.parse_args()

# The ledger is written by the PLAYER, so the player has to know whether it is publishing
# an identity. Set it here, once, so both spawn paths carry it: the worker-mode `Popen`
# inherits os.environ untouched, and the player-published path builds its env from it.
os.environ["PLAYER_IDENTITY"] = A.player_identity

if A.sweep_on_election == "on" and A.sweep_mode == "off":
    A.sweep_mode = "record"

D = A.speak_dir
JOB = os.path.join(D, "job")
PIDF = os.path.join(D, "pid")
READY = os.path.join(D, "ready")
LEDGER = os.path.join(D, "players")          # round-1 append-only ledger
PLAYERDIR = os.path.join(D, "playerdir")     # round-2 per-player records
HERE = os.path.dirname(os.path.abspath(__file__))
PLAYER = os.path.join(HERE, "player_probe.py")
GEN_RE = re.compile(r"^worker\.lock\.(\d+)$")
SIG_SWEEP_REC = signal.SIGUSR2               # 31
SIG_SWEEP_PGID = signal.SIGALRM              # 14


def rec(kind, **kw):
    fields = " ".join(f"{k}={v}" for k, v in kw.items())
    with open(A.trace, "a") as fh:
        fh.write(f"{time.time():.6f}\tworker\t{os.getpid()}\tgen{A.generation}\t"
                 f"{kind}\t{fields}\n")
        fh.flush()
        os.fsync(fh.fileno())


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


PS_PRESENT = "present"     # a process with that pid exists; its start time is returned
PS_ABSENT = "absent"       # CONFIRMED: no process has that pid
PS_ERROR = "error"         # the LOOKUP failed; nothing at all is known about the pid


def ps_starttime(pid):
    """(outcome, starttime) from `ps -o lstart= -p <pid>`. THREE outcomes, not two.

    ROUND 24 -- THIS FUNCTION COLLAPSED "THE PID IS ABSENT" INTO "THE LOOKUP FAILED",
    AND THAT MADE THE IDENTITY GUARD FAIL OPEN ON EXACTLY THE INPUT IT EXISTS FOR.
    Every failure returned None, and every caller read None as `gone`. `gone` is the
    verdict that SIGNALS (the sweeps) and that lets the election SUPERSEDE. So one
    transient `ps` failure -- fork pressure, EINTR, a full process table -- made the
    guard do the two things it was added to prevent: the election supersedes a
    still-live owner (two owners), and the sweeps signal a pid that may already have
    been recycled (a stranger's process, or a stranger's whole process group at
    clause 7(iv)). The guard was least trustworthy precisely when the machine was
    under the pressure that makes pid reuse fastest.

    THE DISCRIMINATOR, measured on this machine (Darwin 25.6, /bin/ps), round 24:
      * present -- rc 0 with a row on stdout.
      * absent  -- rc NONZERO with NOTHING on stdout and NOTHING on stderr. That is
                   the one shape Darwin's `ps` produces for "no process matched":
                   `ps -o lstart= -p 99999` gives rc=1, both streams empty.
      * error   -- everything else. `ps -o lstart= -p 999999999` gives rc=1 with
                   `ps: process id too large` on STDERR; a missing or unexecutable
                   /bin/ps gives rc 127 with a diagnostic; `subprocess.run` itself
                   raises OSError when the fork or the exec fails. rc 0 with an empty
                   stdout is also an error, not an absence: `ps` cannot both succeed
                   and decline to answer, so the reading is that something else did.
    stderr is therefore CAPTURED and not sent to /dev/null. Discarding it is what made
    the diagnostic shapes indistinguishable from the silent one.

    "pid too large" is classified `error` rather than `absent` although such a pid
    certainly names nothing (`kern.maxproc` is 4000 here). That is the fail-closed
    direction and it costs nothing: `safe_pid()` is the domain gate, and a caller that
    treats an out-of-range pid as unverifiable merely refuses to act on a record that
    was corrupt anyway.

    The start time has spaces squeezed to `_` -- the value has to live in a symlink
    target beside the pid, and a reader splits on the FIRST dot. `"_".join(s.split())`
    is byte-identical to the `tr -s " " "_"` the player wrapper and `hook_probe.sh` use,
    and the three are compared as strings, so any disagreement fails closed.

    This is the SAME instrument the spec's §10.5 clause 2 specifies for the owner record
    (`<pid>.<starttime>`), used here for the same reason: a pid is a number, not an
    identity, and every question this probe asks of a recorded pid is really a question
    about the process that wrote it. Its resolution is one second, which is the honest
    limit of the repair and is stated as such in the document.
    """
    try:
        out = subprocess.run(["/bin/ps", "-o", "lstart=", "-p", str(pid)],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError:
        return PS_ERROR, None
    so = out.stdout.decode("utf-8", "replace").strip()
    se = out.stderr.decode("utf-8", "replace").strip()
    if out.returncode == 0:
        s = "_".join(so.split())
        return (PS_PRESENT, s) if s else (PS_ERROR, None)
    if not so and not se:
        return PS_ABSENT, None
    return PS_ERROR, None


def proc_starttime(pid):
    """The start time, or None when this process cannot state one.

    For the two callers that want an identity FOR A RECORD THEY ARE ABOUT TO WRITE, an
    absent pid and a failed lookup mean the same thing -- no identity can be published --
    and both already fail closed (the worker refuses to start, or writes a bare record
    that every reader refuses to signal). They keep the two-valued view. Every caller
    that DECIDES SOMETHING ABOUT A RECORDED PID must use `ps_starttime()` instead, because
    for those the difference between the two is the whole guard.
    """
    outcome, st = ps_starttime(pid)
    return st if outcome == PS_PRESENT else None


# ------------------------------------------------------------------ election
# Row 21's `proposed` protocol: the owner record is a symlink whose target IS the
# owner's identity, so it is never partially initialized, and a dead owner is SUPERSEDED
# by a new generation rather than removed. Using it here is not incidental -- row 20's
# pgid sweep must READ the superseded owner, which a protocol that deletes the record
# cannot provide. The two rows' fixes are coupled.
#
# ROUND 15: that target is `<pid>.<starttime>` and not a bare pid. Both rows need the same
# thing from it and neither can get it from a number -- the election needs to know that the
# process it is calling live is the one that wrote the record, and the sweep needs to know
# that the pgid it is about to signal is still the owner's and not a stranger's. Two fields
# in a symlink target cost nothing: the create is still exclusive and still atomic.
def gen_path(g):
    return os.path.join(D, f"worker.lock.{g}")


def highest_gen():
    hi = None
    try:
        for name in os.listdir(D):
            m = GEN_RE.match(name)
            if m:
                g = int(m.group(1))
                if hi is None or g > hi:
                    hi = g
    except OSError:
        pass
    return hi


superseded = []          # [(gen, owner_pid, owner_starttime)] this worker took over from
MYGEN = None             # the generation THIS worker created; tags its .pending markers

# The owner record's CONTENT. `<pid>.<starttime>` under --owner-identity on, a bare pid
# under off. A symlink's target is an arbitrary string, so carrying two fields instead of
# one changes no primitive and no atomicity argument: it is still one exclusive-create
# and there is still no partially-initialised state to interpret.
MY_STARTTIME = proc_starttime(os.getpid()) if A.owner_identity == "on" else None
if A.owner_identity == "on" and MY_STARTTIME is None:
    # Degrading to a bare pid here is worse than not starting, and ROUND 21 CHANGED THE
    # REASON WITHOUT CHANGING THE RULE. Round 16's reason was that `unverifiable`
    # superseded unconditionally, so a worker that could not state its identity would be
    # superseded while alive and two workers would own the session. The election no longer
    # does that -- it refuses to supersede an unverifiable owner whose pid is still held --
    # so that particular failure is now closed from the other side.
    #
    # The rule stands on what happens LATER. A bare record under `on` is unverifiable
    # forever: when this worker dies, the next contender can only ask whether some process
    # holds the number, and if the pid has been recycled by then it refuses and THE SESSION
    # WEDGES until that stranger exits. An identity record turns the same death into a
    # clean `recycled` or `gone` verdict and a clean succession. So publishing bare under
    # `on` converts a recoverable death into a possibly permanent silence, which is a worse
    # trade than declining to start at all -- and declining is immediate, attributable, and
    # leaves the session exactly as it was.
    # For our OWN pid `PS_ABSENT` is unreachable -- this process is running -- so a None
    # here is always round 24's `PS_ERROR`: the lookup itself failed. The message says
    # `unreadable` and not `gone` for that reason, and the two-valued `proc_starttime()`
    # is the right view at this one site because both outcomes forbid the same act.
    sys.stderr.write("speakd_probe: --owner-identity=on but this process's own start "
                     "time is unreadable; refusing to publish a bare-pid record.\n")
    sys.exit(4)
OWNER_RECORD = (f"{os.getpid()}.{MY_STARTTIME}" if MY_STARTTIME
                else str(os.getpid()))



# A parsed pid is a SIGNAL TARGET, so its DOMAIN is a safety property, not tidiness.
# kill(2)/killpg(2) give 0 and negatives special meaning: 0 is "every process in the
# caller's own process group", -1 is "every process the caller may signal", and any other
# negative is that process group. So a record whose pid field reads `0` turns this rig's
# own sweep into killpg(0, ...) -- it signals the PROBE's process group, or under
# hook_probe.sh the HOOK's, which is the harness's. That is the catastrophic over-reach
# this document already prices for a missing setsid(), reachable through a completely
# different door: one corrupt or truncated record. 1 is init and is never a player.
# Nothing may reach a signal call unless it is an integer strictly greater than 1.
def safe_pid(text):
    """int(text) if it is a plausible signal target, else None."""
    t = text.strip()
    if not t.isdigit():            # rejects "", "-1", "+3", "0x10", " 12"
        return None
    v = int(t)
    return v if v > 1 else None


def read_owner(g):
    """(pid, starttime) of generation g's owner, or None if the record is unreadable.

    Split on the FIRST dot: a Darwin pid is decimal digits only and the start time is
    appended, never prepended. A bare-pid record (--owner-identity off, or a record
    written by an older worker) yields a None start time, which every caller below reads
    as 'this record carries no identity' rather than as 'the identity matched'.

    ROUND 16: that sentence was the INTENT and not the behaviour. `owner_identity()`
    turned a None start time straight back into the pid-existence test, so under `on` a
    bare record did read as 'the identity matched'. It now yields "unverifiable"; see
    there for why the sweep and the election fail safe in opposite directions.
    """
    try:
        target = os.readlink(gen_path(g))
    except OSError:
        return None
    pid, _, st = target.partition(".")
    # The owner pid is used AS A PGID by the superseded-owner sweep, so an owner target of
    # 0 would make that sweep killpg(0, ...) -- this probe's own process group.
    v = safe_pid(pid)
    return None if v is None else (v, st or None)


def owner_identity(pid, st):
    """Five-way: SAME / RECYCLED / GONE / UNVERIFIABLE / LOOKUP_FAILED.

    `kill(pid, 0)` answers 'does some process have this pid', which is the wrong
    question everywhere a pid was READ FROM A RECORD. The cases and what each means for
    the record's authority:

      "same"     -- a process with that pid exists and started when the record says.
                    It IS the owner. Everything the record authorises is legitimate.
      "recycled" -- a process with that pid exists and started at some OTHER time. The
                    owner is gone AND its pid has been handed to a stranger. The record
                    is stale; it authorises nothing. This is the case a bare pid cannot
                    see, and the case in which acting on the record damages a third
                    party -- at clause 7(iv) the damage is a whole process group.
      "gone"     -- no process has that pid, CONFIRMED (see `ps_starttime`: rc nonzero
                    with both streams silent, which is Darwin's one no-match shape).
                    The owner is dead and its pid has not been handed out again, so a
                    pgid derived from it is still reserved to it and any orphan of ours
                    is still inside it. THIS is the case clause 7(iv) exists for, and it
                    is the one that must still signal.
      "unverifiable"
                 -- the option is ON but the RECORD carries no start time (a bare
                    `<pid>` written by an `--owner-identity off` worker, or by a worker
                    that predates the option). There is nothing to compare against, so
                    none of the three verdicts above can be reached honestly. In
                    particular it does NOT mean "dead": a bare record may belong to a
                    live legacy worker, and the election treats it accordingly -- see
                    `elect()`, which refuses to supersede one whose pid is still held.
      "lookup_failed"
                 -- ROUND 24. The record carries a start time and the LIVE side could
                    not be read: `ps` failed, or answered in a shape that is not the
                    confirmed-absence shape. Nothing whatever is known about the pid.
                    This used to be `gone` -- see `ps_starttime` for what that cost --
                    and it is a DIFFERENT FACT from `unverifiable`: a bare record can
                    never be verified, while this one can be, on the next attempt. The
                    two therefore get different policies at the election and the SAME
                    policy at every signaller. Every consumer must handle it explicitly;
                    none may fall through to a signal.

    ROUND 16 -- THE HOLE THE OPTION LEFT IN ITSELF. Round 15 wrote the guard as
    `if A.owner_identity == "off" or st is None`, which made a bare record degrade to
    the pid-existence test SILENTLY, under `on`. That is the exact failure `on` exists
    to prevent, reachable from the exact input the option's own falsification arm
    produces: an `off` worker's record read by an `on` worker. A recycled pid came back
    "same", and at the sweep a pending marker then authorised `killpg` against a
    stranger's whole process group.

    THE TENSION, AND HOW IT IS RESOLVED. `off` is the deliberate falsification arm and
    must keep the round-14 bare-pid behaviour exactly, or the arm stops falsifying
    anything. But `off` and "the record has no start time" are two different facts, and
    round 15 keyed on their disjunction, which let the RECORD decide whether the check
    happened. So THE DEGRADATION KEYS ON THE OPTION AND NEVER ON THE RECORD SHAPE:
    under `off`, every record degrades; under `on`, a record that cannot be verified is
    reported as unverifiable and each caller fails safe for its own site. No record
    shape can turn `on` back into `off`.
    """
    if A.owner_identity == "off":
        # The falsification arm, unchanged: a pid is treated as an identity, which is
        # the defect being demonstrated. `ps` is never consulted on this path, so the
        # round-24 outcome split cannot reach it and `off` stays bit-for-bit round 14.
        return ("same" if alive(pid) else "gone"), None
    if st is None:
        return "unverifiable", None
    outcome, cur = ps_starttime(pid)
    if outcome == PS_ERROR:
        return "lookup_failed", None
    if outcome == PS_ABSENT:
        return "gone", None
    if cur != st:
        return "recycled", cur
    return "same", cur


# ROUND 24. How many times the election re-asks `ps` about an owner whose lookup failed
# before it gives up and loses. A transient failure clears inside one scheduling quantum,
# so a handful of attempts with a short pause between them is the whole of the repair;
# the cap exists so a machine that has stopped being able to fork cannot hold the
# election open indefinitely. The retries share the 60-iteration budget of the loop below
# and so cannot extend it.
LOOKUP_RETRIES = 5
LOOKUP_BACKOFF_S = 0.02

# ROUND 27. THE ATTEMPT BUDGET IS NAMED, AND SO IS ITS EXHAUSTION. §4a used to claim "a
# loser retries; it does not fail", which contradicted this loop: it has always had a
# bound, and falling off the end returned False -- WITH NO TRACE RECORD AT ALL, so the
# one terminal outcome the document said could not happen was also the only one that left
# no evidence. `election_lost` and `election_gave_up` are different facts and now read
# differently: the first is a live owner observed, the second is a budget spent.
#
# WHAT SPENDS THE BUDGET, and why only one of the two gets a backoff:
#   * a COLLISION (`FileExistsError` on either symlink) means somebody else published the
#     generation this attempt wanted. That is progress by another process -- the next
#     `highest_gen()` reads a HIGHER generation -- so retrying immediately is correct, and
#     spending all 60 this way needs 60 successful publications during one election.
#   * an UNREADABLE record makes no progress at all: `highest_gen()` returns the same `g`
#     and `read_owner` fails on it again. Unpaced, this burnt the whole budget in
#     microseconds and gave up, which is a spin dressed as a retry. It gets the backoff,
#     so the budget spans a stated interval (<= 60 * 20 ms = 1.2 s) instead of an
#     unstated one, and the reason is recorded per attempt -- ENOENT (the record was
#     removed between the readdir and the readlink, genuinely transient) is a different
#     fact from a record that is present and does not parse, which no retry will fix.
ELECT_ATTEMPTS = 60
UNREADABLE_BACKOFF_S = 0.02


def elect():
    global MYGEN
    lookup_failures = 0
    collisions = 0
    unreadable = 0
    for _ in range(ELECT_ATTEMPTS):
        g = highest_gen()
        if g is None:
            try:
                os.symlink(OWNER_RECORD, gen_path(0))
                MYGEN = 0
                rec("election_won", gen=0, record=OWNER_RECORD)
                return True
            except FileExistsError:
                collisions += 1
                continue
        own = read_owner(g)
        if own is None:
            unreadable += 1
            rec("owner_record_unreadable", site="election", gen=g,
                why=("absent" if not os.path.lexists(gen_path(g)) else "unparseable"),
                attempt=unreadable)
            time.sleep(UNREADABLE_BACKOFF_S)
            continue
        owner, owner_st = own
        verdict, live_st = owner_identity(owner, owner_st)
        if verdict == "lookup_failed":
            # ROUND 24. THE RECORD IS VERIFIABLE AND THE LOOKUP FAILED. That is a
            # different fact from `unverifiable` below, and it gets a different policy,
            # deliberately rather than by reusing the bare-record rule.
            #
            # WHY NOT REUSE `kill(pid, 0)` HERE. The bare-record rule is vacant ->
            # supersede, held -> refuse, and it is the right rule THERE because a bare
            # record can never be verified: no retry will ever produce better evidence,
            # so the election has to make a terminal decision on the weakest evidence
            # that exists. None of that is true of a failed lookup. The record carries a
            # start time; the comparison is available in principle and was merely
            # unavailable at this instant. So the response the bare-record case cannot
            # have is the correct one here: ASK AGAIN, then refuse.
            #
            # And falling back to `kill(pid, 0)` would be actively wrong, not merely
            # unnecessary, for three reasons:
            #   (1) it re-admits pid existence as an election input under
            #       `--owner-identity on`. That is the round-14 behaviour the option
            #       exists to abolish, re-entering through a path nothing exercises --
            #       structurally the same hole round 16 found, where the RECORD's shape
            #       decided whether the check happened. Here a TRANSIENT FAILURE would
            #       decide it, which is worse: it is not even visible in the record.
            #   (2) the trigger correlates with the hazard. `ps` fails under fork
            #       pressure and a full process table, which is exactly when pids are
            #       being allocated and recycled fastest -- the worst moment to decide
            #       an identity by pid existence.
            #   (3) its failure mode is silent. `vacant -> supersede` on a failed lookup
            #       is indistinguishable in the trace from `vacant -> supersede` on a
            #       confirmed-dead owner, so a machine that had started failing `ps`
            #       would quietly revert to round-14 semantics with nothing to see.
            #
            # WHAT REFUSING COSTS, STATED. `elect()` returning False exits this worker
            # (sys.exit(0)), so a persistent failure means the worker does not start.
            # That is a LIVENESS failure of one worker invocation, and it is bounded:
            # the retry budget absorbs the transient case in tens of ms; a machine that
            # genuinely cannot fork `ps` could not have forked a player either, so the
            # worker had nothing to offer; and every attempt is recorded, so the refusal
            # is attributable rather than a worker that silently declined to run. It is
            # the same trade this document takes everywhere else: silence over two
            # owners.
            lookup_failures += 1
            if lookup_failures < LOOKUP_RETRIES:
                rec("owner_lookup_failed", site="election", gen=g, pid=owner,
                    attempt=lookup_failures, action="retry")
                time.sleep(LOOKUP_BACKOFF_S)
                continue
            rec("owner_lookup_failed", site="election", gen=g, pid=owner,
                attempt=lookup_failures, action="refused_lookup_unavailable")
            rec("election_lost", held_by=owner, gen=g,
                reason="owner_lookup_failed")
            return False
        if verdict == "recycled":
            # A dead owner whose pid a stranger now holds used to read as LIVE here, so
            # every candidate lost the election to a process that was never the owner and
            # jobs sat unconsumed. Same defect as the sweep's, one clause earlier.
            rec("owner_pid_recycled", site="election", gen=g, pid=owner,
                recorded=owner_st, live=live_st)
        if verdict == "unverifiable":
            # A bare record under --owner-identity on: a MIGRATION record, written by an
            # `off` worker or by one predating the option.
            #
            # ROUND 21 REPLACES ROUND 16'S REASONING HERE, WHICH WAS WRONG IN ITS PREMISE
            # RATHER THAN ITS CONCLUSION. Round 16 argued: supersede freely, because "the
            # only destructive consequence of superseding is the pgid sweep, and the
            # sweep refuses this verdict on its own". That premise is false. Superseding
            # is not merely a licence to signal -- IT IS THE LICENCE TO CONSUME JOBS.
            # A bare record may belong to a LIVE LEGACY WORKER, and there is no evidence
            # in the record that says otherwise. Supersede that worker and it keeps
            # claiming jobs from `speak/job` and keeps spawning players, while this worker
            # does the same at `gen+1`: TWO OWNERS, overlapping audio, which is the single
            # invariant the whole protocol exists to hold. The sweep refusing to `killpg`
            # does not help; it is a different act with a different victim.
            #
            # AND SUPERSEDING CANNOT BE MADE INTO A DRAIN, which is the repair one reaches
            # for first. Nothing in this protocol observes being superseded: `MYGEN` is
            # assigned once, here, and `highest_gen()` is called from nowhere but `elect()`
            # -- a worker that has won never looks at the lock again. So creating `gen+1`
            # tells the incumbent nothing, and no notice can be added that reaches it,
            # because a LEGACY worker is by definition one that predates whatever notice
            # we would add. Announce-and-drain is unavailable in principle here, not
            # merely unimplemented.
            #
            # SO THE POLICY IS DECIDED ON THE RECORD'S OWN EVIDENCE, AND IT SPLITS. The
            # record cannot tell a live legacy owner from a recycled pid -- but `kill(pid,
            # 0)` can tell BOTH of those from a pid that names nothing at all, and a live
            # legacy owner necessarily holds its pid:
            #   * PID VACANT -- no process has that pid, so there is no live legacy worker
            #     to double up with, whatever wrote the record. Superseding cannot produce
            #     two owners. SUPERSEDE. This is the case round 16's liveness argument was
            #     actually about, and it is the common one: the ordinary reason a stale
            #     bare record is lying around is that its worker died.
            #   * PID HELD -- either the legacy owner is still running, or its pid has been
            #     recycled by a stranger. Indistinguishable, and the two demand opposite
            #     actions. REFUSE: lose the election and consume nothing.
            #
            # WHAT REFUSING COSTS, STATED PLAINLY. If the pid was in fact recycled, this
            # session WEDGES -- no worker ever wins, no job is ever claimed, and nothing is
            # ever spoken -- for as long as some unrelated process holds that number. That
            # is a real cost and it is chosen, not overlooked. Three things bound it:
            #   (1) it is a LIVENESS failure, and silence is the failure mode this document
            #       accepts everywhere else; two owners is a SAFETY failure, and audible.
            #   (2) it is confined to ONE SESSION. These records live under
            #       `$BUF_ROOT/<session_id>/speak/`, so a wedged session cannot wedge the
            #       next one, and the operator clears it by removing that directory.
            #   (3) it is LOUD: every election records the refusal, by pid, so the wedge is
            #       diagnosable rather than a session that mysteriously stopped talking.
            #
            # AND MIXED MODE IS OUT OF CONTRACT. A bare-record worker and an identity-record
            # worker must not share a session; the supported upgrade is a DRAINED one --
            # stop the old worker, or let the session end, then start the new one. This
            # branch is what makes the unsupported case fail visibly and safely instead of
            # quietly running two owners, and it is not a licence to run mixed.
            if alive(owner):
                rec("owner_record_unverifiable", site="election", gen=g, pid=owner,
                    action="refused_pid_held")
                rec("election_lost", held_by=owner, gen=g,
                    reason="unverifiable_record_pid_held")
                return False
            rec("owner_record_unverifiable", site="election", gen=g, pid=owner,
                action="superseded_pid_vacant")
        if verdict == "same":
            rec("election_lost", held_by=owner, gen=g)
            return False
        try:
            os.symlink(OWNER_RECORD, gen_path(g + 1))
        except FileExistsError:
            collisions += 1
            continue
        for gg in range(g, -1, -1):
            prev = read_owner(gg)
            if prev is None:
                continue
            superseded.append((gg, prev[0], prev[1]))
        MYGEN = g + 1
        rec("election_won", gen=g + 1, superseded=g, prev_owner=owner,
            record=OWNER_RECORD)
        return True
    # THE BUDGET IS SPENT AND NO OWNER WAS OBSERVED. This worker does not start
    # (`sys.exit(0)` below), which is a liveness failure of ONE worker invocation and not
    # of the session -- the next hook re-enters ensure-worker and elects again. Recorded
    # with the breakdown, because "60 collisions" and "60 unreadable reads" call for
    # opposite operator actions and the bare `return False` this replaces could say
    # neither. §4a states the policy and prices it.
    rec("election_gave_up", attempts=ELECT_ATTEMPTS, collisions=collisions,
        unreadable=unreadable, lookup_failures=lookup_failures)
    return False


# GUARD. A sweep signal whose disposition is SIG_IGN makes the sweep a silent no-op --
# which is exactly how the first round-2 sweep produced a false negative under `nohup`.
# Record the dispositions, and refuse to run if a signal the probe depends on is ignored.
_dispo = {}
for _n, _s in (("SIGTERM", signal.SIGTERM), ("SIGUSR1", signal.SIGUSR1),
               ("SIGUSR2", SIG_SWEEP_REC), ("SWEEP_PGID", SIG_SWEEP_PGID)):
    _h = signal.getsignal(_s)
    _dispo[_n] = ("SIG_IGN" if _h is signal.SIG_IGN
                  else "SIG_DFL" if _h is signal.SIG_DFL else "handler")

os.setsid()          # so this worker's pid IS its pgid, and its players inherit it
t_exec = time.time()
rec("signal_dispositions", **_dispo)
if _dispo["SWEEP_PGID"] == "SIG_IGN" or _dispo["SIGUSR2"] == "SIG_IGN":
    rec("FATAL", why="a sweep signal is SIG_IGN; the sweep would be a silent no-op")
    sys.exit(3)

# ROUND 26. The handle kill's safety rests on `waitid(WNOWAIT)` holding the child's pid
# reserved while the handle is retired -- see `reap()`. Without that primitive there is
# no safe handle kill at all, so the arm REFUSES TO RUN rather than degrading to the
# round-25 behaviour under an option that now claims to be guarded. Checked HERE, beside
# the other startup fatal and before the election, so the refusal costs no model load and
# leaves no elected owner behind. `waitid` is present on this Darwin/Python
# [measured-here]; the branch exists because a silent degradation is how the identity
# check shipped broken in round 15.
HANDLE_RESERVE = all(hasattr(os, n) for n in ("waitid", "P_PID", "WEXITED", "WNOWAIT"))
if A.claim_kill in ("handle", "both") and not HANDLE_RESERVE:
    rec("FATAL", why="claim_kill names the handle but waitid(WNOWAIT) is absent, so a "
                     "reaped pid cannot be retired before the kernel can recycle it")
    sys.stderr.write("speakd_probe: --claim-kill %s needs os.waitid(WNOWAIT) to hold the "
                     "pid reserved while the handle is retired; refusing to run.\n"
                     % A.claim_kill)
    sys.exit(5)

if not elect():
    sys.exit(0)


# ------------------------------------------------- newly-elected-worker sweep
def sweep_pgid():
    """Kill the PROCESS GROUP of each superseded owner.

    This is the round-2 repair. A player joins the worker's process group at fork(2)
    -- before it executes one instruction -- so this reaches a player that has
    published nothing and may not even have been scheduled yet. No record, no
    handshake, and no assumption about when the child gets to run.
    """
    # `marked_gens is None` means the marker discipline is off altogether: that arm is
    # unbounded by design and every superseded generation is signalled.
    marked_gens = None
    pend_by_gen = {}
    if A.pending_marker == "on":
        pend = []
        try:
            pend = [x for x in os.listdir(PLAYERDIR) if x.endswith(".pending")]
        except OSError:
            pass
        if not pend:
            # every player that exists is NAMED, so the record sweep can reach all of
            # them and there is no reason to signal a whole process group
            rec("election_sweep_pgid", skipped="no_pending_marker", groups=0)
            return
        rec("pending_found", n=len(pend), names=",".join(sorted(pend)))
        # A marker left over in the pre-round-10 UNTAGGED shape (`<nonce>.pending`) keys
        # to its nonce, which matches no generation, so it authorises nothing and is
        # never retired here. That is the right reading -- an untagged marker cannot say
        # whose it is -- but it is also visible in the trace as a `pending_found` that
        # never shrinks, rather than as a silent behaviour change.
        for name in pend:
            pend_by_gen.setdefault(name.split(".")[0], []).append(name)
        marked_gens = set(pend_by_gen)

    # ONE MARKER MUST NOT AUTHORISE EVERY HISTORICAL GENERATION. Round 10 tagged the
    # marker with its generation, which made ownership readable, but the loop below
    # still walked the whole `superseded` list the moment ANY `.pending` existed. One
    # marker left by gen12 therefore licensed `killpg` against gen1..gen11 as well --
    # process-group ids the kernel is free to have recycled by then, belonging to
    # generations that may never have had an unnamed player at all. That is precisely
    # the blast-radius bound the marker exists to provide, spent. A player that
    # published is reachable through the record sweep already (clause 7(iv-a)), so
    # narrowing the group sweep to marked generations removes no coverage.
    # A MARKER TAGS A GENERATION; IT DOES NOT IDENTIFY THAT GENERATION'S OWNER. This is
    # the fourth distinct defect in the `.pending` bound and it is the one the generation
    # tag cannot reach. Round 14 stopped one marker authorising OTHER generations. It did
    # nothing about the marker's authority over its OWN: `superseded` carries a pid the
    # record wrote at some earlier time, the whole process group can have exited before
    # any replacement election, the marker has no expiry and sits on disk until an
    # election retires it -- and by that election the kernel may have handed that pid to
    # an unrelated group leader. `killpg` on it then signals a stranger's whole group,
    # which is worse than the failure clause 7(iv) exists to fix.
    #
    # So the marker is a NECESSARY condition and never a sufficient one. Before signalling
    # a marked generation, re-read the recorded owner's start time and take the verdict:
    # signal on "same" and on CONFIRMED "gone", SKIP on "recycled", on "unverifiable" and
    # (round 24) on "lookup_failed". The recycled case also EXPIRES the marker -- the owner
    # is provably gone, so the marker can never become actionable again, and leaving it
    # standing is exactly what keeps the gate open on every later election. The other two
    # skips prove nothing about the owner and so must NOT expire anything.
    n = 0
    swept = set()
    expired = set()
    for g, p, st in superseded:
        if p == os.getpid():
            continue
        if marked_gens is not None and str(g) not in marked_gens:
            rec("kill_skipped", by="election-sweep", site="pgid", target=p, gen=g,
                reason="no_pending_marker_for_this_gen")
            continue
        verdict, live_st = owner_identity(p, st)
        if verdict == "recycled":
            rec("kill_skipped", by="election-sweep", site="pgid", target=p, gen=g,
                reason="owner_pid_recycled", recorded=st, live=live_st)
            expired.add(str(g))
            continue
        if verdict == "lookup_failed":
            # ROUND 24. The record HAS an identity and `ps` could not be asked. The sweep
            # takes the same action as for `unverifiable` and for the same reason -- the
            # target is unverified and the blast radius is a whole process group -- but it
            # is recorded under its own reason, because the two facts differ in what an
            # operator should do about them. `owner_record_has_no_identity` means drain
            # the bare-record generations; this means the machine could not answer, and it
            # is expected to clear on the next election with no intervention at all.
            #
            # NOT EXPIRED, for the same reason `unverifiable` is not: expiry asserts the
            # owner is PROVABLY gone, and here nothing whatever is known. Expiring on a
            # failed lookup would discard the only record that an unswept generation
            # exists, on the strength of a `ps` that did not run.
            #
            # No retry loop here, unlike the election. The sweep has no decision to hold
            # open: refusing costs one deferred `killpg` against a generation whose marker
            # survives, and the next election re-reads it. The election refuses to START,
            # which is why it is worth spending a few attempts there and not here.
            rec("kill_skipped", by="election-sweep", site="pgid", target=p, gen=g,
                reason="owner_lookup_failed", recorded=(st or "-"))
            continue
        if verdict == "unverifiable":
            # A record with no start time under --owner-identity on. `killpg` here would
            # be the whole hazard the option was added to close, decided by a coin: the
            # pid is either still the owner's or already a stranger's group leader, and
            # a bare record cannot tell those apart. REFUSE TO SIGNAL. This is one of the
            # two verdicts that neither signal nor expire (round 24 added the other,
            # `lookup_failed`, just above):
            #   * not signalled, because the target is unverified and the blast radius
            #     is a whole process group that may not be ours;
            #   * NOT EXPIRED, because expiry means "the owner is PROVABLY gone, so this
            #     marker can never become actionable again", which is true of "recycled"
            #     and is exactly what is not known here. Retiring it would throw away
            #     the only record that an unswept generation exists.
            # The marker therefore survives, this generation stays out of `swept`, and
            # every later election re-reads and re-refuses it -- a bounded, visible leak
            # of one marker rather than an unbounded signal at a stranger. It is loud in
            # the trace on purpose: a `pending_found` that never shrinks alongside these
            # lines is the operator's signal to drain the bare-record generations.
            rec("kill_skipped", by="election-sweep", site="pgid", target=p, gen=g,
                reason="owner_record_has_no_identity", recorded="-")
            continue
        try:
            os.killpg(p, SIG_SWEEP_PGID)
            rec("kill_attempt", by="election-sweep", site="pgid", target=p,
                sig=int(SIG_SWEEP_PGID), gen=g, result="sent")
            swept.add(str(g))
            n += 1
        except ProcessLookupError:
            # No such group. A player lives in that group from fork(2) onward, so if
            # the group is gone the thing the marker guarded is gone: count the
            # generation swept and let its marker be retired below.
            rec("kill_attempt", by="election-sweep", site="pgid", target=p,
                sig=int(SIG_SWEEP_PGID), gen=g, result="ESRCH")
            swept.add(str(g))
        except OSError as e:
            # Anything else (EPERM) means the group was NOT reached. Leave the marker
            # standing so the next election tries again.
            rec("kill_attempt", by="election-sweep", site="pgid", target=p,
                gen=g, result=type(e).__name__)
    rec("election_sweep_pgid", groups=n, superseded=len(superseded),
        expired=len(expired))

    # SIGNAL FIRST, THEN RETIRE THE MARKER: each marker goes only after its OWN
    # generation's group has been swept, and still before this worker forks any player
    # of its own (the sweep runs before the model load, well ahead of the first fork).
    #
    # Round 10 unlinked before the killpg loop, which re-opened the region the marker
    # exists to close. A worker that dies after the unlink and before signalling leaves
    # the unnamed player alive; the NEXT election finds no marker, takes the
    # `no_pending_marker` early return above, and cannot reach that player by record
    # either, because it never published one -- C12c reconstructed out of the cleanup.
    # Unlinking after the signal makes that crash window fail safe: the marker survives,
    # the next election sweeps the group again, and a redundant killpg on a group that
    # is already gone is an ESRCH.
    #
    # WHY THE CLEANUP IS NEEDED AT ALL, from the committed C16a trace: the wrapper
    # renames its marker away as its FIRST act, so a killpg that WORKS kills the wrapper
    # before that act and strands the marker that authorised it. Every successful sweep
    # leaked one. 25 markers created, 0 removed, pending_found climbing 1 -> 12 across
    # twelve generations, and 33f62e9b.pending surviving from gen1 to gen12r. So 23 of
    # 25 elections ran killpg although only 12 orphan windows were ever staged: the
    # marker did not bound the window, it accumulated.
    for g in sorted(swept):
        for name in pend_by_gen.get(g, []):
            try:
                os.unlink(os.path.join(PLAYERDIR, name))
                rec("pending_reaped", name=name, gen=g)
            except OSError as e:
                rec("pending_reap_failed", name=name, err=type(e).__name__)

    # EXPIRY, which is a different rule from reaping and must be visible as one. A marker
    # is reaped because its generation's group WAS swept; it is expired because its
    # generation's group can never be swept again -- the recorded owner pid now names a
    # stranger, so the record is stale for good. Without expiry the skip above would fix
    # the blast radius and leave the accumulation, and an election that skips every
    # marked generation would leave every marker standing forever: `pending_found` would
    # keep climbing exactly as C16a measured it climbing, and the cheap
    # `no_pending_marker` early return would never be taken again.
    #
    # THE SAFETY ARGUMENT IS THE ONE KERNEL PROPERTY EXPIRY RESTS ON: a pid is not
    # reallocated while it is still in use as a process-group id. If it holds, "the pid
    # was recycled" and "our group still has members" are mutually exclusive, so an
    # expired marker cannot be hiding a live orphan. [inferred] -- read off BSD allocator
    # behaviour, not measured here, and the document says so.
    for g in sorted(expired):
        for name in pend_by_gen.get(g, []):
            try:
                os.unlink(os.path.join(PLAYERDIR, name))
                rec("pending_expired", name=name, gen=g, reason="owner_pid_recycled")
            except OSError as e:
                rec("pending_expire_failed", name=name, err=type(e).__name__)


# A per-player record is EXACTLY `<pid>.<8-hex-nonce>`. Matching the shape rather than
# splitting on the first dot is not pedantry: `<nonce>.pending` also splits to something
# int()-able whenever the 8-hex nonce happens to be all decimal (~2.3% of nonces), and
# the record sweep then signals a pid nobody ever published. It happened once in the
# committed set -- C17's `02679968.pending` was targeted twice as pid 2679968, ESRCH
# both times. Harmless there; not harmless once that number names a live process.
RECORD_RE = re.compile(r"^(\d+)\.[0-9a-f]{8}$")


def split_record(field):
    """`<pid>` or `<pid>.<starttime>` -> (pid, starttime|None); None on garbage.

    Split on the FIRST dot, exactly as `read_owner()` does, and for the same reason: a
    Darwin pid is decimal digits only and the start time is appended, never prepended.
    """
    pid, _, st = field.strip().partition(".")
    v = safe_pid(pid)
    return None if v is None else (v, st or None)



def read_player_records():
    """Every pid currently published: (pid, path, recorded_starttime).

    ROUND 21 -- THE THIRD FIELD, AND WHY THE NAME DOES NOT CARRY IT. A player record's
    name is `<pid>.<nonce>` and the nonce is not an identity, so the pid in the NAME is a
    number that outlives the process that published it. The identity is the record's
    CONTENT, `<pid>.<starttime>`, written by whoever publishes the record and re-read by
    every signaller. This matches PR #27 clause 7(i) deliberately -- it specifies the
    same content and the same anchored name -- so the two documents describe one scheme.

    THE NAME'S PID AND THE CONTENT'S PID MUST AGREE. They are written by the same act,
    so a disagreement is a corrupt or half-written record, and a signaller that trusted
    the name while reading somebody else's start time would verify one process and signal
    another. A mismatch yields no start time, which every caller reads as unverifiable
    and refuses. Under `--player-identity off` the content is a bare pid and this reduces
    to the round-20 behaviour exactly, which is what the falsification arm needs.
    """
    out = []
    if A.pid_mode == "perplayer":
        try:
            names = os.listdir(PLAYERDIR)
        except OSError:
            return out
        for name in names:
            m = RECORD_RE.match(name)
            if not m:
                continue
            path = os.path.join(PLAYERDIR, name)
            # THE DOMAIN RULE APPLIES TO THE FILENAME TOO, and it did not. Round 22 put
            # safe_pid() on the record CONTENT parsers and left this path on a bare int()
            # -- and RECORD_RE matches `0.abcdef01`, so a corrupt per-player name reached
            # alive(0) and os.kill(0, sig): the worker's OWN process group. Identity mode
            # does not rescue it either, because `ps -p 0` fails and that is classified
            # `gone`, which is then signalled. The domain is a safety property and cannot
            # depend on an option.
            named_pid = safe_pid(m.group(1))
            if named_pid is None:
                rec("record_skipped", by="reader", site="perplayer",
                    target=m.group(1), verdict="unsafe_pid")
                continue
            st = None
            if A.player_identity == "on":
                try:
                    body = split_record(open(path).read())
                except OSError:
                    # The record went away between the listdir and the open. It names
                    # nothing now; dropping the row is the same outcome as never having
                    # seen it, and is safe because the player it named cannot be reached
                    # through a record that no longer exists.
                    continue
                if body is not None and body[0] == named_pid:
                    st = body[1]
            out.append((named_pid, path, st))
        return out
    if A.ledger == "on":
        try:
            for row in open(LEDGER):
                if row.strip():
                    body = split_record(row.split("\t")[0])
                    if body is not None:
                        out.append((body[0], LEDGER,
                                    body[1] if A.player_identity == "on" else None))
        except OSError:
            pass
        return out
    try:
        body = split_record(open(PIDF).read())
    except OSError:
        body = None
    if body is not None:
        out.append((body[0], PIDF,
                    body[1] if A.player_identity == "on" else None))
    return out


def player_identity(pid, st):
    """SAME / RECYCLED / GONE / UNVERIFIABLE / LOOKUP_FAILED for a pid from a PLAYER record.

    The same five-way as `owner_identity()`, over a different record, and it is a
    SEPARATE function on purpose: round 20's review found that the owner's start time had
    been credited against a player's pid, and one function serving both records is how
    that gets done again. The owner record says nothing whatever about a player process.

    THE DEGRADATION KEYS ON THE OPTION AND NEVER ON THE RECORD SHAPE -- round 16's
    finding, applied here before it could be rediscovered. Under `off` every record
    degrades to the pid-existence test, which is the arm being falsified; under `on` a
    record that cannot be verified is `unverifiable` and every signaller refuses it. No
    record shape can turn `on` back into `off`.

    Unlike the owner's, ALL THREE of this verdict's consumers are `kill(pid, sig)` at a
    single process -- never `killpg` -- so there is no site here that fails safe in the
    other direction. All three refuse `recycled`, `unverifiable` and `lookup_failed`, and
    all three signal `same`.

    ROUND 24 ADDED `lookup_failed`, AND IT IS NOT A REFINEMENT OF `gone`. Before it, every
    `ps` failure returned None and every caller read None as `gone` -- the one verdict here
    that still signals. So a transient `ps` failure, which is likeliest exactly when the
    machine is churning pids, turned each of the three signallers into a bare-pid
    signaller: the very behaviour `--player-identity on` exists to abolish, reached without
    the option being off. There is no site on the player side that needs the permissive
    reading, so all three refuse, and `gone` keeps its meaning -- CONFIRMED absence, and
    nothing else.

    `GONE` STILL ATTEMPTS THE KILL, and that is a deliberate match to PR #27 rather than
    an oversight. Clause 7(i) says every signaller "skips in silence on a MISMATCH"; a
    vacant pid is not a mismatch. The attempt raises ESRCH and is recorded as ESRCH,
    which is exactly what a bare-pid signaller did, so no arm's accounting moves and
    `collect.sh`'s sweep columns keep their meaning. The residual is a race -- `ps` says
    vacant, the pid is reused, the `kill` lands on the stranger -- and it is narrower
    than the hazard being closed here rather than a separate one: closing it needs the
    same pid-allocator property row 20(b) already blocks on, so it is named there and not
    papered over with a skip that would change what four committed arms measured.
    """
    if A.player_identity == "off":
        # The falsification arm, unchanged. `ps` is not consulted, so round 24's outcome
        # split cannot reach this path either.
        return ("same" if alive(pid) else "gone"), None
    if st is None:
        return "unverifiable", None
    outcome, cur = ps_starttime(pid)
    if outcome == PS_ERROR:
        return "lookup_failed", None
    if outcome == PS_ABSENT:
        return "gone", None
    if cur != st:
        return "recycled", cur
    return "same", cur


def sweep_record():
    rows = read_player_records()
    n = 0
    skipped = 0
    for p, _src, st in rows:
        if p == os.getpid():
            continue
        # ROUND 21. This loop used to go from a number parsed out of a FILENAME straight
        # to `os.kill`, with nothing between them. The name is matched anchored, which
        # stops a `.pending` marker being read as a pid, and that was mistaken for making
        # the pid an identity. It does not: nothing removes a player record when its
        # player dies, so the record outlives it for the whole session -- C12b's warm-up
        # record is in this list on 24 of 25 elections -- and the first pid reuse turns
        # this line into a signal at a stranger.
        verdict, live_st = player_identity(p, st)
        if verdict in ("recycled", "unverifiable", "lookup_failed"):
            rec("record_skipped", by="election-sweep", site="record", target=p,
                verdict=verdict, recorded=(st or "-"), live=(live_st or "-"))
            skipped += 1
            continue
        try:
            os.kill(p, SIG_SWEEP_REC)
            rec("kill_attempt", by="election-sweep", site="record", target=p,
                sig=int(SIG_SWEEP_REC), result="sent")
            n += 1
        except OSError:
            rec("kill_attempt", by="election-sweep", site="record", target=p,
                sig=int(SIG_SWEEP_REC), result="ESRCH")
    rec("election_sweep_record", swept=n, rows=len(rows), skipped=skipped,
        pids=(",".join(str(x[0]) for x in rows) or "-"))
    # The round-1 ledger truncation, kept switchable BECAUSE it is the defect:
    # anything appended between the read above and this truncate is erased without
    # ever having been signalled. The perplayer scheme has nothing to truncate.
    if A.ledger == "on":
        if A.sweep_gap_ms:
            time.sleep(A.sweep_gap_ms / 1000.0)
        at_truncate = [str(x[0]) for x in read_player_records()]  # (pid, path, st)
        try:
            open(LEDGER, "w").close()
            rec("ledger_truncated", held_at_truncate=(",".join(at_truncate) or "-"),
                erased=(",".join(sorted(set(at_truncate)
                                        - {str(x[0]) for x in rows})) or "-"))
        except OSError:
            pass


if A.sweep_mode in ("pgid", "both"):
    sweep_pgid()
if A.sweep_mode in ("record", "both"):
    sweep_record()

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
if A.pid_mode == "perplayer":
    os.makedirs(PLAYERDIR, exist_ok=True)
with open(READY, "w") as fh:
    fh.write(f"{os.getpid()}\n")

player = None            # in-memory handle: what --claim-kill handle uses

# ROUND 26: THE HANDLE WAS NEVER A RESERVATION, AND THE COMMITTED TRACE SAYS SO.
# `kill_player` used to exempt the in-memory `Popen` handle from the identity test on
# the grounds that "the pid is reserved until this process reaps it". The premise is
# true; the code did not satisfy it. `reap()` calls `proc.wait()` -- which releases the
# pid -- and NOTHING cleared this global, so the handle went on naming a reaped child
# until the next `Popen` overwrote it. In `C10b_nopid_handle` that is not a corner: of
# its 24 `via=handle` rows, 12 are `result=ESRCH` [trials], one per `jNa` claim, each
# signalling the previous trial's b-player about 2.6 s after its `player_exit`. Only
# the kernel declining to recycle a pid inside those 2.6 s kept `os.kill` off a
# stranger -- which is the hazard the record path is guarded against, in the one path
# that was excused from the guard, and it is the FIFTH pid-reuse site (after the owner
# record, the player record's content, the per-player filename and the hook).
#
# THE REPAIR IS TO MAKE THE PREMISE TRUE RATHER THAN TO TEST FOR ITS FAILURE.
# `os.waitid(P_PID, pid, WEXITED | WNOWAIT)` blocks until the child is waitable and
# LEAVES IT UNREAPED, so its pid is still reserved when it returns. The reaper then
# retires the handle and reaps under `player_lock`; a signaller reads the handle and
# calls `os.kill` under the SAME lock. So at every instant a handle is signalled, the
# child is either live or an unreaped zombie -- reserved either way -- and the exemption
# from the identity test becomes a fact instead of an assertion. Clearing the global
# alone would NOT have been enough: the signaller could read the handle, lose the CPU,
# and kill after the reap. The lock is what removes that window, and it is only
# affordable because `proc.wait()` under it cannot block -- `waitid` has already
# established that the status is there.
#
# The two alternatives were weaker. A per-job generation counter DETECTS a stale handle
# instead of removing it, and leaves the same read/kill window unless it is also locked,
# so it is this repair plus a counter. Re-reading `<pid>.<starttime>` gives the handle
# the record path's guard, but that guard resolves to ONE SECOND (`ps -o lstart=`) where
# this one is exact, and it would put a `ps` fork on the claim path -- inside the very
# window several published figures measure. A real `pidfd` would be better than all
# three and DARWIN HAS NONE: `os.pidfd_open` is absent on this machine [measured-here],
# and kqueue's `EVFILT_PROC` needs the pid it is arming against, so it inherits the
# same race rather than closing it.
#
# [inferred]. No committed trace was produced with this code. TO CLOSE: run
# `C10b_nopid_handle` and `C6_handle` and confirm every `jNa` claim records
# `result=no_target` with a `handle_retired` row before it, and every `jNb` claim still
# records `via=handle ... result=sent` 12/12.
player_lock = threading.Lock()


def reap(proc, jid, t_popen, record):
    """Attribution comes from the player's EXIT STATUS, read by its parent.

    The player's own log cannot do this job: a kill landing inside the player's own
    startup terminates it by the signal's default action before any handler is
    installed, so the log stays empty and "killed at once" is indistinguishable from
    "never started". The returncode is exact:
      -15 hook kill   -30 claim kill   -31 sweep by record   -14 sweep by pgid
        0 played to completion; NOTHING killed it
    Reaping also removes the zombie, which matters: kill(2) on an unreaped zombie
    SUCCEEDS, so a worker that does not reap makes every kill site report success
    while killing nothing.

    ROUND 26 -- REAPING IS ALSO WHAT RELEASES THE PID, so it is where the in-memory
    handle has to be retired, and the retirement has to happen WHILE THE PID IS STILL
    RESERVED. `waitid(WNOWAIT)` waits for the child to become waitable without
    consuming it, so on the far side of that call the child is an unreaped zombie: its
    pid cannot be handed to anyone else, and a concurrent handle kill can only reach a
    process this worker forked. The handle is dropped and the child reaped under
    `player_lock`, which `kill_player` also holds while it signals -- so there is no
    instant at which a signaller can be holding a pid this function has released.
    `proc.wait()` under the lock cannot block, because `waitid` has already established
    that the status is available.
    """
    global player
    reserved = 0
    if HANDLE_RESERVE:
        try:
            os.waitid(os.P_PID, proc.pid, os.WEXITED | os.WNOWAIT)
            reserved = 1
        except OSError:
            # `ChildProcessError` means something already reaped it, so there is no
            # reservation left to lean on; any other `OSError` means the wait itself
            # failed. `reserved` stays 0 and the trace says so.
            pass
    if reserved:
        # THE LOCK MAY ONLY SPAN `proc.wait()` WHEN THE STATUS IS ALREADY THERE. `waitid`
        # returning is exactly that guarantee, so this `wait()` cannot block and cannot
        # hold a claim-time kill behind it.
        with player_lock:
            if player is proc:
                player = None
                rec("handle_retired", job=jid, player_pid=proc.pid, reserved=1)
            rc = proc.wait()
    else:
        # DEGRADED, AND FAIL-CLOSED. Without the reservation the pid may be released the
        # instant this thread reaps, so the handle is retired FIRST -- possibly while the
        # child is still live -- and the reap happens OUTSIDE the lock, because a blocking
        # `wait()` under it would stall every claim-time kill for a whole player. Retiring
        # early can only LOSE a kill, never misdirect one, and losing one is loud: it
        # breaks the handle arm's 12/12 rather than passing quietly. Unreachable on a
        # platform with `waitid(WNOWAIT)`, and the startup guard refuses the handle site
        # on one without it.
        with player_lock:
            if player is proc:
                player = None
                rec("handle_retired", job=jid, player_pid=proc.pid, reserved=0)
        rc = proc.wait()
    rec("player_exit", job=jid, player_pid=proc.pid, rc=rc,
        killed_by_sig=(-rc if rc < 0 else 0),
        alive_s=round(time.time() - t_popen, 4))
    if A.unlink_on_reap == "on" and record:
        # The TOCTOU under test: with one SHARED record, a delay here lets a NEWER
        # player publish first, and this unlink then removes the NEWER player's
        # record. With a per-player name it can only ever remove its own.
        if A.reap_delay_ms:
            time.sleep(A.reap_delay_ms / 1000.0)
        try:
            os.unlink(record)
            rec("record_unlinked", job=jid, player_pid=proc.pid,
                path=os.path.basename(record))
        except OSError as e:
            rec("record_unlink_failed", job=jid,
                err=errno.errorcode.get(e.errno, e.errno))


def signal_one(how, target, sig, site, jid):
    try:
        os.kill(target, sig)
        rec("kill_attempt", by="worker-claim", site=site, via=how,
            target=target, sig=sig, result="sent", job=jid)
    except ProcessLookupError:
        rec("kill_attempt", by="worker-claim", site=site, via=how,
            target=target, sig=sig, result="ESRCH", job=jid)
    except OSError as e:
        rec("kill_attempt", by="worker-claim", site=site, via=how,
            target=target, result=type(e).__name__, job=jid)


def kill_player(site, sig, jid):
    acted = 0
    # THE RECORD SCAN RUNS FIRST, exactly as the round-25 code did. It emits
    # `record_skipped` rows, and reordering it against the handle kill would reorder
    # those rows in the trace and -- under `--unlink-on-reap on` -- change which records
    # the scan can still see, because the handle kill can start the reap that unlinks
    # them. No committed configuration sets `--claim-kill both`, so nothing published
    # would move either way; the order is preserved because a rig whose trace ordering
    # changes for no reason is a rig whose old traces stop being comparable.
    targets = []
    if site in ("pidfile", "both"):
        # ROUND 21. The third signaller of a recorded player pid, and the one the review
        # did not name -- it reads the same records the sweep does, through the same
        # function, and `kill(pid, SIGUSR1)` at a stale pid is the same act. Guarding two
        # of three sites is how a repair ships broken, so it is guarded here too. This is
        # PR #27's clause 7(iii); the sweep is 7(iv-a) and the hook is 10.3 step 6.
        for p, _s, st in read_player_records():
            verdict, live_st = player_identity(p, st)
            if verdict in ("recycled", "unverifiable", "lookup_failed"):
                rec("record_skipped", by="worker-claim", site=site, target=p,
                    verdict=verdict, recorded=(st or "-"), live=(live_st or "-"),
                    job=jid)
                continue
            targets.append(("record", p))
    if site in ("handle", "both"):
        # THE HANDLE IS READ AND SIGNALLED UNDER `player_lock`, AND THAT IS WHAT MAKES
        # IT NEED NO IDENTITY TEST. The old comment here claimed the exemption outright
        # -- "the pid is reserved until this process reaps it, there is no window in
        # which it can name a stranger" -- and the code did not provide it: `reap()`
        # reaped and left this global naming the dead child, which `C10b`'s 12 `ESRCH`
        # rows are the trace of. Holding the lock across the `os.kill` is the window's
        # only closure: without it a signaller can read a live handle, be descheduled,
        # and signal after `reap()` has released the pid. With it, `reap()` cannot reap
        # while this call is in flight, so the target is live or an unreaped zombie --
        # reserved either way, and `kill` on an unreaped zombie succeeds while killing
        # nothing, which is the harmless failure rather than the dangerous one.
        # The handle is signalled BEFORE the records, which is the order the round-25
        # `targets` list produced.
        with player_lock:
            ph = player
            if ph is not None:
                signal_one("handle", ph.pid, sig, site, jid)
                acted += 1
    for how, target in targets:
        signal_one(how, target, sig, site, jid)
        acted += 1
    # `no_target` still means NOTHING WAS SIGNALLED, over both sites together, which is
    # what `C10a`/`C10b` read it as. A retired handle now reaches it where the round-25
    # code recorded a `via=handle ... ESRCH` against a released pid instead.
    if acted == 0:
        rec("kill_attempt", by="worker-claim", site=site, target="none",
            result="no_target", job=jid)


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

    taken = f"{JOB}.taken.{os.getpid()}.{uuid.uuid4().hex[:6]}"
    try:
        os.rename(JOB, taken)
    except OSError:
        continue
    body = open(taken).read()
    os.unlink(taken)
    jid = body.split("\n", 1)[0].strip()
    rec("S_claim", job=jid)
    last_work = time.time()

    if A.claim_kill != "off":
        kill_player(A.claim_kill, signal.SIGUSR1, jid)
    else:
        rec("kill_attempt", by="worker-claim", site="off", target="none",
            result="disabled", job=jid)

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

    if A.prespawn_recheck == "on":
        newer = os.path.exists(JOB)
        rec("S2_prespawn_stat", job=jid, newer_waiting=int(newer))
        if newer:
            rec("discarded", job=jid, by="prespawn_recheck")
            continue
    else:
        rec("S2_prespawn_stat", job=jid, newer_waiting="skipped")

    if A.prespawn_delay_ms:
        time.sleep(A.prespawn_delay_ms / 1000.0)

    # ------------------------------------------------------------------ P
    nonce = uuid.uuid4().hex[:8]
    t_popen = time.time()
    if A.pid_mode == "worker":
        if A.real_player and wav:
            argv = ["/usr/bin/afplay", wav]
        else:
            argv = [sys.executable, PLAYER, str(A.player_secs), A.player_log, jid]
            if A.ledger == "on":
                argv.append(LEDGER)
        player = subprocess.Popen(argv, start_new_session=(A.player_setsid == "on"))
        record = PIDF
    else:
        # The player publishes its OWN identity before it can make a sound, through a
        # wrapper that exec()s -- so the published pid IS the player's pid, and the
        # record exists before any audio can start. --publish-delay-ms stages the
        # wrapper staying descheduled after Popen returns, which is the ordering the
        # round-1 arm could not reach.
        pending = None
        if A.pid_mode == "shared":
            recpath = PIDF
        else:
            recpath = os.path.join(PLAYERDIR, "PIDPLACEHOLDER." + nonce)
            if A.pending_marker == "on":
                # created BEFORE the fork, so it exists whenever an unnamed player can
                # <gen>.<nonce>.pending -- the generation is part of the name because
                # the sweep must be able to clean up EXACTLY the markers it just acted
                # on. An un-tagged marker cannot be attributed to an owner, so the
                # round-4 rule "remove the entries it has just swept" named no
                # determinable set. See the leak this repairs, below.
                pending = os.path.join(PLAYERDIR, f"{MYGEN}.{nonce}.pending")
                open(pending, "w").close()
                rec("pending_created", job=jid, name=os.path.basename(pending))
        inner = [sys.executable, PLAYER, str(A.player_secs), A.player_log, jid]
        if A.ledger == "on":
            inner.append(LEDGER)
        # PUBLICATION IS A PREREQUISITE FOR PLAYBACK, and it was not: the `if ... fi`
        # status was discarded and `exec` ran unconditionally, so a failed write or a
        # failed `mv` produced AUDIBLE playback with neither a published record nor a
        # pending marker. That is the one state no preemption path can reach -- the hook
        # has no record to read, the record sweep has no name to signal, and the pgid
        # sweep has no marker to authorise it -- while the player is making a sound. It
        # is exactly the invariant this document asserts, inverted, inside the rig that
        # measures it. Exit 97 instead of exec'ing, so the reap attributes it rather than
        # reading it as a player that ran to completion.
        # ROUND 21: THE RECORD'S CONTENT IS THE PLAYER'S OWN `<pid>.<starttime>`, obtained
        # here, before the rename that publishes it -- PR #27 clause 7(i), matched field
        # for field so the two documents specify one scheme. The NAME is untouched: it is
        # still `<pid>.<nonce>` and still matched anchored, because the nonce is what
        # makes the path unique and the start time is what makes the pid an identity, and
        # those are two different jobs.
        #
        # `ps -o lstart=` on $$ cannot fail for a live self, but if it somehow returns
        # nothing the wrapper EXITS RATHER THAN PUBLISHING A BARE RECORD -- the same rule,
        # for the same reason, as the worker's refusal to publish a bare owner record
        # under `--owner-identity on`. `on` PROMISES an identity, so a bare record
        # published under it reads as `unverifiable` and every signaller refuses it: the
        # player would be audible and unreachable by all three kill sites, which is the
        # one state this whole document says must not exist. Exit 96 instead, so the reap
        # attributes it rather than reading it as a player that ran to completion.
        #
        # `tr -s " " "_"` then stripping one leading and one trailing `_` is exactly
        # `"_".join(s.split())`, which is what `proc_starttime()` does on the reading
        # side. The two must agree as strings or every comparison fails closed.
        ident = ('st=$(/bin/ps -o lstart= -p $$ | tr -s " " "_"); '
                 'st=${st#_}; st=${st%_}; '
                 '[ -n "$st" ] || exit 96; id="$$.$st"; '
                 if A.player_identity == "on" else 'id="$$"; ')
        sh = ('sleep "$PUBDELAY"; '
              'rp=$(printf %s "$REC" | sed "s/PIDPLACEHOLDER/$$/"); '
              + ident +
              'if [ -n "$PENDING" ]; then printf "%s\\n" "$id" > "$PENDING" && '
              'mv "$PENDING" "$rp" || exit 97; '
              'else printf "%s\\n" "$id" > "$rp.tmp" && mv "$rp.tmp" "$rp" || exit 97; fi; '
              'exec "$@"')
        env = dict(os.environ, REC=recpath, PENDING=(pending or ""),
                   PUBDELAY=str(A.publish_delay_ms / 1000.0))
        player = subprocess.Popen(["/bin/sh", "-c", sh, "_"] + inner, env=env,
                                  start_new_session=(A.player_setsid == "on"))
        record = recpath.replace("PIDPLACEHOLDER", str(player.pid))
    # THE REST OF THIS ITERATION HOLDS ITS OWN REFERENCE, because from here on the
    # reaper thread may retire the global at any instant (round 26). The `publish_refused`
    # path in particular calls `.terminate()` on the child it just spawned, and reading
    # the global there would be an `AttributeError` on a short player. The global exists
    # for `kill_player`, which wants "the CURRENT player or nothing"; this block wants
    # "the child THIS iteration forked", and they are not the same question.
    # The global is assigned outside `player_lock` on purpose: `reap()` retires it only
    # when `player is proc`, so a reaper for the previous child can never clear a handle
    # this line has just installed, in either interleaving.
    proc = player
    rec("P_popen", job=jid, player_pid=proc.pid, pid_mode=A.pid_mode,
        record=os.path.basename(record) if record else "-")
    if A.reap == "on":
        threading.Thread(target=reap, args=(proc, jid, t_popen, record),
                         daemon=True).start()
    if A.die_after == "popen":
        rec("worker_die", where="between_P_and_W")
        os._exit(9)

    # ------------------------------------------------------------------ W
    if A.pid_mode == "worker":
        if A.pid_write == "on":
            # The worker publishes this one, so the worker obtains the identity -- of the
            # CHILD, not of itself. It can legitimately fail to get one, and ROUND 24
            # CORRECTED WHAT THIS COMMENT USED TO SAY ABOUT WHY: it said "only in one
            # case: the child is already gone", which was exactly the conflation the
            # round-24 finding is about. There are TWO cases and the trace now names
            # which one occurred:
            #   PS_ABSENT -- the child is already gone. Nothing is left to signal.
            #   PS_ERROR  -- the lookup failed and the child's state is unknown.
            # The two outcomes must not print the same word: `identity=absent` names a
            # player that is already gone, `lookup_failed` names one we could not identify.
            # An earlier revision of this comment concluded from that distinction that
            # writing a bare record was "fail-safe in BOTH" -- see immediately below for
            # why that was wrong.
            outcome, st = (ps_starttime(proc.pid) if A.player_identity == "on"
                           else (None, None))
            # A BARE RECORD IS NOT FAIL-SAFE HERE, and the comment above used to claim it
            # was. It is fail-safe for the SIGNALLER -- every reader treats a bare record
            # as `unverifiable` and refuses to signal it, so no stranger is killed. It is
            # fail-OPEN for PREEMPTION, which is the property this record exists to
            # provide: with identity on, all three record-based signallers skip it, so a
            # LIVE player becomes unreachable by the hook, by the claim-time kill and by
            # the election sweep at once. The old comment even named that outcome and
            # shipped it anyway.
            #
            # The wrapper already resolves the same failure the other way: it refuses to
            # `exec` if it cannot publish, so nothing plays that cannot be stopped. This
            # path holds the child's Popen handle, so it can do better than the wrapper --
            # retry the lookup, and if it still fails, stop the player through the handle
            # and void the trial rather than publish a record no signaller will act on.
            if A.player_identity == "on" and outcome == PS_ERROR:
                for _ in range(4):
                    time.sleep(0.002)
                    outcome, st = ps_starttime(proc.pid)
                    if outcome != PS_ERROR:
                        break
            if A.player_identity == "on" and outcome == PS_ERROR:
                rec("publish_refused", job=jid, player_pid=proc.pid,
                    why="identity_lookup_failed",
                    action="player_terminated_via_handle")
                # ROUND 26: THIS IS THE SECOND SITE THAT SIGNALS THROUGH A HANDLE, so it
                # takes the same rule as the first. `Popen.terminate()` polls, sees no
                # returncode, and calls `os.kill` -- and between those two the reaper
                # thread can reap, which releases the pid. Under `player_lock` the reaper
                # cannot, so the target is live or an unreaped zombie. A repair applied to
                # one of two handle sites is the shape this document keeps finding.
                try:
                    with player_lock:
                        proc.terminate()
                except OSError as e:
                    rec("publish_refused_kill_failed", job=jid,
                        player_pid=proc.pid, err=type(e).__name__)
                rec("W_pid_write", job=jid, player_pid=proc.pid, by="worker",
                    result="refused", identity="lookup_failed")
            else:
                with open(PIDF, "w") as fh:
                    fh.write(f"{proc.pid}.{st}\n" if st else f"{proc.pid}\n")
                rec("W_pid_write", job=jid, player_pid=proc.pid, by="worker",
                    identity=(st if st else
                              "off" if A.player_identity == "off" else "absent"))
        else:
            rec("W_pid_write", job=jid, player_pid=proc.pid, result="disabled")
    else:
        rec("W_pid_write", job=jid, player_pid=proc.pid, by="player",
            result="deferred_to_player")
    if A.die_after == "pid":
        rec("worker_die", where="after_W")
        os._exit(9)
