#!/bin/bash
# MessageDisplay probe for the Stop/MessageDisplay ordering measurement.
#
# Emits nothing on stdout, so the display is untouched and the hook is
# fail-open by construction.
#
# TIMEKEEPING. The first statement is a bare bash builtin redirection. It forks
# nothing, so the kernel stamps the marker file's mtime -- nanosecond resolution
# on APFS -- at the open() syscall, before this process has done anything else.
# Every timestamp in this kit is a file mtime read back later with
# `stat -f '%Fm'`, which means all markers from all hook processes share one
# clock and are directly comparable. This is a bash-side clock: bash 3.2 has no
# in-process hi-res clock, and shelling out to `date` would charge a fork to the
# measurement. A zsh cross-check is taken below to validate the mtime clock
# against zsh's $EPOCHREALTIME.
#
# NOTE: `zsh -f` does NOT autoload zsh/datetime, so $EPOCHREALTIME is EMPTY
# unless zmodload runs first. A probe that reads it bare measures nothing.
#
# Env:
#   PROBE_DIR      where markers, payloads and buffers go (required)
#   PROBE_SLEEP_F  file holding the seconds to hold the final branch open
#                  (default "$PROBE_DIR/sleep_md"); 0 disables
P="${PROBE_DIR:?PROBE_DIR must be set}"
: > "$P/ev/MD.$$.t0"
payload=$(cat)
: > "$P/ev/MD.$$.t1"
printf '%s' "$payload" > "$P/pay/MD.$$.json"
zsh -fc 'zmodload zsh/datetime; : > $1; print -r -- $EPOCHREALTIME' zp \
  "$P/ev/MD.$$.zsync" > "$P/ev/MD.$$.zclock" 2>/dev/null
mid=$(printf '%s' "$payload" | jq -r '.message_id // "NOMID"' 2>/dev/null)
idx=$(printf '%s' "$payload" | jq -r '(.index // 0)|tostring' 2>/dev/null)
fin=$(printf '%s' "$payload" | jq -r '(.final // false)|tostring' 2>/dev/null)
printf 'mid=%s idx=%s final=%s\n' "$mid" "$idx" "$fin" > "$P/ev/MD.$$.meta"

# Buffer this chunk's delta byte-exactly, as rewrite.sh:124 does. jq -j adds no
# trailing newline, so the concatenation of the .part files is the message.
printf '%s' "$payload" | jq -j '.delta // ""' >> "$P/buf/$mid.txt" 2>/dev/null

if [ "$fin" = "true" ]; then
  # Variant A -- publish the assembled text IMMEDIATELY on the final chunk,
  # before any slow work. This is the best case for a display hook that wants
  # to beat Stop's read.
  cp "$P/buf/$mid.txt" "$P/latest_pre.txt" 2>/dev/null
  : > "$P/ev/MD.$$.tpre"

  s=$(cat "${PROBE_SLEEP_F:-$P/sleep_md}" 2>/dev/null || echo 0)
  if [ "$s" != "0" ]; then sleep "$s"; fi
  : > "$P/ev/MD.$$.tslept"

  # Variant B -- publish AFTER the slow work. This is what rewrite.sh actually
  # does: it publishes once the LLM rewrite is in hand.
  cp "$P/buf/$mid.txt" "$P/latest_post.txt" 2>/dev/null
  : > "$P/ev/MD.$$.tpost"
fi
: > "$P/ev/MD.$$.t2"
exit 0
