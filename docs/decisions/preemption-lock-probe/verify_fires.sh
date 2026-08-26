#!/bin/bash
# Every hook invocation stamps $TAG.entry BEFORE it does anything. A hook that never
# ran is otherwise indistinguishable from one that measured zero, and this project has
# been bitten by exactly that. Expected per configuration with N trials:
#   entry markers = 1 warmup + 2N        K markers = same        Rdone = same
# Any shortfall means a hook did not fire and the configuration must not be read.
#
# CORRECTED in round 5's review. This used to read `$O/RUNS.txt` only, which exists in a
# live run tree and NOT in the committed traces/ directory. Pointed at traces/ it iterated
# over nothing and printed "all hooks fired" -- a null reported as a pass, by the very
# script whose whole job is to stop a null being read as a pass. It now also accepts the
# committed `<cfg>.markers.tsv` files, and it REFUSES to report success over zero inputs.
#
# usage: verify_fires.sh <out_dir_or_traces_dir> <trials>
set -u
O=${1:?out dir}; N=${2:-12}
fail=0
seen=0

check() {   # cfg entry K Rdone
  local cfg=$1 e=$2 k=$3 r=$4 want
  # C14a/C14b fire a third hook per trial to observe the TOCTOU's consequence
  case "$cfg" in C14a_*|C14b_*) want=$((1 + 3 * N)) ;; *) want=$((1 + 2 * N)) ;; esac
  seen=$((seen + 1))
  if [[ "$e" -eq "$want" && "$k" -eq "$want" && "$r" -eq "$want" ]]; then
    printf 'OK    %-28s entry=%s K=%s Rdone=%s\n' "$cfg" "$e" "$k" "$r"
  else
    printf 'SHORT %-28s entry=%s K=%s Rdone=%s  (want %s)\n' "$cfg" "$e" "$k" "$r" "$want"
    fail=1
  fi
}

if [[ -f "$O/RUNS.txt" ]]; then
  while read -r cfg d; do
    [[ -n "${d:-}" ]] || continue
    check "$cfg" \
      "$(ls "$d/markers" 2>/dev/null | grep -c '\.entry$')" \
      "$(ls "$d/markers" 2>/dev/null | grep -c '\.K$')" \
      "$(ls "$d/markers" 2>/dev/null | grep -c '\.Rdone$')"
  done < "$O/RUNS.txt"
else
  for m in "$O"/*.markers.tsv; do
    [[ -f "$m" ]] || continue
    cfg=$(basename "$m" .markers.tsv)
    check "$cfg" \
      "$(awk -F'\t' 'NR>1 && $2=="entry"' "$m" | wc -l | tr -d ' ')" \
      "$(awk -F'\t' 'NR>1 && $2=="K"'     "$m" | wc -l | tr -d ' ')" \
      "$(awk -F'\t' 'NR>1 && $2=="Rdone"' "$m" | wc -l | tr -d ' ')"
  done
fi

if [[ $seen -eq 0 ]]; then
  echo "NO INPUT: $O has neither RUNS.txt nor *.markers.tsv -- this is NOT a pass" >&2
  exit 2
fi
[[ $fail -eq 0 ]] && echo "all hooks fired ($seen configurations)" \
                  || echo "SOME HOOKS DID NOT FIRE -- do not read those configs"
exit $fail
