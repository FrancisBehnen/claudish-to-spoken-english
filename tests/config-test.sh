#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Pin the CONFIG facts that no runtime test can reach, and that #14 moved.
#
#   tests/config-test.sh
#
# Free: nothing here calls a model, spawns a session, plays audio, or spends a
# single token.  Everything is either a `case`/parameter expansion inside
# providers.sh at source time, or a number read out of a file.
#
# Why a suite of its own rather than more cases in speak-selftest.sh: these are
# static assertions with no scratch TMPDIR, no fork and no wall time, and they
# cover the DISPLAY path as much as the speech path.  speak-selftest.sh stays
# the speech suite and its case count stays where it was.
#
# Cases:
#   1  the default provider is claude-cli, and its default model is haiku
#   2  CLAUDISH_PROVIDER still overrides the default (the escape hatch #14's
#      quota tradeoff rests on)
#   3  a stale ollama CLAUDISH_MODEL is IGNORED on claude-cli, not handed to
#      the CLI, which was measured to exit 1 and rewrite nothing
#   4  ... and it is still honoured on the ollama provider, where it is valid
#   5  Bedrock/Vertex model ids survive the guard: they carry a colon too
#   6  a colon-free CLAUDISH_MODEL is passed through untouched, so a typo in a
#      real model name still fails loudly instead of being papered over
#   7  CLAUDISH_TIMEOUT's default does not exceed the MessageDisplay hook
#      timeout, so the LLM budget is never larger than the process spending it
#   8  speak.sh's MD_TIMEOUT equals hooks/hooks.json's declared MessageDisplay
#      timeout.  THIS IS THE ONE THAT MATTERS.  The §3.5.1 clause 3 deadline is
#      min( CLAUDISH_TIMEOUT + 2, MD_TIMEOUT ) + 3, and MD_TIMEOUT is DEFINED
#      as that declared number.  Leave the constant behind when hooks.json
#      moves and rewrites land inside the display budget but outside the speech
#      deadline: displayed, never spoken, and no error anywhere.
#   9  the derived wait actually covers the display budget at the defaults
# ---------------------------------------------------------------------------
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
ok()  { echo "  PASS  $*"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $*"; fail=$((fail + 1)); }

# providers.sh resolves PROVIDER and MODEL at SOURCE time, so each case needs a
# fresh shell with a fresh environment.  `env -i` would drop PATH and HOME and
# break the sourcing itself, so the two CLAUDISH_* vars are unset one by one --
# this machine exports CLAUDISH_MODEL for its own ollama setup, and an inherited
# value would silently answer a different question than the one asked.
resolve() {  # resolve [VAR=VAL ...] -> "provider<TAB>model<TAB>ignored"
  env -u CLAUDISH_PROVIDER -u CLAUDISH_MODEL "$@" bash -c '
    dbg() { :; }
    . "'"$ROOT"'/providers.sh" || exit 1
    printf "%s\t%s\t%s\n" "$PROVIDER" "$MODEL" "$MODEL_IGNORED"
  '
}
field() { printf '%s\n' "$2" | cut -f"$1"; }

echo "--- providers.sh defaults ---"

r="$(resolve)" || { echo "  FAIL  could not source providers.sh"; exit 1; }
p="$(field 1 "$r")"; m="$(field 2 "$r")"
if [ "$p" = "claude-cli" ]; then ok "default provider is claude-cli (was ollama before #14)"
else bad "default provider is '$p', expected claude-cli"; fi
if [ "$m" = "haiku" ]; then ok "default claude-cli model is haiku"
else bad "default claude-cli model is '$m', expected haiku"; fi

r="$(resolve CLAUDISH_PROVIDER=ollama)"
if [ "$(field 1 "$r")" = "ollama" ]; then ok "CLAUDISH_PROVIDER=ollama still overrides the default"
else bad "CLAUDISH_PROVIDER=ollama did not take effect"; fi

echo
echo "--- the stale CLAUDISH_MODEL trap (#14 section 3, traps doc trap 1) ---"

STALE="qwen3:4b-instruct-2507-q4_K_M"
r="$(resolve CLAUDISH_MODEL="$STALE")"
if [ "$(field 2 "$r")" = "haiku" ] && [ "$(field 3 "$r")" = "$STALE" ]; then
  ok "an ollama tag is ignored on claude-cli and recorded in MODEL_IGNORED"
else
  bad "claude-cli would run --model '$(field 2 "$r")'; the CLI exits 1 on that"
fi

r="$(resolve CLAUDISH_PROVIDER=ollama CLAUDISH_MODEL="$STALE")"
if [ "$(field 2 "$r")" = "$STALE" ] && [ -z "$(field 3 "$r")" ]; then
  ok "the same tag is still honoured on the ollama provider"
else
  bad "the guard leaked into the ollama provider: model='$(field 2 "$r")'"
fi

BEDROCK="us.anthropic.claude-haiku-4-5-20251001-v1:0"
r="$(resolve CLAUDISH_MODEL="$BEDROCK")"
if [ "$(field 2 "$r")" = "$BEDROCK" ]; then ok "a Bedrock model id survives the guard (it has a colon too)"
else bad "the guard ate a Bedrock id: model='$(field 2 "$r")'"; fi

r="$(resolve CLAUDISH_MODEL=hiaku)"
if [ "$(field 2 "$r")" = "hiaku" ]; then ok "a colon-free name is passed through, so a typo still fails loudly"
else bad "a colon-free name was rewritten to '$(field 2 "$r")'"; fi

echo
echo "--- the two timeouts, and the speech deadline derived from them ---"

MD_JSON="$(jq -r '.hooks.MessageDisplay[0].hooks[0].timeout' "$ROOT/hooks/hooks.json" 2>/dev/null)"
RW_DEF="$(sed -n 's/^LLM_TIMEOUT="\${CLAUDISH_TIMEOUT:-\([0-9]*\)}"$/\1/p' "$ROOT/rewrite.sh")"
SP_MD="$(sed -n 's/^MD_TIMEOUT=\([0-9]*\)$/\1/p' "$ROOT/speak.sh")"
SP_DEF="$(sed -n 's/^LLM_TIMEOUT="\${CLAUDISH_TIMEOUT:-\([0-9]*\)}"$/\1/p' "$ROOT/speak.sh")"

# A grep that stops matching must FAIL loudly, not compare empty strings and
# quietly pass: this whole section is only worth anything if it still reads the
# live values out of the live files.
for v in MD_JSON RW_DEF SP_MD SP_DEF; do
  eval "x=\${$v:-}"
  case "$x" in
    ''|*[!0-9]*) bad "could not read $v (got '$x') -- the extraction in this test needs updating" ;;
  esac
