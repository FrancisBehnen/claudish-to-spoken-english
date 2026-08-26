#!/bin/bash
# Stand-in for speak.sh's Stop-hook body. bash, because the shipped hook is bash.
#
# Does exactly the two things spec 10.6 gives the hook, in the order it gives them:
#   K  read the pid record(s) and kill                   (hook-side kill)
#   R  publish the job by atomic rename onto speak/job   (producer rename)
# and nothing else. The interval between them is the measured hook cost
# (0.063-0.219 s, median 0.086 s [hook]) and is reproduced by HOOK_GAP_S rather than
# by re-running three jq invocations and a shasum.
#
# Two record shapes are supported, because round 2 changes which one is specified:
#   speak/pid            one shared record  (round 1, and --pid-mode shared)
#   speak/playerdir/*    one record per player, named <pid>.<nonce>
# When the directory exists the hook kills every pid in it. A stale entry gives
# ESRCH, which is harmless; the point is that no LIVE player is unreachable.
#
# Timestamps use the fork-free `: > file` marker technique validated by the residency
# run (~90 us granularity, agreed with $EPOCHREALTIME to 47-277 us). $TAG.entry is an
# ENTRY MARKER: a hook that never ran must be distinguishable from one that measured
# zero. $TAG.Rdone is stamped AFTER the rename returns, so it is a conservative upper
# bound on when publication completed -- collect.sh requires it to precede P before
# it will call a trial adversarial.
#
# usage: hook_probe.sh <speak_dir> <marker_dir> <tag> <job_id> <text_file>
#
# Every step below that can fail is now fatal, and the trailing `exit 0` is gone. It
# reported success unconditionally: a hook whose marker directory did not exist stamped
# nothing, a hook whose text file was unreadable published a job with no text, and a
# hook whose rename failed still stamped $TAG.Rdone -- which collect.sh reads as
# "publication demonstrably complete" and uses to classify a trial as adversarial. The
# driver saw 0 either way and ran the next trial. verify_fires.sh catches the missing
# markers afterwards, but only for a run somebody remembers to check, and it cannot
# catch a Rdone that was stamped after a rename that never happened.
#
# ROUND 21 -- THE PID IS NOT AN IDENTITY, AND THE ANCHORED NAME DID NOT MAKE IT ONE.
# Round 20 tightened the record NAME to `<pid>.<8-hex>` so a `.pending` marker could not
# be parsed as a pid. That is a parsing fix. It leaves the pid a number that outlives the
# process which published it -- nothing removes a player record when its player dies, so
# the record stands for the rest of the session (the committed `C12b` warm-up record is
# still in the worker sweep's target list on 24 of its 25 elections) -- and the `kill
# -TERM` below then lands on whatever process holds that number next.
#
# So the record's CONTENT is now the player's own `<pid>.<starttime>` and this hook
# re-reads the pid's current start time before signalling, skipping IN SILENCE on a
# mismatch. Same shape as PR #27 clause 7(i), deliberately; the name is unchanged.
# PLAYER_IDENTITY=off restores the bare-pid behaviour for the falsification arm, and the
# degradation keys on that variable and NEVER on the record's shape -- a record with no
# start time under `on` is UNVERIFIABLE and is refused, because letting the record decide
# whether the check happens is exactly the hole round 16 found on the owner side.
set -u
SD=$1; MD=$2; TAG=$3; JID=$4; TXT=$5
PIDENT=${PLAYER_IDENTITY:-on}

