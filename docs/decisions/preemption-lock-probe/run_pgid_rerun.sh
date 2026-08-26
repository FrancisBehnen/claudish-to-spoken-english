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
#
# Paths resolve from this script, not from a private bench dir -- see run_preempt.sh.
# A failed configuration is fatal rather than recorded as an empty path -- see the
# `tail -1` note in run_all_preempt.sh.
set -u -o pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RIG=${RIG:-$HERE}
OUT=${OUT:-$RIG/out}
export RIG OUT
mkdir -p "$OUT"
for cfg in C12a_pgid_pubfirst C12b_pgid_sweepfirst C13b_perplayer_sametiming \
           C16a_pending_sweepfirst C16b_pending_pubfirst \
           C15c_norecheck_death_pgid C17_setsid_player; do
  echo "=== $cfg ==="
  if ! d=$(bash "$RIG/run_preempt.sh" "$cfg" 12 2>>"$OUT/run.err" | tail -1); then
    echo "run_pgid_rerun.sh: $cfg FAILED -- see $OUT/run.err. The existing entry is" >&2
    echo "left alone rather than replaced by a re-run that did not happen." >&2
    exit 2
  fi
  if [[ ! -d "$d" ]]; then
    echo "run_pgid_rerun.sh: $cfg returned '$d', which is not a run directory." >&2
    exit 2
  fi
  # replace any stale entry for this config, then record the new one
  if [[ -f "$OUT/RUNS.txt" ]]; then
    grep -v "^$cfg	" "$OUT/RUNS.txt" > "$OUT/RUNS.tmp" || true
    mv "$OUT/RUNS.tmp" "$OUT/RUNS.txt"
  fi
  printf '%s\t%s\n' "$cfg" "$d" >> "$OUT/RUNS.txt"
  echo "$cfg -> $d"
done
echo PGIDRERUNDONE
