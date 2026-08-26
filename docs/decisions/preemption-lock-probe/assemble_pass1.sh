#!/bin/bash
# Pass 1's RUNS.txt holds paths from before the directory was renamed, so rebuild
# the list from the directories that are actually there.
#
# collect.sh resolves beside this script (overridable with RIG=), so a re-assembly
# cannot run a stale copy of the parser. OUT still names the pass-1 RUN TREE, which is
# genuinely external -- those run directories are not in the repository.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
R=${RIG:-$HERE}
O=${OUT:-$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25/out-pass1}
DEST=${1:?dest}
mkdir -p "$DEST"
first=1
: > "$DEST/preemption-trials-replication.tsv"
for d in "$O"/C1_prespawn-* "$O"/C2_hookside-* "$O"/C3_adversarial-1787683326 \
         "$O"/C4_noclaimkill-* "$O"/C5_norecheck-* "$O"/C6_handle-* \
         "$O"/C7_noreap-* "$O"/C8_orphan-* "$O"/C9_ledger-* \
         "$O"/C10a_nopid_pidfile-* "$O"/C10b_nopid_handle-*; do
  [[ -d "$d" ]] || continue
  cfg=$(basename "$d"); cfg=${cfg%-*}
  # Same defect as assemble.sh: the collector's status was discarded and trials.tsv
  # read regardless, so a failed re-collection republished the file an EARLIER
  # collection had left in that run directory.
  if ! bash "$R/collect.sh" "$d" "$cfg" > /dev/null; then
    echo "assemble_pass1.sh: collect.sh failed for $cfg ($d) -- refusing to publish." >&2
    echo "Anything already in $d/trials.tsv is from an EARLIER collection." >&2
    exit 2
  fi
  if [[ ! -f "$d/trials.tsv" ]]; then
    echo "assemble_pass1.sh: collect.sh left no $d/trials.tsv for $cfg." >&2
    exit 2
  fi
  if [[ $first == 1 ]]; then head -1 "$d/trials.tsv" >> "$DEST/preemption-trials-replication.tsv"; first=0; fi
  tail -n +2 "$d/trials.tsv" >> "$DEST/preemption-trials-replication.tsv"
done
# The directory names above are HARD-CODED, and $O defaults to a path that exists only
# on the author's machine. Point this anywhere else and every branch of the loop is
# skipped, leaving a file with no rows -- or none, if `first` was never cleared -- and
# `wc` reports it as an assembly. It is not one: the replication arm exists to be
# compared against the published arm, and nothing compares against nothing.
rows=$(( $(wc -l < "$DEST/preemption-trials-replication.tsv") - 1 ))
if [[ $rows -lt 1 ]]; then
  echo "assemble_pass1.sh: none of the pass-1 run directories under $O matched --" >&2
  echo "wrote no trials. This is NOT a successful assembly; set OUT= to the pass-1" >&2
  echo "run tree." >&2
  exit 2
fi
wc -l "$DEST/preemption-trials-replication.tsv"
