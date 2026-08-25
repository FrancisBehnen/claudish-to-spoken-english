#!/bin/bash
# Re-derive the section 3.2 handoff result for the turn just captured: does
# Stop's .last_assistant_message equal rewrite.sh's delta concatenation?
#
# Run AFTER the turn has settled, so the display hook has certainly published.
# This comparison is therefore INDEPENDENT of the timing race measured by
# collect.sh -- it answers "do the two strings agree", not "does Stop see them".
#
# Two verdicts are reported:
#   raw        byte-for-byte, the delta concatenation exactly as streamed
#   assembled  with trailing newlines stripped, which is what rewrite.sh:135's
#              full="$(cat "$d"/*.part)" command substitution actually produces
P="${PROBE_DIR:?PROBE_DIR must be set}"
tag="${1:-run}"
cd "$P/ev" || exit 1
lamf=$(ls STOP.*.lam 2>/dev/null | head -1)
if [ -z "$lamf" ] || [ ! -f "$P/latest_pre.txt" ]; then
  printf '%s\tNO_DATA\n' "$tag"; exit 0
fi
concat="$P/latest_pre.txt"
h_raw=$(shasum -a 256 "$concat" | awk '{print $1}')
h_lam=$(shasum -a 256 "$lamf"   | awk '{print $1}')
sa=$(printf '%s' "$(cat "$concat")" | shasum -a 256 | awk '{print $1}')
sb=$(printf '%s' "$(cat "$lamf")"   | shasum -a 256 | awk '{print $1}')
n_c=$(wc -c < "$concat" | tr -d ' ')
n_l=$(wc -c < "$lamf"   | tr -d ' ')
vr=MISMATCH; [ "$h_raw" = "$h_lam" ] && vr=exact
va=MISMATCH; [ "$sa" = "$sb" ] && va=exact
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$tag" "$n_c" "$n_l" "$vr" "$va" \
  "$(echo "$h_raw" | cut -c1-12)" "$(echo "$h_lam" | cut -c1-12)"
