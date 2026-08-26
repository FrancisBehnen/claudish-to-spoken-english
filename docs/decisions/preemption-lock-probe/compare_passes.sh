#!/bin/bash
# Show that the replication arm and the published arm agree, config for config.
# Both are collected with the SAME collector and the same adversarial predicate,
# so a disagreement would be about the runs and not about the derivation.
# (BWK awk will not accept a line break after a ternary ':', hence the long lines.)
# usage: compare_passes.sh <evidence_dir>
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
D=${1:?dir}

# THE ATTRIBUTION RULE IS NOT WRITTEN HERE ANY MORE, and that is the point of this
# revision. This script carried its own copy of the attribution chain in summarise.sh,
# over the same two columns of the same TSV. Round 16 fixed the copy in summarise.sh and
# this one kept both of the defects that fix was about -- in the script the decision
# document cites as the replication-AGREEMENT check. See attrib.sh for the rule, the
# defect and its blast radius.
if [[ ! -f "$HERE/attrib.sh" ]]; then
  echo "compare_passes.sh: missing $HERE/attrib.sh -- the attribution rule lives there." >&2
  echo "Without it every row would normalise to the same value and the two passes would" >&2
  echo "agree trivially. Refusing to report agreement that was never tested." >&2
  exit 2
fi
# shellcheck source=attrib.sh
. "$HERE/attrib.sh"
if [[ -z ${ATTRIB:-} ]]; then
  echo "compare_passes.sh: $HERE/attrib.sh defined no ATTRIB. An empty awk program is a" >&2
  echo "LEGAL one, so the comparison would run over blank attributions and PASS on every" >&2
  echo "input. Refusing." >&2
  exit 2
fi

TMP=$(mktemp -d) || { echo "compare_passes.sh: cannot make a temp dir" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
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
  # Columns, from the TSV header: 13 player_pid, 14 rc, 17 player_log_sig, 18
  # pstart_to_pend_s. These offsets predated the insertion of Rdone_b and were reading
  # player_pid as rc and alive_s as player_log_sig, so every row scored "unknown" and
  # this comparison silently compared nothing.
  #
  # ROUND 29. THE EXPRESSION THAT USED TO BE ON THE NEXT LINE HAD TWO MORE DEFECTS, and
  # both were fixed in summarise.sh at round 16 and left standing here:
  #
  #   * `$14=="-15"||$17=="15"` let the PLAYER LOG OVERRIDE a conflicting wait status.
  #     The wait status is the kernel`s, written once; the player log is the LAST of
  #     possibly several `sig=` lines the player wrote. A row with rc=-14 and a final
  #     player-log value of 31 scored as a record sweep.
  #   * SIGALRM was OMITTED ENTIRELY -- no -14/14 arm at all -- so the 12
  #     C12a_pgid_pubfirst rows at (rc=-, plog=14) scored `unknown`, and two runs could
  #     appear to agree or disagree on a bucket that means "this script has no rule".
  #
  # It now calls the one shared rule, so the two passes are normalised by the same
  # function summarise.sh publishes section A with, and a future correction cannot reach
  # one and miss the other. The labels are summarise.sh`s, which splits the sweep into
  # `election-sweep-record` and `election-sweep-pgid` where this script had a single
  # `election-sweep`; both sides of the comparison are normalised by the same call, so
  # the split cannot manufacture a disagreement.
  awk -F'\t' "$ATTRIB"'$1=="config"{next}{ printf "%s\t%s\n", $1, attrib($14,$17,$13,$18) }' "$D/$f" \
    | sort | uniq -c | awk '{printf "%-5s %-20s %s\n",$1"x",$2,$3}' > "$TMP/$f.norm"
  sed 's/^/   /' "$TMP/$f.norm"
done

# THIS SCRIPT DID NOT COMPARE ANYTHING. It printed each pass's normalised summary and
# exited 0, and the decision document cites it as the replication-AGREEMENT check -- so a
# disagreement between the two passes was reported as success. That is the same
# null-as-pass shape this rig has been closing everywhere else, in the one script whose
# entire purpose is the comparison, and it survived because a reader sees two identical
# blocks of output and supplies the conclusion themselves.
#
# The comparison is now made, and a difference is fatal.
# The replication arm is DELIBERATELY a subset -- it re-runs C1..C10, not all 26 -- so a
# whole-file diff reports every config the published arm adds as a disagreement. That is
# not what agreement means here. The claim is that where the two passes measured the SAME
# configuration they reached the SAME attribution, so the comparison is over the
# INTERSECTION, and the script says how large that intersection is rather than leaving a
# reader to assume it was everything.
cut -d' ' -f2- "$TMP/preemption-trials-replication.tsv.norm" | awk '{print $1}' | sort -u > "$TMP/rep.cfgs"
cut -d' ' -f2- "$TMP/preemption-trials.tsv.norm"             | awk '{print $1}' | sort -u > "$TMP/pub.cfgs"
comm -12 "$TMP/rep.cfgs" "$TMP/pub.cfgs" > "$TMP/both.cfgs"
n_both=$(wc -l < "$TMP/both.cfgs" | tr -d ' ')
if [[ $n_both -lt 1 ]]; then
  echo "compare_passes.sh: the two passes share NO configuration -- nothing to compare." >&2
  exit 2
fi
for side in preemption-trials-replication.tsv preemption-trials.tsv; do
  awk 'NR==FNR{keep[$1]=1;next}{c=$2; if (c in keep) print}' \
      "$TMP/both.cfgs" "$TMP/$side.norm" | sort > "$TMP/$side.shared"
done
if ! diff -u "$TMP/preemption-trials-replication.tsv.shared" \
             "$TMP/preemption-trials.tsv.shared" > "$TMP/delta"; then
  echo >&2
  echo "compare_passes.sh: THE TWO PASSES DISAGREE on $n_both shared configuration(s)." >&2
  echo "Left is the replication arm, right the published arm; <count>x <config> <attribution>." >&2
  sed 's/^/   /' "$TMP/delta" >&2
  exit 2
fi
echo
echo "   the two passes agree on all $n_both shared configuration(s), attribution for attribution"
echo "   (the replication arm re-runs a subset by design; configurations only in the"
echo "    published arm are outside this comparison and are listed below)"
comm -23 "$TMP/pub.cfgs" "$TMP/both.cfgs" | sed 's/^/     published-only: /'

