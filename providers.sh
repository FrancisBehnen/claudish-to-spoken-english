#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Provider layer for claudish-to-english. Sourced by rewrite.sh and
# rewrite-md.sh — not executed directly.
#
# One function does the work: llm_complete SYSTEM USER runs a single chat
# completion against the configured provider and sets these globals:
#   rewrite   the completion text ("" on any failure)
#   curl_rc   curl exit code (0 unless transport failed; 1 when no API key).
#             The claude-cli provider has no curl, so it reuses this field for
#             the subprocess outcome: 127 = binary not on PATH, 28 = timed out
#             (curl's own timeout code, so the wording downstream still fits),
#             otherwise the CLI's exit status.
#   err       provider error message ("" when none)
#   http      HTTP status of the response ("" when unknown; cloud providers only)
#   ratelimited 1 when the provider refused for quota reasons (claude-cli only)
#   truncated 1 when the completion hit an output-token cap and was discarded
# It returns 2 when the JSON request body could not be built, 0 otherwise.
# llm_notice_why then maps a failure onto NOTICE_WHY, a one-line reason fit
# for the once-per-session setup notice ("" when the skip should stay
# silent — an empty completion with no transport error).
#
# Providers (CLAUDISH_PROVIDER):
#   ollama     (default) local ollama at CLAUDISH_OLLAMA
#   anthropic  Anthropic Messages API; key from CLAUDISH_ANTHROPIC_KEY or
#              ANTHROPIC_API_KEY; base URL from CLAUDISH_ANTHROPIC_URL
#   openai     any OpenAI-compatible /chat/completions endpoint (OpenAI,
#              LM Studio, llama.cpp server, vLLM, OpenRouter, ...); base URL
#              from CLAUDISH_OPENAI_URL, key from CLAUDISH_OPENAI_KEY or
#              OPENAI_API_KEY. A key is only required for the default
#              api.openai.com URL — local servers work keyless.
#   claude-cli the local `claude` CLI in print mode, so rewrites run on this
#              machine's Claude Code SUBSCRIPTION instead of a metered API
#              key. No key, no local model. Binary from CLAUDISH_CLAUDE_BIN
#              (default `claude`). This is the one provider that is a
#              subprocess rather than an HTTP call, so it has no HTTP status
#              and needs its own timeout — see _llm_run_bounded.
#              NOTE: rewrites consume the same 5-hour and 7-day subscription
#              windows as your real Claude Code work.
#
# Extra config:
#   CLAUDISH_MODEL          overrides the per-provider default model
#   CLAUDISH_MAX_TOKENS     completion cap for the anthropic provider (default
#                           4096; the Messages API requires an explicit cap)
#   CLAUDISH_OPENAI_EFFORT  reasoning_effort for the openai provider. Unset
#                           defaults to "none" against api.openai.com
#                           (GPT-5.6-class models otherwise burn reasoning
#                           tokens on a plain rewrite) and to omitted against
#                           custom compat URLs (some local servers reject
#                           unknown fields). Set it EMPTY
#                           (CLAUDISH_OPENAI_EFFORT=) to force the field off
#                           even for api.openai.com — needed for models that
#                           reject reasoning_effort entirely.
#
# The caller must define dbg() and set LLM_TIMEOUT before calling
# llm_complete, and may set TIMEOUT_HINT to customize llm_notice_why's
# timed-out advice. Fail-open stays the caller's job: every failure here
# comes back as an empty $rewrite, never an exit.
# ---------------------------------------------------------------------------

PROVIDER="${CLAUDISH_PROVIDER:-ollama}"
OLLAMA="${CLAUDISH_OLLAMA:-http://localhost:11434}"
ANTHROPIC_KEY="${CLAUDISH_ANTHROPIC_KEY:-${ANTHROPIC_API_KEY:-}}"
OPENAI_KEY="${CLAUDISH_OPENAI_KEY:-${OPENAI_API_KEY:-}}"
OPENAI_URL="${CLAUDISH_OPENAI_URL:-https://api.openai.com/v1}"
ANTHROPIC_URL="${CLAUDISH_ANTHROPIC_URL:-https://api.anthropic.com}"
MAX_TOKENS="${CLAUDISH_MAX_TOKENS:-4096}"
CLAUDE_BIN="${CLAUDISH_CLAUDE_BIN:-claude}"

