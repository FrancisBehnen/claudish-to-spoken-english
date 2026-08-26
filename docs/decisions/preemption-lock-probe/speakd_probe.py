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
                     "stranger's group.")
ap.add_argument("--generation", default="1")
A = ap.parse_args()

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


def proc_starttime(pid):
    """Existence AND identity in one call: `ps -o lstart= -p <pid>`.

    Darwin's `ps` prints the process's start time and exits 1 with no output when there
    is no such process, so one fork answers both questions that `kill(pid, 0)` conflates.
    Returns the start time with spaces squeezed to `_` -- the value has to live in a
    symlink target beside the pid, and a reader splits on the FIRST dot -- or None when
    the pid names nothing.

    This is the SAME instrument the spec's §10.5 clause 2 specifies for the owner record
    (`<pid>.<starttime>`), used here for the same reason: a pid is a number, not an
    identity, and every question this probe asks of a recorded pid is really a question
    about the process that wrote it. Its resolution is one second, which is the honest
    limit of the repair and is stated as such in the document.
    """
    try:
        out = subprocess.run(["/bin/ps", "-o", "lstart=", "-p", str(pid)],
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    except OSError:
        return None
    if out.returncode != 0:
        return None
    s = out.stdout.decode("utf-8", "replace").strip()
    return "_".join(s.split()) if s else None


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
OWNER_RECORD = (f"{os.getpid()}.{MY_STARTTIME}" if MY_STARTTIME
                else str(os.getpid()))


def read_owner(g):
    """(pid, starttime) of generation g's owner, or None if the record is unreadable.

    Split on the FIRST dot: a Darwin pid is decimal digits only and the start time is
    appended, never prepended. A bare-pid record (--owner-identity off, or a record
    written by an older worker) yields a None start time, which every caller below reads
    as 'this record carries no identity' rather than as 'the identity matched'.
    """
    try:
        target = os.readlink(gen_path(g))
    except OSError:
        return None
    pid, _, st = target.partition(".")
    try:
        return (int(pid), st or None)
    except ValueError:
        return None


def owner_identity(pid, st):
    """Three-way, not two: SAME / RECYCLED / GONE.

    `kill(pid, 0)` answers 'does some process have this pid', which is the wrong
    question everywhere a pid was READ FROM A RECORD. The three cases and what each
    means for the record's authority:

      "same"     -- a process with that pid exists and started when the record says.
                    It IS the owner. Everything the record authorises is legitimate.
      "recycled" -- a process with that pid exists and started at some OTHER time. The
                    owner is gone AND its pid has been handed to a stranger. The record
                    is stale; it authorises nothing. This is the case a bare pid cannot
                    see, and the case in which acting on the record damages a third
                    party -- at clause 7(iv) the damage is a whole process group.
      "gone"     -- no process has that pid. The owner is dead and its pid has not been
                    handed out again, so a pgid derived from it is still reserved to it
                    and any orphan of ours is still inside it. THIS is the case clause
                    7(iv) exists for, and it is the one that must still signal.

    Under --owner-identity off, or against a record that carries no start time, this
    degrades to the two-way test it replaces and says so, so the trace never shows an
    identity check that did not happen.
    """
    if A.owner_identity == "off" or st is None:
        return ("same" if alive(pid) else "gone"), None
    cur = proc_starttime(pid)
    if cur is None:
        return "gone", None
    if cur != st:
        return "recycled", cur
    return "same", cur


def elect():
    global MYGEN
    for _ in range(60):
        g = highest_gen()
        if g is None:
            try:
                os.symlink(OWNER_RECORD, gen_path(0))
                MYGEN = 0
                rec("election_won", gen=0, record=OWNER_RECORD)
                return True
            except FileExistsError:
                continue
        own = read_owner(g)
        if own is None:
            continue
        owner, owner_st = own
        verdict, live_st = owner_identity(owner, owner_st)
        if verdict == "recycled":
            # A dead owner whose pid a stranger now holds used to read as LIVE here, so
            # every candidate lost the election to a process that was never the owner and
            # jobs sat unconsumed. Same defect as the sweep's, one clause earlier.
            rec("owner_pid_recycled", site="election", gen=g, pid=owner,
                recorded=owner_st, live=live_st)
        if verdict == "same":
            rec("election_lost", held_by=owner, gen=g)
            return False
        try:
            os.symlink(OWNER_RECORD, gen_path(g + 1))
        except FileExistsError:
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
    # a marked generation, re-read the recorded owner's start time and take the three-way
    # verdict: signal on "same" and on "gone", SKIP on "recycled". The recycled case also
    # EXPIRES the marker -- the owner is provably gone, so the marker can never become
    # actionable again, and leaving it standing is exactly what keeps the gate open on
    # every later election.
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
    # THE SAFETY ARGUMENT IS THE ONE KERNEL PROPERTY THE THREE-WAY RESTS ON: a pid is not
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


def read_player_records():
    """Every pid currently published, with the path that published it."""
    out = []
    if A.pid_mode == "perplayer":
        try:
            for name in os.listdir(PLAYERDIR):
                m = RECORD_RE.match(name)
                if m:
                    out.append((int(m.group(1)),
                                os.path.join(PLAYERDIR, name)))
        except OSError:
            pass
        return out
    if A.ledger == "on":
        try:
            for row in open(LEDGER):
                if row.strip():
                    try:
                        out.append((int(row.split("\t")[0]), LEDGER))
                    except ValueError:
                        pass
        except OSError:
            pass
        return out
    try:
        out.append((int(open(PIDF).read().strip()), PIDF))
    except (OSError, ValueError):
        pass
    return out


def sweep_record():
    rows = read_player_records()
    n = 0
    for p, _src in rows:
        if p == os.getpid():
            continue
        try:
            os.kill(p, SIG_SWEEP_REC)
            rec("kill_attempt", by="election-sweep", site="record", target=p,
                sig=int(SIG_SWEEP_REC), result="sent")
            n += 1
        except OSError:
            rec("kill_attempt", by="election-sweep", site="record", target=p,
                sig=int(SIG_SWEEP_REC), result="ESRCH")
    rec("election_sweep_record", swept=n, rows=len(rows),
        pids=(",".join(str(x[0]) for x in rows) or "-"))
    # The round-1 ledger truncation, kept switchable BECAUSE it is the defect:
    # anything appended between the read above and this truncate is erased without
    # ever having been signalled. The perplayer scheme has nothing to truncate.
    if A.ledger == "on":
        if A.sweep_gap_ms:
            time.sleep(A.sweep_gap_ms / 1000.0)
        at_truncate = [str(x[0]) for x in read_player_records()]
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
    """
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


def kill_player(site, sig, jid):
    targets = []
    if site in ("handle", "both") and player is not None:
        targets.append(("handle", player.pid))
    if site in ("pidfile", "both"):
        for p, _s in read_player_records():
            targets.append(("record", p))
    if not targets:
        rec("kill_attempt", by="worker-claim", site=site, target="none",
            result="no_target", job=jid)
        return
    for how, target in targets:
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
        sh = ('sleep "$PUBDELAY"; '
              'rp=$(printf %s "$REC" | sed "s/PIDPLACEHOLDER/$$/"); '
              'if [ -n "$PENDING" ]; then printf "%s\\n" "$$" > "$PENDING" && '
              'mv "$PENDING" "$rp"; '
              'else printf "%s\\n" "$$" > "$rp.tmp" && mv "$rp.tmp" "$rp"; fi; '
              'exec "$@"')
        env = dict(os.environ, REC=recpath, PENDING=(pending or ""),
                   PUBDELAY=str(A.publish_delay_ms / 1000.0))
        player = subprocess.Popen(["/bin/sh", "-c", sh, "_"] + inner, env=env,
                                  start_new_session=(A.player_setsid == "on"))
        record = recpath.replace("PIDPLACEHOLDER", str(player.pid))
    rec("P_popen", job=jid, player_pid=player.pid, pid_mode=A.pid_mode,
        record=os.path.basename(record) if record else "-")
    if A.reap == "on":
        threading.Thread(target=reap, args=(player, jid, t_popen, record),
                         daemon=True).start()
    if A.die_after == "popen":
        rec("worker_die", where="between_P_and_W")
        os._exit(9)

    # ------------------------------------------------------------------ W
    if A.pid_mode == "worker":
        if A.pid_write == "on":
            with open(PIDF, "w") as fh:
                fh.write(f"{player.pid}\n")
            rec("W_pid_write", job=jid, player_pid=player.pid, by="worker")
        else:
            rec("W_pid_write", job=jid, player_pid=player.pid, result="disabled")
    else:
        rec("W_pid_write", job=jid, player_pid=player.pid, by="player",
            result="deferred_to_player")
    if A.die_after == "pid":
        rec("worker_die", where="after_W")
        os._exit(9)
