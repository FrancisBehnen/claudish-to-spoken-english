# ---------------------------------------------------------------------------
# speak-key.sh -- THE definition of the speech handoff key.  Sourced, not run.
#
# `rewrite.sh` publishes its rewrite to `speak/rw.<key>` and `speak.sh` looks
# for `speak/rw.<key>`.  If the two ever computed that key differently the user
# would hear nothing, on every turn, with no error anywhere.  So the derivation
# lives HERE, once, and both hooks source it.  One invariant, one copy.
#
#   speak_key <text>   ->  sha256( trim( text ) ), lowercase hex, on stdout
#                          empty on any failure -- callers must test for that
#
# `trim` is leading and trailing whitespace, and it is defensive rather than
# load-bearing: 44 captured message streams had zero edge whitespace, and the
# harness itself trims `last_assistant_message` before it hands it over.  It is
# kept because both sides doing the same no-op costs nothing and the two sides
# doing *different* no-ops would cost the whole feature.  NOTHING ELSE is
# normalised -- not internal whitespace runs, not a fixed-length prefix.  Both
# were tested against 35 messages, both were no-ops, and both widen a key whose
# whole job is to be narrow (§3.2).
#
# IT MUST BEHAVE IDENTICALLY IN TWO DIFFERENT SHELL REGIMES, so it depends on
# neither:
#   * `rewrite.sh` runs under `set -uo pipefail`.  Every variable below is
#     assigned before it is read, so `-u` has nothing to fire on; the one
#     pipeline's status is never tested, and `pipefail` only changes a status
#     nobody reads.
#   * `speak.sh` runs with NO `set` options at all (§5: on a Stop hook a stray
#     non-zero can become an exit 2, which BLOCKS the turn).  Nothing here
#     relies on `-e`, `-u` or `pipefail` being on.
# It also uses no bashisms beyond `${var#pat}` / `${var%pat}`, so it is safe to
# source from either.
#
# The hex extraction is `${h%% *}` rather than `| cut -d' ' -f1` on purpose:
# one process instead of two, and no second pipeline whose status `pipefail`
# would have an opinion about.
#
# The fixture table that pins this down is `tests/speak-key-cases.tsv`, checked
# by `tests/speak-key-test.sh`.  Change the derivation and that table fails --
# which is the point, because a silent change here is a silently mute plugin.
#
# HOW A CALLER PROVES IT GOT *THIS* DEFINITION: test `SPEAK_KEY_DEFINED`, which
# the last line of this file assigns.  `command -v speak_key` is NOT that
# proof -- it resolves shell functions, builtins AND executables on `PATH`, so
# on a run where sourcing this file failed (absent, unreadable, truncated) a
# stray `speak_key` on `PATH`, or one exported into the environment with
# `export -f`, answers `command -v` just as well and then gets CALLED.  That
# breaks the one-definition guarantee in the only way that matters: the two
# hooks would derive the handoff key with code that is not this file, possibly
# different code on each side, and the user hears nothing on every turn with
# no error anywhere.  Callers therefore zero the sentinel, source, and test it:
#
#   SPEAK_KEY_DEFINED=0
#   . "<dir>/speak-key.sh" 2>/dev/null
#   [ "$SPEAK_KEY_DEFINED" = "1" ] || <give up quietly>
#
# Zeroing it first is what makes the test meaningful -- it cannot be satisfied
# by an inherited environment variable -- and assigning before reading is also
# what keeps it safe under `rewrite.sh`'s `set -u`.
# ---------------------------------------------------------------------------

speak_key() {
  _sk_text="$1"
  _sk_text="${_sk_text#"${_sk_text%%[![:space:]]*}"}"
  _sk_text="${_sk_text%"${_sk_text##*[![:space:]]}"}"
  _sk_out="$(printf '%s' "$_sk_text" | shasum -a 256 2>/dev/null)"
  _sk_out="${_sk_out%% *}"
  case "$_sk_out" in
    *[!0-9a-f]* | '') printf '' ;;
    *) printf '%s' "$_sk_out" ;;
  esac
}

# LAST LINE ON PURPOSE.  Reaching it is the whole assertion: the definition
# above ran, in this shell, out of this file.  Nothing may be added below it.
SPEAK_KEY_DEFINED=1
