#!/bin/bash
# THE NULL-AS-PASS RULE, IN ONE PLACE. Sourced, not executed.
#
# WHY THIS FILE EXISTS. "A validator that checks a file EXISTS but not that it CONTAINS
# anything" is now the finding of three consecutive review rounds, and by round 34 it had
# SIX SITES in this rig -- four analysers/collectors testing `-f`/`-e` and one driver that
# validated no input at all. The rig has had a NAME for the shape since round 12 (the
# phrase `null-as-pass` appears in collect.sh, lock_overlap.sh, assemble.sh and
# summarise.sh) and it still had six independent implementations of the check that is
# supposed to stop it. That is the shape round 29 met in `attrib.sh` and round 30 met in
# `cleanup.sh`: one rule, many copies, fixed at one copy per round.
#
# So the rule has exactly one definition and every consumer calls it. A seventh consumer
# written later inherits the check rather than re-deriving it -- which is the whole
# argument, because every one of the six sites below was written by someone who had just
# read the site before it.
#
# WHAT `-f` DOES NOT ESTABLISH, concretely, on this rig:
#
#   * A ZERO-BYTE trace passes `-f` and reaches awk as a name with no records. In
#     `lock_overlap.sh` the per-file dispatch is `FNR == 1`, which an empty file never
#     fires, so the file is silently absent from the `files` count while the SHELL glob
#     count still says seven -- the coverage fraction the document quotes derived over
#     fewer traces than its own numerator names.
#   * A ZERO-BYTE player log / marker TSV / hook log passes `-f && -r` in `analyse_c14.sh`.
#     All 12 trials then classify as `nohook`, the accounting total is satisfied, and the
#     script exits 0 having made no observation at all.
#   * A ZERO-BYTE `kills.log` / `player.log` / `worker.trace` passes `-e` in `collect.sh`,
#     which then WRITES an evidence file with blank hook fields and no player evidence.
#     That one does not report nothing -- it publishes something wrong.
#   * An UNVALIDATED count (`REPS`) makes every `seq` loop in `run_lock.sh` empty, so the
#     driver leaves a header-only `owners.tsv`, prints `DONE` and exits 0.
#   * A count of DISTINCT ids is not the id SET: `1..11,13` has twelve distinct values,
#     twelve is the expected count, and trial 12 is missing while 13 was never run.
#
# THE COMMON PROPERTY, and the reason these are one rule and not five: every one of them
# lets a script report SUCCESS over input it did not read, or output it did not produce.
# The refusal direction is the only safe one -- a derivation that observed nothing must not
# be quotable as a derivation.
#
# WHY A SEPARATE FILE AND NOT `attrib.sh`. `attrib.sh` is one rule -- the kill attribution
# -- and its header says so. Two unrelated rules in one include is the coupling this rig
# spent round 29 removing, and it would mean `run_lock.sh` (which attributes no kills)
# sourcing the attribution rule to get a range check. `publish.sh` lists this file for the
# reason it lists `attrib.sh`: every consumer refuses to run without it, so a rig published
# without it satisfies every other name and validates nothing.
#
# Consumers: collect.sh, analyse_c14.sh, analyse_round2.sh, lock_overlap.sh, run_lock.sh,
# assemble_pass1.sh.
#
# NOTE: no apostrophes inside the single-quoted awk programs below. No `set` here either:
# this file is SOURCED, so an option set in it would silently change its callers -- and all
# six already set `-u` themselves.

# ---- require_dir <who> <path>
# A directory, and readable/searchable. `collect.sh`s marker path is a DIRECTORY whose
# per-trial marker files are stat(2)ed one at a time; `-e` accepted a regular file of that
# name and every stat then failed into a blank column.
require_dir() {
  local who=$1 p=$2
  if [[ ! -e $p ]]; then
    echo "$who: MISSING INPUT: $p (expected a directory)" >&2
    return 1
  fi
  if [[ ! -d $p ]]; then
    echo "$who: $p is not a DIRECTORY -- the markers are read out of it one file at a" >&2
    echo "  time, and every one of those reads would fail into an empty column." >&2
    return 1
  fi
  if [[ ! -r $p || ! -x $p ]]; then
    echo "$who: $p is not readable/searchable -- the markers cannot be read out of it." >&2
    return 1
  fi
  return 0
}

# ---- require_nonempty <who> <path>
# A REGULAR, readable file with AT LEAST ONE BYTE. One byte is the right floor and not an
# arbitrary one: awk dispatches per file on `FNR == 1`, and a file of one byte has one
# record while a file of zero bytes has none, so "non-empty" is exactly "awk will see this
# file at all". Every failure names WHICH of the four conditions failed, because "missing"
# and "present but empty" are different accidents and one message for both is how a
# diagnostic stops diagnosing.
require_nonempty() {
  local who=$1 f=$2
  if [[ -d $f ]]; then
    echo "$who: $f is a DIRECTORY, not the file this derivation reads." >&2
    return 1
  fi
  if [[ ! -e $f ]]; then
    echo "$who: MISSING INPUT: $f" >&2
    return 1
  fi
  if [[ ! -f $f ]]; then
    echo "$who: NOT A REGULAR FILE: $f -- a fifo or device may read as empty, or block," >&2
    echo "  and either way it is not the committed evidence this expects." >&2
    return 1
  fi
  if [[ ! -r $f ]]; then
    echo "$who: UNREADABLE INPUT: $f -- awk aborts on a file it cannot open just as" >&2
    echo "  surely as on one that is not there." >&2
    return 1
  fi
  if [[ ! -s $f ]]; then
    echo "$who: EMPTY INPUT: $f is 0 bytes. It EXISTS and it contains nothing, so every" >&2
    echo "  count taken from it is zero and no observation in it was ever made. A" >&2
    echo "  derivation over it is not a derivation." >&2
    return 1
  fi
  return 0
}

