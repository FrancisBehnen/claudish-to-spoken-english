#!/bin/bash
# Outcome summary for one configuration, by attribution and player-process runtime.
# The second column printed is $18, pstart_to_pend_s, read BY POSITION: the stale player
# process own start-to-end interval. It was called "audible duration" here and audible_s
# in the schema; the player is a stub that opens no audio device, so neither name was a
# fact about sound.
# collect.sh beside this script; OUT names the run tree. Overridable: RIG, OUT.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RIG=${RIG:-$HERE}
OUT=${OUT:-$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25/out}

# THE THIRD COPY OF THE ATTRIBUTION RULE USED TO LIVE HERE, and it was the worst of the
# three. It tested -31/31 FIRST, which is exactly the ordering round 16 identified as the
# defect in summarise.sh: a row whose wait status said -14 (process-group sweep) but whose
# LAST player-log line said 31 was reported as a RECORD sweep, because the player log was
# consulted before the kernel and 31 was tested before 14. This is a by-eye diagnostic, so
# a wrong label here is a wrong conclusion drawn by a human rather than a wrong published
# figure -- which is why it survived thirteen rounds after the same defect was fixed one
# file away. It now calls the one shared rule. See attrib.sh.
if [[ ! -f "$RIG/attrib.sh" ]]; then
  echo "peek_one.sh: missing $RIG/attrib.sh -- the attribution rule lives there, and" >&2
  echo "without it every trial below would be labelled identically. Refusing to print a" >&2
  echo "summary whose whole content is the attribution." >&2
  exit 2
fi
# shellcheck source=attrib.sh
. "$RIG/attrib.sh"
if [[ -z ${ATTRIB:-} ]]; then
  echo "peek_one.sh: $RIG/attrib.sh defined no ATTRIB -- an empty awk program is a legal" >&2
  echo "one, so every row would print a blank label. Refusing." >&2
  exit 2
fi
[[ -f "$OUT/RUNS.txt" ]] || { echo "peek_one.sh: no $OUT/RUNS.txt." >&2; exit 2; }
for c in "$@"; do
  d=$(awk -v c="$c" '$1==c{print $2}' "$OUT/RUNS.txt")
  [[ -n "${d:-}" && -d "$d" ]] || { echo "=== $c (not run) ==="; continue; }
  # `>/dev/null 2>&1` discarded both the collector's output and its diagnosis, and the
  # summary below was then printed from whatever trials.tsv that directory already had
  # -- an earlier collection's numbers under today's heading. Failure is now visible
  # and the stale rows are not printed at all.
  if ! bash "$RIG/collect.sh" "$d" "$c" >/dev/null; then
    echo "=== $c (COLLECTION FAILED -- any rows here would be stale) ==="
    continue
  fi
  echo "=== $c ==="
  awk -F'\t' "$ATTRIB"'NR>1{ print "  " attrib($14,$17,$13,$18) "\t" $18 "\t" $26 }' \
    "$d/trials.tsv" | sort | uniq -c
done
