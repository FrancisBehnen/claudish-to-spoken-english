#!/bin/bash
set -u
RIG="$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25"
for cfg in C13b_perplayer_sametiming C16a_pending_sweepfirst \
           C15c_norecheck_death_pgid C17_setsid_player; do
  echo "=== $cfg ==="
  d=$(bash "$RIG/run_preempt.sh" "$cfg" 12 2>>"$RIG/out/run.err" | tail -1)
  echo "$cfg -> $d"
done
echo MISSINGDONE
