#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Stop hook: speak the turn's plain-English rewrite aloud.  COLD PATH.
#
# This is the hook half of docs/decisions/speech-integration-spec.md.  It does
# the steps of §10.3 -- in §10.3's order except for step 6, which runs later
# than the spec puts it and says why -- drops a job, forks a DETACHED speaker,
# and exits 0.  It never waits for synthesis, playback, or the rewrite.
#
# NO `set` OPTIONS, DELIBERATELY (§5).  On a Stop hook exit code 2 is not a
# failure report, it is a request to BLOCK the turn, and it costs nine
# invocations of this hook with our stderr fed to the model as prompt input.
# So: exit 0 on every path, nothing on stderr ever, and no `set -e`/`-u`/
# `pipefail` that could turn a typo into a 2.  The two routes that actually
# reach 2 are a bash syntax error (gated with `bash -n`) and jq handed a
# filename it cannot read (`--rawfile`/`--slurpfile`) -- this script passes NO
# filename to jq, on any path.
#
# WHAT IS DEFERRED FROM THE SPEC, collected in
# docs/decisions/speak-cold-path.md rather than only here:
#   * §10.5's lazy self-electing per-session RESIDENT WORKER is NOT built.  No
#     generation election, no kqueue wake, no owner records, no retirement, no
#     20-minute idle exit.  This hook forks a fresh speaker per turn.  Measured
#     cold time-to-first-audio on this machine is 2.27/2.29/2.81 s, already
#     under the spec's own 3 s line, and residency is the direct cause of four
#     of the spec's five ship-blocking defects (§13 rows 20, 21, 24, 27).
#   * §10.6's anchored player-record preemption protocol is NOT built.  Step 6
#     below is a best-effort barge-in instead, and it also runs LATER than
#     §10.3 orders it; see its comment for both.
#   * §3.5.1's bounded wait lives in the DETACHED CHILD, never here, because
#     there is no worker to put it in.  §6's non-blocking guarantee is the
#     reason it cannot live in this process.
#   * §3.3, §3.4, and three of §3.5's four table rows are GONE, by the user's
#     decision of 2026-09-01: speech has no length floor of its own.  There is
#     no raw path in this hook any more, and therefore no eight-class hazard
#     gate on one.  Step 10 says what that costs.
#
# Config (§10.1).  CLAUDISH_SPEAK_MIN_CHARS and CLAUDISH_TTS_URL are LOCKED
# ABSENT by §9 and #5 and are deliberately not implemented anywhere:
#   CLAUDISH_SPEAK           1|0     master speech switch (default 0 -- OFF)
#   CLAUDISH_SPEAK_OFF_FILE  <path>  runtime mute, checked fresh every
#                                    invocation AND again in the child before
#                                    every sentence (default
#                                    ~/.claude/claudish-speak-off).  Separate
#                                    from the rewrite plugin's claudish-off.
#   CLAUDISH_VOICE           <name>  Kokoro voice (default bf_emma)
#   CLAUDISH_PLAYER          <cmd>   audio player (default afplay)
#   CLAUDISH_SPEAK_TIMEOUT   <secs>  bounds SYNTHESIS, not this hook (default 30)
#   KOKORO_ROOT              <path>  (default ~/.local/share/kokoro)
#   CLAUDISH_DEBUG           1|0     reuse rewrite.sh's flag and its
#                                    $BUF_ROOT/debug.log sink; never stderr
# and, read from rewrite.sh's own variables so the two hooks cannot disagree:
#   CLAUDISH_ENABLED, CLAUDISH_OFF_FILE, CLAUDISH_TIMEOUT
# CLAUDISH_MIN_CHARS was on that list and is NOT read here any more, on any
# path: it gates the REWRITE, and speech no longer has a length gate at all.
# ---------------------------------------------------------------------------

# ---- step 0a: DERIVE ENABLED, exactly as rewrite.sh:57 derives it. --------
# Unset means ENABLED, which is the state essentially every user is in.
# Before reading stdin.
ENABLED="${CLAUDISH_ENABLED:-1}"

