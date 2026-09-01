#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# MessageDisplay LLM rewrite hook  (buffer-to-final, fail-open)
#
# Claude Code fires the MessageDisplay event once PER STREAMED CHUNK of an
# assistant message. Each fire is a separate process and carries:
#   .message_id  groups chunks of one message
#   .index       chunk order (0,1,2,...)
#   .final       true on the last chunk
#   .delta       this chunk's text fragment (NOT cumulative)
#
# To rewrite a whole message we buffer every .delta to disk (keyed by
# message_id) and only call the LLM on the final chunk, once the whole
# message is known.
#
# On the final chunk we also read the ORIGINAL USER QUESTION from
# .transcript_path (the last real user message) and pass it to the model as
# CONTEXT ONLY — it helps the rewrite stay on-topic. The model is told never
# to rewrite, answer, or repeat the question; only the assistant message is
# rewritten. Missing/unreadable transcript -> no context, still rewrites.
#
# FAIL-OPEN CONTRACT: on ANY problem (disabled, no jq, parse error, LLM down,
# timeout, empty rewrite) we emit nothing and exit 0, which leaves Claude's
# ORIGINAL text on screen. A display hook must never be able to swallow the
# assistant's answer.
#
# Config (all via env, with safe defaults):
#   CLAUDISH_ENABLED   1|0            master switch (default 1)
#   CLAUDISH_OFF_FILE  <path>         flag file checked per message; when it
#                                          exists, rewrites pause (default
#                                          ~/.claude/claudish-off) — lets a
#                                          hotkey/script toggle mid-session
#   CLAUDISH_MODE      append|replace display strategy (default append)
#   CLAUDISH_PROMPT_FILE <path>       file holding a replacement rewrite prompt
#                                          (whole prompt, not merged; empty or
#                                          unreadable -> built-in default)
#   CLAUDISH_PROVIDER  ollama|anthropic|openai|claude-cli
#                                          which LLM serves rewrites
#                                           (default ollama; keys, base URLs,
#                                           and per-provider model defaults
#                                           are documented in providers.sh)
#   CLAUDISH_MODEL     <model>         overrides the provider's default model
#   CLAUDISH_OLLAMA    <base url>      (default http://localhost:11434)
#   CLAUDISH_MIN_CHARS <n>            skip messages shorter than this
#                                           (prose, code stripped) (default 200)
#   CLAUDISH_STUB      1|0            deterministic stub instead of the LLM
#                                           (for display-mechanics testing)
#   CLAUDISH_TIMEOUT   <seconds>      LLM client timeout (default 120). MUST stay
#                                           at or below hooks/hooks.json's
#                                           MessageDisplay `timeout` (120), which
#                                           bounds this whole PROCESS and so is
#                                           the real ceiling.
#   CLAUDISH_DEBUG     1|0            write a debug log (default 0)
#   CLAUDISH_NOTICE    1|0            once-per-session on-screen notice when the
#                                           rewrite is skipped because the
#                                           provider is unreachable, times out,
#                                           is missing a key or model (default 1)
# ---------------------------------------------------------------------------
set -uo pipefail

ENABLED="${CLAUDISH_ENABLED:-1}"
# Runtime kill switch: env is frozen at session launch, so a hotkey or script
# can't flip CLAUDISH_ENABLED mid-session. A flag file can be checked fresh on
# every invocation. Create it to pause rewrites instantly; remove it to resume.
[ -f "${CLAUDISH_OFF_FILE:-$HOME/.claude/claudish-off}" ] && ENABLED=0
MODE="${CLAUDISH_MODE:-append}"
MIN_CHARS="${CLAUDISH_MIN_CHARS:-200}"
STUB="${CLAUDISH_STUB:-0}"
# 120, raised from 45 for #14.  Two numbers, not one: hooks/hooks.json bounds
# THIS PROCESS, so raising only this one is inert -- the harness would kill the
# hook at the declared hook timeout and the rewrite would publish nothing.  Both
# moved together to 120; speak.sh:MD_TIMEOUT tracks the hooks.json half.
LLM_TIMEOUT="${CLAUDISH_TIMEOUT:-120}"
DEBUG="${CLAUDISH_DEBUG:-0}"
NOTICE="${CLAUDISH_NOTICE:-1}"

BUF_ROOT="${TMPDIR:-/tmp}/claudish-to-english"
SEP=$'\n\n────────────────────────\n💬 In plain English:\n\n'

