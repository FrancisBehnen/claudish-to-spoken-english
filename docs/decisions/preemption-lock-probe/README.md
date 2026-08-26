# The preemption and lock-protocol probe rig

A **probe, not shippable code.** It exists to convert §13 rows 20 and 21 from
`[inferred]` into measured, and it is deliberately switchable so each clause can be
*falsified* as well as confirmed — a run in which the mechanism happens to work
proves nothing about the clause that makes it work.

Nothing here calls an LLM. Nothing here touches `rewrite.sh`, `providers.sh`,
`hooks/`, `bench/sanitizers.py`, `COND_CUTOFF`, or `~/.claude/settings.json`.

## Running it from a checkout

**Round 5 fixed the thing that made this section impossible to write.** Every driver used to
resolve its helpers from a private bench directory
(`RIG="$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25"`), and `run_preempt.sh` and
`run_lock.sh` invoked one user's absolute interpreter path. From any other checkout they failed;
on the author's machine they could execute **stale external copies of the very probes committed
here**, which is how a document premised on re-derivability quietly stops re-deriving.

Helpers now resolve relative to the script, so the drivers just run:

    ./run_lock.sh 20
    ./run_preempt.sh C3_adversarial 12
    ./run_all_preempt.sh 12

Three environment variables override, and the author's original layout is reachable through them:

| var | default | what it names |
| --- | --- | --- |
| `RIG` | the script's own directory | where the sibling scripts and probes are found |
| `OUT` | `$RIG/out` (`$RIG/out/lock` for `run_lock.sh`) | where run directories and results are written |
| `PYTHON` | `python3` | the interpreter. `run_real.sh` defaults to the Kokoro venv instead, because that arm imports `kokoro_onnx` (the probe does `from kokoro_onnx import Kokoro`; the distribution is `kokoro-onnx`); point `PYTHON` at any interpreter that can |

The stub arms need nothing but a stdlib `python3`. The re-derivations need no interpreter at all:
`summarise.sh <dir-with-the-four-TSVs>` and `analyse_round2.sh traces` are `awk` and `sort`.

The helpers that address the author's archived **run tree** rather than the rig's scripts —
`gather_out.sh`, `clean_copies.sh`, `peek.sh`, `peek_one.sh`, `assemble_pass1.sh` — keep the
external path as their default, because those run directories are not in the repository. They
take the same overrides.

## Files