# ---- step 0b: clear it exactly as rewrite.sh:61 clears it, then compare ---
# exactly as rewrite.sh:100 compares -- against the DERIVED variable, never
# against the raw environment.  These three lines are rewrite.sh:57, :61 and
# :100 in that order; specifying only the last of them is the defect the spec
# records three drafts of.
[ -f "${CLAUDISH_OFF_FILE:-$HOME/.claude/claudish-off}" ] && ENABLED=0
[ "$ENABLED" = "1" ] || exit 0

# ---- step 1: off by default.  Before reading stdin, before jq. ------------
[ "${CLAUDISH_SPEAK:-0}" = "1" ] || exit 0

# ---- step 2: runtime mute.  Not the whole mute promise -- the child ------
# re-checks this file before every synthesis and every play, because this stat
# can be the whole bounded wait (123 s at the defaults) older than the sound.
SPEAK_OFF_FILE="${CLAUDISH_SPEAK_OFF_FILE:-$HOME/.claude/claudish-speak-off}"
[ -f "$SPEAK_OFF_FILE" ] && exit 0

# ---- step 3: jq.  AFTER the gates, so a speech-disabled user's turn never --
# depends on jq being installed (§11).  rewrite.sh:100-101 is the precedent.
command -v jq >/dev/null 2>&1 || exit 0

# Same string as rewrite.sh:69.  Do not give this its own default; the two
# must not be able to drift.
BUF_ROOT="${TMPDIR:-/tmp}/claudish-to-english"
DEBUG="${CLAUDISH_DEBUG:-0}"
SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"

# Debug goes to a FILE.  Never stderr: on Stop, a blocking hook's stderr is
# delivered to the model as a synthetic user message (§5).
dbg() {
  [ "$DEBUG" = "1" ] && printf '%s [%s] speak: %s\n' \
    "$(date '+%H:%M:%S')" "$$" "$*" >> "$BUF_ROOT/debug.log" 2>/dev/null
  return 0
}

# ---- step 4: read the payload --------------------------------------------
payload="$(cat)"
[ -n "$payload" ] || exit 0

