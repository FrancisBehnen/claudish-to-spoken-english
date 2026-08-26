#!/bin/bash
# Paths resolve from this script, not from a private bench dir -- see run_preempt.sh.
# A failed configuration is fatal rather than announced as an empty path -- see the
# `tail -1` note in run_all_preempt.sh. This script does not write RUNS.txt at all, so
# its printed path IS its whole output, and "$cfg -> " with nothing after it read as a
# run that had happened.
set -u -o pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RIG=${RIG:-$HERE}
OUT=${OUT:-$RIG/out}
export RIG OUT
mkdir -p "$OUT"
for cfg in C13b_perplayer_sametiming C16a_pending_sweepfirst \
           C15c_norecheck_death_pgid C17_setsid_player; do
  echo "=== $cfg ==="
  if ! d=$(bash "$RIG/run_preempt.sh" "$cfg" 12 2>>"$OUT/run.err" | tail -1); then
    echo "run_missing.sh: $cfg FAILED -- see $OUT/run.err." >&2
    exit 2
  fi
  if [[ ! -d "$d" ]]; then
    echo "run_missing.sh: $cfg returned '$d', which is not a run directory." >&2
    exit 2
  fi
  echo "$cfg -> $d"
done
echo MISSINGDONE
