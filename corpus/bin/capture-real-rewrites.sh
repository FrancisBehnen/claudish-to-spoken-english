#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Produce corpus/spoken/rNN.txt from corpus/source/rNN.txt by running the real
# plugin rewrite path over each source message.
#
# This is not a re-implementation of rewrite.sh. It sources the plugin's own
# providers.sh and calls llm_complete with the SAME system prompt string
# rewrite.sh uses (rewrite.sh:170), so what lands in corpus/spoken/ is what the
# plugin would actually put on screen — and therefore what a speech path would
# actually have to say.
#
# COST: every item spends the user's Claude Code subscription quota, on the same
# 5-hour and 7-day windows as their real work. The run is capped (MAX_ITEMS) and
# stops immediately on a quota refusal (ratelimited=1). It never retries.
#
# Two traps this script exists to defuse:
#   1. This machine exports CLAUDISH_MODEL=qwen3:4b-instruct-2507-q4_K_M for the
#      ollama path. Left set, providers.sh would hand that string to the claude
#      CLI as --model and every rewrite would fail. It is unset below.
#   2. providers.sh is a LIBRARY: the caller must define dbg() and set
#      LLM_TIMEOUT before calling llm_complete. Both are done below.
#
# Usage: capture-real-rewrites.sh [corpus-dir]
# Writes <corpus>/spoken/rNN.txt on success and appends one row per item to
# <corpus>/capture-log.tsv (id, rc, http, ratelimited, truncated, secs, bytes, err).
# ---------------------------------------------------------------------------
set -uo pipefail

CORPUS="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO="$(cd "$CORPUS/.." && pwd)"
LOG="$CORPUS/capture-log.tsv"

# Cap the spend. 12 items is the corpus size; the headroom covers a retry the
# operator decides to make by hand, not an automatic one.
MAX_ITEMS="${MAX_ITEMS:-20}"

# The claude-cli provider is the only working route on this machine: ollama is
# installed but has zero models pulled, so the default provider cannot answer.
export CLAUDISH_PROVIDER=claude-cli
unset CLAUDISH_MODEL          # trap 1 above; let providers.sh pick `haiku`

# rewrite.sh's default is 45s, sized for a display hook that must never stall.
# Nothing here is on a critical path, and the longest source is ~4 KB, so the
# bound is raised to keep a slow long item from being logged as a false timeout.
LLM_TIMEOUT="${LLM_TIMEOUT:-120}"

# providers.sh calls dbg() unconditionally; it is the caller's to define.
dbg() { [ "${CAPTURE_DEBUG:-0}" = "1" ] && printf '%s\n' "dbg: $*" >&2; return 0; }

. "$REPO/providers.sh" || { printf 'cannot source %s/providers.sh\n' "$REPO" >&2; exit 1; }

# Verbatim from rewrite.sh:170. Any drift here makes the corpus unrepresentative,
# which is the whole point of the corpus — so it is copied, not paraphrased.
SYS="You rewrite the assistant's message into much simpler, plain English. Keep every fact, name, number, and file path. Use short sentences and everyday words. Leave fenced code blocks unchanged. Output ONLY the rewritten message with no preamble, labels, or commentary."

mkdir -p "$CORPUS/spoken"
[ -f "$LOG" ] || printf 'id\trc\thttp\tratelimited\ttruncated\tsecs\tbytes\terr\n' > "$LOG"

printf 'provider=%s model=%s timeout=%s max_items=%s\n' \
  "$PROVIDER" "$MODEL" "$LLM_TIMEOUT" "$MAX_ITEMS" >&2

spent=0
for src in "$CORPUS"/source/r*.txt; do
  [ -f "$src" ] || continue
  id="$(basename "$src" .txt)"
  out="$CORPUS/spoken/$id.txt"

  # Idempotent: an already-captured item is never paid for twice.
  if [ -s "$out" ]; then
    printf '%s: already captured, skipping\n' "$id" >&2
    continue
  fi

  if [ "$spent" -ge "$MAX_ITEMS" ]; then
    printf 'stopping: hit MAX_ITEMS=%s\n' "$MAX_ITEMS" >&2
    break
  fi

  # The message is read from the file into a quoted variable and handed to
  # llm_complete as an argument, which puts it on the child's STDIN. It is never
  # spliced into a command line.
  msg="$(cat "$src")"
  [ -n "$msg" ] || { printf '%s: empty source, skipping\n' "$id" >&2; continue; }

  t0="$(date +%s)"
  llm_complete "$SYS" "$msg"
  rc=$?
  t1="$(date +%s)"
  spent=$((spent + 1))

  secs=$((t1 - t0))
  # Collapse the error to one line so the log stays one row per item.
  errline="$(printf '%s' "${err:-}" | tr '\t\n' '  ' | cut -c1-200)"

  if [ "$rc" = "2" ]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$id" "req-build-failed" "" "" "" "$secs" "0" "$errline" >> "$LOG"
    printf '%s: FAILED to build request\n' "$id" >&2
    continue
  fi

  if [ -n "$rewrite" ]; then
    printf '%s' "$rewrite" > "$out"
    bytes="$(wc -c < "$out" | tr -d ' ')"
  else
    bytes=0
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$id" "${curl_rc:-}" "${http:-}" "${ratelimited:-0}" "${truncated:-0}" \
    "$secs" "$bytes" "$errline" >> "$LOG"
  printf '%s: rc=%s bytes=%s %ss\n' "$id" "${curl_rc:-}" "$bytes" "$secs" >&2

  # An empty rewrite is RECORDED, not retried. Retrying a quota refusal in a
  # loop is how a capped capture turns into an uncapped one.
  if [ "${ratelimited:-0}" = "1" ]; then
    printf 'STOPPING: provider refused for quota reasons (ratelimited=1)\n' >&2
    break
  fi
done

printf 'done: %s rewrite call(s) spent this run\n' "$spent" >&2
