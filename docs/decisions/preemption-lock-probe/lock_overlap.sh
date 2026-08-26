#!/bin/bash
# ROW 21's METRIC, CHECKED RATHER THAN ASSUMED.
#
# `run_lock.sh` scores a trial by counting `owner` records. The document reads a count of
# 2 as "two resident workers, each holding a ~340 MB model" -- which is a statement about
# two processes owning the session AT THE SAME TIME. Counting records establishes no such
# thing, and review was right that nothing in the rig checked it. This script is that
# check, over the committed per-trial lock traces.
#
# WHAT REVIEW GOT RIGHT AND WHAT IT GOT WRONG. The observation that started this was:
# in lock-S2_longstall-spec-N4-s1000-r1.tsv the two `owner` records are 0.939 s apart
# while HOLD is 0.500 s, so "the racer released before the winner claimed" -- sequential,
# not concurrent. The arithmetic is exact. The inference is not, and this script exists
# to make the reason mechanical rather than arguable:
#
#   THE WINNER DOES NOT CLAIM AT ITS `owner` RECORD. It claims at `mkdir_ok` -- the
#   successful exclusive create -- and `owner` is where it FINISHES publishing, one whole
#   injected stall later. That ordering is the entire premise of S1/S2: the racer
#   misclassifies a winner that has ALREADY WON and is mid-publication. Read the winner's
#   ownership from `mkdir_ok`, and in that trace the racer's whole 0.500 s hold sits
#   INSIDE the winner's interval. The two owners are not sequential; one is nested in the
#   other.
#
# So an ownership interval here is [claim, owner + HOLD]:
#   claim   `mkdir_ok` (current/spec: the exclusive create that decided the election) or
#           `published` (proposed: the exclusive-create symlink). NOT `owner`.
#   release owner + HOLD, from `run_lock.sh`'s own HOLD -- see the next paragraph.
#
# THE DIRECTION OF THE ERROR IN THIS DERIVATION IS ONE-WAY, AND THAT IS WHY IT IS USABLE.
# No process records a release: `lockrace.py` ends an owner with `time.sleep(hold_ms)` and
# exits, and `sleep(3)` is a LOWER bound on the time slept. So [claim, owner + HOLD] is a
# SUBSET of the interval over which the process actually believed it owned the session.
# Overlap of two subsets therefore PROVES concurrency; absence of overlap proves nothing
# and only leaves it UNESTABLISHED. This script reports it in exactly those terms and
# never claims a trial was sequential.
#
# WHAT IT CANNOT DO. lock-owners.tsv carries a count per trial and no timestamps at all,
# and per-trial traces were kept for 7 of 1200 trials. So this check reaches the traced
# trials and no others; §3.3a in the decision document carries what the remaining
# two-owner trials rest on instead. A guard that quietly passed on the 1193 it cannot see
# would be worse than no guard, so it prints the coverage as a fraction and the document
# quotes that fraction.
#
# usage: lock_overlap.sh <traces_dir> [expected_lock_traces]
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
T=${1:?traces dir}
WANT=${2:-0}

if [[ ! -d $T ]]; then
  echo "lock_overlap.sh: $T is not a directory -- nothing to derive." >&2
  exit 2
fi

# HOLD IS NOT HAND-CARRIED. The release instant is an inference from the producer, so the
# producer is where the number has to come from; a 500 typed into this file would drift
# away from run_lock.sh silently and take every overlap with it.
DRIVER=${DRIVER:-$HERE/run_lock.sh}
if [[ ! -f $DRIVER ]]; then
  echo "lock_overlap.sh: cannot read $DRIVER -- HOLD is defined there and the release" >&2
  echo "instant is derived from it. Refusing to assume a hold time." >&2
  exit 2
fi
hold_lines=$(grep -c '^HOLD=' "$DRIVER" || true)
if [[ ${hold_lines:-0} -ne 1 ]]; then
  echo "lock_overlap.sh: $DRIVER has $hold_lines lines matching ^HOLD= -- expected exactly 1." >&2
  echo "The hold time this script derives releases from is no longer unambiguous." >&2
  exit 2
fi
HOLD_MS=$(sed -n 's/^HOLD=\([0-9][0-9]*\)$/\1/p' "$DRIVER")
if [[ -z ${HOLD_MS:-} ]]; then
  echo "lock_overlap.sh: $DRIVER's HOLD= is not a plain integer of milliseconds." >&2
  exit 2
fi

