#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Time ONE rewrite of ONE message through the real provider path, and stop.
#
# #14 asks whether claude-cli's near-flat latency curve still holds at the
# message size that times out on ollama (~1,200-1,400 words). The 12 corpus
# measurements in capture-log.tsv top out at 663 source words, so the answer is
# an extrapolation until somebody spends one call at twice that size. This is
# the script that spends it.
#
# A sibling of capture-real-rewrites.sh, not a loop over it. Same provider path,
# same system prompt, same two traps defused -- but ONE item, no MAX_ITEMS, no
# resume, and no retry of any kind. A latency measurement that retries is a
# latency measurement of the second attempt.
#
# COST: one call against the user's Claude Code subscription, on the same 5-hour
# and 7-day windows as their real work. The guard below refuses to overwrite an
# existing output file, so a re-run cannot silently spend a second call.
#
# The two traps this shares with capture-real-rewrites.sh, both documented in
# docs/decisions/provider-switch-traps.md:
#   1. This machine sets CLAUDISH_MODEL=qwen3:4b-instruct-2507-q4_K_M in the env
#      block of ~/.claude/settings.json, for the ollama path. providers.sh:92
#      hands CLAUDISH_MODEL to the claude CLI as --model verbatim, so left set it
#      would fail the call. It is unset below, BEFORE providers.sh is sourced --
#      providers.sh resolves PROVIDER and MODEL at source time (providers.sh:61,
#      :87-94), so exporting afterwards would be too late.
#   2. providers.sh is a LIBRARY: the caller must define dbg() and set
#      LLM_TIMEOUT before calling llm_complete. Both are done below.
#
# LLM_TIMEOUT defaults to 120s, well above the display hook's own 45s
# (rewrite.sh:65) and above its 60s hooks.json ceiling (hooks/hooks.json:9). That
# is deliberate: the question is "how many seconds does this take", and a bound
# at 45 would answer it with the word "timeout". Compare the measured number
# against 45 afterwards; that comparison is the finding.
#
# Usage: time-one-rewrite.sh <input.txt> <output.txt>
# Prints one TSV line to stdout: words chars rc ratelimited truncated secs bytes
# ---------------------------------------------------------------------------
set -uo pipefail

SRC="${1:?input text file}"
OUT="${2:?output file for the rewrite}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"

[ -r "$SRC" ] || { printf 'cannot read %s\n' "$SRC" >&2; exit 1; }
[ -e "$OUT" ] && { printf 'refusing to spend a call: %s already exists\n' "$OUT" >&2; exit 1; }

export CLAUDISH_PROVIDER=claude-cli
unset CLAUDISH_MODEL                     # trap 1; let providers.sh pick `haiku`
LLM_TIMEOUT="${LLM_TIMEOUT:-120}"

dbg() { [ "${TIME_ONE_DEBUG:-0}" = "1" ] && printf 'dbg: %s\n' "$*" >&2; return 0; }

. "$REPO/providers.sh" || { printf 'cannot source %s/providers.sh\n' "$REPO" >&2; exit 1; }

# Verbatim from rewrite.sh:170, like capture-real-rewrites.sh. Copied rather
# than paraphrased: a different prompt measures a different thing.
SYS="You rewrite the assistant's message into much simpler, plain English. Keep every fact, name, number, and file path. Use short sentences and everyday words. Leave fenced code blocks unchanged. Output ONLY the rewritten message with no preamble, labels, or commentary."

msg="$(cat "$SRC")"
[ -n "$msg" ] || { printf 'empty input\n' >&2; exit 1; }
words="$(wc -w < "$SRC" | tr -d ' ')"
chars="$(wc -c < "$SRC" | tr -d ' ')"

printf 'provider=%s model=%s timeout=%ss input=%sw/%sc\n' \
  "$PROVIDER" "$MODEL" "$LLM_TIMEOUT" "$words" "$chars" >&2

# Sub-second, because the whole question is where between 13s and 45s this lands.
# `date +%s` would report 45.9s as 45.
now() { python3 -c 'import time; print("%.3f" % time.time())'; }

t0="$(now)"
llm_complete "$SYS" "$msg"
rc=$?
t1="$(now)"
secs="$(python3 -c "print('%.2f' % ($t1 - $t0))")"

if [ "$rc" = "2" ]; then
  printf '%s\t%s\treq-build-failed\t\t\t%s\t0\n' "$words" "$chars" "$secs"
  exit 1
fi

bytes=0
if [ -n "$rewrite" ]; then
  printf '%s' "$rewrite" > "$OUT"
  bytes="$(wc -c < "$OUT" | tr -d ' ')"
fi

# An empty rewrite is REPORTED, never retried.
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$words" "$chars" "${curl_rc:-}" "${ratelimited:-0}" "${truncated:-0}" "$secs" "$bytes"
[ -n "${err:-}" ] && printf 'err: %s\n' "$(printf '%s' "$err" | head -1)" >&2
exit 0