done

if [ "$RW_DEF" = "$SP_DEF" ]; then ok "rewrite.sh and speak.sh agree on CLAUDISH_TIMEOUT's default ($RW_DEF)"
else bad "CLAUDISH_TIMEOUT default differs: rewrite.sh=$RW_DEF speak.sh=$SP_DEF"; fi

if [ "$RW_DEF" -le "$MD_JSON" ]; then
  ok "CLAUDISH_TIMEOUT default ($RW_DEF) does not exceed the MessageDisplay hook timeout ($MD_JSON)"
else
  bad "CLAUDISH_TIMEOUT default $RW_DEF exceeds the hook timeout $MD_JSON: the harness kills the hook first and the rewrite publishes nothing"
fi

if [ "$SP_MD" = "$MD_JSON" ]; then
  ok "speak.sh MD_TIMEOUT ($SP_MD) == hooks.json MessageDisplay timeout ($MD_JSON)"
else
  bad "speak.sh MD_TIMEOUT=$SP_MD but hooks.json declares $MD_JSON -- a rewrite landing between $((SP_MD + 3))s and ${MD_JSON}s would be DISPLAYED and never SPOKEN (spec 3.5.1 clause 3)"
fi

# The clause verbatim: min( CLAUDISH_TIMEOUT + 2, MD_TIMEOUT ) + 3
WANT=$((SP_DEF + 2)); [ "$WANT" -gt "$SP_MD" ] && WANT="$SP_MD"; WANT=$((WANT + 3))
if [ "$WANT" -ge "$MD_JSON" ]; then
  ok "derived wait (${WANT}s) covers the whole display budget (${MD_JSON}s)"
else
  bad "derived wait ${WANT}s is short of the ${MD_JSON}s display budget: rewrites in between are silent"
fi

echo
echo "$pass passed, $fail failed."
[ "$fail" -eq 0 ] || exit 1
exit 0
