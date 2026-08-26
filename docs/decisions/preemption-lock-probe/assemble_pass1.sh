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
  bash "$R/collect.sh" "$d" "$cfg" > /dev/null
  if [[ $first == 1 ]]; then head -1 "$d/trials.tsv" >> "$DEST/preemption-trials-replication.tsv"; first=0; fi
  tail -n +2 "$d/trials.tsv" >> "$DEST/preemption-trials-replication.tsv"
done
wc -l "$DEST/preemption-trials-replication.tsv"
