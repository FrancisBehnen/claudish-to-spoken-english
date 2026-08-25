#!/bin/bash
set -u
RIG="$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25"
for cfg in C16a_pending_sweepfirst C16b_pending_pubfirst; do
  d=$(bash "$RIG/run_preempt.sh" "$cfg" 12 2>>"$RIG/out/run.err" | tail -1)
  printf '%s\t%s\n' "$cfg" "$d" >> "$RIG/out/RUNS.txt"
  echo "$cfg -> $d"
done
echo C16DONE
