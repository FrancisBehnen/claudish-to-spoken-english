#!/bin/bash
# Recount the decision document's own tallies FROM THEIR OWN ROW BLOCKS, and refuse any
# site that disagrees with the recount.
#
#   usage: tally_check.sh [path/to/preemption-and-lock-protocol.md]
#   exit 0  every stated tally equals its recount
#   exit 2  a site disagrees, or a site this guard checks is no longer present
#   exit 3  the document itself could not be read
#
# WHY THIS EXISTS. Round 27 found that the §6 induction count was carried by hand in three
# places and that all three disagreed ("three numbers for one tally, none of them
# defined, in the section whose entire argument is an induction over that tally"). Round 31
# recounted them programmatically and wrote that "every site now carries the same number
# for the same reason". IT DID NOT: the paragraph directly under the table still read
# "Fourteen rows" over a sixteen-row table -- two rounds behind, which is exactly the
# drift rate the paragraph above it measures. A recount performed once is a recount that
# expires. So the recount is a script, it is a guard, and it fails rather than warns.
#
# THIS GUARD REFUSES A MISSING SITE, NOT ONLY A WRONG ONE. Every check below asserts that
# its sentence is still in the document. A tally guard whose pattern silently matches
# nothing is the null-as-pass shape section 1 keeps meeting; here it would report a clean
# tally for a document that no longer states one.
set -u

DOC=${1:-}
if [[ -z $DOC ]]; then
  DOC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/preemption-and-lock-protocol.md"
fi
[[ -r $DOC ]] || { echo "tally_check.sh: cannot read $DOC" >&2; exit 3; }

# ---- the recounts. Each is over the block that IS the thing being counted.

# (1) the §6 induction table: its own data rows.
ROUNDS=$(awk '
  /^### What the rounds actually did/            { zone = 1 }
  zone && /^\| round \| the clause it examined/  { tab = 1; next }
  tab && /^\| --- \|/                            { next }
  tab && /^\|/                                   { n++; next }
  tab && !/^\|/                                  { tab = 0; zone = 0 }
  END { print n+0 }' "$DOC")

# (2) and (3) the two §1 defect lists: their own top-level numbered items. Contiguity is
# checked too -- a list numbered 1..16,18 has seventeen items and a missing sixteenth, and
# "seventeen" would be true of the count while false of the list.
read -r DERIV DERIV_GAPS HARN HARN_GAPS <<<"$(awk '
  /derivation defects have been found/ { zone = "d" }
  /HARNESS defects were also found/    { zone = "h" }
  /^## /                               { if (zone == "h") zone = "" }
  /^[0-9]+\. \*\*/ {
    k = $1; sub(/\./, "", k)
    if (zone == "d") { d[k+0] = 1; if (k+0 > dmax) dmax = k+0; dn++ }
    if (zone == "h") { h[k+0] = 1; if (k+0 > hmax) hmax = k+0; hn++ }
  }
  END {
    dg = ""; for (i = 1; i <= dmax; i++) if (!(i in d)) dg = dg "," i
    hg = ""; for (i = 1; i <= hmax; i++) if (!(i in h)) hg = hg "," i
    printf "%d %s %d %s\n", dn+0, (dg == "" ? "none" : substr(dg, 2)), \
                            hn+0, (hg == "" ? "none" : substr(hg, 2))
  }' "$DOC")"

# (4) §6's enumerated clause list: its own "(n)" markers, which run inline through one
# list item rather than down a column, so they are counted where they are written.
read -r CLAUSES CLAUSE_GAPS <<<"$(awk '
  /failed on [a-z]+ distinct clauses/ { zone = 1 }
  zone && /^### /                     { zone = 0 }
  zone {
    s = $0
    while (match(s, /\([0-9]+\)/)) {
      k = substr(s, RSTART + 1, RLENGTH - 2) + 0
      c[k] = 1; if (k > cmax) cmax = k
      s = substr(s, RSTART + RLENGTH)
    }
  }
  END {
    n = 0; for (k in c) n++
    g = ""; for (i = 1; i <= cmax; i++) if (!(i in c)) g = g "," i
    printf "%d %s\n", n, (g == "" ? "none" : substr(g, 2))
  }' "$DOC")"

echo "recounted from the document itself:"
printf '  induction-table rows      %s   (missing: -)\n'     "$ROUNDS"
printf '  derivation-defect items   %s   (missing: %s)\n'    "$DERIV" "$DERIV_GAPS"
printf '  harness-defect items      %s   (missing: %s)\n'    "$HARN"  "$HARN_GAPS"
printf '  distinct-clause markers   %s   (missing: %s)\n'    "$CLAUSES" "$CLAUSE_GAPS"
echo

FAIL=0
for pair in "derivation:$DERIV_GAPS" "harness:$HARN_GAPS" "clause:$CLAUSE_GAPS"; do
  if [[ ${pair#*:} != none ]]; then
    echo "GAP: the ${pair%%:*} list skips ${pair#*:} -- the count is not the list" >&2
    FAIL=1
  fi
done

# ---- word <-> integer. The document spells its tallies out, so the guard has to read
# words; digits are accepted where the document writes digits.
w2n() {
  case $(printf '%s' "$1" | tr 'A-Z' 'a-z') in
    one) echo 1 ;;      two) echo 2 ;;        three) echo 3 ;;      four) echo 4 ;;
    five) echo 5 ;;     six) echo 6 ;;        seven) echo 7 ;;      eight) echo 8 ;;
    nine) echo 9 ;;     ten) echo 10 ;;       eleven) echo 11 ;;    twelve) echo 12 ;;
    thirteen) echo 13 ;; fourteen) echo 14 ;; fifteen) echo 15 ;;   sixteen) echo 16 ;;
    seventeen) echo 17 ;; eighteen) echo 18 ;; nineteen) echo 19 ;; twenty) echo 20 ;;
    twentyone|twenty-one) echo 21 ;;          twentytwo|twenty-two) echo 22 ;;
    first) echo 1 ;;    fourteenth) echo 14 ;;
    [0-9]|[0-9][0-9]) printf '%s\n' "$1" ;;
    *) echo "" ;;
  esac
}

