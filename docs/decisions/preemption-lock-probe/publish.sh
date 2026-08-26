#!/bin/bash
# Copy the rig into the branch so every figure re-derives from committed files.
# usage: publish.sh <repo_docs_decisions_dir>
#
# The file list used to be spelled out by hand, and had fallen six files behind what
# the rig actually contains (clean_copies.sh, gather_out.sh, peek_one.sh,
# run_missing.sh, run_pgid_rerun.sh, run_tail.sh) -- the same "the run script is one
# round behind the document" defect, one level down. It is now a glob, so it cannot.
# RIG is the SOURCE of the copy and is therefore external by definition; overridable.
#
# ROUND 15 -- the glob fixed the OMISSION and left the two defects underneath it:
#
#  * EVERY name was optional except the manifest. `[[ -f $f ]] || continue` is the only
#    thing standing between "the glob matched nothing" and "speakd_probe.py is not in
#    the rig", and it treats those identically. A rig missing the probe, the player, the
#    lock driver or the collector published in silence.
#  * THE DESTINATION WAS NEVER CLEARED, so the copy was a MERGE. A source file that was
#    absent (see above) left the branch's older copy of that same name standing, and the
#    closing `ls` then listed it as though it had just been published -- a rig that is
#    part new code and part stale code, reported as a success. That is the worst shape
#    this failure can take here, because the whole claim of the branch is that the
#    committed rig is the one the traces came from.
#  * And there was no `set -e`, so a `chmod` or `mkdir` failure did not stop it either.
#
# It now stages into a fresh temporary directory beside the destination, checks the
# runtime set THERE, and only then swaps it into place. A failure at any point leaves
# the existing rig exactly as it was rather than half-replaced.
set -eu
DEST=${1:?dest}/preemption-lock-probe
RIG=${RIG:-$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25}

# The files without which the published rig cannot produce evidence or re-derive a
# figure. Every one of them is named by the document or by another script in this list:
# a missing name here is a rig that cannot do the job the branch says it does.
#
# ROUND 16 -- the list did not meet its own criterion. Four of the branch's committed
# evidence files and two of the document's cited derivations were absent from it, so a
# rig missing any of them published successfully and could then not rebuild the file the
# document points at. `collect_real.sh` is the plainest case: without it
# `real-audio-trials.tsv` cannot be rebuilt from the committed REAL traces, and
# `summarise.sh` section E -- which fails the whole re-derivation when that file is
# absent -- has no producer. The list is now closed under "every committed TSV has the
# script that builds it, and every derivation the document cites is present".
REQUIRED=(
  speakd_probe.py         # the worker under test
  player_probe.py         # the player it spawns; its exit status IS the attribution
  lockrace.py             # row 21's three protocols
  hook_probe.sh           # the Stop-hook side that stamps R/K/Rdone
  run_preempt.sh          # row 20 driver
  run_lock.sh             # row 21 driver
  run_real.sh             # the REAL-audio driver: the third of three, and section E's
  collect.sh              # run directory -> committed TSV
  collect_real.sh         # REAL traces -> real-audio-trials.tsv, section E's input
  assemble.sh             # builds preemption-trials.tsv AND lock-owners.tsv, and is the
                          #   only caller of verify_fires.sh on the publishing path
  assemble_pass1.sh       # builds preemption-trials-replication.tsv, the fourth TSV
  compare_passes.sh       # the document's derivation of the two arms' agreement
  summarise.sh            # the advertised re-derivation of every published figure
  verify_fires.sh         # the completeness check
  analyse_round2.sh       # the round-2 protocol facts the document quotes
  analyse_c14.sh          # the document's "third derivation", over the C14 traces
  expected-configs.txt    # the manifest verify_fires.sh checks against
)

if [[ ! -d "$RIG" ]]; then
  echo "publish.sh: no rig at $RIG" >&2; exit 2
fi
RIG_ABS=$(cd "$RIG" && pwd)
DEST_PARENT=$(dirname "$DEST")
if [[ ! -d "$DEST_PARENT" ]]; then
  echo "publish.sh: no destination directory $DEST_PARENT" >&2; exit 2
fi
DEST_PARENT_ABS=$(cd "$DEST_PARENT" && pwd)
if [[ "$RIG_ABS" == "$DEST_PARENT_ABS/preemption-lock-probe" ]]; then
  echo "refusing to publish $RIG onto itself" >&2; exit 2
fi

