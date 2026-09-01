#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Exercise speak.sh in isolation, without Claude Code.
#
#   tests/speak-selftest.sh                  # all cases, with real audio
#   tests/speak-selftest.sh -q               # all cases, silent (fake player)
#   tests/speak-selftest.sh path/to/text.txt # use your own text
#
# Everything runs inside a scratch TMPDIR and a scratch mute file, so your real
# ~/.claude/claudish-speak-off and your real session buffers are never touched.
#
# NO CASE HERE SPENDS TOKENS OR QUOTA.  Case 9 is the only one that drives
# rewrite.sh, and the LLM is pinned out of it (see the CLAUDISH_STUB block
# below) -- necessary since #14 made claude-cli, which bills the user's own
# subscription, the default provider.
#
# Cases:
#   1  speech OFF (CLAUDISH_SPEAK unset)  -> exit 0, zero side effects
#   2  buffered HIT                       -> audio, time-to-wav reported
#   3  bounded WAIT (§3.5.1)              -> rw.<hash> published 3 s late,
#                                            audio still happens
#   4  mute MID-UTTERANCE                 -> touching the off-file kills the
#                                            player that is already sounding
#   5  wait DEADLINE                      -> nothing published, silent, exit 0
#   6  AT MOST ONE CONSUMER                -> a second turn while the first is
#                                            speaking leaves exactly one
#                                            speaker, never two talking over
#                                            each other (§3.5.1 cl. 5, §5.1)
#   7  a SILENT turn does NOT preempt     -> a turn that exits at a content
#                                            gate (empty last_assistant_message,
#                                            or a running background task)
#                                            leaves the live speaker alone.
#                                            §10.3 ordered the kill above those
#                                            gates and it cut a playing answer
#                                            off with nothing in its place
#   8  a SPEAKING turn DOES preempt       -> the old speaker is gone, exactly
#                                            one survives, and the survivor is
#                                            the NEW one
#   9  SHORT message is SPOKEN            -> well under CLAUDISH_MIN_CHARS:
#                                            rewrite.sh publishes the RAW text
#                                            under the same key and it is
#                                            spoken.  There is no audio floor.
#                                            This case was silent before
#  10 an UNSOURCEABLE speak-key.sh is       -> with no speak-key.sh beside it,
#     silent, and does NOT fall back to        speak.sh must go silent rather
#     PATH                                     than call whatever `speak_key`
#                                            PATH or the environment happens
#                                            to offer.  `command -v speak_key`
#                                            answered for a stray and the
#                                            handoff key would then come from
#                                            code that is not the one
#                                            definition
# ---------------------------------------------------------------------------

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SILENT=0
TEXT=""
for a in "$@"; do
  case "$a" in
    -q|--quiet) SILENT=1 ;;
    *) TEXT="$a" ;;
  esac
