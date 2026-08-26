#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Pin the speech handoff key.
#
# `speak_key()` from speak-key.sh must agree with an INDEPENDENT implementation
# (python hashlib) on every row of tests/speak-key-cases.tsv, and must do so
# under BOTH shell regimes the two hooks run in:
#
#   loose   no `set` options at all -- speak.sh's regime (§5: on a Stop hook a
#           stray non-zero can become an exit 2, which BLOCKS the turn)
#   strict  `set -uo pipefail`      -- rewrite.sh's regime
#
# The reason this test exists rather than a paragraph claiming the two hooks
# agree: if they ever disagree, rewrite.sh publishes to one path and speak.sh
# looks at another, the user hears nothing on every single turn, and nothing
# anywhere reports an error.
#
#   tests/speak-key-test.sh            # check
#   tests/speak-key-test.sh --regen    # recompute the key column, then check
# ---------------------------------------------------------------------------

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CASES="$ROOT/tests/speak-key-cases.tsv"
GEN="$ROOT/tests/speak-key-gen.py"

if [ "${1:-}" = "--regen" ]; then
  python3 "$GEN" --regen "$CASES" || exit 1
  echo "regenerated $CASES"
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/speak-key.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

EXPECTED="$(python3 "$GEN" --emit "$CASES" "$WORK/cases")" || exit 1

run_regime() {
  bash -c '
    if [ "$1" = "strict" ]; then set -uo pipefail; fi
    . "$2/speak-key.sh"
    for f in "$3"/*.txt; do
      n="$(basename "$f" .txt)"
      # $(cat f) is exactly how speak.sh feeds the message in, trailing-newline
      # stripping and all, so this exercises the production path.
      printf "%s\t%s\n" "$n" "$(speak_key "$(cat "$f")")"
    done
  ' _ "$1" "$ROOT" "$WORK/cases"
}

fail=0
for regime in loose strict; do
  got="$(run_regime "$regime")"
  if [ "$got" = "$EXPECTED" ]; then
    echo "  PASS  speak_key == python hashlib, regime: $regime"
  else
    echo "  FAIL  speak_key != python hashlib, regime: $regime"
    diff <(printf '%s\n' "$EXPECTED") <(printf '%s\n' "$got") 2>/dev/null | sed 's/^/        /'
    fail=1
  fi
done

echo "  $(printf '%s\n' "$EXPECTED" | grep -c .) cases"
exit "$fail"
