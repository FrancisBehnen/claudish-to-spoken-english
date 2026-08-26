#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Stop hook: speak the turn's plain-English rewrite aloud.  COLD PATH.
#
# This is the hook half of docs/decisions/speech-integration-spec.md.  It does
# the ordered steps of §10.3, drops a job, forks a DETACHED speaker, and exits
# 0.  It never waits for synthesis, playback, or the rewrite.
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
#     below is a best-effort barge-in instead; see its comment.
#   * §3.5.1's bounded wait lives in the DETACHED CHILD, never here, because
#     there is no worker to put it in.  §6's non-blocking guarantee is the
#     reason it cannot live in this process.
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
#   CLAUDISH_ENABLED, CLAUDISH_OFF_FILE, CLAUDISH_MIN_CHARS, CLAUDISH_TIMEOUT
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
# can be the whole bounded wait (50 s at the defaults) older than the sound.
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

# ---- step 6: PREEMPTION, before any content-based exit -------------------
# §10.3's ordering is load-bearing and it is kept: a newer turn that is
# deliberately silent (a running background task, a disqualifying hazard, a
# deadline that will pass) must still cut the previous turn's audio, because
# nothing else will.  Every path below this line has executed this step.
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

# ---- step 10: classify via §3.5's decision table ------------------------
# prose_len by rewrite.sh:139-142's own formula (strip fenced blocks, delete
# whitespace, wc -c), so the two hooks agree about the threshold without
# coordinating.  It is 200 BYTES of non-whitespace, not 200 characters.
MIN_CHARS="${CLAUDISH_MIN_CHARS:-200}"
case "$MIN_CHARS" in ''|*[!0-9]*) MIN_CHARS=200 ;; esac
prose_len="$(awk 'BEGIN{f=0} /^```/{f=!f; next} f==0{print}' "$msg" 2>/dev/null \
  | tr -d '[:space:]' | wc -c | tr -d ' ')"
case "$prose_len" in ''|*[!0-9]*) prose_len=0 ;; esac

# H = sha256( trim( last_assistant_message ) ), from speak-key.sh -- the ONE
# definition of the handoff key, sourced by this hook and by rewrite.sh's
# publish so the two cannot drift.  Getting this identical on both sides is the
# single thing that decides whether the user hears this turn's rewrite or
# nothing at all.  Sourced AFTER step 6, so a missing file still preempts.
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
mode=""
if [ -f "$SPEAK_DIR/rw.$H" ]; then
  mode="buffered"
elif [ "$prose_len" -lt "$MIN_CHARS" ]; then
  # §3.3: below the threshold rewrite.sh publishes NOTHING, ever, so waiting
  # here could only wait for something that will not come.  Speak the raw text
  # -- sanitized -- unless it carries one of §3.4's eight disqualifying hazard
  # classes.  The eight expressions are lifted VERBATIM from
  # corpus/bin/detect-hazards.sh (:42 :47-52 :93 :71 :72 :73 :74 :94) so the
  # runtime gate and the checked reference cannot drift.  Eight greps, no
  # pipeline whose status can escape, and detect-hazards.sh itself is NEVER
  # shelled out to: it takes file arguments, spawns ~60 greps, and sets
  # `set -uo pipefail`, which is forbidden here.
  haz=""
  grep -q '```' "$msg" 2>/dev/null && haz="MD-FENCE"
  # MD-FENCE-MULTI is a strict subset of MD-FENCE, so it can add nothing; it is
  # written out anyway because §3.4 names it as one of the eight.
  if [ -z "$haz" ]; then
    awk '
      /^[ \t]*```/ { if (inb) { if (n >= 2) found = 1; inb = 0; n = 0 }
                     else { inb = 1; n = 0 } ; next }
      inb && NF > 0 { n++ }
      END { exit(found ? 0 : 1) }
    ' "$msg" 2>/dev/null && haz="MD-FENCE-MULTI"
  fi
  [ -z "$haz" ] && grep -qE 'https?://'                       "$msg" 2>/dev/null && haz="URL"
  [ -z "$haz" ] && grep -qE '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' "$msg" 2>/dev/null && haz="PATH-SLASH"
  [ -z "$haz" ] && grep -qE '(^| )/[A-Za-z]'                  "$msg" 2>/dev/null && haz="PATH-ABS"
  [ -z "$haz" ] && grep -qE '~/'                              "$msg" 2>/dev/null && haz="PATH-TILDE"
  [ -z "$haz" ] && grep -qE '(^| )\.[A-Za-z][A-Za-z0-9_-]*/'  "$msg" 2>/dev/null && haz="PATH-DOTDIR"
  [ -z "$haz" ] && grep -qE '[✅⚠️💬✦]'                         "$msg" 2>/dev/null && haz="EMOJI"
  if [ -n "$haz" ]; then
    dbg "raw path disqualified by $haz -> silent"
    rm -f "$msg" 2>/dev/null
    exit 0
  fi
  mode="raw"
else
  # Above the threshold with no publish yet: this is the common case, not the
  # exception.  Stop is dispatched a median 6.7 ms BEFORE the final
  # MessageDisplay chunk and the buffer was stale 29 of 30 times, so a hook
  # that gave up here would be silent on nearly every turn.  The child waits.
  mode="buffered"
fi

dbg "classify mode=$mode prose_len=$prose_len hash=$H"

# ---- step 11: dedup -- NOT here.  §3.5.1 clause 6 puts it in the child, ---
# at the moment text goes to synthesis, because on the waiting row the
# resolved text is not known in this process.  Nothing here reads or writes
# speak/spoken.

# ---- step 12: install the job by rename, fork detached, exit 0 -----------
# The wait deadline is DERIVED, not a new knob (§10.1, §3.5.1 clause 3):
#   min( CLAUDISH_TIMEOUT + 2, MD_TIMEOUT ) + 3   ==  50 s at the defaults
# MD_TIMEOUT is hooks/hooks.json's declared MessageDisplay timeout: a rewrite
# the harness stops at 60 s publishes nothing at all, so raising
# CLAUDISH_TIMEOUT past 58 buys the wait nothing.  Read from the SAME env var
# rewrite.sh:65 reads, so both hooks see the same frozen number.
LLM_TIMEOUT="${CLAUDISH_TIMEOUT:-45}"
case "$LLM_TIMEOUT" in ''|*[!0-9]*) LLM_TIMEOUT=45 ;; esac
MD_TIMEOUT=60
WAIT=$((LLM_TIMEOUT + 2))
[ "$WAIT" -gt "$MD_TIMEOUT" ] && WAIT="$MD_TIMEOUT"
WAIT=$((WAIT + 3))
[ "$mode" = "raw" ] && WAIT=0

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
