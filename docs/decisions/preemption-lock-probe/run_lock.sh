#!/bin/bash
# Row 21 driver. Every scenario runs against all THREE protocols, so a fix is
# demonstrated rather than asserted and a protocol that fails is visible beside one
# that passes.
#
# Scenarios
#  S1 init       winner stalled between mkdir and its pid write by --stall-ms.
#                This is the window clause (a) exists for. Swept over N and stall.
#                stall=0 is NOT a window test: the window is zero-width there, so the
#                cell is a live-owner/who-wins check. It is kept because the VOID rule
#                in trial_init now demonstrates that rather than assuming it.
#  S2 longstall  the same, stall set LONGER than clause (a)'s own bounded backoff
#                (20 attempts x 2 ms = 40 ms). Review attack 1: a fixed backoff
#                cannot tell a descheduled winner from a dead one.
#  S3 aba        winner publishes a lock owned by an ALREADY-EXITED pid, so
#                reclamation is legitimate. Racer A reclaims immediately; racer B
#                classified stale at the same instant but is stalled 120 ms before
#                acting, so it acts on a stale observation. Review attack 2: the
#                quarantine rename is path-based, so B renames A's FRESH lock and
#                gets success instead of ENOENT. This is also the shape of the
#                third failure 10.5 names (a reclaimer removing a lock a third
#                process legitimately re-created).
#  S4 dualreclaim  two reclaimers with no asymmetry at all, to separate "simultaneous
#                reclamation" from "reclamation on a stale observation".
#
# Metric: how many processes log `owner` in one trial. 1 is correct.
#
# ROUND 31 CORRECTED THE SECOND HALF OF THIS COMMENT, WHICH WAS AN INTERPRETATION WEARING
# A DEFINITION. It read "2 is two resident workers each holding a ~340 MB model and racing
# the claim-rename" -- and that is a claim about two processes owning the session AT THE
# SAME TIME, which this script does not measure. It counts `owner` records. Nothing here
# recorded a release or compared two owners intervals, so the concurrency was asserted.
#
# It is derived instead by `lock_overlap.sh <traces_dir>`, which builds each owner an
# interval from its CLAIM -- `mkdir_ok` / `published`, NOT `owner` -- to its release, and
# proves the overlap where the traces allow: 4 of the 4 committed two-owner traces. The
# claim instant is the load-bearing part. A winner that has returned from mkdir(2) owns the
# lock; `owner` is where it FINISHES publishing, one injected stall later, which is why the
# review that read the winners `owner` record as its claim concluded a nested pair was
# sequential. That ordering is the whole premise of S1/S2: the racer misclassifies a winner
# that has ALREADY WON.
#
# `lockrace.py` now records `released` when a hold ends, so a re-run OBSERVES each interval
# rather than inferring its end from HOLD below. lock-owners.tsv predates that record.
#
# usage: run_lock.sh <reps>
#
# CORRECTED in round 5's review: this script used to resolve lockrace.py out of a
# private bench directory and invoke one user's absolute interpreter path. On any
# other checkout it failed outright, and on the author's machine it could run a STALE
# external copy of lockrace.py rather than the file committed beside it -- which
# silently voids the claim that every figure re-derives from the committed rig.
# Helpers now resolve relative to this script; RIG, PYTHON and OUT stay overridable so
# the original layout is still reachable (RIG=... PYTHON=... OUT=... run_lock.sh).
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RIG=${RIG:-$HERE}
PY=${PYTHON:-python3}
OUT=${OUT:-$RIG/out/lock}
mkdir -p "$OUT"
if [[ ! -f "$RIG/require.sh" ]]; then
  echo "run_lock.sh: missing $RIG/require.sh -- the input-validation rule lives there, and" >&2
  echo "this driver validates both its argument and its own output through it." >&2
  exit 2
fi
# shellcheck source=require.sh
. "$RIG/require.sh"
if ! declare -F require_uint >/dev/null; then
  echo "run_lock.sh: $RIG/require.sh defined no require_uint -- REPS would go unvalidated." >&2
  exit 2
