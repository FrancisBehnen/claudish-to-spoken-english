#!/bin/bash
# Re-run every configuration whose result depended on the process-group sweep.
#
# The first round-2 sweep was launched under `nohup`, which sets SIGHUP to SIG_IGN --
# a disposition inherited across fork AND exec. The pgid sweep used SIGHUP, so it was
# a silent no-op for the whole run, and C12b's "the repair fails" was an artefact of
# the harness rather than a result about the design. The sweep signal is now SIGALRM,
# the worker records its signal dispositions at startup and refuses to run if a sweep
# signal is ignored, and this script is deliberately NOT launched under nohup.
#
# Unaffected and NOT re-run: C11a/C11b/C12c/C13a (record sweep, SIGUSR2),
# C14a/C14b (no sweep), C15a/C15b (sweep off), C1-C10 (no sweep).
set -u
RIG="$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25"
for cfg in C12a_pgid_pubfirst C12b_pgid_sweepfirst C13b_perplayer_sametiming \
           C16a_pending_sweepfirst C16b_pending_pubfirst \
           C15c_norecheck_death_pgid C17_setsid_player; do
  echo "=== $cfg ==="
  d=$(bash "$RIG/run_preempt.sh" "$cfg" 12 2>>"$RIG/out/run.err" | tail -1)
  # replace any stale entry for this config, then record the new one
  if [[ -f "$RIG/out/RUNS.txt" ]]; then
    grep -v "^$cfg	" "$RIG/out/RUNS.txt" > "$RIG/out/RUNS.tmp" || true
    mv "$RIG/out/RUNS.tmp" "$RIG/out/RUNS.txt"
  fi
  printf '%s\t%s\n' "$cfg" "$d" >> "$RIG/out/RUNS.txt"
  echo "$cfg -> $d"
done
echo PGIDRERUNDONE