# ---- step 5: session_id, and DO NOT default it ---------------------------
# Everything below is addressed by $BUF_ROOT/<session_id>/speak/.  Pooling
# unrelated sessions under a literal "nosession" is the trap rewrite.sh:108
# already carries on the publisher's side.
sid="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$sid" ] || exit 0
case "$sid" in */*|..|.) exit 0 ;; esac
SPEAK_DIR="$BUF_ROOT/$sid/speak"

# ---- step 7: NOT a stop_hook_active check -------------------------------
# §5.1: that flag is read for no behaviour.  Dedup is the child's, on the
# resolved text, at the moment it goes to synthesis (§3.5.1 clause 6).

# ---- step 8: a running background task suppresses the announcement (§8) --
bg="$(printf '%s' "$payload" \
  | jq -r '[.background_tasks[]? | select(.status=="running")] | length' 2>/dev/null)"
case "$bg" in ''|*[!0-9]*) bg=0 ;; esac
[ "$bg" -eq 0 ] 2>/dev/null || { dbg "background task running -> silent"; exit 0; }

# ---- step 9: last_assistant_message, absent-by-default (§2) -------------
# Read from the Stop payload, NEVER from transcript_path.  The payload has
# exactly eleven fields; stop_reason and model are ABSENT despite the docs, so
# nothing here references them.
mkdir -p "$SPEAK_DIR" 2>/dev/null || exit 0
msg="$SPEAK_DIR/.msg.$$"
printf '%s' "$payload" | jq -j '.last_assistant_message // ""' > "$msg" 2>/dev/null \
  || { rm -f "$msg" 2>/dev/null; exit 0; }
[ -s "$msg" ] || { rm -f "$msg" 2>/dev/null; exit 0; }

# ---- step 6: PREEMPTION -- DELIBERATELY LATER THAN §10.3 ORDERS IT -------
# §10.3 puts this above every content-based exit, reasoning that a newer turn
# which is deliberately silent must still cut the previous turn's audio
# because nothing else will.  THAT REASONING WAS OBSERVED WRONG.  A long
# answer was playing, the user asked a one-line question, the reply to it
# never reached synthesis -- and the previous answer was cut off mid-sentence
# with nothing in its place.  Two turns in one live log would have done it
# (prose_len 53 and 54).  Silence where speech was is not preemption, it is a
# lost utterance.
#
# So the kill runs HERE: below every gate that exits WITHOUT speaking (step
# 8's running background task, step 9's absent last_assistant_message) and
# above the fork, so a turn that DOES speak still leaves exactly one speaker.
# What is still below this line is FAILURE, never silence by design -- an
# unreadable speak-key.sh, a key that will not compute, an unwritable job, a
# missing Kokoro venv -- and preempting on a failure is deliberate: that turn
# was going to speak.  (The venv row is vacuous anyway: with no interpreter
# nothing ever became a speaker to preempt.)
#
# DEFERRED: this is NOT §10.6's anchored player-record protocol.  There is no
# playerdir/, no per-player <pid>.<nonce> record matched on an anchored
# ^[0-9]+\.[0-9a-f]{8}$, no .pending markers and no generation prefix.  It is a
# deliberate cold-path stand-in built on the SAME record speak-child.py's
# exclusive consumer claim uses (§3.5.1 clause 5, §5.1): one lock directory,
# one owner record holding <pid> and <lstart>, one process group.  The speaker
# is its own session leader, so its players share its group and one signal
# reaches all of them.
#
# The record is validated TWICE before it is signalled, and both tests matter:
#   * the recorded start time must equal the CURRENT start time of that pid --
#     otherwise the pid was recycled and now names a stranger; and
#   * the command must still be one of ours.
# A confirmed absence and a failed lookup both decline to signal.  The residual
# is `ps`'s one-second `lstart` resolution: a pid recycled inside the same
# second reads as a match.  §10.6 has the same residual.
#
# Everything here is best-effort: preemption can never change this hook's exit
# path.  If it misses, speak-child.py's own claim is the second line of defence
# -- and if BOTH miss, two speakers talk over each other.  That is the failure
# mode, and docs/decisions/speak-cold-path.md names it.
preempt() {
  owner="$SPEAK_DIR/consumer/owner"
  [ -f "$owner" ] || return 0
  opid="$(sed -n 1p "$owner" 2>/dev/null)"
  ostart="$(sed -n 2p "$owner" 2>/dev/null)"
  case "$opid" in ''|*[!0-9]*) return 0 ;; esac
  [ "$opid" -gt 1 ] 2>/dev/null || return 0
  # Same canonical form speak-child.py builds: five ps fields, single-spaced.
  cstart="$(ps -p "$opid" -o lstart= 2>/dev/null \
            | awk '{printf "%s %s %s %s %s", $1, $2, $3, $4, $5}')"
  [ -n "$cstart" ] || return 0
  [ -n "$ostart" ] && [ "$cstart" != "$ostart" ] && return 0
  ps -p "$opid" -o command= 2>/dev/null | grep -q 'speak-child\.py' || return 0
  dbg "preempt speaker pid=$opid"
  kill -TERM -"$opid" 2>/dev/null
  return 0
}
preempt

# ---- step 10: classify -- ONE row now, and no length floor -------------
# §3.5's decision table had four rows.  Three of them turned on
# CLAUDISH_MIN_CHARS and all three are GONE, by the user's decision of
# 2026-09-01: speech gets no length floor of its own, because rewrite.sh
# already decides what is worth rewriting.
#
# What the floor rested on here was §3.3's premise 2 -- "below the threshold
# there is no rewrite to hand over" -- and that premise is now FALSE:
# rewrite.sh publishes on its short path too, carrying the RAW text under the
# SAME key (speak-key.sh, one definition, both hooks).  With the premise gone:
#
#   * the RAW mode is gone.  Short text now arrives the way long text does,
#     through speak/rw.<H>, so there is nothing left for this hook to speak
#     out of the job payload and no wait=0 row to speak it on.
#   * §3.4's EIGHT-CLASS HAZARD GATE went with it, and that is a spec change,
#     not a cleanup.  The gate guarded RAW speech FROM THIS HOOK, and this
#     hook no longer speaks raw -- but §3.4 is LOCKED, so state the cost:
#     short text carrying a disqualifying class (a path, a URL, a fence) is
#     now spoken, sanitized, which means a path loses its leading segments and
#     a fence becomes "Code block, N lines."  What makes that tolerable is
#     §3.4's own measurement, and it is a measurement of no-op rather than of
#     benefit: of #10's sixteen real sub-threshold items, ZERO carried a
#     disqualifying class.  The gate silenced nothing anyone has measured.
#   * §3.5's "below MIN_CHARS the wait must never run" is gone too.  Below the
#     threshold there is now something to wait FOR, and it lands in
#     milliseconds because rewrite.sh's short path makes no LLM call.
#
# One row is left, and it is §3.5's last one: wait for speak/rw.<H>, speak it
# if it lands, be silent at the deadline (§3.5.1).
#
# prose_len is still computed and it is now PURELY DIAGNOSTIC -- nothing
# compares it to anything.  It is kept because it is the number that named the
# bug step 6 fixes (two live turns at 53 and 54) and it is what to grep for in
# debug.log.  Same formula as rewrite.sh:139-142 (strip fenced blocks, delete
# whitespace, wc -c), so the two logs stay comparable: BYTES of non-whitespace,
# not characters.
prose_len="$(awk 'BEGIN{f=0} /^```/{f=!f; next} f==0{print}' "$msg" 2>/dev/null \
  | tr -d '[:space:]' | wc -c | tr -d ' ')"
case "$prose_len" in ''|*[!0-9]*) prose_len=0 ;; esac

# H = sha256( trim( last_assistant_message ) ), from speak-key.sh -- the ONE
# definition of the handoff key, sourced by this hook and by rewrite.sh's
# publish so the two cannot drift.  Getting this identical on both sides is the
# single thing that decides whether the user hears this turn's rewrite or
# nothing at all.  Sourced AFTER step 6, so a key that cannot be computed still
# preempts: this turn was going to speak.
. "$SELF_DIR/speak-key.sh" 2>/dev/null
command -v speak_key >/dev/null 2>&1 || { rm -f "$msg" 2>/dev/null; exit 0; }
H="$(speak_key "$(cat "$msg" 2>/dev/null)")"
case "$H" in
  '') rm -f "$msg" 2>/dev/null; exit 0 ;;
esac

# The hit test is an existence check on ONE path computed from our own hash --
# never a read-and-compare, and there is no speak/source to compare against
# (§3.1 draft 3).  A path that already exists identifies the TEXT, not the
# generation: it was probably installed by an earlier turn (§3.2's repeated-
# text collision, §13 row 28), and on the tail of turns where this turn's own
# publish landed first it is the current one.
#
# It selects nothing any more -- there is one mode -- and it is NOT dropped for
# that reason: speak-child.py re-tests the same path on the first turn of its
# wait, so a hit resolves there, and this test is the only place §3.2's
# repeated-text collision is observable at all.  A label for the log.
hit="no"
[ -f "$SPEAK_DIR/rw.$H" ] && hit="yes"
mode="buffered"

dbg "classify mode=$mode hit=$hit prose_len=$prose_len hash=$H"

# ---- step 11: dedup -- NOT here.  §3.5.1 clause 6 puts it in the child, ---
# at the moment text goes to synthesis, because on the waiting row the
# resolved text is not known in this process.  Nothing here reads or writes
# speak/spoken.

# ---- step 12: install the job by rename, fork detached, exit 0 -----------
# The wait deadline is DERIVED, not a new knob (§10.1, §3.5.1 clause 3):
#   min( CLAUDISH_TIMEOUT + 2, MD_TIMEOUT ) + 3   ==  123 s at the defaults
# MD_TIMEOUT is hooks/hooks.json's declared MessageDisplay timeout: a rewrite
# the harness stops at MD_TIMEOUT publishes nothing at all, so raising
# CLAUDISH_TIMEOUT past MD_TIMEOUT - 2 buys the wait nothing.  Read from the
# SAME env var rewrite.sh reads, so both hooks see the same frozen number.
#
# THE FORMULA IS UNCHANGED BY #14; ONLY ITS [repo] INPUTS MOVED.  hooks.json's
# MessageDisplay timeout went 60 -> 120 and CLAUDISH_TIMEOUT's default 45 -> 120,
# so both constants below are re-read from the repo rather than the clause being
# amended.  Had MD_TIMEOUT been left at 60 while hooks.json said 120, every
# rewrite landing between 63 s and 120 s would be DISPLAYED and never SPOKEN --
# the exact undocumented-interaction-between-two-numbers failure this project
# keeps hitting.  tests/config-test.sh pins MD_TIMEOUT to hooks.json's declared
# value, so the two can no longer drift silently.
LLM_TIMEOUT="${CLAUDISH_TIMEOUT:-120}"
case "$LLM_TIMEOUT" in ''|*[!0-9]*) LLM_TIMEOUT=120 ;; esac
MD_TIMEOUT=120
WAIT=$((LLM_TIMEOUT + 2))
[ "$WAIT" -gt "$MD_TIMEOUT" ] && WAIT="$MD_TIMEOUT"
WAIT=$((WAIT + 3))

SPEAK_TIMEOUT="${CLAUDISH_SPEAK_TIMEOUT:-30}"
case "$SPEAK_TIMEOUT" in ''|*[!0-9]*) SPEAK_TIMEOUT=30 ;; esac

job_tmp="$SPEAK_DIR/.job.$$.$RANDOM"
job="$SPEAK_DIR/job.$$"
{
  printf 'fire=%s\n'          "$(date +%s)"
  printf 'hash=%s\n'          "$H"
  printf 'mode=%s\n'          "$mode"
  printf 'wait=%s\n'          "$WAIT"
  printf 'synth_timeout=%s\n' "$SPEAK_TIMEOUT"
  printf 'voice=%s\n'         "${CLAUDISH_VOICE:-bf_emma}"
  printf 'player=%s\n'        "${CLAUDISH_PLAYER:-afplay}"
  printf 'root=%s\n'          "$SELF_DIR"
  printf -- '--TEXT--\n'
  cat "$msg" 2>/dev/null
} > "$job_tmp" 2>/dev/null || { rm -f "$job_tmp" "$msg" 2>/dev/null; exit 0; }
rm -f "$msg" 2>/dev/null
# rename(2), atomic, inside the one directory both hooks already share.
# DEFERRED: the job is NOT renamed onto a single `speak/job` claimed by a
# resident worker (§10.5 clause 1).  There is no shared worker to claim it, so
# each hook installs its own job at a unique name and hands that name to the
# child it forks.  A second hook therefore cannot overwrite a job a child is
# still reading.
mv -f "$job_tmp" "$job" 2>/dev/null || { rm -f "$job_tmp" 2>/dev/null; exit 0; }

PY="${KOKORO_ROOT:-$HOME/.local/share/kokoro}/venv/bin/python"
CHILD="$SELF_DIR/speak-child.py"
if [ ! -x "$PY" ] || [ ! -f "$CHILD" ]; then
  # Kokoro venv missing at $KOKORO_ROOT: exit 0, no notice.  A Stop hook has
  # no displayContent affordance and §1 forbids it touching the screen, so a
  # misconfigured setup is silent in both senses.  CLAUDISH_DEBUG is the only
  # diagnostic.
  dbg "no interpreter at $PY or no child at $CHILD -> silent"
  rm -f "$job" 2>/dev/null
  exit 0
fi

# Non-blocking rests on THIS detachment, not on `async: true` (§6): stdio
# closed, SIGHUP ignored, and the child calls os.setsid() on its first line
# because macOS ships no setsid(1) in the base install.  Nothing below waits
# for the worker, for synthesis, for the wait, or for playback.
dbg "fork mode=$mode hash=$H prose_len=$prose_len wait=$WAIT"
nohup "$PY" "$CHILD" "$job" >/dev/null 2>&1 </dev/null &
exit 0
