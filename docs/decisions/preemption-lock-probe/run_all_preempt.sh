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
set -u
RIG="$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25"
N=${1:-12}
: > "$RIG/out/RUNS.txt"
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
  d=$(bash "$RIG/run_preempt.sh" "$cfg" "$N" 2>>"$RIG/out/run.err" | tail -1)
  printf '%s\t%s\n' "$cfg" "$d" >> "$RIG/out/RUNS.txt"
  echo "$cfg -> $d"
done
echo DONE
