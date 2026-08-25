#!/bin/bash
# Turn the REAL-* worker traces into a structured evidence file, so section 2.6's
# figures re-derive like every other figure instead of being read off a trace by eye.
# Round 1 had no such file, which made the PR's "every published figure re-derives"
# claim false. Review comment on summarise.sh:2.
#
# One row per trial. The stale player is job jNa, the newer one jNb.
#   life_s    how long the stale player's process existed (Popen -> exit)
#   sig       what killed it (0 = ran to completion)
#   overlap_s for an arm where nothing kills the stale player: how long the two
#             players were alive at the same time. "-" when the stale one was killed.
#
# usage: collect_real.sh <out_dir> <dest_dir>
set -u
O=${1:?out dir}; DEST=${2:?dest}
mkdir -p "$DEST"
{
  printf 'arm\ttrial\tp_popen\tp_exit\tlife_s\tkilled_by_sig\toverlap_s\n'
  for d in "$O"/REAL-*; do
    [[ -d "$d" ]] || continue
    arm=$(basename "$d"); arm=${arm%-*}
    awk -F'\t' -v arm="$arm" '
      { n = split($6, f, " "); delete V
        for (i = 1; i <= n; i++) { split(f[i], kv, "="); V[kv[1]] = kv[2] } }
      $5 == "P_popen"     { POP[V["job"]] = $1 }
      $5 == "player_exit" { EX[V["job"]] = $1; SIG[V["job"]] = V["killed_by_sig"];
                            LIFE[V["job"]] = V["alive_s"] }
      END {
        for (t = 1; t <= 99; t++) {
          ja = "j" t "a"; jb = "j" t "b"
          if (!(ja in POP)) continue
          ov = "-"
          # the stale player overlapped the newer one only if it was still alive
          # when the newer one was spawned and nothing had killed it
          if (SIG[ja] == "0" && (jb in POP) && (ja in EX) && EX[ja] > POP[jb])
            ov = sprintf("%.4f", EX[ja] - POP[jb])
          printf "%s\t%d\t%.6f\t%s\t%s\t%s\t%s\n", arm, t, POP[ja],
                 (ja in EX ? sprintf("%.6f", EX[ja]) : "-"),
                 (ja in LIFE ? LIFE[ja] : "-"),
                 (ja in SIG ? SIG[ja] : "-"), ov
        }
      }' "$d/worker.trace"
  done
} > "$DEST/real-audio-trials.tsv"
wc -l < "$DEST/real-audio-trials.tsv"
