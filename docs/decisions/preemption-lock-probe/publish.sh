#!/bin/bash
# Copy the rig into the branch so every figure re-derives from committed files.
# usage: publish.sh <repo_docs_decisions_dir>
#
# The file list used to be spelled out by hand, and had fallen six files behind what
# the rig actually contains (clean_copies.sh, gather_out.sh, peek_one.sh,
# run_missing.sh, run_pgid_rerun.sh, run_tail.sh) -- the same "the run script is one
# round behind the document" defect, one level down. It is now a glob, so it cannot.
# RIG is the SOURCE of the copy and is therefore external by definition; overridable.
set -u
DEST=${1:?dest}/preemption-lock-probe
RIG=${RIG:-$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25}
if [[ "$(cd "$RIG" && pwd)" == "$(cd "$(dirname "$DEST")" 2>/dev/null && pwd)/preemption-lock-probe" ]]; then
  echo "refusing to publish $RIG onto itself" >&2; exit 2
fi
mkdir -p "$DEST"
for f in "$RIG"/README.md "$RIG"/*.py "$RIG"/*.sh; do
  [[ -f "$f" ]] && cp "$f" "$DEST/$(basename "$f")"
done
chmod +x "$DEST"/*.sh "$DEST"/*.py
ls -1 "$DEST"