# Normalize away trailing slashes BEFORE any URL comparison, so
# ".../v1/" gets the same key requirement and effort default as ".../v1".
while [ "${OPENAI_URL%/}" != "$OPENAI_URL" ]; do OPENAI_URL="${OPENAI_URL%/}"; done
while [ "${ANTHROPIC_URL%/}" != "$ANTHROPIC_URL" ]; do ANTHROPIC_URL="${ANTHROPIC_URL%/}"; done

# An explicitly set CLAUDISH_OPENAI_EFFORT always wins — including an
# explicitly EMPTY one, which omits the field (the escape hatch for models
# that reject reasoning_effort). Only when unset does the api.openai.com
# default of "none" apply.
if [ -n "${CLAUDISH_OPENAI_EFFORT+x}" ]; then
  OPENAI_EFFORT="$CLAUDISH_OPENAI_EFFORT"
elif [ "$OPENAI_URL" = "https://api.openai.com/v1" ]; then
  OPENAI_EFFORT="none"
else
  OPENAI_EFFORT=""
fi

case "$PROVIDER" in
  anthropic)  MODEL="${CLAUDISH_MODEL:-claude-haiku-4-5}" ;;
  openai)     MODEL="${CLAUDISH_MODEL:-gpt-5.6-luna}" ;;
  # An alias, not a full model id: the CLI resolves 'haiku' to whatever the
  # latest Haiku is, which is what a display rewrite wants.
  claude-cli) MODEL="${CLAUDISH_MODEL:-haiku}" ;;
  *)          MODEL="${CLAUDISH_MODEL:-gemma4:26b-mlx}" ;;
esac

# Opt-in, and EMPTY by default. A rewrite needs no tools, so blocking them
# looks free — but `--disallowed-tools` validates every name against the CLI's
# tool registry and exits on the first one it doesn't know ("Permission deny
# rule "MultiEdit" matches no known tool"), which killed every rewrite on
# CLI 2.1.233 until MultiEdit came out of this list. A hard-coded tool list in
# a display hook is a hostage to the next tool rename, and it fails loudly
# rather than quietly. Real containment against a wedged or tool-happy child is
# the watchdog in _llm_run_bounded plus a system prompt that asks only for the
# rewrite. Set CLAUDISH_CLAUDE_DISALLOW="Bash Read Edit" to tighten it yourself.
read -r -a CLAUDE_CLI_DISALLOW <<< "${CLAUDISH_CLAUDE_DISALLOW:-}"

# Split the "\n<status>" suffix appended by curl -w '\n%{http_code}' off $resp
# into $http. "000" (no response at all) is normalized to "".
_llm_split_status() {
  _nl='
'
  http="${resp##*"$_nl"}"
  case "$http" in
    [0-9][0-9][0-9]) resp="${resp%"$_nl"*}" ;;
    *)               http="" ;;
  esac
  [ "$http" = "000" ] && http=""
  return 0
}

# Write 'header = "<name>: <key>"' into a private (0600) temp file for
# curl -K, keeping the key off the curl command line — argv is visible to
# every local user via ps. Prints the file path; prints nothing on failure.
_llm_key_file() {
  _kf="$(mktemp "${TMPDIR:-/tmp}/claudish-key.XXXXXX" 2>/dev/null)" || return 0
  _kv="$2"
  _kv="${_kv//\\/\\\\}"; _kv="${_kv//\"/\\\"}"
  printf 'header = "%s: %s"\n' "$1" "$_kv" > "$_kf" 2>/dev/null \
    || { rm -f "$_kf" 2>/dev/null; return 0; }
  # curl accepts an EMPTY -K file and would proceed unauthenticated; a partial
  # write (ENOSPC) must therefore fail here, not at the endpoint.
  [ -s "$_kf" ] || { rm -f "$_kf" 2>/dev/null; return 0; }
  printf '%s' "$_kf"
}