mkdir -p "$BUF_ROOT" 2>/dev/null || true

dbg() { [ "$DEBUG" = "1" ] && printf '%s [%s] %s\n' "$(date '+%H:%M:%S')" "$$" "$*" >> "$BUF_ROOT/debug.log" 2>/dev/null; return 0; }

# Fail-open: keep the original delta on screen.
pass_through() { dbg "pass_through"; exit 0; }

# Provider layer (ollama/anthropic/openai): MODEL/OLLAMA defaults,
# llm_complete, llm_notice_why. Missing file -> fail open.
. "$(cd "$(dirname "$0")" && pwd)/providers.sh" 2>/dev/null || pass_through

# Replace this chunk's on-screen text with $1 (a temp file, read and then
# removed here — the opportunistic find below only sweeps buffer DIRECTORIES,
# so without this these would pile up in TMPDIR one per assistant message).
emit() {
  jq -n --rawfile dc "$1" \
    '{hookSpecificOutput:{hookEventName:"MessageDisplay",displayContent:$dc}}' \
    2>/dev/null || { rm -f "$1" 2>/dev/null; pass_through; }
  rm -f "$1" 2>/dev/null
  exit 0
}

# Emit an empty string (used to suppress intermediate chunks in replace mode).
emit_empty() {
  jq -n '{hookSpecificOutput:{hookEventName:"MessageDisplay",displayContent:""}}' 2>/dev/null || pass_through
  exit 0
}

# ---- publish text for speak.sh (speech handoff) --------------------------
# Content-addressed: the path is sha256( trim( the SOURCE text ) ) — always
# "$full", never "$1" — so the path is the proof that what we publish belongs
# to the message Claude actually produced, and it is the same key speak.sh
# computes from its own copy of that message. "$1" is what gets SPOKEN, and it
# is not always a rewrite:
#
#   publish_speech "$rewrite"   the normal path, above MIN_CHARS
#   publish_speech "$full"      the short path, below MIN_CHARS, where there
#                               is no rewrite to hand over — the message was
#                               skipped precisely because it is already plain.
#                               Speech has no length floor of its own (the
#                               user's decision, 2026-09-01), so the raw text
#                               is what there is to speak, and starving the
#                               short path was the silence this replaced.
#
# Guarded throughout — temp-write + rename (atomic), every step's failure
# swallowed — so a full disk, an unreadable speak-key.sh, or anything else can
# never change this hook's exit path or one byte of what it displays. The
# display hook's fail-open contract outranks the speech feature absolutely.
# Gated on CLAUDISH_SPEAK, so with speech off a call is one variable test and a
# return. speak-key.sh holds the ONE definition of the key and speak.sh sources
# the same file, so the two sides cannot drift apart; a missing or unreadable
# speak-key.sh just means no publish — and "no publish" is asserted with
# speak-key.sh's `SPEAK_KEY_DEFINED` sentinel rather than `command -v
# speak_key`, which would also be satisfied by a stray `speak_key` on PATH or
# one exported into the environment. Calling that stray would hand this hook a
# key derived by code that is not the one definition (speak.sh, sourcing the
# real file, would then wait on a different path and nothing would ever be
# heard) and would run code we did not intend to run. The sentinel is zeroed
# first so an inherited variable cannot satisfy it.
publish_speech() {
  [ "${CLAUDISH_SPEAK:-0}" = "1" ] || return 0
  SPEAK_KEY_DEFINED=0
  . "$(cd "$(dirname "$0")" 2>/dev/null && pwd)/speak-key.sh" 2>/dev/null
  _sh=""
  [ "$SPEAK_KEY_DEFINED" = "1" ] && _sh="$(speak_key "$full")"
  _sd="$BUF_ROOT/$sid/speak"
  if [ -n "$_sh" ] && mkdir -p "$_sd" 2>/dev/null; then
    _st="$_sd/.rw.$$.$RANDOM"
    { printf '%s' "$1" > "$_st" 2>/dev/null \
      && mv -f "$_st" "$_sd/rw.$_sh" 2>/dev/null; } || rm -f "$_st" 2>/dev/null
    printf '%s' "$(printf '%s' "$payload" | jq -r '.prompt_id // empty' 2>/dev/null)" \
      > "$_sd/prompt_id" 2>/dev/null
    dbg "speak: published rw.$_sh (${#1} bytes)"
  else
    dbg "speak: no publish (no key)"
  fi
  return 0
}

