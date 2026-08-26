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
# CORRECTED AGAIN, ROUND 26: RESTRICTING `reached` TO `sent` MOVED THE DEFECT, IT DID
# NOT REMOVE IT. Round 25 tightened the reached arm to `HC[i] == "sent"` so that
# `esrch` and `record_skipped` rows could no longer be counted as successful reaches.
# But BLIND was the `else`, so those rows landed in the blind arm instead -- and blind
# means "the hook found NO record", which is what neither of them means. A
# `record_skipped` row is the opposite claim: the hook FOUND a record and REFUSED to
# signal it. It carries `verdict=` and no `result=` at all, so the field parsed empty
# and fell through as well. An identity-enabled re-run could therefore have been
# published as a record DESTRUCTION on a trial where the record was intact.
# Blind now requires `nopid` or `norecord` BY NAME. Every other outcome is excluded
# BY NAME and PRINTED, because a row that is in neither denominator and in no line of
# the output is the defect class this rig has spent the most rounds closing. A trial
# carrying MORE THAN ONE hook-C row is excluded for the same reason: the old form kept
# whichever row came last, which is a silent choice between two readings.
# On the committed traces only `nopid` and `sent` occur on a hook-C row, so no
# published figure moves -- C14a 4 unreachable / 8 reachable, C14b 0 / 12, verified
# rather than assumed. It is latent, and `record_skipped` exists only because round 21
# added the identity test, so a re-run is exactly when it would have bitten.
#
# CORRECTED AGAIN, ROUND 34: `-f && -r` IS NOT "THIS FILE HAS ANYTHING IN IT". A ZERO-BYTE
# player log, marker TSV or hook log passes that test. Every trial then falls into the
# `nohook` arm -- 12 of 12 -- the accounting check `tot != 12` is SATISFIED because nohook
# is one of its terms, and the script prints "0 unreachable, 0 reachable" and exits 0. The
# crux the document calls its third derivation would have been reported as derived with not
# one observation behind it, which is the same shape as the missing-input defect the check
# above was written for, one condition further in. The check is now the shared
# `require_nonempty_all` (see require.sh), so the six sites that had this hole have one
# definition between them.
#
# usage: analyse_c14.sh <traces_dir> [config ...]
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ ! -f "$HERE/require.sh" ]]; then
  echo "analyse_c14.sh: missing $HERE/require.sh -- the input-validation rule lives there." >&2
  exit 2
fi
# shellcheck source=require.sh
. "$HERE/require.sh"
if ! declare -F require_nonempty_all >/dev/null; then
  echo "analyse_c14.sh: $HERE/require.sh defined no require_nonempty_all -- the inputs" >&2
  echo "would go unchecked and 12 of 12 trials would classify as nohook and exit 0." >&2
  exit 2
fi
T=${1:?traces dir}
shift
CFGS=${*:-"C14a_shared_unlink C14b_perplayer_unlink"}

