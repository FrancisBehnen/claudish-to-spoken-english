#!/bin/bash
# All 26 configurations, in sequence. Round 1 (C1-C10) is RE-RUN because the adversarial
# predicate in collect.sh changed: it now requires the Rdone marker -- publication
# demonstrably COMPLETE -- to precede P, which round 1 did not check.
#
# CORRECTED in round 3's review: this loop listed 24 configurations while the document
# summarised 26. C15c_norecheck_death_pgid and C17_setsid_player were added to the
# config table in run_preempt.sh but never to this loop, so a fresh run silently
# produced a smaller set than the published one -- and those two are exactly the arms
# that settle clause (ii) and falsify clause 7(iv).
#
# ALSO corrected in round 5: this resolved run_preempt.sh out of a private bench
# directory, so from a checkout it ran nothing and on the author's machine it could run
# a stale copy of the driver rather than the committed one. Overridable: RIG, OUT,
# PYTHON -- all exported, so the child driver agrees with this one.
#
# AND in round 12: `d=$(... | tail -1)` discarded the driver's exit status. `tail`
# succeeds over an empty stream, so run_preempt.sh dying at "worker never became ready"
# -- or refusing an unknown config -- appended an EMPTY run directory to RUNS.txt and
# this script went on to print DONE and exit 0. pipefail restores the status, and `d` is
# checked to be a real directory before it is recorded.
set -u -o pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RIG=${RIG:-$HERE}
OUT=${OUT:-$RIG/out}
export RIG OUT
mkdir -p "$OUT"
N=${1:-12}
: > "$OUT/RUNS.txt"
for cfg in \
  C1_prespawn C2_hookside C3_adversarial C4_noclaimkill C5_norecheck \
  C6_handle C7_noreap C8_orphan C9_ledger C10a_nopid_pidfile C10b_nopid_handle \
  C11a_shared_pubfirst C11b_shared_sweepfirst \
  C12a_pgid_pubfirst C12b_pgid_sweepfirst C12c_perplayer_recordonly \
  C13a_ledger_truncate C13b_perplayer_sametiming \
  C14a_shared_unlink C14b_perplayer_unlink \
  C15a_recheck_death C15b_norecheck_death C15c_norecheck_death_pgid \
  C16a_pending_sweepfirst C16b_pending_pubfirst \
  C17_setsid_player; do
  echo "=== $cfg ==="
  if ! d=$(bash "$RIG/run_preempt.sh" "$cfg" "$N" 2>>"$OUT/run.err" | tail -1); then
    echo "run_all_preempt.sh: $cfg FAILED -- see $OUT/run.err. Not recorded." >&2
    exit 2
  fi
  if [[ ! -d "$d" ]]; then
    echo "run_all_preempt.sh: $cfg returned '$d', which is not a run directory." >&2
    exit 2
  fi
  printf '%s\t%s\n' "$cfg" "$d" >> "$OUT/RUNS.txt"
  echo "$cfg -> $d"
done
echo DONE
