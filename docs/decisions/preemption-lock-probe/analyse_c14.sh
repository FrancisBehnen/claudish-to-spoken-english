#!/bin/bash
# The crux of the read-then-unlink TOCTOU: at the moment the THIRD hook of a trial
# fires, the trial's second player is still playing. Could that hook reach it?
#
#   C14a  one shared record, unlinked by whichever reap finishes last
#   C14b  one record per player, unlinked only by exact name
#
# For each trial: what hook C found, and whether the player it needed to reach was
# alive at that moment (from the player's own start/end records).
# usage: analyse_c14.sh <run_dir_a> <run_dir_b>
set -u
for d in "$@"; do
  echo "=== $(basename "$d") ==="
  awk -F'\t' '
    FILENAME ~ /player\.log$/ {
      if ($4=="player_start") { st[$3]=$1; pid[$3]=$2 }
      else if ($4=="player_end") { en[$3]=$1 }
      next }
    FILENAME ~ /kills\.log$/ {
      if ($1 !~ /c$/) next
      n=split($5,f," "); delete V
      for (i=1;i<=n;i++) { split(f[i],kv,"="); V[kv[1]]=kv[2] }
      t=$1; sub(/^t/,"",t); sub(/c$/,"",t)
      HC[t]=V["result"]; HT[t]=V["target"]
      next }
    END {
      live=0; blind=0; reached=0
      for (i=1;i<=12;i++) {
        jb="j" i "b"
        if (!(jb in st)) continue
        # hook C fires ~1.9 s after hook B returns; the marker time is not in this
        # file, so use the player window itself: if the player ended AFTER the hook
        # could have fired it was alive. Conservatively require an end time.
        alive = (jb in en) ? 1 : 0
        if (!alive) continue
        live++
        if (HC[i] == "nopid" || HC[i] == "norecord") { blind++;
          printf "  trial %-2d hook C found NOTHING while player %s was playing\n", i, pid[jb] }
        else { reached++;
          printf "  trial %-2d hook C reached %-6s (result=%s)\n", i, HT[i], HC[i] }
      }
      printf "  --> %d trials with a live player at hook C: %d unreachable, %d reachable\n",
             live, blind, reached
    }' "$d/player.log" "$d/markers/kills.log"
done
