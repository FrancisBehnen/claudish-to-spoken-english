#!/bin/bash
# The two arms added after the main sweep, so the main sweep was never edited while
# running. C15c settles whether clause (ii) keeps a correctness role once clause (iv)
# is present; C17 shows the one line that defeats clause (iv).
# Paths resolve from this script, not from a private bench dir -- see run_preempt.sh.
# A failed configuration is fatal rather than recorded as an empty path -- see the
# `tail -1` note in run_all_preempt.sh.
set -u -o pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RIG=${RIG:-$HERE}
OUT=${OUT:-$RIG/out}
export RIG OUT
mkdir -p "$OUT"
for cfg in C15c_norecheck_death_pgid C17_setsid_player; do
  if ! d=$(bash "$RIG/run_preempt.sh" "$cfg" 12 2>>"$OUT/run.err" | tail -1); then
    echo "run_tail.sh: $cfg FAILED -- see $OUT/run.err. Not recorded." >&2
    exit 2
  fi
  if [[ ! -d "$d" ]]; then
    echo "run_tail.sh: $cfg returned '$d', which is not a run directory." >&2
    exit 2
  fi
  printf '%s\t%s\n' "$cfg" "$d" >> "$OUT/RUNS.txt"
  echo "$cfg -> $d"
done
echo TAILDONE
