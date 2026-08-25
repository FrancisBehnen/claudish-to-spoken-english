#!/bin/bash
# The two in-hook latencies that decide the race, per turn.
#
#   md_entry_to_publish  display hook entry -> assembled text on disk
#   stop_entry_to_read   Stop hook entry    -> buffer read
#   stop_abs_read        when Stop reads, measured from the DISPLAY hook's entry
#                        (= dispatch_gap + stop_entry_to_read)
#   margin               publish - stop_abs_read; negative means Stop read first
#
# The display hook must publish inside stop_abs_read to win. That is the budget
# any "publish immediately" repair has to fit into.
P="${PROBE_DIR:?PROBE_DIR must be set}"
printf 'tag\tmd_entry_to_publish_ms\tstop_entry_to_read_ms\tdispatch_gap_ms\tstop_abs_read_ms\tmargin_ms\n'
for f in "$P"/keep/*/analysis.txt; do
  [ -f "$f" ] || continue
  tag=$(basename "$(dirname "$f")")
  awk -v tag="$tag" '
    $2 ~ /^(MD|STOP)\./ && $1 ~ /^-?[0-9.]+$/ { t[$2]=$1+0; next }
    /^[0-9]+  mid=/ { if ($0 ~ /final=true/) fpid=$1; next }
    /^--- STOP\./ { split($2,sp,"."); spid=sp[2]; next }
    END {
      if (fpid=="" || spid=="") exit
      md0=t["MD." fpid ".t0"]; mdp=t["MD." fpid ".tpre"]
      st0=t["STOP." spid ".t0"]; rd=t["STOP." spid ".tread0"]
      if (mdp==0 || rd==0) exit
      pub=mdp-md0; rdl=rd-st0; gap=st0-md0; abs=gap+rdl
      printf "%s\t%.1f\t%.1f\t%+.1f\t%.1f\t%+.1f\n", tag, pub, rdl, gap, abs, pub-abs
    }
  ' "$f"
done
