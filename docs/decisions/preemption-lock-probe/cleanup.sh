#!/bin/bash
# THE DRIVERS' FATAL-PATH CLEANUP, SOURCED NOT EXECUTED.
#
# WHY THIS FILE EXISTS, AND IT IS THIS DOCUMENT'S OWN CENTRAL FINDING TURNED ON THE RIG
# THAT PRODUCED IT.
#
# Round 27 gave `run_real.sh` and `run_preempt.sh` an `EXIT` trap, because four fatal
# paths were leaving a worker running under `--idle-exit-s 600` (harness defect 5). The
# trap did `kill -TERM "$WPID"`. Round 30's review found that this terminates ONLY THE
# WORKER, and the worker's players are not the worker: `speakd_probe.py` calls
# `os.setsid()` before it elects, so the worker is a process-group leader and every
# player it forks joins ITS group -- not the driver's, and not something a signal to the
# worker's pid reaches. On a fatal readiness or hook path the worker died and its
# `afplay` process ran to the end of the 5.7 s wav, or its stub kept sleeping, and the
# immediate retry -- which is what an operator does with a failed run -- started with the
# previous run's processes still holding the audio device and the CPU.
#
# THAT IS EXACTLY THE MISTAKE THE PROTOCOL UNDER TEST WAS WRITTEN TO PREVENT. §4b clause
# 7(iv) exists because killing a worker's pid does not reach that worker's player; the
# whole process-group sweep in `sweep_pgid()` is the repair for it, and `C17_setsid_player`
# is the arm that shows even THAT sweep failing when the player leaves the group. The
# cleanup path of the rig made the same error, in the same rig, one function away from the
# code that measures it. The general rule, which is worth more than these two edits:
#
#   ANY PLACE THIS RIG TERMINATES SOMETHING, ASK WHAT THAT THING'S CHILDREN ARE IN.
#
# It is one file rather than two copies for the reason `attrib.sh` is one file: this
# document's most frequent disclosure is a repair applied to one site and not to its
# sibling, and both drivers need the same rule.
#
# ---------------------------------------------------------------------------------------
# THE RULE APPLIED TO EVERY OTHER TERMINATION SITE IN THE RIG, so that "we fixed the two
# we noticed" is not what this file amounts to. Verdict per site, including the sites that
# were already right -- an audit that lists only the defects cannot be checked for
# coverage:
#
#   run_real.sh EXIT trap            WAS WRONG, fixed here. Worker leads a group; afplay
#                                    was in it and survived the pid kill.
#   run_preempt.sh EXIT trap         WAS WRONG, fixed here. Same defect; C17's player is
#                                    outside even the worker's group.
#   run_preempt.sh per-trial kill    CORRECT AS A PID KILL, and deliberately left one.
#                                    It is staging, not cleanup: the orphaned player IS
#                                    the subject of the trial. A group kill here would
#                                    destroy what the trial measures.
#   run_lock.sh                      CORRECT, nothing to fix. It has no `kill` and no
#                                    trap at all: every `lockrace.py` is backgrounded and
#                                    `wait`ed, on the timeout paths too, and `lockrace.py`
#                                    neither calls `setsid()` nor spawns a player. Its one
#                                    `Popen` is `dead_pid()`, which `wait()`s immediately.
#                                    No `--idle-exit-s` worker exists in this arm.
#   run_c10 / run_c16 / run_tail /   CORRECT, nothing to fix. They terminate nothing. Each
#   run_missing / run_pgid_rerun /   runs the driver synchronously in a command
#   run_all_preempt                  substitution and checks its status; the driver's own
#                                    trap owns the worker. Their exposure is the OPPOSITE
#                                    direction -- see `kill_worker_group`'s note on why a
#                                    wrong pgid would kill these wrappers, which is the
#                                    reason the group kill is guarded rather than assumed.
#   hook_probe.sh                    CORRECT, and must stay a pid kill. Its kills are the
#                                    MECHANISM UNDER TEST (the hook-side kill K), which
#                                    the protocol specifies against a published pid. It
#                                    already refuses pid <= 1 before any signal -- the
#                                    guard that stops `kill -TERM 0` reaching this hook's
#                                    own group. It backgrounds nothing and needs no trap.
#   speakd_probe.py sweep/kill sites CORRECT, and out of scope for this file. `sweep_pgid`,
#                                    `sweep_record`, `kill_player` and the
#                                    `publish_refused` `terminate()` are the subject of
#                                    the measurement, not its housekeeping, and each is
#                                    already guarded against pid 0 and negatives.
#   speakd_probe.py `idle_exit`      A REAL GAP, NOT REACHED, and not closed here. The
#                                    worker breaks its loop and exits without signalling
#                                    a player still in its group. Both drivers pass
#                                    `--idle-exit-s 600`, longer than any run, and every
#                                    player is bounded (2.5 s stub, 5.7 s wav), so no
#                                    configuration reaches it. Recorded rather than fixed
#                                    because fixing it means an `atexit` inside the
#                                    process whose abrupt death several arms deliberately
#                                    stage, and `os._exit(9)` would bypass it anyway.
#   player_probe.py                  CORRECT. Its `os.kill(getpid(), signum)` re-raises on
#                                    ITSELF to preserve the wait status. It has no
#                                    children beyond a waited `subprocess.run`.

