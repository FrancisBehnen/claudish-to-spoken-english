#!/bin/bash
# Outcome summary for one configuration, by attribution and player-process runtime.
# The second column printed is $18, pstart_to_pend_s, read BY POSITION: the stale player
# process own start-to-end interval. It was called "audible duration" here and audible_s
# in the schema; the player is a stub that opens no audio device, so neither name was a
# fact about sound.
# collect.sh beside this script; OUT names the run tree. Overridable: RIG, OUT.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RIG=${RIG:-$HERE}
OUT=${OUT:-$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25/out}
[[ -f "$OUT/RUNS.txt" ]] || { echo "peek_one.sh: no $OUT/RUNS.txt." >&2; exit 2; }
for c in "$@"; do
  d=$(awk -v c="$c" '$1==c{print $2}' "$OUT/RUNS.txt")
  [[ -n "${d:-}" && -d "$d" ]] || { echo "=== $c (not run) ==="; continue; }
  # `>/dev/null 2>&1` discarded both the collector's output and its diagnosis, and the
  # summary below was then printed from whatever trials.tsv that directory already had
  # -- an earlier collection's numbers under today's heading. Failure is now visible
  # and the stale rows are not printed at all.
  if ! bash "$RIG/collect.sh" "$d" "$c" >/dev/null; then
    echo "=== $c (COLLECTION FAILED -- any rows here would be stale) ==="
    continue
  fi
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
