#!/bin/bash
# The two arms added after the main sweep, so the main sweep was never edited while
# running. C15c settles whether clause (ii) keeps a correctness role once clause (iv)
# is present; C17 shows the one line that defeats clause (iv).
set -u
RIG="$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25"
for cfg in C15c_norecheck_death_pgid C17_setsid_player; do
  d=$(bash "$RIG/run_preempt.sh" "$cfg" 12 2>>"$RIG/out/run.err" | tail -1)
  printf '%s\t%s\n' "$cfg" "$d" >> "$RIG/out/RUNS.txt"
  echo "$cfg -> $d"
done
echo TAILDONE