fi

# ROUND 34 -- `REPS` WAS NOT VALIDATED, AND THE DRIVER REPORTED `DONE` OVER A SWEEP THAT WAS
# NOT THE SWEEP. Every trial below runs inside `for r in $(seq 1 "$REPS")`, and neither
# `seq`s output nor its status was inspected. The review that found this said `0` and `abc`
# both produce no trials. MEASURED ON THIS MACHINE, ONE HALF OF THAT IS RIGHT AND THE OTHER
# HALF IS WORSE THAN STATED, because /usr/bin/seq here is BSD seq and BSD seq COUNTS DOWN:
#
#   $(seq 1 abc)  -> nothing, rc=2. `run_lock.sh abc` ran ZERO trials, left a header-only
#                    owners.tsv, printed DONE and exited 0. Exactly as reviewed.
#   $(seq 1 0)    -> `1` then `0`, rc=0. `run_lock.sh 0` did NOT run an empty sweep -- it
#                    ran TWO reps of every cell, one of them numbered `0`, and published 120
#                    trials with an out-of-range rep id as the documented 1200-trial sweep.
#                    That is not a run that produced nothing; it is a run that produced rows
#                    the document has no denominator for, which is the direction this rig
#                    treats as the dangerous one.
#   $(seq 1 -1)   -> `1 0 -1`, three reps, same shape again.
#
# So the premise holds -- an unvalidated count lets this driver report a finished run over a
# result set that is not the documented one -- and the mechanism is stated here as measured
# rather than as reviewed. Both ends are closed: the ARGUMENT before the sweep, through the
# shared range check, and the RESULT after it, through the shared record count and a per-cell
# rep-set check that would have caught the rep numbered `0` on its own.
require_uint "run_lock.sh" "reps (argument 1)" "${1:-20}" 1 || {
  echo "run_lock.sh: reps is the repetition count of every cell in the sweep, and it must" >&2
  echo "be a positive integer. On this machine seq(1) is BSD seq: it cannot count to 'abc'" >&2
  echo "(so every loop is empty and the run records nothing) and it counts DOWN to 0 or a" >&2
  echo "negative bound (so the run records reps this experiment does not have). Neither is" >&2
  echo "the documented sweep." >&2
  exit 2; }
REPS=${1:-20}
HOLD=500
RESULTS="$OUT/owners.tsv"
# A RESULT THAT WAS NEVER WRITTEN IS NOT A RESULT. Both writes were unchecked, so an
# unwritable or full output filesystem let all 1200 trials run to completion, every emit
# fail, and the closing `echo DONE` exit 0 -- presenting a missing or truncated owners.tsv
# as a finished run. The header is checked here; emit() below aborts the run on the first
# append it cannot make, rather than continuing for another 1199 trials it cannot record.
printf 'scenario\tprotocol\tN\tstall_ms\trep\towners\n' > "$RESULTS" || {
  echo "run_lock.sh: cannot write the header to $RESULTS -- refusing to run 1200 trials" >&2
  echo "that could not be recorded." >&2
  exit 2; }

# EMITS counts the appends this run MADE, so the closing check compares the driver`s own
# count of what it did against the file`s count of what arrived, and hand-carries neither.
# (The alternative was a literal 60 cells x REPS, which is the shape of every drifting
# constant this rig has removed.)
EMITS=0
emit() { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" >> "$RESULTS" || {
    echo "run_lock.sh: cannot append to $RESULTS -- aborting; the run so far is incomplete" >&2
    exit 2; }
  EMITS=$((EMITS + 1)); }