# Check the SOURCE before touching anything, so the message names what is wrong with the
# rig rather than what went wrong halfway through a copy.
missing=()
for f in "${REQUIRED[@]}"; do
  [[ -f "$RIG/$f" ]] || missing+=("$f")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "publish.sh: $RIG is not a complete rig -- missing: ${missing[*]}" >&2
  echo "Publishing it would put a rig in the branch that cannot produce or re-derive" >&2
  echo "the evidence the document points at. Nothing was copied." >&2
  exit 2
fi

# Stage into a fresh directory. `mktemp -d` beside the destination keeps the final swap
# a rename within one filesystem rather than a copy that can half-finish.
STAGE=$(mktemp -d "$DEST_PARENT_ABS/.preemption-lock-probe.stage.XXXXXX")
cleanup() { if [[ -n "${STAGE:-}" && -d "${STAGE:-}" ]]; then rm -rf "$STAGE"; fi; }
trap cleanup EXIT

for f in "$RIG"/README.md "$RIG"/*.py "$RIG"/*.sh "$RIG"/expected-configs.txt; do
  # an unmatched glob degrades to its own literal text, which is the only reason a
  # name here may be absent; a copy that FAILS is fatal. The REQUIRED check above is
  # what makes "absent" mean "the glob matched nothing" and never "the probe is gone".
  [[ -f "$f" ]] || continue
  cp "$f" "$STAGE/$(basename "$f")" || { echo "publish.sh: cp $f failed" >&2; exit 2; }
done

# Check the STAGING copy, not the source: a cp that silently produced nothing would
# otherwise pass the source check above and still publish an empty rig.
for f in "${REQUIRED[@]}"; do
  [[ -s "$STAGE/$f" ]] || { echo "publish.sh: $f did not arrive in the staging copy" >&2; exit 2; }
done
chmod +x "$STAGE"/*.sh "$STAGE"/*.py

# The traces/ directory is committed evidence and is NOT part of the rig copy, so carry
# it across rather than destroying it with the old rig.
#
# ROUND 16 -- THE ROLLBACK WAS BROKEN, AND ITS FAILURE MODE WAS TOTAL DATA LOSS. This
# was a `mv`, which MOVED the evidence out of the live destination before the swap. The
# rollback below then restored $OLD -- a directory whose traces/ had already been taken
# out of it -- and the EXIT trap deleted $STAGE, which by then held the ONLY copy. So
# the one path written to leave the original intact was the one path that destroyed it.
#
# COPY, so the original stays whole until the swap has succeeded and $OLD is removed.
# `-p` because harness defect 3 in this same rig was `cp -R` rewriting mtimes that were
# the measurement: those live in a run tree's markers/ and not in committed traces/,
# whose timestamps are already inside .markers.tsv, but the copy preserves them anyway
# rather than relying on that argument staying true.
if [[ -d "$DEST/traces" ]]; then
  cp -Rp "$DEST/traces" "$STAGE/traces" \
    || { echo "publish.sh: could not copy $DEST/traces into staging" >&2; exit 2; }
  # A partial copy is the same loss one step later, because $OLD is removed on success.
  # Compare the two by entry count before anything irreversible happens.
  src_n=$(find "$DEST/traces" | wc -l | tr -d ' ')
  dst_n=$(find "$STAGE/traces" | wc -l | tr -d ' ')
  if [[ "$src_n" != "$dst_n" ]]; then
    echo "publish.sh: staged traces/ has $dst_n entries, the original has $src_n." >&2
    echo "Refusing to swap: the old rig is about to be deleted and this copy is not it." >&2
    exit 2
  fi
fi

# Replace, do not merge. The old rig goes aside first so that a failure here leaves one
# of the two intact rather than a directory that is half of each.
OLD=""
if [[ -e "$DEST" ]]; then
  OLD="$DEST.replaced.$$"
  mv "$DEST" "$OLD"
fi
if ! mv "$STAGE" "$DEST"; then
  echo "publish.sh: could not move the staged rig into place" >&2
  if [[ -n $OLD ]]; then
    if mv "$OLD" "$DEST"; then
      echo "publish.sh: the original rig, traces/ included, was restored to $DEST" >&2
    else
      # Do not exit silently on a failed rollback: the evidence still EXISTS, and the
      # only thing standing between the operator and it is knowing this path.
      echo "publish.sh: ROLLBACK ALSO FAILED. The original rig is intact at $OLD --" >&2
      echo "move it back to $DEST by hand. Nothing has been deleted." >&2
    fi
  fi
  exit 2
fi
STAGE=""
# Only now is the copy in place and the original redundant.
if [[ -n $OLD ]]; then rm -rf "$OLD"; fi
ls -1 "$DEST"
