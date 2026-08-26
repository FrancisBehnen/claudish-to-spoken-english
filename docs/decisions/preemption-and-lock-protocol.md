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
  nothing can reach — **12/12 played to completion**. The window is **median 1.41 ms** (range
  0.43–5.61, n = 72), so this is a low-rate failure and is not presented as more. The figure is
  over the **worker-published** arms only; the player-published arms cannot supply a real `W`
  and pooling them was harness defect 4 (§1).
- **The first revision's repair for it was wrong, and this is the correction that matters
  most.** It specified one player-written record and reported "12 of 12 orphans killed" — but
  it *measured* an append-only ledger, in an arm whose respawn delay guaranteed the sweep
  always ran **after** the player published. Staged on both sides, **the single-record form
  fails**: sweep before publication, the orphan plays to completion, **12/12** (`C11b`). Per-
  player records alone fail the same way (`C12c`, 12/12).
- **What does close it is process-group membership**, which `fork(2)` establishes before the
  child runs an instruction. `C12b`: sweep before publication, the player is **killed before it
  can `exec`**, 12/12, and never appears in the player log. **The attribution does not rest on
  the record sweep having found nothing** — it reported `swept=1` on **6 of its 25** elections,
  against pids left by *earlier* trials. It rests on the `killpg` having been **sent**, exactly
  once per election to the immediately superseded owner (24 of 25; every older generation's
  group was already empty), and on `C12c` — the same timing with the pgid sweep removed —
  running to completion 12/12 (§2.4).
- **But the sweep that actually killed the orphan is not always the process-group one, and §4b
  had to be corrected for that.** In the two arms where the player publishes promptly — `C15c`
  and `C16b` — the `.pending` marker is gone before the election, `killpg` is skipped 25/25, and
  the kill is attributed to the **record** sweep, 12/12 each. The election therefore owes **two**
  sweeps, not one; the first revision of §4b specified only the `killpg` (§4b clause 7(iv-a)).
- **Three measured qualifications on that repair.** A `.pending` marker created before the fork
  confines `killpg` to the window where an unnamed player can exist (`C16b` skipped it **25/25**
  when it was not needed; `C16a` used it 23/25 when it was). One keyword — spawning the player
  with `start_new_session=True` — **defeats the clause entirely** (`C17`, orphan plays to
  completion 12/12). And a sweep signal that anything ignores makes the sweep a silent no-op:
  `nohup` sets `SIGHUP` to `SIG_IGN`, inherited across `fork` and `exec`, which produced a
  **false "the repair fails"** for a whole run (§2.5).
- **Two further defects in the first revision's protocol, both reproduced — one of them at a
  third of the rate previously published.** Unlinking a *shared* pid record is a TOCTOU: an
  older player's reap destroyed a newer player's record on **4 of 12** trials (**8** unlinks),
  and a hook fired inside the resulting window could not reach a live player on the same
  **4/12**. Round 3 reported 12/12 and 24 unlinks; that count was anchored on harness defect
  4's bad timestamp and does not survive (§2.5). And the ledger's truncate erased registrations
  it had never signalled on **12 of 25** truncations. Per-player records fix both: **0/12** and
  **0** respectively — the control is what carries the conclusion, and it is unaffected.

**Row 21 — the spec's two clauses do not hold, and they were known not to hold before this
was run.** 1200 trials, three protocols, six scenarios **[measured-here]**:

| protocol | trials | worst case | trials ≠ 1 owner | rate |
| --- | --- | --- | --- | --- |
| `current` — the residency probe's own | 400 | **3 owners** | 121 | **30.2 %** |
| `spec` — §10.5 clause 2 (a) + (b) | 400 | **3 owners** | 61 | **15.2 %** |
| **`proposed`** — atomic `symlink` owner record, superseded by generation | 400 † | **1** | **0** | **0.0 %** |

† **`proposed` produced 1 owner on 400 of 400 and NONE of those trials is confirmed to have
exercised reclamation.** Round 3 said 20 were unconfirmed (its S3 cell, staged by a fixed 4 ms
sleep); round 5 found the same defect in S4 and S6, which stage the dead incumbent's record by a
fixed `sleep 0.05`. All three reclamation scenarios — **100 trials** — are therefore staged by a
clock, and the defect is asymmetric: under `current`/`spec` a mis-staged trial degenerates into
the empty-directory control and yields 1 owner, so their 2- and 3-owner results prove their own
staging held; under `proposed` a mis-staged trial *also* yields 1 owner and is indistinguishable
from a pass. Of the remaining 300, **220 (S1, S2) are structurally vacuous** for `proposed` and
**80 (S5) are valid but answer the who-wins question**, which §3.0 says is a different race. The
harness is fixed on all three and **every fix is unrun**; the committed `lock-owners.tsv` predates
them. **No *failure* in the table is affected** — mis-staging can only hide failures, never invent
them — so `current`'s 121/400 and `spec`'s 61/400 stand. What does not stand is any claim that
`proposed`'s clean sheet was earned against a dead owner. §3.3 and §13 row 21 carry the re-run as
an open item, and §3.3 states plainly why no further inspection of this harness should be trusted
to close it.

`spec` is a genuine improvement and still fails: clean to a 50 ms stall (180/180, where
`current` fails 60 of the same 180), then **40/40 wrong at 200 ms and 1000 ms** — a bounded
backoff cannot distinguish a descheduled winner from a dead one — and **20/20 wrong on the
quarantine ABA**, where `rename(2)` is atomic on a *path* and a reclaimer acting on a stale
observation renames the fresh owner's live lock and gets success rather than `ENOENT`.

**And the two rows are now coupled.** Row 20's process-group sweep must read the *superseded*
owner's pid, which only row 21's generation protocol supplies — a protocol that deletes the
record of the worker it replaced cannot. They can no longer be signed off independently.

**Both rows stay ship-blocking**, and the reason has changed: they are no longer unverified.
**Five consecutive rounds of review have each found a real defect in the previous round's
confident answer**, including in the repair this document proposed and in the *text* of the
repair that replaced it. See §6.

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

**Two arms, both committed.** All 26 configurations were run in one sweep — 26 distinct values
of the `config` column over 312 data rows in `preemption-trials.tsv`. `C1`–`C10` were
additionally run in an earlier round and are re-collected here with the *current* collector, so
the two arms are compared under the same predicate rather than across a changed derivation:
[`preemption-trials.tsv`](preemption-trials.tsv) is the published set,
[`preemption-trials-replication.tsv`](preemption-trials-replication.tsv) the replication, and
`preemption-lock-probe/compare_passes.sh` prints them side by side.

**Five derivation defects have been found by review, and all five are fixed here. Three of them
made the reproducibility claim false, which was the claim the whole document rested on.** The
first three came from review of the first revision; the last two from round 5, and both are of
the same kind as the first three — a figure whose name and whose derivation are not the same
quantity.

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
   takes a median 11.1844 ms there (12.2745 ms on the published arm), while the margin from
   `Rdone` to `P` on the adversarial trials is a median **446.21 ms** (range 418.46–472.67) on
   that same replication arm. The check was missing; it was never close to binding.
   `summarise.sh` section F now prints that margin, which round 2 quoted without deriving.
3. **Section 2.6 had no derivation at all.** There was no input for the `REAL-*` traces, so the
   real-audio figures could not be re-derived. `collect_real.sh` now produces a committed
   [`real-audio-trials.tsv`](real-audio-trials.tsv) and `summarise.sh` has a section over it.
4. **The stale player's lifetime in §2.6 was published as an interval it is not.** Round 3's
   `collect_real.sh` wrote `life_s` from the probe's `alive_s` and documented it as
   *"Popen → exit"*. It is not: `speakd_probe.py` stamps `t_popen` **before** `subprocess.Popen`,
   so `alive_s` includes the fork/exec launch latency. **The same row's own columns disagree by
   about 7×** — `p_exit - p_popen` is 2.30, 2.76 and 1.57 ms against `alive_s`'s 17.5, 18.6 and
   13.0 ms — so most of the published figure was launch, not life. The column is renamed
   `timerstart_to_exit_s`, `popen_to_exit_s` is added beside it, and §2.6 now says which bound it
   quotes and why. **This is deliberately NOT filed as a fifth harness defect**, and the reason is
   worth stating because the count matters: the probe's field is named and computed correctly —
   `alive_s` measured from a timer is exactly what it says — and nothing in the trace was wrong.
   What was wrong was the collector's gloss and the document's. That is this list's kind of
   defect, not the harness list's. Also unlike harness defect 4, it is fixable by re-deriving,
   and it has been: both bounds come from the same committed traces.
