#!/bin/bash
# The crux of the read-then-unlink TOCTOU: at the moment the THIRD hook of a trial
# fires, the trial's second player is still playing. Could that hook reach it?
#
#   C14a  one shared record, unlinked by whichever reap finishes last
#   C14b  one record per player, unlinked only by exact name
#
# For each trial: what hook C found, and whether the player it needed to reach was
# actually alive at that moment.
#
# CORRECTED in review. The earlier version tested only that an END record existed
# for the trial's second player -- `alive = (jb in en) ? 1 : 0` -- which every
# completed player satisfies, so it counted "the player finished at some point"
# as "the player was live at hook C". Its own comment conceded that the marker
# time was not in the file. It is: `markers.tsv` carries `tNc entry`, the moment
# hook C started. The predicate is now the real one, `start <= hook_c < end`, and
# a trial whose player was NOT live at hook C is reported separately rather than
# folded into the denominator.
#
# usage: analyse_c14.sh <traces_dir> [config ...]
set -u
T=${1:?traces dir}
shift
CFGS=${*:-"C14a_shared_unlink C14b_perplayer_unlink"}

# The three inputs are checked before they are read. awk aborts on a file it cannot
# open, so a traces directory missing any of them printed the "=== <config> ===" heading
# and not one line under it, and this script exited 0 -- a crux left underived, reported
# as a run that had nothing to report.
miss=0
for c in $CFGS; do
  echo "=== $c ==="
  absent=0
  for f in "$T/$c.player.log" "$T/$c.markers.tsv" "$T/$c.hook-kills.log"; do
    [[ -f "$f" && -r "$f" ]] && continue
    echo "  MISSING INPUT: $f" >&2
    absent=1; miss=$((miss + 1))
  done
  if [[ $absent -eq 1 ]]; then
    echo "  (inputs missing -- not analysed)"
    continue
  fi
  awk -F'\t' '
    FILENAME ~ /player\.log$/ {
      if ($4=="player_start") { st[$3]=$1+0; pid[$3]=$2 }
      else if ($4=="player_end") { en[$3]=$1+0 }
      next }
    FILENAME ~ /markers\.tsv$/ {
      # tNc entry <ts> -- the instant hook C started. This is the observation the
      # earlier version claimed was unavailable.
      if ($2=="entry" && $1 ~ /^t[0-9]+c$/) { t=$1; sub(/^t/,"",t); sub(/c$/,"",t); HCT[t+0]=$3+0 }
      next }
    FILENAME ~ /hook-kills\.log$/ {
      if ($1 !~ /c$/) next
      n=split($5,f," "); delete V
      for (i=1;i<=n;i++) { split(f[i],kv,"="); V[kv[1]]=kv[2] }
      t=$1; sub(/^t/,"",t); sub(/c$/,"",t)
      HC[t+0]=V["result"]; HT[t+0]=V["target"]
      next }
    END {
      live=0; blind=0; reached=0; notlive=0
      for (i=1;i<=12;i++) {
        jb="j" i "b"
        if (!(jb in st) || !(jb in en) || !(i in HCT)) { notlive++; continue }
        if (!(st[jb] <= HCT[i] && HCT[i] < en[jb]))    { notlive++; continue }
        live++
        if (HC[i] == "nopid" || HC[i] == "norecord") { blind++;
          printf "  trial %-2d hook C found NOTHING while player %s was playing\n", i, pid[jb] }
        else { reached++;
          printf "  trial %-2d hook C reached %-6s (result=%s)\n", i, HT[i], HC[i] }
      }
      printf "  --> %d trials with a live player at hook C: %d unreachable, %d reachable",
             live, blind, reached
      printf "   (%d trials had no live player at hook C and are excluded)\n", notlive
    }' "$T/$c.player.log" "$T/$c.markers.tsv" "$T/$c.hook-kills.log"
done

if [[ $miss -gt 0 ]]; then
  echo "INCOMPLETE: $miss input(s) missing from $T -- at least one configuration above" >&2
  echo "was not analysed at all. This is NOT a pass." >&2
  exit 2
fi
