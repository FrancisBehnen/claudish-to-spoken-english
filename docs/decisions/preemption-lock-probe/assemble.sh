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

first=1
: > "$DEST/preemption-trials.tsv"
while read -r cfg d; do
  [[ -n "${d:-}" ]] || continue
  bash "$R/collect.sh" "$d" "$cfg" > /dev/null
  if [[ $first == 1 ]]; then head -1 "$d/trials.tsv" >> "$DEST/preemption-trials.tsv"; first=0; fi
  tail -n +2 "$d/trials.tsv" >> "$DEST/preemption-trials.tsv"
done < "$O/RUNS.txt"

# A row-20-only run must not leave a STALE lock-owners.tsv in place and then have the
# wc below report it as part of this assembly. Say so and fail, rather than publishing
# one run's row 20 beside another run's row 21.
if [[ -f "$O/lock/owners.tsv" ]]; then
  cp "$O/lock/owners.tsv" "$DEST/lock-owners.tsv"
elif [[ -f "$DEST/lock-owners.tsv" ]]; then
  echo "assemble.sh: no lock run in $O, but $DEST/lock-owners.tsv already exists." >&2
  echo "Refusing to report a stale row-21 file as part of this assembly." >&2
  echo "Remove it, or re-run the lock scenarios, or set ALLOW_STALE_LOCK=1." >&2
  [[ ${ALLOW_STALE_LOCK:-0} = 1 ]] || exit 2
fi
wc -l "$DEST/preemption-trials.tsv" "$DEST/lock-owners.tsv" 2>/dev/null