# `ps -o lstart= -p <pid>`, spaces squeezed to `_`. Byte-identical to speakd_probe.py's
# `proc_starttime()` and to the wrapper that writes the record; they are compared as
# strings, so any disagreement fails closed and nothing is ever signalled.
now_starttime() {
  local s
  s=$(/bin/ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' '_') || return 1
  s=${s#_}; s=${s%_}
  [[ -n $s ]] || return 1
  printf '%s' "$s"
}

# Returns the verdict for a pid read from a record whose content is $2.
#   same | recycled | gone | unverifiable
identity_verdict() {
  local pid=$1 rec_st=$2 cur
  if [[ $PIDENT == off ]]; then
    if kill -0 "$pid" 2>/dev/null; then printf same; else printf gone; fi
    return
  fi
  [[ -n $rec_st ]] || { printf unverifiable; return; }
  cur=$(now_starttime "$pid") || { printf gone; return; }
  if [[ $cur == "$rec_st" ]]; then printf same; else printf recycled; fi
}

# The record's content is `<pid>` or `<pid>.<starttime>`. Split on the FIRST dot, as
# every other reader does. The content's pid must equal the one in the NAME -- they are
# written by one act, so a disagreement is a corrupt record, and a hook that trusted the
# name while reading somebody else's start time would verify one process and kill
# another. A mismatch yields no start time, which reads as unverifiable and is refused.
record_starttime() {
  local path=$1 want=$2 line body_pid
  [[ -r $path ]] || return 1
  read -r line < "$path" || return 1
  body_pid=${line%%.*}
  [[ $body_pid == "$want" ]] || return 1
  [[ $line == *.* ]] || return 1
  printf '%s' "${line#*.}"
}

: > "$MD/$TAG.entry" || { echo "hook_probe.sh: cannot stamp $MD/$TAG.entry" >&2; exit 3; }

: > "$MD/$TAG.K" || { echo "hook_probe.sh: cannot stamp $MD/$TAG.K" >&2; exit 3; }
found=0
if [[ -d "$SD/playerdir" ]]; then
  for f in "$SD"/playerdir/*; do
    [[ -e "$f" ]] || continue
    b=${f##*/}
    # STRICT record shape: <pid>.<8 hex nonce>. A `<nonce>.pending` marker whose
    # nonce happens to be all decimal parses as a pid otherwise -- it did, in the
    # committed C17 run (02679968.pending -> 2679968) -- and after pid reuse this
    # `kill` lands on a stranger. The worker-side parser rejects the same shape.
    [[ $b == *.pending ]] && continue
    [[ $b =~ ^[0-9]+\.[0-9a-f]{8}$ ]] || continue
    pid=${b%%.*}
    rec_st=$(record_starttime "$f" "$pid") || rec_st=""
    v=$(identity_verdict "$pid" "$rec_st")
    if [[ $v == recycled || $v == unverifiable ]]; then
      printf '%s\thook\t%s\trecord_skipped\tby=hook via=perplayer target=%s verdict=%s\n' \
        "$TAG" "$$" "$pid" "$v" >> "$MD/kills.log"
      found=1
      continue
    fi
    if kill -TERM "$pid" 2>/dev/null; then res=sent; else res=esrch; fi
    printf '%s\thook\t%s\tkill_attempt\tby=hook via=perplayer target=%s sig=15 result=%s\n' \
      "$TAG" "$$" "$pid" "$res" >> "$MD/kills.log"
    found=1
  done
  if [[ $found -eq 0 ]]; then
    printf '%s\thook\t%s\tkill_attempt\tby=hook via=perplayer target=none sig=15 result=norecord\n' \
      "$TAG" "$$" >> "$MD/kills.log"
  fi
else
  # The shared record has no name to carry a pid, so BOTH fields come from the content:
  # `<pid>` or `<pid>.<starttime>`, split on the first dot exactly as everywhere else.
  # `result=nopid` keeps its meaning -- NO RECORD ON DISK -- and a record that is present
  # but refused is reported as `record_skipped`, never as `nopid`. The C14a derivation
  # reads `nopid` as "the record was destroyed", so conflating the two would manufacture
  # a destruction out of a successful identity check.
  line=""; pid=""; rec_st=""
  if [[ -r "$SD/pid" ]]; then read -r line < "$SD/pid" || line=""; fi
  if [[ -n "$line" ]]; then
    pid=${line%%.*}
    [[ $line == *.* ]] && rec_st=${line#*.}
  fi
  if [[ -n "$pid" ]]; then
    v=$(identity_verdict "$pid" "$rec_st")
    if [[ $v == recycled || $v == unverifiable ]]; then
      printf '%s\thook\t%s\trecord_skipped\tby=hook via=shared target=%s verdict=%s\n' \
        "$TAG" "$$" "$pid" "$v" >> "$MD/kills.log"
      exit_after_skip=1
    else
      if kill -TERM "$pid" 2>/dev/null; then res=sent; else res=esrch; fi
    fi
  else
    res=nopid; pid=none
  fi
  if [[ -z ${exit_after_skip:-} ]]; then
    printf '%s\thook\t%s\tkill_attempt\tby=hook via=shared target=%s sig=15 result=%s\n' \
      "$TAG" "$$" "$pid" "$res" >> "$MD/kills.log"
  fi
fi

sleep "${HOOK_GAP_S:-0.09}"

tmp="$SD/.job.$$"
if ! { printf '%s\n' "$JID"; cat "$TXT"; } > "$tmp"; then
  echo "hook_probe.sh: could not stage the job file from $TXT" >&2
  rm -f "$tmp"
  exit 3
fi
: > "$MD/$TAG.R" || { echo "hook_probe.sh: cannot stamp $MD/$TAG.R" >&2; exit 3; }
# Rdone is stamped ONLY after the rename has actually returned 0. It is the marker
# collect.sh treats as proof that publication completed, so stamping it beside a failed
# mv would manufacture the very ordering the adversarial predicate tests for.
mv -f "$tmp" "$SD/job" || { echo "hook_probe.sh: publish rename to $SD/job failed" >&2; exit 3; }
: > "$MD/$TAG.Rdone" || { echo "hook_probe.sh: cannot stamp $MD/$TAG.Rdone" >&2; exit 3; }
exit 0
