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
def read_lock_pid():
    try:
        return int(open(LOCK_PID).read().strip())
    except (OSError, ValueError):
        return -1


def elect_current():
    for _ in range(60):
        try:
            os.mkdir(LOCK)
        except FileExistsError:
            pid = read_lock_pid()
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
            pid = -1
            for _i in range(A.backoff_attempts):
                pid = read_lock_pid()
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


# ===================================================================== main
if A.role == "winner":
    if A.protocol == "proposed":
        g = highest_gen()
        g = 0 if g is None else g + 1
        who = dead_pid() if A.dead_owner else os.getpid()
        os.symlink(str(who), gen_path(g))
        rec("published", gen=g, owner=who, window="none")
        if A.stall_ms:
            time.sleep(A.stall_ms / 1000.0)   # after publication: no window exists
        if not A.dead_owner:
            rec("owner", via="election")
    else:
        os.mkdir(LOCK)
        rec("mkdir_ok")
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
    if fn[A.protocol]():
        rec("owner", via="election")
        time.sleep(A.hold_ms / 1000.0)
sys.exit(0)
