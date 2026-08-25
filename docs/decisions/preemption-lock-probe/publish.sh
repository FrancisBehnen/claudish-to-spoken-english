#!/bin/bash
# Copy the rig into the branch so every figure re-derives from committed files.
# usage: publish.sh <repo_docs_decisions_dir>
set -u
DEST=${1:?dest}/preemption-lock-probe
RIG="$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25"
mkdir -p "$DEST"
for f in README.md speakd_probe.py player_probe.py lockrace.py hook_probe.sh \
         run_preempt.sh run_all_preempt.sh run_c10.sh run_lock.sh run_real.sh run_c16.sh assemble_pass1.sh compare_passes.sh \
         collect_real.sh analyse_round2.sh \
         collect.sh assemble.sh summarise.sh peek.sh publish.sh; do
  cp "$RIG/$f" "$DEST/$f"
done
chmod +x "$DEST"/*.sh "$DEST"/*.py
ls -1 "$DEST"
