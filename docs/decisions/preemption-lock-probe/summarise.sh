#!/bin/bash
# The published figures THAT LIVE IN THE COMMITTED TSVs, re-derived with awk and sort
# only. That is sections A-F below and nothing else.
#
# ROUND 16 -- THIS LINE USED TO READ "Every published figure, re-derived from the
# committed TSVs", AND THAT WAS FALSE. The aggregate TSVs are one row per TRIAL, and
# several published figures are counts of trace EVENTS that no TSV column carries:
# `record_unlinked`, `pending_found`/`pending_created`, and the sweep-skip events. So
#
#   * C14a's "8 record destructions across 4 trials",
#   * the C15c/C16 25-election `killpg`-skipped counts, and
#   * every other statement about what a sweep DID rather than what a player's exit
#     status WAS,
#
# are derivable only by `analyse_round2.sh preemption-lock-probe/traces`, over the
# committed raw traces. The two derivations are disjoint and both are required; neither
# is a check on the other. The decision document draws the same boundary in section 1
# and this script now agrees with it, because "every figure re-derives" is the premise
# the whole document rests on and a script that overstates its own coverage is the
# quietest way for that premise to stop being true.
#
# Two things this script gets right that round 1 got wrong, both found in review:
#  * MEDIAN. macOS awk is BWK awk and has no asort(), so percentiles come from a
#    `sort -n` pipeline. Round 1 then took v[int((NR+1)/2)], which is the LOWER
#    MIDDLE observation, not the median. Every sample here is even-sized, so that
#    silently disagreed with the published medians. `med()` below averages the two
#    middle observations.
#  * REAL-AUDIO. Round 1 had no input for the REAL-* traces, so it could not
#    re-derive section 2.6. `real-audio-trials.tsv` is now a committed evidence file
#    and section E summarises it.
#
# Two more added in round 3's review, both because the document quoted a figure this
# script did not print, which is the same defect one level down:
#  * The Rdone->P adversarial margin (section F). It was quoted in the text as the
#    reason the corrected predicate was never close to binding, with no derivation.
#  * The P->W window SPLIT BY WHO PUBLISHED (section C). For a player-published
#    record the probe stamps W in the PARENT immediately after Popen, before the
#    wrapper has slept or renamed, so those samples are not a publication instant at
#    all. They must not be pooled with the worker-published ones -- harness defect 4.
#
# usage: summarise.sh <evidence_dir>
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
E=${1:?evidence dir}
P="$E/preemption-trials.tsv"
L="$E/lock-owners.tsv"
R="$E/real-audio-trials.tsv"

# The row-20 and row-21 inputs are checked HERE, before any of them is read. awk prints
# "can't open file" and returns 2 to a script with no `set -e`, so a missing $P or $L
# used to leave every section below printing its heading and no rows -- and this script,
# which IS the advertised re-derivation of every published figure, exited 0 having
# derived none of them. $R keeps its own softer path further down only because it
# reports the omission and fails at the end.
for f in "$P" "$L"; do
  if [[ ! -f $f ]]; then
    echo "summarise.sh: missing $f -- nothing below it can be re-derived." >&2
    exit 2
  fi
  if [[ $(wc -l < "$f") -lt 2 ]]; then
    echo "summarise.sh: $f has a header and no data rows." >&2
    echo "Every figure below would print as an empty section. This is NOT a pass." >&2
    exit 2
  fi
done

