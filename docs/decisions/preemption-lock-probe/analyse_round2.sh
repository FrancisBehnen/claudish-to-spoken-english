#!/bin/bash
# Round-2 protocol facts, each extracted from a committed worker.trace with awk only.
# These are the claims the round-1 document could not make because it had no arm for
# them, plus the two defects review found in the round-1 repair.
#
# usage: analyse_round2.sh <traces_dir>
#
# ROUND 12: every block below used to end in `2>/dev/null || echo "(trace missing)"`,
# and the script still exited 0 when every one of them had printed it -- an analysis
# that derived none of the facts it names, reported as a success. Worse, one block
# ended in `| head -20 ||`, where the status belongs to `head` and never to awk, so a
# missing trace there printed nothing at all. Inputs are now checked before they are
# read, `2>/dev/null` no longer hides awk's own runtime errors, and a missing input is
# fatal at the end.
set -u
T=${1:?traces dir}

hdr() { printf '\n== %s ==\n' "$1"; }

miss=0
# ROUND 15. A MISSING input and a FAILED derivation are two different ways for a section
# to come out empty, and only the first was counted. `need X && awk ...` leaves awk's own
# status as the status of a compound command nothing inspects, so an awk that aborted
# mid-file printed a partial section and the script still exited 0. `broke` counts those
# the way `miss` counts the other, and the tail below fails on either.
broke=0
derive_failed() {   # section-name -- called when the awk for that section did not exit 0
  echo "  DERIVATION FAILED: $1 -- awk did not complete, so that section is partial" >&2
  echo "  (derivation failed)"
  broke=$((broke + 1))
}
need() {   # file... -> 0 if all present, else name what is absent and count it
  local f rc=0
  for f in "$@"; do
    # -r, not just -f: awk aborts on a file it cannot READ just as surely as on one
    # that is not there, and one of the blocks below ends in a pipe that would hide it.
    [[ -f "$f" && -r "$f" ]] && continue
    echo "  MISSING INPUT: $f" >&2
    echo "  (trace missing)"
    miss=$((miss + 1)); rc=1
  done
  return $rc
}

