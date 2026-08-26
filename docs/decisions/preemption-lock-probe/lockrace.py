#!/usr/bin/env python3
"""Row 21: the stale-lock protocol under N workers. THREE protocols, not two.

  current    the protocol read out of the residency probe's own source
             (worker-residency.md 2a, [rig]): a lock dir with no pid inside is
             classified stale, rmdir'd, and replaced.

  spec       spec 10.5 clause 2, both sub-clauses:
             (a) no pid yet == INITIALIZING -> bounded backoff retry,
                 reclaim only if the pid is STILL absent afterwards;
             (b) reclamation serialized by an atomic rename into a unique
                 quarantine name, never rmdir-then-mkdir.
             Two races were found in review of this clause BEFORE it was ever
             measured, and this harness provokes both:
               A1  the backoff is a fixed timeout, so a winner descheduled or
                   stopped for longer than it is misclassified anyway;
               A2  the quarantine rename is path-based, so a reclaimer that
                   decided "stale" before another reclaimer finished can rename
                   the FRESH lock (ABA) instead of getting ENOENT.

  proposed   the repair measured here. Ownership is published by symlink(2),
             whose content is created WITH the object, so a record is never
             partially initialized and liveness is never inferred from absence:
               - the owner record is  worker.lock.<gen> -> "<pid>"
               - symlink() is atomic exclusive-create, so exactly one process
                 can ever own a given generation;
               - a dead owner is superseded by creating generation gen+1, never
                 by removing generation gen -- so there is no removable path for
                 an ABA to land on;
               - kill(pid,0) is applied only to a COMPLETE record.
             No backoff, no timeout, no quarantine.

Roles: --role winner  wins first and (for current/spec) stalls in the window
       --role racer   runs the election under contention
Every process that concludes "I own the session" logs an `owner` line. The metric
is how many `owner` lines one trial produces.
"""
import argparse
import os
import re
import subprocess
import sys
import time
import uuid

ap = argparse.ArgumentParser()
ap.add_argument("--dir", required=True)
ap.add_argument("--log", required=True)
ap.add_argument("--role", choices=["winner", "racer"], required=True)
ap.add_argument("--protocol", choices=["current", "spec", "proposed"], required=True)
ap.add_argument("--stall-ms", type=float, default=0.0,
                help="winner: pause between claiming the lock and publishing its pid. "
                     "For `proposed` there is no such window, so the pause lands "
                     "after publication -- stated rather than hidden.")
ap.add_argument("--hold-ms", type=float, default=1200.0)
ap.add_argument("--dead-owner", action="store_true",
                help="winner: publish a lock owned by a pid that has already exited, "
                     "so reclamation is LEGITIMATE. Stages A2.")
ap.add_argument("--classify-stall-ms", type=float, default=0.0,
                help="racer: pause after classifying the lock stale and before acting "
                     "on it. This is what stages A2's ABA ordering.")
ap.add_argument("--reclaim-gap-ms", type=float, default=0.0,
                help="current only: pause between rmdir and mkdir, staging the third "
                     "failure named in 10.5 (a reclaimer removing a lock a third "
                     "process has legitimately re-created).")
ap.add_argument("--backoff-attempts", type=int, default=20)
ap.add_argument("--backoff-ms", type=float, default=2.0)
ap.add_argument("--barrier-dir", default="",
                help="two-way staging barrier. Racers write one file here the instant "
                     "before their protocol read; the winner waits for --barrier-n of "
                     "them before writing its pid. This is what actually puts a racer "
                     "inside the claimed-but-unpublished window: waiting only for the "
                     "winner's claim does not, because a racer still has to start a "
                     "fresh interpreter afterwards, which is tens of ms against a 0-5 ms "
                     "window.")
ap.add_argument("--barrier-n", type=int, default=0,
                help="winner: how many racer acknowledgements to wait for.")
ap.add_argument("--trial", default="0")
ap.add_argument("--label", default="")
A = ap.parse_args()

D = A.dir
LOCK = os.path.join(D, "worker.lock")
LOCK_PID = os.path.join(LOCK, "pid")
GEN_RE = re.compile(r"^worker\.lock\.(\d+)$")


def rec(kind, **kw):
    fields = " ".join(f"{k}={v}" for k, v in kw.items())
    with open(A.log, "a") as fh:
        fh.write(f"{time.time():.6f}\t{A.trial}\t{A.protocol}\t{A.label}\t{A.role}\t"
                 f"{os.getpid()}\t{kind}\t{fields}\n")
        fh.flush()
        os.fsync(fh.fileno())


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def dead_pid():
    """A pid that has certainly exited and been reaped."""
    p = subprocess.Popen([sys.executable, "-c", "pass"])
    p.wait()
    return p.pid


