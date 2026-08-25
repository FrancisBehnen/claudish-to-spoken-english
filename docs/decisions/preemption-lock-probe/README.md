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
| `speakd_probe.py` | the instrumented resident worker. §10.5's shape (file-drop job address, `mkdir` election with a pid inside, `kqueue` wake, claim by `rename`), with each of clause 7's three preemption hooks independently switchable and a settable delay between the pre-spawn `stat` and the `Popen` |
| `player_probe.py` | stub player. Stands in for `afplay` so the probe can record *why* playback ended. Also self-registers in the player ledger |
| `hook_probe.sh` | stand-in for `speak.sh`'s `Stop` body, in **bash**, doing only the two things §10.6 gives the hook: read `speak/pid` and kill (**K**), then publish by atomic rename (**R**) |
| `lockrace.py` | row 21. Three election protocols — `current`, `spec`, `proposed` — plus a winner that can be stalled in the `mkdir`→pid-write window and racers that can be stalled *after* classifying a lock stale |
| `run_preempt.sh` | row 20 driver. One warm worker per configuration; the second hook's launch time picks which ordering the trial lands in |
| `run_all_preempt.sh` | all nine configurations in sequence |
| `run_real.sh` | real-audio confirmation: real Kokoro synthesis on `bf_emma`, `afplay` as the player |
| `run_lock.sh` | row 21 driver. Four scenarios × three protocols × N × stall |
| `collect.sh` | joins the marker files, `kills.log`, `player.log` and `worker.trace` into one `trials.tsv` per run |
| `summarise.sh` | every published figure, from the committed TSVs, with `awk` and `sort` only |

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

## `traces/` — the raw evidence the TSVs were derived from

The committed `preemption-trials.tsv`, `preemption-trials-pass1.tsv` and `lock-owners.tsv` are
**derived**. `traces/` holds the raw traces for the runs the conclusions turn on, so the
derivation can be checked rather than trusted:

- `C3_adversarial`, `C4_noclaimkill` — the adversarial ordering, with and without clause (iii)
- `C8_orphan`, `C9_ledger` — the `P`→`W` hole and the repair
- `C10a_nopid_pidfile`, `C10b_nopid_handle` — clause (i) removed, both claim-kill targets
- `REAL-pidfile`, `REAL-off` — the real Kokoro / `afplay` arms
- `lock-S3_aba-*` — the quarantine ABA, one trial per protocol
- `lock-S1_init-current-N2-s50`, `lock-S2_longstall-{spec,proposed}-N4-s1000` — the stall failures
- `lock-S5_scratch-proposed-N16` — the who-wins race at N = 16

Each row 20 config has four files: `worker.trace` (the worker's own `S`/`S2`/`P`/`W`, kill
attempts and player exit statuses), `player.log` (the player's own start/end and signal),
`hook-kills.log` (what each hook's `speak/pid` read found and did), and `markers.tsv` (the
hook-side `K`/`R` timestamps read out of the marker files with `stat -f %Fm`).

`collect.sh` joins those four into one `trials.tsv`; `assemble.sh` concatenates them;
`summarise.sh` produces every published figure with `awk` and `sort`; `compare_passes.sh`
prints pass 1 beside pass 2.
