#!/bin/bash
# Build one RUNS.txt naming exactly one run directory per configuration, WITHOUT
# copying anything.
#
# Copying is not an option here: the hook-side timestamps are the marker files' mtimes,
# and `cp -R` on macOS rewrites mtimes, which silently destroys every R/K/Rdone value.
# (That is not hypothetical -- an earlier version of this script did exactly that and
# produced trials.tsv rows whose hook timestamps were minutes away from their own
# worker trace.) So RUNS.txt points at the directories where the runs actually happened.
#
# AFFECTED holds the configurations re-run after the SIGHUP/nohup defect was found;
# they live in out/. Everything else is read from out-round2-sighup/, where its pgid
# sweep was irrelevant to the result.
#
# RIG here names the author's RUN TREE, not the rig's scripts: this walks the two
# output directories a completed run left behind, and those are not in the repository.
# Overridable so it can be pointed at another run.
set -u
RIG=${RIG:-$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25}
OLD=${OLD:-$RIG/out-round2-sighup}
NEW=${NEW:-$RIG/out}
AFFECTED=" C12a_pgid_pubfirst C12b_pgid_sweepfirst C13b_perplayer_sametiming
C16a_pending_sweepfirst C16b_pending_pubfirst C15c_norecheck_death_pgid
C17_setsid_player "
UNAFFECTED="C1_prespawn C2_hookside C3_adversarial C4_noclaimkill C5_norecheck
C6_handle C7_noreap C8_orphan C9_ledger C10a_nopid_pidfile C10b_nopid_handle
C11a_shared_pubfirst C11b_shared_sweepfirst C12c_perplayer_recordonly
C13a_ledger_truncate C14a_shared_unlink C14b_perplayer_unlink
C15a_recheck_death C15b_norecheck_death"

out="$RIG/RUNS.final"
: > "$out"

pick() {   # dir_glob [want] -> newest matching dir with a full set of entry markers.
  # 25 = 1 warm-up + 2 hooks x 12 trials; 37 = 1 + 3 x 12 for the C14 arms, which fire
  # a third hook so the TOCTOU's consequence is observed rather than inferred.
  local best="" b want=${2:-25}
  for b in $1; do
    [[ -d "$b" && -f "$b/worker.trace" ]] || continue
    [[ "$(ls "$b/markers" 2>/dev/null | grep -c '\.entry$')" -eq "$want" ]] || continue
    best="$b"
  done
  printf '%s\n' "$best"
}

# `pick` returns an empty string for a configuration with no run directory that has a
# FULL set of entry markers -- an absent run and a short one look the same from here --
# and `[[ -n $d ]] && printf` then dropped it without a word. The RUNS.txt that came out
# was shorter than the configuration list that went in, `wc` reported the shorter number
# as the result, and everything downstream took the file as the complete run set.
# Skipping is now named, counted, and fatal, on the same rule verify_fires.sh applies:
# silence about a configuration that is absent reads like confirmation that it ran.
absent=0
record() {   # config candidate_dir
  if [[ -z "$2" ]]; then
    echo "NO COMPLETE RUN: $1 has no run directory with a full marker set" >&2
    absent=$((absent + 1))
    return
  fi
  printf '%s\t%s\n' "$1" "$2" >> "$out"
}

for c in $UNAFFECTED; do
  case "$c" in
    C14a_*|C14b_*) d=$(pick "$NEW/$c-*" 37) ;;   # re-run with the third hook
    *)             d=$(pick "$OLD/$c-*") ;;
  esac
  record "$c" "$d"
done
for c in $AFFECTED; do
  d=$(pick "$NEW/$c-*")
  record "$c" "$d"
done
if [[ $absent -gt 0 ]]; then
  echo "INCOMPLETE: $absent configuration(s) have no complete run -- RUNS.txt would" >&2
  echo "name fewer configurations than this script was asked to gather. Re-run them," >&2
  echo "or set ALLOW_INCOMPLETE=1 to gather a partial set deliberately." >&2
  [[ ${ALLOW_INCOMPLETE:-0} = 1 ]] || exit 2
  echo "WARNING: gathering an INCOMPLETE set because ALLOW_INCOMPLETE=1" >&2
fi
sort "$out" -o "$out"
cp "$out" "$NEW/RUNS.txt" || { echo "gather_out.sh: could not write $NEW/RUNS.txt" >&2; exit 2; }
wc -l < "$out"
