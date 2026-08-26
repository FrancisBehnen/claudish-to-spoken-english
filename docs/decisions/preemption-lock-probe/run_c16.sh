#!/bin/bash
# Paths resolve from this script, not from a private bench dir -- see run_preempt.sh.
# A failed configuration is fatal rather than recorded as an empty path -- see the
# `tail -1` note in run_all_preempt.sh.
set -u -o pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RIG=${RIG:-$HERE}
OUT=${OUT:-$RIG/out}
export RIG OUT
mkdir -p "$OUT"
for cfg in C16a_pending_sweepfirst C16b_pending_pubfirst; do
  if ! d=$(bash "$RIG/run_preempt.sh" "$cfg" 12 2>>"$OUT/run.err" | tail -1); then
    echo "run_c16.sh: $cfg FAILED -- see $OUT/run.err. Not recorded." >&2
    exit 2
  fi
  if [[ ! -d "$d" ]]; then
    echo "run_c16.sh: $cfg returned '$d', which is not a run directory." >&2
    exit 2
  fi
  printf '%s\t%s\n' "$cfg" "$d" >> "$OUT/RUNS.txt"
  echo "$cfg -> $d"
done
echo C16DONE