5. **`collect_real.sh` could not be run against the committed evidence.** It required the run
   directories a live run leaves behind, which are not in the repository, so the one file added
   in round 3 *to make §2.6 re-derivable* could not itself be regenerated from anything committed.
   It now also accepts the flat `traces/REAL-*.worker.trace` files, and the committed
   `real-audio-trials.tsv` re-derives from the repository alone. That is how defect 4 above was
   confirmed rather than argued.

**Four HARNESS defects were also found and are disclosed here, because three of them changed
results and one of them destroyed data.** They are listed rather than quietly fixed, since a
reader deciding how much to trust these numbers should know what went wrong in producing them.
The fourth was found in round 3 and it touches a published figure.

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
4. **`W` is not a publication instant in the player-published arms, and the `P`→`W` figure was
   pooled across both.** For `pid_mode != worker` the probe stamps `W_pid_write` **in the
   parent, immediately after `Popen` returns**, with `by=player result=deferred_to_player` — it
   is a *deferral* record, not a write. The wrapper only publishes after sleeping `$PUBDELAY`
   and renaming. `collect.sh`'s `$5=="W_pid_write" && V["by"]=="player"` branch nonetheless
   takes that stamp as `W`, so `C14a` and `C14b` contributed **24 synthetic samples** to the
   96-sample `P`→`W` window. Re-derived three ways by `summarise.sh` section C:

   | sample | n | min | med | max |
   | --- | --- | --- | --- | --- |
   | pooled — **do not quote** | 96 | 0.3591 | 1.2681 | 5.6069 |
   | **worker-published — the figure** | 72 | 0.4289 | 1.4119 | 5.6069 |
   | player-published — synthetic | 24 | 0.3591 | 1.0430 | 2.3630 |

   Every `P`→`W` figure in this document is now over the **72 worker-published trials**. The
   defect is not fixable by re-deriving: **the player-published arms cannot supply a real `W`
   at all**, because nothing in the wrapper acknowledges back to the worker after its `mv`.
   Measuring publication on that side needs a handshake the harness does not have, and that is
   an experiment, not a patch. The `P`→`W` orderings are structurally safe from it rather than
   luckily so: `collect.sh` tests `WPLAYER` *before* both the `W<R` and the adversarial
   branches, so a player-published trial is labelled `record published by player` and the two
   orderings that read `W` never see a synthetic one.

   **Round 3 wrote that it "disturbs no other figure" and named the `P`→`W` window as its only
   consumer. That was wrong, and round 5 found the second one.** `analyse_round2.sh` read the
   same stamp as `C14a`'s publication instant — `$5=="W_pid_write" { lastpub_t=$1 }`, at `:56`
   before this revision removed it — and
   printed a **41.3–82.3 ms "publication→destruction" lag** from it. `C14a` runs `pid_mode=shared`,
   so every one of those samples is the deferral record: the figure was never measured from
   publication and could not be. **It is removed rather than caveated**, because nothing in the
   committed traces marks the wrapper's `mv` and no publish→destruction interval is derivable
   from them at all. What replaces it, and what it cost the `C14a` claim, is §2.5 item 3 — and
   the cost is not only the lag: the *count* was anchored on the same stamp too.

**The first two are the reason this revision re-ran everything rather than patching numbers.**

**And one defect in the rig itself, which is not a measurement error but which voided the claim
every other figure rests on.** Every driver in `preemption-lock-probe/` resolved its helpers from
a private bench directory — `RIG="$HOME/.local/share/kokoro/bench/preempt-lock-2026-08-25"` — and
`run_lock.sh` and `run_preempt.sh` additionally invoked one user's absolute interpreter path. Two
consequences, both real. On any other checkout the drivers fail outright, so *"the rig is in the
repository, so its protocol can be read as well as its output"* was true of reading and false of
running. And on the author's own machine they would execute **whatever is in that external
directory** — which is not necessarily what is committed here, and a stale copy would produce a
result the committed rig cannot reproduce while looking identical. **This is exactly how a
document whose premise is re-derivability stops being re-derivable without anyone noticing.**
Every driver now resolves helpers relative to its own location, with `RIG`, `OUT` and `PYTHON`
overridable so the original layout stays reachable. `run_real.sh` keeps the Kokoro venv as its
default because that arm imports `kokoro`; the stub drivers default to `python3`. `publish.sh`
copied a hand-maintained file list that had fallen six files behind the rig, and now globs.

Rig: [`preemption-lock-probe/`](preemption-lock-probe/README.md). Every figure below re-derives
from committed files with `awk` and `sort` only — `summarise.sh <dir>` over the four committed
TSVs, and `analyse_round2.sh preemption-lock-probe/traces` over the committed traces, are the
derivations. (Round 3 wrote "from the committed TSVs" for both; `analyse_round2.sh` takes the
trace directory, and pointing it at the TSVs prints `(trace missing)` for every block.)
`verify_fires.sh` confirms every hook fired — **and until round 5 it could not do so from the
repository, while reporting that it had.** It read a `RUNS.txt` that exists only in a live run
tree; pointed at the committed `traces/`, it iterated over nothing and printed *"all hooks
fired"*. **A null reported as a pass, by the one script whose entire purpose is to stop a null
being read as a pass** — the same shape as harness defect 1, in the guard against it. It now also
reads the committed `<cfg>.markers.tsv` files and exits 2 rather than succeeding over zero inputs.
Run against `traces/` it reports **21 configurations OK**, which is where the counts below stop
being an assertion (25 entry markers per
configuration: one warm-up plus two per trial — **except `C14a` and `C14b`, which fire a third
hook per trial to observe the TOCTOU's consequence and therefore want `1 + 3N = 37`;
`verify_fires.sh` special-cases them and their committed `markers.tsv` files carry 37 entries
each**) so that a null result can be distinguished from a hook that never ran. `analyse_c14.sh`
is a third derivation, over the `C14` traces; **it was corrected in round 3** — it had tested
only that a player's END record existed, which every completed player satisfies, instead of that
the player was live at hook C. It now reads `tNc.entry` from `markers.tsv` and requires
`start ≤ hook_c < end`. Under the real predicate the published figures are unchanged, **4 of 12
and 0 of 12**, and all 12 trials of each arm did have a live player at hook C. Unlike the
residency run's `[rig]`, **this probe is in the repository**, so its protocol can be read as
well as its output.

---

## 2. Row 20 — preemption

### 2.1 Twenty-six configurations

One warm worker per configuration — it has already elected, loaded, synthesised and
played before the first trial. Then twelve trials of two `Stop` hooks (three, in the
`C14` arms). The second hook's launch time is what selects the ordering; nothing is
sampled and hoped for. **26 configurations × 12 trials = 312 trials, and every
configuration is uniform 12/12** on the outcome reported for it.

**`run_all_preempt.sh` was one round behind the document and is fixed here.** Its loop listed
**24** configurations — `C15c_norecheck_death_pgid` and `C17_setsid_player`, both added late and
both load-bearing (`C15c` settles clause (ii); `C17` is the arm that defeats clause 7(iv)), were
missing — so a fresh run did not reproduce the published set. Both are now in the loop.

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
near its middle. The rename itself takes a median **12.2745 ms** (range 3.8891–61.1639), which is
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
| `C14a_shared_unlink` | shared record, reap unlinks late | hook kill | 0.503–0.539 |
| `C14b_perplayer_unlink` | per-player record, same timing | hook kill | 0.501–0.537 |
| `C15a_recheck_death` | recheck **on** + worker death | **no player spawned** | none |
| `C15b_norecheck_death` | recheck **off** + worker death, no sweep | **NOTHING** | 2.501–2.504, **full** |
| `C15c_norecheck_death_pgid` | the same **with `sweepmode=both`** — the name says pgid, the kill was the record sweep | election sweep (**record**) | 0.386–0.471, med 0.421 |
| **`C16a_pending_sweepfirst`** | `.pending` marker, sweep before publish | **killed before exec** | **0 — never started** |
| **`C16b_pending_pubfirst`** | `.pending` marker, sweep after publish | election sweep (record) | 0.693–0.804, med 0.781 |
| **`C17_setsid_player`** | `C12b` + the player **leaves the group** | **NOTHING** | **2.502–2.510, full** |

**[measured-here]**; `summarise.sh` sections A and B over `preemption-trials.tsv` re-derive
every row.

