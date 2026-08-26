#!/bin/bash
# collect.sh beside this script; OUT names the run tree. Overridable: RIG, OUT.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
R=${RIG:-$HERE}
O=${OUT:-$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25/out}
[[ -f "$O/RUNS.txt" ]] || { echo "peek.sh: no $O/RUNS.txt -- nothing to peek at." >&2; exit 2; }
while read -r cfg d; do
  [[ -n "${d:-}" ]] || continue
  # Same defect as assemble.sh, and it is worse in a script meant for reading by eye:
  # a run directory collected earlier still holds a trials.tsv, so a failed collection
  # printed the PREVIOUS collection's rows under this configuration's heading.
  if ! bash "$R/collect.sh" "$d" "$cfg" > /dev/null; then
    echo "=== $cfg -- COLLECTION FAILED, rows below would be stale; skipped ===" >&2
    continue
  fi
  echo "=== $cfg ==="
  # $18 is pstart_to_pend_s, read BY POSITION. The label was `aud=` while the column was
  # called audible_s; both were wrong in the same way -- the value is the stub player
  # process own interval and nothing in this rig opens an audio device -- so the label
  # moves with the column name rather than outliving it.
  awk -F'\t' 'NR==1{next}{printf "  t%-3s ord=%-32s hookB=%s/%s wclaim=%s/%s rc=%s plog=%s prun=%s\n",$2,$26,$21,$22,$23,$24,$14,$17,$18}' "$d/trials.tsv"
done < "$O/RUNS.txt"
