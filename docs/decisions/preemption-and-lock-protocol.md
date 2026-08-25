# Preemption and the lock protocol — §13 rows 20 and 21, measured

**Date:** 2026-08-25. **Owner issue:** #11 (spec) — this document does **not** edit
`speech-integration-spec.md`; PR #27 is open on it. §"What §10.5, §10.6 and §13 will need
to say" carries the proposed replacement text, which is how every other measurement in
this project has been handed to #11.

**Nothing was implemented.** `speak.sh` still does not exist. `rewrite.sh`,
`rewrite-md.sh`, `providers.sh` and `hooks/` are untouched. `bench/` and `corpus/` are
untouched — `bench/sanitizers.py`, `COND_CUTOFF` and the trailing-slash rule
specifically. No LLM was called. `~/.claude/settings.json` was not modified; its sha256
was `b73f471a3f100d111d7a69387be3d0adaa8e37c6552b52362f7209fdbb3f945f` before this work
and `b73f471a3f100d111d7a69387be3d0adaa8e37c6552b52362f7209fdbb3f945f` after.

## Evidence labels

Same scheme as the rest of `docs/decisions/`. **[measured-here]** — produced by this
run's rig. **[rig]** — read out of a probe's own source. **[repo]** — read out of the
shipped tree. **[hook]** / **[obs]** — carried over from an earlier run, cited. **[inferred]**
— reasoned, not measured; every remaining one is named as such.

---

## 0. The headline, before the detail

**Row 20 — the two-kill design does not partition the timeline; the first proposed repair did
not close the gap either; the repair that does close it is a different mechanism, and it is
measured on both sides of the ordering that matters.**

- **Confirmed.** The adversarial ordering `R < S2 < R_b < P < W` was provoked and held on
  **48 of 48** trials, with the hook's own kill hitting nothing every time. Clause (iii), the
  worker's claim-time kill, is **load-bearing**: with it the stale player dies before it makes
  a sound (36/36); without it, in the identical ordering, it runs to completion (12/12), and in
  real audio two utterances overlap for **3.25–3.50 s** **[measured-here]**.
- **Uncovered region.** A worker dying between `Popen` and the pid write orphans a player
  nothing can reach — **12/12 played to completion**. The window is **median 1.27 ms** (range
  0.29–5.61), so this is a low-rate failure and is not presented as more.
- **The first revision's repair for it was wrong, and this is the correction that matters
  most.** It specified one player-written record and reported "12 of 12 orphans killed" — but
  it *measured* an append-only ledger, in an arm whose respawn delay guaranteed the sweep
  always ran **after** the player published. Staged on both sides, **the single-record form
  fails**: sweep before publication, the orphan plays to completion, **12/12** (`C11b`). Per-
  player records alone fail the same way (`C12c`, 12/12).
- **What does close it is process-group membership**, which `fork(2)` establishes before the
  child runs an instruction. `C12b`: sweep before publication, the player is **killed before it
  can `exec`**, 12/12, and never appears in the player log — while the record sweep in the same
  election reported `swept=0`, so only the group could have reached it.
- **Three measured qualifications on that repair.** A `.pending` marker created before the fork
  confines `killpg` to the window where an unnamed player can exist (`C16b` skipped it **25/25**
  when it was not needed; `C16a` used it 23/25 when it was). One keyword — spawning the player
  with `start_new_session=True` — **defeats the clause entirely** (`C17`, orphan plays to
  completion 12/12). And a sweep signal that anything ignores makes the sweep a silent no-op:
  `nohup` sets `SIGHUP` to `SIG_IGN`, inherited across `fork` and `exec`, which produced a
  **false "the repair fails"** for a whole run (§2.5).
- **Two further defects in the first revision's protocol, both reproduced.** Unlinking a
  *shared* pid record is a TOCTOU — an older player's reap destroyed a newer player's record
  **12/12**, and a hook fired inside the resulting window could not reach a live player on
  **4/12** trials. And the ledger's truncate erased registrations it had never signalled on
  **12 of 25** truncations. Per-player records fix both: **0/12** and **0** respectively.

**Row 21 — the spec's two clauses do not hold, and they were known not to hold before this
was run.** 1200 trials, three protocols, six scenarios **[measured-here]**:

| protocol | trials | worst case | trials ≠ 1 owner | rate |
| --- | --- | --- | --- | --- |
| `current` — the residency probe's own | 400 | **3 owners** | 121 | **30.2 %** |
| `spec` — §10.5 clause 2 (a) + (b) | 400 | **3 owners** | 61 | **15.2 %** |
| **`proposed`** — atomic `symlink` owner record, superseded by generation | 400 | **1** | **0** | **0.0 %** |

`spec` is a genuine improvement and still fails: clean to a 50 ms stall (180/180, where
`current` fails 60 of the same 180), then **40/40 wrong at 200 ms and 1000 ms** — a bounded
backoff cannot distinguish a descheduled winner from a dead one — and **20/20 wrong on the
quarantine ABA**, where `rename(2)` is atomic on a *path* and a reclaimer acting on a stale
observation renames the fresh owner's live lock and gets success rather than `ENOENT`.

**And the two rows are now coupled.** Row 20's process-group sweep must read the *superseded*
owner's pid, which only row 21's generation protocol supplies — a protocol that deletes the
record of the worker it replaced cannot. They can no longer be signed off independently.

**Both rows stay ship-blocking**, and the reason has changed: they are no longer unverified.
**Three consecutive rounds of review have each found a real defect in the previous round's
confident answer**, including in the repair this document proposed. See §6.

---

## 1. What was run, and what it is not

**A synthetic harness, deliberately, and no driven `claude` session at all.** Both
mechanisms are worker-and-filesystem level. Driving real turns would have bought realistic
`Stop` timing and cost the only thing that matters here — control over the ordering. The
hook's own contribution to that ordering is a single measured constant, and it was already
measured from real hooks: **the kill-to-rename gap, 0.063–0.219 s, median 0.086 s**
**[hook]**, reproduced here by `HOOK_GAP_S=0.09` and landing at **median 125.6 ms, range
103.8–206.1 ms** measured, which is inside that band (§2.1). Nothing else about a real turn enters
either mechanism. **No number in this document came from a driven session, and none needed
to.**

**Synthesis and playback are stubbed by default.** The question is an ordering; a
controlled `sleep` isolates it and real audio does not. One arm uses real Kokoro on
`bf_emma` with `afplay`, and it is labelled where it appears (§2.6).

**Attribution is by distinct signal.** `SIGTERM` 15 for the hook's pid kill, `SIGUSR1` 30
for the worker's claim-time kill, `SIGUSR2` 31 for the election sweep (Darwin numbering).
The shipped design would use `TERM` for all three; the substitution changes nothing about
the mechanism and is the only reason the trace can say *which* step fired rather than
merely that the player died. **"Was it audible" was never the observation** — the brief was
explicit that it is insufficient, and the data shows why twice over: `C3` and `C6` are
audibly identical (both silent, 12/12) and use different kill targets; `C3` and `C10b` are
audibly *different* (silent versus 0.70 s) while both are killed by the same clause. An
audibility-only record would have merged the first pair and split the second.

