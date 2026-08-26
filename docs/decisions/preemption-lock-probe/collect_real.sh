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
# failure again, on the evidence section E is derived from.
#
# ONE data row is too weak a bar, and the weak version of this guard was itself an
# instance of the defect it was written against: a partial experiment -- one REAL-off
# trial with the whole REAL-pidfile arm missing -- passed it, and summarise.sh then
# printed a one-armed section E and exited 0. Section E is a COMPARISON (the stale
# player runs to completion with the claim-time kill off; it dies in milliseconds with
# it on), so one arm cannot support it and unequal arms make the two columns
# incomparable. Require BOTH arms, non-empty, with the same number of trials.
#
# The failure path below also used to interpolate $SRC, which is not a variable this
# script has -- under `set -u` it died with "unbound variable" instead of printing the
# actionable message. A guard whose failure path crashes is the same defect one layer in.
n_off=$(awk -F'\t' 'NR > 1 && $1 == "REAL-off"' "$DEST/real-audio-trials.tsv" | wc -l | tr -d ' ')
n_pid=$(awk -F'\t' 'NR > 1 && $1 == "REAL-pidfile"' "$DEST/real-audio-trials.tsv" | wc -l | tr -d ' ')
rows=$(( $(wc -l < "$DEST/real-audio-trials.tsv") - 1 ))
# Equality alone is not the published shape. The experiment is THREE trials per arm, so
# one `off` and one `pidfile` satisfies "both arms, equal, non-zero" and would then be
# summarised as the documented result over a third of the evidence. REAL_TRIALS is the
# expected denominator; override it deliberately if a future run uses a different one.
REAL_TRIALS=${REAL_TRIALS:-3}
if [[ $n_off -ne $REAL_TRIALS || $n_pid -ne $REAL_TRIALS ]]; then
  echo "collect_real.sh: expected BOTH real-audio arms at exactly $REAL_TRIALS trials each," >&2
  echo "  but $O yielded REAL-off=$n_off REAL-pidfile=$n_pid (total data rows: $rows)." >&2
  echo "This is NOT a successful collection; section E would be derived over a short" >&2
  echo "denominator while still looking complete. Set REAL_TRIALS to change the expectation." >&2
  exit 2
fi
# run_real.sh only takes `pidfile` or `off`, so anything else under REAL-* is a name
# this collector does not understand -- and dropping it silently is how a third arm
# would go unpublished while the file still looked complete.
if [[ $rows -ne $(( n_off + n_pid )) ]]; then
  echo "collect_real.sh: $(( rows - n_off - n_pid )) row(s) in $O belong to neither arm:" >&2
  awk -F'\t' 'NR > 1 && $1 != "REAL-off" && $1 != "REAL-pidfile" {print "  " $1}' \
    "$DEST/real-audio-trials.tsv" | sort -u >&2
  exit 2
fi
echo "$rows data rows (REAL-off=$n_off REAL-pidfile=$n_pid)"
wc -l < "$DEST/real-audio-trials.tsv"
