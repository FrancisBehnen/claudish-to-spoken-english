#!/bin/bash
# Real-audio confirmation for row 20. Kokoro synthesis, afplay as the player, on
# bf_emma, is_phonemes=False. The stub runs establish the ORDERING and the
# attribution; this answers the one question a stub cannot -- whether the stale
# utterance is audible, and for how long.
#
# usage: run_real.sh <claim_kill: pidfile|off> <trials>
set -u
RIG="$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25"
OUT="$RIG/out"
PY="$HOME/.local/share/kokoro/venv/bin/python"
CK=${1:?claim-kill}; N=${2:-3}
HOOK_GAP_S=0.09
export HOOK_GAP_S

SID="REAL-$CK-$(date +%s)"
SD="$OUT/$SID/speak"; MD="$OUT/$SID/markers"
mkdir -p "$SD" "$MD"
TRACE="$OUT/$SID/worker.trace"; PLOG="$OUT/$SID/player.log"; TXT="$OUT/$SID/text"
# two clearly distinguishable utterances, so an overlap is audible as an overlap
printf 'The older utterance says: one, two, three, four, five, six, seven, eight.\n' > "$TXT"
printf 'The newer utterance says: alpha, bravo, charlie, delta, echo, foxtrot.\n' > "$OUT/$SID/text2"

"$PY" "$RIG/speakd_probe.py" --speak-dir "$SD" --trace "$TRACE" --player-log "$PLOG" \
  --claim-kill "$CK" --prespawn-recheck on --pid-write on \
  --prespawn-delay-ms 1000 --real-kokoro --real-player --voice bf_emma \
  --idle-exit-s 600 --generation 1 &
WPID=$!
for _ in $(seq 1 400); do [[ -f "$SD/ready" ]] && break; sleep 0.05; done
[[ -f "$SD/ready" ]] || { echo "FATAL: worker never ready" >&2; exit 1; }

"$RIG/hook_probe.sh" "$SD" "$MD" warmup w0 "$TXT"
sleep 8
for i in $(seq 1 "$N"); do
  "$RIG/hook_probe.sh" "$SD" "$MD" "t${i}a" "j${i}a" "$TXT"
  sleep 1.4
  "$RIG/hook_probe.sh" "$SD" "$MD" "t${i}b" "j${i}b" "$OUT/$SID/text2"
  sleep 12
done
kill -TERM "$WPID" 2>/dev/null
sleep 0.3
printf '%s\n' "$OUT/$SID"
