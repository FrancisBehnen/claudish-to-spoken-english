#!/bin/bash
# Turn one run directory into two committed evidence files, then join them with awk.
#
#   markers.tsv   the hook-side timestamps, read out of the marker files with
#                 `stat -f %Fm` (the fork-free technique the residency run
#                 validated to ~90 us against $EPOCHREALTIME)
#   trials.tsv    one row per trial, joining markers.tsv with worker.trace
#
# WHAT trials.tsv IS ENOUGH FOR, AND WHAT IT IS NOT. This header used to read
# "everything published derives from trials.tsv with awk/sort and nothing else", which is
# the claim the PR description and the README both had to withdraw and which came back
# here. trials.tsv is ONE ROW PER TRIAL, so it carries what a trial's players and hooks
# ENDED UP as -- and no column of it carries a trace EVENT. The boundary, by consumer:
#
#   summarise.sh <evidence_dir>            over the four committed TSVs -- the per-trial
#                                          quantities: kill attribution, the player
#                                          process intervals, the window widths, and
#                                          row 21's owner counts.
#   analyse_round2.sh traces               over the raw traces -- `record_unlinked`,
#                                          `pending_found`/`pending_created`, the
#                                          sweep-skip counts, and every statement about
#                                          what a sweep DID. None is a TSV column.
#   analyse_c14.sh traces                  the hook-C reachability arms (4/8 and 0/12),
#                                          which need the `tNc` markers and hook rows.
#   compare_passes.sh <evidence_dir>       the published arm against the replication.
#
# The two derivations are disjoint and both are required; neither checks the other.
#
# usage: collect.sh <rundir> <config>
set -u
D=${1:?rundir}; CFG=${2:?config}
MD="$D/markers"

# Check the inputs BEFORE parsing them. awk aborts on a file it cannot open, so a run
# directory missing any of these left an EMPTY trials.tsv behind -- and this script then
# exited 0, because its last command was the `wc` that counted the nothing. That is the
# null-as-pass defect at its source: every caller that runs collect.sh and reads
# trials.tsv afterwards inherited it.
#
# All four exist in any run that happened: the warm-up job alone makes every hook write
# kills.log and its markers, and makes one player write player.log. An absent file means
# the run did not happen, not that there was nothing to record.
[[ -d "$D" ]] || { echo "collect.sh: no run directory $D" >&2; exit 2; }
for f in "$MD" "$MD/kills.log" "$D/player.log" "$D/worker.trace"; do
  [[ -e "$f" ]] || { echo "collect.sh: $D is not a complete run -- missing $f" >&2; exit 2; }
done

# ---- publish_refused: A VOID TRIAL THAT USED TO COLLECT AS SUCCESSFUL PREEMPTION
#
# ROUND 29, AND THIS IS THE SHARPEST OF THE THREE THIS REVISION CLOSES, because it does
# not mislabel evidence -- it MANUFACTURES it.
#
# Round 25 made speakd_probe.py fail closed on a failed identity lookup: rather than
# publish a pid record no signaller would act on, it stops the player through the Popen
# handle and records `publish_refused`. The player is then dead, the record was never
# published, and the trial measured NOTHING about preemption. THAT FIX HAD NO CONSUMER.
# Downstream, every step read the void as a success:
#
#   1. speakd_probe.py emits `W_pid_write ... result=refused`.
#   2. This collector`s W branch tested `result != "disabled"` -- a BLIND ELSE -- so
#      `refused` fell through it and stamped W[job]. A publication that was REFUSED was
#      recorded as a publication that HAPPENED, at the instant of the refusal.
#   3. The refusal path calls Popen.terminate(), i.e. SIGTERM, so the parent reaps
#      rc=-15.
#   4. attrib.sh maps rc=-15 to `hook-pid-kill`. NO HOOK RAN. The trial is published as
#      a successful hook-side pid kill -- direct support for the very mechanism row 20
#      certifies -- out of a transient `ps` failure.
#
# A transient identity-lookup failure could therefore be published as evidence FOR
# hook preemption. Nothing anywhere refused it: `publish_refused` appears in no
# collector, no validator and no analyser, and it is absent from every committed trace
# (grep over traces/ finds zero occurrences of `publish_refused` and zero of
# `result=refused`), so the committed figures are NOT affected. This is a defect that
# would bite on the next re-run.
#
# WHY REJECT THE RUN RATHER THAN CARRY A VOID COLUMN. A VOID flowing through the schema
# is more informative, and it was the other candidate. It loses on consumers: adding
# column 27 means teaching summarise.sh sections A-F, compare_passes.sh and peek_one.sh
# to refuse a VOID row, and MISSING ONE OF THEM RECREATES EXACTLY THIS DEFECT -- a new
# outcome with no consumer -- inside the fix for it. Rejecting the run needs no new
# consumer, because every caller of this script already checks its exit status:
# assemble.sh (:36), assemble_pass1.sh, peek.sh (:13) and peek_one.sh (:20) each refuse
# to publish or print when collection fails. That consumer set is complete today and was
# verified to be.
#
# THE COST, stated: the whole configuration is refused, not the one affected trial. Its
# eleven good trials are discarded with the void one and the configuration must be
# re-run, where a VOID column would have let the other eleven be analysed. That is the
# price of a guard that cannot be misread, and a re-run of one configuration is cheap
# next to a published row-20 arm that never happened.
#
# `publish_refused_kill_failed` is rejected on the SAME line and is strictly worse: the
# terminate() itself raised OSError, so the player may still be RUNNING and is now
# unreachable by every signaller, since no record was ever published.
refused=$(awk -F'\t' '$5 == "publish_refused" || $5 == "publish_refused_kill_failed" { print $5 }' \
          "$D/worker.trace" | sort | uniq -c)
