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
set -u
SD=$1; MD=$2; TAG=$3; JID=$4; TXT=$5

: > "$MD/$TAG.entry"

: > "$MD/$TAG.K"
found=0
if [[ -d "$SD/playerdir" ]]; then
  for f in "$SD"/playerdir/*; do
    [[ -e "$f" ]] || continue
    b=${f##*/}; pid=${b%%.*}
    [[ -n "$pid" ]] || continue
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
  pid=""
  if [[ -r "$SD/pid" ]]; then read -r pid < "$SD/pid"; fi
  if [[ -n "$pid" ]]; then
    if kill -TERM "$pid" 2>/dev/null; then res=sent; else res=esrch; fi
  else
    res=nopid; pid=none
  fi
  printf '%s\thook\t%s\tkill_attempt\tby=hook via=shared target=%s sig=15 result=%s\n' \
    "$TAG" "$$" "$pid" "$res" >> "$MD/kills.log"
fi

sleep "${HOOK_GAP_S:-0.09}"

tmp="$SD/.job.$$"
{ printf '%s\n' "$JID"; cat "$TXT"; } > "$tmp"
: > "$MD/$TAG.R"
mv -f "$tmp" "$SD/job"
: > "$MD/$TAG.Rdone"
exit 0
