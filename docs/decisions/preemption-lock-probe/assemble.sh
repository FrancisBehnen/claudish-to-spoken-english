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
if [[ ! -f "$R/require.sh" ]]; then
  echo "assemble.sh: missing $R/require.sh -- the input-validation rule lives there, and" >&2
  echo "this script must not publish a header-only owners.tsv over committed evidence." >&2
  exit 2
fi
# shellcheck source=require.sh
. "$R/require.sh"
if ! declare -F require_data_rows >/dev/null; then
  echo "assemble.sh: $R/require.sh defined no require_data_rows." >&2
  exit 2
fi
mkdir -p "$DEST"

# Run the completeness guard BEFORE truncating anything. Assembly that publishes a
# partial evidence set and leaves summarise.sh to accept it is the null-as-pass defect
# one layer earlier: the guard existed but nothing on the publishing path called it.
# ALLOW_INCOMPLETE=1 is the deliberate override, and it is the only way past.
if ! bash "$R/verify_fires.sh" "$O" "${N:-12}"; then
  if [[ ${ALLOW_INCOMPLETE:-0} != 1 ]]; then
    echo "assemble.sh: verify_fires.sh failed -- refusing to publish an incomplete set." >&2
    echo "Set ALLOW_INCOMPLETE=1 to publish it anyway, deliberately." >&2
    exit 2
  fi
  echo "assemble.sh: WARNING publishing an INCOMPLETE set because ALLOW_INCOMPLETE=1" >&2
fi

# ---- ASSEMBLE INTO A TEMPORARY FILE AND RENAME IT ONLY WHEN EVERY CHECK HAS PASSED.
#
# ROUND 34, and this one is a PRODUCER that could destroy evidence rather than misreport it.
# This used to be `: > "$DEST/preemption-trials.tsv"` -- the COMMITTED evidence file,
# truncated before the first collection was even attempted. Every `exit 2` below then left
# the destination holding a partial file, or a zero-byte one, in place of the valid evidence
# that was there when the script started. The failure paths this revision`s predecessors
# added -- a failed collect.sh, a missing trials.tsv, a short row count -- each made that
# outcome MORE likely, because each is a new way to exit after the truncation.
#
# NOTHING WAS EVER LOST, and the ancestry says so rather than the author. The truncation has
# been in this file since `9e5a29b`, the commit that first published the evidence, so unlike
# harness defect 8 it is an ANCESTOR of every write and could have run. What settles it is
# the committed history of the files themselves: `preemption-trials.tsv` is 133 lines at
# `9e5a29b`, 313 at `07c3944`, and 313 at `c293618` and at HEAD;
# `preemption-trials-replication.tsv` is 133 at `07c3944` and 133 since. No committed state
# of either file is ever shorter than its predecessor, and `c293618` is a one-line header
# rename with byte-identical data rows, not an assembly. So this is a DISCLOSED NEAR-MISS on
# the harness list and not a harness defect -- see §1.
#
# `mv` within one directory is rename(2), which REPLACES the destination as one step: a
# reader sees the old file or the new file and never a half-written one, and a failure before
# the rename leaves the old file exactly as it was. That is the whole claim being made here
# -- nothing about ordering against any other process, and nothing about durability without
# an fsync.
STAGE=$(mktemp "$DEST/.preemption-trials.tsv.XXXXXX") || {
  echo "assemble.sh: cannot create a staging file in $DEST -- refusing to assemble in" >&2
  echo "place, because every failure below would then leave the committed evidence" >&2
  echo "replaced by a partial file." >&2
  exit 2; }
STAGE_LOCK=""
cleanup_stage() {
  [[ -n ${STAGE:-} && -e ${STAGE:-} ]] && rm -f "$STAGE"
  [[ -n ${STAGE_LOCK:-} && -e ${STAGE_LOCK:-} ]] && rm -f "$STAGE_LOCK"
  return 0
}
trap cleanup_stage EXIT

first=1
while read -r cfg d; do
  [[ -n "${d:-}" ]] || continue
  # collect.sh's exit status used to be discarded and $d/trials.tsv read regardless.
  # A run directory that has been collected before still HOLDS a trials.tsv, so a
  # failed re-collection published the OLD one as this assembly's evidence -- a stale
  # file standing in for the missing one, which is worse than an empty column because
  # it looks like data. Collection must succeed AND leave a file behind.
  if ! bash "$R/collect.sh" "$d" "$cfg" > /dev/null; then
    echo "assemble.sh: collect.sh failed for $cfg ($d) -- refusing to publish." >&2
    echo "Anything already in $d/trials.tsv is from an EARLIER collection." >&2
    exit 2
  fi
  if [[ ! -f "$d/trials.tsv" ]]; then
    echo "assemble.sh: collect.sh left no $d/trials.tsv for $cfg." >&2
    exit 2
  fi
  if [[ $first == 1 ]]; then head -1 "$d/trials.tsv" >> "$STAGE"; first=0; fi
  tail -n +2 "$d/trials.tsv" >> "$STAGE"
done < "$O/RUNS.txt"

