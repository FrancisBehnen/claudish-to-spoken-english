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
# would be worse than no guard, so it prints the coverage as a fraction, the document quotes
# that fraction, and -- since round 33 -- the script REFUSES a set that is not the size the
# fraction's numerator names. Printing a coverage it does not enforce is how this same guard
# would have reported 7/1200 over six traces, which is what round 33 found.
#
# ROUND 33 CLOSED THE TWO WAYS THIS GUARD COULD PASS WITHOUT CHECKING ANYTHING, and both
# were in the paragraph above rather than against it -- the coverage was PRINTED and not
# REQUIRED, which is the difference between a report and a guard.
#
#   1. THE EXPECTED TRACE COUNT DEFAULTED TO OFF. It was `${2:-0}` under a `-gt 0` test,
#      and the invocation this rig and the README both document is `lock_overlap.sh
#      traces` with no second argument. So the count check never ran in the only form
#      anyone calls, and deleting one of the seven committed traces left this script
#      exiting 0 over a smaller sample while the document went on quoting 7/1200. The
#      committed evidence is a FIXED set, so its size is a fact this file can hold:
#      the default is now that size, and a caller pointing this at some other run's logs
#      passes that run's count.
#   2. NO QUALIFYING TRIAL WAS A SUCCESSFUL DERIVATION. `twoplus == 0` printed a NOTE
#      saying nothing had been checked and then fell out of END with status 0. This is the
#      script the document cites as the reason row 21's `owners` metric is DERIVED rather
#      than asserted, so a run that established nothing must not report establishment.
#      Zero qualifying trials is now exit 2, and so is a set of traces that parse to no
#      records at all.
#
# Both are the shape §1 keeps meeting -- a check that passes on nothing or on part of its
# input -- and this is the first time this document has met it TWICE IN ONE FILE, one
# commit after that file was written as the repair for a different defect.
#
# ROUND 34 FOUND A THIRD HOLE IN THE SAME GUARD, AND IT IS THE ONE THE ROUND-33 REPAIR
# LOOKED LIKE IT HAD CLOSED. The count check compares the GLOB SIZE against 7. The awk
# below dispatches per file on `FNR == 1`, which a ZERO-BYTE file never fires -- so an empty
# trace is counted by the shell and absent from awk. Seven files of which three are empty
# passes the count check, reports `traces read=4`, and exits 0 if any of the remaining four
# still has two overlapping owners: the coverage fraction the document quotes derived over
# FEWER traces than its own numerator names, which is verbatim what round 33 said it had
# fixed. The `files == 0` guard added in round 33 only catches the case where ALL of them
# are empty, which is the case the round-33 test happened to use.
#
# It is closed at BOTH layers, because the two layers fail for different reasons:
#   * the shell refuses a non-regular, unreadable or ZERO-BYTE trace before awk is invoked
#     (`require_nonempty_all`, the one shared definition in `require.sh`); and
#   * awk asserts that it READ every file it was handed -- `files == want_files` -- so a
#     future dispatch condition subtler than emptiness cannot drop a file silently either.
# The second is the guard that would have caught this one without anyone predicting it.
#
# usage: lock_overlap.sh <traces_dir> [expected_lock_traces]
#        expected_lock_traces defaults to the committed set's size. `0` disables the
#        count check and says so on stderr; it is for a caller deriving over logs whose
#        size is not known in advance, and it is never the default.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# The null-as-pass rule -- "exists" is not "contains anything" -- has ONE definition in
# this rig, for the reason the attribution rule does. This script is the file that met the
# shape twice, so it is the last file that should carry its own private copy of the check.
if [[ ! -f "$HERE/require.sh" ]]; then
  echo "lock_overlap.sh: missing $HERE/require.sh -- the input-validation rule lives there," >&2
  echo "and this script must not fall back to checking its inputs a private way." >&2
  exit 2
fi
# shellcheck source=require.sh
. "$HERE/require.sh"
if ! declare -F require_nonempty_all >/dev/null; then
  echo "lock_overlap.sh: $HERE/require.sh defined no require_nonempty_all. An include that" >&2
  echo "sources cleanly and defines nothing would leave every input unchecked." >&2
  exit 2
fi

T=${1:?traces dir}

# THE SIZE OF THE COMMITTED EVIDENCE, in one place, because it is what the document's
# 7/1200 coverage fraction is the numerator of.
#
# AND IT IS A LITERAL ON PURPOSE, which is the one place in this rig where that is the right
# answer. Every other number here is derived from its producer -- HOLD out of run_lock.sh
# above, the tallies out of their own row blocks in tally_check.sh -- because a copy drifts.
# An EXPECTED count cannot be: deriving it by counting the traces in $T is precisely the
# defect this round closed, a check that asks the input how many inputs there should be and
# therefore always agrees. The number has to be asserted from outside the thing it checks,
# and a fixed committed set is a fact this file is allowed to hold. If a trace is ever added
# deliberately, this line and the document's fraction move together, and the guard fails
# loudly in between -- which is the intended direction.
COMMITTED_LOCK_TRACES=7
WANT=${2:-$COMMITTED_LOCK_TRACES}
# `[[ $WANT -gt 0 ]]` evaluates a non-numeric WANT as 0, i.e. straight back into the
# disabled-by-accident state round 33 removed. Refuse it instead -- through the shared
# check, which also refuses `010` (bash arithmetic reads that as octal 8, so a value can
# compare as a different number than it reads as).
require_uint "lock_overlap.sh" "expected_lock_traces" "$WANT" 0 || exit 2