# SITES counts the checks below, so that the number of sites this guard covers is itself
# recounted rather than restated. Round 32's whole finding is a hand-maintained count that
# fell behind; a guard that fixes that by introducing its own hand-maintained count of
# sites would be the defect one level up.
SITES=0

# site <expected> <label> <sed-regex-with-one-capture-group>
site() {
  local want=$1 label=$2 re=$3 hits got n
  SITES=$((SITES + 1))
  hits=$(sed -nE "s/.*${re}.*/\1/p" "$DOC")
  if [[ -z $hits ]]; then
    echo "MISSING SITE: $label -- this guard checks a sentence the document no longer has." >&2
    echo "              Either the sentence moved (re-anchor this check) or the tally is" >&2
    echo "              no longer stated (say so deliberately). Not a pass either way." >&2
    FAIL=1
    return
  fi
  n=0
  while IFS= read -r word; do
    [[ -n $word ]] || continue
    n=$((n + 1))
    got=$(w2n "$word")
    if [[ -z $got ]]; then
      printf 'UNREADABLE: %-34s reads %q, which is not a number this guard knows\n' \
        "$label" "$word" >&2
      FAIL=1
    elif [[ $got -ne $want ]]; then
      printf 'MISMATCH:   %-34s says %s (%s), recount says %s\n' \
        "$label" "$word" "$got" "$want" >&2
      FAIL=1
    else
      printf 'ok          %-34s %s\n' "$label" "$word"
    fi
  done <<<"$hits"
  [[ $n -gt 0 ]] || FAIL=1
}

# The row count, at every site that states it -- one in §0, the rest in §6.
site "$ROUNDS" "S0/S6 consecutive rounds" \
  '\*\*([A-Za-z]+) consecutive rounds of review'
site "$ROUNDS" "S6 count is now" \
  '\*\*([A-Za-z]+)\*\* because this round adds one'
site "$ROUNDS" "S6 smallest defensible" \
  '\*\*([A-Za-z]+) is therefore the smallest defensible number here\*\*'
site "$ROUNDS" "S6 rows-after-this-round" \
  "this round.s, ([0-9]+) after\\*\\*"
site $((ROUNDS - 1)) "S6 rows-before-this-round" \
  '\*\*([0-9]+) rows before'
site "$ROUNDS" "S6 under-the-table row count" \
  '\*\*([A-Za-z]+) rows, and every one of them a round'
site "$ROUNDS" "S6 heading, refuted in N rounds" \
  'in that table — ([a-z]+) of them'