**The adversarial ordering was reached, not sampled.** `R < S2 < R_b < P < W` held on all
**48** trials of `C3`–`C6` under the corrected predicate — publication demonstrably complete
before `P`, with a margin of median **440.96 ms** (range 359.38–482.18) **on this arm** — and on
all 48 the hook's own kill returned `ESRCH`. **No trial in `C3`–`C6` saw a live pid**, which is
the precondition §13 row 20 insisted on. (§1's defect 2 quotes **446.21 ms**, range
418.46–472.67: that is the *replication* arm, which is what the reclassification check was run
against. The two are separate runs of the same 48 trials and the arm must be named — round 2
quoted the replication figure here, in a section about the published one. `summarise.sh`
section F prints whichever arm it is pointed at.)

### 2.3 What each clause is actually worth

- **Clause (iii), the claim-time kill: REQUIRED, and confirmed by falsification.** Remove it
  and the stale player runs its full length, 12/12 (`C4`), with nothing in the design touching
  it. In real audio two utterances overlapped for **3.25–3.50 s**.
- **Clause (iii) must kill BOTH targets.** `handle` and `pidfile` are indistinguishable while
  the record exists (`C3` vs `C6`, 24/24 identical) and **opposite** when it does not
  (`C10a` NOTHING vs `C10b` killed, 12/12 each way).
- **Clause (i)'s independent value is latency.** In `C2` the hook reached the player a median
  **134 ms** sooner (range 123–143) than the worker's next claim would have.
- **Clause (ii) is correctness-relevant only in the absence of AN ELECTION-TIME SWEEP, and this
  now has both arms — and round 2 got the sweep's identity wrong.** The first revision claimed it was "an optimisation, not a correctness clause"
  on the strength of `C5` alone; review pointed out that `C5` only removes the recheck while
  the worker *survives*. Staged properly:
  - `C15a` (recheck on, worker dies after the spawn): **no player is ever spawned**, 12/12 —
    the recheck discards the stale job, so there is nothing to orphan.
  - `C15b` (recheck off, same death, no sweep): the stale player is spawned and orphaned,
    and **NOTHING kills it**, 12/12. So the recheck *does* prevent an orphan the no-recheck
    arm creates. **The first revision's conclusion was wrong as stated.**
  - `C15c` (recheck off, same death, **with the election-time sweeps on**): the orphan is
    killed, 12/12, after a median **0.4207 s** (range 0.3864–0.4712). **So clause (ii)'s
    correctness role is conditional on the election sweeping.** With the sweep it returns to
    being an optimisation — which is the accurate form of the claim, and it needed three arms
    rather than one.
  - **But `C15c` does NOT credit the process-group sweep, and round 2 said it did.** `C15c` runs
    `sweepmode=both` with `pending=on` and no publish delay, so the player renames its
    `.pending` away before the replacement worker elects; `killpg` is **skipped 25/25** with
    `skipped=no_pending_marker`, and `summarise.sh` section A attributes all 12 kills to
    **`election-sweep-record`**. The clause this arm vindicates is therefore 7(iv-a), the
    election-time *record* sweep — which §4b did not specify at all until this revision. Written
    against §4b as it stood, an implementer whose player published and cleared its marker would
    have had **nothing** run at election time.

### 2.4 The uncovered region, and what actually closes it

§10.6 says the two kills *"partition the timeline at the `speak/pid` write"*. They partition
it at the **pid record's publication**, which under clause 7(i) is a different instant from
the spawn. `C8` measures the consequence: the worker dies between `Popen` and the write, the
hook reads a pid that predates the orphan, a replacement worker's claim-time kill reads the
same stale pid, and the orphan **plays to completion, 12/12**. The window is **median 1.4119 ms,
range 0.4289–5.6069 ms**, n = **72** — small, and this document does not inflate it. The 72 are
the **worker-published** trials; the 24 player-published ones that round 2 pooled in are not a
publication instant at all and were harness defect 4 (§1). Correcting it moves the median
*up*, from 1.2681 to 1.4119 ms, so the pooled figure was understating the window rather than
inflating it.

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
`player.log` at all.

**Round 2's stated proof of that attribution was false, and is replaced here.** It wrote that
*"the record sweep in the same election reported `swept=0`, having found nothing but the
previous, dead player"*. The committed `C12b` trace says otherwise: of its **25** elections,
**6 report `swept=1`** — the record sweep does reach processes, just never the current player,
whose record does not exist yet. The conclusion survives on three other legs, all in the same
committed trace and all printed by `analyse_round2.sh`:

- the player was **spawned** (`P_popen` carries its pid) and **never logged `player_start`**,
  and a player that survives to run always logs;
- exactly **one `killpg` was `sent` per election, on 24 of 25** — to the *immediately*
  superseded owner, the dead worker whose group the player is still in. All 276 other pgid
  attempts returned `ESRCH`, because every older generation's group was already empty;
- and `C12c` is the control: identical timing, `sweepmode=record`, **zero** pgid sweeps, and
  the orphan runs to completion 12/12.

The pids the record sweep did reach are from *earlier trials* — which is the same unbounded
target list §5 now prices (`C12b`'s list grows monotonically to **12** names within one 12-trial
run, and the warm-up player `94309` is in **24 of the 25** sweeps).

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

### 2.5 Six things the run found that nobody asked about

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

**3. Unlinking a SHARED record is a TOCTOU, and its consequence is observed — on 4 of 12 trials,
not 12 of 12.** This is the claim round 5 cut down, and the reason is harness defect 4 again:
round 3's test for "an older reap destroyed a newer player's record" was
`unlink_time > W_pid_write_time`, and in `C14a` — which runs `pid_mode=shared` — `W_pid_write` is
the parent's deferral stamp, not the publication. It counted **24** such unlinks and quoted a
**41.3–82.3 ms** publication→destruction lag. **Neither figure survives.** Nothing in the
committed traces marks the wrapper's `mv`, so the lag is removed outright rather than caveated,
and the count was measuring "a newer player had been *spawned*", which is not the same event.

What `analyse_round2.sh` derives instead is *order*, from two independent sides, and only where
the order is actually determined:

- **the player log.** `player_start` is stamped by the player itself, after the wrapper renamed
  and after `exec`, so it is strictly later than publication. **4 unlinks** landed after it —
  those destroyed a record that certainly existed. (They are the four second-hook reaps, a whole
  trial-gap late; `unlink − player_start` is 1597.5–1649.7 ms, a *lower* bound on the lag and not
  the lag.)
- **the hook side.** A third hook fires while the newer player is still playing. It **found no
  record at all on 4 of 12 trials**, and on the corrected `analyse_c14.sh` predicate all 12
  trials did have a live player at hook C. Nothing else in this arm unlinks, so on those 4 the
  record was published and then destroyed.

Those two sets are **8 distinct unlinks falling in the same 4 trials** — the trial's first unlink
caught by the hook, its second by the player log. Of the **16** remaining, **8 are positively
shown NOT to be destructions**: hook C read the *newer* player's pid, so that trial's first
unlink removed the older player's **own** record and the newer one had not published yet. The
last **8** are simply undetermined — the unlink falls inside the newer player's unobserved
`Popen`→publish→`exec` gap and nothing in the traces resolves it. So the honest statement is
**4 of 12 trials, 8 proven destructions** — a real defect at a third of the rate round 3
published, found because the count and the lag shared one bad timestamp.

**The design conclusion is unchanged, and it is the control that carries it.** With per-player
records (`C14b`, identical timing) every one of **37** unlinks removed only its own name, **0 of
another player's**, and the third hook reached the live player **12 of 12** — against `C14a`'s
4/12 blind. A defect that fires on a third of trials is still a defect that per-player records
make structurally impossible.

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

**6. The record sweep can be made to signal a pid nobody ever published, by a filename.**
`read_player_records()` did `int(name.split(".")[0])` over **every** entry in `playerdir/`. A
record is `<pid>.<nonce>`, so that is right for records — and wrong for `<nonce>.pending`,
which splits to the *nonce*. An 8-hex nonce is all-decimal about 2.3 % of the time, and when it
is, the sweep signals it as a pid. It happened: **2 of the 100 committed `.pending` nonces are
all-decimal**, and one of them was still on disk at an election — `C17`'s `02679968.pending`,
targeted twice as pid **2679968**, `ESRCH` both times. Blast radius **1 trial across the 23
committed traces**, and harmless there only because that number named nothing. `read_player_records()`
now matches the record shape (`^\d+\.[0-9a-f]{8}$`) and excludes `.pending` by construction.
**This does NOT overturn `C17`.** `C17`'s result comes from the *pgid* sweep, and the pgid sweep
targets the superseded **worker**'s group: `killpg(19781) → ESRCH` is *positive* evidence that
the player left that group, because a process group persists while any member lives. The
mis-parse touched only the separate record sweep, which in `C17` legitimately had no record to
find — the player publishes 1.5 s later. It is a defect in the rig's parser, not in the arm.

