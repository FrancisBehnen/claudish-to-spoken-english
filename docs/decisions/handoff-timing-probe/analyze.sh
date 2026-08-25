#!/bin/bash
# Print one ordered timeline for the turn currently in $PROBE_DIR/ev, plus the
# chunk metadata, what Stop saw, and the zsh-vs-mtime clock cross-check.
# Every marker mtime comes from the same kernel clock, so the ordering is exact.
P="${PROBE_DIR:?PROBE_DIR must be set}"
cd "$P/ev" || exit 1
stat -f '%Fm %N' * 2>/dev/null | sort -n > "$P/timeline.raw"

base=$(head -1 "$P/timeline.raw" | awk '{print $1}')
echo "base_epoch=$base"
echo
printf '%12s  %s\n' "rel_ms" "marker"
awk -v b="$base" '{ printf "%12.3f  %s\n", ($1-b)*1000, $2 }' "$P/timeline.raw"

echo
echo "=== MD chunk metadata (pid -> idx/final) ==="
for f in *.meta; do
  [ -f "$f" ] || continue
  printf '%s  %s\n' "$(echo "$f" | cut -d. -f2)" "$(cat "$f")"
done | sort

echo
echo "=== what Stop saw in the buffer ==="
for f in *.saw; do
  [ -f "$f" ] || continue
  echo "--- $f"
  cat "$f"
done

echo
echo "=== zsh EPOCHREALTIME vs mtime clock (cross-validation) ==="
for f in *.zclock; do
  [ -f "$f" ] || continue
  stem=${f%.zclock}
  z=$(cat "$f" 2>/dev/null)
  m=$(stat -f '%Fm' "$stem.zsync" 2>/dev/null)
  if [ -n "$z" ] && [ -n "$m" ]; then
    awk -v z="$z" -v m="$m" -v s="$stem" 'BEGIN{
      printf "%s  zsh=%.6f mtime=%.6f delta_us=%+.1f\n", s, z, m, (m-z)*1000000 }'
  else
    echo "$stem  MISSING z=[$z] m=[$m]  <- zsh/datetime probably not loaded"
  fi
done
