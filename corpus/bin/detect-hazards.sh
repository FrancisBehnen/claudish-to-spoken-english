#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Report which hazard classes are literally present in each corpus item.
#
# This exists so corpus/README.md's coverage table is CHECKED rather than
# asserted. It is a textual detector, not a phonemiser: it answers "does this
# item contain a token of class X", which is exactly what coverage means here.
# It cannot and does not say how anything sounds.
#
# Class ids and the behaviour each one names are defined in corpus/classes.tsv,
# sourced from docs/research/kokoro-text-handling.md (#3),
# docs/research/kokoro-programming-text-audio.md (#10) and
# docs/research/espeak-sanitizer-rules.md (#8) — the last of which is
# authoritative for chunking, because it is the only one measured against
# kokoro-onnx, the frontend the project actually settled on.
#
# Usage: detect-hazards.sh <file>...          # one row per file
#        detect-hazards.sh corpus/spoken/*.txt
# Output: <id>\t<prose_len>\t<bytes>\t<lines>\t<max_run>\t<comma separated class ids>
# where max_run is the longest run of characters containing no `. , ! ? ;`
# after newlines are removed — the measurement the chunking classes turn on.
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
  # A fence whose BODY holds more than one non-blank line. Same phonemes as any
  # other fence; the difference is that the announcement replacing a skipped
  # block carries a line count (bench/sanitizers.py rule_N_code_block), so the
  # count word cannot be judged from a corpus of one-line blocks.
  awk '
    /^[ \t]*```/ { if (inb) { if (n >= 2) found = 1; inb = 0; n = 0 } \
                   else { inb = 1; n = 0 } ; next }
    inb && NF > 0 { n++ }
    END { exit(found ? 0 : 1) }
  ' "$f" && add MD-FENCE-MULTI
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

  # The real risk metric on kokoro-onnx is the longest run with no `. , ! ? ;`
  # in it, measured AFTER deleting newlines -- because `\n` is not in
  # DEFAULT_VOCAB and is silently dropped, so lines fuse into one run
  # (espeak-sanitizer-rules.md §11). `_split_phonemes` splits on `. , ! ? ;`
  # ONLY; `:` and `—` reach the model but are not boundaries. A run that
  # phonemises to >=510 raises IndexError, and 509 is the last safe batch
  # (§10). English prose measures ~1.02 phonemes per input character.
  #
  # 400 is used as the threshold rather than ~500 because a character count is
  # a HEURISTIC that can under-protect: dense token-heavy text phonemises to
  # well over 1 phoneme per character (an identifier spelled letter by letter
  # is the worst case), so a run can cross 510 phonemes at fewer than 500
  # characters. 400 is the same conservative bound §10's rule A recommends.
  # Only a real phonemiser can settle a specific item; this flags candidates.
  max_run="$(tr -d '\n' < "$f" | tr '.,!?;' '\n' | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')"

  if [ "$max_run" -ge 400 ]; then
    # Over budget with no boundary to back off to: create() raises.
    if [ "$lines" -gt 1 ]; then add CHUNK-LIST-NOPUNCT; else add CHUNK-510-NOPUNCT; fi
  else
    # Under budget per run. If the whole item is nonetheless long enough to
    # need splitting, it is the case that splits CLEANLY.
    [ "$bytes" -gt 520 ] && add CHUNK-510-PUNCT
    # Multi-line with unpunctuated lines, but short enough to be safe: the
    # control that separates the shape from the length.
    if [ "$lines" -gt 1 ] \
       && [ "$(grep -cE '^[[:space:]]*[-*][^.,!?;]*$' "$f")" -ge 2 ]; then
      add CHUNK-LIST-SAFE
    fi
  fi

  [ "$lines" -gt 1 ] && add SPLIT-NEWLINE

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$prose_len" "$bytes" "$lines" "$max_run" "${h%,}"
done