**Attribution is read from the player's wait status, cross-checked against the player's
own log.** This matters and cost one wasted pass to learn: a kill landing inside the
player's own interpreter startup terminates it by the signal's default action *before any
handler is installed*, so the player's log stays empty and "killed instantly" is
indistinguishable from "never started" **[measured-here]**. The parent's returncode is
exact. Both are recorded and they agree.

**Two arms, both committed.** All 24 configurations were run in one sweep. `C1`–`C10` were
additionally run in an earlier round and are re-collected here with the *current* collector, so
the two arms are compared under the same predicate rather than across a changed derivation:
[`preemption-trials.tsv`](preemption-trials.tsv) is the published set,
[`preemption-trials-replication.tsv`](preemption-trials-replication.tsv) the replication, and
`preemption-lock-probe/compare_passes.sh` prints them side by side.

**Three derivation defects were found by review of this document's first revision, and all three
are fixed here. Two of them made the reproducibility claim false, which was the claim the whole
document rested on.**

1. **The medians were not medians.** `summarise.sh` took `v[int((NR+1)/2)]`, the **lower middle**
   observation. Every sample here is even-sized, so the script systematically did not re-derive
   the values printed as medians. There is now one `med()` helper that averages the two middle
   observations, used by every block. **Numerically it moves almost nothing** — `P`→`W` goes
   from 1.3320 to 1.3331 ms on the replication arm, and the hook-kill-to-death median from
   0.7696 to 0.7755 ms — **and
   that is not a defence.** The figures were not reproducible from the committed script, and
   "every figure re-derives" was the premise the document was shipped on.
2. **The adversarial predicate did not check what the document claimed.** `R` is stamped
   *before* the external `mv`, so a trial where `P` fell inside the rename would still have
   counted as adversarial. The predicate now uses the `Rdone` marker — stamped *after* `mv`
   returns, so publication is demonstrably complete — and requires `Rdone < P` as well as
   `Rdone > S2` and `K < W`. `Rdone_b` is carried into `preemption-trials.tsv` so it can be
   re-checked by hand. **Re-deriving the earlier data under the corrected predicate reclassifies
   zero trials** on the replication arm, and the reason is quantitative: the rename itself
   takes a median 11.2 ms there (12.8 ms on the published arm), while the margin from `Rdone`
   to `P` on the adversarial trials is a median **446 ms** (range 419–473). The check was missing; it was never close to binding.
3. **Section 2.6 had no derivation at all.** There was no input for the `REAL-*` traces, so the
   real-audio figures could not be re-derived. `collect_real.sh` now produces a committed
   [`real-audio-trials.tsv`](real-audio-trials.tsv) and `summarise.sh` has a section over it.

**Three HARNESS defects were also found and are disclosed here, because two of them changed
results and one of them destroyed data.** They are listed rather than quietly fixed, since a
reader deciding how much to trust these numbers should know what went wrong in producing them.

1. **`nohup` made the process-group sweep a silent no-op.** The sweep used `SIGHUP`; `nohup`
   sets it to `SIG_IGN`, inherited across `fork` *and* `exec`. `killpg` returned success and
   nothing died. This produced a **false "the repair fails", 12/12**, which would have been
   published as a design result. The sweep signal is now `SIGALRM`, and the worker records its
   signal dispositions at startup and exits 3 if a signal it depends on is ignored. Every
   configuration whose result depended on that sweep was re-run.
2. **`cp -R` destroyed hook timestamps.** The hook-side `R`/`K`/`Rdone` values *are* the marker
   files' mtimes, and copying a run directory rewrote them — producing rows whose hook
   timestamps sat minutes from their own worker trace. Run directories are now referenced in
   place and never copied; `gather_out.sh` carries the reason.
3. **A `case` pattern over a multi-line list deleted four run directories.** `*" $cfg "*` does
   not match an entry adjacent to a newline. Those four configurations were simply re-run. This
   one cost time, not correctness.

**The first two are the reason this revision re-ran everything rather than patching numbers.**

Rig: [`preemption-lock-probe/`](preemption-lock-probe/README.md). Every figure below re-derives
from the committed TSVs with `awk` and `sort` only — `summarise.sh` and `analyse_round2.sh` are
the derivations, and `verify_fires.sh` confirms every hook fired (25 entry markers per
configuration: one warm-up plus two per trial) so that a null result can be distinguished from a
hook that never ran. Unlike the residency run's `[rig]`, **this probe is in the repository**, so
its protocol can be read as well as its output.

---

## 2. Row 20 — preemption

### 2.1 Twenty-six configurations

One warm worker per configuration — it has already elected, loaded, synthesised and
played before the first trial. Then twelve trials of two `Stop` hooks (three, in the
`C14` arms). The second hook's launch time is what selects the ordering; nothing is
sampled and hoped for. **26 configurations × 12 trials = 312 trials, and every
configuration is uniform 12/12** on the outcome reported for it.

Nominal timeline of one trial, from hook A's rename `R_a = t0`, synth 1.0 s, pre-spawn
delay `D`:

```
S  = t0             claim: rename(job, job.taken.<pid>)
S2 = t0 + 1.0       pre-spawn re-stat of speak/job            (clause ii)
P  = t0 + 1.0 + D   player Popen
W  = P + ~1 ms      pid record published  (by the worker, or by the player)
K_b = t0 + GAP                    hook B reads the record(s) and kills
R_b = t0 + GAP + 0.126            hook B renames its job into place
```

The kill-to-rename interval came out at **median 125.6 ms, range 103.8–206.1 ms**, n = 312
**[measured-here]** — inside the real hook's measured **0.063–0.219 s** band **[hook]**, and
near its middle. The rename itself takes a median **12.8 ms** (range 3.9–61.2), which is
why `Rdone` rather than `R` is now the publication bound (§1).

`RESPAWN_DELAY` — how long after hook B a replacement worker is elected — is the knob that
decides whether a sweep lands **before** or **after** the player publishes. **In the first
revision it was hardcoded at 1.2 s, which guaranteed every sweep ran after publication**, and
that single fact is why the first revision's repair looked closed when it was not.

### 2.2 Which step killed the player — the whole of row 20 in one table

Attribution from the player's wait status, cross-checked against its own log; the two agree
on every row where both exist. `killed-before-exec` means the player was spawned, never
logged a start, and has no exit status — a player that survives to run always logs, so this
is a kill that landed before `exec`.

