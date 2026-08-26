#!/bin/bash
# Turn the REAL-* worker traces into a structured evidence file, so section 2.6's
# figures re-derive like every other figure instead of being read off a trace by eye.
# Round 1 had no such file, which made the PR's "every published figure re-derives"
# claim false. Review comment on summarise.sh:2.
#
# One row per trial. The stale player is job jNa, the newer one jNb.
#
#   timerstart_to_exit_s  the probe's `alive_s`. CORRECTED LABEL, round 5: its timer
#             starts at t_popen, which speakd_probe.py stamps BEFORE subprocess.Popen,
#             so it includes the fork/exec launch latency and is an UPPER bound on how
#             long the process existed. It was published as "Popen -> exit", which it
#             is not: on the committed REAL-pidfile rows the two differ by ~7x.
#   popen_to_exit_s  p_exit - p_popen, both worker-trace record stamps, so this is the
#             interval from Popen RETURNING to the reap -- a LOWER bound on the same
#             lifetime, because the child was forked during the Popen this excludes.
#             Neither is "time audible": nothing here listens (see the doc's §2.6).
#   sig       what killed it (0 = ran to completion)
#   overlap_s for an arm where nothing kills the stale player: how long the two
#             players were alive at the same time. "-" when the stale one was killed.
#
# <out_dir> may hold either the run directories a fresh run produces (REAL-<arm>-<ts>/
# with a worker.trace inside) or the flat committed traces (REAL-<arm>.worker.trace),
# so the committed real-audio-trials.tsv re-derives from the repository alone.
#
# usage: collect_real.sh <out_dir> <dest_dir>
set -u
O=${1:?out dir}; DEST=${2:?dest}
mkdir -p "$DEST"
{
  printf 'arm\ttrial\tp_popen\tp_exit\ttimerstart_to_exit_s\tkilled_by_sig\toverlap_s\tpopen_to_exit_s\n'
  for d in "$O"/REAL-*; do
    if [[ -d "$d" ]]; then
      trace="$d/worker.trace"; arm=$(basename "$d"); arm=${arm%-*}
    elif [[ "$d" == *.worker.trace && -f "$d" ]]; then
      trace="$d"; arm=$(basename "$d" .worker.trace)
    else
      continue
    fi
    [[ -f "$trace" ]] || continue
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
          printf "%s\t%d\t%.6f\t%s\t%s\t%s\t%s\t%s\n", arm, t, POP[ja],
                 (ja in EX ? sprintf("%.6f", EX[ja]) : "-"),
                 (ja in LIFE ? LIFE[ja] : "-"),
                 (ja in SIG ? SIG[ja] : "-"), ov,
                 (ja in EX ? sprintf("%.6f", EX[ja] - POP[ja]) : "-")
        }
      }' "$trace"
  done
} > "$DEST/real-audio-trials.tsv"
# A header and nothing else is not a successful collection -- it is the null-as-pass
# failure again, on the evidence section E is derived from. Require a data row.
rows=$(( $(wc -l < "$DEST/real-audio-trials.tsv") - 1 ))
if [[ $rows -lt 1 ]]; then
  echo "collect_real.sh: no real-audio trials matched in $SRC -- wrote a header only." >&2
  echo "This is NOT a successful collection; section E would silently vanish." >&2
  exit 2
fi
echo "$rows data rows"
wc -l < "$DEST/real-audio-trials.tsv"