done
[ -n "$TEXT" ] || TEXT="$ROOT/corpus/spoken/r03.txt"
[ -f "$TEXT" ] || { echo "no such text file: $TEXT"; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/claudish-selftest.XXXXXX")"
SID="selftest-$$"
BUF="$WORK/claudish-to-english"
SPEAK_DIR="$BUF/$SID/speak"
OFF="$WORK/claudish-speak-off"
PLAYLOG="$WORK/player.log"

# A player wrapper, so we can assert that the player really was invoked and
# what it exited with. With -q it makes no sound but still occupies the same
# wall time a short utterance would, so case 4 still has something to mute.
cat > "$WORK/player" <<PEOF
#!/bin/sh
if [ "$SILENT" = "1" ]; then
  sleep 6
  rc=0
else
  /usr/bin/afplay "\$1"
  rc=\$?
fi
echo "played \$1 rc=\$rc \$(date +%s.%N)" >> "$PLAYLOG"
exit \$rc
PEOF
chmod +x "$WORK/player"

export TMPDIR="$WORK"
export CLAUDISH_SPEAK_OFF_FILE="$OFF"
export CLAUDISH_PLAYER="$WORK/player"
export CLAUDISH_DEBUG=1
# Point the GLOBAL off-file at a scratch path that does not exist, rather than
# unsetting it: unset means the real ~/.claude/claudish-off, and a user who has
# that file would watch every case here fail with no hint why.  Case 9 drives
# rewrite.sh, which reads the same file.
export CLAUDISH_OFF_FILE="$WORK/claudish-off"

# ---- no case here may spend the user's Claude subscription quota ---------
# Case 9 drives rewrite.sh for real, and since #14 the DEFAULT provider is
# claude-cli, which bills the SAME 5-hour and 7-day windows as the user's real
# Claude Code work.  Case 9 is safe today only by accident of its fixture: 48
# prose chars, under CLAUDISH_MIN_CHARS, so rewrite.sh returns at the
# below-threshold gate and never reaches llm_complete.  That is a property of
# the FIXTURE, not of the suite, and speech no longer has a length floor of its
# own keeping it true -- so anyone who lengthens that fixture would silently
# bill the user.  Pinned here in two independent layers instead:
#
#   CLAUDISH_STUB=1   rewrite.sh takes its deterministic stub branch, and that
#                     branch is the `if` whose `else` holds the ONLY
#                     llm_complete call in the file -- so no provider is
#                     invoked at any fixture length.  This is the real guard.
#   CLAUDISH_PROVIDER ollama at a closed scratch port, so if the stub branch is
#   CLAUDISH_OLLAMA   ever removed the call lands on a refused local socket
#                     rather than on a metered provider.  Belt to the braces.
#
# Set here rather than on the case-9 line so a case added later inherits them,
# and as assignments that beat the user's exported environment.  A lengthened
# fixture now FAILS LOUDLY -- the stub text hashes to a different handoff key
# than the raw text case 9 asserts -- instead of quietly spending quota.
# tests/config-test.sh is where the provider DEFAULT is pinned; this is only
# about never exercising it.  The speech path reads none of these three.
export CLAUDISH_STUB=1
export CLAUDISH_PROVIDER=ollama
export CLAUDISH_OLLAMA="http://127.0.0.1:1"

PAYLOAD="$WORK/stop.json"
python3 "$ROOT/tests/mkpayload.py" stop "$TEXT" "$SID" > "$PAYLOAD" || exit 1

# The key comes from the SAME file both hooks source, never from a third copy.
# tests/speak-key-test.sh is what pins that function down.
. "$ROOT/speak-key.sh"
H="$(speak_key "$(cat "$TEXT")")"

now() { date +%s.%N; }
elapsed() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.2f", b-a}'; }
reset() { rm -rf "$BUF/$SID" "$OFF" "$PLAYLOG" 2>/dev/null; mkdir -p "$SPEAK_DIR"; }
publish() { printf '%s' "$(cat "$TEXT")" > "$SPEAK_DIR/.t"; mv -f "$SPEAK_DIR/.t" "$SPEAK_DIR/rw.$H"; }
wait_wav() {  # $1 = seconds to wait; echoes the first wav seen, or nothing
  _n=0
  while [ "$_n" -lt "$1" ]; do
    _w="$(ls "$SPEAK_DIR"/wav/*.wav 2>/dev/null | sed -n 1p)"
    [ -n "$_w" ] && { printf '%s' "$_w"; return 0; }
    sleep 0.1
    _n=$((_n + 1))
  done
  return 1
}
# macOS pgrep has no -a, so count from ps: our speakers carry the session id
# in their argv (the job path).
speakers() { ps -Ao command= 2>/dev/null | grep 'speak-child\.py' | grep -c "$SID"; }
# The same set, as pids: cases 7 and 8 are about WHICH speaker survives, which
# a count cannot tell apart from a replacement.
speaker_pids() {
  ps -Ao pid=,command= 2>/dev/null | grep 'speak-child\.py' | grep "$SID" | awk '{print $1}'
}
quiesce() { _n=0; while [ "$_n" -lt 400 ] && pgrep -f "$SID" >/dev/null 2>&1; do sleep 0.1; _n=$((_n+1)); done; }

pass=0; fail=0
ok()  { echo "  PASS  $*"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $*"; fail=$((fail + 1)); }

echo "speak.sh self-test"
echo "  text     $TEXT ($(wc -c < "$TEXT" | tr -d ' ') bytes)"
echo "  hash     $H"
echo "  scratch  $WORK"
echo "  player   $([ "$SILENT" = 1 ] && echo 'fake (silent)' || echo '/usr/bin/afplay')"
echo

# --- 1: speech off --------------------------------------------------------
echo "1  speech OFF (CLAUDISH_SPEAK unset)"
rm -rf "$BUF"
( unset CLAUDISH_SPEAK; bash "$ROOT/speak.sh" < "$PAYLOAD" )
rc=$?
[ "$rc" -eq 0 ] && ok "exit 0" || bad "exit $rc, expected 0"
if [ -e "$BUF/$SID" ]; then bad "created $BUF/$SID -- expected zero side effects"
else ok "no session directory created"; fi
if [ -e "$BUF/debug.log" ]; then bad "wrote a debug log before the gates"
else ok "no debug log"; fi
echo

# --- 2: buffered hit ------------------------------------------------------
echo "2  buffered HIT (rewrite already published)"
reset; publish
t0="$(now)"
CLAUDISH_SPEAK=1 bash "$ROOT/speak.sh" < "$PAYLOAD"; rc=$?
t1="$(now)"
[ "$rc" -eq 0 ] && ok "hook exit 0, returned in $(elapsed "$t0" "$t1")s" || bad "hook exit $rc"
wav="$(wait_wav 200)"
if [ -n "$wav" ]; then
  t2="$(now)"
  ok "wav at $(elapsed "$t0" "$t2")s from hook invocation: $(basename "$wav")"
else
  bad "no wav within 20s"
fi
quiesce
if [ -s "$PLAYLOG" ]; then
  ok "player invoked: $(wc -l < "$PLAYLOG" | tr -d ' ') time(s)"
  if grep -q 'rc=0' "$PLAYLOG"; then ok "player exited 0"; else bad "player did not exit 0"; fi
  sed 's/^/        /' "$PLAYLOG"
else
  bad "player never invoked"
fi
echo

# --- 3: bounded wait ------------------------------------------------------
echo "3  bounded WAIT -- rewrite published 3s AFTER the Stop hook (§3.5.1)"
reset
t0="$(now)"
CLAUDISH_SPEAK=1 bash "$ROOT/speak.sh" < "$PAYLOAD"; rc=$?
[ "$rc" -eq 0 ] && ok "hook exit 0 immediately, without waiting" || bad "hook exit $rc"
sleep 3
publish
wav="$(wait_wav 250)"
if [ -n "$wav" ]; then ok "wav at $(elapsed "$t0" "$(now)")s -- the late publish was heard"
else bad "no wav: the bounded wait did not pick up the late publish"; fi
quiesce
echo

# --- 4: mute mid-utterance ------------------------------------------------
echo "4  MUTE mid-utterance -- touch the off-file while audio is sounding"
reset; publish
CLAUDISH_SPEAK=1 bash "$ROOT/speak.sh" < "$PAYLOAD"
wav="$(wait_wav 250)"
if [ -z "$wav" ]; then
  bad "no wav to interrupt"
else
  sleep 1
  before="$(cat "$PLAYLOG" 2>/dev/null | wc -l | tr -d ' ')"
  tm="$(now)"
  touch "$OFF"
  quiesce
  te="$(now)"
  ok "speaker stopped $(elapsed "$tm" "$te")s after the off-file appeared"
  if pgrep -f "$SID" >/dev/null 2>&1; then bad "a speaker is still running"
  else ok "no player left running"; fi
  after="$(cat "$PLAYLOG" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$after" -le $((before + 1)) ]; then ok "no further sentences were played"
  else bad "kept playing: $before -> $after"; fi
fi
rm -f "$OFF"
echo

# --- 5: deadline ----------------------------------------------------------
echo "5  wait DEADLINE -- nothing is ever published"
reset
t0="$(now)"
CLAUDISH_SPEAK=1 CLAUDISH_TIMEOUT=1 bash "$ROOT/speak.sh" < "$PAYLOAD"; rc=$?
[ "$rc" -eq 0 ] && ok "hook exit 0" || bad "hook exit $rc"
quiesce
if [ -n "$(ls "$SPEAK_DIR"/wav/*.wav 2>/dev/null)" ]; then bad "spoke something with no publish"
else ok "silent after the deadline ($(elapsed "$t0" "$(now)")s), nothing synthesised"; fi
echo

# --- 6: at most one consumer ---------------------------------------------
# The invariant §3.5.1 clause 5 and §5.1 both lean on. In the spec a resident
# worker holds it by election; in the cold path it rests on the hook's step-6
# preemption plus speak-child.py's mkdir claim. If it breaks, TWO speakers
# finish their waits and talk over each other -- so this counts them.
echo "6  AT MOST ONE CONSUMER -- a second turn while the first is speaking"
reset; publish
CLAUDISH_SPEAK=1 bash "$ROOT/speak.sh" < "$PAYLOAD"
wav="$(wait_wav 250)"
if [ -z "$wav" ]; then
  bad "first speaker never started"
else
  n1="$(speakers)"
  [ "$n1" -eq 1 ] && ok "one speaker running" || bad "$n1 speakers running, expected 1"
  # A DIFFERENT text, so §5.1's dedup cannot be what silences the second one.
  { cat "$TEXT"; printf ' And one more sentence, so this turn is not a repeat.'; } > "$WORK/textB.txt"
  python3 "$ROOT/tests/mkpayload.py" stop "$WORK/textB.txt" "$SID" > "$WORK/stopB.json"
  HB="$(speak_key "$(cat "$WORK/textB.txt")")"
  printf '%s' "$(cat "$WORK/textB.txt")" > "$SPEAK_DIR/.tb"; mv -f "$SPEAK_DIR/.tb" "$SPEAK_DIR/rw.$HB"
  CLAUDISH_SPEAK=1 bash "$ROOT/speak.sh" < "$WORK/stopB.json"
  sleep 2
  n2="$(speakers)"
  if [ "$n2" -le 1 ]; then ok "still at most one speaker after the second turn ($n2)"
  else bad "$n2 speakers running -- two voices would overlap"; fi
  quiesce
  # Only the newer turn's wavs should have been played after the switch.
  ok "player log: $(cat "$PLAYLOG" 2>/dev/null | wc -l | tr -d ' ') plays across both turns"
fi
echo


# --- 7: a silent turn must not kill the live speaker ----------------------
# Change 1.  §10.3 put step 6's kill above every content-based exit, so a turn
# that was never going to speak still TERMed the previous speaker's process
# group: a long answer playing, a one-line question asked, the answer to it
# gated out, and the previous answer cut off mid-sentence with nothing in its
# place.  Both content gates are exercised, because the kill sat above both.
echo "7  a SILENT turn must NOT kill the live speaker"
reset; publish
CLAUDISH_SPEAK=1 bash "$ROOT/speak.sh" < "$PAYLOAD"
wav="$(wait_wav 250)"
if [ -z "$wav" ]; then
  bad "first speaker never started -- nothing to protect"
else
  pid1="$(speaker_pids | sed -n 1p)"
  if [ -n "$pid1" ]; then ok "speaker running, pid $pid1"; else bad "no speaker pid"; fi
  # step 9's gate: last_assistant_message present and empty.
  : > "$WORK/empty.txt"
  python3 "$ROOT/tests/mkpayload.py" stop "$WORK/empty.txt" "$SID" > "$WORK/stop-empty.json"
  CLAUDISH_SPEAK=1 bash "$ROOT/speak.sh" < "$WORK/stop-empty.json"
  sleep 1
  if kill -0 "$pid1" 2>/dev/null; then ok "empty last_assistant_message left the speaker alive"
  else bad "the empty-message turn killed the speaker"; fi
  # step 8's gate: a running background task.
  python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); p["background_tasks"]=[{"status":"running"}]; print(json.dumps(p))' \
    "$PAYLOAD" > "$WORK/stop-bg.json"
  CLAUDISH_SPEAK=1 bash "$ROOT/speak.sh" < "$WORK/stop-bg.json"
  sleep 1
  if kill -0 "$pid1" 2>/dev/null; then ok "a running background task left the speaker alive"
  else bad "the background-task turn killed the speaker"; fi
  n="$(speakers)"
  if [ "$n" -eq 1 ]; then ok "still exactly one speaker, and it is the original"
  else bad "$n speakers running, expected 1"; fi
