#!/bin/bash
# Round-2 protocol facts, each extracted from a committed worker.trace with awk only.
# These are the claims the round-1 document could not make because it had no arm for
# them, plus the two defects review found in the round-1 repair.
#
# usage: analyse_round2.sh <traces_dir>
set -u
T=${1:?traces dir}

hdr() { printf '\n== %s ==\n' "$1"; }

hdr "C12b: what ACTUALLY attributes the kill to the process group?"
echo "   Round 2 wrote 'the record sweep in the same election reported swept=0, so"
echo "   only the group could have reached it'. That is FALSE and is corrected here:"
echo "   the record sweep's target list is unbounded and it does reach pids left by"
echo "   earlier trials. The attribution is the killpg that was SENT, plus C12c."
awk -F'\t' '
  { n=split($6,f," "); delete V; for(i=1;i<=n;i++){split(f[i],kv,"="); V[kv[1]]=kv[2]} }
  $5=="election_sweep_record" { el++; if (V["swept"]+0 > 0) sw++
                                r=V["rows"]+0; if (r>maxrows) maxrows=r
                                if (V["pids"] ~ /94309/) warm++ }
  $5=="kill_attempt" && $6 ~ /site=pgid/ { if (V["result"]=="sent") sent++; else esrch++ }
  END { printf "  record sweeps=%d of which swept>0: %d   target list grew to %d pids   warm-up player 94309 present in %d\n",
               el+0, sw+0, maxrows+0, warm+0
        printf "  pgid kill_attempts: sent=%d  ESRCH=%d  (one live group per election, the rest already empty)\n",
               sent+0, esrch+0 }
' "$T/C12b_pgid_sweepfirst.worker.trace" 2>/dev/null || echo "  (trace missing)"
echo "   and the control, C12c -- identical timing, pgid sweep REMOVED:"
awk -F'\t' '
  { n=split($6,f," "); delete V; for(i=1;i<=n;i++){split(f[i],kv,"="); V[kv[1]]=kv[2]} }
  $5=="election_sweep_pgid" { g++ }
  END { printf "  pgid sweeps in C12c = %d\n", g+0 }
' "$T/C12c_perplayer_recordonly.worker.trace" 2>/dev/null || echo "  (trace missing)"

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
        lag = ($1 - lastpub_t) * 1000
        L[bad] = lag
        if (lag > 1000) slow++          # a SECOND-hook reap, one trial-gap late
        printf "  t=%.6f  reap of %-6s unlinked %-4s -- newer player %s had published %.1f ms earlier\n",
               $1, V["player_pid"], V["path"], lastpub, lag
      } }
  END { printf "  --> %d unlinks destroyed a newer player%s record\n", bad+0, "'"'"'s"
        # The lag is what the document quotes as "the record was destroyed N ms after
        # it was published". Round 2 quoted 31-76 ms, which re-derives from nothing:
        # the reaps of a trial`s FIRST player land a whole trial gap later.
        lo = 1e18; hi = 0; lo2 = 1e18; hi2 = 0
        for (i = 1; i <= bad; i++) {
          if (L[i] < lo) lo = L[i]; if (L[i] > hi) hi = L[i]
          if (L[i] <= 1000) { if (L[i] < lo2) lo2 = L[i]; if (L[i] > hi2) hi2 = L[i] } }
        if (bad) printf "  --> lag publish->destroy: %.1f-%.1f ms overall; %.1f-%.1f ms excluding the %d second-hook reaps\n",
                        lo, hi, lo2, hi2, slow+0 }
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

hdr "C15c/C16: was killpg USED or SKIPPED, and did the player still die?"
echo "   (the pending marker bounds pgid-reuse blast radius to the narrow window)"
echo "   C15c is included because round 2 credited its 12/12 to the pgid sweep. It is"
echo "   not: killpg is skipped on every election and the RECORD sweep does the work,"
echo "   which is why clause 7(iv-a) exists."
for c in C15c_norecheck_death_pgid C16a_pending_sweepfirst C16b_pending_pubfirst; do
  awk -F'\t' -v c="$c" '
    { n=split($6,f," "); delete V; for(i=1;i<=n;i++){split(f[i],kv,"="); V[kv[1]]=kv[2]} }
    $5=="election_sweep_pgid" { if (V["skipped"] != "") skip++; else used++ }
    $5=="election_sweep_record" { if (V["swept"]+0 > 0) recswept++ }
    $5=="pending_found" { found++ }
    $5=="pending_created" { created++ }
    END { printf "  %-26s pending created=%d found_at_sweep=%d | killpg used=%d skipped=%d | record sweeps that signalled=%d\n",
                 c, created+0, found+0, used+0, skip+0, recswept+0 }
  ' "$T/$c.worker.trace" 2>/dev/null || echo "  $c (trace missing)"
done
