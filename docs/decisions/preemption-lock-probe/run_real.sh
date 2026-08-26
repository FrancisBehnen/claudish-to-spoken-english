#!/bin/bash
# Real-audio confirmation for row 20. Kokoro synthesis, afplay as the player, on
# bf_emma, is_phonemes=False. The stub runs establish the ORDERING and the attribution;
# this arm runs the same ordering against a REAL PLAYER on a real wav.
#
# ROUND 27: IT DOES NOT ANSWER AUDIBILITY, and this header used to say it did -- "the one
# question a stub cannot: whether the stale utterance is audible, and for how long". It
# cannot. Nothing in this rig listens: every figure the arm produces is an `afplay`
# PROCESS stamp (Popen return, reap), and afplay's time-to-first-sample is not
# instrumented anywhere. A newer afplay process existing does not establish when its
# output became audible. What the arm adds over a stub is that the process being killed
# is a real player decoding a real 5.7 s wav rather than a `sleep`. Audibility needs a
# loopback capture of the output device, which this driver does not do and this machine
# cannot do; see the decision document's section 2.6 and derivation defect 14.
#
# usage: run_real.sh <claim_kill: pidfile|off> <trials>
#
# Paths resolve from this script, not from a private bench dir -- see run_preempt.sh.
# PYTHON is overridable but NOT defaulted to a bare python3 as in the stub drivers:
# this arm imports kokoro_onnx (the installed distribution is kokoro-onnx; the probe does
# `from kokoro_onnx import Kokoro`) and loads a ~340 MB model, so the default stays the venv
# that has it. Point PYTHON at any interpreter that can `import kokoro_onnx`.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RIG=${RIG:-$HERE}
OUT=${OUT:-$RIG/out}
PY=${PYTHON:-$HOME/.local/share/kokoro/venv/bin/python}
CK=${1:?claim-kill}; N=${2:-3}
# SOURCED BEFORE THE WORKER EXISTS, and the order is the point. The round-30 draft
# sourced this at the trap, thirty lines AFTER `speakd_probe.py &` -- so a missing or
# unreadable cleanup.sh took the `exit 2` branch while the worker it could no longer
# terminate ran on under `--idle-exit-s 600`. That is harness defect 5 exactly, re-armed
# by the code written to repair it. Nothing here reads $SID or $TRACE at source time;
# they are read when the trap CALLS these functions, so sourcing early costs nothing and
# makes "the cleanup exists before the thing needing cleanup" a property of the file
# order rather than of a reviewer noticing.
. "$RIG/cleanup.sh" || { echo "FATAL: cannot source $RIG/cleanup.sh" >&2; exit 2; }
HOOK_GAP_S=0.09
export HOOK_GAP_S

SID="REAL-$CK-$(date +%s)"
SD="$OUT/$SID/speak"; MD="$OUT/$SID/markers"
mkdir -p "$SD" "$MD"
TRACE="$OUT/$SID/worker.trace"; PLOG="$OUT/$SID/player.log"; TXT="$OUT/$SID/text"
# Two lexically distinguishable utterances, so that a listener WOULD be able to tell an
# overlap from a single voice. Nobody listens: this is a property of the fixture, not an
# observation, and round 28 reworded it because the old form ("so an overlap is audible as
# an overlap") asserted the observation. Round 27 corrected this file's header and left the
# line; it belongs to derivation defect 14's arm, not to defect 15's stub schema.
printf 'The older utterance says: one, two, three, four, five, six, seven, eight.\n' > "$TXT"
printf 'The newer utterance says: alpha, bravo, charlie, delta, echo, foxtrot.\n' > "$OUT/$SID/text2"

"$PY" "$RIG/speakd_probe.py" --speak-dir "$SD" --trace "$TRACE" --player-log "$PLOG" \
  --claim-kill "$CK" --prespawn-recheck on --pid-write on \
  --prespawn-delay-ms 1000 --real-kokoro --real-player --voice bf_emma \
  --idle-exit-s 600 --generation 1 &
WPID=$!
# EVERY FATAL PATH MUST TAKE THE WORKER WITH IT, and the trap is installed HERE --
# immediately after the pid is captured -- rather than repeated at each `exit`.
# The readiness timeout below used to `exit 1` while leaving the worker it had just
# started running with `--idle-exit-s 600`: ten minutes of stranded background process
# per failed run. In THIS arm that process holds a loaded ~340 MB Kokoro model, so a
# failed run does not merely leak, it can contaminate the resource usage of the retry
# the operator is about to start -- and the retry looks like a clean run. A trap rather
# than a `kill` at each site because the defect is structural: the guard has to cover
# the fatal path somebody adds later without remembering this paragraph.
# $WPID is read AT TRAP TIME, so this covers the current worker in a driver that
# restarts one (run_preempt.sh does; this one does not, yet).
#
# ROUND 30 -- AND THE TRAP AS ROUND 27 WROTE IT MADE THIS DOCUMENT'S OWN CENTRAL MISTAKE.
# It did `kill -TERM "$WPID"`, which terminates the worker and NOTHING ELSE. The worker
# calls `os.setsid()`, so it leads its own process group and its `afplay` is in THAT group:
# a signal to the worker's pid reaches the player not at all. In this arm the player is
# `afplay` decoding a real 5.7 s wav, so a fatal readiness or hook path terminated the
# worker and left that process running for the rest of the file, holding the output device
# it had opened -- into the
# retry the operator starts next, which is the contamination harness defect 5 exists to
# disclose, arriving through defect 5's own fix. §4b clause 7(iv) exists precisely because
# killing a worker's pid does not reach its player. See cleanup.sh, which holds the rule
# and the guards, in one place for both drivers -- sourced at the top of this file, not
# here, so that a cleanup.sh that cannot be read fails BEFORE there is a worker to leak.
kill_worker() {
  [[ -n ${WPID:-} ]] || return 0
  kill_worker_group "$WPID"
  # `--player-setsid` is off in this arm and `--die-after` is unset, so the worker leads
  # its group and every `afplay` is inside it: the group kill above is sufficient HERE.
  # The sweep runs anyway, because "sufficient here" is a property of today's flag set and
  # the leak it would allow is silent. It signals nothing on a clean run.
  reap_stray_players "$TRACE" "$SID" "$WPID"
  wait "$WPID" 2>/dev/null
  return 0
}
trap kill_worker EXIT
for _ in $(seq 1 400); do [[ -f "$SD/ready" ]] && break; sleep 0.05; done
[[ -f "$SD/ready" ]] || { echo "FATAL: worker never ready" >&2; exit 1; }

# A failed hook is fatal here for the same reason as in run_preempt.sh: it measures
# nothing, and this arm has three trials, so one silent loss is a third of section E.
hook() {   # tag job_id text_file
  "$RIG/hook_probe.sh" "$SD" "$MD" "$1" "$2" "$3" && return 0
  echo "FATAL: hook $1 failed in $SID -- the run is not measurable" >&2
  exit 1
}

hook warmup w0 "$TXT"
sleep 8
for i in $(seq 1 "$N"); do
  hook "t${i}a" "j${i}a" "$TXT"
  sleep 1.4
  hook "t${i}b" "j${i}b" "$OUT/$SID/text2"
  sleep 12
done
# The EXIT trap terminates and REAPS the worker, so the normal path no longer needs its
# own kill and no longer sleeps hoping the process is gone by the time the caller reads
# the path this prints.
printf '%s\n' "$OUT/$SID"
