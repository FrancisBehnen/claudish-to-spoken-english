#!/usr/bin/env python3
"""Stub player. Stands in for `afplay f.wav`.

Two jobs beyond making a noise-shaped delay:

 1. it appends its OWN pid to the player ledger as its first action, so the
    ledger's existence does not depend on the worker surviving the spawn;
 2. it logs its own PROCESS START, so the interval a trial's stale player ran for has
    two endpoints (collect.sh joins them into `pstart_to_pend_s`).

This is not an audibility instrument and the docstring used to say it was -- "it logs its
start so `audible from` has a timestamp". THIS PROCESS OPENS NO AUDIO DEVICE: the delay is
a `sleep`, there is no synthesis, no file and no output stream, so `player_start` is the
instant the interpreter reached this module and nothing more. A `player_start` that is
absent bounds when the kill landed -- inside interpreter startup -- and a `player_start`
that is present does not establish that anything was heard. Only the `REAL-*` arm runs
`afplay`, and §2.6 of the decision document records that even there the figures are
process stamps and audibility is `[inferred]`.

Attribution of WHICH step killed it does NOT come from here -- a kill landing
inside interpreter startup terminates the process by the signal's default action
before any handler exists. That comes from the parent's returncode.

usage: player_probe.py <secs> <log> <tag> [ledger]
"""
import os
import signal
import subprocess
import sys
import time

secs = float(sys.argv[1])
log = sys.argv[2]
tag = sys.argv[3]
ledger = sys.argv[4] if len(sys.argv) > 4 else ""


def starttime(pid):
    """`ps -o lstart= -p <pid>`, spaces squeezed to `_`. See speakd_probe's copy.

    The ledger is a player RECORD -- `read_player_records()` returns its rows and the
    election sweep and the claim-time kill both signal them -- so its first field carries
    the same `<pid>.<starttime>` identity as every other player record. A ledger row that
    carried a bare pid under `--player-identity on` would read as `unverifiable` and be
    refused by every signaller, which would silently disarm the two arms that use it.
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


if ledger:
    # One extra fork, before player_start is stamped, and ONLY in the two ledger arms
    # (C9, C13a). No arm that derives a figure from player_start runs ledger=on -- C14a
    # and C14b are ledger=off -- so this perturbs no published timestamp.
    me = os.getpid()
    st = starttime(me) if os.environ.get("PLAYER_IDENTITY", "on") == "on" else None
    with open(ledger, "a") as fh:
        fh.write(f"{me}.{st}\t{tag}\t{time.time():.6f}\n" if st
                 else f"{me}\t{tag}\t{time.time():.6f}\n")
        fh.flush()
        os.fsync(fh.fileno())


def rec(kind, **kw):
    fields = " ".join(f"{k}={v}" for k, v in kw.items())
    with open(log, "a") as fh:
        fh.write(f"{time.time():.6f}\t{os.getpid()}\t{tag}\t{kind}\t{fields}\n")
        fh.flush()
        os.fsync(fh.fileno())


def handler(signum, frame):
    rec("player_end", sig=signum)
    # Re-raise with the default action so the WAIT STATUS carries the signal too.
    # Exiting 0 here would make the parent's returncode 0 and destroy the only
    # attribution available when the kill lands inside interpreter startup.
    signal.signal(signum, signal.SIG_DFL)
    os.kill(os.getpid(), signum)


for s in (signal.SIGTERM, signal.SIGUSR1, signal.SIGUSR2, signal.SIGINT,
          signal.SIGHUP, signal.SIGALRM):
    signal.signal(s, handler)

rec("player_start", secs=secs)
end = time.time() + secs
while True:
    left = end - time.time()
    if left <= 0:
        break
    time.sleep(min(left, 0.02))
rec("player_end", sig=0)