fi
quiesce
echo

# --- 8: a speaking turn still preempts ------------------------------------
# The other half of change 1, and the part that is load-bearing: moving the
# kill must not lose it.  Case 6 counts speakers; this one names them, because
# "one speaker" is also what a failure to start the newcomer looks like.
echo "8  a turn that SPEAKS still preempts -- and the survivor is the NEW one"
reset; publish
CLAUDISH_SPEAK=1 bash "$ROOT/speak.sh" < "$PAYLOAD"
wav="$(wait_wav 250)"
if [ -z "$wav" ]; then
  bad "first speaker never started"
else
  pid1="$(speaker_pids | sed -n 1p)"
  { cat "$TEXT"; printf ' A different closing sentence, so this turn is not a repeat.'; } > "$WORK/textC.txt"
  python3 "$ROOT/tests/mkpayload.py" stop "$WORK/textC.txt" "$SID" > "$WORK/stopC.json"
  HC="$(speak_key "$(cat "$WORK/textC.txt")")"
  printf '%s' "$(cat "$WORK/textC.txt")" > "$SPEAK_DIR/.tc"
  mv -f "$SPEAK_DIR/.tc" "$SPEAK_DIR/rw.$HC"
  CLAUDISH_SPEAK=1 bash "$ROOT/speak.sh" < "$WORK/stopC.json"
  _n=0
  while [ "$_n" -lt 60 ] && kill -0 "$pid1" 2>/dev/null; do sleep 0.1; _n=$((_n + 1)); done
  if kill -0 "$pid1" 2>/dev/null; then bad "old speaker $pid1 survived a speaking turn -- preemption lost"
  else ok "old speaker $pid1 was preempted"; fi
  sleep 2
  n2="$(speakers)"
  if [ "$n2" -eq 1 ]; then ok "exactly one speaker survives"
  else bad "$n2 speakers running, expected 1"; fi
  pid2="$(speaker_pids | sed -n 1p)"
  if [ -n "$pid2" ] && [ "$pid2" != "$pid1" ]; then ok "the survivor is the new speaker, pid $pid2"
  else bad "survivor pid '$pid2' against old '$pid1' -- the newcomer never took over"; fi
