#!/bin/bash
# Every published figure, re-derived from the committed TSVs with awk and sort only.
#
# Two things this script gets right that round 1 got wrong, both found in review:
#  * MEDIAN. macOS awk is BWK awk and has no asort(), so percentiles come from a
#    `sort -n` pipeline. Round 1 then took v[int((NR+1)/2)], which is the LOWER
#    MIDDLE observation, not the median. Every sample here is even-sized, so that
#    silently disagreed with the published medians. `med()` below averages the two
#    middle observations.
#  * REAL-AUDIO. Round 1 had no input for the REAL-* traces, so it could not
#    re-derive section 2.6. `real-audio-trials.tsv` is now a committed evidence file
#    and section E summarises it.
#
# Two more added in round 3's review, both because the document quoted a figure this
# script did not print, which is the same defect one level down:
#  * The Rdone->P adversarial margin (section F). It was quoted in the text as the
#    reason the corrected predicate was never close to binding, with no derivation.
#  * The P->W window SPLIT BY WHO PUBLISHED (section C). For a player-published
#    record the probe stamps W in the PARENT immediately after Popen, before the
#    wrapper has slept or renamed, so those samples are not a publication instant at
#    all. They must not be pooled with the worker-published ones -- harness defect 4.
#
# usage: summarise.sh <evidence_dir>
set -u
E=${1:?evidence dir}
P="$E/preemption-trials.tsv"
L="$E/lock-owners.tsv"
R="$E/real-audio-trials.tsv"

# One definition of median, reused by every block below. Reads numbers on stdin.
MED='function med(v, n) { if (n % 2) return v[(n + 1) / 2]; return (v[n / 2] + v[n / 2 + 1]) / 2 }'

stats() {   # label < numbers-on-stdin
  sort -n | awk "$MED"'{v[NR] = $1} END { if (NR) printf "%-28s n=%-4d min=%-11.4f med=%-11.4f max=%.4f\n", L, NR, v[1], med(v, NR), v[NR] }' L="$1"
}

# attribution rule, written once. Darwin signal numbers.
ATTRIB='function attrib(sig, plog, ppid, aud) {
  if (sig=="-15" || plog=="15") return "hook-pid-kill"
  if (sig=="-30" || plog=="30") return "worker-claim-kill"
  if (sig=="-31" || plog=="31") return "election-sweep-record"
  if (sig=="-14" || plog=="14") return "election-sweep-pgid"
  if (sig=="0"   || plog=="0")  return "NOTHING-ran-to-end"
  if (ppid=="-")                return "no-player-spawned"
  # Spawned, never logged a start, no exit status: killed BEFORE it could exec.
  # A player that survived to run always logs player_start, so this is unambiguous.
  if (aud=="0(never_started)")  return "killed-before-exec"
  return "unknown"
}'

echo "== ROW 20 / A: which step killed the player, per configuration =="
awk -F'\t' "$ATTRIB"'
$1=="config"{next}
{ printf "%s\t%s\t%s\n", $1, attrib($14,$17,$13,$18), $26 }' "$P" \
  | sort | uniq -c | awk '{printf "%-4s %-22s %-24s %s\n", $1"x", $2, $3, $4" "$5" "$6" "$7" "$8}'

echo
echo "== ROW 20 / B: was the stale utterance audible, and for how long =="
echo "   audible_s = the stale player's own start-to-end interval. 0(never_started)"
echo "   means the kill landed inside its startup: no audio device was ever opened."
for c in $(awk -F'\t' '$1!="config"{print $1}' "$P" | sort -u); do
  awk -F'\t' -v c="$c" '$1==c {print $18}' "$P" | sort -n \
    | awk "$MED"'
      /^[0-9][0-9.]*$/ { v[++n]=$1+0; next }
      { other[$0]++ }
      END {
        line = sprintf("%-20s ", c)
        if (n) line = line sprintf("n=%-3d min=%.4f med=%.4f max=%.4f  ", n, v[1], med(v, n), v[n])
        for (k in other) line = line sprintf("[%s x%d] ", k, other[k])
        print line
      }' c="$c"
done

echo
echo "== ROW 20 / C: window widths, ms =="
# P->W, three ways. The pooled figure is NOT the one to quote: in a player-published
# arm the probe stamps W in the parent right after Popen (speakd_probe.py, the
# `by=player result=deferred_to_player` branch), so the sample is the Popen return
# rather than the record's publication. Only the worker-published arms measure the
# real window.
awk -F'\t' '$1=="config"{next} $9!="-" && $10!="-" {printf "%.4f\n", ($10-$9)*1000}'  "$P" | stats "P->W_pooled_DO_NOT_QUOTE"
awk -F'\t' '$1=="config"{next} $9!="-" && $10!="-" && $26!="record published by player" {printf "%.4f\n", ($10-$9)*1000}' "$P" | stats "P->W_worker_published"
awk -F'\t' '$1=="config"{next} $9!="-" && $10!="-" && $26=="record published by player" {printf "%.4f\n", ($10-$9)*1000}' "$P" | stats "P->W_player_SYNTHETIC"
awk -F'\t' '$1=="config"{next} $7!="-" && $8!="-"  {printf "%.4f\n", ($8-$7)*1000}'   "$P" | stats "S->S2_claim_to_prespawn"
awk -F'\t' '$1=="config"{next} $4!="-" && $5!="-"  {printf "%.4f\n", ($5-$4)*1000}'   "$P" | stats "K->R_hook_kill_to_rename"
awk -F'\t' '$1=="config"{next} $5!="-" && $6!="-"  {printf "%.4f\n", ($6-$5)*1000}'   "$P" | stats "R->Rdone_rename_itself"
awk -F'\t' '$1=="config"{next} $17=="15" && $20!="-" && $4!="-" {printf "%.4f\n", ($20-$4)*1000}' "$P" | stats "hook_kill->player_death"

