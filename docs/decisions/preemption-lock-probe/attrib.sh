#!/bin/bash
# THE KILL-ATTRIBUTION RULE, IN ONE PLACE. Sourced, not executed.
#
# WHY THIS FILE EXISTS. Until round 29 this rule was written THREE TIMES -- in
# summarise.sh, in compare_passes.sh and in peek_one.sh -- and each copy read the same
# two columns of the same TSV to answer the same question. Round 16 found the defect
# below, fixed the copy in summarise.sh, and left the other two standing. Both were
# still wrong thirteen rounds later, and one of them is the script the document cites as
# the replication-AGREEMENT check.
#
# "The same fix applied to one site and not to its sibling" is the most frequent finding
# in this PR. A rule with three copies cannot be fixed once, so it now has one copy and
# every consumer calls it. Fixing the two copies in place would have left three copies
# to diverge again.
#
# Consumers: summarise.sh (section A), compare_passes.sh, peek_one.sh.
#
# THE DEFECT, from round 16 -- THE TWO SOURCES WERE INTERLEAVED, AND THE WEAKER ONE
# COULD WIN.
# `rc` is the parent wait status: one value, written once, by the kernel. `player_log_sig`
# is the LAST `sig=` the player wrote to its own log, and collect.sh keeps only the last
# (`PSIG[$3] = V2["sig"]`), so a player that is signalled twice reports the second.
# THAT HAPPENS: the committed C12b log has pid 94309 writing `player_end sig=14` and then
# `player_end sig=31` 69 us later -- one process, two sites, both recorded.
#
# The old chain tested `sig=="-15" || plog=="15"`, then -30/30, then -31/31, then -14/14,
# so a row with rc=-14 and a final player-log value of 31 matched the RECORD-sweep arm
# first and was published as a record sweep although the wait status said process group.
# The player log outranked the kernel purely because 31 was tested before 14.
# peek_one.sh had the same chain in a WORSE order -- it tested -31/31 FIRST -- and
# compare_passes.sh had it with SIGALRM omitted altogether, so every `rc=-14` row there
# scored `unknown`.
#
# The wait status now decides ALONE whenever it exists, and the player log is consulted
# ONLY as a fallback for the rows that have no wait status -- the player-published arms,
# where the parent never reaped the process it is asking about.
#
# BLAST RADIUS, verified over both committed evidence files. The (rc, player_log_sig)
# pairs present in preemption-trials.tsv are (-,0) x72, (-,-) x60, (-,31) x48, (-30,-)
# x36, (-15,15) x36, (0,0) x24, (-30,30) x12, (-,15) x12, (-,14) x12; and in
# preemption-trials-replication.tsv (-30,-) x36, (0,0) x24, (-30,30) x12, (-15,15) x12,
# (-,31) x12, (-,15) x12, (-,0) x12, (-,-) x12. NO row in EITHER file has both fields
# present and disagreeing, so the OVERRIDE half of this defect changes no published
# attribution and remains latent -- one scheduling accident on the C12b arm away from
# biting. The SIGALRM half was NOT latent for compare_passes.sh: the 12
# C12a_pgid_pubfirst rows at (rc=-, plog=14) scored `unknown` there and score
# `election-sweep-pgid` now. That configuration is published-arm-only, so it is outside
# the intersection compare_passes.sh diffs and the AGREEMENT verdict is unchanged; the
# per-file block it prints above that verdict does change.
#
# NOTE: no apostrophes below this line -- the awk program is single-quoted, and one
# apostrophe would end the shell string. Darwin signal numbers.
ATTRIB='function attrib(sig, plog, ppid, prun) {
  # 1. The wait status, if the parent has one. Authoritative and sufficient.
  if (sig != "-") {
    if (sig=="-15") return "hook-pid-kill"
    if (sig=="-30") return "worker-claim-kill"
    if (sig=="-31") return "election-sweep-record"
    if (sig=="-14") return "election-sweep-pgid"
    if (sig=="0")   return "NOTHING-ran-to-end"
    # A status this rig has no kill site for. Falling back to the player log here would
    # be the same defect again, so name it instead. Unreached on the committed evidence:
    # rc is one of -, -30, -15, 0 on all 312 rows.
    return "unrecognised-wait-status:" sig
  }
  # 2. No wait status: the player log is the only witness. It is the LAST value the
  #    player wrote, so where two sites reached one process this under-reports the
  #    first -- which is why it is the fallback and not the rule.
  if (plog=="15") return "hook-pid-kill"
  if (plog=="30") return "worker-claim-kill"
  if (plog=="31") return "election-sweep-record"
  if (plog=="14") return "election-sweep-pgid"
  if (plog=="0")  return "NOTHING-ran-to-end"
  if (ppid=="-")                return "no-player-spawned"
  # Spawned, never logged a start, no exit status: killed BEFORE it could exec.
  # A player that survived to run always logs player_start, so this is unambiguous.
  if (prun=="0(never_started)")  return "killed-before-exec"
  return "unknown"
}'
