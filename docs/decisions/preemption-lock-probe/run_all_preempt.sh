#!/bin/bash
# All configurations, in sequence. Round 1 (C1-C10) is RE-RUN because the adversarial
# predicate in collect.sh changed: it now requires the Rdone marker -- publication
# demonstrably COMPLETE -- to precede P, which round 1 did not check.
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
  C15a_recheck_death C15b_norecheck_death \
  C16a_pending_sweepfirst C16b_pending_pubfirst; do
  echo "=== $cfg ==="
  d=$(bash "$RIG/run_preempt.sh" "$cfg" "$N" 2>>"$RIG/out/run.err" | tail -1)
  printf '%s\t%s\n' "$cfg" "$d" >> "$RIG/out/RUNS.txt"
  echo "$cfg -> $d"
done
echo DONE