# =========================================================== current / spec
def lock_ino():
    """Identity of the lock directory this read is looking at.

    The barrier can only prove a racer once saw A pid-less lock. Under `current` a
    racer that reclaims first leaves its OWN lock pid-less for an instant, so a bare
    "I saw no pid" is not proof the WINNER's window was entered. The inode is: the
    winner records the inode it created, and only a racer read carrying that same
    inode counts as having been inside the staged window.
    """
    try:
        return os.stat(LOCK).st_ino
    except OSError:
        return -1


def read_lock_pid():
    try:
        return int(open(LOCK_PID).read().strip())
    except (OSError, ValueError):
        return -1


def _still_linked(ino):
    """Does LOCK still name the inode we just read through? See read_lock_identity."""
    try:
        return 1 if os.stat(LOCK).st_ino == ino else 0
    except OSError:
        return 0


def read_lock_identity():
    """(inode, pid) taken through ONE open directory handle.

    Calling lock_ino() and then read_lock_pid() is itself a TOCTOU, and it is the
    same class of bug this detector exists to catch: another racer can rmdir and
    re-create LOCK between the two calls, so the winner's inode gets paired with a
    DIFFERENT lock's missing pid and the trial is scored as staged when the deciding
    read never entered the winner's window.

    Opening the directory once fixes what both observations refer to: the descriptor
    keeps naming the inode it opened even if the path is replaced underneath it, and
    `pid` is resolved relative to that descriptor rather than by path.
        Anchoring alone is not quite enough, and the third value says why. Once the
    descriptor is open the inode stays reachable even after another racer `rmdir`s the
    directory -- at which point `pid` is missing because the lock was DESTROYED, not
    because the winner had not written it yet. Both look like "no pid at the winner's
    inode", and only the first is evidence the staged window was entered.

    `st_nlink` does NOT separate them here: measured on this machine's APFS, `fstat`
    through the open descriptor still reports a positive link count after the directory
    is removed. So the discriminator is a CONFIRMATION re-stat of the path after the
    pid read -- if the path no longer resolves to the inode we read, the lock we were
    looking at is gone and the read is not window evidence.

    This is deliberately conservative rather than atomic: a winner's lock replaced in
    the instant after a genuine window read is scored `linked=0` and the trial is
    VOIDed. It errs toward discarding a real observation, never toward accepting a
    false one, which is the only direction that is safe for a staging detector.
    """
    try:
        fd = os.open(LOCK, os.O_RDONLY | os.O_DIRECTORY)
    except OSError:
        return (-1, -1, 0)
    try:
        ino = os.fstat(fd).st_ino
        try:
            pfd = os.open("pid", os.O_RDONLY, dir_fd=fd)
        except OSError:
            return (ino, -1, _still_linked(ino))
        try:
            with os.fdopen(pfd, "r") as fh:
                return (ino, int(fh.read().strip()), _still_linked(ino))
        except (OSError, ValueError):
            return (ino, -1, _still_linked(ino))
    finally:
        os.close(fd)


def elect_current():
    for _ in range(60):
        try:
            os.mkdir(LOCK)
        except FileExistsError:
            # THE READ THAT DECIDES THE TRIAL, and it reports on itself.
            #
            # ack_barrier() stages the OBSERVATION and then blocks on GO. But after GO
            # the winner writes its pid, and this racer -- released by the same token --
            # performs its own FRESH read here. Nothing orders the two. So the read
            # below could just as easily be an ordinary live-owner check, and a clean
            # cell would look identical either way. Rather than add a sixth staging
            # mechanism, say what this read actually saw; run_lock.sh VOIDs an S1/S2
            # trial in which no racer's deciding read carried the winner's window.
            ino, pid, linked = read_lock_identity()
            rec("election_read", protocol="current", ino=ino, pid=pid, linked=linked,
                saw_window=("yes" if (pid <= 0 and linked) else "no"))
            if pid > 0:
                if alive(pid):
                    rec("lost", held_by=pid)
                    return False
                rec("classified_stale", reason="pid_dead", pid=pid)
            else:
                rec("classified_stale", reason="no_pid")
            if A.classify_stall_ms:
                time.sleep(A.classify_stall_ms / 1000.0)
            try:
                os.unlink(LOCK_PID)
            except OSError:
                pass
            try:
                os.rmdir(LOCK)
                rec("rmdir_ok")
            except OSError as e:
                rec("rmdir_failed", err=type(e).__name__)
                return False
            if A.reclaim_gap_ms:
                time.sleep(A.reclaim_gap_ms / 1000.0)
            continue
        with open(LOCK_PID, "w") as fh:
            fh.write(f"{os.getpid()}\n")
        rec("mkdir_ok")
        return True
    rec("gave_up")
    return False


