#!/bin/bash
# Show that the replication arm and the published arm agree, config for config.
# Both are collected with the SAME collector and the same adversarial predicate,
# so a disagreement would be about the runs and not about the derivation.
# (BWK awk will not accept a line break after a ternary ':', hence the long lines.)
# usage: compare_passes.sh <evidence_dir>
set -u
D=${1:?dir}
for f in preemption-trials-replication.tsv preemption-trials.tsv; do
  echo "-- $f"
  # An AGREEMENT check has to fail loudly when it has nothing to compare. awk aborts on
  # a file it cannot open and this script has no `set -e`, so a missing evidence file
  # printed its "-- <name>" heading, no rows underneath, and exited 0 -- which reads
  # exactly like the two passes agreeing on an empty set of disagreements. The column
  # comment below records that this comparison has already silently compared nothing
  # once, for a different reason; that is why it is checked rather than assumed.
  if [[ ! -f "$D/$f" || $(wc -l < "$D/$f") -lt 2 ]]; then
    echo "compare_passes.sh: $D/$f is missing or has no data rows -- nothing to compare." >&2
    exit 2
  fi
  # Columns, from the TSV header: 13 player_pid, 14 rc, 16 alive_s, 17 player_log_sig.
  # These offsets predated the insertion of Rdone_b and were reading player_pid as rc
  # and alive_s as player_log_sig, so every row scored "unknown" and this comparison
  # silently compared nothing.
  awk -F'\t' '$1=="config"{next}{ a="unknown"; if ($14=="-15"||$17=="15") a="hook-pid-kill"; else if ($14=="-30"||$17=="30") a="worker-claim-kill"; else if ($14=="-31"||$17=="31") a="election-sweep"; else if ($14=="0"||$17=="0") a="NOTHING-ran-to-end"; else if ($13=="-") a="no-player-spawned"; printf "%s\t%s\n", $1, a }' "$D/$f" \
    | sort | uniq -c | awk '{printf "   %-5s %-20s %s\n",$1"x",$2,$3}'
done
