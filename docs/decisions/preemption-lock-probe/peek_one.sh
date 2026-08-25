#!/bin/bash
# Outcome summary for one configuration, by attribution and audible duration.
set -u
RIG="$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25"
for c in "$@"; do
  d=$(awk -v c="$c" '$1==c{print $2}' "$RIG/out/RUNS.txt")
  [[ -n "${d:-}" && -d "$d" ]] || { echo "=== $c (not run) ==="; continue; }
  bash "$RIG/collect.sh" "$d" "$c" >/dev/null 2>&1
  echo "=== $c ==="
  awk -F'\t' 'NR>1{
    a="?";
    if ($14=="-31"||$17=="31") a="sweep-record";
    else if ($14=="-14"||$17=="14") a="sweep-pgid";
    else if ($14=="-30"||$17=="30") a="claim-kill";
    else if ($14=="-15"||$17=="15") a="hook-kill";
    else if ($14=="0"||$17=="0") a="NOTHING";
    else if ($13=="-") a="no-player";
    else if ($18=="0(never_started)") a="killed-before-exec";
    print "  "a"\t"$18"\t"$26 }' "$d/trials.tsv" | sort | uniq -c
done
