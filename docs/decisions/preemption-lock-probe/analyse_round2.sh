#!/bin/bash
# Round-2 protocol facts, each extracted from a committed worker.trace with awk only.
# These are the claims the round-1 document could not make because it had no arm for
# them, plus the two defects review found in the round-1 repair.
#
# usage: analyse_round2.sh <traces_dir>
set -u
T=${1:?traces dir}

hdr() { printf '\n== %s ==\n' "$1"; }

hdr "C13a: did the ledger truncate ERASE a live player's entry?"
echo "   (an entry appended between the sweep's read and its truncate is wiped"
echo "    without ever having been signalled -- review comment on speakd_probe.py:167)"
awk -F'\t' '
  { n=split($6,f," "); delete V; for(i=1;i<=n;i++){split(f[i],kv,"="); V[kv[1]]=kv[2]} }
  $5=="election_sweep_record" { printf "  sweep read pids=%s swept=%s\n", V["pids"], V["swept"] }
  $5=="ledger_truncated" { printf "  truncate held=%-12s ERASED=%s\n", V["held_at_truncate"], V["erased"] }
' "$T/C13a_ledger_truncate.worker.trace" 2>/dev/null | head -20 || echo "  (trace missing)"

hdr "C13b: same timing, per-player records -- nothing to truncate"
awk -F'\t' '
  { n=split($6,f," "); delete V; for(i=1;i<=n;i++){split(f[i],kv,"="); V[kv[1]]=kv[2]} }
  $5=="ledger_truncated" { t++ }
  $5=="election_sweep_pgid" { g++ }
  END { printf "  ledger_truncated events=%d   pgid sweeps=%d\n", t+0, g+0 }
' "$T/C13b_perplayer_sametiming.worker.trace" 2>/dev/null || echo "  (trace missing)"

hdr "C14a: did an OLDER player's reap unlink a NEWER player's record?"
echo "   (read-then-unlink TOCTOU -- review comment on the doc at :573)"
awk -F'\t' '
  { n=split($6,f," "); delete V; for(i=1;i<=n;i++){split(f[i],kv,"="); V[kv[1]]=kv[2]} }
  $5=="W_pid_write" { lastpub=V["player_pid"]; lastpub_t=$1 }
  $5=="record_unlinked" {
      if (lastpub != "" && V["player_pid"] != lastpub && $1 > lastpub_t) {
        bad++
        printf "  t=%.6f  reap of %-6s unlinked %-4s -- newer player %s had published at %.6f\n",
               $1, V["player_pid"], V["path"], lastpub, lastpub_t
      } }
  END { printf "  --> %d unlinks destroyed a newer player%s record\n", bad+0, "'"'"'s" }
' "$T/C14a_shared_unlink.worker.trace" 2>/dev/null || echo "  (trace missing)"
echo "   and the consequence, from the hook side:"
awk -F'\t' '$5=="kill_attempt" { n=split($5,x,""); }
  { if ($0 ~ /result=nopid/) nopid++ ; if ($0 ~ /result=sent/) sent++ }
  END { printf "  hook reads: nopid=%d  sent=%d\n", nopid+0, sent+0 }' \
  "$T/C14a_shared_unlink.hook-kills.log" 2>/dev/null || echo "  (log missing)"

hdr "C14b: per-player records -- an unlink can only remove its own name"
awk -F'\t' '
  { n=split($6,f," "); delete V; for(i=1;i<=n;i++){split(f[i],kv,"="); V[kv[1]]=kv[2]} }
  $5=="record_unlinked" { if (V["path"] ~ ("^" V["player_pid"] "\\.")) own++; else other++ }
  END { printf "  unlinks of own record=%d   of another player%s record=%d\n", own+0, "'"'"'s", other+0 }
' "$T/C14b_perplayer_unlink.worker.trace" 2>/dev/null || echo "  (trace missing)"
echo "   and the consequence, from the hook side:"
awk '{ if ($0 ~ /result=norecord/) none++ ; if ($0 ~ /result=sent/) sent++ ; if ($0 ~ /result=esrch/) esrch++ }
  END { printf "  hook reads: norecord=%d  sent=%d  esrch=%d\n", none+0, sent+0, esrch+0 }' \
  "$T/C14b_perplayer_unlink.hook-kills.log" 2>/dev/null || echo "  (log missing)"

hdr "C16: was killpg USED or SKIPPED, and did the player still die?"
echo "   (the pending marker bounds pgid-reuse blast radius to the narrow window)"
for c in C16a_pending_sweepfirst C16b_pending_pubfirst; do
  awk -F'\t' -v c="$c" '
    { n=split($6,f," "); delete V; for(i=1;i<=n;i++){split(f[i],kv,"="); V[kv[1]]=kv[2]} }
    $5=="election_sweep_pgid" { if (V["skipped"] != "") skip++; else used++ }
    $5=="pending_found" { found++ }
    $5=="pending_created" { created++ }
    END { printf "  %-26s pending created=%d found_at_sweep=%d | killpg used=%d skipped=%d\n",
                 c, created+0, found+0, used+0, skip+0 }
  ' "$T/$c.worker.trace" 2>/dev/null || echo "  $c (trace missing)"
done