# `awk ... | wc -l` counts 0 just as happily over a log that does not exist as over one
# in which nobody claimed ownership, and `wc` succeeds either way -- so a trial whose
# python never ran at all (wrong PYTHON, missing lockrace.py) emitted owners=0, and
# summarise.sh scored 1200 staging failures as 1200 protocol failures. Every role ends
# by recording exactly one of owner/lost/gave_up, so a log with none of them is a trial
# that did not happen. That is VOID -- the same verdict the staging checks already give
# -- and never a protocol result.
#
# ROUND 15: "at least one process recorded an outcome" is the WRONG QUANTIFIER, and it
# fails in the direction that produces a false pass. `wait` returns when the last
# background job exits, not when they all SUCCEEDED, so a racer whose interpreter never
# started, or that died mid-election, is invisible: the survivors still record their
# outcomes, one of them still records `owner`, and the trial scores owners=1 -- a clean
# result from a race that was never run at the width it claims. It bites hardest exactly
# where the evidence is thinnest, at the N=16 S5 cells, where fifteen of sixteen racers
# could be missing and the cell would still read as a pass.
#
# So the check is now per-PARTICIPANT and exact: the expected number of processes must
# each record EXACTLY ONE terminal outcome. Verified against every committed lock sample
# log (S1 N2 -> 3, S2 N4 -> 5, S3 -> 2, S5 N16 -> 16, none with a duplicate), including
# the two-owner failures, so the rule does not soften a single published result.
#
# THIS REQUIRED A CHANGE IN THE PRODUCER TOO, and that coupling is the point: until
# round 15 `elect_current()` could return on `rmdir_failed` having recorded NO terminal
# outcome at all, so a racer that legitimately dropped out was indistinguishable here
# from a racer that never ran. Validating participation without fixing that would have
# VOIDed correct trials. See lockrace.py's rmdir_failed branch.
#
# The dead-owner `winner` in S3/S4/S6 is NOT a participant: it stages an incumbent and
# exits without electing anything, so it records `published`/`pid_written` and no
# terminal. Callers pass the number of processes that actually run an election.
count_owners() {   # log expected_participants -> owner count, or VOID
  local log=$1 want=$2
  if [[ ! -s "$log" ]] || ! awk -F'\t' '$7=="owner"||$7=="lost"||$7=="gave_up"{f=1}
                                        END{exit !f}' "$log"; then
    echo "$log: no process recorded an outcome -- trial VOID" >&2
    printf 'VOID\n'
    return
  fi
  local census
  census=$(awk -F'\t' -v want="$want" '
    $7=="owner"||$7=="lost"||$7=="gave_up" { t[$6]++ }
    END {
      np = 0; multi = 0
      for (p in t) { np++; if (t[p] > 1) { multi++; dup = dup " " p "(x" t[p] ")" } }
      printf "%d %d%s", np, multi, dup
    }' "$log")
  local np=${census%% *} rest=${census#* }
  local multi=${rest%% *}
  if [[ $np -ne $want ]]; then
    echo "$log: $np of $want participants recorded a terminal outcome -- trial VOID" >&2
    echo "  (a racer that never started or died mid-election leaves the survivors" >&2
    echo "   looking like a clean 1-owner trial; it is a trial that did not happen)" >&2
    printf 'VOID\n'
    return
  fi
  if [[ ${multi:-0} -ne 0 ]]; then
    echo "$log: a participant recorded more than one terminal outcome --" >&2
    echo "  ${rest#* } -- the outcome census is not a partition; trial VOID" >&2
    printf 'VOID\n'
    return
  fi
  awk -F'\t' '$7=="owner"' "$log" | wc -l | tr -d ' '
}

newdir() {
  local d="$OUT/$1"; rm -rf "$d"; mkdir -p "$d"; printf '%s\n' "$d"
}

# The winner's publication is COMPLETE at `pid_written` (current/spec: the mkdir is
# done AND the pid is in it) or at `published` (proposed: the generation symlink
# exists). S3, S4 and S6 need the incumbent's record to be on disk before a racer
# looks -- a racer that arrives first sees an EMPTY directory, wins uncontested, and
# the trial degenerates into S5's who-wins control while still producing owners=1.
# That is indistinguishable from a genuine pass, so it must be a fact, not a sleep.
await_publication() {   # log protocol -> 0 published, 1 timed out
  local log=$1 pr=$2 pat waited=0
  if [[ $pr == proposed ]]; then pat='published'; else pat='pid_written'; fi
  until grep -q "$pat" "$log" 2>/dev/null; do
    sleep 0.002
    waited=$((waited + 1))
    [[ $waited -ge 1000 ]] && return 1
  done
  return 0
}

# ---- S1 / S2: winner stalls in the mkdir -> pid-write window, N racers pile in
trial_init() {   # proto N stall rep scenario
  local pr=$1 n=$2 stall=$3 rep=$4 sc=$5
  local dir; dir=$(newdir "$sc-$pr-N$n-s$stall-r$rep")
  local log="$dir/log.tsv"; : > "$log"
  local bar="$dir/barrier"; mkdir -p "$bar"
  "$PY" "$RIG/lockrace.py" --dir "$dir" --log "$log" --role winner --protocol "$pr" \
      --stall-ms "$stall" --hold-ms "$HOLD" --trial "$rep" --label "$sc" \
      --barrier-dir "$bar" --barrier-n "$n" &
  # TWO-WAY barrier, not a one-way wait. Waiting for the winner's own claim record
  # is still not enough: after that grep succeeds each racer has to start a fresh
  # Python interpreter, tens of ms, while the window under test is 0-5 ms -- so the
  # winner would write its pid first and the CLEAN cells would quietly degenerate
  # into an ordinary live-owner check. The winner now blocks after claiming until
  # `barrier-n` racers have each announced they are at their protocol read, and only
  # then applies the stall and writes the pid. `--barrier-dir` is per-trial.
  local waited=0
  until grep -qE 'mkdir_ok|published' "$log" 2>/dev/null; do
    sleep 0.002
    waited=$((waited + 1))
    if [[ $waited -ge 1000 ]]; then
      echo "$sc $pr N$n s$stall r$rep: winner never claimed -- trial VOID" >&2
      wait
      emit "$sc" "$pr" "$n" "$stall" "$rep" "VOID"
      return
    fi
  done
  local i
  for i in $(seq 1 "$n"); do
    "$PY" "$RIG/lockrace.py" --dir "$dir" --log "$log" --role racer --protocol "$pr" \
        --hold-ms "$HOLD" --trial "$rep" --label "$sc" --barrier-dir "$bar" &
  done
  wait
  # Staging failure must NOT be scored as a protocol result. The winner records
  # `barrier_timeout` if it never collected N acknowledgements; a racer records
  # `observe_timeout` if it never saw the state it was supposed to observe. Either
  # one voids the trial, and summarise.sh excludes VOID from both the numerator and
  # the denominator.
  if grep -qE 'barrier_timeout|observe_timeout|release_timeout' "$log" 2>/dev/null; then
    echo "$sc $pr N$n s$stall r$rep: staging never established the window -- trial VOID" >&2
    emit "$sc" "$pr" "$n" "$stall" "$rep" "VOID"
    return
  fi
  # ROUND 11. The barrier above stages the OBSERVATION; it does not stage the ELECTION
  # READ. After GO the winner applies its stall and writes its pid while each racer,
  # released by the same token, performs its own fresh read -- and that second read is
  # what decides the trial. So a clean cell could still be an ordinary live-owner check.
  #
  # The answer is detection, not a sixth staging mechanism. Every deciding read now
  # reports itself (`election_read ... saw_window=`), and it carries the inode of the
  # lock it read, so "inside the WINNER's window" is distinguishable from "saw some
  # pid-less lock another racer had just created". A trial in which no racer's deciding
  # read landed in the winner's window did not test the window, and is VOID.
  #
  # EXPECT THIS TO VOID MOST OF THE stall=0 CELL, and read that as the rule working
  # rather than failing. At --stall-ms 0 the winner writes its pid immediately after
  # releasing the barrier, so the interval a racer must land in is zero-width: no
  # staging can place a read inside it, and a read that lands there did so by luck.
  # The cell is therefore a live-owner/who-wins check with a chance of being a window
  # test, and its surviving trials are a self-selected sample, not a swept one. The doc
  # now says that instead of counting the cell as window evidence.
  #
  # `proposed` is exempt because it has no pid-less state to enter -- not because its
  # staging is trusted. S1/S2 are structurally vacuous for it either way.
  if [[ $pr != proposed ]]; then
    local wino staged
    wino=$(awk -F'\t' '$5=="winner" && $7=="mkdir_ok" {print $8}' "$log" 2>/dev/null \
           | sed -n 's/.*ino=\([0-9-]*\).*/\1/p' | head -1)
    staged=$(awk -F'\t' -v i="${wino:-none}" \
      '$5=="racer" && $7=="election_read" && $8 ~ /(^| )saw_window=yes( |$)/ \
       && $8 ~ ("(^| )ino=" i "( |$)")' "$log" 2>/dev/null | wc -l | tr -d ' ')
    if [[ ${staged:-0} -eq 0 ]]; then
      echo "$sc $pr N$n s$stall r$rep: no racer's election read entered the winner's window -- trial VOID" >&2
      emit "$sc" "$pr" "$n" "$stall" "$rep" "VOID"
      return
    fi
  fi
  # The live winner runs an election too, so it is the (n + 1)th participant.
  emit "$sc" "$pr" "$n" "$stall" "$rep" "$(count_owners "$log" $((n + 1)))"
}

# ---- S3: legitimate reclamation, one reclaimer acting on a STALE observation
#
# CORRECTED in round 3's review, and NOT YET RE-RUN. The earlier version slept a flat
# 4 ms between launching B and launching A, and then asserted that B had classified the
# dead generation before A superseded it. 4 ms guarantees nothing: B is a fresh Python
# interpreter and can be descheduled straight through startup, in which case it observes
# A's LIVE record instead and the trial never exercises a stale observation at all.
#
# That matters asymmetrically. Under `current`/`spec` a mis-staged trial degenerates
# into S4 and yields 1 owner, so the published 20/20 two-owner result is its own proof
# the staging held. Under `proposed` a mis-staged trial ALSO yields 1 owner -- the
# elector sees a live owner and records `lost` -- so it is indistinguishable from a
# genuine pass, and `proposed`'s S3 cell cannot distinguish them.
#
# The fix is to wait for B's own `classified_stale` record rather than for the clock,
# and to fail the trial loudly if it never appears. The committed lock-owners.tsv was
# produced under the old 4 ms sleep; re-running S3 is the open item.
#
# ROUND 5 found the SECOND fixed sleep in the same function, which the previous repair
# left in place: the 50 ms between launching the winner and launching B was staging the
# incumbent's publication by the clock. Now gated on `pid_written`/`published`.
#
# ROUND 24 -- THE LAST CLOCK IN THIS FUNCTION, AND THE SIXTH STAGING REPAIR TO THIS FILE.
# Waiting for B's `classified_stale` proves that B OBSERVED a dead generation. It does
# not prove that A RECLAIMED before B's 120 ms classify stall expired. A is a fresh
# Python interpreter; if it starts slowly or is descheduled past 120 ms then B reclaims
# first and A merely loses -- owners=1, the SILENT FALSE PASS this repair exists to
# eliminate, and for `proposed` indistinguishable from a genuine pass exactly as 2.6
# already explains of every mis-staged S3 trial.
#
# So the clock is replaced by an explicit RELEASE BARRIER, the same two-phase file-token
# shape the S1/S2 barrier ended up with rather than a seventh mechanism: B holds after
# recording `classified_stale`; A drops the GO token only once its own election has
# returned a successful reclaim; B is then released and commits the ABA act. Either side
# failing records its own marker -- `classify_hold_timeout` on B's side,
# `classify_hold_norelease` on A's -- and both VOID the trial, which summarise.sh
# excludes from the numerator and the denominator alike.
#
# THIS DOES NOT MAKE THE COMMITTED NUMBERS RIGHT. lock-owners.tsv predates every staging
# fix in this file, including this one, so row 21's S3 cell stays `[inferred]` and the
# re-run stays the open item it has been since round 3. The document already says
# inspection is not converging on this function; the change is kept minimal for that
# reason.
trial_aba() {    # proto rep
  local pr=$1 rep=$2 sc=S3_aba
  local dir; dir=$(newdir "$sc-$pr-r$rep")
  local log="$dir/log.tsv"; : > "$log"
  # Per-trial, like --barrier-dir: a token left behind by one trial would release the
  # next trial's B before its A had reclaimed, which is the failure being fixed.
  local hold="$dir/holdbar"; mkdir -p "$hold"
  "$PY" "$RIG/lockrace.py" --dir "$dir" --log "$log" --role winner --protocol "$pr" \
      --dead-owner --hold-ms "$HOLD" --trial "$rep" --label "$sc" &
  if ! await_publication "$log" "$pr"; then
    echo "S3 $pr r$rep: incumbent never published -- trial VOID" >&2
    wait
    emit "$sc" "$pr" 2 0 "$rep" "VOID"
    return
  fi
  # B classifies now, then PARKS on the barrier until A's reclaim is in the log.
  "$PY" "$RIG/lockrace.py" --dir "$dir" --log "$log" --role racer --protocol "$pr" \
      --classify-hold-dir "$hold" --classify-hold-role hold \
      --hold-ms "$HOLD" --trial "$rep" --label "$sc" &
  # Wait for the OBSERVATION, not for the clock. 2 s is a deadlock guard.
  local waited=0
  until grep -q 'classified_stale' "$log" 2>/dev/null; do
    sleep 0.002
    waited=$((waited + 1))
    if [[ $waited -ge 1000 ]]; then
      echo "S3 $pr r$rep: B never recorded classified_stale -- trial VOID" >&2
      wait
      emit "$sc" "$pr" 2 0 "$rep" "VOID"
      return
    fi
  done
  # A classifies and reclaims on top of an observation B has already made, then releases B.
  "$PY" "$RIG/lockrace.py" --dir "$dir" --log "$log" --role racer --protocol "$pr" \
      --classify-hold-dir "$hold" --classify-hold-role release \
      --hold-ms "$HOLD" --trial "$rep" --label "$sc" &
  wait
  # THE BARRIER'S OWN FAILURES, checked before the trial is scored. Without this the
  # barrier would be an annotation rather than a guard -- the shape summarise.sh's VOID
  # check and verify_fires.sh both had to have closed for them. `classify_hold_timeout`
  # is B waiting out the guard because A never reclaimed; `classify_hold_norelease` is
  # A finishing without a reclaim to release. Either one means the ABA ordering was not
  # staged, so the trial is not a protocol result.
  if grep -qE 'classify_hold_timeout|classify_hold_norelease' "$log" 2>/dev/null; then
    echo "S3 $pr r$rep: the release barrier never ordered A's reclaim before B's act -- trial VOID" >&2
    emit "$sc" "$pr" 2 0 "$rep" "VOID"
    return
  fi
  # And the POSITIVE requirement, which is not the same statement: the two markers above
  # are absent when the barrier failed AND when it never ran at all (a racer whose
  # interpreter died before `classified_stale`, say). The trial is only staged if A's
  # release and B's release-observation are both in the log.
  if ! grep -q 'classify_hold_release' "$log" 2>/dev/null \
     || ! grep -q 'classify_hold_go_seen' "$log" 2>/dev/null; then
    echo "S3 $pr r$rep: no release barrier in the log at all -- trial VOID" >&2
    emit "$sc" "$pr" 2 0 "$rep" "VOID"
    return
  fi
  # A and B are the participants; the --dead-owner winner stages an incumbent and
  # records no terminal outcome of its own.
  emit "$sc" "$pr" 2 0 "$rep" "$(count_owners "$log" 2)"
}

# ---- S4: two reclaimers, no asymmetry
#
# CORRECTED in round 5's review, and NOT YET RE-RUN. The 50 ms sleep here staged the
# dead incumbent's publication by the clock. If the winner's fresh interpreter is slow,
# both reclaimers see an empty directory, one wins, owners=1 -- S5's control result
# wearing S4's label, and for `proposed` in particular a mis-staged trial and a genuine
# pass are the same number. Now gated on the winner's own publication record.
trial_dual() {   # proto rep
  local pr=$1 rep=$2 sc=S4_dualreclaim
  local dir; dir=$(newdir "$sc-$pr-r$rep")
  local log="$dir/log.tsv"; : > "$log"
  "$PY" "$RIG/lockrace.py" --dir "$dir" --log "$log" --role winner --protocol "$pr" \
      --dead-owner --hold-ms "$HOLD" --trial "$rep" --label "$sc" &
  if ! await_publication "$log" "$pr"; then
    echo "S4 $pr r$rep: incumbent never published -- trial VOID" >&2
    wait
    emit "$sc" "$pr" 2 0 "$rep" "VOID"
    return
  fi
  local i
  for i in 1 2; do
    "$PY" "$RIG/lockrace.py" --dir "$dir" --log "$log" --role racer --protocol "$pr" \
        --hold-ms "$HOLD" --trial "$rep" --label "$sc" &
  done
  wait
  # two reclaimers; the --dead-owner winner is staging, not a participant
  emit "$sc" "$pr" 2 0 "$rep" "$(count_owners "$log" 2)"
}

# ---- S5: no incumbent at all. N racers from an empty dir. This is the
#      ALREADY-MEASURED race (the mkdir won it 8/8, [obs]) -- included so the two
#      races are visibly separate: S5 is about WHO WINS, S1-S4 are about
#      MISCLASSIFYING the winner. A protocol must pass both.
trial_scratch() {  # proto N rep
  local pr=$1 n=$2 rep=$3 sc=S5_scratch
  local dir; dir=$(newdir "$sc-$pr-N$n-r$rep")
  local log="$dir/log.tsv"; : > "$log"
  local i
  for i in $(seq 1 "$n"); do
    "$PY" "$RIG/lockrace.py" --dir "$dir" --log "$log" --role racer --protocol "$pr" \
        --hold-ms "$HOLD" --trial "$rep" --label "$sc" &
  done
  wait
  # no incumbent at all: the n racers are the whole field
  emit "$sc" "$pr" "$n" 0 "$rep" "$(count_owners "$log" "$n")"
}

# ---- S6: legitimate reclamation under CONTENTION. A dead incumbent and N racers,
#      no asymmetry. For `proposed` this is the real test of exclusive-create
#      supersession; S1/S2 are structurally vacuous for it (see the doc).
#
# CORRECTED in round 5's review, and NOT YET RE-RUN -- same defect as S4, and it bites
# hardest here, because S6 is the largest block of `proposed` trials the document
# counts as genuinely exercising reclamation.
trial_deadN() {  # proto N rep
  local pr=$1 n=$2 rep=$3 sc=S6_deadN
  local dir; dir=$(newdir "$sc-$pr-N$n-r$rep")
  local log="$dir/log.tsv"; : > "$log"
  "$PY" "$RIG/lockrace.py" --dir "$dir" --log "$log" --role winner --protocol "$pr" \
      --dead-owner --hold-ms "$HOLD" --trial "$rep" --label "$sc" &
  if ! await_publication "$log" "$pr"; then
    echo "S6 $pr N$n r$rep: incumbent never published -- trial VOID" >&2
    wait
    emit "$sc" "$pr" "$n" 0 "$rep" "VOID"
    return
  fi
  local i
  for i in $(seq 1 "$n"); do
    "$PY" "$RIG/lockrace.py" --dir "$dir" --log "$log" --role racer --protocol "$pr" \
        --hold-ms "$HOLD" --trial "$rep" --label "$sc" &
  done
  wait
  # n reclaimers; the --dead-owner winner is staging, not a participant
  emit "$sc" "$pr" "$n" 0 "$rep" "$(count_owners "$log" "$n")"
}

for pr in current spec proposed; do
  for n in 2 4 8; do
    for stall in 0 5 50; do
      for r in $(seq 1 "$REPS"); do trial_init "$pr" "$n" "$stall" "$r" S1_init; done
    done
  done
  for stall in 200 1000; do
    for r in $(seq 1 "$REPS"); do trial_init "$pr" 4 "$stall" "$r" S2_longstall; done
  done
  for r in $(seq 1 "$REPS"); do trial_aba "$pr" "$r"; done
  for r in $(seq 1 "$REPS"); do trial_dual "$pr" "$r"; done
  for n in 2 4 8 16; do
    for r in $(seq 1 "$REPS"); do trial_scratch "$pr" "$n" "$r"; done
  done
  for n in 2 4 8; do
    for r in $(seq 1 "$REPS"); do trial_deadN "$pr" "$n" "$r"; done
  done
done

# ---- THE RESULT, CHECKED BEFORE `DONE` IS PRINTED.
#
# `DONE` used to be the last line of this file with nothing between it and the sweep, so
# every way of producing no rows -- an unvalidated REPS, a sweep whose every cell was
# skipped -- reported a finished run. Three checks, none of them hand-carrying a constant:
#
#   1. the file holds at least one record BEYOND its header (the shared record count; the
#      header check at the top of this file only establishes that the header could be
#      WRITTEN, which is also true of a run that produced nothing else);
#   2. as many records arrived as this driver appended -- EMITS is its own count of what it
#      did, so a lost append is visible without knowing how many there should have been;
#   3. every cell in the sweep carries the rep set 1..REPS exactly once. This is the check
#      that would have caught an empty `seq` without anyone validating REPS: a cell present
#      with the wrong reps, or a cell of duplicates, is a sweep that is not the sweep the
#      document quotes. Cells are partitioned with ARRAY SUBSCRIPTS (SUBSEP-joined), not
#      with `==`: on /usr/bin/awk here (BWK awk 20200816) a trailing U+2032 PRIME is
#      INVISIBLE to the comparison operators, while a subscript compares by identity and
#      sees it.
if ! require_data_rows "run_lock.sh" "$RESULTS" 1; then
  echo "run_lock.sh: the sweep produced no trials. reps=$REPS." >&2
  exit 2
fi
rows=$(awk 'END { print NR - 1 }' "$RESULTS")
if [[ ${rows:-0} -ne $EMITS ]]; then
  echo "run_lock.sh: appended $EMITS trial(s) and $RESULTS holds ${rows:-0} record(s)." >&2
  echo "The recorded run is not the run that happened." >&2
  exit 2
fi
if ! awk -F'\t' -v reps="$REPS" '
  NR == 1 { next }
  { key = $1 SUBSEP $2 SUBSEP $3 SUBSEP $4
    cells[key] = 1
    seen[key SUBSEP $5]++ }
  END {
    ncells = 0; bad = 0
    for (k in cells) {
      ncells++
      for (r = 1; r <= reps; r++) {
        split(k, f, SUBSEP)
        if (!((k SUBSEP r) in seen)) {
          printf "run_lock.sh: cell %s/%s/N%s/s%s is missing rep %d.\n",
            f[1], f[2], f[3], f[4], r > "/dev/stderr"
          bad = 1
        } else if (seen[k SUBSEP r] > 1) {
          printf "run_lock.sh: cell %s/%s/N%s/s%s has rep %d recorded %d times.\n",
            f[1], f[2], f[3], f[4], r, seen[k SUBSEP r] > "/dev/stderr"
          bad = 1
        }
      }
    }
    for (kr in seen) {
      n = split(kr, g, SUBSEP)
      if (g[n] + 0 < 1 || g[n] + 0 > reps) {
        printf "run_lock.sh: a cell carries rep %s, which is outside 1..%d.\n",
          g[n], reps > "/dev/stderr"
        bad = 1
      }
    }
    if (bad) exit 1
    printf "run_lock.sh: %d cells x %d reps = %d trials recorded.\n",
      ncells, reps, ncells * reps
  }' "$RESULTS"; then
  echo "run_lock.sh: the recorded sweep is not the sweep this driver ran. NOT a pass." >&2
  exit 2
fi
echo DONE