# An empty RUNS.txt leaves a zero-byte file here, and `wc` at the end reports it
# without complaint. verify_fires.sh normally catches that first, but ALLOW_INCOMPLETE=1
# is a deliberate way past it and must not also be a way to publish no evidence at all.
#
# The count is over the STAGING file, and it is `awk`s NR and not `wc -l`: wc counts
# newlines, so a final row written without one is invisible to it, and undercounting turns a
# real assembly into a refusal.
rows=$(( $(awk 'END { print NR }' "$STAGE") - 1 ))
if [[ $rows -lt 1 ]]; then
  echo "assemble.sh: $O/RUNS.txt yielded no trials -- the staged evidence file is empty." >&2
  echo "This is NOT a successful assembly. $DEST/preemption-trials.tsv is untouched." >&2
  exit 2
fi

# A row-20-only run must not leave a STALE lock-owners.tsv in place and then have the
# wc below report it as part of this assembly. Say so and fail, rather than publishing
# one run's row 20 beside another run's row 21.
if [[ -f "$O/lock/owners.tsv" ]]; then
  # Unchecked, with no `set -e`, a failed copy (permissions, full filesystem) left any
  # existing destination file in place, the wc below counted THAT, and the final exit 0
  # reported a successful assembly over the previous run's row-21 evidence.
  #
  # AND A `cp` STRAIGHT ONTO THE DESTINATION IS THE SAME DEFECT AS THE TRUNCATION ABOVE:
  # cp(1) opens the destination with O_TRUNC and then writes, so a copy that fails PART WAY
  # -- a full filesystem is the obvious way -- leaves a truncated lock-owners.tsv where the
  # committed one was, and the `exit 2` below cannot put it back. Stage and rename, for the
  # same reason and with the same claim: rename(2) replaces in one step, so a failure before
  # it leaves the committed file exactly as it was.
  # The SOURCE is checked first, so the message names the file the operator has to fix.
  require_data_rows "assemble.sh" "$O/lock/owners.tsv" 1 || {
    echo "assemble.sh: $O/lock/owners.tsv is a header with no trials. Publishing it would" >&2
    echo "replace the committed row-21 evidence with a run that recorded nothing." >&2
    echo "$DEST/lock-owners.tsv is untouched." >&2
    exit 2; }
  STAGE_LOCK=$(mktemp "$DEST/.lock-owners.tsv.XXXXXX") || {
    echo "assemble.sh: cannot create a staging file for lock-owners.tsv in $DEST." >&2
    exit 2; }
  cp "$O/lock/owners.tsv" "$STAGE_LOCK" || {
    echo "assemble.sh: cp of $O/lock/owners.tsv failed -- refusing to report success" >&2
    echo "over whatever was already at $DEST/lock-owners.tsv, which is untouched." >&2
    exit 2; }
  # AND THE COPY IS CHECKED AGAINST THE SOURCE, not merely for success. cp(1) can return 0
  # having written less than it read on some filesystems, and the record count is the cheap
  # question that would notice.
  src_rows=$(awk 'END { print NR }' "$O/lock/owners.tsv")
  cp_rows=$(awk 'END { print NR }' "$STAGE_LOCK")
  if [[ ${src_rows:-0} -ne ${cp_rows:-1} ]]; then
    echo "assemble.sh: the staged copy of owners.tsv holds ${cp_rows:-0} line(s) and the" >&2
    echo "source holds ${src_rows:-0}. $DEST/lock-owners.tsv is untouched." >&2
    exit 2
  fi
elif [[ -f "$DEST/lock-owners.tsv" ]]; then
  echo "assemble.sh: no lock run in $O, but $DEST/lock-owners.tsv already exists." >&2
  echo "Refusing to report a stale row-21 file as part of this assembly." >&2
  echo "Remove it, or re-run the lock scenarios, or set ALLOW_STALE_LOCK=1." >&2
  [[ ${ALLOW_STALE_LOCK:-0} = 1 ]] || exit 2
fi

# ---- BOTH RENAMES, AFTER EVERY CHECK, AND NEITHER BEFORE THE OTHER'S CHECK.
# The two files are read TOGETHER -- the elif above exists precisely to stop one run`s row
# 20 being published beside another run`s row 21 -- so renaming trials.tsv into place before
# the lock branch had finished would leave exactly that pairing behind on the ALLOW_STALE_LOCK
# refusal. Every exit above this line leaves both committed files as they were.
mv -f "$STAGE" "$DEST/preemption-trials.tsv" || {
  echo "assemble.sh: cannot rename the staged preemption-trials.tsv into place." >&2
  exit 2; }
STAGE=""
if [[ -n $STAGE_LOCK ]]; then
  mv -f "$STAGE_LOCK" "$DEST/lock-owners.tsv" || {
    echo "assemble.sh: cannot rename the staged lock-owners.tsv into place. NOTE that" >&2
    echo "$DEST/preemption-trials.tsv HAS been replaced, so this pair is now mismatched." >&2
    exit 2; }
  STAGE_LOCK=""
fi

wc -l "$DEST/preemption-trials.tsv" "$DEST/lock-owners.tsv" 2>/dev/null
# The closing report must not decide this script's exit status. `wc` fails merely
# because a row-20-only assembly has no lock-owners.tsv to count, which reported a
# FAILURE for an assembly that had succeeded -- the mirror of the defect this revision
# sweeps, and just as misleading to anything reading the status. Every real failure
# above exits explicitly, so reaching here means success.
exit 0