hdr "C12b: what ACTUALLY attributes the kill to the process group?"
echo "   Round 2 wrote 'the record sweep in the same election reported swept=0, so"
echo "   only the group could have reached it'. That is FALSE and is corrected here:"
echo "   the record sweep's target list is unbounded and it does reach pids left by"
echo "   earlier trials. The attribution is the killpg that was SENT, plus C12c."
need "$T/C12b_pgid_sweepfirst.worker.trace" && { awk -F'\t' '
  { n=split($6,f," "); delete V; for(i=1;i<=n;i++){split(f[i],kv,"="); V[kv[1]]=kv[2]} }
  # The warm-up player pid is DERIVED from its own P_popen, not hard-coded. A literal
  # only matches the committed run: after any re-run the pid necessarily differs and the
  # count silently reports zero -- a figure that reads as "the leak stopped".
  $5=="P_popen" && V["job"]=="w0" { W0=V["player_pid"] }
  # Exact comma-delimited membership, not a substring: /94309/ also matches 194309.
  $5=="election_sweep_record" { el++; if (V["swept"]+0 > 0) sw++
                                r=V["rows"]+0; if (r>maxrows) maxrows=r
                                if (W0 != "") { m=0; k=split(V["pids"], P, ",")
                                                for (q=1; q<=k; q++) if (P[q]==W0) m=1
                                                if (m) warm++ } }
  $5=="kill_attempt" && $6 ~ /site=pgid/ { if (V["result"]=="sent") sent++; else esrch++ }
  END { if (W0 == "") { print "  DERIVATION FAILED: no P_popen for job w0 -- warm-up pid not derivable" > "/dev/stderr"; exit 2 }
        printf "  record sweeps=%d of which swept>0: %d   target list grew to %d pids   warm-up player %s present in %d\n",
               el+0, sw+0, maxrows+0, W0, warm+0
        printf "  pgid kill_attempts: sent=%d  ESRCH=%d  (one live group per election, the rest already empty)\n",
               sent+0, esrch+0 }
' "$T/C12b_pgid_sweepfirst.worker.trace" || derive_failed C12b; }
echo "   and the control, C12c -- identical timing, pgid sweep REMOVED:"
need "$T/C12c_perplayer_recordonly.worker.trace" && { awk -F'\t' '
  { n=split($6,f," "); delete V; for(i=1;i<=n;i++){split(f[i],kv,"="); V[kv[1]]=kv[2]} }
  $5=="election_sweep_pgid" { g++ }
  END { printf "  pgid sweeps in C12c = %d\n", g+0 }
' "$T/C12c_perplayer_recordonly.worker.trace" || derive_failed C12c; }

hdr "C13a: did the ledger truncate ERASE a live player's entry?"
echo "   (an entry appended between the sweep's read and its truncate is wiped"
echo "    without ever having been signalled -- review comment on speakd_probe.py:167)"
# ROUND 15: this was the one block left with a pipe, and it was wrong in BOTH
# directions at once.
#  * `| head -20` put the block's exit status on `head`, which succeeds over an awk that
#    aborted, so a runtime error in the awk above came out as an empty-but-successful
#    C13a section -- the defect the round-12 header describes, still present in the one
#    place a pipe could hide it.
#  * And `head` was not merely a safety cap: the block emits FIFTY lines (25 sweeps +
#    25 truncates) and 20 of them were shown, so the section silently dropped 30 rows --
#    8 of the 12 erasures among them, leaving 4 visible. The 12/25 figure the document
#    quotes was therefore NOT derivable from the output of the script that derives it.
# Adding `pipefail` alone would have made it worse rather than better: `head` closes the
# pipe at line 20, awk dies of SIGPIPE, and a section that is merely truncated starts
# reporting itself as a hard failure. So the pipe goes, every row prints, and the block
# ends with the count the document actually quotes.
need "$T/C13a_ledger_truncate.worker.trace" && { awk -F'\t' '
  { n=split($6,f," "); delete V; for(i=1;i<=n;i++){split(f[i],kv,"="); V[kv[1]]=kv[2]} }
  $5=="election_sweep_record" { printf "  sweep read pids=%s swept=%s\n", V["pids"], V["swept"] }
  $5=="ledger_truncated" { t++; if (V["erased"] != "-") e++
                           printf "  truncate held=%-12s ERASED=%s\n", V["held_at_truncate"], V["erased"] }
  END { printf "  --> %d of %d truncations erased a registration that was never signalled\n", e+0, t+0 }
' "$T/C13a_ledger_truncate.worker.trace" || derive_failed C13a; }

hdr "C13b: same timing, per-player records -- nothing to truncate"
need "$T/C13b_perplayer_sametiming.worker.trace" && { awk -F'\t' '
  { n=split($6,f," "); delete V; for(i=1;i<=n;i++){split(f[i],kv,"="); V[kv[1]]=kv[2]} }
  $5=="ledger_truncated" { t++ }
  $5=="election_sweep_pgid" { g++ }
  END { printf "  ledger_truncated events=%d   pgid sweeps=%d\n", t+0, g+0 }
' "$T/C13b_perplayer_sametiming.worker.trace" || derive_failed C13b; }

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
need "$T/C14a_shared_unlink.player.log" "$T/C14a_shared_unlink.worker.trace" && { awk -F'\t' '
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
' "$T/C14a_shared_unlink.player.log" "$T/C14a_shared_unlink.worker.trace" || derive_failed C14a-order; }
echo "   and the consequence, from the hook side:"
need "$T/C14a_shared_unlink.hook-kills.log" && { awk -F'\t' '
  # ROUND 21: THE EVENT COLUMN IS CHECKED BEFORE `result=` IS EXTRACTED. The hook now also
  # emits `record_skipped … verdict=…`, which carries no `result=` at all -- so the blind
  # `sub(/^.*result=/…)` below left the whole tag in `r` and filed the row under a bucket
  # named after the tag. Nothing crashed and no total moved; the row simply vanished from
  # the denominator, which is the defect this document keeps finding, in miniature.
  $4 == "record_skipped" { SK++; next }
  $4 != "kill_attempt"   { OTHER++; next }
  { r = $0; sub(/^.*result=/, "", r); sub(/[ \t].*$/, "", r)
    if ($1 ~ /a$/)      A[r]++
    else if ($1 ~ /b$/) B[r]++
    else if ($1 ~ /c$/) C[r]++
    else                W[r]++
    T[r]++ }
  END { if (SK) printf "  NOTE: %d hook row(s) are `record_skipped` -- the hook found a record and\n        REFUSED it on identity grounds. Neither a read nor a kill; excluded below.\n", SK
        if (OTHER) printf "  NOTE: %d hook row(s) are of an unrecognised kind and were excluded.\n", OTHER
        printf "  hook reads, all: nopid=%d  sent=%d\n", T["nopid"]+0, T["sent"]+0
        printf "  hook A (before the trial spawns):   nopid=%d sent=%d\n", A["nopid"]+0, A["sent"]+0
        printf "  hook B (kills the a-player):        nopid=%d sent=%d\n", B["nopid"]+0, B["sent"]+0
        printf "  hook C (the b-player is playing):   nopid=%d sent=%d\n", C["nopid"]+0, C["sent"]+0
        printf "  --> hook C read NO record on %d of %d trials. THIS BLOCK CANNOT SAY whether\n", C["nopid"]+0, C["nopid"]+C["sent"]+0
        printf "      a player was live when it looked -- it reads only hook-kills.log, which\n"
        printf "      carries no timestamps -- and round 24 stopped it saying so. Witness (b)\n"
        printf "      below joins these trials to the K/R markers and settles it there.\n"
        printf "      On the other %d it read the b-player, which means that trial%s first\n", C["sent"]+0, "'"'"'s"
        printf "      unlink removed the a-player%s OWN record -- the b-player had not\n", "'"'"'s"
        printf "      published yet. The count of destroyed records is therefore NOT the\n"
        printf "      cross-unlink count above.\n" }' \
  "$T/C14a_shared_unlink.hook-kills.log" || derive_failed C14a-hook; }
# ROUND 17. THIS BLOCK USED TO ADD TWO GLOBAL COUNTERS AND THEN ASSERT THE JOIN.
# It counted `plog` (unlinks ordered after a newer player's own player_start) and
# `hookc` (hook-C reads that found nothing) as two independent totals with NO key in
# common -- not the trial, not the unlink -- printed their SUM as "PROVEN destructions
# of a published record", and then stated as fact that "they fall in the SAME k trials,
# and they are distinct unlinks". Nothing in the code established either half. The two
# witnesses could have seen the same unlink twice, or come from disjoint trials, and the
# arithmetic would have been identical. The figure it produced -- 8 destructions across
# 4 trials -- is quoted in the decision document AND is itself the correction that
# replaced a withdrawn one (24 across 12/12, lost with harness defect 4's bad `W`
# stamp), so a correction was resting on an assertion.
#
# The join keys were in the committed traces the whole time, and the third input is the
# one this block never opened:
#   worker.trace     `record_unlinked` carries `job=jNa|jNb`, so the TRIAL is in the
#                    row, and $1 is the timestamp. (trial, timestamp) is a unique key
#                    for the unlink EVENT.
#   hook-kills.log   hook-C rows carry TAG `tNc`, so the trial is in the row -- but
#                    there is NO timestamp column, so this file alone cannot order a
#                    hook-C read against any unlink.
#   markers.tsv      carries `tNc K` and `tNc R`, which BRACKET the record scan. Round
#                    17 used `tNc entry` and round 24 found that to be the wrong instant
#                    (see the liveness test below); analyse_c14.sh reads the same pair for
#                    the same reason. It is what turns the hook-C witness from a per-trial
#                    count into a NAMED event.
#
# ROUND 21 REPLACED THE ARGUMENT THAT BINDS THE HOOK-C WITNESS TO ONE UNLINK. Round 17
# used a window whose LOWER end was `W_pid_write[jNb]`, on the stated ground that "the
# record is published by the player's wrapper AFTER the parent stamps W, so it cannot have
# existed before this instant". THAT GROUND IS FALSE, and this script had already said so
# forty lines above: in a player-published arm the parent stamps W immediately after
# `Popen` returns and the wrapper runs CONCURRENTLY with it, so at `pubdelay=0` the rename
# can complete before the parent gets to the `rec()` call. That is harness defect 4 -- the
# same synthetic timestamp this block withdrew a lag figure for -- reintroduced as a bound.
# Measured on the committed traces, the parent's W trails its own `Popen` by 0.271-2.687 ms
# (mean 0.941), and publication may fall anywhere in that interval, so W is not a lower
# bound on anything.
#
# THE REPAIR IS NOT A BETTER BOUND. There is no directly observed publication instant in
# the committed traces at all -- nothing marks the wrapper's `mv`, `P_popen` is stamped
# after the fork just as W is, and `player_start` is stamped after `exec` and so may be
# LATER than the destruction rather than earlier. The event-level claim is instead carried
# by a UNIQUENESS argument that needs no publication timestamp:
#   (1) the b-player's record was certainly published before its own `player_start` -- the
#       wrapper is `write; mv || exit 97; exec`, so the player only exists if the rename
#       returned 0. [repo]
#   (2) hook C read NO record during its RECORD SCAN, at a moment when that player was
#       live. The scan is bracketed by `tNc K` (stamped immediately before it) and `tNc R`
#       (stamped after the HOOK_GAP_S sleep that follows it), and its exact instant is
#       unobserved -- so liveness is required ACROSS the interval:
#       `player_start <= tNc K` AND `player_end > tNc R`. So the record was published and
#       then destroyed, strictly before `tNc R`. [measured]
#       ROUND 24 CORRECTED THIS FROM `player_start <= tNc entry < player_end`, which
#       tested the instant the hook STARTED rather than the instant it LOOKED, and so
#       admitted a trial whose player had exited in between. On the committed traces all
#       four blind trials pass the stronger test with 1.52-1.56 s of margin past R, so the
#       derivation is strengthened and the figure does not move -- verified, not assumed.
#   (3) in this arm the ONLY thing that removes the record is the reaper's `os.unlink`,
#       which emits `record_unlinked`: `sweepmode=off`, and the two other `os.unlink` sites
#       in the probe remove `.pending` markers inside the pgid sweep. [repo]
# So the destroying unlink is one of the `record_unlinked` events lying between the b-job's
# SPAWN and the scan. If EXACTLY ONE lies there it is that one, wherever inside the
# unobserved window the publication actually fell -- which is what makes the naming sound
# without a publication instant.
#
# The interval is `(S2_prespawn_stat[jNb], tNc R)` -- round 24 moved the upper end from
# `tNc entry` for the same reason as the liveness test, and in the same safe direction: a
# wider interval can only add candidates and so can only make this refuse. It still holds
# exactly one on every one of the four trials. `S2_prespawn_stat` is emitted by the
# worker BEFORE it calls `Popen`, so it is strictly before the fork and therefore strictly
# before any publication: a valid lower bound, directly observed, and deliberately the
# LOOSEST one available -- widening it can only add candidates, and adding candidates can
# only make this check refuse. THE TRIAL FILTER IS GONE for the same reason. Round 17
# required `UTR[u] == i`, which EXCLUDES a delayed unlink from another trial that lands in
# this trial's interval; but such an unlink is a genuine candidate destroyer, so filtering
# it out could name an unlink while a second one was equally able to have done it. Every
# `record_unlinked` in the interval now counts, whatever job tag it carries.
# If exactly ONE `record_unlinked` falls in that interval, the destroying unlink is
# NAMED and can be compared against the player-log set as an event. If zero or several
# fall in it, the destruction is still witnessed but the unlink is NOT nameable, and
# that trial contributes a TRIAL to the union and no EVENT -- printed as a narrowing
# rather than folded into a total. That branch is exercised by the negative test in
# the commit message; on the committed traces every interval holds exactly one.
#
# What is printed is now the UNION of distinct events and the count of distinct trials,
# with the intersection derived rather than assumed to be empty, and the "first unlink
# / second unlink" ordering derived from each event's rank among its own trial's
# unlinks rather than stated.
echo "   the two witnesses JOINED per trial and per unlink -- the figure the document quotes:"
need "$T/C14a_shared_unlink.player.log" "$T/C14a_shared_unlink.hook-kills.log" \
     "$T/C14a_shared_unlink.markers.tsv" "$T/C14a_shared_unlink.worker.trace" && { awk -F'\t' '
  FILENAME ~ /player\.log$/ {
      if ($4=="player_start")    { PST[$3]=$1+0; PPID[$3]=$2 }
      else if ($4=="player_end")   PEN[$3]=$1+0
      next }
  FILENAME ~ /markers\.tsv$/ {
      # ROUND 24. `entry` was the wrong instant. The hook stamps it as its FIRST act;
      # the record scan happens after `K` and before `R` (which follows the HOOK_GAP_S
      # sleep), so `entry` proves nothing about the scan. Both ends of the enclosing
      # interval are read instead, and the block below uses K as its lower bound and R
      # as its upper one throughout.
      if ($1 !~ /^t[0-9]+c$/) next
      t=$1; sub(/^t/,"",t); sub(/c$/,"",t); t=t+0
      if ($2=="K")      HCK[t]=$3+0
      else if ($2=="R") HCR[t]=$3+0
      next }
  FILENAME ~ /hook-kills\.log$/ {
      if ($1 !~ /^t[0-9]+c$/) next
      t=$1; sub(/^t/,"",t); sub(/c$/,"",t); t+=0
      if (t>maxtr) maxtr=t
      # ROUND 21: only a `kill_attempt` may set the verdict. A `record_skipped` row has no
      # `result=` field, so the blind substitution below used to store the TAG as the
      # verdict -- which is neither "nopid" nor "sent", so the trial fell out of witness (b)
      # in total silence. A skipped record also MEANS the opposite of `nopid`: the hook
      # FOUND a record and refused it, so the record was not destroyed. Recorded separately
      # and reported, never folded into either bucket. This keys on the ROW KIND and not on
      # the verdict value, so the `lookup_failed` verdict round 24 added needed no change
      # here -- which is the reason to key on the kind. (And no apostrophes in here: this
      # comment lives inside a single-quoted awk program, so one would end the quote.)
      if ($4 == "record_skipped") { HSK[t]++; next }
      if ($4 != "kill_attempt") next
      r=$0; sub(/^.*result=/,"",r); sub(/[ \t].*$/,"",r)
      HC[t]=r
      next }
  # worker.trace
  { n=split($6,f," "); delete V; for(i=1;i<=n;i++){split(f[i],kv,"="); V[kv[1]]=kv[2]} }
  # THE SPAWN INSTANT, and the only per-job timestamp this block now uses. Emitted by the
  # worker BEFORE it calls Popen, so it is strictly before the fork and therefore strictly
  # before any publication -- unlike W_pid_write, which round 17 used for both jobs below
  # and which is stamped AFTER Popen returns, while the wrapper is already running.
  # W_pid_write is not read here at all any more: it is harness defect 4'"'"'s synthetic
  # stamp in this arm, and neither witness needs it.
  # S2 carries no player_pid -- the player does not exist yet -- so the ordered arrays key
  # on the JOB and the pid is resolved from P_popen in END. A job with an S2 and no P_popen
  # (the worker died between them) resolves to an empty pid and is skipped, which is the
  # guard witness (a) already had.
  $5=="S2_prespawn_stat" { nw++; WTS[nw]=$1+0; WJOB[nw]=V["job"]; SPAWN[V["job"]]=$1+0 }
  $5=="P_popen" { PPD[V["job"]]=V["player_pid"] }
  $5=="record_unlinked" {
      nu++; UTS[nu]=$1; UN[nu]=$1+0; UPID[nu]=V["player_pid"]
      tr=V["job"]; sub(/^j/,"",tr); sub(/[abc]$/,"",tr)
      UTR[nu] = (tr ~ /^[0-9]+$/) ? tr+0 : -1        # w0 and any non-trial job -> -1
      if (UTR[nu] > maxtr) maxtr = UTR[nu] }
  END {
    # rank of each unlink among its own trial'"'"'s unlinks, by timestamp. Derived here so
    # the "first unlink / second unlink" statement below is a reading and not a claim.
    for (u=1; u<=nu; u++) {
      NPER[UTR[u]]++
      r=1; for (v=1; v<=nu; v++) if (UTR[v]==UTR[u] && UN[v] < UN[u]) r++
      RK[u]=r }

    # ---- witness (a): the player log. An unlink that landed after a DIFFERENT, newer
    #      player'"'"'s own player_start destroyed a record that was certainly on disk.
    for (u=1; u<=nu; u++) {
      lastp=""; lastj=""
      for (w=1; w<=nw; w++) if (WTS[w] < UN[u]) { lastj=WJOB[w]; lastp=PPD[lastj] }
      if (lastp=="" || lastp==UPID[u]) continue
      if (!(lastj in PST) || UN[u] <= PST[lastj]) continue
      PLOG[u]=1; VICT[u]=lastp; nplog++ }

    # ---- witness (b): hook C read nothing while the trial'"'"'s b-player was demonstrably
    #      live, joined to the one unlink that can have done it.
    for (i=1; i<=maxtr; i++) {
      # A trial whose hook C only ever SKIPPED is neither a destruction nor a clean read,
      # and must not disappear. Name it, then move on.
      if (!(i in HC) && (i in HSK)) {
        printf "  trial %-2d hook C refused every record it found on identity grounds (%d row(s))\n", i, HSK[i]
        printf "           -- the record was NOT destroyed: NOT counted either way\n"
        continue }
      if (!(i in HC) || HC[i] != "nopid") continue
      jb = "j" i "b"
      if (!(i in HCK) || !(i in HCR) || !(jb in PST) || !(jb in PEN) || !(jb in SPAWN)) {
        printf "  trial %-2d hook C read nothing, but its own timing is not in the traces --\n", i
        printf "           no live-player check and no interval: NOT counted either way\n"
        unjoinable++; continue }
      # ROUND 24. THIS TEST WAS AT THE WRONG INSTANT. `PST <= entry < PEN` says the
      # b-player was live when the hook STARTED. The `nopid` observation is later -- after
      # K, after the record scan -- so a player that exited in between satisfied the old
      # predicate and made this block count a destruction with no player live at the scan.
      # The scan lies strictly inside (K, R), and its exact instant is unobserved, so the
      # only sound test is liveness ACROSS the whole interval. R is a loose upper bound
      # (it trails the scan by the ~90 ms hook sleep) and loose is the safe direction for
      # a witness whose content is an absence.
      if (!(PST[jb] <= HCK[i] && PEN[jb] > HCR[i])) {
        printf "  trial %-2d hook C read nothing, but its b-player was not live ACROSS the\n", i
        printf "           scan interval (K..R) -- NOT a destruction\n"
        continue }
      hc_trials++; HCTR[i]=1
      cnt=0; pick=0
      # THE UNIQUENESS CHECK. Every record_unlinked between the b-job'"'"'s SPAWN and hook C
      # is a candidate destroyer, because the publication instant is unobserved and may
      # fall anywhere after the fork. NO TRIAL FILTER: round 17 required UTR[u]==i, which
      # discards a delayed unlink from another trial landing in this interval -- but such
      # an unlink could equally have done the destroying, so discarding it could name one
      # unlink while a second was just as able. Counting every candidate can only make this
      # refuse, never make it name more.
      # The UPPER END IS `R`, not `entry`, for the same reason the liveness test moved:
      # the destroying unlink must precede the SCAN, and the latest the scan can have
      # happened is R. Widening the interval can only ADD candidates and so can only make
      # this refuse -- never make it name more -- which is the direction a naming argument
      # has to err in.
      for (u=1; u<=nu; u++) if (UN[u] > SPAWN[jb] && UN[u] < HCR[i]) { cnt++; pick=u }
      if (cnt == 1) { HOOKC[pick]=1; HVICT[pick]=PPID[jb]; nhookc++ }
      else { printf "  trial %-2d hook C witnessed a destruction, but %d unlinks fall in\n", i, cnt
             printf "           (S2_prespawn_stat[%s], tNc R) -- the destroying unlink is NOT nameable\n", jb
             ambig++ } }

    # ---- the union, over the (trial, timestamp) event key.
    for (u=1; u<=nu; u++) {
      if (!PLOG[u] && !HOOKC[u]) continue
      nunion++
      # UTR is -1 for a job with no trial number (`w0`, the warm-up). Such an event
      # would be counted in the union and then dropped from the 1..maxtr trial walk
      # below, so the two totals would disagree with nothing saying why. Name it.
      if (UTR[u] < 1) notrial++; else TR[UTR[u]]=1
      if (PLOG[u] && HOOKC[u]) { both++; w="BOTH  " ; d=VICT[u] }
      else if (HOOKC[u])       { w="hook C"; d=HVICT[u] }
      else                     { w="p-log " ; d=VICT[u] }
      if (RK[u] > hcmax && HOOKC[u] && !PLOG[u]) hcmax=RK[u]
      if (HOOKC[u] && !PLOG[u] && (hcmin==0 || RK[u] < hcmin)) hcmin=RK[u]
      if (RK[u] > plmax && PLOG[u] && !HOOKC[u]) plmax=RK[u]
      if (PLOG[u] && !HOOKC[u] && (plmin==0 || RK[u] < plmin)) plmin=RK[u]
      printf "  trial %-2d unlink %d of %-2d  t=%s  reap of %-6s destroyed %-6s  witness: %s\n",
             UTR[u], RK[u], NPER[UTR[u]], UTS[u], UPID[u], d, w }
    # A hook-C trial whose unlink could NOT be named still witnessed a destruction in
    # that trial, so it belongs to the trial union even though it names no event.
    for (i=1; i<=maxtr; i++) if (HCTR[i]) TR[i]=1
    ntr=0; list=""
    for (i=1; i<=maxtr; i++) if (TR[i]) { ntr++; list = list " " i }

    printf "  --> witness (a), player-log order:  %d distinct unlink event(s)\n", nplog+0
    printf "  --> witness (b), hook C read nothing with a player live ACROSS the scan: %d trial(s),\n", hc_trials+0
    printf "      of which %d had exactly one unlink candidate in the interval and are NAMED as events\n", nhookc+0
    printf "  --> the two witness sets intersect in %d event(s) (derived over the (trial,\n", both+0
    printf "      timestamp) key, not assumed disjoint)\n"
    printf "  --> UNION of DISTINCT destroying unlinks: %d, across %d DISTINCT trial(s):%s\n",
           nunion+0, ntr+0, list
    if (notrial)
      printf "  --> %d of those %d event(s) carry a job with NO trial number (the warm-up) and\n      are counted in the union but in none of the trials above\n", notrial, nunion+0
    if (nhookc && nplog) {
      if (hcmin==hcmax && plmin==plmax)
        printf "  --> within its own trial every hook-C event is unlink #%d and every player-log\n      event is unlink #%d -- derived from the ranks above, not assumed\n", hcmin, plmin
      else
        printf "  --> hook-C events rank #%d-#%d within their trial, player-log events #%d-#%d\n", hcmin, hcmax, plmin, plmax
    }
    if (ambig || unjoinable)
      printf "  NARROWED: %d hook-C trial(s) witness a destruction whose unlink could not be\n            named, and %d could not be checked at all. They add TRIALS to the union\n            above and NO events. The event total counts only named events.\n", ambig+0, unjoinable+0
  }
' "$T/C14a_shared_unlink.player.log" "$T/C14a_shared_unlink.hook-kills.log" \
  "$T/C14a_shared_unlink.markers.tsv" "$T/C14a_shared_unlink.worker.trace" || derive_failed C14a-total; }

hdr "C14b: per-player records -- an unlink can only remove its own name"
need "$T/C14b_perplayer_unlink.worker.trace" && { awk -F'\t' '
  { n=split($6,f," "); delete V; for(i=1;i<=n;i++){split(f[i],kv,"="); V[kv[1]]=kv[2]} }
  $5=="record_unlinked" { if (V["path"] ~ ("^" V["player_pid"] "\\.")) own++; else other++ }
  END { printf "  unlinks of own record=%d   of another player%s record=%d\n", own+0, "'"'"'s", other+0 }
' "$T/C14b_perplayer_unlink.worker.trace" || derive_failed C14b; }
echo "   and the consequence, from the hook side:"
need "$T/C14b_perplayer_unlink.hook-kills.log" && { awk '{ if ($0 ~ /result=norecord/) none++ ; if ($0 ~ /result=sent/) sent++ ; if ($0 ~ /result=esrch/) esrch++ ; if ($0 ~ /record_skipped/) skip++ }
  END { printf "  hook reads: norecord=%d  sent=%d  esrch=%d  skipped_on_identity=%d\n", none+0, sent+0, esrch+0, skip+0 }' \
  "$T/C14b_perplayer_unlink.hook-kills.log" || derive_failed C14b-hook; }

hdr "C15c/C16: was killpg USED or SKIPPED, and did the player still die?"
echo "   (the pending marker did NOT bound the blast radius in THIS arm: the committed"
echo "    marker is a boolean, it leaked -- 25 created, 0 removed -- and the gate was"
echo "    open on 23 of 25 elections against 12 staged windows. The generation tag and"
echo "    the owner-identity check that would bound it are specified and UNRUN.)"
echo "   C15c is included because round 2 credited its 12/12 to the pgid sweep. It is"
echo "   not: killpg is skipped on every election and the RECORD sweep does the work,"
echo "   which is why clause 7(iv-a) exists."
for c in C15c_norecheck_death_pgid C16a_pending_sweepfirst C16b_pending_pubfirst; do
  need "$T/$c.worker.trace" || continue
  awk -F'\t' -v c="$c" '
    { n=split($6,f," "); delete V; for(i=1;i<=n;i++){split(f[i],kv,"="); V[kv[1]]=kv[2]} }
    $5=="election_sweep_pgid" { if (V["skipped"] != "") skip++; else used++ }
    $5=="election_sweep_record" { if (V["swept"]+0 > 0) recswept++ }
    $5=="pending_found" { found++ }
    $5=="pending_created" { created++ }
    END { printf "  %-26s pending created=%d found_at_sweep=%d | killpg used=%d skipped=%d | record sweeps that signalled=%d\n",
                 c, created+0, found+0, used+0, skip+0, recswept+0 }
  ' "$T/$c.worker.trace" || derive_failed "$c"
done

if [[ $miss -gt 0 || $broke -gt 0 ]]; then
  echo "INCOMPLETE: $miss input(s) missing from $T and $broke derivation(s) failed --" >&2
  echo "the facts above are a SUBSET of what this script names, and the ones it could" >&2
  echo "not derive are not marked in the output the document quotes from. NOT a pass." >&2
  exit 2
fi