# ---- require_nonempty_all <who> <path>...
# Every path, and NAME EVERY FAILURE rather than stopping at the first: a caller told about
# one absent input re-runs, gets told about the next, and learns the state of its own run
# one round trip at a time.
require_nonempty_all() {
  local who=$1 f rc=0
  shift
  for f in "$@"; do
    require_nonempty "$who" "$f" || rc=1
  done
  return $rc
}

# ---- require_uint <who> <label> <value> [min]
# A plain non-negative decimal integer, at least `min` (default 0).
#
# LEADING ZEROS ARE REFUSED ON PURPOSE. `[[ 010 -lt 8 ]]` is TRUE in bash -- arithmetic
# context reads `010` as octal 8 -- so a value that passed a `^[0-9]+$` test could then
# compare as a different number than it reads as. Refusing the form is cheaper than
# reasoning about where it is next used.
require_uint() {
  local who=$1 label=$2 val=$3 min=${4:-0}
  if [[ ! $val =~ ^(0|[1-9][0-9]*)$ ]]; then
    echo "$who: $label must be a plain non-negative integer (no sign, no leading zero," >&2
    echo "  no whitespace), got '$val'." >&2
    return 1
  fi
  if [[ $val -lt $min ]]; then
    echo "$who: $label must be at least $min, got $val." >&2
    return 1
  fi
  return 0
}

# ---- require_data_rows <who> <path> <min>
# The file exists, is non-empty, AND carries at least `min` records BEYOND its header.
#
# A HEADER IS NOT A RESULT. Every producer here writes its header first and its rows as it
# goes, so "the header got written" is the state of a run that recorded nothing -- and it
# is also the state of a run whose every append failed. `wc -l` is not used: it counts
# newlines, so a final row with no trailing newline is invisible to it, and undercounting
# is the direction that turns a real result into a refusal.
require_data_rows() {
  local who=$1 f=$2 min=$3 rows
  require_nonempty "$who" "$f" || return 1
  rows=$(awk 'END { print NR - 1 }' "$f")
  if [[ ${rows:-0} -lt $min ]]; then
    echo "$who: $f holds ${rows:-0} record(s) after its header, expected at least $min." >&2
    echo "  A file that is only a header is the state of a run that produced nothing, and" >&2
    echo "  reporting success over it is the defect this guard exists for." >&2
    return 1
  fi
  return 0
}

# ---- require_exact_id_set <who> <path> <col> <n>
# Column `col` of the data rows must be EXACTLY the set 1..n, each value once, and the file
# must hold exactly n data rows.
#
# A COUNT OF DISTINCT VALUES IS NOT THE SET, and this is the whole finding: `1..11,13` has
# twelve distinct trial ids, so a `distinct == 12` test passes a run that is MISSING trial
# 12 and carries a trial 13 that is outside the experiment. Duplicate rows are the mirror
# -- twelve distinct ids across twenty-four rows -- and are equally invisible to a distinct
# count.
#
# MEMBERSHIP IS TESTED WITH ARRAY SUBSCRIPTS AND NOT WITH `==`. On /usr/bin/awk here (BWK
# awk 20200816) `"12" == "12′"` is TRUE -- U+2032 PRIME is invisible to the comparison
# operators -- while `in` sees it, because a subscript is compared by identity. So a field
# carrying an invisible suffix is reported out-of-range rather than silently accepted as
# the id it merely looks like.
require_exact_id_set() {
  local who=$1 f=$2 col=$3 n=$4
  require_nonempty "$who" "$f" || return 1
  require_uint "$who" "the expected id count" "$n" 1 || return 1
  awk -F'\t' -v who="$who" -v c="$col" -v n="$n" -v fn="$f" '
    NR == 1 { next }
    { rows++; L[$c]++ }
    END {
      for (i = 1; i <= n; i++) E[i ""] = 1
      gap = ""; extra = ""; dup = ""
      for (i = 1; i <= n; i++) if (!((i "") in L)) gap = gap " " i
      for (k in L) {
        if (!(k in E))  extra = extra " [" k "]"
        if (L[k] > 1)   dup   = dup " " k "(x" L[k] ")"
      }
      bad = 0
      if (rows+0 != n) {
        printf "%s: %s has %d data row(s), expected exactly %d.\n", who, fn, rows+0, n > "/dev/stderr"
        bad = 1
      }
      if (gap != "") {
        printf "%s: %s is MISSING id(s):%s -- a count of distinct ids cannot see a gap.\n", who, fn, gap > "/dev/stderr"
        bad = 1
      }
      if (extra != "") {
        printf "%s: %s carries id(s) outside 1..%d:%s\n", who, fn, n, extra > "/dev/stderr"
        bad = 1
      }
      if (dup != "") {
        printf "%s: %s repeats id(s):%s -- duplicate rows are not extra evidence.\n", who, fn, dup > "/dev/stderr"
        bad = 1
      }
      if (bad) {
        printf "%s: the id set is not 1..%d, so this is not the run the document names.\n", who, n > "/dev/stderr"
        exit 1
      }
    }' "$f"
}
