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
# expected-configs.txt is NOT optional decoration: it is the manifest verify_fires.sh
# checks completeness against. The loop below is `[[ -f $f ]] && cp`, which treats every
# name in the list as optional -- so a missing manifest was skipped in silence and the
# published rig arrived at its destination with its completeness check disarmed. That is
# this document's own defect (a step that produces nothing and still exits 0) on the
# script that hands the rig to the branch, so it fails BEFORE copying anything.
if [[ ! -f "$RIG/expected-configs.txt" ]]; then
  echo "publish.sh: no $RIG/expected-configs.txt -- refusing to publish a rig without" >&2
  echo "its completeness manifest. verify_fires.sh cannot check a partial evidence set" >&2
  echo "against a manifest that is not there." >&2
  exit 2
fi
mkdir -p "$DEST"
for f in "$RIG"/README.md "$RIG"/*.py "$RIG"/*.sh "$RIG"/expected-configs.txt; do
  # an unmatched glob degrades to its own literal text, which is the only reason a
  # name here may be absent; a copy that FAILS is fatal.
  [[ -f "$f" ]] || continue
  cp "$f" "$DEST/$(basename "$f")" || { echo "publish.sh: cp $f failed" >&2; exit 2; }
done
chmod +x "$DEST"/*.sh "$DEST"/*.py
ls -1 "$DEST"
