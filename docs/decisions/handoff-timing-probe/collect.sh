#!/bin/bash
# Emit the runs table as TSV, one row per captured turn, by parsing each run's
# analysis.txt (base_epoch + per-marker rel_ms).
#
# Parse analysis.txt rather than the preserved marker files: `cp` without -p
# rewrites mtimes and would silently flatten every interval to zero.
#
# Staleness is decided by comparing the bracketed snapshot's first 70 chars
# against Stop's own .last_assistant_message -- ground truth from the payload.
P="${PROBE_DIR:?PROBE_DIR must be set}"
printf 'tag\tregime\tchunks\tdispatch_gap_ms\tstop_start_minus_md_return_ms\tmd_hook_dur_ms\tread_vs_immediate_publish_ms\tread_vs_slow_publish_ms\tbuf_immediate\tbuf_slow\n'
for f in "$P"/keep/*/analysis.txt; do
  [ -f "$f" ] || continue
  tag=$(basename "$(dirname "$f")")
  awk -v tag="$tag" '
    $2 ~ /^(MD|STOP)\./ && $1 ~ /^-?[0-9.]+$/ { t[$2]=$1+0; next }
    /^[0-9]+  mid=/ { if ($0 ~ /final=true/) fpid=$1; nch++; next }
    /^--- STOP\./ { split($2,sp,"."); spid=sp[2]; next }
    /^pre_head/  { sub(/^pre_head[ ]+/,"");  preh=$0; next }
    /^post_head/ { sub(/^post_head[ ]+/,""); posth=$0; next }
    /^stop_lam/  { sub(/^stop_lam[ ]+/,"");  lam=$0; next }
    END {
      if (fpid=="" || spid=="") { printf "%s\tINCOMPLETE\n", tag; exit }
      md0=t["MD." fpid ".t0"];   md2=t["MD." fpid ".t2"]
      mdp=t["MD." fpid ".tpre"]; mdq=t["MD." fpid ".tpost"]
      st0=t["STOP." spid ".t0"]; rd=t["STOP." spid ".tread0"]
      reg = ((md2-md0) > 1000) ? "hold4" : "control"
      pf = (lam=="") ? "NA" : ((preh==lam)  ? "fresh" : "STALE")
      qf = (lam=="") ? "NA" : ((posth==lam) ? "fresh" : "STALE")
      printf "%s\t%s\t%d\t%+.1f\t%+.1f\t%.1f\t%+.1f\t%+.1f\t%s\t%s\n",
        tag, reg, nch, st0-md0, st0-md2, md2-md0, rd-mdp, rd-mdq, pf, qf
    }
  ' "$f"
done
