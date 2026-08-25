#!/bin/bash
# Stop probe. Same fork-free bash-side t0 stamp as md.sh (see its header).
#
# The buffer read is bracketed by tread0/tread1, and both buffers are SNAPSHOT
# (copied) inside that bracket before anything is hashed. Hashing a live file
# after the bracket would report a later state than the one the bracket timed,
# which makes a stale read look fresh.
#
# Env: PROBE_DIR (required)
P="${PROBE_DIR:?PROBE_DIR must be set}"
: > "$P/ev/STOP.$$.t0"
payload=$(cat)
: > "$P/ev/STOP.$$.t1"
printf '%s' "$payload" > "$P/pay/STOP.$$.json"
zsh -fc 'zmodload zsh/datetime; : > $1; print -r -- $EPOCHREALTIME' zp \
  "$P/ev/STOP.$$.zsync" > "$P/ev/STOP.$$.zclock" 2>/dev/null

# ---- the read a speak.sh would do, bracketed and snapshotted ----
: > "$P/ev/STOP.$$.tread0"
cp "$P/latest_pre.txt"  "$P/ev/STOP.$$.snap_pre"  2>/dev/null
cp "$P/latest_post.txt" "$P/ev/STOP.$$.snap_post" 2>/dev/null
: > "$P/ev/STOP.$$.tread1"

pre_h=NONE; post_h=NONE; pre_d=""; post_d=""
if [ -f "$P/ev/STOP.$$.snap_pre" ]; then
  pre_h=$(shasum -a 256 "$P/ev/STOP.$$.snap_pre" | awk '{print $1}')
  pre_d=$(head -c 70 "$P/ev/STOP.$$.snap_pre")
fi
if [ -f "$P/ev/STOP.$$.snap_post" ]; then
  post_h=$(shasum -a 256 "$P/ev/STOP.$$.snap_post" | awk '{print $1}')
  post_d=$(head -c 70 "$P/ev/STOP.$$.snap_post")
fi

# Stop's own view of the message, which is the ground truth both for staleness
# and for the section 3.2 match rate. The full value goes to disk so match.sh
# can re-derive the handoff result after the turn has settled.
printf '%s' "$payload" | jq -j '.last_assistant_message // ""' > "$P/ev/STOP.$$.lam" 2>/dev/null
lam=$(printf '%s' "$payload" | jq -r '.last_assistant_message // "NONE"' 2>/dev/null)
{
  printf 'pre  %s\n' "$pre_h"
  printf 'post %s\n' "$post_h"
  printf 'pre_head  %s\n' "$(printf '%s' "$pre_d"  | tr '\n' ' ')"
  printf 'post_head %s\n' "$(printf '%s' "$post_d" | tr '\n' ' ')"
  printf 'stop_lam  %s\n' "$(printf '%s' "$lam" | head -c 70 | tr '\n' ' ')"
} > "$P/ev/STOP.$$.saw"
: > "$P/ev/STOP.$$.t2"
exit 0
