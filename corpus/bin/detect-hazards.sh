#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Report which hazard classes are literally present in each corpus item.
#
# This exists so corpus/README.md's coverage table is CHECKED rather than
# asserted. It is a textual detector, not a phonemiser: it answers "does this
# item contain a token of class X", which is exactly what coverage means here.
# It cannot and does not say how anything sounds.
#
# Class ids and the behaviour each one names are defined in corpus/README.md,
# sourced from docs/research/kokoro-text-handling.md (#3) and
# docs/research/kokoro-programming-text-audio.md (#10).
#
# Usage: detect-hazards.sh <file>...          # one row per file
#        detect-hazards.sh corpus/spoken/*.txt
# Output: <id>\t<prose_len>\t<bytes>\t<lines>\t<comma separated class ids>
# ---------------------------------------------------------------------------
set -uo pipefail

for f in "$@"; do
  [ -f "$f" ] || continue
  id="$(basename "$f" .txt)"
  # Body with fenced code blocks removed, for the prose_len gate only.
  prose_len="$(awk 'BEGIN{c=0} /^```/{c=!c; next} c==0{print}' "$f" \
    | tr -d '[:space:]' | wc -c | tr -d ' ')"
  bytes="$(wc -c < "$f" | tr -d ' ')"
  lines="$(wc -l < "$f" | tr -d ' ')"

  h=""
  add() { h="$h$1,"; }

  # --- markdown ----------------------------------------------------------
  grep -q '\*'                            "$f" && add MD-ASTERISK
  grep -qE '^#{1,6} '                     "$f" && add MD-HASH
  grep -qE '_[A-Za-z][A-Za-z ]*_'         "$f" && add MD-UNDERSCORE
  grep -q '`'                             "$f" && add MD-BACKTICK
  grep -q '```'                           "$f" && add MD-FENCE
  grep -qE '^[[:space:]]*- '              "$f" && add MD-BULLET
  grep -qE '^[[:space:]]*[0-9]+\. '       "$f" && add MD-ORDERED
  grep -qE '^[[:space:]]*> '              "$f" && add MD-BLOCKQUOTE
  grep -qE '^\|'                          "$f" && add MD-PIPE

  # --- identifiers -------------------------------------------------------
  grep -qE '[A-Z][A-Z0-9]*_[A-Z0-9_]+'    "$f" && add ID-SCREAM
  grep -qE '[a-z][a-z0-9]*_[a-z0-9_]+'    "$f" && add ID-SNAKE
  grep -qE '[a-z]+[A-Z][a-z]+'            "$f" && add ID-CAMEL
  grep -qE '[a-z]+-case'                  "$f" && add ID-KEBAB
  grep -qE '\b(JSON|API|HTTP|HTTPS|TTS|G2P|ONNX|CLI|URL|MLX)\b' "$f" && add ID-ACRONYM
  grep -qE '\b(jq|npm|cd|stdin|sh|git)\b' "$f" && add ID-VOWELLESS
  grep -qE '[A-Za-z_]+=[0-9]'             "$f" && add ID-ASSIGN
  grep -qE '\b[0-9a-f]{7}\b'              "$f" && add ID-SHA

  # --- paths -------------------------------------------------------------
  grep -qE '[A-Za-z0-9_-]+\.(sh|md|json|py|jsonl|wav|dylib|onnx|log|ts|txt)' "$f" && add PATH-EXT
  grep -qE '\.sh, \.py'                   "$f" && add PATH-EXTBARE
  grep -qE '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' "$f" && add PATH-SLASH
  grep -qE '(^| )/[A-Za-z]'               "$f" && add PATH-ABS
  grep -qE '~/'                           "$f" && add PATH-TILDE
  grep -qE '(^| )\.[A-Za-z][A-Za-z0-9_-]*/' "$f" && add PATH-DOTDIR
  grep -qE '\.(sh|py|md|json):[0-9]+'     "$f" && add PATH-LINEREF
  grep -q '::'                            "$f" && add PATH-DBLCOLON
  grep -qE '[a-z]+-[a-z]+\.(sh|py|md)'    "$f" && add PATH-HYPHEN-EXT

  # --- numbers -----------------------------------------------------------
  grep -qE '(^|[^0-9,.])[0-9]{4}([^0-9,.]|$)' "$f" && add NUM-4DIGIT
  grep -qE '[0-9],[0-9]{3}'               "$f" && add NUM-THOUSANDS
  grep -qE 'v?[0-9]+\.[0-9]+\.[0-9]+'     "$f" && add NUM-VERSION
  grep -qE '[0-9]\.[0-9]+x'               "$f" && add NUM-DECIMAL
  grep -qE '[0-9]+(\.[0-9]+)? ?(s|ms|MB|GB|MiB|KB|bytes|seconds|minutes)\b' "$f" && add NUM-UNIT
  grep -qE '[0-9]+ ?%'                    "$f" && add NUM-PERCENT
  grep -qE '\$[0-9]'                      "$f" && add NUM-CURRENCY
  grep -qE '[0-9]+(st|nd|rd|th)\b'        "$f" && add NUM-ORDINAL
  grep -qE '\b(HTTP|http=)[ ]?[0-9]{3}\b' "$f" && add NUM-STATUS
  grep -qE '\b[0-9]{1,2}:[0-9]{2}\b'      "$f" && add NUM-TIME
  grep -qE '[A-Z]+-[0-9]+'                "$f" && add NUM-HYPHEN

  # --- other voiced noise ------------------------------------------------
  grep -qE 'https?://'                    "$f" && add URL
  grep -qE '[✅⚠️💬✦]'                     "$f" && add EMOJI
  grep -q '─'                             "$f" && add GLYPH
  grep -qE '(^| )-[a-zA-Z]( |$|,|\.)'     "$f" && add FLAG-SHORT
  grep -qE ' --[a-z]'                     "$f" && add FLAG-LONG
  grep -qE ' (&|\+) |@[a-z]'              "$f" && add SYM
  grep -qE '\blives\b'                    "$f" && add PROSE-LIVES
  grep -qE '\[[^]]+\]\(/[^)]*/\)'         "$f" && add OVERRIDE

  # --- length and chunking ------------------------------------------------
  [ "$prose_len" -lt 200 ] && add LEN-UNDER
  [ "$prose_len" -ge 200 ] && [ "$prose_len" -le 260 ] && add LEN-OVER
  # A single line longer than ~520 characters exceeds the 510-phoneme budget
  # (measured at roughly one phoneme per character, kokoro-text-handling.md §6)
  # and is the only way to reach the chunker: KPipeline splits on \n+ first.
  if awk 'length($0) > 520 {found=1} END{exit !found}' "$f"; then
    if grep -qE '[.!?]' "$f"; then add CHUNK-510-PUNCT; else add CHUNK-510-NOPUNCT; fi
  fi
  [ "$lines" -gt 1 ] && add SPLIT-NEWLINE

  printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$prose_len" "$bytes" "$lines" "${h%,}"
done
