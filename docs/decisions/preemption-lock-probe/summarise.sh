#!/bin/bash
# Every published figure, re-derived from the committed TSVs with awk and sort only.
# No asort(): macOS awk is BWK awk, which does not have it -- percentiles come from
# `sort -n` in a pipeline instead.
#
# usage: summarise.sh <evidence_dir>
set -u
E=${1:?evidence dir}
P="$E/preemption-trials.tsv"
L="$E/lock-owners.tsv"

# attribution rule, written once: prefer the wait status, fall back to the player's
# own record. 15=SIGTERM=hook pid kill, 30=SIGUSR1=worker claim kill,
# 31=SIGUSR2=newly-elected-worker sweep, 0=ran to completion, nothing killed it.
ATTRIB='function attrib(sig, plog, ppid) {
  if (sig=="-15" || plog=="15") return "hook-pid-kill"
  if (sig=="-30" || plog=="30") return "worker-claim-kill"
  if (sig=="-31" || plog=="31") return "election-sweep"
  if (sig=="0"   || plog=="0")  return "NOTHING-ran-to-end"
  if (ppid=="-")                return "no-player-spawned"
  return "unknown"
}'

echo "== ROW 20 / A: which step killed the player, per configuration =="
awk -F'\t' "$ATTRIB"'
$1=="config"{next}
{ printf "%s\t%s\t%s\n", $1, attrib($13,$16,$12), $25 }' "$P" \
  | sort | uniq -c | awk '{printf "%-4s %-16s %-20s %s\n", $1"x", $2, $3, $4" "$5" "$6" "$7}'

echo
echo "== ROW 20 / B: was the stale utterance audible, and for how long =="
echo "   audible_s = the stale player's own start-to-end interval. 0(never_started)"
echo "   means the kill landed inside its startup: no audio device was ever opened."
for c in $(awk -F'\t' '$1!="config"{print $1}' "$P" | sort -u); do
  awk -F'\t' -v c="$c" '$1==c {print $17}' "$P" | sort -n \
    | awk -v c="$c" '
      /^[0-9][0-9.]*$/ { v[++n]=$1+0; next }
      { other[$0]++ }
      END {
        line = sprintf("%-16s ", c)
        if (n) line = line sprintf("n=%-3d min=%.4f med=%.4f max=%.4f  ", n, v[1], v[int((n+1)/2)], v[n])
        for (k in other) line = line sprintf("[%s x%d] ", k, other[k])
        print line
      }'
done

echo
echo "== ROW 20 / C: window widths, ms =="
for spec in "P->W_pid_write_window 8 9" "S->S2_claim_to_prespawn 6 7" \
            "K->R_hook_kill_to_rename 4 5"; do
  set -- $spec
  name=$1; a=$2; b=$3
  awk -F'\t' -v a="$a" -v b="$b" '$1=="config"{next} $a!="-" && $b!="-" {printf "%.4f\n", ($b-$a)*1000}' "$P" \
    | sort -n | awk -v n="$name" '{v[NR]=$1} END{ if(NR)printf "%-28s n=%-4d min=%-10.4f med=%-10.4f max=%.4f\n", n, NR, v[1], v[int((NR+1)/2)], v[NR] }'
done
# kill latency: from the hook's kill marker to the player's own death record
awk -F'\t' '$1=="config"{next} $16=="15" && $19!="-" && $4!="-" {printf "%.4f\n", ($19-$4)*1000}' "$P" \
  | sort -n | awk '{v[NR]=$1} END{ if(NR)printf "%-28s n=%-4d min=%-10.4f med=%-10.4f max=%.4f\n", "hook_kill->player_death", NR, v[1], v[int((NR+1)/2)], v[NR] }'
# same for the worker's claim-time kill
awk -F'\t' '$1=="config"{next} $16=="30" && $19!="-" && $6!="-" {printf "%.4f\n", ($19-$19)*1000}' "$P" >/dev/null

echo
echo "== ROW 20 / D: what the hook-side pid kill actually buys, ms =="
echo "   (C2: the player died at the hook kill. Without clause (i) the worker's"
echo "    claim-time kill would have reached it at S_b instead. S_b - K_b is the"
echo "    extra stale audio the hook-side kill removes.)"
awk -F'\t' '$1=="config"{next} $1=="C2_hookside" && $24!="-" && $4!="-" {printf "%.4f\n", ($24-$4)*1000}' "$P" \
  | sort -n | awk '{v[NR]=$1} END{ if(NR)printf "%-28s n=%-4d min=%-9.2f med=%-9.2f max=%.2f\n", "S_b - K_b", NR, v[1], v[int((NR+1)/2)], v[NR] }'

echo
echo "== ROW 21 / A: owner counts per scenario x protocol x N x stall =="
awk -F'\t' 'NR==1{next}{printf "%s\t%s\t%s\t%s\towners=%s\n", $1,$2,$3,$4,$6}' "$L" \
  | sort | uniq -c \
  | awk '{printf "%-5s %-16s %-9s N=%-3s stall=%-6s %s\n", $1"x", $2, $3, $4, $5, $6}'

echo
echo "== ROW 21 / B: per-protocol worst case and duplicate-owner rate =="
awk -F'\t' 'NR==1{next}
{ n[$2]++; if ($6+0>mx[$2]) mx[$2]=$6+0; if ($6+0!=1) bad[$2]++ }
END{ for (p in n) printf "%s\ttrials=%d\tmax_owners=%d\ttrials_not_exactly_1=%d\trate=%.1f%%\n",
       p, n[p], mx[p], bad[p]+0, 100*(bad[p]+0)/n[p] }' "$L" | sort

echo
echo "== ROW 21 / C: duplicate-owner rate per protocol x scenario =="
awk -F'\t' 'NR==1{next}
{ k=$2"/"$1; n[k]++; if ($6+0!=1) bad[k]++ }
END{ for (p in n) printf "%s\ttrials=%d\tnot_exactly_1=%d\trate=%.0f%%\n", p, n[p], bad[p]+0, 100*(bad[p]+0)/n[p] }' "$L" | sort
