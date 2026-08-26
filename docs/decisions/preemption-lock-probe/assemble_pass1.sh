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
if [[ ! -f "$R/require.sh" ]]; then
  echo "assemble_pass1.sh: missing $R/require.sh -- the input-validation rule lives there," >&2
  echo "and the per-configuration trial check is one of its definitions." >&2
  exit 2
fi
# shellcheck source=require.sh
. "$R/require.sh"
if ! declare -F require_exact_id_set >/dev/null; then
  echo "assemble_pass1.sh: $R/require.sh defined no require_exact_id_set -- a run with the" >&2
  echo "right NUMBER of trials and the wrong SET would publish as the replication arm." >&2
  exit 2
fi
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

# THE SAME TRUNCATION AS assemble.sh HAD, IN THE SCRIPT THAT PUBLISHES THE OTHER COMMITTED
# TSV, and it is fixed the same way and for the same reason: this used to be
# `: > "$DEST/preemption-trials-replication.tsv"`, so every `exit 2` below left the committed
# replication arm replaced by a partial file. The finding named assemble.sh; leaving its
# sibling standing is the shape §1 keeps meeting -- one fix applied to one site and not to the
# copy beside it -- and it is why the two truncations are one entry.
#
# Nothing was lost here either: `preemption-trials-replication.tsv` is 133 lines at
# `07c3944`, at `c293618` and at HEAD, and `c293618` is a one-line header rename with
# byte-identical data rows.
first=1
STAGE=$(mktemp "$DEST/.preemption-trials-replication.tsv.XXXXXX") || {
  echo "assemble_pass1.sh: cannot create a staging file in $DEST -- refusing to assemble" >&2
  echo "in place, because every failure below would then leave the committed replication" >&2
  echo "arm replaced by a partial file." >&2
  exit 2; }
cleanup_stage() { [[ -n ${STAGE:-} && -e ${STAGE:-} ]] && rm -f "$STAGE"; return 0; }
trap cleanup_stage EXIT

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
  # Exactly-one-directory per configuration is not the same as a COMPLETE directory.
  # collect.sh only compares the rows it parsed against that run's own attempted hooks,
  # so eleven complete ONE-trial runs satisfy every check above and publish an 11-row
  # file as the documented 132-row replication arm. Require the trial count too.
  #
  # ROUND 34 -- AND A COUNT OF DISTINCT IDS IS NOT THE ID SET. The old check was
  # `distinct($2) == 12`, which is the same shape as the five existence-only input checks
  # this round closed: it validates a PROPERTY of the set and not the set. Three runs pass
  # it and are not the run this arm publishes:
  #
  #   * ids `1..11,13` -- twelve distinct values, so trial 12 is MISSING and a trial 13 that
  #     is outside the twelve-trial experiment is published in its place;
  #   * twenty-four rows carrying ids `1..12` twice -- twelve distinct values again, and the
  #     replication denominator this arm exists to compare against is DOUBLED;
  #   * any twelve distinct ids at all, including `101..112`.
  #
  # The requirement is the row count, uniqueness, and the exact set 1..PASS1_TRIALS -- all
  # three, through the one shared definition, which tests membership with array subscripts
  # rather than `==` (see require.sh: on BWK awk here a trailing U+2032 PRIME is invisible to
  # `==` and visible to a subscript, so `12<PRIME>` is reported out-of-range rather than
  # silently accepted as trial 12).
  want=${PASS1_TRIALS:-12}
  require_uint "assemble_pass1.sh" "PASS1_TRIALS" "$want" 1 || exit 2
  if ! require_exact_id_set "assemble_pass1.sh ($cfg)" "$d/trials.tsv" 2 "$want"; then
    echo "assemble_pass1.sh: $cfg in $d/trials.tsv is not a complete $want-trial run." >&2
    echo "  Publishing it would move the replication denominator while the file still" >&2
    echo "  looked complete -- and a count of distinct trial ids cannot see a gap, an" >&2
    echo "  out-of-range id, or a duplicated row." >&2
    exit 2
  fi
  if [[ $first == 1 ]]; then head -1 "$d/trials.tsv" >> "$STAGE"; first=0; fi
  tail -n +2 "$d/trials.tsv" >> "$STAGE"
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
#
# Over the STAGING file, and with awk`s NR rather than `wc -l`: wc counts newlines, so a
# final row written without one is invisible to it.
rows=$(( $(awk 'END { print NR }' "$STAGE") - 1 ))
if [[ $rows -lt 1 ]]; then
  echo "assemble_pass1.sh: none of the pass-1 run directories under $O matched --" >&2
  echo "staged no trials. This is NOT a successful assembly; set OUT= to the pass-1" >&2
  echo "run tree. $DEST/preemption-trials-replication.tsv is untouched." >&2
  exit 2
fi

# Every check has passed, so the rename happens now and not before. rename(2) replaces the
# destination in one step: a reader sees the old file or the new one, and every exit above
# this line leaves the committed file exactly as it was.
mv -f "$STAGE" "$DEST/preemption-trials-replication.tsv" || {
  echo "assemble_pass1.sh: cannot rename the staged file into place." >&2
  exit 2; }
STAGE=""
wc -l "$DEST/preemption-trials-replication.tsv"