### 2.6 The real-audio arm

Real Kokoro synthesis on `bf_emma`, `is_phonemes=False`, `/usr/bin/afplay` as the player, two
distinguishable utterances, the `C3` ordering, 3 trials per arm. This arm answers audibility
only; the stub arms establish the ordering and the attribution.

| arm | result |
| --- | --- |
| claim-time kill **on** | the stale `afplay` existed for **at most 13.0, 17.5 and 18.6 ms** against a 5.7 s wav; the newer utterance then played in full, 3/3 |
| claim-time kill **off** | both `afplay`s ran to completion and **overlapped for 3.2486, 3.2564 and 3.4981 s**, 3/3 |

**[measured-here]**, and now re-derivable from the repository alone: `real-audio-trials.tsv` is a
committed evidence file, `summarise.sh` section E prints these figures from it, and
`collect_real.sh` regenerates the file from the committed `traces/REAL-*.worker.trace`. The first
revision published these figures with no derivation at all; round 3 added the file but not a way
to rebuild it from anything committed.

**Which interval those milliseconds are, exactly — round 3 got this wrong and the correction
matters more than the number.** They are `alive_s`, and the probe starts that timer **before**
`subprocess.Popen`, so they are **timer-start→exit and include the process launch latency**;
round 3's `collect_real.sh` documented the column as *"Popen → exit"*, which it is not. The same
rows' `p_exit − p_popen` is **2.30, 2.76 and 1.57 ms** — the two columns of one row disagree by
roughly **7×**, and most of the published figure is `fork`/`exec`, not life. Both are now in the
evidence file (`timerstart_to_exit_s`, `popen_to_exit_s`) and both are printed. **This document
keeps quoting the larger one**, and deliberately: the claim being supported is *the stale player
did not last long enough to be heard*, so the conservative bound is the upper one. `alive_s`
strictly encloses the process's real lifetime — the child is created inside the `Popen` the timer
already started before — whereas `popen_to_exit_s` excludes the fork and would flatter the
result by a factor of seven. The figure is therefore **an upper bound of 13–19 ms, not a
measurement of 13–19 ms**, and §1's derivation defect 4 records how it was published as the
latter.

**One honest limit, and the correction above does not touch it.** What is bounded is the
process's existence. Whether ≤ 19 ms is short enough that no sample reached the output device is
**[inferred]** — `afplay`'s time-to-first-sample was not measured, and nothing here listens. If
anything the correction sharpens the limit rather than weakening it: `popen_to_exit_s` shows the
process was reaped 1.6–2.8 ms after `Popen` returned, which makes the audibility question turn
almost entirely on launch latency the harness never instrumented. The experiment that removes
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

`summarise.sh` sections A–C over `lock-owners.tsv` re-derives every cell. **Both rates land exactly on a
half and are printed round-half-to-EVEN** — 121/400 is 30.25 % and 61/400 is 15.25 %, both
exactly representable, and `%.1f` rounds each to the even digit: 30.2 and 15.2, not 30.3 and
15.3. They do re-derive from the script; the document rounds half-up elsewhere, so the
difference is named here rather than silently carried.

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

**S3's staging is not guaranteed per trial, and this is a limitation on `proposed`'s S3 result
specifically.** `run_lock.sh` launched reclaimer B, slept **4 ms**, then launched A. 4 ms does
not guarantee that B — a fresh Python interpreter — has started, read the directory and
classified the incumbent as dead; B can be descheduled straight through startup and instead
observe A's *live* record, which is not a stale observation at all. **For `current` and `spec`
the result is its own evidence that the staging worked:** S3 produced 2 owners on 20/20 of each,
while S4 — the same two reclaimers with the asymmetry removed — produced 1 owner on 20/20. A
trial where B failed to go stale would have behaved like S4 and shown 1. **For `proposed` that
argument is not available**, because a mis-staged trial and a correctly staged one both produce
1 owner: `elect_proposed` sees a live owner, records `lost`, and returns. So some unknown number
of `proposed`'s 20 S3 trials may never have exercised a stale observation, and the run cannot
say which. `run_lock.sh` now waits for B's own `classified_stale` record before launching A and
fails the trial if it never appears — **that change is UNRUN**, and the committed
`lock-owners.tsv` was produced under the 4 ms sleep. To close: re-run S3 under the corrected
harness.

**The previous round closed that sentence with "S4, S5 and S6 are untouched", and round 5 found
that this was wrong for two of the three.** The repair replaced the 4 ms sleep between launching B and
launching A, and left the *other* fixed sleep in the same function — the `sleep 0.05` between
launching the incumbent and launching B (`run_lock.sh:114` as it stood before this revision).
`trial_dual` (`:145`) and `trial_deadN` (`:181`) staged their incumbent by the same 50 ms sleep
and were never touched. That sleep is not staging two
reclaimers against each other; it is staging **the dead incumbent's record existing at all**, and
the winner that writes it is a fresh Python interpreter whose startup is of the same order as the
sleep. When it loses, the racers arrive at an *empty* directory, one wins uncontested, `owners=1`
— **S5's who-wins control wearing S4's or S6's label**, and producing exactly the number a pass
produces. All three now gate on the incumbent's own publication record (`pid_written` for
`current`/`spec`, `published` for `proposed`) and emit `VOID` on timeout. **Those changes are
UNRUN as well**, on the same committed `lock-owners.tsv`. That a mis-staged S4/S6 trial
degenerates into S5's control and yields exactly 1 owner is **[inferred]** — it follows from
`trial_scratch` being `trial_deadN` with the incumbent absent, and no committed cell distinguishes
the two. **To close, for that inference and for everything it qualifies: re-run S3, S4 and S6
under the gated driver and confirm the `VOID` count is zero.**

**S1 and S2 had the same defect in a different place, and it is now fixed the same way.**
`trial_init` staged the racers behind a fixed `sleep 0.004` after forking the winner, which is
an assumption that the winner has claimed the lock, not a fact. When it does not hold the racers
arrive at an *empty* directory and the trial silently degenerates into S5's who-wins control —
so a **clean** S1/S2 cell could be clean because nothing was staged, not because the protocol
held. That is the mirror image of the S3 problem: there the risk was a false pass for `proposed`,
here it is a false *clean* for `current` and `spec`, whose S1/S2 cells at stall 0 and 5 ms are
the ones reported clean. **The first attempt at fixing it was itself too weak, and that is worth recording.**
Waiting for the winner's own `mkdir_ok` / `published` record is still a one-way wait: after
that record appears, each racer has to start a **fresh Python interpreter**, tens of
milliseconds, while the window under test at stall 0 and 5 ms is *smaller than that*. The
winner would write its pid first and the cell would degenerate exactly as before — so
"the racers land inside the window by construction" was wrong when this document first
claimed it. The staging is now a **two-phase barrier**, and the first attempt at *that*
was also too weak: an acknowledgement written just *before* the protocol read still lets
the winner see the last ack and publish before that racer looks. So a racer now
acknowledges only **after it has actually observed the state under test** — for
`current`/`spec` a lock directory with no `pid` in it, for `proposed` an existing
generation record, there being no pid-less state to observe. The winner blocks after
claiming until `N` such acknowledgements appear, and only then applies the stall and
writes its pid. The window is therefore
established by *ordering* rather than by out-running an interpreter start.
A trial whose staging still fails emits `VOID` — and `summarise.sh` excludes `VOID` from
both the numerator and the denominator and reports it on its own line, because a staging
failure coerced to `owners=0` would otherwise read as a *protocol* failure and quietly
inflate the very rate this table is about. **That change is UNRUN too**, on the same committed `lock-owners.tsv`. It
does not put any *failure* in doubt: a mis-staged trial degenerates into the empty-directory
control, which yields **1** owner, so any cell that produced 2 or 3 owners demonstrably staged
correctly. That covers every wrong result reported here — `current` 121/400 (S1 at 50 ms, 60;
S2, 40; S3, 20; S6, 1) and `spec` 61/400 (S2, 40; S3, 20; S6, 1). What it qualifies is every
**clean** cell in the table: S1/S2 at stall 0 and 5 ms, `spec`'s S1 at 50 ms — one of the two
places the document credits the spec's own fix with working — and, after round 5's finding above,
**S4 in all three protocols and the 59-of-60 clean part of S6 as well**, since those staged their
incumbent by the same kind of sleep.