def elect_spec():
    for _ in range(60):
        try:
            os.mkdir(LOCK)
        except FileExistsError:
            # clause (a): a lock with no pid is INITIALIZING -> bounded backoff
            #
            # The FIRST pass of this loop is spec's counterpart to `current`'s deciding
            # read -- the same instant, the same state -- and it is the one that has to
            # report whether the winner's window was actually open when this racer
            # looked. The later passes cannot: clause (a) exists precisely to keep
            # waiting, so `no_pid_after_backoff` conflates "the window was open and
            # stayed open" with "the window was never entered at all".
            pid = -1
            for _i in range(A.backoff_attempts):
                ino, pid, linked = read_lock_identity()
                if _i == 0:
                    rec("election_read", protocol="spec", ino=ino, pid=pid, linked=linked,
                        saw_window=("yes" if (pid <= 0 and linked) else "no"))
                if pid > 0:
                    break
                time.sleep(A.backoff_ms / 1000.0)
            if pid > 0:
                if alive(pid):
                    rec("lost", held_by=pid)
                    return False
                rec("classified_stale", reason="pid_dead", pid=pid)
            else:
                rec("classified_stale", reason="no_pid_after_backoff",
                    waited_ms=A.backoff_attempts * A.backoff_ms)
            if A.classify_stall_ms:
                time.sleep(A.classify_stall_ms / 1000.0)
            # clause (b): serialize reclamation with an atomic rename
            q = f"{LOCK}.dead.{os.getpid()}.{uuid.uuid4().hex[:8]}"
            try:
                os.rename(LOCK, q)
                rec("quarantine_won", to=os.path.basename(q),
                    quarantined_pid=read_q_pid(q))
            except OSError as e:
                rec("quarantine_lost", err=type(e).__name__)
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
        rec("mkdir_ok")
        return True
    rec("gave_up")
    return False


def read_q_pid(q):
    try:
        return int(open(os.path.join(q, "pid")).read().strip())
    except (OSError, ValueError):
        return -1


# ================================================================= proposed
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


def gen_path(g):
    return os.path.join(D, f"worker.lock.{g}")


def publish(g):
    """Atomic exclusive-create of a FULLY INITIALIZED owner record."""
    try:
        os.symlink(str(os.getpid()), gen_path(g))
        return True
    except FileExistsError:
        return False


def elect_proposed():
    for _ in range(60):
        g = highest_gen()
        if g is None:
            if publish(0):
                rec("published", gen=0)
                return True
            rec("publish_lost", gen=0)
            continue
        try:
            owner = int(os.readlink(gen_path(g)))
        except (OSError, ValueError):
            continue
        # `saw_window=n/a`, and it is not a dodge: there is no pid-less state to enter.
        # readlink() returns the owner or ENOENT, never a half-written record, so S1/S2
        # have nothing to stage for this protocol and run_lock.sh does not VOID it on
        # that ground. The doc says the same thing in words: S1/S2 are structurally
        # vacuous for `proposed`, and its result rests on S3/S4/S6.
        rec("election_read", protocol="proposed", gen=g, owner=owner,
            saw_window="n/a", why="no_pidless_state_by_construction")
        if alive(owner):
            rec("lost", held_by=owner, gen=g)
            return False
        rec("classified_stale", reason="pid_dead", pid=owner, gen=g)
        if A.classify_stall_ms:
            time.sleep(A.classify_stall_ms / 1000.0)
        if publish(g + 1):
            rec("published", gen=g + 1, superseded=g)
            return True
        rec("publish_lost", gen=g + 1)
        continue
    rec("gave_up")
    return False


def await_barrier():
    """Winner: block until --barrier-n racers say they are at their protocol read.

    Without this the staging is a hope, not a fact. run_lock.sh used to sleep 4 ms
    and later waited for the winner's own claim record -- neither puts a racer inside
    the window, because after either signal the racer still has to start a fresh
    Python interpreter (tens of ms) while the window being tested is 0-5 ms. The
    result was that S1's CLEAN cells could be clean because they had degenerated into
    an ordinary live-owner check.
    """
    if not (A.barrier_dir and A.barrier_n):
        return
    os.makedirs(A.barrier_dir, exist_ok=True)
    deadline = time.time() + 5.0
    while len([x for x in os.listdir(A.barrier_dir) if x.startswith("r")]) < A.barrier_n:
        if time.time() > deadline:
            rec("barrier_timeout",
                seen=len([x for x in os.listdir(A.barrier_dir) if x.startswith("r")]),
                wanted=A.barrier_n)
            return
        time.sleep(0.001)
    # PHASE 2. Release every racer at once, only now that all N have observed the
    # window. Without this the barrier was not two-phase at all: a racer acknowledged
    # and went straight into its protocol, so the FIRST racer could reclaim or replace
    # the pid-less lock before racers 2..N ever looked at it, and the staging was
    # race-dependent again.
    try:
        open(os.path.join(A.barrier_dir, "GO"), "w").close()
    except OSError:
        pass
    rec("barrier_released", n=A.barrier_n)