# ---------------------------------------------------------------------------------------
# pgid_of <pid> -- the process group of a LIVE pid, or nothing.
#
# Empty output means "no live process has that pid", which is exactly the case the caller
# must not turn into a group kill.
pgid_of() {
  local out
  out=$(ps -o pgid= -p "$1" 2>/dev/null | tr -d '[:space:]') || return 1
  [[ $out =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$out"
}

# ---------------------------------------------------------------------------------------
# kill_worker_group <wpid> -- terminate the worker's process GROUP, guarded.
#
# THE OVER-KILL DIRECTION IS THE DANGEROUS ONE HERE, and it is why the pgid is derived
# rather than assumed. `os.setsid()` makes the worker its own group leader, so its pgid IS
# its pid -- but only from the instant it reaches that call. Before it (a worker that
# failed in argparse, or that has not been scheduled yet) and after it has exited, the pid
# either belongs to the DRIVER's own process group or belongs to nothing:
#
#   * `kill -TERM -<driver pgid>` kills this driver, the wrapper that invoked it
#     (`run_all_preempt.sh` and friends run the driver in a command substitution, in their
#     own group), and the shell above that. Measured: a plain `cmd &` child reports the
#     invoking shell's pgid, NOT its own pid.
#   * `kill -TERM -<dead worker pid>` names a group whose leader is gone. The kernel is
#     free to have handed that pid to an unrelated group leader -- the same recycling
#     hazard §4b prices for `sweep_pgid()`, arriving through the cleanup path instead.
#
# So the group kill fires on ONE conjunction, and falls back to the plain pid kill (which
# is harmless: at worst `ESRCH`) on anything else:
#
#   the pid is live  AND  its pgid parses  AND  pgid > 1  AND  pgid == the pid itself
#   AND pgid != this driver's own process group.
#
# `pgid == pid` IS the verification that `os.setsid()` ran: a group leader's pgid is its
# own pid, and nothing else in this rig makes the worker one. The `!= driver pgid` test is
# implied by it and kept anyway, because it is the catastrophic direction and a redundant
# guard on that costs one `ps`.
#
# Prints one line naming what it did, so a demonstration can read the decision rather
# than infer it from what survived.
kill_worker_group() {
  local wp=$1 wpg dpg
  [[ -n $wp ]] || return 0
  wpg=$(pgid_of "$wp") || wpg=""
  dpg=$(pgid_of "$$") || dpg=""
  if [[ -n $wpg && $wpg -gt 1 && $wpg == "$wp" && $wpg != "$dpg" ]]; then
    printf 'cleanup: worker %s is its own group leader; kill -TERM -%s\n' "$wp" "$wpg" >&2
    kill -TERM -"$wpg" 2>/dev/null
  else
    printf 'cleanup: worker %s pgid=%s driver pgid=%s -- NOT a group leader, pid kill only\n' \
      "$wp" "${wpg:-none}" "${dpg:-none}" >&2
    kill -TERM "$wp" 2>/dev/null
  fi
  return 0
}

# ---------------------------------------------------------------------------------------
# reap_stray_players <trace> <sid> [pid to spare...] -- the players a group kill cannot
# reach.
#
# TWO POPULATIONS ARE OUT OF THE WORKER'S GROUP, and both are staged deliberately by
# configurations in this rig:
#
#   1. `--player-setsid on` (`C17_setsid_player`) spawns the player with
#      `start_new_session=True`, so it is its OWN session leader. That one line is what
#      §4b's clause 7(iv) cannot reach, which is the entire point of the arm -- and it is
#      equally out of reach of the cleanup above.
#   2. `--die-after popen` (every `DIE=popen` configuration) kills the worker inside the
#      P->W window, so by cleanup time the group's LEADER is gone. The group still has a
#      member, but its pgid can no longer be verified against a live leader, so
#      `kill_worker_group` correctly refuses to signal it.
#
# THE PID SET COMES FROM THE TRACE, NOT FROM THE PLAYER RECORDS, and that is a choice with
# a reason. A per-player record appears only after the wrapper's `mv`, and the two arms
# that matter here stage the worker's death BEFORE that (`--publish-delay-ms 1500` against
# `--die-after popen`): at cleanup there is a `.pending` marker and no record. `P_popen` is
# stamped and `fsync`ed the instant `Popen` returns, for every `--pid-mode`, so it is the
# only complete list. Where a validated `<pid>.<starttime>` record does exist it is a
# STRONGER identity than what is used below; it is not a more COMPLETE one, and
# completeness is what a leak check needs.
#
# IDENTITY, BECAUSE A TRACE PID IS NOT AN IDENTITY EITHER. Every pid in the trace is long
# dead on the happy path, and the kernel recycles pids: signalling one on the strength of
# the trace alone is `sweep_pgid()`'s recycled-owner hazard with the numbers read out of a
# file instead of a record. So a pid is signalled only if its LIVE argv still names this
# run's session id -- `ps -ww -o command=` and a fixed-string match on `$SID`, which is
# `<config>-<epoch second>` and appears in every player's argv: the stub carries
# `.../out/<SID>/player.log`, `afplay` carries `.../out/<SID>/speak/<wav>`. A recycled pid
# running a stranger's program does not match. That is weaker than `<pid>.<starttime>` in
# principle and stronger in practice for this job: it proves the process IS one of this
# run's players, rather than that it started when one of them did.
#
# Prints one line per pid, and the count, so both demonstration directions are readable.
reap_stray_players() {
  local trace=$1 sid=$2; shift 2
  local spare=" $* "
  local pid cmd n=0
  [[ -f $trace ]] || return 0
  # BWK awk on this macOS: no `match()` capture groups, so the field is split by hand.
  for pid in $(awk -F'\t' '$5=="P_popen" {
                             n=split($6, f, " ")
                             for (i = 1; i <= n; i++)
                               if (f[i] ~ /^player_pid=/) { sub(/^player_pid=/, "", f[i]); print f[i] }
                           }' "$trace" | sort -u); do
    [[ $pid =~ ^[0-9]+$ ]] || continue
    [[ $pid -gt 1 ]] || continue
    [[ $spare == *" $pid "* ]] && continue
    kill -0 "$pid" 2>/dev/null || continue
    cmd=$(ps -ww -o command= -p "$pid" 2>/dev/null)
    if [[ -z $cmd ]] || ! printf '%s' "$cmd" | grep -qF -- "$sid"; then
      printf 'cleanup: player %s alive but argv does not name %s -- NOT signalled\n' \
        "$pid" "$sid" >&2
      continue
    fi
    printf 'cleanup: stray player %s (%s) -- kill -TERM\n' "$pid" "$cmd" >&2
    kill -TERM "$pid" 2>/dev/null
    n=$((n + 1))
  done
  printf 'cleanup: %d stray player(s) signalled\n' "$n" >&2
  return 0
}

# ---------------------------------------------------------------------------------------
# WHAT REMAINS UNREACHABLE, stated rather than implied, because "the cleanup is total"
# would be the same kind of claim this document has had to withdraw four times.
#
# A player that is BOTH out of the worker's process group AND absent from the trace is
# reachable by neither mechanism. That is one window: between `subprocess.Popen` returning
# a child and `rec("P_popen", ...)` completing its `fsync`, under `--player-setsid on`. A
# worker killed inside those microseconds leaves a session-leading child that nothing here
# names. It is not staged by any configuration -- `--die-after popen` fires AFTER `P_popen`
# is written, so every deliberately orphaned player IS in the trace -- and it is not
# closable from the driver: closing it needs the child to publish its own identity before
# it can run, which is what clause 7(i) is and what the `.pending` marker approximates.
#
# C17 IS NOT IN THAT CATEGORY, and the draft of this file implied it might be. Measured:
# under `--player-setsid on` each player's pgid is its OWN pid, so `kill_worker_group` is
# correctly refused against it and reaches it not at all -- and `reap_stray_players` then
# finds both players in the trace, matches `$SID` in their live argv, and signals both.
# The arm that exists to defeat clause 7(iv) IS cleaned up here; what it defeats is the
# process-group MECHANISM, not this cleanup, because this cleanup does not rely on the
# group. Saying "C17 is unreachable" would have been the easier sentence and a false one.
#
# Second residual, smaller: `reap_stray_players` reads the trace, then `ps`, then signals.
# A pid that dies and is recycled between the `ps` and the `kill` is signalled as a
# stranger. Unavoidable without a pidfd; the window is one `kill(2)` wide and the argv
# check has to pass first.
#
# THIRD RESIDUAL, AND IT IS THIS FILE'S OWN RULE TURNED ON ITSELF -- ask what the thing
# being terminated has for children. `reap_stray_players` signals a PLAYER pid, so:
#   * `afplay` and `player_probe.py` fork nothing that outlives them. `player_probe.py`
#     shells out to `/bin/ps` for its ledger identity via `subprocess.run`, which WAITS.
#     Killing the player pid is therefore complete for the `--pid-mode worker` arms.
#   * the `--pid-mode shared|perplayer` arms do not spawn the player directly. They spawn
#     `/bin/sh -c 'sleep $PUBDELAY; ...; exec "$@"'`, so `player_pid` names the WRAPPER
#     until the `exec`, and the wrapper forks `/bin/sleep` for the publish delay. A kill
#     landing inside that window takes the wrapper and leaves that `sleep` orphaned.
#     It is bounded by `--publish-delay-ms` (1500 ms at the longest, in C11b/C12b/C16a/
#     C17), holds no audio device, and exits on its own; it is named here rather than
#     swept because a group kill on the wrapper is the over-kill direction under
#     `--player-setsid on`, where the wrapper leads a session this driver did not create.
#     Both phases DO satisfy the argv check: the wrapper carries `inner` -- which ends in
#     `$OUT/$SID/player.log` -- on its own command line, and after the `exec` the player
#     carries it directly.
