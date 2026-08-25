#!/bin/bash
# run.sh <tag> <hold_seconds> <prompt>
#
# Drive one turn through the probe session and capture it.
#
# Clears only ev/ and pay/. latest_pre.txt and latest_post.txt deliberately
# SURVIVE between turns -- that is what makes the stale-buffer hazard directly
# observable: if Stop reads before the display hook publishes, it reads the
# PREVIOUS turn's text, and the capture shows exactly that.
#
# Requires: PROBE_DIR set; a live probe session reachable as the Herdr agent
# named by PROBE_AGENT (default "hookprobe"). Substitute your own driver here if
# you are not using Herdr -- nothing else in the kit depends on it.
P="${PROBE_DIR:?PROBE_DIR must be set}"
AGENT="${PROBE_AGENT:-hookprobe}"
KIT="$(cd "$(dirname "$0")" && pwd)"
tag="$1"; hold="$2"; prompt="$3"

rm -f "$P"/ev/* "$P"/pay/*
echo "$hold" > "$P/sleep_md"

herdr agent prompt "$AGENT" "$prompt" --wait --timeout 300000 >/dev/null 2>&1

# Must exceed the hold, or the display hook's return marker has not landed yet
# and every interval measured against it is garbage.
sleep $((hold + 4))

mkdir -p "$P/keep/$tag"
cp -p "$P"/ev/* "$P/keep/$tag/" 2>/dev/null    # -p or the mtimes are destroyed
"$KIT/analyze.sh" > "$P/keep/$tag/analysis.txt" 2>&1
"$KIT/match.sh" "$tag" | tee -a "$P/match.tsv"
