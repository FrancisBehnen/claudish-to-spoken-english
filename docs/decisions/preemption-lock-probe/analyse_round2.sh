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
echo "   ROUND 5 REMOVED THE 'publication -> destruction' LAG THIS BLOCK USED TO PRINT."
echo "   It anchored on W_pid_write, which in a player-published arm is stamped by the"
echo "   PARENT immediately after Popen and before the wrapper renames -- harness defect"
echo "   4. So it was never measured from publication, and the 41.3-82.3 ms range it"
echo "   produced is not an interval between the two events it named. Nothing in the"
echo "   committed traces marks the wrapper's mv, so no publish->destroy figure is"
echo "   derivable at all; it is removed rather than caveated."
echo "   What IS derivable is ORDER, from two independent sides:"
echo "    (a) the player log. player_start is stamped by the player itself, after the"
echo "        wrapper renamed and after exec, so it is strictly LATER than publication."
echo "        An unlink after it therefore destroyed a record that certainly existed."
echo "    (b) the hook side, below: a later hook that reads NO record while that newer"
echo "        player is demonstrably live can only mean the record was published and"
echo "        then destroyed -- nothing else in this arm unlinks."
awk -F'\t' '
  # pass 1: the player log, keyed by pid.
  FNR==NR { if ($4=="player_start") START[$2]=$1; next }
  { n=split($6,f," "); delete V; for(i=1;i<=n;i++){split(f[i],kv,"="); V[kv[1]]=kv[2]} }
  $5=="W_pid_write" { last=V["player_pid"]; last_t=$1 }
  $5=="record_unlinked" {
      if (last != "" && V["player_pid"] != last && $1 > last_t) {
        cross++
        ps = (last in START) ? START[last] : ""
        if (ps != "" && $1 > ps) {
          proven++
          d = ($1 - ps) * 1000
          if (d < lo || proven == 1) lo = d
          if (d > hi) hi = d
          printf "  t=%.6f  reap of %-6s unlinked %-4s -- newer player %s was already RUNNING (%.1f ms)\n",
                 $1, V["player_pid"], V["path"], last, d
        } else {
          unordered++
        }
      } }
  END {
    printf "  --> %d unlinks of the shared path landed while a newer player existed\n", cross+0
    printf "  --> of those, %d are PROVEN destructions: the unlink followed the newer\n", proven+0
    printf "      player%s own player_start, so its record was certainly already on disk\n", "'"'"'s"
    if (proven) printf "      (unlink - player_start = %.1f-%.1f ms; a LOWER bound on publish->destroy,\n       not the interval itself)\n", lo, hi
    printf "  --> the other %d cannot be ordered against publication on the committed data\n", unordered+0
    printf "      at all -- the unlink lands inside the newer player%s unobserved\n", "'"'"'s"
    printf "      Popen->publish->exec gap. See the hook side for what settles them.\n"
  }
' "$T/C14a_shared_unlink.player.log" "$T/C14a_shared_unlink.worker.trace" 2>/dev/null \
  || echo "  (trace missing)"
echo "   and the consequence, from the hook side:"
awk -F'\t' '
  { r = $0; sub(/^.*result=/, "", r); sub(/[ \t].*$/, "", r)
    if ($1 ~ /a$/)      A[r]++
    else if ($1 ~ /b$/) B[r]++
    else if ($1 ~ /c$/) C[r]++
    else                W[r]++
    T[r]++ }
  END { printf "  hook reads, all: nopid=%d  sent=%d\n", T["nopid"]+0, T["sent"]+0
        printf "  hook A (before the trial spawns):   nopid=%d sent=%d\n", A["nopid"]+0, A["sent"]+0
        printf "  hook B (kills the a-player):        nopid=%d sent=%d\n", B["nopid"]+0, B["sent"]+0
        printf "  hook C (the b-player is playing):   nopid=%d sent=%d\n", C["nopid"]+0, C["sent"]+0
        printf "  --> hook C read NO record on %d of %d trials while a live player was\n", C["nopid"]+0, C["nopid"]+C["sent"]+0
        printf "      there to preempt: those are destructions of a published record.\n"
        printf "      On the other %d it read the b-player, which means that trial%s first\n", C["sent"]+0, "'"'"'s"
        printf "      unlink removed the a-player%s OWN record -- the b-player had not\n", "'"'"'s"
        printf "      published yet. The count of destroyed records is therefore NOT the\n"
        printf "      cross-unlink count above.\n" }' \
  "$T/C14a_shared_unlink.hook-kills.log" 2>/dev/null || echo "  (log missing)"
echo "   the two sides added up -- this is the figure the document quotes:"
awk -F'\t' '
  FILENAME ~ /player\.log$/   { if ($4=="player_start") START[$2]=$1; next }
  FILENAME ~ /hook-kills\.log$/ { if ($1 ~ /c$/) { if ($0 ~ /result=nopid/) hookc++ } ; next }
  { n=split($6,f," "); delete V; for(i=1;i<=n;i++){split(f[i],kv,"="); V[kv[1]]=kv[2]} }
  $5=="W_pid_write" { last=$6; sub(/^.*player_pid=/,"",last); sub(/[ \t].*$/,"",last); last_t=$1 }
  $5=="record_unlinked" {
      if (last != "" && V["player_pid"] != last && $1 > last_t &&
          (last in START) && $1 > START[last]) plog++ }
  END { printf "  PROVEN destructions of a published record: %d (player-log order) + %d (hook C read nothing) = %d\n",
               plog+0, hookc+0, plog+hookc+0
        printf "  They fall in the SAME %d trials, and they are distinct unlinks: the first\n", hookc+0
        printf "  unlink of such a trial is caught by hook C, the second by the player log.\n" }
' "$T/C14a_shared_unlink.player.log" "$T/C14a_shared_unlink.hook-kills.log" \
  "$T/C14a_shared_unlink.worker.trace" 2>/dev/null || echo "  (trace missing)"

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