def ack_barrier():
    """Racer: acknowledge only AFTER actually observing the state under test.

    An acknowledgement written before the protocol read proves nothing: at a 0 ms
    stall the winner can see the last ack and publish its pid before that racer ever
    looks, and the cell degenerates into an ordinary live-owner check -- the same
    false-clean this barrier exists to prevent, one level down. So the racer waits
    here until it has SEEN the state its protocol is being tested against, and only
    then releases the winner.

    For `current`/`spec` that state is the pid-less lock: the directory exists and
    `pid` does not. For `proposed` there is no pid-less state by construction -- the
    symlink's target is created with it -- so the observation is simply that a
    generation record exists.

    AND THAT IS ALL IT DOES. Round 11: this stages the OBSERVATION, not the ELECTION
    READ. After GO the winner applies its stall and writes its pid while each racer
    starts its protocol and performs a second, independent read -- and it is the second
    read that decides the trial. Nothing here orders those two, and at --stall-ms 0
    nothing can: the winner writes the pid immediately after GO, so the interval a
    racer would have to land in is zero-width. The fix is not a sixth staging
    mechanism. Each election read now reports what it saw (`election_read
    saw_window=`), and run_lock.sh VOIDs an S1/S2 trial whose deciding reads all
    missed the window.
    """
    if not A.barrier_dir:
        return
    os.makedirs(A.barrier_dir, exist_ok=True)
    deadline = time.time() + 5.0
    while True:
        if A.protocol == "proposed":
            seen = highest_gen() is not None
        else:
            seen = os.path.isdir(LOCK) and not os.path.exists(LOCK_PID)
        if seen:
            break
        if time.time() > deadline:
            # Never observed the window. Say so loudly: the driver turns this into
            # VOID rather than letting it score as a protocol result.
            rec("observe_timeout", protocol=A.protocol)
            return
        time.sleep(0.0005)
    try:
        open(os.path.join(A.barrier_dir, f"r{os.getpid()}"), "w").close()
        rec("barrier_ack", observed="pid_less" if A.protocol != "proposed" else "gen")
    except OSError:
        pass
    # PHASE 2. Wait to be released. Acknowledging and proceeding immediately is what
    # let the first racer destroy the state the others were staged to observe.
    go = os.path.join(A.barrier_dir, "GO")
    deadline = time.time() + 5.0
    while not os.path.exists(go):
        if time.time() > deadline:
            rec("release_timeout")
            return
        time.sleep(0.0005)


# ===================================================================== main
if A.role == "winner":
    if A.protocol == "proposed":
        g = highest_gen()
        g = 0 if g is None else g + 1
        who = dead_pid() if A.dead_owner else os.getpid()
        os.symlink(str(who), gen_path(g))
        rec("published", gen=g, owner=who, window="none")
        # The barrier runs for `proposed` TOO. It has no pid-less window -- the
        # symlink's target is created with it -- but the racers still block on the GO
        # token, so a winner that never releases them leaves every racer in
        # release_timeout and the whole cell VOID. Omitting this call did exactly that.
        await_barrier()
        if A.stall_ms:
            time.sleep(A.stall_ms / 1000.0)   # after publication: no window exists
        if not A.dead_owner:
            rec("owner", via="election")
    else:
        os.mkdir(LOCK)
        # The inode is what lets run_lock.sh tell "a racer's deciding read was inside
        # MY window" from "a racer saw some pid-less lock, possibly one another racer
        # had just created".
        rec("mkdir_ok", ino=lock_ino())
        await_barrier()
        if A.stall_ms:
            time.sleep(A.stall_ms / 1000.0)   # THE WINDOW
        who = dead_pid() if A.dead_owner else os.getpid()
        with open(LOCK_PID, "w") as fh:
            fh.write(f"{who}\n")
        rec("pid_written", owner=who)
        if not A.dead_owner:
            rec("owner", via="election")
    time.sleep(A.hold_ms / 1000.0)
else:
    fn = {"current": elect_current, "spec": elect_spec, "proposed": elect_proposed}
    ack_barrier()
    if fn[A.protocol]():
        rec("owner", via="election")
        time.sleep(A.hold_ms / 1000.0)
sys.exit(0)
