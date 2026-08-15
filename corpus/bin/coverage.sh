#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Invert manifest.tsv: for every hazard class, which items exercise it.
#
# This is the check behind the coverage table in corpus/README.md. A class with
# 0 items is a real gap and should be visible here rather than argued about.
# Classes are read from corpus/classes.tsv, so a class nobody covers still gets
# a row (an inverted index built only from the items could never show a gap).
#
# Usage: coverage.sh [corpus-dir]
# Output: class \t n_real \t n_synthetic \t items
# ---------------------------------------------------------------------------
set -uo pipefail
CORPUS="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
MAN="$CORPUS/manifest.tsv"
CLS="$CORPUS/classes.tsv"

[ -f "$MAN" ] || { printf 'no manifest at %s; run build-manifest.sh first\n' "$MAN" >&2; exit 1; }

gaps=0
while IFS=$'\t' read -r cls _desc; do
  case "$cls" in class|'') continue ;; esac
  # Match the class as a whole comma-separated field, so ID-SNAKE never matches
  # inside some future ID-SNAKE-CASE.
  items="$(awk -F'\t' -v c="$cls" '
    NR > 1 {
      n = split($7, a, ",")
      for (i = 1; i <= n; i++) if (a[i] == c) { printf "%s ", $1 }
    }' "$MAN")"
  items="${items% }"
  nr=0; ns=0
  for it in $items; do
    case "$it" in r*) nr=$((nr + 1)) ;; s*) ns=$((ns + 1)) ;; esac
  done
  [ "$nr" -eq 0 ] && [ "$ns" -eq 0 ] && gaps=$((gaps + 1))
  printf '%s\t%s\t%s\t%s\n' "$cls" "$nr" "$ns" "$items"
done < "$CLS"

printf -- '---\n%s class(es) with no item at all\n' "$gaps" >&2