**S6's single failures (1 in 60, both protocols) are the same defect at its natural window
width.** No stall was injected; the ABA simply happened on its own once per 60 trials under
contention. That is the honest answer to *"the failure windows are microseconds wide"* — at
N = 8, unprovoked, it fires at roughly 2 %.

**`proposed` is clean on 400 of 400, and after round 5 the committed run confirms none of that
as reclamation.** The 400 decompose, and the decomposition is the finding:

| `proposed`'s 400 trials | n | what the committed data supports |
| --- | --- | --- |
| S1, S2 | 220 | **structurally vacuous.** There is no `mkdir`→write window for a stall to sit in — a `symlink`'s target is created with the object — so a stalled-but-live winner is simply seen as alive. Never a pass to be counted |
| S5 | 80 | **valid, and answers a different question.** No incumbent, no staging sleep, nothing to mis-stage. It is the who-wins race, which §3.0 says must not be conflated with row 21 |
| S3, S4, S6 | 100 | **the reclamation scenarios, and all 100 are unconfirmed.** Every one staged by a fixed sleep, and for `proposed` a mis-staged trial yields the same `owners=1` a pass yields |

The asymmetry is what makes this fatal for `proposed` alone. Under `current`/`spec` a mis-staged
S3 trial degenerates into S4 and yields 1 owner, so their 20/20 two-owner results are their own
proof the staging held; under `proposed`, `elect_proposed` sees a live owner, records `lost`, and
returns 1 — indistinguishable from never having seen a dead one. Round 3 applied that reasoning
to S3 and stopped there, reporting **160 genuinely-exercised trials (S4, S5, S6)**. S4 and S6
stage their incumbent by `sleep 0.05`, so the same argument applies to them verbatim, and the
count is not 160.

**Read the headline as: `proposed` produced 1 owner on 400 of 400, of which 80 (S5) exercise the
who-wins race and 0 are confirmed to have exercised reclamation of a dead owner.** That is not
evidence `proposed` fails — no trial produced a wrong number, and no *failure* anywhere in the
table is in doubt, since mis-staging can only hide failures, never invent them. It is a statement
that **the mechanism `proposed` exists to provide has not yet been shown to have run.** The
harness is now correct on all three scenarios; the committed `lock-owners.tsv` predates every one
of those fixes. Re-running S3, S4 and S6 under the synchronised driver is an open item, carried
in §13 row 21.

