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
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
O=${1:?out dir}; N=${2:-12}
fail=0
seen=0
SEEN_CFG=()

check() {   # cfg entry K Rdone
  local cfg=$1 e=$2 k=$3 r=$4 want
  # C14a/C14b fire a third hook per trial to observe the TOCTOU's consequence
  case "$cfg" in C14a_*|C14b_*) want=$((1 + 3 * N)) ;; *) want=$((1 + 2 * N)) ;; esac
  seen=$((seen + 1))
  SEEN_CFG+=("$cfg")
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

# DUPLICATES, checked before the manifest and independently of it -- a configuration
# counted twice is a defect whether or not there is anything to compare against.
#
# ROUND 16. This script checked that every expected name APPEARED. It did not check
# that each appeared ONCE, which made it a subset test wearing the name of a
# completeness test. `run_c10.sh`, `run_c16.sh` and `run_tail.sh` all APPEND to
# RUNS.txt (`>> "$OUT/RUNS.txt"`) and only `run_pgid_rerun.sh` filters the old line out
# first -- so re-running one configuration to fix it leaves TWO lines naming it, both
# pointing at run directories that exist. Every name is still present, so this script
# said "all hooks fired"; `assemble.sh` then walked the same RUNS.txt and appended that
# configuration's twelve rows TWICE, and the 312-trial denominator the document quotes
# silently became 324. The guard whose entire job is to stop a miscounted evidence set
# being read as a pass was the one thing that could not see it.
dups=$(printf '%s\n' "${SEEN_CFG[@]}" | sort | uniq -d)
if [[ -n $dups ]]; then
  printf '%s\n' "$dups" | while read -r d; do
    n=$(printf '%s\n' "${SEEN_CFG[@]}" | grep -cxF "$d")
    echo "DUPLICATE: $d appears $n times in $O -- its trials would be counted $n times" >&2
  done
  echo "NOT A PASS: the evidence set is not a set. Each configuration must appear" >&2
  echo "exactly once; a re-run must REPLACE its RUNS.txt line, not append another." >&2
  exit 2
fi

# A PARTIAL evidence set is not a pass either, and this is the second half of the same
# defect: the zero-input guard above was added after this script reported "all hooks
# fired" over nothing at all, but it still greenlit 21 inputs against a document that
# claims 26 configurations. Silence about the five that are absent reads exactly like
# confirmation that they fired. EXPECTED is the manifest; anything missing is a failure.
#
# ROUND 16: and anything PRESENT that the manifest does not name is a failure too. The
# check is now SEEN == EXPECTED exactly -- no subset in either direction. An unexpected
# name is a configuration the document does not report, and `assemble.sh` would publish
# its rows into the same denominator.
EXPECTED=${EXPECTED:-$HERE/expected-configs.txt}
if [[ -f $EXPECTED ]]; then
  manifest=$(grep -vE '^[[:space:]]*(#|$)' "$EXPECTED" | sort -u)
  seenlist=$(printf '%s\n' "${SEEN_CFG[@]}" | sort -u)

  extra=$(comm -23 <(printf '%s\n' "$seenlist") <(printf '%s\n' "$manifest"))
  if [[ -n $extra ]]; then
    printf '%s\n' "$extra" | while read -r x; do
      echo "UNEXPECTED: $x has marker evidence in $O but is not in the manifest" >&2
    done
    echo "NOT A PASS: an unreported configuration would be assembled into the published" >&2
    echo "denominator. Add it to $EXPECTED, or remove its evidence." >&2
    exit 2
  fi

  absent=$(comm -13 <(printf '%s\n' "$seenlist") <(printf '%s\n' "$manifest"))
  missing=0
  if [[ -n $absent ]]; then
    while read -r want; do
      [[ -n $want ]] || continue
      echo "MISSING: $want has no marker evidence in $O" >&2
      missing=$((missing + 1))
    done <<< "$absent"
  fi
  if [[ $missing -gt 0 ]]; then
    echo "INCOMPLETE: $missing of $(grep -cvE '^\s*(#|$)' "$EXPECTED") expected configurations have no evidence -- this is NOT a pass" >&2
    exit 2
  fi
else
  # A warning is not a guard. The whole point of the manifest is that a partial
  # evidence set must not read as a pass, and "the manifest was missing" is the most
  # likely way for it to go partial. Refuse, and make the override explicit.
  echo "NO MANIFEST at $EXPECTED -- completeness cannot be checked, so this is NOT a pass." >&2
  echo "Set ALLOW_NO_MANIFEST=1 to accept an unchecked run deliberately." >&2
  [[ ${ALLOW_NO_MANIFEST:-0} = 1 ]] || exit 2
  echo "WARNING: proceeding without a completeness check because ALLOW_NO_MANIFEST=1" >&2
fi

[[ $fail -eq 0 ]] && echo "all hooks fired ($seen configurations)" \
                  || echo "SOME HOOKS DID NOT FIRE -- do not read those configs"
exit $fail