# Run a command with $_user on stdin, stdout to $2 and stderr to $3, bounded to
# $1 seconds. Sets _rc to the command's exit status, or 28 when the bound fired
# (curl's timeout code, so downstream wording about timeouts still applies).
#
# The HTTP providers get their bound free from `curl --max-time`. A subprocess
# provider has to bring its own, and macOS ships no timeout(1) — so the bound
# is a watchdog subshell that TERMs, waits, then KILLs. This is not optional
# politeness: rewrite.sh is a MessageDisplay hook, and an unbounded child would
# let a wedged CLI stall the assistant's answer, breaking the fail-open
# contract that the rest of this file exists to uphold.
_llm_run_bounded() {
  _to="$1"; _ofile="$2"; _efile="$3"; shift 3
  printf '%s' "$_user" | "$@" > "$_ofile" 2> "$_efile" &
  _cpid=$!   # last element of the pipeline — the command, not printf
  (
    _i=0
    while [ "$_i" -lt "$_to" ]; do
      # Once the parent's `wait` below reaps the child this fails, which is how
      # the watchdog learns the command finished on its own.
      kill -0 "$_cpid" 2>/dev/null || exit 0
      sleep 1
      _i=$((_i + 1))
    done
    kill -TERM "$_cpid" 2>/dev/null
    sleep 2
    kill -KILL "$_cpid" 2>/dev/null
  ) &
  _wpid=$!
  wait "$_cpid" 2>/dev/null; _rc=$?
  # A killed child is reported as a timeout: the watchdog is the only thing
  # that signals it, short of the whole hook being torn down (in which case
  # the child dies with it and nothing downstream is read anyway).
  case "$_rc" in 143|137) _rc=28 ;; esac
  kill -TERM "$_wpid" 2>/dev/null
  wait "$_wpid" 2>/dev/null
  return 0
}

