#!/bin/bash
# Paths resolve from this script, not from a private bench dir -- see run_preempt.sh.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RIG=${RIG:-$HERE}
OUT=${OUT:-$RIG/out}
export RIG OUT
mkdir -p "$OUT"
for cfg in C13b_perplayer_sametiming C16a_pending_sweepfirst \
           C15c_norecheck_death_pgid C17_setsid_player; do
  echo "=== $cfg ==="
  d=$(bash "$RIG/run_preempt.sh" "$cfg" 12 2>>"$OUT/run.err" | tail -1)
  echo "$cfg -> $d"
done
echo MISSINGDONE