site "$ROUNDS" "S6 rows-are-a-floor" \
  'so the ([a-z]+) rows are a'

# The two defect-list counts, at every site that states them.
#
# ROUND 34: THE CAPTURE CLASS HAD TO INCLUDE A HYPHEN, and the reason is worth recording because
# it is the failure mode this guard is for. `w2n` has understood `twenty-one` since round 32, but
# these three patterns captured `[A-Za-z]+`, which stops at the hyphen -- so the first time the
# derivation list crossed twenty, all three sites reported MISSING SITE rather than a wrong number.
# That is the guard behaving correctly (it refuses a site it cannot read, and did not pass), but the
# class was too narrow for the numbers the document was always going to reach. Widening it accepts
# more WORDS, not more VALUES: an unreadable word is still `UNREADABLE` and a wrong one still
# `MISMATCH`.
site "$DERIV" "S1 derivation-defect count" \
  '\*\*([A-Za-z-]+) derivation defects have been found'
site "$DERIV" "S1 all N are addressed" \
  'and all ([a-z-]+) are addressed here'
site "$DERIV" "S1 recurrence denominator" \
  'of ([a-z-]+) have come back \*\*the same way\*\*'
site "$HARN" "S1 harness-defect count" \
  '\*\*([A-Za-z]+) HARNESS defects were also found'
site "$HARN" "S1 sharpest of the N" \
  'sharpest of the ([a-z]+) despite moving nothing'

# The clause count in §6, which is a count of clauses and NOT of rounds -- checked
# against its own markers so the two can never be reconciled to each other by mistake.
site "$CLAUSES" "S6 distinct clauses failed" \
  'has now failed on ([a-z]+) distinct clauses'
site "$CLAUSES" "S6 inspection produced all N" \
  'Inspection is what produced all ([a-z]+)\.'

# "sixteen fixed, and the fourteenth re-labelled" -- fixed + the one re-labelled must be
# the whole list, or the sentence understates what the list contains.
SITES=$((SITES + 1))   # this block is a site too; it just needs arithmetic, not equality
fixed=$(sed -nE 's/.*^([a-z]+) fixed, and the [a-z]+ re-labelled.*/\1/p' "$DOC")
[[ -n $fixed ]] || fixed=$(sed -nE 's/.*[^a-z]([a-z]+) fixed, and the [a-z]+ re-labelled.*/\1/p' "$DOC")
if [[ -z $fixed ]]; then
  echo "MISSING SITE: S1 fixed-plus-relabelled -- sentence not found" >&2
  FAIL=1
else
  f=$(w2n "$fixed")
  if [[ -z $f || $((f + 1)) -ne $DERIV ]]; then
    printf 'MISMATCH:   %-34s says %s fixed + 1 re-labelled, list has %s\n' \
      "S1 fixed-plus-relabelled" "$fixed" "$DERIV" >&2
    FAIL=1
  else
    printf 'ok          %-34s %s fixed + 1 re-labelled = %s\n' \
      "S1 fixed-plus-relabelled" "$fixed" "$DERIV"
  fi
fi

# ---- and the guard's own coverage, recounted the same way. These checks are deliberately
# NOT added to SITES: they are a check ON the site count, and counting them in it would make
# the number self-referential rather than derived.
NSITES=$SITES
echo
echo "site count recounted from the checks above: $NSITES"
site "$NSITES" "S1/18 site count"        '\*\*([A-Za-z]+) sites\*\*, and the guard fails'
site "$NSITES" "S6 checks N stated sites" 'checks \*\*([a-z]+)\*\* stated sites'
site "$NSITES" "S6 one wrong site out of" 'one wrong site out of ([a-z]+)'
site "$NSITES" "S0 site count"            'tally_check\.sh`, ([a-z]+) sites,'
site "$NSITES" "S6 row, guard over N"     'a guard over ([a-z]+) sites'
site $((NSITES - 1)) "S1/18 ok-lines on rev 14" \
  'give ([a-z]+) `ok` lines and one'

echo
if [[ $FAIL -ne 0 ]]; then
  echo "TALLY CHECK FAILED -- at least one site disagrees with its own row block." >&2
  exit 2
fi
echo "TALLY CHECK PASSED -- rounds=$ROUNDS derivation=$DERIV harness=$HARN clauses=$CLAUSES,"
echo "every stated site recounted from the block it is a count of."
