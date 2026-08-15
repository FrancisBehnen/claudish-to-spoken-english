#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Rebuild corpus/manifest.tsv from the two committed inputs:
#   corpus/spoken/*.txt  the items themselves  -> measured columns + hazards
#   corpus/notes.tsv     hand-maintained       -> origin and note columns
#
# Run this after adding, removing or editing any item, so the manifest can never
# quietly disagree with the files it describes.
#
# Usage: build-manifest.sh [corpus-dir]
# ---------------------------------------------------------------------------
set -uo pipefail
CORPUS="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$CORPUS/manifest.tsv"
TMP="$(mktemp "${TMPDIR:-/tmp}/claudish-manifest.XXXXXX")" || exit 1
trap 'rm -f "$TMP" 2>/dev/null' EXIT

bash "$HERE/detect-hazards.sh" "$CORPUS"/spoken/*.txt > "$TMP" || exit 1

{
  printf 'id\tkind\tprose_len\tbytes\tlines\thazard_classes\torigin\tnote\n'
  while IFS=$'\t' read -r id prose_len bytes lines hazards; do
    case "$id" in
      r*) kind=real ;;
      s*) kind=synthetic ;;
      *)  kind=unknown ;;
    esac
    # Pull origin and note for this id out of notes.tsv (first match wins).
    meta="$(awk -F'\t' -v k="$id" '$1 == k {print $2 "\t" $3; exit}' "$CORPUS/notes.tsv")"
    origin="${meta%%$'\t'*}"
    note="${meta#*$'\t'}"
    [ -n "$meta" ] || { origin="MISSING-FROM-notes.tsv"; note=""; }
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$id" "$kind" "$prose_len" "$bytes" "$lines" "$hazards" "$origin" "$note"
  done < "$TMP"
} > "$OUT"

printf 'wrote %s (%s items)\n' "$OUT" "$(($(wc -l < "$OUT") - 1))"