fi
quiesce
echo

# --- 9: a short message is spoken -----------------------------------------
# Change 2.  Below CLAUDISH_MIN_CHARS rewrite.sh used to publish NOTHING, so
# speak.sh's own sub-threshold row spoke the raw text out of the job -- or, if
# it carried one of §3.4's eight hazard classes, went silent.  Now the short
# path publishes the raw text under the same key and there is no floor on the
# speech side at all.  This drives BOTH hooks, in live order: Stop is
# dispatched a median 6.7 ms BEFORE the final MessageDisplay chunk.
echo "9  SHORT message -- no floor: rewrite.sh publishes RAW, speak.sh speaks it"
reset
SHORT="$WORK/short.txt"
printf 'Yes, that is done. The tests pass and nothing else changed.' > "$SHORT"
plen="$(tr -d '[:space:]' < "$SHORT" | wc -c | tr -d ' ')"
python3 "$ROOT/tests/mkpayload.py" stop    "$SHORT" "$SID"             > "$WORK/stop-short.json"
python3 "$ROOT/tests/mkpayload.py" display "$SHORT" "$SID" "msg-short" > "$WORK/disp-short.json"
HS="$(speak_key "$(cat "$SHORT")")"
t0="$(now)"
CLAUDISH_SPEAK=1 bash "$ROOT/speak.sh" < "$WORK/stop-short.json"; rc=$?
if [ "$rc" -eq 0 ]; then ok "hook exit 0 on a $plen-byte message (well under 200)"
else bad "hook exit $rc"; fi
CLAUDISH_SPEAK=1 bash "$ROOT/rewrite.sh" < "$WORK/disp-short.json" > "$WORK/rw-out.json"
if [ -f "$SPEAK_DIR/rw.$HS" ]; then ok "rewrite.sh published rw.<key> below MIN_CHARS"
else bad "rewrite.sh published nothing below MIN_CHARS"; fi
if [ ! -s "$WORK/rw-out.json" ]; then ok "rewrite.sh stayed fail-open: nothing on stdout"
else bad "rewrite.sh emitted displayContent on the short path: $(cat "$WORK/rw-out.json")"; fi
wav="$(wait_wav 250)"
if [ -n "$wav" ]; then ok "wav at $(elapsed "$t0" "$(now)")s -- the short answer was SPOKEN"
else bad "no wav: the short answer is still silent"; fi
quiesce
if [ -s "$PLAYLOG" ]; then ok "player invoked for the short answer"
else bad "player never invoked for the short answer"; fi
echo