| config | what it varies | which step killed the player | stale audio, s |
| --- | --- | --- | --- |
| `C1_prespawn` | recheck sees the newer job | **no player spawned** | none |
| `C2_hookside` | `R_b` after `W` | **hook kill** | 0.556–0.581, med 0.565 |
| `C3_adversarial` | **`R<S2<R_b<P<W`** | **worker claim-time kill** | **0 — never started** |
| `C4_noclaimkill` | clause (iii) **off** | **NOTHING** | 2.500–2.513, **full** |
| `C5_norecheck` | clause (ii) **off** | worker claim-time kill | **0 — never started** |
| `C6_handle` | (iii) via in-memory handle | worker claim-time kill | **0 — never started** |
| `C7_noreap` | worker never `wait()`s | hook kill — and **both** sites reported success against a **zombie** | 0.549–0.577 |
| `C8_orphan` | worker dies in `P`→`W` | **NOTHING** | 2.501–2.505, **full** |
| `C9_ledger` | + append-only ledger sweep | election sweep (record) | 0.816–0.870 |
| `C10a_nopid_pidfile` | clause (i) off, (iii) reads record | **NOTHING** | 2.502–2.510, **full** |
| `C10b_nopid_handle` | clause (i) off, (iii) holds handle | worker claim-time kill | 0.563–0.714 |
| **`C11a_shared_pubfirst`** | **single record**, sweep **after** publish | election sweep (record) | 0.770–0.837, med 0.811 |
| **`C11b_shared_sweepfirst`** | **single record**, sweep **before** publish | **NOTHING** | **2.501–2.504, full** |
| **`C12a_pgid_pubfirst`** | **process group**, sweep after publish | **election sweep (pgid)** | 0.738–0.841, med 0.795 |
| **`C12b_pgid_sweepfirst`** | **process group**, sweep **before** publish | **killed before exec** | **0 — never started** |
| `C12c_perplayer_recordonly` | per-player records, **no** pgid sweep | **NOTHING** | 2.502–2.506, **full** |
| `C13a_ledger_truncate` | publish inside the sweep's read→truncate gap | **NOTHING** | 2.501–2.504, **full** |
| `C13b_perplayer_sametiming` | same timing, per-player + pgid | **killed before exec** | **0 — never started** |
| `C14a_shared_unlink` | shared record, reap unlinks late | hook kill | 0.489–0.553 |
| `C14b_perplayer_unlink` | per-player record, same timing | hook kill | 0.471–0.528 |
| `C15a_recheck_death` | recheck **on** + worker death | **no player spawned** | none |
| `C15b_norecheck_death` | recheck **off** + worker death, no sweep | **NOTHING** | 2.501–2.504, **full** |
| `C15c_norecheck_death_pgid` | the same **with** clause (iv) | election sweep (record) | 0.384–0.435, med 0.407 |
| **`C16a_pending_sweepfirst`** | `.pending` marker, sweep before publish | **killed before exec** | **0 — never started** |
| **`C16b_pending_pubfirst`** | `.pending` marker, sweep after publish | election sweep (record) | 0.693–0.804, med 0.781 |
| **`C17_setsid_player`** | `C12b` + the player **leaves the group** | **NOTHING** | **2.501–2.504, full** |

**[measured-here]**; `summarise.sh` sections A and B over `preemption-trials.tsv` re-derive
every row.

**The adversarial ordering was reached, not sampled.** `R < S2 < R_b < P < W` held on all
**48** trials of `C3`–`C6` under the corrected predicate — publication demonstrably complete
before `P`, with a margin of median **446 ms** — and on all 48 the hook's own kill returned
`ESRCH`. **No trial in `C3`–`C6` saw a live pid**, which is the precondition §13 row 20
insisted on.

### 2.3 What each clause is actually worth

- **Clause (iii), the claim-time kill: REQUIRED, and confirmed by falsification.** Remove it
  and the stale player runs its full length, 12/12 (`C4`), with nothing in the design touching
  it. In real audio two utterances overlapped for **3.25–3.50 s**.
- **Clause (iii) must kill BOTH targets.** `handle` and `pidfile` are indistinguishable while
  the record exists (`C3` vs `C6`, 24/24 identical) and **opposite** when it does not
  (`C10a` NOTHING vs `C10b` killed, 12/12 each way).
- **Clause (i)'s independent value is latency.** In `C2` the hook reached the player a median
  **134 ms** sooner (range 123–143) than the worker's next claim would have.
- **Clause (ii) is correctness-relevant only in the absence of clause (iv), and this now has
  both arms.** The first revision claimed it was "an optimisation, not a correctness clause"
  on the strength of `C5` alone; review pointed out that `C5` only removes the recheck while
  the worker *survives*. Staged properly:
  - `C15a` (recheck on, worker dies after the spawn): **no player is ever spawned**, 12/12 —
    the recheck discards the stale job, so there is nothing to orphan.
  - `C15b` (recheck off, same death, no sweep): the stale player is spawned and orphaned,
    and **NOTHING kills it**, 12/12. So the recheck *does* prevent an orphan the no-recheck
    arm creates. **The first revision's conclusion was wrong as stated.**
  - `C15c` (recheck off, same death, **with** clause (iv)): the orphan is killed, 12/12, after
    a median 0.407 s. **So clause (ii)'s correctness role is conditional on (iv) being
    absent.** With (iv) it returns to being an optimisation — which is the accurate form of
    the claim, and it needed three arms rather than one.

### 2.4 The uncovered region, and what actually closes it

§10.6 says the two kills *"partition the timeline at the `speak/pid` write"*. They partition
it at the **pid record's publication**, which under clause 7(i) is a different instant from
the spawn. `C8` measures the consequence: the worker dies between `Popen` and the write, the
hook reads a pid that predates the orphan, a replacement worker's claim-time kill reads the
same stale pid, and the orphan **plays to completion, 12/12**. The window is **median 1.27 ms,
range 0.29–5.61 ms**, n = 96 — small, and this document does not inflate it.

**The first revision's repair for this does not work, and that is the most important
correction in this revision.** It specified *one replaceable record, written by the player
before it can make a sound*, and reported "12 of 12 orphans killed". What it measured was an
append-only ledger, in an arm whose 1.2 s respawn delay meant the sweep always ran **after**
the player published. Staged on both sides:

| repair | sweep **after** publication | sweep **before** publication |
| --- | --- | --- |
| single record written by the player (`C11a` / `C11b`) | killed 12/12 | **NOTHING, 12/12, full length** |
| per-player records, record sweep only (`C16b` / `C12c`) | killed 12/12 | **NOTHING, 12/12, full length** |
| **process-group sweep** (`C12a` / `C12b`) | killed 12/12 | **killed before exec, 12/12** |

**Publishing from the player does not close the region**, because the wrapper can stay
descheduled between `Popen` returning and its own first instruction, and a one-time sweep in
that gap sees nothing. **What closes it is process-group membership, which is established by
`fork(2)` before the child executes an instruction.** In `C12b` the player never appears in
`player.log` at all, and the trace shows why it could only have been the group: the record
sweep in the same election reported `swept=0`, having found nothing but the previous, dead
player.

**Three qualifications, all measured.**