[ "$ENABLED" = "1" ] || pass_through
command -v jq  >/dev/null 2>&1 || pass_through
command -v curl >/dev/null 2>&1 || pass_through

payload="$(cat)"
[ -n "$payload" ] || pass_through

mid="$(printf '%s' "$payload"   | jq -r '.message_id // empty' 2>/dev/null)"
sid="$(printf '%s' "$payload"   | jq -r '.session_id // "nosession"' 2>/dev/null)"
idx="$(printf '%s' "$payload"   | jq -r '(.index // 0) | tostring' 2>/dev/null)"
final="$(printf '%s' "$payload" | jq -r '.final // false' 2>/dev/null)"
tpath="$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)"
[ -n "$mid" ] || pass_through
case "$idx" in ''|*[!0-9]*) idx=0 ;; esac

# Opportunistic cleanup of abandoned buffers (older than 30 min), then of the
# session directories they leave behind once empty.
find "$BUF_ROOT" -mindepth 2 -maxdepth 2 -type d -mmin +30 -exec rm -rf {} + 2>/dev/null || true
find "$BUF_ROOT" -mindepth 1 -maxdepth 1 -type d -empty -mmin +30 -exec rmdir {} + 2>/dev/null || true

mdir="$BUF_ROOT/$sid/$mid"
mkdir -p "$mdir" 2>/dev/null || pass_through

# Persist this chunk's delta exactly (jq -j = no added trailing newline).
printf '%s' "$payload" | jq -j '.delta // ""' > "$mdir/$(printf '%08d' "$idx").part" 2>/dev/null || pass_through
dbg "chunk idx=$idx final=$final mid=$mid mode=$MODE"

# ---- non-final chunks ----------------------------------------------------
if [ "$final" != "true" ]; then
  # append: let the original stream through untouched.
  # replace: suppress the streamed original; the whole rewrite lands on final.
  if [ "$MODE" = "replace" ]; then emit_empty; else pass_through; fi
fi

# ---- final chunk: reconstruct + rewrite ----------------------------------
full="$(cat "$mdir"/*.part 2>/dev/null)"
final_part="$mdir/$(printf '%08d' "$idx").part"

# Prose length gate (strip fenced code blocks, then count non-space chars).
prose_len="$(printf '%s' "$full" \
  | awk 'BEGIN{f=0} /^```/{f=!f; next} f==0{print}' \
  | tr -d '[:space:]' | wc -c | tr -d ' ')"
dbg "final: prose_len=$prose_len min=$MIN_CHARS mode=$MODE full_bytes=${#full}"

cleanup() { rm -rf "$mdir" 2>/dev/null || true; }

# Below threshold -> do not rewrite.
if [ "${prose_len:-0}" -lt "$MIN_CHARS" ]; then
  dbg "skip: below min_chars"
  # No rewrite will ever exist for this message — and speech no longer has a
  # floor of its own, so hand speak.sh the RAW text under the same key rather
  # than leaving the turn silent. Nothing below this line changes: the publish
  # cannot alter what is displayed or how this hook exits.
  publish_speech "$full"
  cleanup
  # replace mode already blanked the intermediate chunks, so it MUST re-show
  # the full original here; append mode already streamed it.
  if [ "$MODE" = "replace" ]; then
    out="$mdir.orig"; printf '%s' "$full" > "$out" 2>/dev/null && emit "$out"
  fi
  pass_through
fi

# ---- obtain the rewrite --------------------------------------------------
rewrite=""
curl_rc=0
err=""
if [ "$STUB" = "1" ]; then
  nparts="$(ls "$mdir"/*.part 2>/dev/null | wc -l | tr -d ' ')"
  rewrite="STUB-SIMPLIFIED ✦ mode=$MODE chunks=$nparts prose_len=$prose_len ✦ (this text came from the hook, not the model)"
  dbg "stub rewrite"