**And this is the fifth consecutive round in which review found a defect in the previous round's
repair of this harness, always in the staging rather than in the design.** §4a and §4b have been
stable for several rounds. `run_lock.sh` has not: a 4 ms sleep, then a one-way wait, then a
one-phase barrier, then a two-phase barrier — and now a fixed sleep in three functions the
previous three repairs walked past. **The honest conclusion is that inspection is not converging
on this harness, and no further reading of it should be trusted to settle the lock evidence.**
The committed lock data predates every staging fix listed above, and **the re-run is the only
thing that closes it.** Until then the row-21 result should be read as: `current` and `spec` are
falsified (their failures are self-proving and stand), and `proposed` is unfalsified but
unconfirmed.

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
>   one `readlink`. **A loser retries; it does not fail.** `symlink` returning `EEXIST` means
>   only that someone else got to this generation number first, so the elector re-reads the
>   highest generation and starts over — `lockrace.py:243` and `:249` both `rec("publish_lost")`
>   and `continue`, bounded at 60 attempts. **This is what gives S3, S4 and S6 their liveness**
>   and the old clause never stated it: without the restart, a legitimate reclaimer that lost a
>   generation race would conclude nothing rather than re-examine a lock that is now live.
> - **Obsolete generations, and the ordering the round-2 text left out. `rewrite.sh:117` does
>   NOT reclaim them, and citing it as the backstop was wrong.** Verbatim **[repo]**:
>
>   ```
>   find "$BUF_ROOT" -mindepth 2 -maxdepth 2 -type d -mmin +30 -exec rm -rf {} + 2>/dev/null || true
>   ```
>
>   A generation record is `$BUF_ROOT/<sid>/speak/worker.lock.<gen>` — **depth 3**, which
>   `-maxdepth 2` excludes, and **a symlink**, which `-type d` excludes again (`find` without
>   `-L` types a symlink as `l`). That sweep can never remove an obsolete generation. The one
>   thing at depth 2 it *can* match is `speak/` itself — which takes the **current** generation
>   with it, and is precisely the hazard PR #27's §10.5 clause 6 exists to exclude by keeping
>   the worker's idle exit strictly shorter than the sweep window. So there is no backstop:
>   **generation cleanup has to be specified, and it has to be ordered.**
> - **The ordering, stated. [inferred] and UNRUN.** A worker may unlink generation `g` **only
>   after it has completed BOTH halves of its election sweep against `g`'s owner** — 7(iv) and
>   7(iv-a) — and **only the worker that created `g+1` may do it**. The reason is §5's own
>   safety argument: the sweep walks *every* generation down to zero
>   (`speakd_probe.py`'s `for gg in range(g, -1, -1)`), and an unlinked generation is a `continue`,
>   not a signal. Unordered, the interleaving is the `C11b`/`C12c` failure by another door: `W1`
>   owns `gen1`, forks `P1`, dies in the `P`→`W` region; `W2` is elected at `gen2`, unlinks
>   `gen1`, then dies before finishing its own sweep; `W3` is elected at `gen3`, finds `gen1`
>   gone, `continue`s, never `killpg`s `pid1` — and `P1` plays to completion, which is the
>   12/12 those two arms measured. **Nothing here is measured:** `lockrace.py` never unlinks a
>   generation, so all 400 trials ran with every generation present. §13 row 21's closing
>   condition now names it.
>
> **Measured: exactly 1 owner on 400 of 400 trials** — but **none of those 400 is confirmed to
> have exercised reclamation of a dead owner** (§3.3): its three reclamation scenarios, 100
> trials, all staged their incumbent or their stale observation by a fixed sleep, and for this
> protocol a mis-staged trial yields the same 1 owner a pass yields; 220 more are structurally
> vacuous and the remaining 80 answer the who-wins race. It is unfalsified, not validated —
> against 121/400 wrong for `current` and
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

### 4b. §10.5 clause 7 — six hooks, and three of the first revision's are wrong

> **7. §10.5 owes §10.6 six hooks. Every clause below names the arm that measured it.**
>
> **Read (iv) and (iv-a) together.** Round 2 specified the process-group sweep as the whole of
> what an election does. **No arm ran that.** Of the 26 configurations, twelve sweep at all:
> seven run `sweepmode=both`, four run `sweepmode=record`, and `C9` reaches `record` through the
> legacy `--sweep-on-election` alias — **`sweepmode=pgid` is set by nothing** **[rig]**. So the
> pgid sweep has never been measured on its own, and in two of the
> `both` arms — `C15c` and `C16b` — `killpg` was **skipped 25/25** and the **record** sweep did
> the killing, 12/12 each. (iv) and (iv-a) are not alternatives, and (iv) alone is unmeasured.
>
> - **(i) The pid record is per-PLAYER, at a unique path, published by the player before it
>   can make a sound. REQUIRED.** `speak/playerdir/<pid>.<nonce>`, written by a wrapper that
>   then `exec`s, and unlinked only by exact name. **One shared `speak/pid` must not be used:**
>   an older player's reap unlinked a newer player's record on 12/12 trials, and a hook firing
>   in that window could not reach a live player on 4/12 (`C14a`); with per-player names, 0/12
>   (`C14b`). **An append-only ledger must not be used either:** its truncate erased
>   registrations it had never signalled on 12 of 25 truncations (`C13a`).
> - **(ii) The pre-spawn re-`stat` of `speak/job` is an optimisation GIVEN AN ELECTION-TIME
>   SWEEP, and a correctness clause without one.** With the worker surviving, removing it
>   changes nothing (`C5`, 12/12). With the worker dying after the spawn and **no sweep at
>   all**, removing it **creates an orphan that nothing kills** (`C15b` 12/12 versus `C15a`,
>   where no player is spawned at all). With the election sweeping, the orphan is caught anyway
>   (`C15c`, 12/12). Keep it; state the condition. **The condition is (iv-a), not (iv)** — round
>   2 wrote "given (iv)" and credited the process-group sweep, but `C15c` skipped `killpg` on
>   every one of its 25 elections and the kill is attributed to the **record** sweep. A reader
>   who implemented (iv) alone and dropped (ii) on the strength of this bullet would have got
>   `C15b`'s result, not `C15c`'s.
> - **(iii) The worker kills the current player the moment it claims a newer job. REQUIRED,
>   and it must kill BOTH targets** — its own handle *and* every published record. Measured
>   load-bearing (`C4`: without it, 12/12 run to completion). The two targets are
>   indistinguishable while a record exists (24/24) and opposite when none does (12/12 each
>   way, `C10a`/`C10b`).
> - **(iv) A newly elected worker kills the PROCESS GROUP of each superseded owner, before it
>   loads the model. REQUIRED, and it is the only thing that reaches a player which has
>   published nothing.** Membership is established by `fork(2)`, before the child executes an
>   instruction, so it reaches a player that has not been scheduled. Measured on both sides of
>   publication: `C12a` killed 12/12, `C12b` killed before `exec` 12/12 — where the
>   single-record and record-only repairs both fail 12/12 (`C11b`, `C12c`). The placement
>   before the model load is normative: the load is 0.80–2.02 s **[hook]**, and a sweep after
>   it would let the orphan talk through all of it.
>   - **The WORKER detaches; the player does not. This is one rule with two halves, and round 2
>     stated neither half.** The whole clause depends on an uncited line of the probe —
>     `os.setsid()` on the worker's own first statement, before it elects — because the sweep
>     signals the owner's **pid as a pgid**: `killpg(owner_pid, TERM)`, never
>     `killpg(getpgid(owner_pid), TERM)`. Both halves are normative and both fail loudly if
>     dropped:
>     - **Omit the worker's `setsid()` and the sweep is a silent no-op.** A worker started the
>       natural way — `nohup … &` from the hook — inherits the *hook's* process group and is not
>       a group leader, so `killpg(owner_pid, …)` returns `ESRCH` and signals nothing. This is
>       the same class of failure as §2.5 item 5's `nohup`/`SIG_IGN` arriving by a different
>       door, and the probe's own `signal_dispositions` guard **cannot** detect it. macOS ships
>       no `setsid(1)`, so it must be done in-process (`os.setsid()`, or `setsid()` between
>       `fork` and `exec`).
>     - **Write the clause's English as `killpg(getpgid(owner_pid), …)` and it is catastrophic,
>       deterministically.** "Kills the process group of each superseded owner" reads as a
>       `getpgid` lookup; without the worker's own `setsid()` that group is the **hook's** —
>       under Claude Code, the harness's own process group. This is not a race; it fires every
>       time.
>     - **Never detach the PLAYER.** `start_new_session=True`, or any `setsid()` on the child,
>       removes it from the group and defeats (iv) completely — measured, orphan plays to
>       completion 12/12 (`C17`). Round 2's only sentence on detachment was "Never detach the
>       player", which reads as *nothing detaches*, and that reading breaks the clause.
>   - **Bound it with a `.pending` marker.** The worker creates `playerdir/<nonce>.pending`
>     *before* the fork; the wrapper renames it away as its first act. `killpg` is used only
>     while such a marker exists, which confines its blast radius to the window where an
>     unnamed player can exist. Measured: skipped 25/25 when not needed (`C16b`), used 23/25
>     and effective when needed (`C16a`).
>   - **Requires row 21's generation protocol.** (iv) reads the *superseded* owner's pid. A
>     lock protocol that deletes the record of the worker it replaced cannot supply it, so
>     §10.5 clause 2 and clause 7(iv) must ship together.
> - **(iv-a) The same newly elected worker ALSO sweeps the published player records, in the same
>   election and also before the model load. REQUIRED. NOT an alternative to (iv).** One
>   `readdir` of `playerdir/`, then `kill(pid, TERM)` for every name that parses as a record.
>   **It unlinks nothing** — removal belongs to (v) and to §5's garbage collection, and a sweep
>   that unlinks is the `C13a` truncation defect in another shape.
>   - **The two clauses cover disjoint players and that is why both are required.** (iv) covers
>     the player that has published **nothing** — no record exists, only group membership does.
>     (iv-a) covers the player that **has** published, and whose `.pending` marker is therefore
>     already gone, so (iv) is *skipped by its own bound*. Measured, and the arithmetic closes:
>     in **both** `C15c` and `C16b` the `.pending` was created 25 times and found at **0 of 25**
>     sweeps, `killpg` was skipped **25/25**, and the record sweep signalled on exactly **12** of
>     its 25 elections — the twelve trials. `summarise.sh` section A attributes the kill in both
>     arms to **`election-sweep-record`**, 12/12 each; `analyse_round2.sh` prints the counts.
>     Without (iv-a), §4b as round 2 wrote it specifies **nothing at all** for that case: the
>     orphan survives the election and is not reached until the next claim — after the
>     0.80–2.02 s model load, which (iv) itself says is fatal.
>   - **Placement, same as (iv): before the model load.** Same reason, same measurement.
>   - **Its target list is bounded by nothing** — see §5. This is a real cost of requiring it,
>     not a footnote.
> - **(v) The worker must `wait()` its player, and unlink that player's own record when it
>   does.** `kill(2)` on an unreaped **zombie succeeds**, so an unreaping worker makes every
>   kill site report success while killing nothing (`C7`, both sites 12/12 against a process
>   already dead). Unlink by exact name only — see (i).
>   - **The REQUIRED unlink is specified but UNMEASURED in combination with the sweeps.**
>     `unlinkreap=on` is set by exactly two configurations, `C14a` and `C14b`, and both run
>     `sweepmode=off` **[rig]**. Every arm that measured either sweep ran `unlinkreap=off`, so
>     records accumulated and nothing ever raced an unlink against a `readdir`. What (v) and
>     (iv-a) do to each other is therefore **[inferred]**: reaping removes exactly the name it
>     published, so a concurrent `readdir` can only miss a player that is already dead, which is
>     harmless — but that argument has no arm behind it. To close: re-run `C12b`, `C16a` and
>     `C16b` with `unlinkreap=on`.
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
> killed before it can `exec`, 12/12. **It closes on 7(iv) AND 7(iv-a) together**, because
> 7(iv)'s `.pending` bound switches it off for exactly the players that 7(iv-a) covers.
>
> **And *"cancellation is latency only, not correctness"* is true with its condition
> discharged** — conditional on 7(iii) with both targets, 7(i) as per-player records, 7(iv)
> with its `.pending` bound *and* the worker's own `setsid()`, 7(iv-a)'s record sweep, and
> 7(v)'s reaping. All are measured **except (v)'s unlink in combination with either sweep**,
> which is `[inferred]`. The residual cost is the newer utterance waiting out the older
> synthesis.

### 4d. §13 — proposed row text

> | **20** | ~~§10.6's preemption rests on three worker-side hooks that are all [inferred]~~ |
> **MEASURED 2026-08-25/26 and PARTLY FALSIFIED — twice.** 312 trials over 26 switchable
> configurations. The adversarial `R < S2 < R_b < P < W` was provoked **48/48** with the hook's
> kill hitting nothing every time; clause (iii) is confirmed load-bearing (36/36 killed before
> any sound) and its absence fatal (**12/12** run to completion; two real utterances overlap
> **3.25–3.50 s**). **The two-kill partition leaves a third region** — a worker dying between
> `Popen` and the record write orphans a player nothing reaches, **12/12**, window median
> **1.41 ms** over the 72 worker-published trials. **The first proposed repair does not close
> it:** a single player-written record fails **12/12** when the sweep lands before publication,
> and per-player records alone fail the same way. **What closes it is a process-group sweep
> PLUS a record sweep, both at election time** (`fork` establishes membership before the child
> runs, and the `.pending` bound switches the group sweep off for exactly the players the
> record sweep covers): killed before `exec` **12/12** where the group sweep fires, killed
> **12/12** by the record sweep where it does not (`C15c`, `C16b`, `killpg` skipped **25/25**).
> The group sweep is defeated entirely by one `setsid()` on the player (**12/12** orphans
> survive) and requires one on the *worker*, which no round before this one stated. Also
> measured: `kill` on an unreaped **zombie succeeds**; a shared record's unlink is a **TOCTOU**
> (a newer player's record proven destroyed on 4/12 trials, 8 unlinks; hook blind to a live
> player on the same 4/12 — round 3 said 12/12 and 24 unlinks, from a bad timestamp, §2.5);
> the ledger's truncate
> **erases unsignalled registrations** (12/25); clause (ii) is a correctness clause **only
> without an election-time sweep**. Requires row 21's generation protocol —
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
> yielded **exactly 1 owner on 400/400** — **but none of those 400 is confirmed to have exercised
> reclamation of a dead owner**: all 100 of its reclamation trials (S3, S4, S6) staged the
> incumbent or the stale observation by a fixed sleep, and for this protocol a mis-staged trial
> yields the same 1 owner a pass yields; 220 more are structurally vacuous and 80 answer the
> who-wins race. The staging fixes are in the harness, not in the run. **The measured 8/8 `mkdir` result is untouched and
> is a different race**, re-run here at N ≤ 16 for all three protocols, 1 owner on 80/80 each
> **[measured-here]** | **YES** — the shipped clause is now known false, and its replacement
> is unreviewed. **Closing conditions:** (1) a review pass by someone other than §4a's author;
> (2) **the generation garbage collection is specified but UNRUN** — `lockrace.py` never
> unlinks a generation, so all 400 trials ran with every generation present, and the ordering
> rule §4a now states (unlink `g` only after completing both halves of the election sweep
> against `g`'s owner, and only from the worker that created `g+1`) has no arm behind it.
> `rewrite.sh:117` is **not** a backstop for it and §4a no longer claims it is; (3) **re-run S3,
> S4 and S6 under the synchronised driver.** This is now the binding evidence item, not a
> footnote: five consecutive review rounds have each found a staging defect in the previous
> round's repair of `run_lock.sh`, and §3.3 states plainly that no further inspection of that
> harness should be trusted to close it |

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
  **This limitation used to say the proposed form handles exactly one orphan, and that is
  no longer what 4b(i) proposes.** Clause 4b(i) now specifies **unique per-player records**
  — `playerdir/<pid>.<nonce>`, one per player, never overwritten — so representing N
  simultaneous orphans is no longer the open question; the record set does it by
  construction, exactly as the ledger did. What remains unmeasured is narrower and worth
  stating precisely: whether the **paired** sweeps of 7(iv) and 7(iv-a) still reach every
  orphan across **consecutive** worker deaths, where each new election must sweep a
  superseded generation it did not itself create. `sweep_pgid` walks every generation down
  to zero for that reason, and no arm here staged two deaths inside one player's lifetime.
  **[inferred]**. To close: stage two consecutive worker deaths inside one player's
  lifetime and count survivors under the paired sweeps.
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
- **REUSE is unmeasured for BOTH sweeps, and round 2 priced it for only one of them.** The
  hazard has two shapes and they are not equally bounded:
  - **Process-group reuse, clause 7(iv).** The sweep `killpg`s the superseded owner's pid. If
    that pid has been recycled *as a process-group leader* of an unrelated group, the sweep
    signals strangers — the blast radius is a whole group rather than one process, which is
    **worse than the pid-reuse hazard it inherits**. The `.pending` marker bounds *when*
    `killpg` is used to the narrow window where an unnamed player can exist — measured, skipped
    25/25 when unneeded (`C16b`) and used 23/25 when needed (`C16a`).
  - **Pid reuse in the record sweep, clause 7(iv-a), which nothing bounds at all.** It is
    `os.kill` over **every name in `playerdir/`**, on **every** election, gated by no marker and
    by no liveness check. **The leak §5's second garbage-collection bullet calls untidiness IS
    this sweep's target list** — the two are the same object, and round 2 never said so. Its
    measured cardinality, from the committed `C12b` trace: the list grows **monotonically to 12
    pids within a single 12-trial run** — 11 of them long dead by the last election — and the
    warm-up player `94309` is a target in **24 of the 25** sweeps, from the moment it exists
    until the run ends. `analyse_round2.sh` prints both. Nothing in the design causes that list
    to shrink; §5's `.pending`/record cleanup below is what would, and it is unimplemented.
  - **Neither reuse is measured.** To close: the same pid-space-wrap experiment named above,
    checking both whether a recorded owner pid ever names a live unrelated *group leader* and
    whether a stale record name ever names a live unrelated *process*. Until then this is the
    one place where the repair could do more damage than the defect it fixes, and it is the
    reason `.pending` is specified as normative rather than optional — and the reason 7(iv-a)'s
    unboundedness is stated in the clause itself rather than left here.
- ~~A player that leaves its process group defeats clause 7(iv) entirely — normative and
  untested.~~ **MEASURED (`C17`): the orphan plays to completion 12/12.** Not an open item any
  more; it is a normative constraint with an arm behind it.
- **There are TWO garbage collections, neither is implemented or measured, and round 3 named
  this as where it expected the next defect. It was right — round 4 found one in each.** Both
  are cleanup steps acting on a path, which is the exact shape of the two races review had
  already found. The bullets below are the corrected forms; **the prediction still stands for
  the round after this one**, because both remain unimplemented.
  - **Lock generations.** `lockrace.py` never unlinks an obsolete generation, so **all 400
    trials ran with every generation present** — the ordering §4a now specifies has no arm
    behind it at all. Round 2 offered `rewrite.sh:117` as the backstop; it is not one, and
    §4a now says why: a generation record is a **symlink at depth 3**, which `-maxdepth 2` and
    `-type d` each exclude on their own, so that sweep can never remove one. The safety
    argument is also stronger than round 2's "the highest generation always exists while its
    owner lives", because the sweep walks *every* generation down to zero and an unlinked one
    is a `continue` rather than a signal: **unlink `g` only after completing both halves of the
    election sweep against `g`'s owner, and only from the worker that created `g+1`.** All
    **[inferred]**. To close: add the unlink and re-run S3, S4 and S6 with a reclaim delay
    straddling it, and add an arm that kills the electing worker between the unlink and the
    sweep.
  - **Player records and `.pending` markers.** `playerdir/` accumulates a record per player and
    nothing removes the records of players that died without reaping (the warm-up player's
    record is visible in the committed `C12b` trace, still present several generations later).
    A stale `.pending` is worse than untidy: it makes every later election take the `killpg`
    path, so the bounding property `C16` measures **degrades to unbounded after one worker dies
    before forking**.
    **Round 2's fix was not implementable as written, and this is the correction.** It said "a
    newly elected worker removes the `.pending` entries it has just swept" — but *"the entries
    it has just swept"* is not a determinable set. `sweep_pgid()` reads `.pending` as a
    **boolean**: it `listdir`s, and if the list is non-empty it signals **every** superseded
    owner. The nonce binds to no generation and to no owner pid, so when `killpg` fires there is
    no mapping from a marker to the owners the marker prompted it to signal. Specify it
    concretely instead:
    - **Tag the marker with its owner generation — `playerdir/<gen>.<nonce>.pending`.** Round 5
      specified removal by `listdir` membership, and that was still not a determinable set: it
      cannot say *whose* marker it is, so an election cannot tell a marker it superseded from a
      marker a live generation is about to use. The generation tag is what makes ownership
      readable, and it is the same shape §10.5 of the spec now specifies, so the two documents
      agree rather than describing two schemes.
    - **Remove exactly the markers whose generation is among the ones this election superseded**,
      and leave every other marker alone.
    - **Do it BEFORE the electing worker forks any player of its own.** Otherwise the GC
      deletes the marker for a fork that has not happened yet, the next election sees no
      `.pending`, skips `killpg`, and the design collapses into `C12c` — the record-sweep-only
      arm that fails 12/12.

    **Why an un-reaped marker is not merely untidy — measured, in `C16a`.** The wrapper renames
    its own marker away as its **first act**, so a `killpg` that *works* kills the wrapper
    **before** that act and strands the marker that authorised it. Every successful sweep leaked
    exactly one. The committed trace: **25 markers created, 0 removed**, `pending_found` climbing
    **1 → 12** across twelve generations, and `33f62e9b.pending` surviving from `gen1` to
    `gen12r`. The consequence is the opposite of the bound the marker was introduced to provide —
    **23 of 25 elections ran `killpg` although only 12 orphan windows were ever staged.** The
    marker did not bound the window; it accumulated, and after the first leak the gate is
    permanently open. The trace separates the two halves cleanly: the leaked names are exactly
    the killed players, while `6fad43e5.pending`, whose player published normally, never
    reappears.

    The reaping is implemented in `speakd_probe.py` (`pending_reaped` / `pending_reap_failed`),
    but it is **[inferred]** as a *result*: the committed traces predate it and were produced
    under the un-tagged name, so no arm here exercises it. To close: re-run `C12b`, `C16a` and
    `C16b` under the tagged marker with a pre-seeded stale `.pending` and a pre-seeded dead
    record, and confirm `pending_found` does not grow across generations.

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
argument about labels — it is an induction over five rounds of review.**

### What the five rounds actually did

| round | the clause it examined | verdict |
| --- | --- | --- |
| PR #27 | *"a newer message kills stale playback"*, `[inferred]` | reviewer found **two races** in the lock clauses before anything was measured |
| PR #28 rev 1 | those clauses, measured | `current` **and** the spec-corrected protocol both produce 2–3 owners; clause (ii) mis-specified; the `P`→`W` region uncovered |
| PR #28 rev 2 | **the repair rev 1 proposed** | reviewer found the repair **was not the one measured**, and that the arm which "closed" the region **could not fail**. Staged properly, **rev 1's repair fails 12/12** — and two further protocol defects in it (shared-record TOCTOU, ledger truncation) both reproduce |
| PR #28 rev 2, self-review | **the repair THIS revision proposes** | `killpg` blast radius under pid reuse (bounded, measured); one `setsid()` defeats it (measured); and the sweep signal itself was a silent no-op under `nohup` (found only by chasing a null) |
| PR #28 rev 3 | **§4b as rev 2 wrote it, read as an implementer would** | **§4b specified ONE election-time action and its own data credits a second one with the kill** — `C15c` and `C16b` skip `killpg` 25/25 and are killed by the *record* sweep, which §4b never mentioned (clause 7(iv-a)). **§4b never required the worker to `setsid()`**, without which the sweep either signals nothing or signals the harness's own process group. **§4a's garbage collection cited `rewrite.sh:117`, which cannot reach a depth-3 symlink**, and specified no ordering against the sweep — the unordered interleaving is `C11b`/`C12c` at 12/12. **§5's `.pending` GC was not implementable as written.** Plus a fourth harness defect touching a published figure (`W` in the player-published arms), a parser that signalled a filename as a pid, a run script one round behind the document, and two derivations that did not derive what they claimed |

| **PR #28 rev 4 (this)** | **the probe tooling and the staging, the two things rev 3 did not re-examine** | **The committed harness could not be run from a checkout at all** — every driver resolved its helpers from a private bench directory and two invoked one user's absolute interpreter, so on the author's machine they could execute stale external copies of the very probes this PR commits. **`run_lock.sh` still staged three scenarios by a fixed sleep** — S3's incumbent (`:114`), S4 (`:145`) and S6 (`:181`) — which the previous round's barrier repair walked past, and that costs `proposed` **every one of its 100 reclamation trials** (§3.3). **Harness defect 4 had a second consumer nobody had looked for:** `C14a`'s publication→destruction lag, and with it the *count* — the TOCTOU is 4/12 trials and 8 unlinks, not 12/12 and 24 (§2.5). **§2.6's stale-player lifetime was published as an interval it is not** — timer-start→exit, not `Popen`→exit, differing 7× on the same row |

**Five consecutive rounds, and every round found a real defect in the previous round's
confident answer.** Rev 1's own headline — *"a repair was built and measured: 12 of 12 orphans
killed"* — was wrong in the way that matters most: the repair specified was a single replaceable
record, the thing measured was an append-only ledger, and the arm that measured it had a 1.2 s
delay that guaranteed the sweep always ran after publication. When the ordering rev 1 claimed to
close was finally staged (`C11b`), **the single-record form failed.**

### So the counter-argument is now refuted five times over

The original argument for non-blocking was that these clauses are *"cheap, obviously correct on
inspection, and their failure windows are microseconds wide."*

1. **"Obviously correct on inspection" has now failed on eleven distinct clauses** — the two
   lock clauses, clause (ii)'s scope (twice: first mis-scoped, then credited to the wrong
   sweep), the shared-record lifecycle, the append-only ledger's truncate, the
   player-authored-record repair, the process-group sweep's own blast radius, the sweep's
   dependence on an unstated `setsid()`, the missing record sweep at election time, the
   generation GC's non-existent reclaimer, and the `.pending` GC's undeterminable set.
   Inspection is what produced all eleven. The player-authored-record repair is the sharpest
   case: it was proposed *in response to* a measured defect, read as obviously correct by its
   author, and **fails 12/12** once the ordering it was written for is actually staged. The
   `setsid()` omission is the second-sharpest, because it is the *invisible* kind: the clause
   reads correctly, and the line it silently depends on is in the probe rather than in the text.
2. **"Microseconds wide" is false for most of them.** The pid-less lock window is a scheduling
   delay (unbounded). The ABA window is a reclaimer's own think-time. The publication window is
   as wide as the wrapper stays descheduled — `C11b` widened it deliberately, but nothing bounds
   it in the real system. Only the `P`→`W` window is genuinely sub-2 ms, and this document says
   so plainly rather than inflating it.
3. **"Cheap" is true of writing them and false of getting them right.** Getting to a repair that
   survives staging on both sides of publication took three protocol variants for row 21, six
   configuration families for row 20, and three rounds of adversarial review.

### What would take them off the list

**Not more measurement from me.** The measurements exist and the arms that can falsify each
clause exist. What is missing is the thing that has caught a defect every single time: **an
adversarial reader who did not write the text.** Concretely, before rows 20 and 21 move to
non-blocking:

- **§4a and §4b need one review pass by someone other than their author**, on the standard that
  found the defects in rounds 1–5. **Round 3 predicted the garbage collection as the most likely
  place for the next defect, and that is where two of round 4's landed** — `rewrite.sh:117`
  cannot reach a generation record, and the `.pending` GC named a set that does not exist. Both
  are now specified rather than gestured at, and **both are still unimplemented and unmeasured**,
  so the prediction stands for the round after this one.
- **Row 20's clauses 7(iv) and 7(iv-a) are the newest things in this document, and they are the
  THIRD proposed repair for the same region.** The first (player-authored single record) is
  measured to fail; the second (per-player records alone) is measured to fail; this one is
  measured to work — **but not in the shape round 2 wrote it**, which specified only the group
  sweep. **`sweepmode=pgid` was never run by any arm**, so "the group sweep alone" has no
  evidence either way, and what is actually measured is the *pair*. That history is the argument
  for a review pass, not against it.
- **One clause depends on a primitive whose failure mode is worse than the defect, and a second
  depends on a line that was never in the text.** `killpg` under pid reuse signals a whole group
  of unrelated processes; the `.pending` marker bounds when it fires and that bounding is
  measured, the reuse is not. And the whole clause requires the *worker* to be a process-group
  leader — `os.setsid()` before it elects — which round 2 never stated, and without which the
  same clause either signals nothing (`ESRCH` against a non-leader) or, written the other
  obvious way, signals the hook's own group. A reviewer should decide whether that trade is
  acceptable, because I cannot settle it by measurement here (§5).
- **The evidence-side items are open, and one of them is now the largest gap in the document.**
  `run_lock.sh` no longer stages anything by a clock — B's classification in S3, and the dead
  incumbent's record in S3, S4 and S6 — but **the committed `lock-owners.tsv` predates every one
  of those fixes**, so on the committed data `proposed` has **no confirmed reclamation trial at
  all** (§3.3): 100 of its 400 are the reclamation scenarios and all 100 were clock-staged, 220
  are structurally vacuous, and the remaining 80 answer the who-wins race. Nothing here suggests
  `proposed` fails — mis-staging can only hide failures — but the mechanism it exists to provide
  has not been shown to have run. **Five rounds have each found a staging defect in the previous
  round's repair of this one script**, so this is not a gap further reading will close; it is a
  re-run. Separately, clause (v)'s unlink has never run in combination with either sweep (§4b).
- **Row 21's replacement changes the lock's on-disk shape**, and row 20 now *depends* on that
  change: the process-group sweep has to read the superseded owner's pid, which a protocol that
  deletes the record it replaced cannot supply. **The two rows can no longer be signed off
  independently**, and that coupling is new information for whoever owns the call.

**One thing I will state as a judgement rather than a measurement.** If a reviewer decides to
ship anyway, the least-bad subset is **clause (iii) with both kill targets, clause (i) as
per-player records, and clause (v)'s reaping** — each is measured, each is falsified when
removed, and none depends on the newest mechanism or on `killpg`. The two election-time sweeps
would then be the one deferred piece, and the honest cost of deferring them is stated in §2.4:
a worker dying in a sub-2 ms window orphans one utterance, which plays to completion. That is a *bounded, single-utterance, low-rate* failure —
which is a defensible thing to ship, and a very different thing from shipping the lock clauses,
where the failure is two resident workers each holding a 340 MB model.
