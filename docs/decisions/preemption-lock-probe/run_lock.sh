#!/bin/bash
# Row 21 driver. Every scenario runs against all THREE protocols, so a fix is
# demonstrated rather than asserted and a protocol that fails is visible beside one
# that passes.
#
# Scenarios
#  S1 init       winner stalled between mkdir and its pid write by --stall-ms.
#                This is the window clause (a) exists for. Swept over N and stall.
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
# Metric: how many processes log `owner` in one trial. 1 is correct; 2 is two
# resident workers each holding a ~340 MB model and racing the claim-rename.
#
# usage: run_lock.sh <reps>
set -u
RIG="$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25"
PY=/Users/francis.behnen/homebrew/bin/python3
OUT="$RIG/out/lock"
mkdir -p "$OUT"
REPS=${1:-20}
HOLD=500
RESULTS="$OUT/owners.tsv"
printf 'scenario\tprotocol\tN\tstall_ms\trep\towners\n' > "$RESULTS"

emit() { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" >> "$RESULTS"; }

count_owners() { awk -F'\t' '$7=="owner"' "$1" | wc -l | tr -d ' '; }

newdir() {
  local d="$OUT/$1"; rm -rf "$d"; mkdir -p "$d"; printf '%s\n' "$d"
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
  if grep -qE 'barrier_timeout|observe_timeout' "$log" 2>/dev/null; then
    echo "$sc $pr N$n s$stall r$rep: staging never established the window -- trial VOID" >&2
    emit "$sc" "$pr" "$n" "$stall" "$rep" "VOID"
    return
  fi
  emit "$sc" "$pr" "$n" "$stall" "$rep" "$(count_owners "$log")"
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
trial_aba() {    # proto rep
  local pr=$1 rep=$2 sc=S3_aba
  local dir; dir=$(newdir "$sc-$pr-r$rep")
  local log="$dir/log.tsv"; : > "$log"
  "$PY" "$RIG/lockrace.py" --dir "$dir" --log "$log" --role winner --protocol "$pr" \
      --dead-owner --hold-ms "$HOLD" --trial "$rep" --label "$sc" &
  sleep 0.05
  # B classifies now, then sits on the decision for 120 ms
  "$PY" "$RIG/lockrace.py" --dir "$dir" --log "$log" --role racer --protocol "$pr" \
      --classify-stall-ms 120 --hold-ms "$HOLD" --trial "$rep" --label "$sc" &
  # Wait for the OBSERVATION, not for the clock. B's classify stall is 120 ms, so
  # there is ample room; 2 s is a deadlock guard, not a timing assumption.
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
  # A classifies and reclaims immediately, on top of an observation B has already made
  "$PY" "$RIG/lockrace.py" --dir "$dir" --log "$log" --role racer --protocol "$pr" \
      --hold-ms "$HOLD" --trial "$rep" --label "$sc" &
  wait
  emit "$sc" "$pr" 2 0 "$rep" "$(count_owners "$log")"
}

# ---- S4: two reclaimers, no asymmetry
trial_dual() {   # proto rep
  local pr=$1 rep=$2 sc=S4_dualreclaim
  local dir; dir=$(newdir "$sc-$pr-r$rep")
  local log="$dir/log.tsv"; : > "$log"
  "$PY" "$RIG/lockrace.py" --dir "$dir" --log "$log" --role winner --protocol "$pr" \
      --dead-owner --hold-ms "$HOLD" --trial "$rep" --label "$sc" &
  sleep 0.05
  local i
  for i in 1 2; do
    "$PY" "$RIG/lockrace.py" --dir "$dir" --log "$log" --role racer --protocol "$pr" \
        --hold-ms "$HOLD" --trial "$rep" --label "$sc" &
  done
  wait
  emit "$sc" "$pr" 2 0 "$rep" "$(count_owners "$log")"
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
  emit "$sc" "$pr" "$n" 0 "$rep" "$(count_owners "$log")"
}

# ---- S6: legitimate reclamation under CONTENTION. A dead incumbent and N racers,
#      no asymmetry. For `proposed` this is the real test of exclusive-create
#      supersession; S1/S2 are structurally vacuous for it (see the doc).
trial_deadN() {  # proto N rep
  local pr=$1 n=$2 rep=$3 sc=S6_deadN
  local dir; dir=$(newdir "$sc-$pr-N$n-r$rep")
  local log="$dir/log.tsv"; : > "$log"
  "$PY" "$RIG/lockrace.py" --dir "$dir" --log "$log" --role winner --protocol "$pr" \
      --dead-owner --hold-ms "$HOLD" --trial "$rep" --label "$sc" &
  sleep 0.05
  local i
  for i in $(seq 1 "$n"); do
    "$PY" "$RIG/lockrace.py" --dir "$dir" --log "$log" --role racer --protocol "$pr" \
        --hold-ms "$HOLD" --trial "$rep" --label "$sc" &
  done
  wait
  emit "$sc" "$pr" "$n" 0 "$rep" "$(count_owners "$log")"
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
echo DONE
