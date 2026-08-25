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
#     W  = P + ~1 ms     pid record published  (by the worker, or by the player)
#     K_B = t0 + GAP     hook B reads the record(s) and kills
#     R_B = t0 + GAP + HOOK_GAP_S
# so GAP picks which of the orderings the trial lands in.
#
# ROUND 2 adds RESPAWN_DELAY as a first-class knob. In round 1 it was hardcoded at
# 1.2 s, which -- as review of PR #28 pointed out -- guaranteed the replacement
# worker was always elected AFTER the player had published, so the C9 arm could
# never exercise the ordering it claimed to close. The C11/C12 families stage the
# replacement on BOTH sides of the publication by varying RESPAWN_DELAY against
# PUBDELAY.
#
# usage: run_preempt.sh <config> <trials>
set -u
RIG="$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25"
OUT="$RIG/out"
PY=/Users/francis.behnen/homebrew/bin/python3
CFG=${1:?config}; N=${2:-12}

SYNTH_MS=1000
PLAYER_SECS=2.5
LOAD_MS=700
HOOK_GAP_S=0.09
export HOOK_GAP_S

DIE=none; REAP=on; LEDGER=off; SWEEP=off; RESPAWN=no; PIDW=on
PIDMODE=worker; PUBDELAY=0; SWEEPMODE=off; SWEEPGAP=0; REAPDELAY=0; UNLINKREAP=off
PENDING=off; PLAYERSETSID=off; THIRD=no
RESPAWN_DELAY=1.2
case "$CFG" in
  # ---------- round 1: the three orderings, all three preemption hooks in
  C1_prespawn)    DELAY=0    ; GAP=0.4 ; CK=pidfile ; RECHK=on  ;;
  C2_hookside)    DELAY=0    ; GAP=1.6 ; CK=pidfile ; RECHK=on  ;;
  C3_adversarial) DELAY=1000 ; GAP=1.4 ; CK=pidfile ; RECHK=on  ;;
  # ---------- round 1: falsification, one clause removed at a time
  C4_noclaimkill) DELAY=1000 ; GAP=1.4 ; CK=off     ; RECHK=on  ;;
  C5_norecheck)   DELAY=1000 ; GAP=1.4 ; CK=pidfile ; RECHK=off ;;
  C6_handle)      DELAY=1000 ; GAP=1.4 ; CK=handle  ; RECHK=on  ;;
  C7_noreap)      DELAY=0    ; GAP=1.6 ; CK=pidfile ; RECHK=on  ; REAP=off ;;
  C8_orphan)      DELAY=1000 ; GAP=1.4 ; CK=pidfile ; RECHK=on  ; DIE=popen ; RESPAWN=yes ;;
  C9_ledger)      DELAY=1000 ; GAP=1.4 ; CK=pidfile ; RECHK=on  ; DIE=popen ; RESPAWN=yes ; LEDGER=on ; SWEEP=on ;;
  C10a_nopid_pidfile) DELAY=0 ; GAP=1.6 ; CK=pidfile ; RECHK=on ; PIDW=off ;;
  C10b_nopid_handle)  DELAY=0 ; GAP=1.6 ; CK=handle  ; RECHK=on ; PIDW=off ;;

  # ---------- round 2: the SINGLE-RECORD form -- what the replacement text
  #            actually specified, as opposed to the ledger C9 measured.
  # C11a: the replacement is elected AFTER the player publishes. This is the only
  #       ordering round 1 could reach.
  C11a_shared_pubfirst)
      DELAY=1000 ; GAP=1.4 ; CK=pidfile ; RECHK=on ; DIE=popen ; RESPAWN=yes
      PIDMODE=shared ; PUBDELAY=0 ; SWEEPMODE=record ; RESPAWN_DELAY=1.2 ;;
  # C11b: the replacement is elected BEFORE the player publishes -- the wrapper is
  #       still descheduled. This is the ordering the review said was untested.
  C11b_shared_sweepfirst)
      DELAY=1000 ; GAP=1.4 ; CK=pidfile ; RECHK=on ; DIE=popen ; RESPAWN=yes
      PIDMODE=shared ; PUBDELAY=1500 ; SWEEPMODE=record ; RESPAWN_DELAY=0.8 ;;

  # ---------- round 2: the PROCESS-GROUP repair, staged on both sides
  C12a_pgid_pubfirst)
      DELAY=1000 ; GAP=1.4 ; CK=pidfile ; RECHK=on ; DIE=popen ; RESPAWN=yes
      PIDMODE=perplayer ; PUBDELAY=0 ; SWEEPMODE=both ; RESPAWN_DELAY=1.2 ;;
  C12b_pgid_sweepfirst)
      DELAY=1000 ; GAP=1.4 ; CK=pidfile ; RECHK=on ; DIE=popen ; RESPAWN=yes
      PIDMODE=perplayer ; PUBDELAY=1500 ; SWEEPMODE=both ; RESPAWN_DELAY=0.8 ;;
  # C12c: per-player records but NO pgid sweep, to show which half does the work
  C12c_perplayer_recordonly)
      DELAY=1000 ; GAP=1.4 ; CK=pidfile ; RECHK=on ; DIE=popen ; RESPAWN=yes
      PIDMODE=perplayer ; PUBDELAY=1500 ; SWEEPMODE=record ; RESPAWN_DELAY=0.8 ;;

  # ---------- round 2: the ledger truncation defect, staged
  # The player publishes INSIDE the gap between the sweep's read and its truncate,
  # so the entry is erased without ever having been signalled.
  C13a_ledger_truncate)
      DELAY=1000 ; GAP=1.4 ; CK=pidfile ; RECHK=on ; DIE=popen ; RESPAWN=yes
      PIDMODE=shared ; LEDGER=on ; PUBDELAY=400 ; SWEEPMODE=record ; SWEEPGAP=900
      RESPAWN_DELAY=0.6 ;;
  C13b_perplayer_sametiming)
      DELAY=1000 ; GAP=1.4 ; CK=pidfile ; RECHK=on ; DIE=popen ; RESPAWN=yes
      PIDMODE=perplayer ; PUBDELAY=400 ; SWEEPMODE=both ; SWEEPGAP=900
      RESPAWN_DELAY=0.6 ;;

  # ---------- round 2: the read-then-unlink TOCTOU on a shared record
  C14a_shared_unlink)
      DELAY=0 ; GAP=1.6 ; CK=pidfile ; RECHK=on
      PIDMODE=shared ; PUBDELAY=0 ; UNLINKREAP=on ; REAPDELAY=1200 ; THIRD=yes ;;
  C14b_perplayer_unlink)
      DELAY=0 ; GAP=1.6 ; CK=pidfile ; RECHK=on
      PIDMODE=perplayer ; PUBDELAY=0 ; UNLINKREAP=on ; REAPDELAY=1200 ; THIRD=yes ;;

  # ---------- round 2: clause (ii) combined with worker death.
  # A newer job IS present at S2 (GAP small), and the worker dies after spawning.
  # With the recheck ON no player is spawned, so there is no orphan; with it OFF
  # the stale player is spawned and orphaned. This is the counterexample review
  # raised against the round-1 C5 conclusion.
  C15a_recheck_death)
      DELAY=0 ; GAP=0.4 ; CK=pidfile ; RECHK=on  ; DIE=popen ; RESPAWN=yes
      SWEEPMODE=off ; RESPAWN_DELAY=0.8 ;;
  C15b_norecheck_death)
      DELAY=0 ; GAP=0.4 ; CK=pidfile ; RECHK=off ; DIE=popen ; RESPAWN=yes
      SWEEPMODE=off ; RESPAWN_DELAY=0.8 ;;

  # ---------- round 2: the PENDING-MARKER refinement.
  # killpg on every election has a worse blast radius than one pid kill if a pid
  # recycles as a group leader. The worker creates playerdir/<nonce>.pending BEFORE
  # forking and the wrapper renames it away, so "an unnamed player may exist" is
  # observable and killpg is used ONLY then.
  # C16a: sweep lands before publication -> .pending present -> killpg fires
  C16a_pending_sweepfirst)
      DELAY=1000 ; GAP=1.4 ; CK=pidfile ; RECHK=on ; DIE=popen ; RESPAWN=yes
      PIDMODE=perplayer ; PUBDELAY=1500 ; SWEEPMODE=both ; RESPAWN_DELAY=0.8
      PENDING=on ;;
  # C16b: sweep lands after publication -> no .pending -> killpg SKIPPED, and the
  #       record sweep alone must do the work
  C16b_pending_pubfirst)
      DELAY=1000 ; GAP=1.4 ; CK=pidfile ; RECHK=on ; DIE=popen ; RESPAWN=yes
      PIDMODE=perplayer ; PUBDELAY=0 ; SWEEPMODE=both ; RESPAWN_DELAY=1.2
      PENDING=on ;;

  # ---------- round 2: does clause (ii)'s correctness role SURVIVE clause (iv)?
  # C15b shows the recheck preventing an orphan that the no-recheck arm creates, but
  # only because no sweep was in place. This is C15b with the process-group sweep on:
  # if the orphan is caught anyway, (ii) is an optimisation again.
  C15c_norecheck_death_pgid)
      DELAY=0 ; GAP=0.4 ; CK=pidfile ; RECHK=off ; DIE=popen ; RESPAWN=yes
      PIDMODE=perplayer ; SWEEPMODE=both ; PENDING=on ; RESPAWN_DELAY=0.8 ;;

  # ---------- round 2: the one line that defeats clause 7(iv).
  # Identical to C12b except the player is spawned into its OWN session, so it is no
  # longer in the worker's process group and killpg cannot reach it.
  C17_setsid_player)
      DELAY=1000 ; GAP=1.4 ; CK=pidfile ; RECHK=on ; DIE=popen ; RESPAWN=yes
      PIDMODE=perplayer ; PUBDELAY=1500 ; SWEEPMODE=both ; RESPAWN_DELAY=0.8
      PENDING=on ; PLAYERSETSID=on ;;
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
printf '%s\n' "cfg=$CFG delay=$DELAY gap=$GAP ck=$CK rechk=$RECHK die=$DIE respawn=$RESPAWN" \
  "respawn_delay=$RESPAWN_DELAY pidmode=$PIDMODE pubdelay=$PUBDELAY sweepmode=$SWEEPMODE" \
  "sweepgap=$SWEEPGAP reapdelay=$REAPDELAY unlinkreap=$UNLINKREAP ledger=$LEDGER pidw=$PIDW" \
  "pending=$PENDING playersetsid=$PLAYERSETSID" \
  > "$OUT/$SID/config.txt"