# `ls | wc` over a glob that matches nothing succeeds and reports 0, and a check that
# accepts 0 traces is the null-as-pass this rig refuses everywhere else.
shopt -s nullglob
traces=("$T"/lock-*.tsv)
shopt -u nullglob
if [[ ${#traces[@]} -eq 0 ]]; then
  echo "lock_overlap.sh: no lock-*.tsv traces in $T -- there is nothing to check, and" >&2
  echo "an empty check is not a passing one." >&2
  exit 2
fi
if [[ $WANT -gt 0 && ${#traces[@]} -ne $WANT ]]; then
  echo "lock_overlap.sh: found ${#traces[@]} lock traces in $T, expected $WANT." >&2
  exit 2
fi

echo "== ROW 21 / OVERLAP: do a trial's owners hold CONCURRENTLY? =="
echo "   HOLD = ${HOLD_MS} ms, read from $(basename "$DRIVER")"
echo "   interval = [claim, release]; claim is mkdir_ok / published, NOT owner. release is"
echo "   the trace's own released record where the run wrote one, else owner + HOLD."
echo "   sleep() is a LOWER bound on the hold, so the interval is a SUBSET of the real"
echo "   one: overlap PROVES concurrency, absence of overlap only leaves it unestablished."
echo

awk -F'\t' -v hold_ms="$HOLD_MS" '
function fail(msg) { printf "  FAIL %s\n", msg; bad++ }
# The interval END. A recorded `released` is an OBSERVATION; owner + HOLD is a LOWER BOUND
# on it, because lockrace.py ends a hold with sleep() and sleep() may overrun. Both are
# usable for proving overlap and neither can rule one out -- see the header.
function rel(i) { return (i in orel ? orel[i] : ot[i] + hold_ms / 1000.0) }
function relkind(i) { return (i in orel ? "recorded" : "inferred") }
function report(   i, j, n, s, e, ov, lo, hi, pairs, best, bestmsg, encl) {
  if (cur == "") return
  files++
  printf "%s\n", cur
  if (nown == 0) { printf "  no owner record -- not a two-owner trial, nothing to check\n\n"
                   cur = ""; nown = 0; return }
  for (i = 1; i <= nown; i++) {
    if (ostart[i] == "") {
      fail(sprintf("owner pid=%s at %.6f has no mkdir_ok/published record of its own --", opid[i], ot[i]))
      printf "       the claim instant is not in the trace, so no interval can be built.\n"
      cur = ""; nown = 0; return
    }
    printf "  owner %d  pid=%-7s role=%-6s claim=%.6f  owner=%.6f  release=%.6f (%s)\n",
      i, opid[i], orole[i], ostart[i], ot[i], rel(i), relkind(i)
  }
  if (nown < 2) { printf "  owners=1 -- correct; concurrency is not in question\n\n"
                  cur = ""; nown = 0; return }
  twoplus++
  best = -1; bestmsg = ""; pairs = 0
  for (i = 1; i <= nown; i++) for (j = i + 1; j <= nown; j++) {
    lo = (ostart[i] > ostart[j] ? ostart[i] : ostart[j])
    hi = (rel(i) < rel(j) ? rel(i) : rel(j))
    ov = hi - lo
    encl = ""
    if (ostart[i] <= ostart[j] && rel(j) <= rel(i)) encl = " (one interval NESTED in the other)"
    if (ostart[j] <= ostart[i] && rel(i) <= rel(j)) encl = " (one interval NESTED in the other)"
    if (ov > 0)
      printf "  pair %d,%d  owner-to-owner gap=%.6f s   INTERVAL OVERLAP=%.6f s%s\n",
        i, j, (ot[j] > ot[i] ? ot[j] - ot[i] : ot[i] - ot[j]), ov, encl
    else
      printf "  pair %d,%d  owner-to-owner gap=%.6f s   NO OVERLAP: the intervals are %.6f s APART\n",
        i, j, (ot[j] > ot[i] ? ot[j] - ot[i] : ot[i] - ot[j]), -ov
    if (ov > 0) { pairs++; if (ov > best) { best = ov; bestmsg = sprintf("%d,%d", i, j) } }
  }
  if (pairs == 0) {
    fail("owners=" nown " but NO pair of ownership intervals overlaps --")
    printf "       the trial counted as a concurrency violation and does not establish one.\n"
  } else {
    printf "  CONCURRENT: %d of %d pairs overlap; widest %s\n", pairs, nown * (nown - 1) / 2, bestmsg
    proven++
  }
  printf "\n"
  cur = ""; nown = 0
}
FNR == 1 { report(); cur = FILENAME; sub(/.*\//, "", cur); nown = 0
           split("", claim); split("", orel); split("", oidx) }
$7 == "mkdir_ok" || $7 == "published" { claim[$6] = $1 }
$7 == "owner" { nown++; ot[nown] = $1; opid[nown] = $6; orole[nown] = $5
                oidx[$6] = nown
                ostart[nown] = ($6 in claim ? claim[$6] : "") }
# ROUND 31 added this record to lockrace.py, so a re-run OBSERVES the release instead of
# inferring it from hold_ms. Prefer it wherever it exists; the committed traces predate it.
$7 == "released" && ($6 in oidx) { orel[oidx[$6]] = $1 }
END {
  report()
  printf "traces read=%d  two-or-more-owner traces=%d  concurrency PROVEN on=%d\n",
    files, twoplus, proven
  if (bad > 0) {
    printf "\n%d trace(s) above did not establish the concurrency the owner count is read as.\n", bad
    exit 3
  }
  if (twoplus == 0)
    printf "\nNOTE: no traced trial produced two owners, so nothing was checked here.\n"
}' "${traces[@]}"
st=$?

if [[ $st -eq 3 ]]; then
  echo "INCOMPLETE: at least one two-owner trace does not establish concurrent ownership." >&2
  echo "owners counts ownership CONCLUSIONS; the document reads 2 as two workers resident" >&2
  echo "at once. Where the intervals do not overlap that reading is not supported by the" >&2
  echo "trace and the document must not present the trial as a concurrency violation." >&2
  exit 2
fi
exit "$st"