echo
echo "== ROW 20 / D: what the hook-side pid kill actually buys, ms =="
echo "   (C2: the player died at the hook kill. Without clause (i) the worker's"
echo "    claim-time kill would have reached it at S_b instead.)"
awk -F'\t' '$1=="C2_hookside" && $25!="-" && $4!="-" {printf "%.4f\n", ($25-$4)*1000}' "$P" | stats "S_b - K_b"

echo
echo "== ROW 20 / E: the real-audio arms =="
echo "   TWO bounds on the stale player's lifetime, not one, and the document quotes the"
echo "   UPPER one. Round 3 published \`alive_s\` as \"Popen -> exit\"; it is not. Its timer"
echo "   starts before subprocess.Popen, so it INCLUDES the fork/exec launch latency, which"
echo "   on the claim-kill arm is MOST of the published figure. The two columns"
echo "   of the same row differ by roughly 7x. Both are printed here so neither can be"
echo "   quoted as the other:"
echo "     timerstart_to_exit_s  upper bound; timer starts before Popen"
echo "     popen_to_exit_s       lower bound; the child was forked inside the Popen this"
echo "                           excludes. Neither is a measure of AUDIBILITY."
if [[ -f "$R" ]]; then
  for a in $(awk -F'\t' 'NR>1{print $1}' "$R" | sort -u); do
    awk -F'\t' -v a="$a" 'NR>1 && $1==a {print $5}' "$R" | stats "$a timerstart_to_exit_s"
    awk -F'\t' -v a="$a" 'NR>1 && $1==a && $8!="-" {print $8}' "$R" | stats "$a popen_to_exit_s"
    awk -F'\t' -v a="$a" 'NR>1 && $1==a && $7!="-" {print $7}' "$R" | stats "$a overlap_s"
    awk -F'\t' -v a="$a" 'NR>1 && $1==a {print $6}' "$R" | sort | uniq -c \
      | awk -v a="$a" '{printf "%-28s killed_by_sig=%-4s x%s\n", a, $2, $1}'
  done
else
  echo "   MISSING: $R"
fi

echo
echo "== ROW 20 / F: the corrected adversarial predicate's own margin, ms =="
echo "   (Rdone_b is stamped AFTER the external mv returns, so publication is"
echo "    demonstrably complete. This is how far it precedes P on the trials the"
echo "    predicate accepts -- the reason the missing check was never close to"
echo "    binding. Quote it per ARM: the two arms differ by ~5 ms of median.)"
awk -F'\t' '$1=="config"{next} $26=="R<S2<R_b<P<W (adversarial)" && $6!="-" && $9!="-" {printf "%.4f\n", ($9-$6)*1000}' "$P" | stats "Rdone_b->P adversarial"

echo
echo "== ROW 21 / A: owner counts per scenario x protocol x N x stall =="
awk -F'\t' 'NR==1{next}{printf "%s\t%s\t%s\t%s\towners=%s\n", $1,$2,$3,$4,$6}' "$L" \
  | sort | uniq -c \
  | awk '{printf "%-5s %-16s %-9s N=%-3s stall=%-6s %s\n", $1"x", $2, $3, $4, $5, $6}'

echo
echo "== ROW 21 / B: per-protocol worst case and duplicate-owner rate =="
# VOID means the STAGING failed, not the protocol. awk would coerce it to 0 and
# score it as a duplicate-owner failure while keeping it in the denominator, so a
# synchronisation problem would read as a protocol problem. Excluded from both, and
# reported on its own line -- a run with any VOID is not a complete run.
awk -F'\t' 'NR==1{next}
$6=="VOID" { void[$2]++; next }
{ n[$2]++; if ($6+0>mx[$2]) mx[$2]=$6+0; if ($6+0!=1) bad[$2]++ }
END{ for (p in n) printf "%s\ttrials=%d\tmax_owners=%d\ttrials_not_exactly_1=%d\trate=%.1f%%%s\n",
       p, n[p], mx[p], bad[p]+0, 100*(bad[p]+0)/n[p],
       (void[p] ? "\tVOID=" void[p] " (staging failed; run is INCOMPLETE)" : "") }' "$L" | sort

echo
echo "== ROW 21 / C: duplicate-owner rate per protocol x scenario =="
awk -F'\t' 'NR==1{next}
$6=="VOID" { k=$2"/"$1; void[k]++; next }
{ k=$2"/"$1; n[k]++; if ($6+0!=1) bad[k]++ }
END{ for (p in n) printf "%s\ttrials=%d\tnot_exactly_1=%d\trate=%.0f%%%s\n", p, n[p], bad[p]+0, 100*(bad[p]+0)/n[p],
       (void[p] ? "\tVOID=" void[p] : "") }' "$L" | sort
