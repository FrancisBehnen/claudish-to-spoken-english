#!/bin/bash
set -u
RIG="$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25"
N=${1:-12}
: > "$RIG/out/RUNS.txt"
for cfg in C1_prespawn C2_hookside C3_adversarial C4_noclaimkill C5_norecheck \
           C6_handle C7_noreap C8_orphan C9_ledger; do
  echo "=== $cfg ==="
  d=$(bash "$RIG/run_preempt.sh" "$cfg" "$N" 2>>"$RIG/out/run.err" | tail -1)
  printf '%s\t%s\n' "$cfg" "$d" >> "$RIG/out/RUNS.txt"
  echo "$cfg -> $d"
done
echo DONE