# ROUND 19. THE ROW-20 DENOMINATOR HAD THE SAME GAP, and it was left behind when round
# 17 closed row 21's -- an asymmetry with no justification: removing one trial, or a whole
# configuration, from preemption-trials.tsv still exited 0 and recomputed EVERY row-20
# rate over a smaller denominator. The manifest already exists (expected-configs.txt is
# what verify_fires.sh checks hook markers against), so the same 26 names are the
# expectation here, at 12 trials each.
P_MANIFEST=${P_MANIFEST:-$HERE/expected-configs.txt}
P_TRIALS=${P_TRIALS:-12}
if [[ -f $P_MANIFEST ]]; then
  p_missing=$(awk -F'\t' -v man="$P_MANIFEST" -v want="$P_TRIALS" '
    BEGIN { while ((getline L < man) > 0) { sub(/[ \t]*#.*/, "", L); gsub(/[ \t]/, "", L)
                                            if (L != "") EXP[L]=1 } }
    # Counting DISTINCT (config, trial) keys is not the same as validating the shape:
    # a duplicated row collapses to the same key, so n[c] still reaches 12 while every
    # summary below counts the row twice. And "12 distinct ids" accepts 1..11 plus 13.
    # So: count rows, reject repeats, and require each id to be an integer in 1..want.
    NR>1 { seen[$1]=1; rows[$1]++
           k=$1 SUBSEP $2
           if (k in T) DUP[$1] = DUP[$1] " " $2; else { T[k]=1; n[$1]++ }
           if ($2 !~ /^[0-9]+$/ || $2+0 < 1 || $2+0 > want) BADID[$1] = BADID[$1] " " $2 }
    END { bad=0
          for (c in EXP) { if (!(c in seen)) { printf "  MISSING configuration: %s\n", c > "/dev/stderr"; bad++ ; continue }
                           if (n[c] != want) { printf "  SHORT %s: %d distinct trials, expected %d\n", c, n[c], want > "/dev/stderr"; bad++ }
                           if (rows[c] != want) { printf "  ROW COUNT %s: %d rows for %d trials\n", c, rows[c], want > "/dev/stderr"; bad++ }
                           if (c in DUP) { printf "  DUPLICATE trial rows in %s:%s\n", c, DUP[c] > "/dev/stderr"; bad++ }
                           if (c in BADID) { printf "  TRIAL ID out of 1..%d in %s:%s\n", want, c, BADID[c] > "/dev/stderr"; bad++ } }
          for (c in seen) if (!(c in EXP)) { printf "  UNEXPECTED configuration: %s\n", c > "/dev/stderr"; bad++ }
          print bad+0 }' "$P")
  if [[ ${p_missing:-1} -ne 0 ]]; then
    echo "summarise.sh: row-20 evidence does not match the manifest ($p_missing problem(s))." >&2
    echo "Every rate below would be computed over a different denominator than the one" >&2
    echo "the document quotes. This is NOT a re-derivation." >&2
    exit 2
  fi
else
  # A warning is not a guard, and this script fixed exactly that shape in verify_fires.sh
  # two revisions ago before reintroducing it here. The manifest is the ONLY independent
  # definition of the expected 26 configurations, so without it a truncated
  # preemption-trials.tsv produces summaries and exits 0 -- defeating the check above by
  # removing one file. Fail closed, with a named override, as verify_fires.sh does.
  echo "summarise.sh: no manifest at $P_MANIFEST -- the row-20 denominator CANNOT be" >&2
  echo "checked, so this is NOT a re-derivation. Set ALLOW_NO_MANIFEST=1 to accept an" >&2
  echo "unchecked run deliberately." >&2
  [[ ${ALLOW_NO_MANIFEST:-0} = 1 ]] || exit 2
  echo "WARNING: proceeding with an UNCHECKED row-20 denominator (ALLOW_NO_MANIFEST=1)" >&2
fi

# ROUND 17. THE ROW-21 DENOMINATOR WAS NEVER VALIDATED, ONLY CHECKED FOR EMPTINESS.
# The loop above rejects a lock-owners.tsv with no data rows and accepts every other
# shape, and assemble.sh (:63) copies the file into place without looking at it either.
# So a run that was interrupted, or that lost an entire protocol or scenario cell,
# re-derives the advertised "1200 trials / 400 per protocol" result over a SMALLER
# denominator and still prints a clean summary under the same headings. That is the
# same null-as-pass shape the VOID check further down closed for staging failures,
# one level up: at the shape of the matrix rather than at the outcome of a cell.
#
# THE EXPECTED MATRIX IS NOT DERIVED FROM THE FILE BEING VALIDATED. Deriving it there
# would make the check vacuous -- a truncated file would derive a truncated expectation
# and pass itself. It is transcribed from run_lock.sh's driver loop (:352-368) and the
# `emit` call in each trial function, which together ARE the committed definition of
# the run:
#
#   for pr in current spec proposed                          3 protocols  (:352)
#     S1_init         N in 2 4 8   x stall in 0 5 50         9 cells      (:353-356)
#     S2_longstall    N = 4        x stall in 200 1000       2 cells      (:358-359)
#     S3_aba          N = 2, stall = 0  -- trial_aba  emits `2 0` (:273)  1 cell
#     S4_dualreclaim  N = 2, stall = 0  -- trial_dual emits `2 0` (:302)  1 cell
#     S5_scratch      N in 2 4 8 16, stall = 0              (:320)        4 cells
#     S6_deadN        N in 2 4 8,    stall = 0              (:349)        3 cells
#     x REPS reps each, REPS = 20                           (:44 default)
#
# 20 cells x 20 reps = 400 trials per protocol, x3 protocols = 1200 rows. Those are the
# numbers the document quotes, and they are now a PRECONDITION for printing them rather
# than a claim about a file nobody read.
#
# REPS is a constant here and is deliberately NOT read from the data. A uniformly
# half-length run would otherwise derive REPS=10 from itself and pass with a 600-row
# denominator, which is exactly the failure this check exists to catch. A run at a
# different rep count is a different result and must not print under these headings
# without editing this line and saying so in the document.
#
# VOID rows COUNT toward the matrix: a VOID trial was attempted and occupies its rep
# slot, so it is a cell that was measured and failed, not a cell that is missing. The
# VOID check below is what refuses those, and the two checks stay orthogonal.
#
# The design is one line per scenario, `scenario:N,...:stall,...`, separated by `;`.
# NOT by newlines: BWK awk (which is /usr/bin/awk on Darwin, the platform every trace
# here was taken on) rejects a literal newline inside a `-v` assignment with "newline
# in string" and produces NO OUTPUT AT ALL. An empty report reads as "no defects
# found", so the first draft of this very check passed the committed evidence by
# failing to run. That is why the `=`-line is mandatory below.
LOCK_REPS=20
LOCK_PROTOCOLS='current spec proposed'
LOCK_DESIGN='S1_init:2,4,8:0,5,50;S2_longstall:4:200,1000;S3_aba:2:0;S4_dualreclaim:2:0;S5_scratch:2,4,8,16:0;S6_deadN:2,4,8:0'

# awk emits one `!`-prefixed line per defect and one `=`-prefixed line describing the
# matrix it validated. The leading digit is a sort key only, so the report is stable.
lock_matrix=$(awk -F'\t' -v reps="$LOCK_REPS" -v protos="$LOCK_PROTOCOLS" -v design="$LOCK_DESIGN" '
  BEGIN {
    np = split(protos, P, /[ \t]+/)
    nd = split(design, D, ";")
    for (d = 1; d <= nd; d++) {
      if (D[d] == "") continue
      split(D[d], F, ":")
      nn = split(F[2], NN, ",")
      ns = split(F[3], SS, ",")
      for (p = 1; p <= np; p++)
        for (a = 1; a <= nn; a++)
          for (b = 1; b <= ns; b++) {
            EXP[P[p] SUBSEP F[1] SUBSEP NN[a] SUBSEP SS[b]] = reps
            cells++; want += reps
          }
    }
    scen = nd
  }
  NR == 1 { next }
  {
    k = $2 SUBSEP $1 SUBSEP $3 SUBSEP $4
    SEEN[k]++; rows++
    if (!(k in EXP)) { UNEXP[k]++; next }
    # A rep outside 1..REPS, or a repeated one, means two runs were merged or a run was
    # resumed over itself. Either way the cell is not REPS independent trials even when
    # it has REPS rows, so counting rows alone would not catch it.
    if ($5 !~ /^[0-9]+$/ || $5 + 0 < 1 || $5 + 0 > reps) BADREP[k] = BADREP[k] " " $5
    else if (++R[k SUBSEP ($5 + 0)] > 1)                 DUPREP[k] = DUPREP[k] " " $5
  }
  END {
    for (k in EXP) {
      split(k, A, SUBSEP)
      n = SEEN[k] + 0
      if (n == 0)
        printf "!1 MISSING CELL   %-9s %-15s N=%-3s stall=%-5s -- expected %d trial(s), found none\n", A[1], A[2], A[3], A[4], EXP[k]
      else if (n != EXP[k])
        printf "!2 SHORT/LONG     %-9s %-15s N=%-3s stall=%-5s -- expected %d trial(s), found %d\n", A[1], A[2], A[3], A[4], EXP[k], n
      if (k in BADREP)
        printf "!3 REP OUT OF 1-%d %-9s %-15s N=%-3s stall=%-5s --%s\n", reps, A[1], A[2], A[3], A[4], BADREP[k]
      if (k in DUPREP)
        printf "!4 REPEATED REP   %-9s %-15s N=%-3s stall=%-5s --%s\n", A[1], A[2], A[3], A[4], DUPREP[k]
    }
    for (k in UNEXP) {
      split(k, A, SUBSEP)
      printf "!5 NOT IN DESIGN  %-9s %-15s N=%-3s stall=%-5s -- %d row(s) the run never emits\n", A[1], A[2], A[3], A[4], UNEXP[k]
    }
    printf "=0 row-21 matrix: %d protocols x %d scenarios = %d cells x %d reps = %d trials (found %d rows)\n",
           np, scen, cells, reps, want, rows + 0
  }' "$L" | sort)

lock_defects=$(printf '%s\n' "$lock_matrix" | sed -n 's/^!. //p')
lock_shape=$(printf '%s\n' "$lock_matrix"   | sed -n 's/^=. //p')

# FAIL CLOSED. The `=`-line is unconditional in the END block above, so its ABSENCE
# means the awk did not reach END: it aborted, or it never started. An empty report is
# then indistinguishable from a clean one, and "clean" is the reading that lets a bad
# denominator through -- which is what this whole check exists to prevent. A check that
# passes when it cannot run is not a check.
if [[ -z $lock_shape ]]; then
  echo "summarise.sh: the row-21 matrix check produced no result over $L." >&2
  echo "Its awk did not reach END, so NOTHING was validated. An empty report is not a" >&2
  echo "clean one. Refusing to print figures whose denominator was never checked." >&2
  exit 2
fi

if [[ -n $lock_defects ]]; then
  echo "summarise.sh: $L does not match the experimental design run_lock.sh implements." >&2
  printf '%s\n' "$lock_defects" >&2
  echo "$lock_shape" >&2
  echo "Row 21's published figures are per-protocol rates over a 400-trial denominator." >&2
  echo "With a cell missing or short, the rates below would be computed over a smaller" >&2
  echo "or a differently-weighted denominator and would still print as a clean summary." >&2
  echo "That is NOT a re-derivation of the published result. Re-run the named cells." >&2
  exit 2
fi

# One definition of median, reused by every block below. Reads numbers on stdin.
MED='function med(v, n) { if (n % 2) return v[(n + 1) / 2]; return (v[n / 2] + v[n / 2 + 1]) / 2 }'

stats() {   # label < numbers-on-stdin
  sort -n | awk "$MED"'{v[NR] = $1} END { if (NR) printf "%-28s n=%-4d min=%-11.4f med=%-11.4f max=%.4f\n", L, NR, v[1], med(v, NR), v[NR] }' L="$1"
}

# The kill-attribution rule. It USED TO BE DEFINED HERE, and that was the whole
# problem: compare_passes.sh and peek_one.sh each carried their own copy of the same
# rule over the same two columns, round 16 fixed this one, and both of the others were
# still wrong thirteen rounds later. It now lives in attrib.sh and all three call it,
# so it cannot be fixed in one place again. The rule itself is unchanged and section A
# below is byte-identical.
if [[ ! -f "$HERE/attrib.sh" ]]; then
  echo "summarise.sh: missing $HERE/attrib.sh -- the attribution rule lives there and" >&2
  echo "section A cannot be derived without it. Refusing to print a summary with the" >&2
  echo "kill attribution silently absent." >&2
  exit 2
fi
# shellcheck source=attrib.sh
. "$HERE/attrib.sh"
# A sourced file that failed to define what it exists to define must not read as a pass:
# `awk ""` is a legal empty program, so an unset ATTRIB would make section A print one
# blank attribution per row rather than fail.
if [[ -z ${ATTRIB:-} ]]; then
  echo "summarise.sh: $HERE/attrib.sh defined no ATTRIB -- section A would print a blank" >&2
  echo "attribution for every row and still exit 0. Refusing." >&2
  exit 2
fi

echo "== ROW 20 / A: which step killed the player, per configuration =="
awk -F'\t' "$ATTRIB"'
$1=="config"{next}
{ printf "%s\t%s\t%s\n", $1, attrib($14,$17,$13,$18), $26 }' "$P" \
  | sort | uniq -c | awk '{printf "%-4s %-22s %-24s %s\n", $1"x", $2, $3, $4" "$5" "$6" "$7" "$8}'

echo
echo "== ROW 20 / B: how long the stale PLAYER PROCESS ran, per configuration =="
echo "   pstart_to_pend_s = the stale player process own start-to-end interval, as the"
echo "   stub logged it (p_end_ts - p_start_ts). Renamed from audible_s in round 28: the"
echo "   player here is player_probe.py, which opens NO AUDIO DEVICE at any point, so no"
echo "   part of any value in this column is known to have been heard. That holds for the"
echo "   nonzero values as much as for the zero one."
echo "   0(never_started) means ONLY that the stub logged no player_start -- the kill"
echo "   landed inside interpreter startup. It bounds WHEN the kill arrived. It is NOT a"
echo "   finding that nothing was audible, because audibility was never observed here."
for c in $(awk -F'\t' '$1!="config"{print $1}' "$P" | sort -u); do
  awk -F'\t' -v c="$c" '$1==c {print $18}' "$P" | sort -n \
    | awk "$MED"'
      /^[0-9][0-9.]*$/ { v[++n]=$1+0; next }
      { other[$0]++ }
      END {
        line = sprintf("%-20s ", c)
        if (n) line = line sprintf("n=%-3d min=%.4f med=%.4f max=%.4f  ", n, v[1], med(v, n), v[n])
        for (k in other) line = line sprintf("[%s x%d] ", k, other[k])
        print line
      }' c="$c"
done

echo
echo "== ROW 20 / C: window widths, ms =="
# P->W, three ways. The pooled figure is NOT the one to quote: in a player-published
# arm the probe stamps W in the parent right after Popen (speakd_probe.py, the
# `by=player result=deferred_to_player` branch), so the sample is the Popen return
# rather than the record's publication. Only the worker-published arms measure the
# real window.
awk -F'\t' '$1=="config"{next} $9!="-" && $10!="-" {printf "%.4f\n", ($10-$9)*1000}'  "$P" | stats "P->W_pooled_DO_NOT_QUOTE"
awk -F'\t' '$1=="config"{next} $9!="-" && $10!="-" && $26!="record published by player" {printf "%.4f\n", ($10-$9)*1000}' "$P" | stats "P->W_worker_published"
awk -F'\t' '$1=="config"{next} $9!="-" && $10!="-" && $26=="record published by player" {printf "%.4f\n", ($10-$9)*1000}' "$P" | stats "P->W_player_SYNTHETIC"
awk -F'\t' '$1=="config"{next} $7!="-" && $8!="-"  {printf "%.4f\n", ($8-$7)*1000}'   "$P" | stats "S->S2_claim_to_prespawn"
awk -F'\t' '$1=="config"{next} $4!="-" && $5!="-"  {printf "%.4f\n", ($5-$4)*1000}'   "$P" | stats "K->R_hook_kill_to_rename"
awk -F'\t' '$1=="config"{next} $5!="-" && $6!="-"  {printf "%.4f\n", ($6-$5)*1000}'   "$P" | stats "R->Rdone_rename_itself"
awk -F'\t' '$1=="config"{next} $17=="15" && $20!="-" && $4!="-" {printf "%.4f\n", ($20-$4)*1000}' "$P" | stats "hook_kill->player_death"

echo
echo "== ROW 20 / D: what the hook-side pid kill actually buys, ms =="
echo "   (C2: the player died at the hook kill. Without clause (i) the worker's"
echo "    claim-time kill would have reached it at S_b instead.)"
awk -F'\t' '$1=="C2_hookside" && $25!="-" && $4!="-" {printf "%.4f\n", ($25-$4)*1000}' "$P" | stats "S_b - K_b"

echo
echo "== ROW 20 / E: the real-audio arms =="
echo "   TWO bounds on the stale player's lifetime, not one, and the document quotes the"
echo "   UPPER one. Round 3 published \`alive_s\` as \"Popen -> exit\"; it is not. Its timer"
echo "   starts before subprocess.Popen, so it INCLUDES the fork/exec launch latency, which"
echo "   on the claim-kill arm is MOST of the published figure. The two columns"
echo "   of the same row differ by roughly 7x. Both are printed here so neither can be"
echo "   quoted as the other:"
echo "     timerstart_to_exit_s  upper bound; timer starts before Popen"
echo "     popen_to_exit_s       lower bound; the child was forked inside the Popen this"
echo "                           excludes. Neither is a measure of AUDIBILITY."
echo "     overlap_s             ROUND 27: an UPPER BOUND on how long the two player"
echo "                           PROCESSES existed at once -- reap stamp of the stale one"
echo "                           minus P_popen of the newer one, so BOTH ends over-count."
echo "                           This line was missing while the document quoted the"
echo "                           number as 'two utterances overlapped'. It is not a"
echo "                           measure of AUDIBILITY either: NOTHING IN THIS RIG"
echo "                           LISTENS, so no column below is an audio observation."
if [[ -f "$R" ]]; then
  # A present-but-empty file is the same omission as an absent one, and it reaches this
  # loop as zero iterations: section E prints its explanatory preamble, no arms, and
  # nothing signals that the comparison the preamble just described did not happen.
  # Route it to the same failure the missing-file branch takes.
  arms=$(awk -F'\t' 'NR>1{print $1}' "$R" | sort -u)
  if [[ -z $arms ]]; then
    echo "   EMPTY: $R has no trials -- section E cannot be re-derived" >&2
    MISSING_E=1
  else
    # collect_real.sh enforces the 3+3 shape when it GENERATES the file; that does not
    # protect this consumer from a truncated committed input. Section E's whole content
    # is a comparison of two arms, so one arm, or a short one, is not a re-derivation.
    #
    # ROUND 29. THIS COUNTED ROWS AND NEVER LOOKED AT THE TRIAL COLUMN, which is the
    # defect round 19 fixed for the row-20 manifest and round 17 fixed for the row-21
    # matrix -- both of which validate IDs and not just totals. Section E was the one
    # denominator check left counting. An arm with trials `1,1,2` has three rows, so it
    # passed at want=3 while trial 3 was ABSENT, and every `stats` call below then read
    # trial 1 TWICE: n=3 with one observation double-weighted, over an arm that measured
    # two trials. Both of the columns section E quotes are medians of three, so one
    # duplicated observation moves the published median outright.
    #
    # The rule is now the same as its two siblings: each arm carries each id from 1
    # through `want` exactly once. Rows and distinct ids are BOTH reported, because they
    # fail differently -- equal-but-wrong (1,1,2) shows as a distinct-id shortfall with
    # the row count intact, while a truncated arm shows as both.
    #
    # SUBSEP, not T[a][b]: BWK awk (which is /usr/bin/awk on Darwin) has no
    # multidimensional arrays, and the row-20 block above takes the same care.
    e_bad=$(awk -F'\t' -v want="${REAL_TRIALS:-3}" '
      NR>1 { c[$1]++
             k = $1 SUBSEP $2
             if (k in T) DUP[$1] = DUP[$1] " " $2; else { T[k] = 1; n[$1]++ }
             if ($2 !~ /^[0-9]+$/ || $2+0 < 1 || $2+0 > want) BADID[$1] = BADID[$1] " " $2 }
      END { bad=0
            for (a in c) if (a != "REAL-off" && a != "REAL-pidfile") {
              printf "   UNEXPECTED real-audio arm: %s\n", a > "/dev/stderr"; bad++ }
            split("REAL-off REAL-pidfile", W, " ")
            for (i=1; i<=2; i++) { a = W[i]
              if (c[a]+0 != want) {
                printf "   ROW COUNT %s: %d row(s) for %d expected trial(s)\n", a, c[a]+0, want > "/dev/stderr"; bad++ }
              if (n[a]+0 != want) {
                printf "   SHORT %s: %d distinct trial(s), expected %d\n", a, n[a]+0, want > "/dev/stderr"; bad++ }
              if (a in DUP) {
                printf "   DUPLICATE trial rows in %s:%s\n", a, DUP[a] > "/dev/stderr"; bad++ }
              if (a in BADID) {
                printf "   TRIAL ID out of 1..%d in %s:%s\n", want, a, BADID[a] > "/dev/stderr"; bad++ } }
            print bad+0 }' "$R")
    if [[ ${e_bad:-1} -ne 0 ]]; then
      echo "   INCOMPLETE: section E needs both arms carrying each trial id 1..${REAL_TRIALS:-3} exactly once" >&2
      MISSING_E=1
    fi
  fi
  for a in $arms; do
    awk -F'\t' -v a="$a" 'NR>1 && $1==a {print $5}' "$R" | stats "$a timerstart_to_exit_s"
    awk -F'\t' -v a="$a" 'NR>1 && $1==a && $8!="-" {print $8}' "$R" | stats "$a popen_to_exit_s"
    awk -F'\t' -v a="$a" 'NR>1 && $1==a && $7!="-" {print $7}' "$R" | stats "$a overlap_s"
    awk -F'\t' -v a="$a" 'NR>1 && $1==a {print $6}' "$R" | sort | uniq -c \
      | awk -v a="$a" '{printf "%-28s killed_by_sig=%-4s x%s\n", a, $2, $1}'
  done
else
  # This script IS the advertised re-derivation check, so a summary that quietly omits
  # section E and still exits 0 is a partial result wearing a pass. Record it and fail
  # at the end.
  echo "   MISSING: $R -- section E cannot be re-derived" >&2
  MISSING_E=1
fi

echo
echo "== ROW 20 / F: the corrected adversarial predicate's own margin, ms =="
echo "   (Rdone_b is stamped AFTER the external mv returns, so publication is"
echo "    demonstrably complete. This is how far it precedes P on the trials the"
echo "    predicate accepts -- the reason the missing check was never close to"
echo "    binding. Quote it per ARM: the two arms differ by ~5 ms of median.)"
awk -F'\t' '$1=="config"{next} $26=="R<S2<R_b<P<W (adversarial)" && $6!="-" && $9!="-" {printf "%.4f\n", ($9-$6)*1000}' "$P" | stats "Rdone_b->P adversarial"

echo
echo "== ROW 21 / A: owner counts per scenario x protocol x N x stall =="
# The denominator every row-21 rate is taken over, printed rather than assumed. It was
# validated against run_lock.sh's design before any section above ran.
echo "   $lock_shape"
awk -F'\t' 'NR==1{next}{printf "%s\t%s\t%s\t%s\towners=%s\n", $1,$2,$3,$4,$6}' "$L" \
  | sort | uniq -c \
  | awk '{printf "%-5s %-16s %-9s N=%-3s stall=%-6s %s\n", $1"x", $2, $3, $4, $5, $6}'

echo
echo "== ROW 21 / B: per-protocol worst case and duplicate-owner rate =="
# VOID means the STAGING failed, not the protocol. awk would coerce it to 0 and
# score it as a duplicate-owner failure while keeping it in the denominator, so a
# synchronisation problem would read as a protocol problem. Excluded from both, and
# reported on its own line -- a run with any VOID is not a complete run.
awk -F'\t' 'NR==1{next}
$6=="VOID" { void[$2]++; next }
{ n[$2]++; if ($6+0>mx[$2]) mx[$2]=$6+0; if ($6+0!=1) bad[$2]++ }
END{ for (p in n) printf "%s\ttrials=%d\tmax_owners=%d\ttrials_not_exactly_1=%d\trate=%.1f%%%s\n",
       p, n[p], mx[p], bad[p]+0, 100*(bad[p]+0)/n[p],
       (void[p] ? "\tVOID=" void[p] " (staging failed; run is INCOMPLETE)" : "") }' "$L" | sort

echo
echo "== ROW 21 / C: duplicate-owner rate per protocol x scenario =="
awk -F'\t' 'NR==1{next}
$6=="VOID" { k=$2"/"$1; void[k]++; next }
{ k=$2"/"$1; n[k]++; if ($6+0!=1) bad[k]++ }
END{ for (p in n) printf "%s\ttrials=%d\tnot_exactly_1=%d\trate=%.0f%%%s\n", p, n[p], bad[p]+0, 100*(bad[p]+0)/n[p],
       (void[p] ? "\tVOID=" void[p] : "") }' "$L" | sort

# ROUND 15. VOID was ANNOTATED and never ENFORCED. Row 21/B already said in a comment
# that "a run with any VOID is not a complete run", and then printed the annotation and
# exited 0 -- so a fresh run whose staging failed on some cells could be consumed as a
# successful full re-derivation, with a denominator quietly smaller than the one the
# document quotes. Annotating a partial result is exactly the null-as-pass shape every
# other script in this rig now refuses, and this is the script the document points at.
# The committed evidence has no VOID rows, so this changes nothing about it; it changes
# what a RE-RUN is allowed to claim.
voids=$(awk -F'\t' 'NR>1 && $6=="VOID"' "$L" | wc -l | tr -d ' ')
if [[ ${voids:-0} -gt 0 ]]; then
  echo "INCOMPLETE: $L has $voids row(s) with owners=VOID." >&2
  awk -F'\t' 'NR>1 && $6=="VOID" { c[$2"/"$1]++ }
              END { for (k in c) printf "  VOID %-24s x%d\n", k, c[k] }' "$L" | sort >&2
  echo "A VOID row is a trial whose STAGING failed, so it is neither a pass nor a" >&2
  echo "protocol failure -- it is a cell that was not measured. The summaries above" >&2
  echo "are therefore over a SMALLER denominator than the run intended, and this is" >&2
  echo "NOT a complete re-derivation. Re-run the voided cells." >&2
  exit 2
fi

if [[ ${MISSING_E:-0} = 1 ]]; then
  echo "INCOMPLETE: real-audio evidence was missing or empty, so section E is absent." >&2
  echo "This is NOT a full re-derivation." >&2
  exit 2
fi
