#!/bin/bash
# Turn one run directory into two committed evidence files, then join them with awk.
#
#   markers.tsv   the hook-side timestamps, read out of the marker files with
#                 `stat -f %Fm` (the fork-free technique the residency run
#                 validated to ~90 us against $EPOCHREALTIME)
#   trials.tsv    one row per trial, joining markers.tsv with worker.trace
#
# Everything published derives from trials.tsv with awk/sort and nothing else.
#
# usage: collect.sh <rundir> <config>
set -u
D=${1:?rundir}; CFG=${2:?config}
MD="$D/markers"

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
  split($5, f, " ")
  for (i in f) { split(f[i], kv, "="); K[$1 "." kv[1]] = kv[2] }
  next
}
FILENAME ~ /player\.log$/ {
  # ts pid tag kind fields   -- the player own view (cross-check). Cross-checks rc, and gives
  # the audible start (a player killed before this line was never audible at all).
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
  else if ($5 == "W_pid_write" && V["by"] == "player") { WPLAYER[job] = 1; W[job] = $1 }
  else if ($5 == "W_pid_write" && V["result"] != "disabled") { W[job] = $1 }
  else if ($5 == "W_pid_write") { WOFF[job] = 1 }
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
  printf "config\ttrial\tR_a\tK_b\tR_b\tRdone_b\tS\tS2\tP\tW\tnewer_at_S2\tdiscarded\t"
  printf "player_pid\trc\tkilled_by_sig\talive_s\tplayer_log_sig\taudible_s\t"
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
    aud = "-"
    if ((ja in PSTART) && (ja in PEND)) aud = sprintf("%.4f", PEND[ja] - PSTART[ja])
    else if (ja in PSTART) aud = "unended"
    else if (ja in P) aud = "0(never_started)"
    printf "%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
      cfg, t, ra, kb, rb, (rdb == "" ? "-" : rdb),
      (ja in S ? S[ja] : "-"), (ja in S2 ? S2[ja] : "-"),
      (ja in P ? P[ja] : "-"), (ja in W ? W[ja] : "-"),
      (ja in NEWER ? NEWER[ja] : "-"), (DISC[ja] ? 1 : 0),
      (ja in PPID ? PPID[ja] : "-"), (ja in RC ? RC[ja] : "-"),
      (ja in SIG ? SIG[ja] : "-"), (ja in ALIVE ? ALIVE[ja] : "-"),
      (ja in PSIG ? PSIG[ja] : "-"), aud,
      (ja in PSTART ? sprintf("%.6f", PSTART[ja]) : "-"),
      (ja in PEND ? sprintf("%.6f", PEND[ja]) : "-"),
      K["t" t "b.target"], K["t" t "b.result"], wct, wcr,
      (jb in S ? sprintf("%.6f", S[jb]) : "-"), ord
  }
}
' "$D/markers.tsv" "$MD/kills.log" "$D/player.log" "$D/worker.trace" > "$D/trials.tsv"
wc -l < "$D/trials.tsv"