require_dir "lock_overlap.sh" "$T" || exit 2

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
# EVERY trace must be a regular, readable, NON-EMPTY file, and this runs BEFORE the count
# check below rather than after it. A zero-byte trace satisfies the count and vanishes from
# awk`s `FNR == 1` dispatch -- see the third hole in the header.
if ! require_nonempty_all "lock_overlap.sh" "${traces[@]}"; then
  echo "lock_overlap.sh: at least one trace above is not readable evidence. The coverage" >&2
  echo "fraction this script derives is over the WHOLE committed set, so a set with an" >&2
  echo "unusable member derives a fraction whose numerator is wrong -- and the shell count" >&2
  echo "cannot see that, because an empty file still counts as a file." >&2
  exit 2
fi
if [[ $WANT -eq 0 ]]; then
  echo "lock_overlap.sh: expected_lock_traces=0 -- the coverage check is DISABLED for this" >&2
  echo "run, deliberately. ${#traces[@]} trace(s) read; whatever fraction this establishes is" >&2
  echo "not the committed set's, and no coverage claim in the document rests on it." >&2
elif [[ ${#traces[@]} -ne $WANT ]]; then
  echo "lock_overlap.sh: found ${#traces[@]} lock traces in $T, expected $WANT." >&2
  echo "This guard derives the document's coverage fraction, so it derives it over the whole" >&2
  echo "committed set or not at all: a smaller sample would exit 0 under a document still" >&2
  echo "quoting 7/1200. Pass the count explicitly to derive over some other run's logs." >&2
  exit 2
fi

echo "== ROW 21 / OVERLAP: do a trial's owners hold CONCURRENTLY? =="
echo "   HOLD = ${HOLD_MS} ms, read from $(basename "$DRIVER")"
echo "   interval = [claim, release]; claim is mkdir_ok / published, NOT owner. release is"
echo "   the trace's own released record where the run wrote one, else owner + HOLD."
echo "   sleep() is a LOWER bound on the hold, so the interval is a SUBSET of the real"
echo "   one: overlap PROVES concurrency, absence of overlap only leaves it unestablished."
echo

awk -F'\t' -v hold_ms="$HOLD_MS" -v want_files="${#traces[@]}" '
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
  # A FILE THAT PARSED TO NO RECORDS IS NOT A TRACE THAT AGREED. The shell above refuses an
  # empty GLOB; this refuses an empty FILE, which reaches `awk` as a name and leaves it with
  # nothing -- the same null-as-pass one layer in.
  if (files == 0) {
    printf "\nNO RECORDS: every file handed to this derivation parsed to zero rows.\n"
    exit 4
  }
  # AND THE SAME QUESTION FOR EVERY OTHER FRACTION OF THE SET, which is the hole round 34
  # found in the two guards above. `files` counts the files this program actually DISPATCHED
  # on, and dispatch is `FNR == 1`; anything that never reaches a first record is counted by
  # the shell and invisible here. The shell now refuses the known cause (a zero-byte trace),
  # and this refuses the CLASS: the derivation reports over exactly as many traces as it was
  # handed, or it reports nothing. A guard that had asked this in round 33 would have caught
  # round 34s finding without anyone having to think of empty files.
  if (files != want_files) {
    printf "\nPARTIAL READ: %d file(s) were handed to this derivation and %d were read.\n",
      want_files, files
    printf "The coverage fraction this script exists to derive would be over the smaller\n"
    printf "number while the document quotes the larger. That is not a derivation.\n"
    exit 4
  }
  # ROUND 33: THIS USED TO BE A NOTE AND EXIT 0. It is the whole finding -- the script that
  # the document cites AS row 21s derivation reported success for a run in which not one
  # trial qualified to be checked. Absence of a qualifying trial is absence of the
  # derivation. (No apostrophes in here: this awk program is single-quoted.)
  if (twoplus == 0) {
    printf "\nNO QUALIFYING TRIAL: not one trace read here has two owners, so the question\n"
    printf "this script exists to answer was never put. That is not a passing derivation.\n"
    exit 4
  }
  if (proven == 0) {
    printf "\nNOTHING PROVEN: qualifying trials were read and none established concurrency.\n"
    exit 4
  }
}' "${traces[@]}"
st=$?

if [[ $st -eq 3 ]]; then
  echo "INCOMPLETE: at least one two-owner trace does not establish concurrent ownership." >&2
  echo "owners counts ownership CONCLUSIONS; the document reads 2 as two workers resident" >&2
  echo "at once. Where the intervals do not overlap that reading is not supported by the" >&2
  echo "trace and the document must not present the trial as a concurrency violation." >&2
  exit 2
fi
if [[ $st -eq 4 ]]; then
  echo "NOT DERIVED: this run established nothing, and an empty derivation is not a" >&2
  echo "successful one. Row 21's owners metric is cited as DERIVED because this script" >&2
  echo "proves concurrent tenure on the traces that have two owners; a run with no such" >&2
  echo "trace -- or no parseable record at all -- cannot be quoted as that derivation." >&2
  exit 2
fi
exit "$st"
