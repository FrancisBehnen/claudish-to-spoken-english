#!/bin/bash
# Show that pass 1 and pass 2 agree, config for config, using awk only.
# (BWK awk will not accept a line break after a ternary ':', hence the long lines.)
# usage: compare_passes.sh <evidence_dir>
set -u
D=${1:?dir}
for f in preemption-trials-pass1.tsv preemption-trials.tsv; do
  echo "-- $f"
  awk -F'\t' '$1=="config"{next}{ a="unknown"; if ($13=="-15"||$16=="15") a="hook-pid-kill"; else if ($13=="-30"||$16=="30") a="worker-claim-kill"; else if ($13=="-31"||$16=="31") a="election-sweep"; else if ($13=="0"||$16=="0") a="NOTHING-ran-to-end"; else if ($12=="-") a="no-player-spawned"; printf "%s\t%s\n", $1, a }' "$D/$f" \
    | sort | uniq -c | awk '{printf "   %-5s %-20s %s\n",$1"x",$2,$3}'
done
