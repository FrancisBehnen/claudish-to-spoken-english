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
# hook C started. The predicate became `start <= hook_c < end`, and a trial whose
# player was NOT live at hook C is reported separately rather than folded into
# the denominator.
#
# CORRECTED AGAIN, ROUND 24: `entry` IS THE WRONG INSTANT, AND THE TWO KINDS OF
# TRIAL NEED DIFFERENT EVIDENCE. `entry` is stamped as the hook's first act. The
# `nopid` observation happens LATER -- after the `K` marker, then the record scan.
# A player that exited in between satisfied `start <= entry < end` and was still
# counted as live at an observation it was not alive for, so the block could report
# a destruction, or "found NOTHING while playing", with no player live at the scan.
#
# The scan is bounded on both sides by committed markers: it runs strictly after
# `K` (stamped immediately before it) and strictly before `R` (stamped after the
# HOOK_GAP_S sleep that follows it). Its exact instant is unobserved, so proving
# the player was live AT it means proving it was live ACROSS the whole interval:
#   BLIND rows (`nopid`/`norecord`) require  start <= K  AND  end > R.
# `R` is a loose upper bound -- it includes the ~90 ms hook sleep -- and loose is
# the safe direction for a witness whose content is an ABSENCE.
#
# REACHED rows (`sent`) get NO across-the-scan check, and that is not an exemption.
# The hook's kill is what ENDS the player, so a reached player CANNOT outlive `R`:
# requiring it to would discard every reached trial (measured here: the player exits
# 0.6-2.0 ms after `K`, i.e. ~113-141 ms BEFORE `R`). For these rows the signal is
# the evidence, and it is checked as such rather than asserted: the record's target
# must BE the trial's b-player, and that player must have been live at `K`.
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
      # The SCAN INTERVAL, not the entry instant. K is stamped immediately before the
      # record scan and R after the sleep that follows it, so the scan lies strictly
      # inside (K, R) and a player live at both ends was live throughout it.
      if ($1 !~ /^t[0-9]+c$/) next
      t=$1; sub(/^t/,"",t); sub(/c$/,"",t); t=t+0
      if ($2=="K")      K[t]=$3+0
      else if ($2=="R") R[t]=$3+0
      next }
    FILENAME ~ /hook-kills\.log$/ {
      if ($1 !~ /c$/) next
      n=split($5,f," "); delete V
      for (i=1;i<=n;i++) { split(f[i],kv,"="); V[kv[1]]=kv[2] }
      t=$1; sub(/^t/,"",t); sub(/c$/,"",t)
      HC[t+0]=V["result"]; HT[t+0]=V["target"]
      next }
    END {
      blind=0; reached=0; notlive=0; nointerval=0; nohook=0; unproven=0
      for (i=1;i<=12;i++) {
        jb="j" i "b"
        # No hook-C row at all is neither a read nor a kill. The old form let it fall
        # into the reached arm with an empty result -- unreached on this data, and
        # named here rather than left to be rediscovered.
        if (!(i in HC)) { nohook++
          printf "  trial %-2d has NO hook-C row -- NOT counted either way\n", i
          continue }
        if (HC[i] != "nopid" && HC[i] != "norecord") {
          # REACHED. The kill returned 0, so a process with that pid existed at the
          # scan. Checked, not assumed: the target must BE the b-player of this very
          # trial, and that player must have been live at K. No across-the-scan check --
          # the kill is what ends it, so it cannot outlive R.
          if (!(jb in st) || !(jb in en) || !(i in K)) { nointerval++
            printf "  trial %-2d hook C reached %-6s but its own timing is not in the\n", i, HT[i]
            printf "           traces -- NOT counted either way\n"
            continue }
          if (HT[i] != pid[jb] || !(st[jb] <= K[i] && K[i] <= en[jb])) { unproven++
            printf "  trial %-2d hook C reached %-6s, which is not the b-player of this\n", i, HT[i]
            printf "           trial (%s) live at K -- NOT counted either way\n", pid[jb]
            continue }
          reached++
          printf "  trial %-2d hook C reached %-6s (result=%s; died %.1f ms after K,\n", i, HT[i], HC[i], (en[jb]-K[i])*1000
          printf "           %.1f ms before R)\n", (R[i]-en[jb])*1000
          continue }
        # BLIND. The witness is an ABSENCE, so it needs a player live at the instant of
        # the scan -- which is unobserved, so it needs one live ACROSS (K, R).
        if (!(jb in st) || !(jb in en) || !(i in K) || !(i in R)) { nointerval++
          printf "  trial %-2d hook C read nothing, but the scan interval is not in the\n", i
          printf "           traces -- NOT counted either way\n"
          continue }
        if (!(st[jb] <= K[i] && en[jb] > R[i])) { notlive++
          printf "  trial %-2d hook C read nothing, but player %s was not live ACROSS the\n", i, pid[jb]
          printf "           scan (start..end vs K..R) -- NOT a destruction\n"
          continue }
        blind++
        printf "  trial %-2d hook C found NOTHING while player %s was playing across the\n", i, pid[jb]
        printf "           whole scan (live %.1f ms before K, still live %.1f ms after R)\n", (K[i]-st[jb])*1000, (en[jb]-R[i])*1000
      }
      printf "  --> %d trials whose hook-C read is JOINED to the trial%ss own b-player:", blind+reached, "\047"
      printf " %d unreachable, %d reachable\n", blind, reached
      printf "      (%d not live across the scan, %d missing the interval, %d with no hook row,\n", notlive, nointerval, nohook
      printf "       %d whose reached target was not the b-player live at K -- all excluded)\n", unproven
    }' "$T/$c.player.log" "$T/$c.markers.tsv" "$T/$c.hook-kills.log"
done

if [[ $miss -gt 0 ]]; then
  echo "INCOMPLETE: $miss input(s) missing from $T -- at least one configuration above" >&2
  echo "was not analysed at all. This is NOT a pass." >&2
  exit 2
fi
