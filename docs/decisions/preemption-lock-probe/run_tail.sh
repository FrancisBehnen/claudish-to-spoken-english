#!/bin/bash
# The two arms added after the main sweep, so the main sweep was never edited while
# running. C15c settles whether clause (ii) keeps a correctness role once clause (iv)
# is present; C17 shows the one line that defeats clause (iv).
# Paths resolve from this script, not from a private bench dir -- see run_preempt.sh.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RIG=${RIG:-$HERE}
OUT=${OUT:-$RIG/out}
export RIG OUT
mkdir -p "$OUT"
for cfg in C15c_norecheck_death_pgid C17_setsid_player; do
  d=$(bash "$RIG/run_preempt.sh" "$cfg" 12 2>>"$OUT/run.err" | tail -1)
  printf '%s\t%s\n' "$cfg" "$d" >> "$OUT/RUNS.txt"
  echo "$cfg -> $d"
done
echo TAILDONE