else
  # Base system prompt, replaceable via CLAUDISH_PROMPT_FILE (a file holding the
  # whole prompt). An unset/empty/unreadable file falls back to this default, so
  # a bad path never stops rewrites — it just uses the built-in prompt.
  sys="You rewrite the assistant's message into much simpler, plain English. Keep every fact, name, number, and file path. Use short sentences and everyday words. Leave fenced code blocks unchanged. Output ONLY the rewritten message with no preamble, labels, or commentary."
  if [ -n "${CLAUDISH_PROMPT_FILE:-}" ]; then
    _p=""
    [ -r "$CLAUDISH_PROMPT_FILE" ] && _p="$(cat "$CLAUDISH_PROMPT_FILE" 2>/dev/null)"
    if [ -n "$_p" ]; then
      sys="$_p"
    else
      dbg "CLAUDISH_PROMPT_FILE set but empty/unreadable ($CLAUDISH_PROMPT_FILE); using default prompt"
    fi
  fi

  # Context only: the original user question the assistant is answering.
  # Truncated to 800 codepoints inside jq (safe on multibyte boundaries).
  userq=""
  if [ -n "$tpath" ] && [ -f "$tpath" ]; then
    userq="$(jq -rs '([ .[] | select(.type=="user" and (.message.content|type=="string") and (.isMeta!=true)) | .message.content ] | last // "") | .[0:800]' "$tpath" 2>/dev/null)"
  fi
  if [ -n "$userq" ]; then
    sys="$sys"$'\n\n'"For context, the user asked the assistant: \"$userq\". Use this only to understand the message. Do NOT rewrite, answer, or repeat the user's question — rewrite only the assistant's message that follows."
    dbg "context: userq_bytes=${#userq}"
  fi

  if ! llm_complete "$sys" "$full"; then
    dbg "req build failed"; cleanup
    [ "$MODE" = "replace" ] && { out="$mdir.orig"; printf '%s' "$full" > "$out" && emit "$out"; }
    pass_through
  fi
fi

# Empty/failed rewrite -> fail open (or re-show original in replace mode).
if [ -z "$rewrite" ]; then
  dbg "empty rewrite -> fail open (curl_rc=$curl_rc)"

  # One-time, per-session notice when the cause is a FIXABLE setup problem:
  # provider unreachable (curl_rc!=0 — connection refused, timeout, DNS), a
  # missing API key, or the provider returning an error (e.g. the ollama model
  # was never pulled). A merely empty completion — provider up, no error —
  # stays silent (llm_notice_why leaves NOTICE_WHY empty); a notice would be
  # wrong then. The notice only APPENDS one line to the original; it never
  # suppresses content, so the fail-open contract still holds.
  notified="$BUF_ROOT/$sid.notified"
  # Names the hooks.json ceiling and the provider switch, like
  # rewrite-md.sh:197 already did.  Raising CLAUDISH_TIMEOUT ALONE is inert
  # once it reaches the MessageDisplay hook timeout, so advice that mentions
  # only CLAUDISH_TIMEOUT is advice that does nothing (#14 step 3,
  # docs/decisions/provider-switch-traps.md section 2).
  TIMEOUT_HINT="switch CLAUDISH_PROVIDER, or raise CLAUDISH_TIMEOUT *and* the MessageDisplay hook timeout in hooks.json, or set CLAUDISH_MODEL to a faster model"
  llm_notice_why
  if [ "$NOTICE" = "1" ] && [ ! -e "$notified" ] && [ -n "$NOTICE_WHY" ]; then
    : > "$notified" 2>/dev/null || true
    last_delta="$(cat "$final_part" 2>/dev/null)"
    note=$'\n\n────────────────────────\n'"⚠️ claudish-to-english: $NOTICE_WHY. Showing Claude's original text unchanged. Shown once per session; set CLAUDISH_NOTICE=0 to silence."
    out="$BUF_ROOT/$sid.$mid.notice"
    if [ "$MODE" = "replace" ]; then
      { printf '%s' "$full"; printf '%s' "$note"; } > "$out" 2>/dev/null
    else
      { printf '%s' "$last_delta"; printf '%s' "$note"; } > "$out" 2>/dev/null
    fi
    cleanup
    emit "$out"
  fi

  cleanup
  if [ "$MODE" = "replace" ]; then
    out="$mdir.orig"; printf '%s' "$full" > "$out" 2>/dev/null && emit "$out"
  fi
  pass_through
fi

# ---- publish the rewrite for speak.sh (speech handoff) -------------------
publish_speech "$rewrite"

# ---- build displayContent for the final chunk ----------------------------
out="$BUF_ROOT/$sid.$mid.out"
if [ "$MODE" = "replace" ]; then
  # Everything before was suppressed; show only the rewrite.
  printf '%s' "$rewrite" > "$out"
else
  # append: keep the streamed original (final chunk = its last delta),
  # then append the simplified version.
  { cat "$final_part" 2>/dev/null; printf '%s' "$SEP"; printf '%s' "$rewrite"; } > "$out"
fi
cleanup
emit "$out"
