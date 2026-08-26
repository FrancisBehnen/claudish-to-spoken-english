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

# The eleven configurations the replication arm covers. C1-C10 are the round-1 set; the
# arm exists to re-collect exactly those under the CURRENT collector.
PASS1=(C1_prespawn C2_hookside C3_adversarial C4_noclaimkill C5_norecheck C6_handle
       C7_noreap C8_orphan C9_ledger C10a_nopid_pidfile C10b_nopid_handle)

# ROUND 16 -- C3 WAS PINNED AND THE OTHERS WERE NOT, AND NOTHING NOTICED THE DIFFERENCE.
# The loop read `"$O"/C3_adversarial-1787683326` -- ONE historical run directory on the
# author's machine -- while every other configuration used a `-*` glob. Point OUT at any
# other valid pass-1 tree and that one literal matches nothing, `[[ -d "$d" ]] || continue`
# skips it in silence, and the arm is published with TEN configurations. The closing
# guard could not catch it: it asked whether the AGGREGATE had at least one row, and ten
# configurations' worth of rows is plenty. A per-configuration shortfall is invisible to
# an aggregate test -- which is the same defect verify_fires.sh's manifest exists to fix,
# one script over.
#
# Every configuration is now globbed and every configuration must match EXACTLY ONE run
# directory. Not zero (the C3 failure), and not two either: a tree holding two runs of
# one configuration is an ambiguity the script must not resolve by picking, because
# either choice publishes a replication arm whose provenance nobody can state. Where a
# tree genuinely holds more than one, name the intended directory explicitly:
#   PASS1_C3_adversarial=C3_adversarial-1787683326 assemble_pass1.sh <dest>
# which is the historical pin, kept as an override rather than as a hidden default.
RUNS=()
for cfg in "${PASS1[@]}"; do
  pin_var="PASS1_$cfg"
  pin=${!pin_var:-}
  if [[ -n $pin ]]; then
    if [[ ! -d "$O/$pin" ]]; then
      echo "assemble_pass1.sh: $pin_var names $O/$pin, which is not a directory." >&2
      exit 2
    fi
    RUNS+=("$O/$pin")
    continue
  fi
  matches=()
  for d in "$O/$cfg"-*; do
    [[ -d "$d" ]] && matches+=("$d")
  done
  if [[ ${#matches[@]} -eq 0 ]]; then
    echo "assemble_pass1.sh: no run directory $O/$cfg-* -- the replication arm would be" >&2
    echo "published WITHOUT $cfg, and the aggregate row count would not show it." >&2
    echo "Set OUT= to the pass-1 run tree, or re-run $cfg." >&2
    exit 2
  fi
  if [[ ${#matches[@]} -gt 1 ]]; then
    echo "assemble_pass1.sh: $O holds ${#matches[@]} run directories for $cfg:" >&2
    printf '  %s\n' "${matches[@]}" >&2
    echo "Refusing to choose. Set $pin_var=<dirname> to name the intended one." >&2
    exit 2
  fi
  RUNS+=("${matches[0]}")
done

first=1
: > "$DEST/preemption-trials-replication.tsv"
for d in "${RUNS[@]}"; do
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
# $O defaults to a path that exists only on the author's machine. Point this anywhere
# else and, before round 16, every branch of the loop was skipped, leaving a file with
# no rows -- or none, if `first` was never cleared -- and `wc` reported it as an
# assembly. It is not one: the replication arm exists to be compared against the
# published arm, and nothing compares against nothing.
#
# This is now a BACKSTOP and no longer the only check: the per-configuration
# exactly-one requirement above has already refused an incomplete tree by name, and the
# aggregate row count is what that requirement was found unable to see.
rows=$(( $(wc -l < "$DEST/preemption-trials-replication.tsv") - 1 ))
if [[ $rows -lt 1 ]]; then
  echo "assemble_pass1.sh: none of the pass-1 run directories under $O matched --" >&2
  echo "wrote no trials. This is NOT a successful assembly; set OUT= to the pass-1" >&2
  echo "run tree." >&2
  exit 2
fi
wc -l "$DEST/preemption-trials-replication.tsv"
