#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Generate the #10 audition: every wav the listening script refers to, plus the
# TSV every number in docs/decisions/min-length-audition.md is read out of.
#
# Silent by design (--play none): siblings may be synthesizing on this machine
# and Francis may be at it. Listen afterwards, from the doc's index.
#
#   bench/audition-10/run.sh                    # default out-dir, candidate sanitizer
#   OUT=/tmp/aud bench/audition-10/run.sh       # somewhere else
#
# Nothing here calls an LLM and nothing here touches a hook.
# ---------------------------------------------------------------------------
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OUT="${OUT:-$HOME/.local/share/kokoro/bench/audition-10}"
SAN="${SAN:-candidate}"
VOICE="${VOICE:-af_heart}"

mkdir -p "$OUT" "$OUT/pairs"

# The raw-vs-rewritten pairs. corpus/source/rNN.txt and corpus/spoken/rNN.txt
# share an id, so they are staged under distinct names rather than passed
# directly -- bench names each wav after the file stem.
for n in r01 r03 r06; do
  cp "$REPO/corpus/source/$n.txt"  "$OUT/pairs/raw-$n.txt"
  cp "$REPO/corpus/spoken/$n.txt"  "$OUT/pairs/rew-$n.txt"
done

# --- pass 1: everything, warm ----------------------------------------------
# --warmup so no measured row is cold; the cold number is taken separately in
# pass 2, where it is the thing being measured rather than an artefact.
"$REPO/bench/bench" \
  "$HERE"/items/*.txt \
  "$OUT"/pairs/raw-r01.txt "$OUT"/pairs/rew-r01.txt \
  "$OUT"/pairs/raw-r03.txt "$OUT"/pairs/rew-r03.txt \
  "$OUT"/pairs/raw-r06.txt "$OUT"/pairs/rew-r06.txt \
  --id s09,s21,s15,s32,s33 \
  --sanitizer "$SAN" --voice "$VOICE" \
  --play none --warmup --out-dir "$OUT" --tsv "$OUT/audition.tsv"

# --- pass 2: the cold first utterance --------------------------------------
# A fresh process, no warmup, one short item: what the first spoken message of a
# session (or the first after a sleep/wake) actually costs. It writes into a
# scratch dir of its own -- pointing it at $OUT would overwrite pass 1's ack01
# wav and then delete it on the way out.
"$REPO/bench/bench" \
  "$HERE/items/ack01.txt" \
  --sanitizer "$SAN" --voice "$VOICE" \
  --play none --no-keep-wav --out-dir "$OUT/cold" --tsv "$OUT/cold.tsv"

printf '\naudition wavs: %s\n' "$OUT"
printf 'tables:        %s/audition.tsv  %s/cold.tsv\n' "$OUT" "$OUT"
