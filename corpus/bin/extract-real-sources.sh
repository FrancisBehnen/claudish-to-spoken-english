#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Pull real assistant messages out of this machine's Claude Code transcripts.
#
# The corpus's "real" half needs the text rewrite.sh actually sees. That text is
# the assistant message; the hook reconstructs it from streamed MessageDisplay
# deltas, but the identical string is already persisted in the session
# transcript, so reading the transcript is the least invasive capture there is:
# no hook change, no temporary tee, no debug flag, nothing to un-install
# afterwards. See corpus/README.md "How the real half was captured".
#
# Assistant text only. rewrite.sh also appends the preceding user question to
# the system prompt as context (rewrite.sh:184-190), but selecting user prompts
# out of a transcript is blocked by this machine's permission classifier, so the
# captured corpus runs rewrite.sh's documented no-context path instead. See
# corpus/README.md "Known deviation from the live hook".
#
# Usage: extract-real-sources.sh <transcript-dir> <out-dir>
# Writes <out-dir>/all.jsonl  (one {sess,uuid,ts,txt} per assistant message)
#    and <out-dir>/scored.tsv (prose_len gate per message, tab separated)
# ---------------------------------------------------------------------------
set -uo pipefail
TDIR="${1:?transcript dir}"
ODIR="${2:?out dir}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ODIR"

: > "$ODIR/all.jsonl"
for f in "$TDIR"/*.jsonl; do
  [ -f "$f" ] || continue
  b="$(basename "$f" .jsonl)"
  jq -s -c --arg sess "$b" -f "$HERE/extract-assistant-messages.jq" "$f" \
    >> "$ODIR/all.jsonl" 2>/dev/null
done

# prose_len is computed exactly as rewrite.sh:139-141 does it: drop fenced code
# blocks, then count non-whitespace characters. Messages under CLAUDISH_MIN_CHARS
# (default 200) are never rewritten, so they can never be spoken either.
: > "$ODIR/scored.tsv"
n=0
while IFS= read -r line; do
  n=$((n + 1))
  txt="$(printf '%s' "$line" | jq -r '.txt')"
  meta="$(printf '%s' "$line" | jq -r '"\(.sess):\(.uuid)"')"
  prose_len="$(printf '%s' "$txt" \
    | awk 'BEGIN{f=0} /^```/{f=!f; next} f==0{print}' \
    | tr -d '[:space:]' | wc -c | tr -d ' ')"
  printf '%s\t%s\t%s\t%s\n' "$n" "$prose_len" "${#txt}" "$meta" >> "$ODIR/scored.tsv"
done < "$ODIR/all.jsonl"

printf 'extracted %s assistant messages -> %s/all.jsonl\n' "$n" "$ODIR"
