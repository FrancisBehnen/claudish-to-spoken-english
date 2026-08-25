# The preemption and lock-protocol probe rig

A **probe, not shippable code.** It exists to convert §13 rows 20 and 21 from
`[inferred]` into measured, and it is deliberately switchable so each clause can be
*falsified* as well as confirmed — a run in which the mechanism happens to work
proves nothing about the clause that makes it work.

Nothing here calls an LLM. Nothing here touches `rewrite.sh`, `providers.sh`,
`hooks/`, `bench/sanitizers.py`, `COND_CUTOFF`, or `~/.claude/settings.json`.

## Files

| file | what it is |
| --- | --- |
| `speakd_probe.py` | the instrumented resident worker. §10.5's shape (file-drop job address, election with the owner pid recorded, `kqueue` wake, claim by `rename`), with every preemption clause independently switchable. Round 2 adds `--pid-mode {worker,shared,perplayer}` (who publishes the player's identity and where), `--publish-delay-ms` (the wrapper stays descheduled after `Popen`, so a sweep can land *before* publication), `--sweep-mode {off,record,pgid,both}`, `--sweep-gap-ms`, `--reap-delay-ms` and `--unlink-on-reap` |
| `player_probe.py` | stub player. Stands in for `afplay` so the probe can record *why* playback ended. Also self-registers in the player ledger |
| `hook_probe.sh` | stand-in for `speak.sh`'s `Stop` body, in **bash**, doing only the two things §10.6 gives the hook: read `speak/pid` and kill (**K**), then publish by atomic rename (**R**) |
| `lockrace.py` | row 21. Three election protocols — `current`, `spec`, `proposed` — plus a winner that can be stalled in the `mkdir`→pid-write window and racers that can be stalled *after* classifying a lock stale |
| `run_preempt.sh` | row 20 driver. One warm worker per configuration; the second hook's launch time picks which ordering the trial lands in |
| `run_all_preempt.sh` | all twenty-two configurations in sequence |
| `run_real.sh` | real-audio confirmation: real Kokoro synthesis on `bf_emma`, `afplay` as the player |
| `run_lock.sh` | row 21 driver. **Six** scenarios (S1 `init`, S2 `longstall`, S3 `aba`, S4 `dualreclaim`, S5 `scratch`, S6 `deadN`) × three protocols × N × stall |
| `collect.sh` | joins the marker files, `kills.log`, `player.log` and `worker.trace` into one `trials.tsv` per run |
| `collect_real.sh` | turns the `REAL-*` traces into `real-audio-trials.tsv`, so section 2.6's figures re-derive like every other figure |
| `summarise.sh` | every published figure, from the committed TSVs, with `awk` and `sort` only. **Medians average the two middle observations** — round 1 took the lower middle, which for these even-sized samples was not the median |

## Timestamp names

Named as §13 row 20 names them.

| | |
| --- | --- |
| **K** | the hook reads `speak/pid` and kills it |
| **R** | the hook renames its job onto `speak/job` — the publication instant |
| **S** | the worker claims: `rename(job, job.taken.<pid>)` |
| **S2** | the worker's pre-spawn re-`stat` of `speak/job` (clause ii) |
| **P** | the player `Popen` |
| **W** | the worker writes `speak/pid` (clause i) |

Hook-side stamps use the fork-free `: > file` marker technique the residency run
validated (~90 µs granularity, agreed with `$EPOCHREALTIME` to 47–277 µs); worker-side
stamps are `time.time()`. Both are wall clock.

## Attribution: distinct signals

The whole point of row 20 is *which* step killed the player, so each kill site sends a
different signal (Darwin numbering):

| signal | site |
| --- | --- |
| `SIGTERM` 15 | the hook's `speak/pid` kill |
| `SIGUSR1` 30 | the worker's claim-time kill (clause iii) |
| `SIGUSR2` 31 | a newly elected worker's ledger sweep (the proposed repair) |

The shipped design would use `TERM` for all three. The substitution changes nothing
about the mechanism, only about what the trace can prove.

Attribution is read from the player's **wait status** (`Popen.wait()` → `-signum`),
cross-checked against the player's own log. The wait status is the load-bearing one: a
kill landing inside the player's own interpreter startup terminates it by the signal's
default action before any handler exists, so the player's log stays empty and "killed
at once" would otherwise be indistinguishable from "never started".

## The stub, and why

Synthesis and playback are stubbed by default — a controlled `sleep` — because the
question is an **ordering**, and a stub isolates it far better than real audio. The
real-audio arm (`run_real.sh`) exists to answer the one thing the stub cannot: whether
the stale utterance is *audible*.

## The signal-attribution table, round 2

| signal | site |
| --- | --- |
| `SIGTERM` 15 | the hook's kill of the pid record(s) |
| `SIGUSR1` 30 | the worker's claim-time kill (clause iii) |
| `SIGUSR2` 31 | a newly elected worker's sweep **by record** |
| `SIGALRM` 14 | a newly elected worker's sweep **by process group**. `SIGHUP` was used first and abandoned: `nohup` sets it to `SIG_IGN`, inherited across fork *and* exec, which turned the sweep into a silent no-op. `speakd_probe.py` now records its signal dispositions at startup and refuses to run if a sweep signal is ignored |

## Why the election here is the generation protocol from row 21

`speakd_probe.py` elects with row 21's `proposed` protocol (`worker.lock.<gen>`, a
symlink whose target is the pid, dead owners superseded rather than removed) and not
with `mkdir`. That is not tidiness: **row 20's process-group sweep has to read the
superseded owner's pid**, and a protocol that deletes the record of the worker it
replaced cannot supply it. The two rows' repairs are coupled, and the coupling runs
in the direction row 21 → row 20.

## Round-2 configurations

| family | what it stages |
| --- | --- |
| `C11a` / `C11b` | the **single-record** form — one replaceable `speak/pid` written by the player — with the replacement worker elected **after** (`a`) and **before** (`b`) the player publishes. `b` is the ordering round 1 could not reach |
| `C12a` / `C12b` | the **process-group** repair, staged on both sides of publication |
| `C12c` | per-player records but **no** pgid sweep, to show which half does the work |
| `C13a` / `C13b` | the ledger **truncation** loss: the player publishes inside the gap between the sweep's read and its truncate. `b` is the same timing with per-player records |
| `C14a` / `C14b` | the **read-then-unlink TOCTOU**: an older player's reap completing after a newer player has replaced the shared record |
| `C15a` / `C15b` | clause (ii) **combined with worker death** — a newer job present at `S2` and the worker dying after the spawn |
