#!/bin/bash
# Row 20 driver. One warm worker per configuration; N trials of two Stop hooks
# against it, with the second hook's launch time chosen to land the ORDERING the
# configuration is named for -- not sampled and hoped for.
#
# Nominal timeline of one trial, measured from hook A's rename R_A = t0, with
# synth 1.0 s and the pre-spawn delay D:
#     S  = t0            claim
#     S2 = t0 + 1.0      pre-spawn recheck
#     P  = t0 + 1.0 + D  Popen
#     W  = P + ~1 ms     pid write
#     K_B = t0 + GAP     hook B reads speak/pid and kills
#     R_B = t0 + GAP + HOOK_GAP_S
# so GAP picks which of the three orderings the trial lands in.
#
# usage: run_preempt.sh <config> <trials>
set -u
RIG="$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25"
OUT="$RIG/out"
PY=/Users/francis.behnen/homebrew/bin/python3
CFG=${1:?config}; N=${2:-10}

SYNTH_MS=1000
PLAYER_SECS=2.5
LOAD_MS=700
HOOK_GAP_S=0.09
export HOOK_GAP_S

DIE=none; REAP=on; LEDGER=off; SWEEP=off; RESPAWN=no; PIDW=on
case "$CFG" in
  # --- the three orderings, all three preemption hooks in
  C1_prespawn)    DELAY=0    ; GAP=0.4 ; CK=pidfile ; RECHK=on  ;;
  C2_hookside)    DELAY=0    ; GAP=1.6 ; CK=pidfile ; RECHK=on  ;;
  C3_adversarial) DELAY=1000 ; GAP=1.4 ; CK=pidfile ; RECHK=on  ;;
  # --- falsification: remove one clause at a time from the adversarial ordering
  C4_noclaimkill) DELAY=1000 ; GAP=1.4 ; CK=off     ; RECHK=on  ;;
  C5_norecheck)   DELAY=1000 ; GAP=1.4 ; CK=pidfile ; RECHK=off ;;
  C6_handle)      DELAY=1000 ; GAP=1.4 ; CK=handle  ; RECHK=on  ;;
  # --- the zombie: a worker that never reaps its player
  C7_noreap)      DELAY=0    ; GAP=1.6 ; CK=pidfile ; RECHK=on  ; REAP=off ;;
  # --- worker dies inside the P->W window; a replacement worker is elected
  C8_orphan)      DELAY=1000 ; GAP=1.4 ; CK=pidfile ; RECHK=on  ; DIE=popen ; RESPAWN=yes ;;
  # --- same, with the proposed repair: player-written ledger + sweep on election
  C9_ledger)      DELAY=1000 ; GAP=1.4 ; CK=pidfile ; RECHK=on  ; DIE=popen ; RESPAWN=yes ; LEDGER=on ; SWEEP=on ;;
  # --- clause (i) removed: is the hook-side pid kill required for CORRECTNESS?
  #     The pair matters: with (iii) reading the pid file, removing (i) removes the
  #     claim-kill's only target too; with (iii) holding an in-memory handle it does not.
  C10a_nopid_pidfile) DELAY=0 ; GAP=1.6 ; CK=pidfile ; RECHK=on ; PIDW=off ;;
  C10b_nopid_handle)  DELAY=0 ; GAP=1.6 ; CK=handle  ; RECHK=on ; PIDW=off ;;
  *) echo "unknown config $CFG" >&2; exit 2 ;;
esac

SID="$CFG-$(date +%s)"
SD="$OUT/$SID/speak"
MD="$OUT/$SID/markers"
mkdir -p "$SD" "$MD"
TRACE="$OUT/$SID/worker.trace"
PLOG="$OUT/$SID/player.log"
TXT="$OUT/$SID/text"
printf 'The nineteen tests all pass and the branch is pushed.\n' > "$TXT"

start_worker() {
  "$PY" "$RIG/speakd_probe.py" --speak-dir "$SD" --trace "$TRACE" --player-log "$PLOG" \
    --claim-kill "$CK" --prespawn-recheck "$RECHK" --pid-write "$PIDW" \
    --prespawn-delay-ms "$DELAY" --synth-ms "$SYNTH_MS" --load-ms "$LOAD_MS" \
    --player-secs "$PLAYER_SECS" --idle-exit-s 600 --reap "$REAP" \
    --die-after "$1" --ledger "$LEDGER" --sweep-on-election "$SWEEP" \
    --generation "$2" &
  WPID=$!
}

wait_ready() {
  rm -f "$SD/ready"
  for _ in $(seq 1 200); do [[ -f "$SD/ready" ]] && return 0; sleep 0.05; done
  return 1
}

start_worker none 1
if ! wait_ready; then echo "FATAL: worker never became ready" >&2; exit 1; fi

# one throwaway job so the worker is WARM: it has already synthesised and played
"$RIG/hook_probe.sh" "$SD" "$MD" warmup w0 "$TXT"
sleep 5

for i in $(seq 1 "$N"); do
  A="t${i}a"; B="t${i}b"
  if [[ "$DIE" != none ]]; then
    # the worker exits inside the P->W window, so it must be (re)started per trial.
    # The old lock is left in place deliberately: reclaiming it via the corrected
    # election is the realistic path a replacement worker takes.
    kill -TERM "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null
    start_worker "$DIE" "$i"
    wait_ready || { echo "FATAL: worker gen$i never ready" >&2; exit 1; }
  fi
  "$RIG/hook_probe.sh" "$SD" "$MD" "$A" "j${i}a" "$TXT"
  sleep "$GAP"
  "$RIG/hook_probe.sh" "$SD" "$MD" "$B" "j${i}b" "$TXT"
  if [[ "$RESPAWN" == yes ]]; then
    # the ensure-worker step notices the worker is gone and elects a replacement,
    # which is what has to deal with the orphaned player
    sleep 1.2
    start_worker none "${i}r"
    wait_ready || { echo "FATAL: replacement gen${i}r never ready" >&2; exit 1; }
  fi
  sleep 6
done

kill -TERM "$WPID" 2>/dev/null
sleep 0.3
printf '%s\n' "$OUT/$SID"
