#!/bin/bash
# Create the probe directory and the throwaway settings file, and print the
# exact command to launch the probe session.
#
# THIS NEVER TOUCHES ~/.claude/settings.json. The probe hooks live only in the
# throwaway file this writes, which is handed to ONE session via --settings, so
# no other session on the machine ever sees them.
#
# usage: PROBE_DIR=/tmp/handoff-probe ./setup.sh
set -u
P="${PROBE_DIR:?PROBE_DIR must be set, e.g. PROBE_DIR=/tmp/handoff-probe}"
KIT="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$P/ev" "$P/pay" "$P/buf" "$P/keep" "$P/work"
echo 0 > "$P/sleep_md"

cat > "$P/settings.json" <<EOF
{
  "hooks": {
    "MessageDisplay": [
      { "hooks": [ { "type": "command", "command": "$KIT/md.sh",   "timeout": 60 } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "$KIT/stop.sh", "timeout": 60 } ] }
    ]
  }
}
EOF

chmod +x "$KIT"/*.sh

echo "probe dir:      $P"
echo "settings file:  $P/settings.json"
echo
echo "sha256 of ~/.claude/settings.json (record before AND after):"
shasum -a 256 "$HOME/.claude/settings.json"
echo
echo "Launch the probe session with PROBE_DIR exported, because the hooks read it:"
echo
echo "  cd '$P/work'"
echo "  CLAUDISH_ENABLED=0 PROBE_DIR='$P' \\"
echo "    claude --settings '$P/settings.json' --model haiku"
echo
echo "CLAUDISH_ENABLED=0 matters: this plugin installs a user-scope"
echo "MessageDisplay hook (rewrite.sh). Left enabled it fires in the probe"
echo "session too, calls an LLM, and pollutes every interval measured here."
echo
echo "Then, per turn:  PROBE_DIR='$P' $KIT/run.sh <tag> <hold_s> '<prompt>'"
echo "And to tabulate: PROBE_DIR='$P' $KIT/collect.sh"
echo "                 PROBE_DIR='$P' $KIT/latency.sh"