| file | what it is |
| --- | --- |
| `speakd_probe.py` | the instrumented resident worker. §10.5's shape (file-drop job address, election with the owner pid recorded, `kqueue` wake, claim by `rename`), with every preemption clause independently switchable. Round 2 adds `--pid-mode {worker,shared,perplayer}` (who publishes the player's identity and where), `--publish-delay-ms` (the wrapper stays descheduled after `Popen`, so a sweep can land *before* publication), `--sweep-mode {off,record,pgid,both}`, `--sweep-gap-ms`, `--reap-delay-ms` and `--unlink-on-reap`. **Round 11 corrected the `.pending` sweep twice:** `killpg` now goes only to superseded owners whose **own generation** has a marker (one marker used to authorise every historical generation, spending the blast-radius bound the marker exists to provide), and each marker is retired only **after** its generation's group has been signalled (removing first left a crash window in which the next election finds no marker, skips `killpg`, and cannot reach the unnamed player by record either — `C12c` rebuilt out of the cleanup). Both are unrun |
| `player_probe.py` | stub player. Stands in for `afplay` so the probe can record *why* playback ended. Also self-registers in the player ledger |
| `hook_probe.sh` | stand-in for `speak.sh`'s `Stop` body, in **bash**, doing only the two things §10.6 gives the hook: read `speak/pid` and kill (**K**), then publish by atomic rename (**R**) |
| `lockrace.py` | row 21. Three election protocols — `current`, `spec`, `proposed` — plus a winner that can be stalled in the `mkdir`→pid-write window and racers that can be stalled *after* classifying a lock stale. **Round 11:** every election read is self-reporting (`election_read … saw_window=` plus the inode of the lock it read), so `run_lock.sh` can tell a trial that entered the staged window from one that quietly degenerated into a live-owner check |
| `run_preempt.sh` | row 20 driver. One warm worker per configuration; the second hook's launch time picks which ordering the trial lands in |
| `run_all_preempt.sh` | all **twenty-six** configurations in sequence. Round 3 fixed it: the loop listed 24, omitting `C15c_norecheck_death_pgid` and `C17_setsid_player`, so a fresh run did not reproduce the published set |
| `run_real.sh` | real-audio confirmation: real Kokoro synthesis on `bf_emma`, `afplay` as the player |
| `run_lock.sh` | row 21 driver. **Six** scenarios (S1 `init`, S2 `longstall`, S3 `aba`, S4 `dualreclaim`, S5 `scratch`, S6 `deadN`) × three protocols × N × stall. **Nothing in it is staged by a clock any more, and none of that is re-run.** Round 3 replaced S3's flat 4 ms wait for the second reclaimer with a wait on `classified_stale`. **Round 5 found the fixed sleeps that repair walked past** — the 50 ms staging the dead incumbent's own record in S3, S4 and S6 — which let those trials degenerate into S5's control while still producing `owners=1`. All three now gate on `pid_written`/`published` and emit `VOID` on timeout. **Round 11 found that the S1/S2 barrier stages the *observation* and not the *election read*** — after the `GO` token the winner writes its pid while each racer performs its own second, deciding read, and nothing orders the two. The answer is detection rather than a sixth staging mechanism: `trial_init` emits `VOID` unless some racer's `election_read` saw the pid-less state **and** the winner's own lock inode. **Expect that to void most of the `stall=0` cell**, because at 0 ms the window is zero-width and no staging can put a read inside it. The committed `lock-owners.tsv` predates **every** one of these fixes |
| `collect.sh` | joins the marker files, `kills.log`, `player.log` and `worker.trace` into one `trials.tsv` per run |
| `collect_real.sh` | turns the `REAL-*` traces into `real-audio-trials.tsv`, so section 2.6's figures re-derive like every other figure. **Round 5:** it now accepts the flat committed `traces/REAL-*.worker.trace` as well as live run directories — round 3 added the file but no way to rebuild it from anything committed — and it emits **both** bounds on the stale player's lifetime, because it had published `alive_s` as "`Popen` → exit" and that is not what `alive_s` measures |
| `summarise.sh` | every published figure, from the committed TSVs, with `awk` and `sort` only. **Medians average the two middle observations** — round 1 took the lower middle, which for these even-sized samples was not the median. Round 3 added section F (the `Rdone`→`P` adversarial margin) and split section C's `P`→`W` window by who published, both because the document quoted a figure the script did not print |
| `analyse_round2.sh` | the round-2 protocol facts, from the committed `traces/`. Round 3 added the `C12b` attribution (the `killpg`s actually sent, and the record sweep's unbounded target list), a `C14a` publish→destroy lag, and `C15c` alongside `C16`. **Round 5 removed that lag** — it anchored on `W_pid_write`, which in `C14a`'s `pid_mode=shared` is the parent's deferral stamp, so it never measured from publication — and replaced it with two soundly-ordered counts, which also cut the `C14a` destruction count from 24 unlinks to **8**, on **4** trials rather than 12 |
| `verify_fires.sh` | every hook stamps `$TAG.entry` before it does anything, so a hook that never ran is distinguishable from one that measured zero. **Round 5:** it read a `RUNS.txt` that exists only in a live run tree, so pointed at `traces/` it iterated over nothing and printed *"all hooks fired"* — a null reported as a pass, by the guard against exactly that. It now reads the committed `<cfg>.markers.tsv` too and exits 2 over zero inputs. **Round 10** added `expected-configs.txt` so a *partial* set could not read as a pass either, and that is where the committed evidence stands: **`verify_fires.sh traces 12` prints 21 `OK` lines, then `MISSING` for `C1_prespawn`, `C2_hookside`, `C5_norecheck`, `C6_handle` and `C7_noreap`, and exits 2.** The five have their twelve trial rows in `preemption-trials.tsv`; what they lack is the hook-fired marker evidence, so for those five alone a hook that never fired is indistinguishable from one that measured nothing. **The right response is to re-run them, not to loosen the guard** |
| `analyse_c14.sh` | hook C's reachability of a live player in the `C14` arms. **Corrected in round 3** — it had tested only that an END record existed, which every completed player satisfies. It now reads `tNc.entry` from `markers.tsv` and requires `start <= hook_c < end`. Reads the committed `traces/` directly: `analyse_c14.sh traces` |

## Timestamp names

Named as §13 row 20 names them.

| | |
| --- | --- |
| **K** | the hook reads `speak/pid` and kills it |
| **R** | the hook renames its job onto `speak/job` — the publication instant |
| **S** | the worker claims: `rename(job, job.taken.<pid>)` |
| **S2** | the worker's pre-spawn re-`stat` of `speak/job` (clause ii) |
| **P** | the player `Popen` |
| **W** | the worker writes `speak/pid` (clause i). **Only meaningful in the worker-published arms** — for `--pid-mode shared`/`perplayer` the probe stamps `W` in the *parent* right after `Popen`, before the wrapper has slept or renamed, so it is a deferral record and not a publication instant. `summarise.sh` splits the `P`→`W` window three ways for exactly this reason |

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
