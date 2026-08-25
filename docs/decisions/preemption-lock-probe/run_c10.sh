#!/bin/bash
set -u
RIG="$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25"
for cfg in C10a_nopid_pidfile C10b_nopid_handle; do
  d=$(bash "$RIG/run_preempt.sh" "$cfg" 12 2>>"$RIG/out/run.err" | tail -1)
  printf '%s\t%s\n' "$cfg" "$d" >> "$RIG/out/RUNS.txt"
  echo "$cfg -> $d"
done
echo C10DONE
