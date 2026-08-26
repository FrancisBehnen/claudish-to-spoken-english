#!/bin/bash
# Paths resolve from this script, not from a private bench dir -- see run_preempt.sh.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RIG=${RIG:-$HERE}
OUT=${OUT:-$RIG/out}
export RIG OUT
mkdir -p "$OUT"
for cfg in C10a_nopid_pidfile C10b_nopid_handle; do
  d=$(bash "$RIG/run_preempt.sh" "$cfg" 12 2>>"$OUT/run.err" | tail -1)
  printf '%s\t%s\n' "$cfg" "$d" >> "$OUT/RUNS.txt"
  echo "$cfg -> $d"
done
echo C10DONE
