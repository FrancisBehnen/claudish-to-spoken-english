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
#
# CORRECTED in round 5's review, for the same reason as run_lock.sh: speakd_probe.py
# and hook_probe.sh were resolved out of a private bench directory and the interpreter
# was one user's absolute path. That made the driver unrunnable from a checkout, and on
# the author's machine it could execute STALE external copies of the probes instead of
# the files committed beside it -- so "every figure re-derives from the committed rig"
# was not something the rig itself enforced. Overridable: RIG, PYTHON, OUT.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RIG=${RIG:-$HERE}
OUT=${OUT:-$RIG/out}
PY=${PYTHON:-python3}
CFG=${1:?config}; N=${2:-12}
# SOURCED BEFORE ANY WORKER EXISTS -- see the same line in run_real.sh for why the order
# is load-bearing rather than tidy: a cleanup.sh that cannot be read must fail while
# there is still nothing to leak. Nothing here reads $SID or $TRACE at source time.
. "$RIG/cleanup.sh" || { echo "FATAL: cannot source $RIG/cleanup.sh" >&2; exit 2; }

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
  # Clear the previous worker's ready marker BEFORE launching this one. Doing it in
  # wait_ready is a race the parent loses whenever the child is fast: the worker stamps
  # `ready`, the parent then deletes it, and the wait times out against a healthy worker.
  rm -f "$SD/ready"
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

# EVERY FATAL PATH MUST TAKE THE CURRENT WORKER WITH IT. Three of them did not: the
# initial readiness failure, the per-trial generation readiness failure, and the
# replacement readiness failure all `exit 1` with a worker running under
# `--idle-exit-s 600` -- ten minutes of stranded background process per failed run,
# holding this configuration's speak dir and its own election. A stranded worker from
# a failed sweep is not merely untidy: it competes for the next run's jobs and shows up
# in its resource usage, so the retry that was supposed to diagnose the failure is
# measuring two workers.
#
# The trap is declared ONCE, here beside `start_worker`, rather than repeated at each
# `exit` -- the defect is that a fatal path added later gets forgotten, and a guard
# spelled out per-site is the same defect waiting. It reads $WPID AT TRAP TIME, which is
# what makes it correct in a driver that restarts the worker per trial: whichever worker
# `start_worker` last launched is the one terminated and reaped.
#
# ROUND 30 -- AND THE TRAP AS ROUND 27 WROTE IT MADE THIS DOCUMENT'S OWN CENTRAL MISTAKE.
# It did `kill -TERM "$WPID"` and nothing else. `speakd_probe.py` calls `os.setsid()`, so
# the worker LEADS a process group and its players are in that group, not in this driver's:
# a signal to the worker's pid does not reach one of them. So a hook-B failure terminated
# the worker and left a 2.5 s stub sleeping, and `C17_setsid_player`'s player -- which
# `setsid()`s ITSELF, and is the arm that exists to show clause 7(iv) failing -- was
# outside even the worker's group and outside anything this trap could name. THE CLEANUP
# PATH MADE EXACTLY THE MISTAKE THE PROTOCOL UNDER TEST WAS WRITTEN TO PREVENT: §4b clause
# 7(iv) is the process-group sweep, and it exists because killing a worker's pid does not
# reach that worker's player. The rule, the guards and the residual are in cleanup.sh, one
# copy for both drivers -- sourced at the top of this file, not here, so that a
# cleanup.sh that cannot be read fails BEFORE there is a worker to leak.
kill_worker() {
  [[ -n ${WPID:-} ]] || return 0
  kill_worker_group "$WPID"
  # AND THEN THE PLAYERS NO GROUP KILL CAN REACH, of which this driver stages two kinds:
  # `PLAYERSETSID=on` (C17) puts the player in its own session, and `DIE=popen` leaves the
  # group without a live leader, so `kill_worker_group` refuses to name it. Both are read
  # out of the trace's `P_popen` pids and identity-checked against $SID. cleanup.sh says
  # why the trace and not the player records, and what is still out of reach.
  reap_stray_players "$TRACE" "$SID" "$WPID"
  wait "$WPID" 2>/dev/null
  return 0
}
trap kill_worker EXIT

wait_ready() {
  # The stale marker is cleared by start_worker BEFORE it launches, not here. Clearing it
  # here is a race the parent loses whenever the child is fast: the worker reaches ready,
  # stamps the marker, and then this function deletes the marker it was waiting for and
  # times out against a perfectly healthy worker.
  for _ in $(seq 1 200); do [[ -f "$SD/ready" ]] && return 0; sleep 0.05; done
  return 1
}

start_worker none 1
if ! wait_ready; then echo "FATAL: worker never became ready" >&2; exit 1; fi

# A hook that fails has not measured the trial it was supposed to measure -- it either
# stamped no markers or published nothing -- and the run must stop rather than continue
# producing a directory that looks complete to everything except a marker count nobody
# is obliged to check. See hook_probe.sh, which no longer exits 0 regardless.
hook() {   # tag job_id text_file
  "$RIG/hook_probe.sh" "$SD" "$MD" "$1" "$2" "$3" && return 0
  echo "FATAL: hook $1 failed in $CFG -- the run is not measurable" >&2
  exit 1
}

# one throwaway job so the worker is WARM: it has already synthesised and played
hook warmup w0 "$TXT"
sleep 5

for i in $(seq 1 "$N"); do
  A="t${i}a"; B="t${i}b"
  if [[ "$DIE" != none ]]; then
    # the worker exits inside the P->W window, so it must be (re)started per trial.
    # The old owner record is left in place deliberately: superseding it via the
    # generation election is the realistic path, and the pgid sweep needs to read it.
    #
    # THIS ONE IS A PID KILL ON PURPOSE and must not be "fixed" into the group kill the
    # EXIT trap uses. It is not cleanup: it is the STAGING. The previous generation's
    # orphaned player is the subject of the trial -- the replacement election's record and
    # process-group sweeps are what has to reach it -- so a group kill here would destroy
    # the orphan before the mechanism under test could be observed failing or succeeding
    # against it. The distinction is the whole of round 30's finding read the other way:
    # ask what the thing's children are in, then decide whether you want them.
    kill -TERM "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null
    start_worker "$DIE" "$i"
    wait_ready || { echo "FATAL: worker gen$i never ready" >&2; exit 1; }
  fi
  hook "$A" "j${i}a" "$TXT"
  sleep "$GAP"
  hook "$B" "j${i}b" "$TXT"
  if [[ "$THIRD" == yes ]]; then
    sleep 1.9
    hook "t${i}c" "j${i}c" "$TXT"
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

# The EXIT trap terminates and REAPS the worker, so the normal path no longer needs its
# own kill and no longer sleeps hoping the process is gone by the time the caller reads
# the path this prints.
printf '%s\n' "$OUT/$SID"