if [[ -n $refused ]]; then
  echo "collect.sh: $D contains a REFUSED publication -- these trials are VOID." >&2
  printf '%s\n' "$refused" | sed 's/^/  /' >&2
  echo "The worker could not obtain the player identity, so it stopped the player through" >&2
  echo "the Popen handle and published NO record. The resulting rc=-15 would be collected" >&2
  echo "as a hook-side pid kill although no hook ran, turning a void trial into evidence" >&2
  echo "for the mechanism row 20 certifies. Refusing to collect it." >&2
  echo "Re-run $CFG. There is no override: a refused publication measured nothing, so" >&2
  echo "there is no reading of the trial that a flag could make valid." >&2
  exit 2
fi
# And any OTHER value in that field. The recognised set is exactly {absent, disabled,
# refused, deferred_to_player} (speakd_probe.py:1554-1566). The W branch below now
# dispatches on those names rather than on "not disabled", so a value added later must
# stop here instead of silently taking the published-successfully path -- which is the
# blind else that made `refused` a defect in the first place.
unknown_w=$(awk -F'\t' '
  $5 != "W_pid_write" { next }
  { n = split($6, f, " "); r = ""
    for (i = 1; i <= n; i++) { split(f[i], kv, "="); if (kv[1] == "result") r = kv[2] }
    if (r != "" && r != "disabled" && r != "refused" && r != "deferred_to_player") print r }' \
  "$D/worker.trace" | sort -u)
if [[ -n $unknown_w ]]; then
  echo "collect.sh: $D has W_pid_write result value(s) this collector has no rule for:" >&2
  printf '%s\n' "$unknown_w" | sed 's/^/  result=/' >&2
  echo "The recognised set is {absent, disabled, refused, deferred_to_player}. An" >&2
  echo "unrecognised value must not default to <published successfully>. Teach the W" >&2
  echo "branch what it means, then re-collect." >&2
  exit 2
fi

# ---- markers.tsv
{
  printf 'tag\tevent\tts\n'
  for f in "$MD"/*.entry "$MD"/*.K "$MD"/*.R "$MD"/*.Rdone; do
    [[ -e "$f" ]] || continue
    b=${f##*/}; tag=${b%.*}; ev=${b##*.}
    printf '%s\t%s\t%s\n' "$tag" "$ev" "$(stat -f '%Fm' "$f")"
  done
} > "$D/markers.tsv"

# ---- trials.tsv
awk -F'\t' -v cfg="$CFG" '
FILENAME ~ /markers\.tsv$/ {
  if ($1 == "tag") next
  M[$1 "." $2] = $3
  next
}
FILENAME ~ /kills\.log$/ {
  # tag  hook  pid  kill_attempt  by=.. target=.. sig=.. result=..
  #
  # ROUND 21: THE EVENT COLUMN IS NOW CHECKED. The hook emits a second kind of row --
  # `record_skipped … verdict=recycled|unverifiable|lookup_failed` (round 24 added the last),
  # when the identity of the player record does not verify -- and that row has a `target=` but
  # NO `result=`. Folding it into the
  # same flat `K[tag.field]` map let a skipped target from one hook invocation overwrite the
  # target it actually killed, since a per-player hook can do both in one call. The
  # columns below mean "what the hook DID", so only `kill_attempt` may write them.
  # Skipped rows are counted and reported rather than dropped in silence, because the
  # whole lesson of this file is that a row nothing consumes is a row nobody knows is
  # missing. NOTE: no apostrophes below this line -- the awk program is single-quoted, and
  # one apostrophe in a comment ends the shell string. It cost a round.
  if ($4 != "kill_attempt") { if ($4 == "record_skipped") nskip++; next }
  split($5, f, " ")
  for (i in f) { split(f[i], kv, "="); K[$1 "." kv[1]] = kv[2] }
  next
}
FILENAME ~ /player\.log$/ {
  # ts pid tag kind fields   -- the player own view (cross-check). Cross-checks rc, and gives
  # the stub PROCESS start (a player killed before this line never reached its own first
  # instruction). It is not an audibility observation and never was: player_probe.py opens
  # no audio device at any point, so "was anything heard" is not a question these stamps
  # can be asked. See the pstart_to_pend_s column below.
  n = split($5, f, " ")
  for (i = 1; i <= n; i++) { split(f[i], kv, "="); V2[kv[1]] = kv[2] }
  if ($4 == "player_start")    { PSTART[$3] = $1 }
  else if ($4 == "player_end") { PEND[$3] = $1; PSIG[$3] = V2["sig"] }
  delete V2
  next
}
FILENAME ~ /worker\.trace$/ {
  # ts worker pid genN kind fields
  n = split($6, f, " "); job = ""
  for (i = 1; i <= n; i++) { split(f[i], kv, "="); V[kv[1]] = kv[2] }
  job = V["job"]
  if ($5 == "S_claim")           { S[job] = $1; SGEN[job] = $4; lastjob = job }
  else if ($5 == "S2_prespawn_stat") { S2[job] = $1; NEWER[job] = V["newer_waiting"] }
  else if ($5 == "discarded")    { DISC[job] = 1 }
  else if ($5 == "P_popen")      { P[job] = $1; PPID[job] = V["player_pid"] }
  # a disabled pid write is NOT a pid write: recording it would mislabel the
  # ordering of any configuration that switches clause (i) off
  #
  # ROUND 29: THESE BRANCHES NOW NAME EVERY RESULT VALUE. The middle one used to read
  # `V["result"] != "disabled"`, a blind else that answered "did a publication happen"
  # with "well, it was not switched off". A REFUSED publication -- the round-25 fail-closed
  # path, which stops the player and writes no record -- fell straight through it and
  # stamped W as though the record had been published, at the instant it was refused. The
  # shell guard at the top of this file rejects such a run outright; these branches are
  # the second half of the same repair, so that a result value added later cannot inherit
  # the published-successfully path by default. `refused` is listed here for that reason
  # even though the guard above means it is never reached.
  else if ($5 == "W_pid_write" && V["by"] == "player") { WPLAYER[job] = 1; W[job] = $1 }
  else if ($5 == "W_pid_write" && V["result"] == "")         { W[job] = $1 }
  else if ($5 == "W_pid_write" && V["result"] == "disabled")  { WOFF[job] = 1 }
  else if ($5 == "W_pid_write" && V["result"] == "refused")   { WREF[job] = 1; nref++ }
  else if ($5 == "player_exit")  { RC[job] = V["rc"]; SIG[job] = V["killed_by_sig"];
                                   ALIVE[job] = V["alive_s"] }
  else if ($5 == "kill_attempt" && V["by"] == "worker-claim") {
                                   # the trace is sequential, so this belongs to the
                                   # job claimed on the line above
                                   WK[lastjob] = V["result"]; WKT[lastjob] = V["target"] }
  else if ($5 == "kill_attempt" && V["by"] == "election-sweep") {
                                   nsw++; SWT[nsw] = V["target"]; SWR[nsw] = V["result"]
                                   SWSITE[nsw] = V["site"] }
  else if ($5 == "worker_die")   { ndie++ }
  delete V
  next
}
END {
  # Reported, not silently dropped. The TSV schema is deliberately unchanged -- adding a
  # column would break every consumer -- so the count goes to stderr, where the callers
  # of this script already look for the completeness complaints below.
  if (nskip)
    printf "collect.sh: %d hook `record_skipped` row(s) in kills.log -- the hook refused a\n            player record on identity grounds. Not a kill and not a `nopid`; see the\n            raw kills.log, since no trials.tsv column carries it.\n", nskip > "/dev/stderr"
  # Unreachable: the shell guard at the top of this file rejects any run with a refused
  # publication before this awk starts. It is printed anyway, because the whole lesson of
  # this file is that an outcome nothing reports is an outcome nobody knows happened, and
  # a future edit that moves or weakens that guard must not make this silent again.
  if (nref)
    printf "collect.sh: %d W_pid_write row(s) with result=refused reached the parser. The\n            guard that rejects a refused publication did NOT run. These trials are\n            VOID and the W column for them is meaningless.\n", nref > "/dev/stderr"
  printf "config\ttrial\tR_a\tK_b\tR_b\tRdone_b\tS\tS2\tP\tW\tnewer_at_S2\tdiscarded\t"
  printf "player_pid\trc\tkilled_by_sig\talive_s\tplayer_log_sig\tpstart_to_pend_s\t"
  printf "p_start_ts\tp_end_ts\t"
  printf "hook_b_target\thook_b_result\t"
  printf "worker_claim_target\tworker_claim_result\tS_b\tordering\n"
  for (t = 1; t <= 99; t++) {
    ja = "j" t "a"; jb = "j" t "b"
    if (!(ja in S)) continue
    ra = M["t" t "a.R"]; kb = M["t" t "b.K"]; rb = M["t" t "b.R"]
    # the worker-claim kill that belongs to job jb is the one at S[jb]
    wct = "-"; wcr = "-"
    if (jb in WKT) { wct = WKT[jb]; wcr = WK[jb] }
    ord = "?"
    # rdb is the Rdone marker: stamped AFTER mv(1) returns, so publication is known
    # to have COMPLETED by then. Using rb (stamped BEFORE the rename) would count a
    # trial where P happened during the rename as adversarial, which it is not.
    rdb = M["t" t "b.Rdone"]
    if (DISC[ja]) ord = "R<S2 (recheck)"
    else if ((ja in P) && (ja in WOFF)) ord = "no pid record (clause i off)"
    else if ((ja in P) && (ja in WPLAYER)) ord = "record published by player"
    else if ((ja in P) && !(ja in W)) ord = "P<death<W (worker died in window)"
    else if (rdb != "" && (ja in W) && rdb+0 > W[ja]+0) ord = "W<R (hook sees live pid)"
    else if (rdb != "" && (ja in S2) && (ja in P) && (ja in W) && \
             rdb+0 > S2[ja]+0 && rdb+0 < P[ja]+0 && kb+0 < W[ja]+0) \
      ord = "R<S2<R_b<P<W (adversarial)"
    else ord = "other"
    # pstart_to_pend_s -- the stub player process own start-to-end interval, from the two
    # stamps carried beside it as p_start_ts and p_end_ts. It was called `audible_s` for
    # ten rounds and that name was wrong in the one place a consumer reads: the value is
    # a PROCESS interval logged by player_probe.py, which opens no audio device, so no
    # part of it is known to have been heard. Round 27 corrected the prose that quotes
    # this column and left the column asserting audibility on its own.
    #   0(never_started)  the stub logged no player_start. That bounds when the kill
    #                     landed -- inside interpreter startup -- and says nothing at all
    #                     about audio, here or in any other value of this column.
    #   unended           a start with no end line in the player log.
    prun = "-"
    if ((ja in PSTART) && (ja in PEND)) prun = sprintf("%.4f", PEND[ja] - PSTART[ja])
    else if (ja in PSTART) prun = "unended"
    else if (ja in P) prun = "0(never_started)"
    printf "%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
      cfg, t, ra, kb, rb, (rdb == "" ? "-" : rdb),
      (ja in S ? S[ja] : "-"), (ja in S2 ? S2[ja] : "-"),
      (ja in P ? P[ja] : "-"), (ja in W ? W[ja] : "-"),
      (ja in NEWER ? NEWER[ja] : "-"), (DISC[ja] ? 1 : 0),
      (ja in PPID ? PPID[ja] : "-"), (ja in RC ? RC[ja] : "-"),
      (ja in SIG ? SIG[ja] : "-"), (ja in ALIVE ? ALIVE[ja] : "-"),
      (ja in PSIG ? PSIG[ja] : "-"), prun,
      (ja in PSTART ? sprintf("%.6f", PSTART[ja]) : "-"),
      (ja in PEND ? sprintf("%.6f", PEND[ja]) : "-"),
      K["t" t "b.target"], K["t" t "b.result"], wct, wcr,
      (jb in S ? sprintf("%.6f", S[jb]) : "-"), ord
  }
}
' "$D/markers.tsv" "$MD/kills.log" "$D/player.log" "$D/worker.trace" > "$D/trials.tsv" \
  || { echo "collect.sh: the parser failed on $D -- trials.tsv is not usable" >&2; exit 2; }

# A trials.tsv with a header and no rows is a parse that matched nothing: the trace
# exists but carries no S_claim, so no trial was reconstructed. Callers append this file
# to the published evidence, so it must fail here rather than contribute nothing there.
#
# ROUND 15: `rows -lt 1` was only the ZERO case, and zero is the one shape this defect
# almost never takes. A run in which one worker claim is missing -- the worker died
# before `S_claim`, or its trace line was never flushed -- still writes every hook-side
# marker, so verify_fires.sh's entry/K/Rdone counts stay complete while this script
# reconstructs ELEVEN trials out of twelve, exits 0, and the caller appends eleven rows
# to the published evidence. The denominator shrinks and nothing anywhere says so.
#
# The count to check against is the hook side, because it is independent of the worker:
# every trial fires exactly one `t<N>a` hook, stamped BEFORE anything else happens, so
# the number of `t<N>a.entry` markers is the number of trials that were ATTEMPTED. It
# holds on all 21 committed configurations (12 = 12 on each). The `b` and `c` hooks are
# deliberately excluded: `b` is the preempting invocation and C14a/C14b fire a third,
# so only `a` counts trials.
rows=$(( $(wc -l < "$D/trials.tsv") - 1 ))
attempted=$(awk -F'\t' 'NR>1 && $2=="entry" && $1 ~ /^t[0-9]+a$/' "$D/markers.tsv" \
            | wc -l | tr -d ' ')
if [[ $rows -lt 1 ]]; then
  echo "collect.sh: no trials parsed out of $D -- wrote a header only." >&2
  exit 2
fi
if [[ ${attempted:-0} -lt 1 ]]; then
  echo "collect.sh: $D/markers.tsv has no t<N>a.entry markers, so the row count below" >&2
  echo "cannot be checked against anything. A run directory with no hook entries is" >&2
  echo "not a run." >&2
  exit 2
fi
if [[ $rows -ne $attempted ]]; then
  echo "collect.sh: $D reconstructed $rows trial(s) from $attempted hook entries." >&2
  # LEXICAL sort on both sides, not `sort -n`: comm merges with strcmp, so numerically
  # sorted input (2 before 10) makes it mis-pair and report differences that are not there.
  # The display is re-sorted numerically afterwards.
  awk -F'\t' 'NR>1 && $2=="entry" && $1 ~ /^t[0-9]+a$/ {print $1}' "$D/markers.tsv" \
    | sed 's/^t\([0-9]*\)a$/\1/' | sort > "$D/.attempted.tmp"
  awk -F'\t' 'NR>1 {print $2}' "$D/trials.tsv" | sort > "$D/.parsed.tmp"
  echo "trial numbers with a hook entry but NO row: $(comm -23 "$D/.attempted.tmp" "$D/.parsed.tmp" | sort -n | tr '\n' ' ')" >&2
  echo "trial numbers with a row but NO hook entry: $(comm -13 "$D/.attempted.tmp" "$D/.parsed.tmp" | sort -n | tr '\n' ' ')" >&2
  rm -f "$D/.attempted.tmp" "$D/.parsed.tmp"
  echo "Every trial fires one t<N>a hook before the worker sees the job, so a shortfall" >&2
  echo "is a trial that happened and was NOT reconstructed. Appending this file would" >&2
  echo "shrink the published denominator in silence." >&2
  exit 2
fi
wc -l < "$D/trials.tsv"
