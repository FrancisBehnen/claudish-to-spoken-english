#!/bin/bash
set -u
R="$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25"
while read -r cfg d; do
  [[ -n "${d:-}" ]] || continue
  bash "$R/collect.sh" "$d" "$cfg" > /dev/null
  echo "=== $cfg ==="
  awk -F'\t' 'NR==1{next}{printf "  t%-3s ord=%-32s hookB=%s/%s wclaim=%s/%s rc=%s plog=%s aud=%s\n",$2,$25,$20,$21,$22,$23,$13,$16,$17}' "$d/trials.tsv"
done < "$R/out/RUNS.txt"
