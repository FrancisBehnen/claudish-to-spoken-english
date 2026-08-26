#!/bin/bash
# Assemble the two committed evidence files from a completed pass.
# usage: assemble.sh <out_dir> <dest_dir>
#
# collect.sh -- the parser that produces the committed preemption-trials.tsv -- now
# resolves beside this script rather than out of a private bench directory, so a
# re-assembly cannot silently run a stale copy of it. Overridable with RIG=.
set -u
O=${1:?out dir}; DEST=${2:?dest dir}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
R=${RIG:-$HERE}
mkdir -p "$DEST"

first=1
: > "$DEST/preemption-trials.tsv"
while read -r cfg d; do
  [[ -n "${d:-}" ]] || continue
  bash "$R/collect.sh" "$d" "$cfg" > /dev/null
  if [[ $first == 1 ]]; then head -1 "$d/trials.tsv" >> "$DEST/preemption-trials.tsv"; first=0; fi
  tail -n +2 "$d/trials.tsv" >> "$DEST/preemption-trials.tsv"
done < "$O/RUNS.txt"

[[ -f "$O/lock/owners.tsv" ]] && cp "$O/lock/owners.tsv" "$DEST/lock-owners.tsv"
wc -l "$DEST/preemption-trials.tsv" "$DEST/lock-owners.tsv" 2>/dev/null