1. **`killpg` on every election has a worse blast radius than one pid kill.** If a superseded
   owner's pid has been recycled as a group leader, the sweep signals strangers — a whole
   group, not one process. So the worker creates `playerdir/<nonce>.pending` **before** the
   fork and the wrapper renames it away as its first act, making *"an unnamed player may
   exist"* observable and confining `killpg` to that window. Measured: `C16a` (sweep before
   publication) found a `.pending` at 23 of 25 sweeps and used `killpg` 23 times, killing the
   player before `exec` 12/12; `C16b` (sweep after publication) found **none**, **skipped
   `killpg` 25 times out of 25**, and the record sweep did the work 12/12.
2. **One line defeats the whole clause.** `C17` is `C12b` with the player spawned into its own
   session — `start_new_session=True`, one keyword — and the orphan **plays to completion,
   12/12**. Never detaching the player is therefore normative, not stylistic, and it is
   exactly the line an implementer adds for unrelated reasons.
3. **The sweep signal must not be one anything ignores.** See §2.5.

### 2.5 Five things the run found that nobody asked about

**1. `kill(2)` on an unreaped zombie SUCCEEDS.** In `C7` the worker never `wait()`s its
player; both kill sites then reported success on all 12 trials against a process the hook had
killed 0.56 s earlier. `C2` is identical except that the worker reaps, and there the
claim-time kill correctly reports `ESRCH`. **A worker that does not reap makes its own
preemption logic unfalsifiable from the inside**, and §10.5 says nothing about reaping.

**2. Nothing unlinks the record, and the hook routinely kills a pid that is not the current
player.** On all 48 adversarial trials the hook's kill returned `ESRCH` against a pid left by
an earlier trial. `ESRCH` is harmless; the same read after that pid is **recycled** is not.
Recycling was not observed (**[inferred]**), but the stale read that precedes it was observed
48/48.

**3. Unlinking a SHARED record is a TOCTOU, and its consequence is observed.** `C14a` gives
the reaper a 1.2 s delay: on **12 of 12** trials an older player's reap unlinked the shared
path **after** a newer player had published into it, 31–76 ms later. A third hook fired while
that newer player was still playing then **found no record at all on 4 of 12 trials** — unable
to preempt a live player. With per-player records (`C14b`, identical timing) every one of 25
unlinks removed only its own name, **0 of another player's**, and the third hook reached the
live player **12 of 12**.

**4. The ledger's truncate erases registrations it never signalled.** `C13a` stages a
publication inside the gap between the sweep's read and its truncate. Of 25 truncations,
**12 erased an entry that had been appended after the read** — a player registered and then
un-registered without ever having been signalled — and all **25 record sweeps swept nothing**.
`C13b` runs the identical timing against per-player records: **zero truncations**, and the
player killed before `exec` 12/12. The append-only ledger measured in the first revision was
not merely a different protocol from the one specified; it has a defect of its own.

**5. A sweep signal that anything ignores makes the sweep a silent no-op — and this cost a
whole run.** The process-group sweep first used `SIGHUP`. The sweep was launched under
`nohup`, which sets `SIGHUP` to `SIG_IGN`, **a disposition inherited across `fork` and
`exec`** — so every worker and every player ignored it, `killpg` reported `sent`, and `C12b`
reported "the repair fails" 12/12. It was the harness, not the design. The sweep signal is now
`SIGALRM`, and **`speakd_probe.py` records its signal dispositions at startup and exits 3 if a
signal it depends on is ignored**, so the same false negative cannot recur silently. It is
recorded here because it is the exact failure mode the brief warns about — a mechanism that
never fired, producing a null indistinguishable from a real negative — and because it would
have been published as a design result.

### 2.6 The real-audio arm

Real Kokoro synthesis on `bf_emma`, `is_phonemes=False`, `/usr/bin/afplay` as the player, two
distinguishable utterances, the `C3` ordering, 3 trials per arm. This arm answers audibility
only; the stub arms establish the ordering and the attribution.

| arm | result |
| --- | --- |
| claim-time kill **on** | the stale `afplay` lived **13.0, 17.5 and 18.6 ms** against a 5.7 s wav; the newer utterance then played in full, 3/3 |
| claim-time kill **off** | both `afplay`s ran to completion and **overlapped for 3.2486, 3.2564 and 3.4981 s**, 3/3 |

**[measured-here]**, and now re-derivable: `real-audio-trials.tsv` is a committed evidence
file and `summarise.sh` section E prints these figures from it. The first revision published
them with no derivation at all.

**One honest limit.** What is measured is that the process lived 13–19 ms. Whether that is
short enough that no sample reached the output device is **[inferred]** — `afplay`'s
time-to-first-sample was not measured, and nothing here listens. The experiment that removes
the inference is a loopback capture, not a longer run.

## 3. Row 21 — the lock protocol

### 3.0 First, the thing this is NOT about

**The measured 8/8 `mkdir` result is untouched, and it answers a different question.** That
result — the hook's `[[ -d worker.lock ]] && kill -0` pre-check lost the race 8 times out of
8 against eight simultaneous hooks, and the `mkdir` inside the worker is the guarantee
**[obs]** — is about **who wins** a contended election. Row 21 is about whether a protocol
can **misclassify the winner** after the election has been decided. The two look
interchangeable and are not, and conflating them would let a passing who-wins result stand in
for a protocol that produces two resident workers.

To keep them visibly separate, scenario **S5** re-runs the who-wins race — N racers from an
empty directory, no incumbent — against all three protocols. **All three produced exactly one
owner on 80 of 80 trials each, at N = 2, 4, 8 and 16 [measured-here].** So the `mkdir` result
generalises, and `symlink(2)` has the same exclusive-create property `mkdir` has. Nothing
below disturbs it.

### 3.1 Three protocols, six scenarios, 1200 trials

`current` is the residency probe's own protocol, read out of its source **[rig]**. `spec` is
§10.5 clause 2 as PR #27 states it: (a) a lock with no pid is *initializing*, retry on a
bounded backoff (20 attempts × 2 ms), reclaim only if the pid is still absent afterwards; and
(b) reclamation serialized by an atomic `rename` into a unique quarantine name. `proposed` is
§4a.

**Both of `spec`'s clauses were found insufficient by review of PR #27 before this run
started**, so the run tests three protocols rather than two, and the scenarios include the
two orderings that review named:

| | scenario | what it stages |
| --- | --- | --- |
| **S1** | `init` | the winner is stalled between `mkdir` and its pid write by 0 / 5 / 50 ms. The window clause (a) exists for. N = 2, 4, 8 |
| **S2** | `longstall` | the same, stalled **200 ms and 1000 ms** — longer than clause (a)'s own backoff. **Review finding 1** |
| **S3** | `aba` | a lock owned by an already-exited pid, so reclamation is legitimate. Reclaimer A acts at once; reclaimer B classified stale at the same instant but is held 120 ms before acting, so it acts on a stale observation. **Review finding 2** |
| **S4** | `dualreclaim` | two reclaimers, no asymmetry — to separate *simultaneous* reclamation from reclamation on a *stale* observation |
| **S5** | `scratch` | no incumbent. The already-measured who-wins race (§3.0) |
| **S6** | `deadN` | legitimate reclamation under contention: a dead incumbent and N = 2, 4, 8 racers |