start_worker() {
  "$PY" "$RIG/speakd_probe.py" --speak-dir "$SD" --trace "$TRACE" --player-log "$PLOG" \
    --claim-kill "$CK" --prespawn-recheck "$RECHK" --pid-write "$PIDW" \
    --prespawn-delay-ms "$DELAY" --synth-ms "$SYNTH_MS" --load-ms "$LOAD_MS" \
    --player-secs "$PLAYER_SECS" --idle-exit-s 600 --reap "$REAP" \
    --die-after "$1" --ledger "$LEDGER" --sweep-on-election "$SWEEP" \
    --pid-mode "$PIDMODE" --publish-delay-ms "$PUBDELAY" \
    --sweep-mode "$SWEEPMODE" --sweep-gap-ms "$SWEEPGAP" \
    --reap-delay-ms "$REAPDELAY" --unlink-on-reap "$UNLINKREAP" \
    --pending-marker "$PENDING" --player-setsid "$PLAYERSETSID" \
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
    # The old owner record is left in place deliberately: superseding it via the
    # generation election is the realistic path, and the pgid sweep needs to read it.
    kill -TERM "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null
    start_worker "$DIE" "$i"
    wait_ready || { echo "FATAL: worker gen$i never ready" >&2; exit 1; }
  fi
  "$RIG/hook_probe.sh" "$SD" "$MD" "$A" "j${i}a" "$TXT"
  sleep "$GAP"
  "$RIG/hook_probe.sh" "$SD" "$MD" "$B" "j${i}b" "$TXT"
  if [[ "$THIRD" == yes ]]; then
    sleep 1.9
    "$RIG/hook_probe.sh" "$SD" "$MD" "t${i}c" "j${i}c" "$TXT"
  fi
  if [[ "$RESPAWN" == yes ]]; then
    # the ensure-worker step notices the worker is gone and elects a replacement,
    # which is what has to deal with the orphaned player. RESPAWN_DELAY decides
    # whether it is elected before or after the player publishes.
    sleep "$RESPAWN_DELAY"
    if kill -0 "$WPID" 2>/dev/null; then
      # the worker is still alive -- it discarded at the recheck and never reached
      # P, so --die-after popen never fired and there is nothing to replace
      printf 'trial %s: no replacement needed, worker still alive\n' "$i" \
        >> "$OUT/$SID/config.txt"
    else
      start_worker none "${i}r"
      wait_ready || { echo "FATAL: replacement gen${i}r never ready" >&2; exit 1; }
    fi
  fi
  sleep 6
done

kill -TERM "$WPID" 2>/dev/null
sleep 0.3
printf '%s\n' "$OUT/$SID"