# The three inputs are checked before they are read. awk aborts on a file it cannot
# open, so a traces directory missing any of them printed the "=== <config> ===" heading
# and not one line under it, and this script exited 0 -- a crux left underived, reported
# as a run that had nothing to report.
miss=0
bad=0
for c in $CFGS; do
  echo "=== $c ==="
  absent=0
  for f in "$T/$c.player.log" "$T/$c.markers.tsv" "$T/$c.hook-kills.log"; do
    require_nonempty "analyse_c14.sh" "$f" && continue
    absent=1; miss=$((miss + 1))
  done
  if [[ $absent -eq 1 ]]; then
    echo "  (inputs missing or empty -- not analysed)"
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
      if ($1 !~ /^t[0-9]+c$/) next
      n=split($5,f," "); delete V
      for (i=1;i<=n;i++) { split(f[i],kv,"="); V[kv[1]]=kv[2] }
      t=$1; sub(/^t/,"",t); sub(/c$/,"",t); t=t+0
      # THE OUTCOME IS NAMED, AND `result=` IS NOT THE WHOLE VOCABULARY. A
      # `record_skipped` row -- the hook found a record and refused to signal it --
      # carries `verdict=` and no `result=`, so reading only `result` gave it the
      # empty string and the empty string used to mean blind. The name is built from
      # whichever field carries it, so every row classifies as something.
      o=$4
      if (V["result"] != "") o=V["result"]
      else if (V["verdict"] != "") o=$4 ":" V["verdict"]
      NC[t]++
      HC[t]=o; HT[t]=V["target"]
      SEEN[t]=(NC[t]==1 ? o : SEEN[t] "," o)
      next }
    END {
      blind=0; reached=0; notlive=0; nointerval=0; nohook=0; unproven=0
      other=0; multi=0
      for (i=1;i<=12;i++) {
        jb="j" i "b"
        # No hook-C row at all is neither a read nor a kill. The old form let it fall
        # into the reached arm with an empty result -- unreached on this data, and
        # named here rather than left to be rediscovered.
        if (!(i in HC)) { nohook++
          printf "  trial %-2d has NO hook-C row -- NOT counted either way\n", i
          continue }
        # MORE THAN ONE hook-C row is not one read. The perplayer path loops over every
        # record it finds and can emit a row per record, so a re-run can produce two.
        # Keeping the last one silently picks between two readings; the trial is
        # excluded and both outcomes are printed instead.
        if (NC[i] > 1) { multi++
          printf "  trial %-2d has %d hook-C rows (%s) -- one read cannot be chosen\n", i, NC[i], SEEN[i]
          printf "           from them, so the trial is NOT counted either way\n"
          continue }
        if (HC[i] == "sent") {
          # REACHED, and ONLY `sent` may enter here. The premise of this branch is that
          # the kill RETURNED 0, so testing `!= nopid && != norecord` was the wrong
          # predicate: `esrch` is a hook result too, and `record_skipped` rows carry no
          # `result=` at all -- either could satisfy the target and live-at-K checks below
          # and be counted as a successful reach while nothing was signalled. On the
          # committed traces only `nopid` and `sent` occur, so no published figure moves
          # (C14a 8 reached, C14b 12, all genuinely `sent`); it is latent, and
          # `record_skipped` exists only because round 21 added the identity test, so a
          # re-run is exactly when it would have bitten.
          # The kill returned 0, so a process with that pid existed at the
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
        # BLIND, AND ONLY `nopid` OR `norecord` MAY ENTER HERE. Blind means the hook
        # found NO RECORD, and round 25 made this branch the `else` of `sent`, which
        # gave it every other outcome by default: `esrch` (a record was found, its pid
        # was gone) and `record_skipped` (a record was found and DELIBERATELY not
        # signalled) both landed here, and a destruction would then have been published
        # off a trial whose record was intact. Every other outcome is excluded by name,
        # printed, and carried in the summary line -- not dropped from both denominators.
        if (HC[i] != "nopid" && HC[i] != "norecord") { other++
          printf "  trial %-2d hook C outcome is %s, which is neither a reach nor a blind\n", i, HC[i]
          printf "           read (target=%s) -- NOT counted either way\n", (i in HT && HT[i] != "" ? HT[i] : "-")
          continue }
        # The witness is an ABSENCE, so it needs a player live at the instant of
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
      printf "       %d whose reached target was not the b-player live at K,\n", unproven
      printf "       %d neither reached nor blind, %d with more than one hook-C row -- all excluded)\n", other, multi
      # EVERY TRIAL MUST BE SOMEWHERE, and this is checked rather than trusted. 12 is the
      # trial count this block iterates; a sum that misses it means an arm was added
      # without a denominator, which is the silent drop this whole block exists to stop.
      # It exits 2 rather than printing a note, because a derivation that has lost a
      # trial must not be able to report a figure and a zero exit at the same time.
      tot=blind+reached+notlive+nointerval+nohook+unproven+other+multi
      if (tot != 12) {
        printf "  ACCOUNTING ERROR: %d of 12 trials classified -- an outcome is unaccounted\n", tot
        printf "analyse_c14.sh: the classification lost a trial. NOT a pass.\n" > "/dev/stderr"
        exit 2
      }
      # AND THE TOTAL BEING RIGHT IS NOT THE SAME AS THE DERIVATION HAVING HAPPENED, which
      # is round 34s finding here. `nohook` is one of the terms above, so twelve trials that
      # all landed in it sum to twelve and satisfy the accounting -- and this block would
      # print "0 unreachable, 0 reachable" and exit 0 over inputs that contained nothing.
      # The shell now refuses a zero-byte input, which is the cause that was found; this
      # refuses the CONSEQUENCE, for whatever cause. Both denominators empty means the crux
      # this script exists to settle was never put, exactly as lock_overlap.sh treats a run
      # with no two-owner trial.
      if (blind + reached == 0) {
        printf "  NOT DERIVED: no trial was classified as either reached or blind, so the\n"
        printf "  reachability question was never answered for any trial.\n"
        printf "analyse_c14.sh: the two denominators are both empty. An analysis that made no\n" > "/dev/stderr"
        printf "observation is not a derivation, whatever its accounting total says.\n" > "/dev/stderr"
        exit 2
      }
    }' "$T/$c.player.log" "$T/$c.markers.tsv" "$T/$c.hook-kills.log" || bad=$((bad + 1))
done

if [[ $miss -gt 0 ]]; then
  echo "INCOMPLETE: $miss input(s) missing or empty in $T -- at least one configuration" >&2
  echo "above was not analysed at all. This is NOT a pass." >&2
  exit 2
fi
# A configuration whose awk block refused is counted separately from a missing input,
# because the two are different failures and one message for both is how a diagnostic
# stops diagnosing.
if [[ $bad -gt 0 ]]; then
  echo "UNSOUND: $bad configuration(s) failed their own accounting check. This is NOT a pass." >&2
  exit 2
fi