20 repetitions per cell. Metric: **how many processes conclude "I own the session"** in one
trial. 1 is correct. 2 means two resident workers, each holding a ~340 MB model, racing the
claim-rename for every job.

### 3.2 The result

Owner counts, 20 trials per cell **[measured-here]**:

| scenario | `current` | `spec` | `proposed` |
| --- | --- | --- | --- |
| S1, stall 0 ms | 1 (60/60) | 1 (60/60) | **1 (60/60)** |
| S1, stall 5 ms | 1 (60/60) | 1 (60/60) | **1 (60/60)** |
| S1, stall 50 ms | **2 (58/60), 3 (2/60)** | 1 (60/60) | **1 (60/60)** |
| S2, stall 200 ms | **2 (20/20)** | **2 (18/20), 3 (2/20)** | **1 (20/20)** |
| S2, stall 1000 ms | **2 (20/20)** | **2 (19/20), 3 (1/20)** | **1 (20/20)** |
| S3, ABA | **2 (20/20)** | **2 (20/20)** | **1 (20/20)** |
| S4, dual reclaim | 1 (20/20) | 1 (20/20) | **1 (20/20)** |
| S5, who-wins | 1 (80/80) | 1 (80/80) | **1 (80/80)** |
| S6, dead + N racers | 1 (59/60), **2 (1/60)** | 1 (59/60), **2 (1/60)** | **1 (60/60)** |

Totals:

| protocol | trials | worst case | trials ≠ 1 owner | rate |
| --- | --- | --- | --- | --- |
| `current` | 400 | **3 owners** | 121 | **30.2 %** |
| `spec` | 400 | **3 owners** | 61 | **15.2 %** |
| **`proposed`** | 400 | **1 owner** | **0** | **0.0 %** |

`summarise.sh` sections A–C over `lock-owners.tsv` re-derives every cell.

### 3.3 What each row means

**`current` fails as predicted, and worse than predicted.** §13 row 21 said the current
protocol *"should produce 2"*. It produces 2 on 119 trials — and **3 on two of them**. Three
owners is the misclassification cascading: two racers each tear down the lock and install
their own, and a third arrives between those events. The prediction was right about the
direction and one short on the magnitude.

**`spec` clause (a) works exactly as far as its timeout and no further.** At stalls of 0, 5
and 50 ms it is clean, 180/180 — that is the clause doing its job, and it is a real
improvement over `current`, which fails 60 of those same 180. At **200 ms and 1000 ms it fails
40 out of 40.** This is **review finding 1, measured**: the clause replaces "a lock with no
pid is abandoned" with "a lock with no pid for more than ~40 ms is abandoned", and a live
winner that is descheduled, paged in, or `SIGSTOP`ped for longer than that is misclassified
just the same. **A bounded backoff narrows this window; it cannot close it, because there is
no bound on how long a live process may take to reach its next statement.**

**`spec` clause (b) does not survive contact with a stale observation, 20 out of 20.** This is
**review finding 2, measured**, and the trace names it in one line — the quarantining racer
logs the pid it removed:

```
winner 71456  mkdir_ok
winner 71456  pid_written        owner=71458          <- a pid that has already exited
racer  71459  classified_stale   reason=pid_dead pid=71458
racer  71461  classified_stale   reason=pid_dead pid=71458
racer  71461  quarantine_won     to=...dead.71461...  quarantined_pid=71458   <- correct
racer  71461  mkdir_ok
racer  71461  owner              via=election
racer  71459  quarantine_won     to=...dead.71459...  quarantined_pid=71461   <- WRONG
racer  71459  mkdir_ok
racer  71459  owner              via=election
```