llm_complete() {
  _sys="$1"; _user="$2"
  rewrite=""; curl_rc=0; err=""; resp=""; http=""; finish=""; truncated=0
  hdrfile=""; cfgerr=0; ratelimited=0
  case "$PROVIDER" in
    anthropic)
      if [ -z "$ANTHROPIC_KEY" ]; then dbg "anthropic: no key"; curl_rc=1; return 0; fi
      # No temperature: current Anthropic models reject sampling parameters.
      req="$(jq -n --arg m "$MODEL" --argjson t "$MAX_TOKENS" --arg s "$_sys" --arg u "$_user" \
            '{model:$m,max_tokens:$t,system:$s,messages:[{role:"user",content:$u}]}' 2>/dev/null)"
      [ -n "$req" ] || return 2
      hdrfile="$(_llm_key_file "x-api-key" "$ANTHROPIC_KEY")"
      if [ -z "$hdrfile" ]; then
        cfgerr=1
        err="could not create a private temp file for the API key under ${TMPDIR:-/tmp} — nothing was sent"
        return 0
      fi
      # If the hook is killed mid-request the file must not linger in TMPDIR.
      # Single quotes: $hdrfile expands when the trap FIRES, immune to quoting
      # in the path (it is always set — reset to "" at the top of this call).
      trap 'rm -f "$hdrfile" 2>/dev/null' EXIT
      resp="$(printf '%s' "$req" | curl -sS --max-time "$LLM_TIMEOUT" -w '\n%{http_code}' \
              -K "$hdrfile" -H 'Content-Type: application/json' \
              -H 'anthropic-version: 2023-06-01' \
              -X POST "$ANTHROPIC_URL/v1/messages" -d @- 2>/dev/null)"
      curl_rc=$?
      rm -f "$hdrfile" 2>/dev/null
      _llm_split_status
      # Join text blocks: models with thinking enabled emit non-text blocks first.
      rewrite="$(printf '%s' "$resp" | jq -j 'if (.content|type)=="array" then ([.content[] | select(.type=="text") | .text] | join("")) else empty end' 2>/dev/null)"
      err="$(printf '%s' "$resp" | jq -r '.error.message // empty' 2>/dev/null)"
      finish="$(printf '%s' "$resp" | jq -r '.stop_reason // empty' 2>/dev/null)"
      [ "$finish" = "max_tokens" ] && { truncated=1; rewrite=""; }
      ;;
    openai)
      if [ -z "$OPENAI_KEY" ] && [ "$OPENAI_URL" = "https://api.openai.com/v1" ]; then
        dbg "openai: no key"; curl_rc=1; return 0
      fi
      # No temperature or token cap: reasoning-tier OpenAI models reject
      # non-default sampling, and compat servers disagree on the cap's name.
      req="$(jq -n --arg m "$MODEL" --arg s "$_sys" --arg u "$_user" --arg e "$OPENAI_EFFORT" \
            '{model:$m,messages:[{role:"system",content:$s},{role:"user",content:$u}]}
             + (if $e == "" then {} else {reasoning_effort:$e} end)' 2>/dev/null)"
      [ -n "$req" ] || return 2
      auth=()
      if [ -n "$OPENAI_KEY" ]; then
        hdrfile="$(_llm_key_file "Authorization" "Bearer $OPENAI_KEY")"
        if [ -z "$hdrfile" ]; then
          cfgerr=1
          err="could not create a private temp file for the API key under ${TMPDIR:-/tmp} — nothing was sent"
          return 0
        fi
        trap 'rm -f "$hdrfile" 2>/dev/null' EXIT
        auth=(-K "$hdrfile")
      fi
      resp="$(printf '%s' "$req" | curl -sS --max-time "$LLM_TIMEOUT" -w '\n%{http_code}' \
              -H 'Content-Type: application/json' ${auth[@]+"${auth[@]}"} \
              -X POST "$OPENAI_URL/chat/completions" -d @- 2>/dev/null)"
      curl_rc=$?
      [ -n "${hdrfile:-}" ] && rm -f "$hdrfile" 2>/dev/null
      _llm_split_status
      rewrite="$(printf '%s' "$resp" | jq -j '.choices[0].message.content // empty' 2>/dev/null)"
      err="$(printf '%s' "$resp" | jq -r 'if (.error|type)=="object" then (.error.message // empty) else (.error // empty) end' 2>/dev/null)"
      finish="$(printf '%s' "$resp" | jq -r '.choices[0].finish_reason // empty' 2>/dev/null)"
      [ "$finish" = "length" ] && { truncated=1; rewrite=""; }
      ;;
    claude-cli)
      if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
        dbg "claude-cli: '$CLAUDE_BIN' not on PATH"; curl_rc=127; return 0
      fi
      ofile="$(mktemp "${TMPDIR:-/tmp}/claudish-cli-out.XXXXXX" 2>/dev/null)" || { cfgerr=1; err="could not create a temp file under ${TMPDIR:-/tmp} — nothing was sent"; return 0; }
      efile="$(mktemp "${TMPDIR:-/tmp}/claudish-cli-err.XXXXXX" 2>/dev/null)" || { rm -f "$ofile" 2>/dev/null; cfgerr=1; err="could not create a temp file under ${TMPDIR:-/tmp} — nothing was sent"; return 0; }
      trap 'rm -f "$ofile" "$efile" 2>/dev/null' EXIT
      # The message goes on STDIN, never argv: real rewrites can be long and
      # ARG_MAX is finite. --input-format text (the CLI's default) reads it.
      # Piping also sidesteps the 3-second wait the CLI spends on an open-but-
      # silent stdin, so no `< /dev/null` is needed here.
      #
      # CLAUDISH_ENABLED=0 is the recursion guard, and it is load-bearing: this
      # hook is installed globally, so the child session loads it too. Both
      # hooks read the variable early and bail (rewrite.sh:56, rewrite-md.sh:57),
      # so the child cannot spawn a grandchild. --bare would be the obvious way
      # to skip hooks but reads auth ONLY from ANTHROPIC_API_KEY/apiKeyHelper,
      # never OAuth or the keychain — which would defeat the whole point of
      # running on the subscription.
      #
      # --strict-mcp-config with no --mcp-config loads NO MCP servers: booting
      # a full MCP fleet per displayed message would be ruinous.
      deny=()
      [ "${#CLAUDE_CLI_DISALLOW[@]}" -gt 0 ] \
        && deny=(--disallowed-tools "${CLAUDE_CLI_DISALLOW[@]}")
      _llm_run_bounded "$LLM_TIMEOUT" "$ofile" "$efile" \
        env CLAUDISH_ENABLED=0 "$CLAUDE_BIN" \
            -p --model "$MODEL" --system-prompt "$_sys" \
            --strict-mcp-config --no-session-persistence \
            --output-format text ${deny[@]+"${deny[@]}"}
      curl_rc=$_rc
      rewrite="$(cat "$ofile" 2>/dev/null)"
      diag="$(head -c 2000 "$efile" 2>/dev/null)"
      if [ "$curl_rc" != "0" ]; then
        # On a failed run stdout is diagnostics, not a rewrite — showing it to
        # the user as their own message in plain English would be worse than
        # showing nothing. Prefer stderr, fall back to whatever stdout holds.
        diag="${diag:-$rewrite}"
        rewrite=""
      fi
      rm -f "$ofile" "$efile" 2>/dev/null
      # Quota refusal only ever gets read out of the DIAGNOSTICS, never out of a
      # successful rewrite — an assistant message about rate limiting rewrites
      # into a rewrite about rate limiting, and that must not trip this.
      if [ -z "$rewrite" ] && printf '%s' "$diag" | grep -qiE 'usage limit|rate limit|rate.limited|out of (quota|credits)|quota exceeded'; then
        ratelimited=1
      fi
      # First non-empty line, so a stack trace becomes one notice-sized line.
      [ -n "$diag" ] && err="$(printf '%s' "$diag" | grep -v '^[[:space:]]*$' | head -1)"
      ;;
    *)
      req="$(jq -n --arg m "$MODEL" --arg s "$_sys" --arg u "$_user" \
            '{model:$m,stream:false,think:false,options:{temperature:0.3},messages:[{role:"system",content:$s},{role:"user",content:$u}]}' 2>/dev/null)"
      [ -n "$req" ] || return 2
      resp="$(printf '%s' "$req" | curl -sS --max-time "$LLM_TIMEOUT" \
              -H 'Content-Type: application/json' -X POST "$OLLAMA/api/chat" -d @- 2>/dev/null)"
      curl_rc=$?
      rewrite="$(printf '%s' "$resp" | jq -j '.message.content // empty' 2>/dev/null)"
      err="$(printf '%s' "$resp" | jq -r '.error // empty' 2>/dev/null)"
      # ollama reports output-cap truncation as done_reason "length"; a
      # half-finished rewrite must be discarded like on the cloud providers.
      # (Response-side only — the request stays byte-identical to before.)
      finish="$(printf '%s' "$resp" | jq -r '.done_reason // empty' 2>/dev/null)"
      [ "$finish" = "length" ] && { truncated=1; rewrite=""; }
      ;;
  esac

  # Cloud providers: an HTTP error whose body carried no parseable message
  # (an HTML 404 from a URL that isn't an API, a bare 502 from a proxy) must
  # not turn into a silent skip forever — give the notice something to say.
  # A 2xx with an empty completion stays silent, as before.
  if [ "$PROVIDER" != "ollama" ] && [ -z "$rewrite" ] && [ -z "$err" ] \
     && [ "$curl_rc" = "0" ] && [ "$truncated" = "0" ] && [ -n "$http" ]; then
    case "$http" in
      2??) ;;
      # Server-side trouble: the URL is probably fine, the endpoint isn't.
      5??|429) err="HTTP $http from the endpoint — it may be down, overloaded, or rate-limiting" ;;
      *)   case "$PROVIDER" in
             anthropic) err="HTTP $http with no error message in the response — check that CLAUDISH_ANTHROPIC_URL points at an Anthropic-compatible API base URL" ;;
             *)         err="HTTP $http with no error message in the response — check that CLAUDISH_OPENAI_URL points at an OpenAI-compatible API base URL (usually ending in /v1)" ;;
           esac ;;
    esac
  fi

  dbg "$PROVIDER model=$MODEL curl_rc=$curl_rc http=${http:-none} resp_bytes=${#resp} rewrite_bytes=${#rewrite} truncated=$truncated err=${err:-none}"
  return 0
}

