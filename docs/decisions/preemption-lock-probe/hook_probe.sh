#!/bin/bash
# Stand-in for speak.sh's Stop-hook body. bash, because the shipped hook is bash.
#
# Does exactly the two things spec 10.6 gives the hook, in the order it gives them:
#   K  read $BUF_ROOT/<sid>/speak/pid and kill it        (hook-side pid kill)
#   R  publish the job by atomic rename onto speak/job   (producer rename)
# and nothing else. The interval between them is the measured hook cost
# (0.063-0.219 s, median 0.086 s [hook]) and is reproduced by HOOK_GAP_S rather
# than by re-running three jq invocations and a shasum.
#
# Timestamps use the fork-free `: > file` marker technique validated by the
# residency run (~90 us granularity, agreed with $EPOCHREALTIME to 47-277 us).
# $TAG.entry is an ENTRY MARKER: a hook that never ran must be distinguishable
# from one that measured zero.
#
# usage: hook_probe.sh <speak_dir> <marker_dir> <tag> <job_id> <text_file>
set -u
SD=$1; MD=$2; TAG=$3; JID=$4; TXT=$5

: > "$MD/$TAG.entry"

: > "$MD/$TAG.K"
pid=""
if [[ -r "$SD/pid" ]]; then read -r pid < "$SD/pid"; fi
if [[ -n "$pid" ]]; then
  if kill -TERM "$pid" 2>/dev/null; then res=sent; else res=esrch; fi
else
  res=nopid; pid=none
fi
printf '%s\thook\t%s\tkill_attempt\tby=hook target=%s sig=15 result=%s\n' \
  "$TAG" "$$" "$pid" "$res" >> "$MD/kills.log"

sleep "${HOOK_GAP_S:-0.09}"

tmp="$SD/.job.$$"
{ printf '%s\n' "$JID"; cat "$TXT"; } > "$tmp"
: > "$MD/$TAG.R"
mv -f "$tmp" "$SD/job"
: > "$MD/$TAG.Rdone"
exit 0