# --- 10: an unsourceable speak-key.sh must not fall through to PATH -------
# The handoff key has ONE definition and both hooks source it.  The guard used
# to be `command -v speak_key`, which resolves executables on PATH and
# functions exported with `export -f` as readily as the function the source
# defines -- so on a run where the source failed, a stray `speak_key` answered
# the guard and was then CALLED, from a Stop hook, on the text of the turn.
# The key would have come from code that is not the one definition, so
# rewrite.sh would publish to one path while the hook waited on another: no
# audio, on every turn, with nothing reporting an error.
#
# This drives a copy of speak.sh in a directory with NO speak-key.sh beside it
# and a stray `speak_key` first on PATH that leaves a marker if it is invoked.
echo "10  unsourceable speak-key.sh -- silent, and no PATH fallback"
reset
mkdir -p "$WORK/nokey" "$WORK/straybin" 2>/dev/null
cp "$ROOT/speak.sh" "$WORK/nokey/speak.sh"
cp "$ROOT/speak-child.py" "$WORK/nokey/speak-child.py"
STRAY_MARK="$WORK/stray-was-called"
cat > "$WORK/straybin/speak_key" <<'SEOF'
#!/bin/sh
: > "$STRAY_MARK_PATH"
printf 'deadbeef'
SEOF
chmod +x "$WORK/straybin/speak_key"
rc=0
( export STRAY_MARK_PATH="$STRAY_MARK"
  PATH="$WORK/straybin:$PATH" CLAUDISH_SPEAK=1 \
    bash "$WORK/nokey/speak.sh" < "$PAYLOAD" ) || rc=$?
if [ "$rc" -eq 0 ]; then ok "hook exit 0 with no speak-key.sh beside it"
else bad "hook exit $rc, expected 0"; fi
if [ -e "$STRAY_MARK" ]; then
  bad "the stray speak_key on PATH was CALLED -- command -v fell through"
else ok "the stray speak_key on PATH was never called"; fi
if [ -n "$(ls "$SPEAK_DIR"/job.* 2>/dev/null)" ]; then
  bad "a job was installed on a run that could not compute the key"
else ok "no job installed: the hook went silent at the key"; fi
if [ "$(speakers)" -eq 0 ]; then ok "no speaker forked"
else bad "$(speakers) speaker(s) forked without a key"; fi
quiesce
echo

echo "--- debug log ---"
sed 's/^/  /' "$BUF/debug.log" 2>/dev/null
echo
echo "$pass passed, $fail failed.  scratch: $WORK"
[ "$fail" -eq 0 ] || exit 1
exit 0