(`out/lock/S3_aba-spec-r1/log.tsv`, verbatim but with the timestamps and full paths trimmed.)
The second reclaimer examined a lock owned by dead pid `71458` and then quarantined a lock
owned by **`71461` — the first reclaimer's own, live, freshly created lock.** `rename(2)` is
atomic, but it is atomic on a **path**, and nothing in the protocol makes a reclaimer notice
that the object at the path is not the one it inspected. It gets success, not `ENOENT`. Then
it installs its own lock, and the first reclaimer — still running, still believing it owns the
session — has had its lock deleted underneath it. **This is also exactly the third failure
§10.5 names** (*"lets a reclaimer `rmdir` a lock a third process has meanwhile legitimately
re-created"*) — §10.5 attributes that failure to `rmdir`-then-`mkdir` and says the rename fixes
it. **The rename has the same failure.**

**S4 is the control that makes S3 mean something.** Two reclaimers with no asymmetry produced
one owner, 60/60 across all three protocols. So it is not *concurrent* reclamation that breaks
`current` and `spec` — it is reclamation acting on an observation that has gone stale. Without
S4, S3 could have been read as "two reclaimers is unsafe", which is a different and wrong
conclusion.

**S6's single failures (1 in 60, both protocols) are the same defect at its natural window
width.** No stall was injected; the ABA simply happened on its own once per 60 trials under
contention. That is the honest answer to *"the failure windows are microseconds wide"* — at
N = 8, unprovoked, it fires at roughly 2 %.

**`proposed` is clean on 400 of 400.** It never encounters the pid-less state, because a
`symlink`'s target is created with the object; it never removes a contested path, because a
dead owner is superseded by a **new generation**; and it wins the who-wins race at N = 16.
**S1 and S2 are structurally vacuous for it and this must be said rather than counted as a
pass** — there is no `mkdir`→write window for a stall to sit in, so a stalled-but-live winner
is simply seen as alive. The scenarios that genuinely test it are **S3 (20), S4 (20), S5 (80)
and S6 (60)** — **180 of its 400 trials**; without S4's control that is 160.

---

## 4. What §10.5, §10.6 and §13 will need to say

Proposed replacement text. **§10.5 clause 2 and clause 7, and §10.6's first bullet, are
SUPERSEDED rather than confirmed** — clauses (a) and (b) of the lock protocol were found
insufficient **by review, before they were ever measured**, and the measurement then
reproduced both failures. An integrator folding this in should replace those clauses, not
annotate them.

### 4a. §10.5 clause 2 — replace both sub-clauses

> **2. The election publishes a COMPLETE owner record atomically, and never infers death
> from an absent one.** `symlink(str(os.getpid()), speak/worker.lock.<gen>)`.
>
> - **`symlink(2)` creates the object and its content in one step, and fails `EEXIST` if
>   the path exists.** So there is no interval in which a lock exists without an owner, and
>   the question clause (a) used to answer — *what does a pid-less lock mean* — does not
>   arise. A `mkdir` followed by a write cannot have this property, because it is two steps.
> - **Liveness is decided only by `kill(pid, 0)` on a complete record.** No backoff, no
>   timeout, nothing for a descheduled or `SIGSTOP`ped winner to defeat. **This is the
>   repair for review finding 1:** a fixed backoff is a bet that a live process will make
>   progress inside it, and an election must not make that bet. The old clause (a) narrowed
>   the window from microseconds to tens of milliseconds; it did not close it, and a stalled
>   winner walks straight through it — measured.
> - **A dead owner is SUPERSEDED by creating generation `gen+1`, never by removing
>   generation `gen`.** Nothing is ever unlinked from a contested path, so there is no path
>   for an ABA to land on. **This is the repair for review finding 2:** `rename(2)` is
>   atomic but it is *path*-addressed, so a reclaimer acting on a stale observation renames
>   whatever is at the path now — including a fresh lock a different process legitimately
>   just created — and gets success rather than `ENOENT`. Measured.
> - **Ownership is "I created the highest generation record"**, read with one `readdir` and
>   one `readlink`. A worker may unlink generation `g` once `g+1` exists, and
>   `rewrite.sh:117`'s 30-minute sweep catches the rest — removing an *obsolete* generation
>   cannot affect who owns the current one, which is exactly why this cleanup is safe where
>   the quarantine rename was not.
>
> **Measured: exactly 1 owner on 400 of 400 trials**, against 121/400 wrong for `current` and
> **61/400 wrong for the clause this replaces**. Worst case observed for both of the others was
> **3** owners, not 2.
>
> **What is NOT changed.** The hook's pre-check stays a best-effort optimisation, and the
> **measured 8/8 result stands untouched**. That result is about **who wins** a contended
> exclusive-create, and `symlink` has the same exclusive-create property `mkdir` has —
> re-measured here at N = 2, 4, 8 and 16 from an empty directory, 1 owner on 80 of 80.
> **Row 21 was never about who wins; it is about misclassifying the winner**, and the two must
> not be conflated.
>
> **Alternatives considered, and why `symlink` rather than each.** `open(O_CREAT|O_EXCL)` on a
> file is exclusive but its *content* is still a second write, so it has the pid-less window
> this clause exists to remove. Darwin's `renamex_np(..., RENAME_EXCL)` would let a
> fully-populated directory be published atomically, and it is the closest true equivalent —
> rejected because it is Darwin-only, needs `ctypes`, and buys nothing `symlink` does not.
> Publishing a *file* whose name carries the pid is the same idea with a worse read path
> (`readdir` and parse, instead of one `readlink`). **`symlink` was chosen because the content
> is the target and POSIX requires the create to be exclusive** — both properties in one call,
> in one line of Python or one `ln -s`.

### 4b. §10.5 clause 7 — five hooks, and two of the first revision's are wrong

> **7. §10.5 owes §10.6 five hooks. Every clause below names the arm that measured it.**
>
> - **(i) The pid record is per-PLAYER, at a unique path, published by the player before it
>   can make a sound. REQUIRED.** `speak/playerdir/<pid>.<nonce>`, written by a wrapper that
>   then `exec`s, and unlinked only by exact name. **One shared `speak/pid` must not be used:**
>   an older player's reap unlinked a newer player's record on 12/12 trials, and a hook firing
>   in that window could not reach a live player on 4/12 (`C14a`); with per-player names, 0/12
>   (`C14b`). **An append-only ledger must not be used either:** its truncate erased
>   registrations it had never signalled on 12 of 25 truncations (`C13a`).
> - **(ii) The pre-spawn re-`stat` of `speak/job` is an optimisation GIVEN (iv), and a
>   correctness clause without it.** With the worker surviving, removing it changes nothing
>   (`C5`, 12/12). With the worker dying after the spawn and no sweep, removing it **creates an
>   orphan that nothing kills** (`C15b` 12/12 versus `C15a`, where no player is spawned at
>   all). With clause (iv) present the orphan is caught anyway (`C15c`, 12/12). Keep it; state
>   the condition.
> - **(iii) The worker kills the current player the moment it claims a newer job. REQUIRED,
>   and it must kill BOTH targets** — its own handle *and* every published record. Measured
>   load-bearing (`C4`: without it, 12/12 run to completion). The two targets are
>   indistinguishable while a record exists (24/24) and opposite when none does (12/12 each
>   way, `C10a`/`C10b`).
> - **(iv) A newly elected worker kills the PROCESS GROUP of each superseded owner, before it
>   loads the model. REQUIRED, and it is the only thing that closes the spawn-to-record
>   region.** Membership is established by `fork(2)`, before the child executes an instruction,
>   so it reaches a player that has published nothing and has not been scheduled. Measured on
>   both sides of publication: `C12a` killed 12/12, `C12b` killed before `exec` 12/12 — where
>   the single-record and record-only repairs both fail 12/12 (`C11b`, `C12c`). The placement
>   before the model load is normative: the load is 0.80–2.02 s **[hook]**, and a sweep after
>   it would let the orphan talk through all of it.
>   - **Bound it with a `.pending` marker.** The worker creates `playerdir/<nonce>.pending`
>     *before* the fork; the wrapper renames it away as its first act. `killpg` is used only
>     while such a marker exists, which confines its blast radius to the window where an
>     unnamed player can exist. Measured: skipped 25/25 when not needed (`C16b`), used 23/25
>     and effective when needed (`C16a`).
>   - **Never detach the player.** `start_new_session=True`, or any `setsid()`, removes it from
>     the group and defeats (iv) completely — measured, orphan plays to completion 12/12
>     (`C17`). This is normative.
>   - **Requires row 21's generation protocol.** (iv) reads the *superseded* owner's pid. A
>     lock protocol that deletes the record of the worker it replaced cannot supply it, so
>     §10.5 clause 2 and clause 7(iv) must ship together.
> - **(v) The worker must `wait()` its player, and unlink that player's own record when it
>   does.** `kill(2)` on an unreaped **zombie succeeds**, so an unreaping worker makes every
>   kill site report success while killing nothing (`C7`, both sites 12/12 against a process
>   already dead). Unlink by exact name only — see (i).
>
> **§10.5's *"Both are required"* about (i) and (iii) should go.** (iii) with both targets
> covers every case where the worker survives the spawn; (i) exists so a *different* process
> can do the killing, and its measured independent value is that the hook reaches the player a
> median **134 ms** sooner than the worker's next claim would (range 123–143, n = 12).

### 4c. §10.6 — the partition sentence is false as written

> **Replace** *"the two kills partition the timeline at the `speak/pid` write and every
> publication instant is covered by one of them"* **with:**
>
> **The two kills do not partition the timeline, and no record-based repair makes them.** There
> are three regions, not two: a hook reading before the record is published kills nothing (the
> worker's claim-time kill covers it); a hook reading after it kills the player (covered); and
> **a worker that dies between spawning the player and the record being published leaves the
> player unreferenced.** Publishing the record from the player rather than the worker does
> *not* close that third region — the wrapper can stay descheduled between `Popen` and its own
> first instruction, and a sweep in that gap sees nothing. Measured: the orphan plays to
> completion, 12/12. **The third region closes on process-group membership** (clause 7(iv)),
> which `fork(2)` establishes before the child executes an instruction: measured, the player is
> killed before it can `exec`, 12/12.
>
> **And *"cancellation is latency only, not correctness"* is true with its condition
> discharged** — conditional on 7(iii) with both targets, 7(i) as per-player records, 7(iv)
> with its `.pending` bound, and 7(v)'s reaping. All are measured. The residual cost is the
> newer utterance waiting out the older synthesis.

### 4d. §13 — proposed row text

> | **20** | ~~§10.6's preemption rests on three worker-side hooks that are all [inferred]~~ |
> **MEASURED 2026-08-25/26 and PARTLY FALSIFIED — twice.** 312 trials over 26 switchable
> configurations. The adversarial `R < S2 < R_b < P < W` was provoked **48/48** with the hook's
> kill hitting nothing every time; clause (iii) is confirmed load-bearing (36/36 killed before
> any sound) and its absence fatal (**12/12** run to completion; two real utterances overlap
> **3.25–3.50 s**). **The two-kill partition leaves a third region** — a worker dying between
> `Popen` and the record write orphans a player nothing reaches, **12/12**, window median
> **1.27 ms**. **The first proposed repair does not close it:** a single player-written record
> fails **12/12** when the sweep lands before publication, and per-player records alone fail the
> same way. **What closes it is a process-group sweep** (`fork` establishes membership before
> the child runs): killed before `exec` **12/12**, bounded by a pre-fork `.pending` marker
> (`killpg` skipped **25/25** when unneeded), and defeated entirely by one `setsid()`
> (**12/12** orphans survive). Also measured: `kill` on an unreaped **zombie succeeds**; a
> shared record's unlink is a **TOCTOU** (12/12 destroyed a newer record, hook blind to a live
> player 4/12); the ledger's truncate **erases unsignalled registrations** (12/25); clause (ii)
> is a correctness clause **only without** clause (iv). Requires row 21's generation protocol —
> [`preemption-and-lock-protocol.md`](preemption-and-lock-protocol.md) **[measured-here]** |
> **YES** — the repair is measured but it is the third proposed repair in three rounds, and it
> has had one round of review |
>
> | **21** | ~~The stale-lock protocol's two clauses are [inferred]~~ | **MEASURED 2026-08-25
> and BOTH CLAUSES FALSIFIED.** 1200 trials, 3 protocols × 6 scenarios. `current`: **121/400
> trials with ≠ 1 owner, worst case 3.** **The spec-corrected protocol: 61/400, worst case 3
> as well** — clean up to a 50 ms stall, then **40/40 wrong at 200 ms and 1000 ms** (a bounded
> backoff cannot tell a descheduled winner from a dead one) and **20/20 wrong on the
> quarantine ABA** (`rename` is atomic on a *path*, so a reclaimer acting on a stale
> observation renames a fresh lock and gets success, not `ENOENT`). A third protocol — owner
> published by `symlink(2)`, dead owners superseded by generation rather than removed —
> yielded **exactly 1 owner on 400/400**. **The measured 8/8 `mkdir` result is untouched and
> is a different race**, re-run here at N ≤ 16 for all three protocols, 1 owner on 80/80 each
> **[measured-here]** | **YES** — the shipped clause is now known false, and its replacement
> is unreviewed |

---

## 5. What could not be measured, and the experiment that would

Each of these is named with the experiment that closes it, not softened.

- **Pid reuse, in both mechanisms.** Two claims here rest on a pid number identifying the
  process that wrote it: the hook's kill of `speak/pid`, and the election's `kill(pid, 0)`.
  Neither is safe under recycling, and **the stale read is not hypothetical — the hook
  targeted a pid that was not the current player on every adversarial trial** (48/48,
  `ESRCH`); only the *recycling* is unobserved **[measured-here]** / **[inferred]**. To
  close: allocate pids until the space wraps (`sysctl kern.maxproc`-bounded, minutes of
  churn) and check whether a stale record ever names a live unrelated process. The cheap
  mitigation is a start-time stamp in the record, which needs no experiment to justify but
  does need one to verify.
- **A worker dying at any point other than `P`→`W`, which is the ONE point staged.** The
  probe also implements `--die-after pid` (death just after the record is published), but
  **no committed configuration sets it and no trace contains `worker_die where=after_W`** —
  it is an unexercised option, and round 1 wrongly listed it as a second staged point.
  Death *inside* `create()`, or between the claim and the claim-time kill, is likewise
  unstaged. To close: wire `--die-after pid` into a configuration and extend the option to
  every step of the loop. Expected outcome from the design, **[inferred]**: everything before
  `P` leaves no player and therefore no orphan, and death after `W` is covered because the
  record exists.
- **More than one orphan at once.** Requires two worker deaths each leaving a live player.
  The ledger form measured here handles N orphans by construction; the simpler
  single-`speak/pid` form proposed in 4b(i) handles exactly one. **The measured arm is the
  ledger; the single-record variant is [inferred].** To close: stage two consecutive
  worker deaths inside one player's lifetime and count survivors under each form.
- **Real `afplay` in the adversarial ordering at scale.** The real-audio arm is 3 trials,
  not 12 (§2.6). The stub establishes the ordering and the attribution; the real arm only
  answers audibility. To close: run `run_real.sh` at n = 12 per arm. It costs ~5 minutes and
  real synthesis is local and free, so this is a scope choice, not a limitation.
- **The hook in bash under real `Stop` dispatch.** `hook_probe.sh` *is* bash, but its
  kill-to-rename interval is a `sleep` calibrated to the measured median (0.086 s) rather
  than three `jq` invocations and a `shasum`. The distribution's *tails* (0.063 and 0.219 s)
  were not swept. To close: sweep `HOOK_GAP_S` across the measured range and confirm no
  ordering flips — the windows here are ~1 s wide, so none should, which is **[inferred]**.
- **Any of this on hardware that is not an M3.** Nothing here is portable evidence.
- **Whether `symlink(2)` is exclusive-create on every filesystem the buffer root can land
  on.** It is POSIX-required, and it was measured on this machine's APFS. A network or
  case-insensitive volume was not tested. To close: run `run_lock.sh` with the buffer root
  on the target filesystem.
- **Process-group REUSE, which is the pgid sweep's own worst case, is unmeasured.** The sweep
  `killpg`s the superseded owner's pid. If that pid has been recycled *as a process-group
  leader* of an unrelated group, the sweep signals strangers — and the blast radius is a whole
  group rather than one process, which is **worse than the pid-reuse hazard it inherits**. The
  `.pending` marker bounds *when* `killpg` is used to the narrow window where an unnamed
  player can exist — measured, skipped 25/25 when unneeded (`C16b`) and used 23/25 when needed
  (`C16a`) — but **the reuse itself is not measured**. To
  close: the same pid-space-wrap experiment named above, with the check being whether a
  recorded owner pid ever names a live unrelated group leader. Until then this is the one place
  where the repair could do more damage than the defect it fixes, and it is the reason
  `.pending` is specified as normative rather than optional.
- ~~A player that leaves its process group defeats clause 7(iv) entirely — normative and
  untested.~~ **MEASURED (`C17`): the orphan plays to completion 12/12.** Not an open item any
  more; it is a normative constraint with an arm behind it.
- **There are now TWO garbage collections, and neither is implemented or measured. Both are
  cleanup steps acting on a path, which is the exact shape of the two races review has already
  found, so this is where I would expect a fourth defect.**
  - **Lock generations.** `lockrace.py` never unlinks an obsolete generation, so every trial
    ran with all of them present. The argument that unlinking generation `g` once `g+1` exists
    is safe — the highest generation always exists while its owner lives, because an owner only
    ever removes generations *below* its own — is **[inferred]**. To close: add the unlink and
    re-run S3, S4 and S6 with a reclaim delay straddling it.
  - **Player records and `.pending` markers.** `playerdir/` accumulates a record per player and
    nothing removes the records of players that died without reaping (the warm-up player's
    record is visible in the committed `C12b` trace, still present several generations later).
    A stale `.pending` is worse than untidy: it makes every later election take the `killpg`
    path, so the bounding property `C16` measures **degrades to unbounded after one worker dies
    before forking**. The fix — a newly elected worker removes the `.pending` entries it has
    just swept, and unlinks records whose pid is dead — is **[inferred]**, and its safety
    argument depends on the sweep covering *all* superseded generations rather than only the
    most recent. To close: implement both cleanups and re-run `C12b`, `C16a` and `C16b` with a
    pre-seeded stale `.pending` and a pre-seeded dead record.

### One thing this run deliberately did not re-open

**The 8/8 `mkdir` pre-check result is untouched.** That measurement asked *who wins a
contended election*, and its answer — the hook's `[[ -d ]]` pre-check lost 8/8, the
`mkdir` inside the worker is the guarantee — is unaffected by anything here. Row 21 asks
the different question of whether a protocol can **misclassify the winner**. Scenario S5
re-runs the who-wins race against all three protocols precisely so the two sit side by side
and cannot be conflated.

---

## 6. Should rows 20 and 21 stay ship-blocking?

**Both stay ship-blocking. The case is now much stronger than it was, and it is no longer an
argument about labels — it is an induction over three rounds of review.**

### What the three rounds actually did

| round | the clause it examined | verdict |
| --- | --- | --- |
| PR #27 | *"a newer message kills stale playback"*, `[inferred]` | reviewer found **two races** in the lock clauses before anything was measured |
| PR #28 rev 1 | those clauses, measured | `current` **and** the spec-corrected protocol both produce 2–3 owners; clause (ii) mis-specified; the `P`→`W` region uncovered |
| PR #28 rev 2 (this) | **the repair rev 1 proposed** | reviewer found the repair **was not the one measured**, and that the arm which "closed" the region **could not fail**. Staged properly, **rev 1's repair fails 12/12** — and two further protocol defects in it (shared-record TOCTOU, ledger truncation) both reproduce |
| PR #28 rev 2, self-review | **the repair THIS revision proposes** | `killpg` blast radius under pid reuse (bounded, measured); one `setsid()` defeats it (measured); and the sweep signal itself was a silent no-op under `nohup` (found only by chasing a null) |

**Three consecutive rounds, and every round found a real defect in the previous round's
confident answer.** Rev 1's own headline — *"a repair was built and measured: 12 of 12 orphans
killed"* — was wrong in the way that matters most: the repair specified was a single replaceable
record, the thing measured was an append-only ledger, and the arm that measured it had a 1.2 s
delay that guaranteed the sweep always ran after publication. When the ordering rev 1 claimed to
close was finally staged (`C11b`), **the single-record form failed.**

### So the counter-argument is now refuted three times over

The original argument for non-blocking was that these clauses are *"cheap, obviously correct on
inspection, and their failure windows are microseconds wide."*

1. **"Obviously correct on inspection" has now failed on seven distinct clauses** — the two
   lock clauses, clause (ii)'s scope, the shared-record lifecycle, the append-only ledger's
   truncate, the player-authored-record repair, and the process-group sweep's own blast radius.
   Inspection is what produced all seven. The player-authored-record repair is the sharpest
   case: it was proposed *in response to* a measured defect, read as obviously correct by its
   author, and **fails 12/12** once the ordering it was written for is actually staged.
2. **"Microseconds wide" is false for most of them.** The pid-less lock window is a scheduling
   delay (unbounded). The ABA window is a reclaimer's own think-time. The publication window is
   as wide as the wrapper stays descheduled — `C11b` widened it deliberately, but nothing bounds
   it in the real system. Only the `P`→`W` window is genuinely sub-2 ms, and this document says
   so plainly rather than inflating it.
3. **"Cheap" is true of writing them and false of getting them right.** Getting to a repair that
   survives staging on both sides of publication took three protocol variants for row 21, six
   configuration families for row 20, and two rounds of adversarial review.

### What would take them off the list

**Not more measurement from me.** The measurements exist and the arms that can falsify each
clause exist. What is missing is the thing that has caught a defect every single time: **an
adversarial reader who did not write the text.** Concretely, before rows 20 and 21 move to
non-blocking:

- **§4a and §4b need one review pass by someone other than their author**, on the standard that
  found the defects in rounds 1–3. The most likely place for a fourth defect is named in §5:
  the proposed protocol's garbage collection, which is still unimplemented and unmeasured, and
  which is a cleanup step acting on a path — the same shape as the two races already found.
- **Row 20's clause 7(iv) is the newest thing in this document, and it is the THIRD proposed
  repair for the same region.** The first (player-authored single record) is measured to fail;
  the second (per-player records alone) is measured to fail; this one is measured to work. That
  history is the argument for a review pass, not against it. It has had one round of review,
  and the two rounds before it each broke their predecessor.
- **One clause depends on a primitive whose failure mode is worse than the defect.** `killpg`
  under pid reuse signals a whole group of unrelated processes. The `.pending` marker bounds
  when it fires and that bounding is measured; the reuse is not. A reviewer should decide
  whether that trade is acceptable, because I cannot settle it by measurement here (§5).
- **Row 21's replacement changes the lock's on-disk shape**, and row 20 now *depends* on that
  change: the process-group sweep has to read the superseded owner's pid, which a protocol that
  deletes the record it replaced cannot supply. **The two rows can no longer be signed off
  independently**, and that coupling is new information for whoever owns the call.

**One thing I will state as a judgement rather than a measurement.** If a reviewer decides to
ship anyway, the least-bad subset is **clause (iii) with both kill targets, clause (i) as
per-player records, and clause (v)'s reaping** — each is measured, each is falsified when
removed, and none depends on the newest mechanism or on `killpg`. The process-group sweep would then be the one deferred piece, and the honest
cost of deferring it is stated in §2.4: a worker dying in a sub-2 ms window orphans one
utterance, which plays to completion. That is a *bounded, single-utterance, low-rate* failure —
which is a defensible thing to ship, and a very different thing from shipping the lock clauses,
where the failure is two resident workers each holding a 340 MB model.
