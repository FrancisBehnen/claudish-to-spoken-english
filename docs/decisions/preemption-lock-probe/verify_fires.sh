#!/bin/bash
# Every hook invocation stamps $TAG.entry BEFORE it does anything. A hook that never
# ran is otherwise indistinguishable from one that measured zero, and this project has
# been bitten by exactly that. Expected per configuration with N trials:
#   entry markers = 1 warmup + 2N        K markers = same        Rdone = same
# Any shortfall means a hook did not fire and the configuration must not be read.
#
# usage: verify_fires.sh <out_dir> <trials>
set -u
O=${1:?out dir}; N=${2:-12}
fail=0
while read -r cfg d; do
  [[ -n "${d:-}" ]] || continue
  # C14a/C14b fire a third hook per trial to observe the TOCTOU's consequence
  case "$cfg" in C14a_*|C14b_*) want=$((1 + 3 * N)) ;; *) want=$((1 + 2 * N)) ;; esac
  e=$(ls "$d/markers" 2>/dev/null | grep -c '\.entry$')
  k=$(ls "$d/markers" 2>/dev/null | grep -c '\.K$')
  r=$(ls "$d/markers" 2>/dev/null | grep -c '\.Rdone$')
  if [[ "$e" -eq "$want" && "$k" -eq "$want" && "$r" -eq "$want" ]]; then
    printf 'OK    %-28s entry=%s K=%s Rdone=%s\n' "$cfg" "$e" "$k" "$r"
  else
    printf 'SHORT %-28s entry=%s K=%s Rdone=%s  (want %s)\n' "$cfg" "$e" "$k" "$r" "$want"
    fail=1
  fi
done < "$O/RUNS.txt"
[[ $fail -eq 0 ]] && echo "all hooks fired" || echo "SOME HOOKS DID NOT FIRE -- do not read those configs"
exit $fail
