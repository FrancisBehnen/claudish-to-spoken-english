#!/usr/bin/env python3
"""Stub player. Stands in for `afplay f.wav`.

Two jobs beyond making a noise-shaped delay:

 1. it appends its OWN pid to the player ledger as its first action, so the
    ledger's existence does not depend on the worker surviving the spawn;
 2. it logs its start so "audible from" has a timestamp.

Attribution of WHICH step killed it does NOT come from here -- a kill landing
inside interpreter startup terminates the process by the signal's default action
before any handler exists. That comes from the parent's returncode.

usage: player_probe.py <secs> <log> <tag> [ledger]
"""
import os
import signal
import sys
import time

secs = float(sys.argv[1])
log = sys.argv[2]
tag = sys.argv[3]
ledger = sys.argv[4] if len(sys.argv) > 4 else ""

if ledger:
    with open(ledger, "a") as fh:
        fh.write(f"{os.getpid()}\t{tag}\t{time.time():.6f}\n")
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


for s in (signal.SIGTERM, signal.SIGUSR1, signal.SIGUSR2, signal.SIGINT, signal.SIGHUP):
    signal.signal(s, handler)

rec("player_start", secs=secs)
end = time.time() + secs
while True:
    left = end - time.time()
    if left <= 0:
        break
    time.sleep(min(left, 0.02))
rec("player_end", sig=0)
