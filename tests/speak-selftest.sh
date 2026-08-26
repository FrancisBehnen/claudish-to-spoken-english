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
unset CLAUDISH_OFF_FILE

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

echo "--- debug log ---"
sed 's/^/  /' "$BUF/debug.log" 2>/dev/null
echo
echo "$pass passed, $fail failed.  scratch: $WORK"
[ "$fail" -eq 0 ] || exit 1
exit 0