llm_notice_why() {
  # shellcheck disable=SC2034  # NOTICE_WHY is read by the sourcing scripts
  NOTICE_WHY=""
  case "$PROVIDER" in
    anthropic)
      if [ -z "$ANTHROPIC_KEY" ]; then
        NOTICE_WHY="no Anthropic API key in this session's environment (set CLAUDISH_ANTHROPIC_KEY or ANTHROPIC_API_KEY), so rewrites are off"
      elif [ "${cfgerr:-0}" = "1" ]; then
        NOTICE_WHY="${err:-provider configuration error}"
      elif [ "${truncated:-0}" = "1" ]; then
        NOTICE_WHY="the rewrite hit the ${MAX_TOKENS}-token output cap and was discarded rather than shown half-finished — raise CLAUDISH_MAX_TOKENS"
      elif [ -n "${err:-}" ]; then
        NOTICE_WHY="Anthropic API error: ${err}"
      elif [ "$curl_rc" = "28" ]; then
        NOTICE_WHY="the rewrite timed out after ${LLM_TIMEOUT}s — ${TIMEOUT_HINT:-raise the timeout}"
      elif [ "$curl_rc" != "0" ]; then
        NOTICE_WHY="cannot reach ${ANTHROPIC_URL} (curl exit $curl_rc)"
      fi
      ;;
    openai)
      if [ -z "$OPENAI_KEY" ] && [ "$OPENAI_URL" = "https://api.openai.com/v1" ]; then
        NOTICE_WHY="no OpenAI API key in this session's environment (set CLAUDISH_OPENAI_KEY or OPENAI_API_KEY), so rewrites are off"
      elif [ "${cfgerr:-0}" = "1" ]; then
        NOTICE_WHY="${err:-provider configuration error}"
      elif [ "${truncated:-0}" = "1" ]; then
        NOTICE_WHY="the rewrite hit the model's output-token limit and was discarded rather than shown half-finished — use a shorter message, or raise the completion cap if you run the server yourself"
      elif [ -n "${err:-}" ]; then
        NOTICE_WHY="OpenAI API error: ${err}"
      elif [ "$curl_rc" = "28" ]; then
        NOTICE_WHY="the rewrite timed out after ${LLM_TIMEOUT}s — ${TIMEOUT_HINT:-raise the timeout}"
      elif [ "$curl_rc" != "0" ]; then
        NOTICE_WHY="cannot reach ${OPENAI_URL} (curl exit $curl_rc)"
      fi
      ;;
    claude-cli)
      # Ordered by how actionable the cause is, quota before the generic
      # failure branches because it is the one users will actually hit.
      if [ "$curl_rc" = "127" ]; then
        NOTICE_WHY="the \`$CLAUDE_BIN\` CLI isn't on this session's PATH, so rewrites are off — set CLAUDISH_CLAUDE_BIN to its full path"
      elif [ "${cfgerr:-0}" = "1" ]; then
        NOTICE_WHY="${err:-provider configuration error}"
      elif [ "${ratelimited:-0}" = "1" ]; then
        NOTICE_WHY="your Claude subscription is out of quota right now, so the rewrite was skipped — rewrites spend the same 5-hour and 7-day windows as your real Claude Code work. Switch CLAUDISH_PROVIDER, raise CLAUDISH_MIN_CHARS, or touch ${CLAUDISH_OFF_FILE:-~/.claude/claudish-off} to pause them"
      elif [ "$curl_rc" = "28" ]; then
        NOTICE_WHY="the rewrite timed out after ${LLM_TIMEOUT}s — ${TIMEOUT_HINT:-raise the timeout}"
      elif [ -n "${err:-}" ]; then
        NOTICE_WHY="the claude CLI failed: ${err}"
      elif [ "$curl_rc" != "0" ]; then
        NOTICE_WHY="the claude CLI exited $curl_rc with no message"
      fi
      ;;
    *)
      # truncated first: it can only occur on a successful response, so none
      # of the pre-existing branches (whose wording must stay byte-identical)
      # can ever fire for the same state.
      if [ "${truncated:-0}" = "1" ]; then
        NOTICE_WHY="the rewrite hit ollama's output-token limit and was discarded rather than shown half-finished — raise the model's output cap (num_predict) or use a shorter message"
      elif [ "$curl_rc" = "28" ]; then
        NOTICE_WHY="the rewrite timed out after ${LLM_TIMEOUT}s (model too slow for this message) — ${TIMEOUT_HINT:-raise the timeout or set CLAUDISH_MODEL to a smaller model}"
      elif [ "$curl_rc" != "0" ]; then
        NOTICE_WHY="can't reach ollama at $OLLAMA — start it with \`ollama serve\` (see the plugin README)"
      elif printf '%s' "${err:-}" | grep -qi 'not found'; then
        NOTICE_WHY="ollama model '$MODEL' isn't available — pull it with \`ollama pull $MODEL\`, or set CLAUDISH_MODEL to a model you have"
      elif [ -n "${err:-}" ]; then
        NOTICE_WHY="ollama returned an error: ${err}"
      fi
      ;;
  esac
}
