# Preemption and the lock protocol — §13 rows 20 and 21, measured

**Date:** 2026-08-25, with **one correction on 2026-08-26**: §4a's generation-cleanup bullet
cited PR #27's §10.5 clause 6 as excluding the `speak/` sweep, and a machine sleep measured
that exclusion false. **Nothing else changed, no arm was re-run, and no figure in this
document moves** — the 312 preemption trials, the 1200 lock trials and every published
count are untouched, and the corrected sentence strengthens the conclusion it was
supporting. **The defect is in PR #27's clause, not in this document's protocol**, so this
correction is deliberately **not** counted in the induction over review rounds in §6 or in
that section's tally of clauses that failed inspection. **Owner issue:** #11 (spec) — this document does **not** edit
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
run's rig, **plus, for the clock figures added on 2026-08-26, the platform's own clocks
and power log**: `sysctl kern.boottime`, `time.monotonic()`, `pmset -g log`, and
`rewrite.sh:117`'s `find` predicate run verbatim against a staged directory. **Those are
the only [measured-here] figures in this document that no arm of the probe produced**, they
are about Darwin rather than about this protocol, and they are cited in exactly one place —
§4a's generation-cleanup bullet, where this document had asserted that PR #27's §10.5
clause 6 excluded a hazard it does not. **[rig]** — read out of a probe's own source.
**[repo]** — read out of the shipped tree. **[hook]** / **[obs]** — carried over from an earlier run, cited. **[inferred]**
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
  when it was not needed; `C16a` used it 23/25 when it was) — **but only if the sweep reads the
  marker's generation tag and retires the marker *after* signalling, and neither was true until
  this round; `C16a`'s 23/25 is the marker leaking, not the marker working** (§5). One
  keyword — spawning the player
  with `start_new_session=True` — **defeats the clause entirely** (`C17`, orphan plays to
  completion 12/12). **And a marker bounds *when* `killpg` runs, never *what* it hits**: the
  recorded owner's identity must be re-verified before signalling, and a record that carries no
  identity — a bare pid from before that rule, or from an implementation with the check off —
  must be treated as **unverifiable** rather than allowed to fall back to `kill(pid, 0)`. That
  fallback is the fifth defect found in this one bound, and it was inside round 15's repair of
  the fourth (§4a, §4b(iv), §5). **The sixth is in the ELECTION half of that repair**: an
  `unverifiable` owner may be a **live legacy worker**, so superseding it — which is the licence
  to consume jobs, not merely to signal — yields **two owners**, and nothing in the protocol
  observes being superseded, so superseding cannot serve as a drain. The election supersedes only
  a **vacant** pid and refuses a **held** one; mixed-mode operation is out of contract and the
  cost is a session that wedges on a recycled bare pid (§4a).
  **The seventh is in the instrument itself, and it made the guard fail open on exactly the input
  it exists to be careful about.** `ps -o lstart= -p <pid>` was read two-valued — a start time, or
  nothing — so a **transient lookup failure** (fork pressure, a full process table, a diagnostic
  on `stderr`) was indistinguishable from a **confirmed absence** and was classified `gone`.
  `gone` signals, and `gone` lets the election supersede, so one failed `ps` did both things the
  identity check was added to prevent: superseded a still-live owner, and signalled a pid that may
  already belong to a stranger — and it did so most readily under the very load that makes pid
  reuse fastest. A confirmed absence is now one specific observation and every other outcome is a
  distinct `lookup_failed` verdict: every signaller refuses it, and the election **retries and
  then loses** rather than falling back to `kill(pid, 0)`, because a bare record is unverifiable
  *forever* while a failed lookup is unverifiable *at this instant* (§4a, §4b(i)).
  **And the PLAYER records had no identity at all, which is the same defect one record over** —
  the anchored `<pid>.<nonce>` name added in round 20 is a *parsing* fix, nothing removes a
  player record when its player dies (`C12b`'s warm-up record is in the sweep's target list on
  **24 of 25** elections), and three separate sites signalled a pid taken straight from it. The
  record's **content** is now `<pid>.<starttime>`, as PR #27 clause 7(i) specifies, and the hook,
  the election sweep and the claim-time kill all verify it (§4b(i)).
  And a sweep signal that anything ignores makes the sweep a silent no-op:
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

† **`proposed` produced 1 owner on 400 of 400, and exactly ONE of those trials is confirmed by a
committed trace to have exercised reclamation — not none, as an earlier revision of this footnote
said.** `traces/lock-S3_aba-proposed-r1.tsv` records the whole mechanism directly: the winner
publishes `gen=0 owner=79728` with a dead pid, **both** racers record
`classified_stale reason=pid_dead pid=79728 gen=0`, and racer `79731` then publishes
`gen=1 superseded=0` and takes ownership `via=election` while the other records
`publish_lost` and `lost`. Fixed-sleep staging makes the **untraced** trials unconfirmed; it does
not erase a trial whose trace shows the reclamation happening. Seven per-trial lock traces are
committed, three of them S3 — and only `proposed`'s carries a `superseded=` publish, because
`current` and `spec` reclaim by `rmdir`/`rename` rather than by superseding. So the confirmed
sample is **1 of 100**, and the remaining **99** are unconfirmed aggregate rows. Round 3 said 20 were unconfirmed (its S3 cell, staged by a fixed 4 ms
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
`current` fails 60 of the same 180 — **but 60 of those 180 are the stall-0 cell, which is a
zero-width window and therefore not a test of clause (a) at all**, §3.3), then **40/40 wrong at
200 ms and 1000 ms** — a bounded backoff cannot distinguish a descheduled winner from a dead
one — and **20/20 wrong on the
quarantine ABA**, where `rename(2)` is atomic on a *path* and a reclaimer acting on a stale
observation renames the fresh owner's live lock and gets success rather than `ENOENT`.

**And the two rows are now coupled.** Row 20's process-group sweep must read the *superseded*
owner's pid, which only row 21's generation protocol supplies — a protocol that deletes the
record of the worker it replaced cannot. They can no longer be signed off independently.

**Both rows stay ship-blocking**, and the reason has changed: they are no longer unverified.
**Ten consecutive rounds of review have each found a real defect in the previous round's
confident answer**, including in the repair this document proposed, in the *text* of the repair
that replaced it, round 16's defect in the identity check round 15 added to repair the repair,
and — round 17 — in the *derivations* of two published figures rather than in any mechanism. See §6.

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

**Twelve derivation defects have been found by review, and all twelve are fixed here. Five of
them made the reproducibility claim false, which was the claim the whole document rested on.**
The first three came from review of the first revision; the next two from round 5, the sixth from
round 15, the seventh and eighth from round 16, the ninth and tenth from round 17, the eleventh
from round 21, the twelfth from round 24, and all of them are of the same kind — a figure whose
name and whose derivation are not the same quantity, or a derivation that does not reach the
figure it is cited for.
**Numbers 11 and 12 are both defects in the fix for number 9**, on the same figure, and that is
worth saying plainly: `C14a`'s destruction count has now been through a withdrawal and three
repairs. It has not moved through any of them, and that is a fact about this data rather than
about the arguments, each of which was wrong when it was made.

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
6. **`analyse_round2.sh`'s `C13a` section printed 20 of its 50 rows, and the ledger figure this
   document quotes was not among them.** The block ended `| head -20`. `C13a` emits 25 sweep
   lines and 25 truncate lines, so **30 rows were dropped in silence — 8 of the 12
   erasures among them**, leaving 4 visible. The document quotes *"erased registrations it had never
   signalled on **12 of 25** truncations"* in three places and cites this script for it; the
   script could not produce that count. The pipe is gone, every row prints, and the block now
   ends with the count itself (`--> 12 of 25 truncations erased a registration that was never
   signalled`). **`pipefail` alone would have made this worse rather than better** — `head`
   closes the pipe at row 20, `awk` dies of `SIGPIPE`, and a merely-truncated section starts
   reporting itself as a hard failure. The same pipe also put the block's exit status on `head`,
   so an `awk` that aborted read as a success; every block in that script now has its own status
   checked and the script exits 2 on a failed derivation as well as on a missing input.
7. **The attribution chain let the player's own log outrank the kernel's wait status — round
   16.** `summarise.sh`'s `attrib()` tested `sig=="-15" || plog=="15"`, then `-30/30`, then
   `-31/31`, then `-14/14`. The two inputs are not equals: `rc` is the parent's wait status,
   written once by the kernel, while `player_log_sig` is the **last** `sig=` the player wrote to
   its own log — `collect.sh` keeps only the last (`PSIG[$3] = V2["sig"]`). A player reached by
   two sites reports the second, and **the committed `C12b` log already contains one**: pid
   `94309` writes `player_end sig=14` and then `player_end sig=31`, 69 µs apart. A row with
   `rc = -14` and a final log value of `31` therefore matched the **record-sweep** arm first,
   purely because 31 is tested before 14, and was published as a record sweep although the wait
   status said process group. `sig` now decides alone whenever it exists and `plog` is consulted
   only for rows that have none — the player-published arms, where the parent never reaps.
   **THIS MOVED NO PUBLISHED FIGURE, AND THAT IS THE HONEST STATEMENT OF IT.** The
   `(rc, player_log_sig)` pairs present in the committed `preemption-trials.tsv` are
   `(-,0)`×72, `(-,-)`×60, `(-,31)`×48, `(-30,-)`×36, `(-15,15)`×36, `(0,0)`×24, `(-30,30)`×12,
   `(-,15)`×12, `(-,14)`×12 — **no row has both fields present and disagreeing**, so
   `summarise.sh`'s output is byte-identical before and after. It is a latent defect that would
   bite on a **re-run**, on an arm that has already produced the doubly-signalled process once.
   Fed a hand-crafted `rc=-14, plog=31` row, the old chain reports `election-sweep-record` and
   the new one `election-sweep-pgid`.
8. **`summarise.sh`'s own header claimed more coverage than the script has — round 16.** Line 2
   read *"Every published figure, re-derived from the committed TSVs"*. It is not every figure.
   The aggregate TSVs are one row per **trial**, and several published figures are counts of
   trace **events** that no TSV column carries — `record_unlinked`, `pending_found` /
   `pending_created`, and the sweep-skip events. So `C14a`'s **8 record destructions across 4
   trials** and the `C15c`/`C16` **25-election `killpg` counts** are derivable only by
   `analyse_round2.sh` over the committed raw traces. The two derivations are **disjoint and
   both required**; neither checks the other. This document already drew that boundary in the
   paragraph below; the script did not, and a script that overstates its own coverage is the
   quietest way for *"every figure re-derives"* to stop being true. The header now states what
   the script covers — sections A–F, from the TSVs — and names `analyse_round2.sh` for the rest.
9. **`C14a`'s headline figure was an addition of two counters that shared no key — round 17.**
   `analyse_round2.sh` counted `plog` (unlinks ordered after a newer player's own `player_start`)
   and `hookc` (hook-C reads that found nothing) as independent **global** totals, printed their
   **sum** as *"PROVEN destructions of a published record"*, and then stated as fact that *"they
   fall in the SAME k trials, and they are distinct unlinks"*. **Neither half was derived.**
   There was no join on trial and none on unlink identity, so the same unlink satisfying both
   witnesses, or the two counts coming from disjoint trials, would have produced identical
   arithmetic. This mattered more than the usual: the figure — **8 destructions across 4 trials** —
   is *itself* the correction that replaced a withdrawn one (24 across 12/12, lost with harness
   defect 4), so a correction was resting on an assertion, in the one spot this document has
   already published two wrong numbers. The keys were in the committed traces the whole time,
   including a third file the block never opened: `record_unlinked` carries `job=jNa|jNb`, so
   **(trial, timestamp) is a unique event key**; `hook-kills.log` carries the trial in its `tNc`
   tag but **has no timestamp column**, so it cannot order a read against an unlink on its own;
   and `markers.tsv` carries the hook's own markers — which `analyse_c14.sh`
   already used and this block did not. The hook-C witness is now bound to a **named** unlink by
   a window with two derived ends — round 17 put `W_pid_write[jNb]` below and the `tNc entry`
   marker above; **the lower end was itself invalid and is replaced in defect 11 below, and the
   upper end was the wrong instant and is replaced in defect 12**, which
   is why this entry's fix is not the last word on the figure —
   and the script prints the **union of distinct events** with the intersection **computed**, the
   **distinct trial count**, and each event's **rank among its own trial's unlinks** in place of
   the "first / second" claim. Over the committed traces every window holds exactly one unlink,
   the intersection is **0**, and **the figure is unchanged at 8 across 4 trials** — it is now
   derived rather than asserted. Where a window is ambiguous or a marker is missing the script
   **narrows**: the trial still counts, the event does not, and the shortfall is named. Both
   directions are exercised — see the demonstration in §1's validator list below.
10. **Row 21's denominator was never validated, only checked for emptiness — round 17.**
   `summarise.sh` rejected a `lock-owners.tsv` with no data rows and accepted **every other
   shape**, and `assemble.sh` copies the file into place without reading it either. So an
   interrupted run, or one that lost an entire protocol or scenario cell, would re-derive the
   advertised **1200-trial / 400-per-protocol** result over a **smaller or differently-weighted
   denominator** and still print a clean summary under the same headings — the same
   annotate-but-do-not-enforce shape round 15 closed for `VOID` rows, one level up at the shape
   of the matrix rather than the outcome of a cell. The expected matrix is now checked before
   **any** section prints, and it is **not derived from the file being validated** (which would
   make the check vacuous — a truncated file would derive a truncated expectation and pass
   itself). It is transcribed from `run_lock.sh`'s driver loop and each trial function's `emit`:
   3 protocols × (`S1` 3 `N` × 3 stalls, `S2` 1 `N` × 2 stalls, `S3` 1, `S4` 1, `S5` 4, `S6` 3)
   = **60 cells × 20 reps = 1200 rows, 400 per protocol**. Rep numbers are checked too, so two
   runs merged or one resumed over itself is caught even when the row count is right. `REPS` is
   deliberately a constant and not read from the data: a uniformly half-length run would
   otherwise derive `REPS=10` from itself and pass over 600 rows, which is precisely the failure
   this check exists to catch. `VOID` rows still count toward the matrix — a `VOID` trial was
   attempted and occupies its slot — so this and the `VOID` check stay orthogonal and neither is
   loosened. **The denominator is now printed above row 21/A rather than assumed.**
11. **The repair for defect 9 bound the hook-C witness with an invalid lower bound — round 21,
   and this is the THIRD revision of the same figure.** Defect 9 replaced an unjoined *sum* with
   a three-way join, and the join bound each hook-C witness to one unlink by the window
   `(W_pid_write[jNb], tNc entry)`. **`W_pid_write` is not a lower bound on anything in this
   arm.** In a player-published arm the parent stamps `W` immediately after `Popen` returns
   (`result=deferred_to_player`) while the wrapper is already running concurrently, so at
   `publish-delay-ms=0` the rename can complete *before* the parent reaches the `rec()` call.
   **This document already classifies that timestamp as synthetic — it is harness defect 4** —
   and the same block that withdrew a lag figure for it then reintroduced it as a bound one
   revision later. Measured on the committed traces, `W` trails its own `Popen` by
   **0.271–2.687 ms** (mean 0.941), and the publication instant may be anywhere in that gap.
   **The repair is not a better bound, because there is no observed publication instant to
   have.** Nothing marks the wrapper's `mv`; `P_popen` is stamped after the fork exactly as `W`
   is; and `player_start` is stamped after `exec`, so it may be *later* than the destruction
   rather than earlier and cannot bound it either. The event-level claim is now carried by a
   **uniqueness argument that needs no publication timestamp at all**: the record was certainly
   published before the player's own `player_start` (the wrapper `exec`s only on a successful
   rename, `[repo]`); hook C read nothing at a moment when that player was live, so it was
   destroyed before then; and in this arm the *only* thing that removes it is the reaper's
   `os.unlink`, which emits `record_unlinked` (`sweepmode=off`, and the probe's two other
   `os.unlink` sites remove `.pending` markers inside the pgid sweep, `[repo]`). So if
   **exactly one** `record_unlinked` lies between the b-job's spawn and hook C's read, that one
   did it — wherever inside the unobserved window publication actually fell. The interval was
   `(S2_prespawn_stat[jNb], tNc entry)` and **defect 12 moves its upper end to `tNc R`**; `S2` is
   emitted *before* the worker calls `Popen`, so
   it is strictly before the fork, directly observed, and deliberately the **loosest** valid
   lower bound, since widening can only add candidates and adding candidates can only make the
   check refuse. **Round 17's trial filter is also gone** — it discarded a delayed unlink from
   another trial landing in this interval, but such an unlink is a genuine candidate destroyer,
   so filtering it could name one unlink while a second was equally able to have done it.
   `W_pid_write` is no longer read by that block at all, in either witness.
   **THE FIGURE SURVIVES UNCHANGED AT 8 ACROSS 4** — output byte-identical to round 17's, ranks
   #1 and #2, intersection 0 — and that is the honest report rather than a fourth new total:
   what was wrong was the *argument*, and on this data the invalid bound happened to select the
   same events, because the nearest unlink to any `W` is **+41.258 ms** while the bound's whole
   uncertainty is at most **2.687 ms**. Latent, exactly as defect 7 was, and it would have
   misnamed on a re-run at a different `publish-delay-ms`. Both directions are demonstrated: a
   second unlink injected into trial 1's interval drops the named events to **3** and reports
   the narrowing while the trial still counts, and removing that trial's `S2` row leaves it
   unjoinable at **7**.
12. **The live-player witness was checked at the wrong instant — round 24, and this is the
   FOURTH revision of the same figure.** Both `analyse_round2.sh` and `analyse_c14.sh` tested
   whether the trial's b-player was live at the hook's **`entry`** marker. `entry` is stamped as
   the hook's *first* act. The `nopid` observation happens **later** — after the `K` marker and
   then the record scan — so a player that exited in between satisfied
   `player_start ≤ entry < player_end` and was still counted as live at an observation it was not
   alive for. On that input the block reports a destruction, or *"found NOTHING while playing"*,
   with **no player live at the scan**: a false positive in the witness whose entire content is
   an absence. The instant of the scan is not observed, so the repair does not move the test to a
   better instant — it requires liveness **across the whole interval that contains the scan**,
   using two markers that were in every committed `markers.tsv` all along: `K` is stamped
   immediately before the scan and `R` after the `HOOK_GAP_S` sleep that follows it, so the scan
   lies strictly inside `(K, R)` and the predicate is `player_start ≤ K` **and**
   `player_end > R`. `R` over-requires by the ~90 ms hook sleep, and that is the safe direction.
   **The uniqueness interval's upper end moves the same way, from `tNc entry` to `tNc R`** —
   the destroying unlink must precede the *scan*, and widening can only add candidates and so can
   only make the check refuse. **`reached`/`sent` rows take no across-the-scan check, and that is
   not an exemption but the opposite finding**: the hook's kill is what *ends* the player, so a
   reached player cannot outlive `R` (measured here, over all **20** reached hook-C rows in the
   two arms: it exits **0.6–2.0 ms** after `K`, i.e.
   **113.2–140.4 ms** before `R`), and requiring it to would have destroyed every `reached` count in
   the document. For those rows the signal is the evidence, and `analyse_c14.sh` now checks it as
   such instead of asserting it: the kill's target must **be** that trial's own b-player and that
   player must have been live at `K`. **THE FIGURE SURVIVES UNCHANGED AT 8 ACROSS 4, AND SO DO
   4 OF 12 AND 12 OF 12** — verified, not assumed: all four blind trials remain live
   **1519.8–1562.6 ms past `R`**, every widened interval still holds exactly one unlink, and all
   **20** reached rows join to their own trial's b-player, live at `K`. So the derivation is
   strengthened and no number moves.
   Both directions are demonstrated: moving one blind trial's `player_end` into `(K, R)` — a
   player that the *old* predicate accepts and the new one rejects — drops `analyse_c14.sh` to
   **3 of 12** and `analyse_round2.sh`'s witness (b) to **3 trials / 7 union events**, each
   naming the trial and why; retargeting one `sent` row away from its b-player drops the reached
   count to **7**; deleting one `tNc R` marker reports the trial as missing its interval rather
   than as live; and injecting a second unlink into the *widened* part of trial 1's interval
   (after `entry`, before `R`) makes that unlink unnameable, which also proves the interval
   really did widen. **One further unproven claim was removed rather than repaired**: the hook-read
   tally block printed *"hook C read NO record on 4 of 12 trials while a live player was there to
   preempt"* while reading only `hook-kills.log`, which carries no timestamps and so cannot
   support any liveness claim at all. It now says the count, says it cannot settle liveness, and
   points at witness (b), which can.

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

**And eight validators that accepted a PARTIAL or STALE run as a pass — four in round 15 and four
in round 16, the same shape as every guard defect above, one level further out.** Each of these
decides whether a *fresh* run may be published; none of them changes a committed number, and the
committed evidence passes all eight unchanged. They are listed because the whole claim of this
branch is that the committed rig is the one the traces came from, and a validator that cannot tell
a complete run from a partial one is what makes that claim unfalsifiable.

- **`run_lock.sh` proved only that ONE racer finished.** `count_owners` accepted any log in which
  *some* process recorded a terminal outcome. `wait` returns when the last background job exits,
  not when they all succeeded, so a racer whose interpreter never started, or that died
  mid-election, was invisible: the survivors still recorded their outcomes, one still recorded
  `owner`, and a race that never ran at its stated width scored **owners=1, a clean pass**. It
  bites hardest exactly where the evidence is thinnest — the N=16 `S5` cells, where fifteen of
  sixteen racers could be absent. The check is now per-participant and exact: the expected number
  of processes must each record **exactly one** terminal outcome. Verified against every committed
  lock sample log, including the two-owner failures, so it softens no published result.
  **It required a change in the PRODUCER too**, and the coupling is the point: `elect_current()`
  could return on `rmdir_failed` having recorded **no** terminal outcome at all, so a racer that
  legitimately abandoned the election was indistinguishable from one that never ran. Validating
  participation without that fix would have `VOID`ed correct trials.
- **`collect.sh` accepted any non-zero number of reconstructed trials.** It checked only for
  *zero* rows, and zero is the shape this defect almost never takes. A run missing one worker
  claim still writes every hook-side marker, so `verify_fires.sh`'s entry/K/Rdone counts stay
  complete while `collect.sh` reconstructs eleven trials out of twelve, exits 0, and the caller
  appends eleven rows to the published evidence — **the denominator shrinks and nothing says so**.
  It now compares the row count against the `t<N>a.entry` marker count, which is independent of
  the worker: every trial fires exactly one `a` hook before anything else happens. The identity
  holds on all 21 committed configurations, 12 = 12 on each.
- **`summarise.sh` annotated `VOID` and exited 0.** Its own comment already said *"a run with any
  VOID is not a complete run"*, and then printed the annotation and returned success — so a fresh
  run whose staging failed on some cells could be consumed as a successful full re-derivation over
  a quietly smaller denominator. It now fails, naming the voided cells. The committed evidence has
  no `VOID` rows and still exits 0.
- **`publish.sh` merged a new rig over a stale one.** Every source file except the manifest was
  optional, the destination was never cleared, and there was no `set -e` — so a missing
  `speakd_probe.py` was skipped in silence while the branch's older copy of that same name
  survived and was reported by the closing `ls`. **A rig that is part new code and part stale
  code, reported as a success**, on the script that hands the rig to the branch. It now requires
  the runtime file set, stages into a fresh temporary directory, and swaps that into place, so a
  failure leaves the existing rig exactly as it was rather than half-replaced.

**And four more in round 16 — three of them in code round 15 had just written, and one of which
would have destroyed the committed evidence outright.** Each is demonstrated in both directions:
refusing the bad input, and still accepting the committed one.

- **`publish.sh`'s rollback deleted the evidence it existed to protect.** The "swap it into
  place" repair above `mv`'d `traces/` **out of** the live destination and into staging before
  the swap. So on a failed `mv "$STAGE" "$DEST"` the rollback restored `$OLD` — a directory
  whose traces had already been taken out of it — and the `EXIT` trap then `rm -rf`'d `$STAGE`,
  which by then held **the only copy**. The one path written to leave the original intact was
  the one path that destroyed it. Executed against a forced swap failure with the round-15
  script, all **114** committed trace files were gone and the destination was left with none.
  It is now a `cp -Rp`, verified by entry count before anything irreversible happens, so the
  original stays whole until the swap has succeeded; the same forced failure now leaves the
  destination byte-identical, and a failed rollback names the recoverable path instead of
  exiting silently. A successful publish is unchanged.
- **`publish.sh`'s required-file set omitted the scripts that build four of the committed
  evidence files.** Its own stated criterion is *"the files without which the published rig
  cannot produce evidence or re-derive a figure"*, and `collect_real.sh` — the only producer of
  [`real-audio-trials.tsv`](real-audio-trials.tsv), without which `summarise.sh` **fails** its
  whole re-derivation — was not in it. Nor were `assemble.sh` (which builds
  `preemption-trials.tsv` and `lock-owners.tsv`, and is the only caller of `verify_fires.sh` on
  the publishing path), `assemble_pass1.sh` (`preemption-trials-replication.tsv`),
  `run_real.sh`, `compare_passes.sh` or `analyse_c14.sh` — the last two named by this document
  as derivations. A rig missing any of them published successfully and could then not rebuild
  the file the document points at. The list is now closed under *every committed TSV has the
  script that builds it, and every derivation this document cites is present*.
- **`verify_fires.sh` was a SUBSET check wearing the name of a completeness check.** It verified
  that every expected configuration **appeared**; it never required each to appear **once**.
  `run_c10.sh`, `run_c16.sh` and `run_tail.sh` all append to `RUNS.txt` (`>> "$OUT/RUNS.txt"`)
  and only `run_pgid_rerun.sh` filters the old line out first — so re-running one configuration
  to fix it leaves **two** lines naming it, both pointing at run directories that exist. Every
  name is still present, so the guard said *"all hooks fired"*; `assemble.sh` then walked the
  same `RUNS.txt` and appended that configuration's twelve rows **twice**, and the **312**-trial
  denominator this document quotes would silently have become **324**. The check is now
  seen-set **equals** manifest exactly: duplicates and unexpected names are both refused, by
  name. **The five-`MISSING` refusal over the committed `traces/` is unchanged and
  byte-identical** — that gap is real and the fix for it is a re-run, not a looser guard.
- **`assemble_pass1.sh` pinned ONE configuration to ONE historical timestamp.** `C3_adversarial`
  was matched as the literal `"$O"/C3_adversarial-1787683326` while every other configuration
  used a `-*` glob. Point `OUT=` at any other valid pass-1 tree and that literal matches nothing,
  `[[ -d "$d" ]] || continue` skips it in silence, and the replication arm is published with
  **ten** configurations. The closing guard could not see it: it asked whether the **aggregate**
  had at least one row, and ten configurations' worth of rows is plenty — a per-configuration
  shortfall is invisible to an aggregate test, which is the same defect the `verify_fires.sh`
  manifest exists to fix, one script over. Executed against a synthetic pass-1 tree whose `C3`
  carries a different timestamp, the round-15 script exits **0** having published 10 of 11
  configurations and 120 of 132 rows. Every configuration is now globbed and every one must
  match **exactly one** run directory — not zero, and not two either, since a tree holding two
  runs of one configuration is an ambiguity the script must not resolve by picking. The
  historical timestamp survives as an explicit override (`PASS1_C3_adversarial=…`) rather than
  as a hidden default.

**And one more in round 17, in the script that publishes row 21's denominator.** Same rule: it is
demonstrated refusing bad input *and* accepting the committed evidence unchanged.

- **`summarise.sh` validated that `lock-owners.tsv` was non-empty and nothing else.** See §1
  derivation defect 10 for what the check now is. Executed against the committed file it exits
  **0** and prints `row-21 matrix: 3 protocols x 6 scenarios = 60 cells x 20 reps = 1200 trials
  (found 1200 rows)` above row 21/A, with `current` **400 / 30.2%**, `spec` **400 / 15.2%** and
  `proposed` **400 / 0.0%** byte-identical to before. Against five bad shapes it exits **2**
  before printing a single line of stdout, naming the cells: a run **truncated** at 1063 rows
  (six missing cells and one short one, all named); a whole **protocol × scenario cell** removed
  (`spec`/`S5_scratch`, 1120 rows); a **re-run appended** (1220 rows — caught both as a long cell
  and as twenty repeated rep numbers); a file with **exactly 1200 rows** where one cell was
  robbed to pay another, which a row count alone can never see; and a **stall value the design
  never emits**, caught as three missing cells *and* three not-in-design cells. The sixth case is
  the check failing **closed**: the first draft of it put a literal newline in an `awk -v`
  assignment, which BWK awk — `/usr/bin/awk` on the platform every trace here was taken on —
  rejects with *"newline in string"* and **no output at all**, and an empty report reads as *"no
  defects found"*. It passed the committed evidence **by failing to run**. The `=`-line the
  reporter emits unconditionally is now mandatory, so a check that cannot run refuses instead of
  agreeing.

**And two in round 21, both created by round 21's own protocol change, and both found by asking
what would consume the new evidence it produces.** The identity test at §4b(i) makes the hook and
the sweep emit a new kind of row — `record_skipped … verdict=recycled|unverifiable` — and three
existing parsers were about to swallow it.

- **Three `hook-kills.log` parsers extracted `result=` without checking the row's KIND.** Each
  did a blind `sub(/^.*result=/, "", r)`, and a `record_skipped` row has no `result=` field at
  all, so the substitution failed to match and left **the whole tag** in `r`. Nothing crashed and
  no total moved; the row was simply filed under a bucket named after its own tag and vanished
  from every denominator — the defect this document has now found nine times, arriving through a
  door round 21 had just installed. Worse in the `C14a` witness: `HC[trial]` was set to the tag,
  which is neither `nopid` nor `sent`, so the trial **fell out of witness (b) in silence** — and a
  skipped record means the *opposite* of `nopid`, since the hook found a record and refused it.
  All three now test the event column first, and a skipped or unrecognised row is **counted and
  reported**. Demonstrated in both directions: over the committed traces the output is unchanged
  but for one added `skipped_on_identity=0` field (no such row exists, so no `NOTE` prints); with
  one trial's hook-C row rewritten as a `record_skipped`, the note prints, the denominator drops
  to **4 of 11**, and that trial is **named** — *"hook C refused every record it found on identity
  grounds"* — instead of disappearing; and an unrecognised row kind is reported as one.
- **`collect.sh` folded the new row into the same flat `K[tag.field]` map.** A per-player hook can
  kill one record and skip another in a single invocation, so a `record_skipped` row's `target=`
  could **overwrite the target the hook actually killed** in that trial's `hook_b_target` column.
  Only `kill_attempt` may write those columns now. The `trials.tsv` schema is deliberately
  **unchanged** — adding a column would break every consumer — so skipped rows are counted and
  named on stderr instead, where this script's other completeness complaints already go.

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
derivations. **They are disjoint, both are required, and neither is a check on the other. Where
the line falls, stated rather than left to inference:** the aggregate TSVs hold **one row per
trial**, so `summarise.sh` covers per-trial quantities — the attribution table, the audibility
intervals, the window widths, the owner counts. Figures that are counts of trace **events**
(`record_unlinked`, `pending_found`/`pending_created`, the sweep-skip records) are in **no TSV
column at all**, so `C14a`'s **8 destructions across 4 trials** and the `C15c`/`C16` 25-election
`killpg`-used/skipped counts come only from `analyse_round2.sh`. Round 16 found `summarise.sh`'s
own header claiming the whole set (§1 derivation defect 8). (Round 3 wrote "from the committed TSVs" for both; `analyse_round2.sh` takes the
trace directory, and pointing it at the TSVs prints `(trace missing)` for every block — and,
since round 12, **exits 2** instead of reporting a successful analysis that derived nothing.)
`verify_fires.sh` is the check that every hook fired, and over the committed `traces/` it
**fails** — see below; that is a real gap in the evidence set, not a formality. **And until
round 5 it could not run from the repository at all, while reporting that it had.** It read a
`RUNS.txt` that exists only in a live run tree; pointed at the committed `traces/`, it iterated
over nothing and printed *"all hooks fired"*. **A null reported as a pass, by the one script
whose entire purpose is to stop a null being read as a pass** — the same shape as harness
defect 1, in the guard against it. It now also
reads the committed `<cfg>.markers.tsv` files and exits 2 rather than succeeding over zero inputs.
**Run against `traces/` it does not pass, and this document said it did.** Round 10 added a
completeness manifest, `expected-configs.txt`, so that a *partial* evidence set could not read as
confirmation either; the manifest lists the **26** configurations reported here and `traces/` holds
**21** marker files. So `verify_fires.sh traces 12` prints 21 `OK` lines, then five `MISSING`
diagnostics — **`C1_prespawn`, `C2_hookside`, `C5_norecheck`, `C6_handle`, `C7_noreap`** — and
exits **2**. The guard is doing its job; the sentence that read *"reports 21 configurations OK"*
predates the manifest and was never updated, which left this document asserting a pass its own
tool refuses to give. **The committed evidence set does not pass its own completeness check.**
What is absent for those five is the **hook-fired marker evidence**, not the measurements: their
twelve trial rows each are in `preemption-trials.tsv`, and every figure derived from them
re-derives exactly as before. What it puts in doubt is narrow and specific — for those five, and
only those five, a hook that never fired cannot be distinguished from one that fired and measured
nothing, so any **zero** they contribute is unconfirmed. It puts nothing in doubt about the other
21, whose counts stop being an assertion at 25 entry markers per configuration — one warm-up plus
two per trial, **except `C14a` and `C14b`, which fire a third hook per trial to observe the
TOCTOU's consequence and therefore want `1 + 3N = 37`; `verify_fires.sh` special-cases them and
their committed `markers.tsv` files carry 37 entries each**.

`analyse_c14.sh` is a third derivation, over the `C14` traces; **it has been corrected twice**.
Round 3 found it had tested only that a player's END record existed, which every completed player
satisfies, instead of that the player was live at hook C, and replaced that with
`start ≤ tNc entry < end`. **Round 24 found that `entry` is the wrong instant** (§1 derivation
defect 12): it is the hook's first act, while the `nopid` read happens after `K` and the record
scan, so a player that exited in between still passed. The blind rows now require liveness
**across** the interval that contains the scan — `start ≤ K` and `end > R` — and the reached rows
are joined to their own trial's b-player by the kill itself, which is stronger evidence and the
only kind available, since the hook's kill is what ends that player. Under both corrections the
published figures are unchanged, **4 of 12 and 0 of 12**, with the blind trials live
**1519.8–1562.6 ms past `R`** and all 20 reached rows joined to their own trial's b-player. Unlike the residency run's `[rig]`, **this probe is in the repository**, so its
protocol can be read as well as its output.

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
   fork and the wrapper removes it once its record is published — **not as its first act,
   which PR #27's clause 7(i) shows is unsatisfiable**: the wrapper must obtain its pid and
   start time, write them as the record's content and `rename(2)` it into place, so a marker
   removed before all three is removed *inside* the window it bounds. Removing it after
   publication is what makes *"an unnamed player may exist"* observable and confines `killpg`
   to that window. Measured: `C16a` (sweep before
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
  record at all on 4 of 12 trials**, and on those 4 the b-player was live **across the whole
  record scan** — `player_start ≤ tNc K` and `player_end > tNc R`, with 1519.8–1562.6 ms to spare
  past `R`. (Round 3 checked `entry` instead, which is the instant the hook *started* rather than the
  instant it *looked*; §1 derivation defect 12.) On the other 8 the kill reached that trial's own
  b-player, which is what makes those reads reads of a live player rather than of nothing.
  Nothing else in this arm unlinks, so on those 4 the record was published and then destroyed.

Those two sets are **8 distinct unlinks falling in the same 4 trials** — the trial's first unlink
caught by the hook, its second by the player log. **Until round 17 that sentence was an assertion
and not a derivation** (§1 derivation defect 9): the script added two *global* counters that
shared no key, so nothing established that the witnesses saw different unlinks or that they fell
in the same trials. It is now a three-way join — the unlink's own `job=jNa|jNb` field gives its
trial and `$1` its timestamp; `markers.tsv`'s `tNc K` and `tNc R` bracket the scan, which is the
column `hook-kills.log` lacks — and the hook-C witness is bound to **one** unlink.
**Round 17 bound it with the window `(W_pid_write[jNb], tNc entry)`, and round 21 found that
lower end invalid** (§1 derivation defect 11): `W` is the *parent's* deferral stamp, taken after
`Popen` returns while the wrapper is already running, so publication may precede it — harness
defect 4, reintroduced as a bound by the very block that had withdrawn a lag figure for it.
There is no observed publication instant in these traces to put there instead, so the binding no
longer rests on one. It rests on **uniqueness**: the record was certainly published before the
player's own `player_start` (the wrapper `exec`s only on a successful rename), hook C read
nothing while that player was live **across the whole scan**, and the reaper's `os.unlink` is the
only thing in this arm that removes a record — so if **exactly one** `record_unlinked` lies
between the b-job's spawn and the scan, that one destroyed it, wherever in the unobserved window
publication fell. The interval is `(S2_prespawn_stat[jNb], tNc R)`, whose lower end is emitted
*before* the worker calls `Popen` and is therefore strictly before the fork, and whose upper end
**round 24 moved out from `tNc entry`** (§1 derivation defect 12) because the scan can have
happened anywhere up to `R`; the trial filter is gone, because an
unlink from another trial landing in the interval is a genuine candidate and excluding it could
name one unlink while a second was equally able. On the committed traces every such interval
holds **exactly one** unlink, the two witness sets **intersect in 0 events**, and the ranks come
out **#1 for every hook-C event and #2 for every player-log event** within their own trial. **The
figure is unchanged at 8 across 4 through all three repairs; what changed is that the script now
derives it, and derives it from something true, at the right instant.** Of the **16** remaining, **8 are positively
shown NOT to be destructions**: hook C read the *newer* player's pid, so that trial's first
unlink removed the older player's **own** record and the newer one had not published yet. The
last **8** are simply undetermined — the unlink falls inside the newer player's unobserved
`Popen`→publish→`exec` gap and nothing in the traces resolves it. So the honest statement is
**4 of 12 trials, 8 proven destructions** — a real defect at a third of the rate round 3
published, found because the count and the lag shared one bad timestamp.

**The design conclusion is unchanged, and it is the control that carries it.** With per-player
records (`C14b`, identical timing) every one of **37** unlinks removed only its own name, **0 of
another player's**, and the third hook reached the live player **12 of 12** — each of those 12
joined to that trial's own b-player, live at `K` and killed 0.6–2.0 ms later — against `C14a`'s
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
| **S1** | `init` | the winner is stalled between `mkdir` and its pid write by 0 / 5 / 50 ms. The window clause (a) exists for. N = 2, 4, 8. **At 0 ms the window is zero-width and the cell is a who-wins check instead — §3.3** |
| **S2** | `longstall` | the same, stalled **200 ms and 1000 ms** — longer than clause (a)'s own backoff. **Review finding 1** |
| **S3** | `aba` | a lock owned by an already-exited pid, so reclamation is legitimate. Reclaimer A acts at once; reclaimer B classified stale at the same instant but is **held on a release barrier until A's reclaim is in the log** before acting, so it acts on a stale observation. Round 24 replaced the 120 ms hold that stood here, which proved only that B had observed — never that A had reclaimed (§3.3). **Review finding 2** |
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
| S1, stall 0 ms ‡ | 1 (60/60) | 1 (60/60) | **1 (60/60)** |
| S1, stall 5 ms | 1 (60/60) | 1 (60/60) | **1 (60/60)** |
| S1, stall 50 ms | **2 (58/60), 3 (2/60)** | 1 (60/60) | **1 (60/60)** |
| S2, stall 200 ms | **2 (20/20)** | **2 (18/20), 3 (2/20)** | **1 (20/20)** |
| S2, stall 1000 ms | **2 (20/20)** | **2 (19/20), 3 (1/20)** | **1 (20/20)** |
| S3, ABA | **2 (20/20)** | **2 (20/20)** | **1 (20/20)** |
| S4, dual reclaim | 1 (20/20) | 1 (20/20) | **1 (20/20)** |
| S5, who-wins | 1 (80/80) | 1 (80/80) | **1 (80/80)** |
| S6, dead + N racers | 1 (59/60), **2 (1/60)** | 1 (59/60), **2 (1/60)** | **1 (60/60)** |

‡ **The stall-0 row is not a window test.** At `--stall-ms 0` the window a racer's election read
would have to fall inside is zero-width, so the row is a live-owner / who-wins check whichever
protocol runs it. Its 180 trials are counted in the totals below because they are real trials
with real outcomes; they are **not** evidence about clause (a). §3.3 sets out why, and why the
row is kept rather than dropped.

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
improvement over `current`, which fails 60 of those same 180. **Read 120/180, not 180/180:** the
stall-0 sixty are a zero-width window and test nothing about clause (a), for the reason set out
below. At **200 ms and 1000 ms it fails 40 out of 40.** This is **review finding 1, measured**:
the clause replaces "a lock with no
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
fails the trial if it never appears — **and round 24 found that this was still not enough, which
is the sixth staging repair to this one file.** Waiting for `classified_stale` proves that B
**observed** a dead generation. It does not prove that A **reclaimed** before B's 120 ms classify
stall expired: A is a fresh Python interpreter, and if it starts slowly or is descheduled past
120 ms then B reclaims first and A merely loses — `owners=1`, the same silent false pass this
whole paragraph is about, arrived at through the *other* clock in the same function. The clock is
now replaced by an explicit **release barrier**, deliberately the same two-phase file-token shape
the S1/S2 barrier ended up with rather than a seventh mechanism: B parks after recording
`classified_stale`; A drops a `GO` token **only after its own election has returned a successful
reclaim**; B is released and then commits the ABA act. Either side failing records its own marker
— `classify_hold_timeout` when B waits out the guard, `classify_hold_norelease` when A's election
ends with nothing to release — and both make the trial `VOID`, which `summarise.sh` excludes from
the numerator and the denominator alike. A log carrying *neither* marker and *no* barrier records
is also `VOID`, because "the barrier did not fail" and "the barrier ran" are different statements
and only the second one stages anything. **All of that change is UNRUN**, and the committed
`lock-owners.tsv` predates every staging fix in this file including this one. To close: re-run S3
under the corrected harness. **Six rounds have each found a clock in the previous round's repair
of this function**, so the honest reading is that inspection is not converging on it and only the
re-run will settle it.

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
claiming until `N` such acknowledgements appear.

**And that was still only half a barrier — the name was aspirational for two revisions.**
A racer that acknowledges and then walks straight into its protocol lets the **first**
racer reclaim or replace the pid-less lock before racers 2..N ever look at it, so an
N-racer cell was still race-dependent no matter how well the winner was staged. The
second phase is now real: the winner writes a **`GO` token** once it has collected all
`N` acknowledgements, and every racer waits for that token before electing. So the
ordering is: winner claims → each racer observes the window and acknowledges → winner
releases all of them at once → winner applies the stall and writes its pid. The window is
therefore established by *ordering* rather than by out-running an interpreter start, and
no racer can destroy the state another racer was staged to observe.
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

**And the barrier stages the *observation*, not the *election read*.** `ack_barrier()` proves
that a racer once saw the pid-less lock, and then holds it on the `GO` token — but `GO` releases
the **winner** too. The winner applies its stall and writes its pid while each racer, released by
the same token, starts its protocol and performs a **second, independent read**, and it is that
second read which decides the trial. Nothing orders the two. So a clean 0 ms or 5 ms cell can
still be an ordinary live-owner check — the same false-clean, one level further down, that each
of the four previous repairs believed it had closed.

**The repair this time is detection, not a sixth staging mechanism.** Every election read now
reports what it saw — `election_read … saw_window=yes|no` — together with the **inode** of the
lock directory it read, and the winner records the inode it created. A racer's read counts as
having entered the staged window only if it saw no pid **and** read the winner's own inode: under
`current` a racer that reclaims first leaves *its own* lock pid-less for an instant, and a bare
"I saw no pid" would score that as staging. `run_lock.sh` emits `VOID` for any S1/S2 trial in
which no racer's deciding read entered the winner's window, and `summarise.sh` already keeps
`VOID` out of both numerator and denominator. That turns *"we hope it was staged"* into *"we can
tell, and we discard it when it was not"* — which is the shape this harness should have had four
repairs ago. **[inferred]**, on the same committed `lock-owners.tsv`, which predates it exactly as
it predates every staging change above; the closing condition is the same re-run. `proposed` is
exempt from the rule because it has no pid-less state for a read to enter, not because its staging
is trusted — S1/S2 are structurally vacuous for it either way, and its election read records
`saw_window=n/a` and says why.

**The 0 ms cell is not a window test at all, and this document counted it as one.** At
`--stall-ms 0` the winner writes its pid *immediately* after releasing the barrier, so the
interval a racer's election read would have to fall inside is **zero-width**. No staging can place
a read inside a zero-width interval; a read that lands there does so by chance, not by
construction. So S1 at stall 0 — 60 trials per protocol, 180 of the trials in the table above —
is a **live-owner / who-wins check**. All three protocols being clean there says only that none
of them misclassifies a winner whose pid is already on disk, which was never in dispute and is
not what clause (a) is about. **`spec`'s "clean to a 50 ms stall, 180/180" is therefore 120 trials
of window evidence and 60 trials of something else**, and `current`'s 120 clean trials in the same
band become 60 on the same subtraction. The cell is kept rather than deleted, because the `VOID`
rule now *demonstrates* that instead of the document asserting it: on the re-run, expect the
stall-0 rows to be largely `VOID`, and read whatever survives as a self-selected sample rather
than a swept one.

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
who-wins race and exactly 1 of the 100 reclamation trials is confirmed by a committed per-trial
trace to have exercised reclamation of a dead owner** — `lock-S3_aba-proposed-r1.tsv`, where both
racers classify the incumbent `pid_dead` and one supersedes it. The other 99 are unconfirmed
because their staging was a clock and no per-trial trace was kept, which is not the same claim as
never having happened. That is not
evidence `proposed` fails — no trial produced a wrong number, and no *failure* anywhere in the
table is in doubt, since mis-staging can only hide failures, never invent them. It is a statement
that **the mechanism `proposed` exists to provide has been shown to run once, in the one trial
whose trace was kept, and is unconfirmed on the other 99.** The
harness is now correct on all three scenarios; the committed `lock-owners.tsv` predates every one
of those fixes. Re-running S3, S4 and S6 under the synchronised driver is an open item, carried
in §13 row 21.

**And every round of review since has found a defect in the previous round's repair of this
harness — until round 15, always in the staging rather than in the design.** That qualifier is
new and it matters: **round 15 found a defect in §4b itself**, not in the staging — the
`.pending` marker validates no owner identity, so clause 7(iv)'s bound was still not the bound
it claimed (§5, defect 4 of 7). §4a and §4b were stable for seven rounds and are not stable now
— **and round 16 found the fifth defect in that same bound, this time inside round 15's repair
of it**: the identity check keyed on the record's shape as well as on the option, so a bare or
legacy record switched it off under an option that said it was on (§5, defect 5 of 7). Round 21
found the sixth, in the election half of that same repair, and round 24 the seventh, in the `ps`
reader both halves share.
The S1/S2 staging has its own separate record: it has been wrong **five times, in five different
ways** — a flat 4 ms sleep; then a one-way wait on the winner's own claim record; then an
acknowledgement written *before* the protocol read; then an acknowledgement with no release, so
the first racer could destroy the state the others were staged to observe; and now a release that
stages the **observation** and leaves the **election read** unstaged. **Four of the five were
introduced by the repair to the one before it.** The incumbent staging in S3, S4 and S6 has its
own lineage — a 4 ms sleep, then a fixed `sleep 0.05` that three consecutive repairs walked past,
and then, found in round 24, **the 120 ms classify stall that had been in `trial_aba` all along**:
waiting for B's `classified_stale` proved B had observed a dead generation and never that A had
reclaimed, so a slow A still produced the false `owners=1` (§3.3). It is now a release barrier
gated on A's own reclaim record, reusing the S1/S2 barrier's shape rather than adding a seventh.
**The honest conclusion is that inspection is not converging on this harness, and no further
reading of it should be trusted to settle the lock evidence** — which is why the answer in these
rounds is a detector that VOIDs an unstaged trial, rather than another mechanism asserting that
staging can no longer go wrong.
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
> from an absent one.** `symlink(f"{os.getpid()}.{starttime}", speak/worker.lock.<gen>)`.
>
> - **`symlink(2)` creates the object and its content in one step, and fails `EEXIST` if
>   the path exists.** So there is no interval in which a lock exists without an owner, and
>   the question clause (a) used to answer — *what does a pid-less lock mean* — does not
>   arise. A `mkdir` followed by a write cannot have this property, because it is two steps.
> - **The record's CONTENT is `<pid>.<starttime>`, not a bare pid, and that is what makes it
>   an IDENTITY rather than a number. Unified with PR #27's §10.5 clause 2 in round 15;
>   the two documents now describe one scheme rather than two.** A pid is reused. A worker
>   that died and whose pid the OS has since handed to an unrelated process reads as **live**
>   to `kill(pid, 0)`, so every candidate loses the election to a stranger and jobs sit
>   unconsumed. **It costs nothing structurally:** a symlink's target is an arbitrary string,
>   so two fields instead of one changes no primitive, no atomicity argument and no failure
>   mode. The `.` separator is safe because a Darwin pid is decimal digits only and the start
>   time is appended, never prepended — a reader splits on the **first** dot.
> - **Liveness is decided by re-reading the recorded pid's CURRENT start time, on a complete
>   record.** `ps -o lstart= -p <pid>` prints the start time and exits 1 with no output when
>   there is no such process, so **one call is both the existence test and the identity test**
>   — verified on this machine (`ps -o lstart= -p 1` → `Mon Aug 10 01:20:30 2026`; an absent
>   pid → empty, exit 1) **[measured-here]**. No backoff, no timeout, nothing for a
>   descheduled or `SIGSTOP`ped winner to defeat. **This is the repair for review finding 1:**
>   a fixed backoff is a bet that a live process will make progress inside it, and an election
>   must not make that bet. The old clause (a) narrowed the window from microseconds to tens
>   of milliseconds; it did not close it, and a stalled winner walks straight through it —
>   measured. **The identity half is `[inferred]`:** `lockrace.py`'s three protocols all
>   decide liveness with `kill(pid, 0)`, so **none of the 400 `proposed` trials exercised a
>   start-time comparison**, and the granularity of `ps -o lstart=` is one second, which is
>   the honest limit of the repair. To close: the pid-space-wrap drive §5 names, plus one
>   election against a hand-written record naming a recycled pid.
>   **`lockrace.py` was deliberately NOT changed to publish the two-field record**, and the
>   reason is the same discipline the rest of this section applies to itself: the committed
>   400/400 belongs to the protocol that produced it, and silently editing that protocol in the
>   rig would leave the document quoting a result for a protocol no longer in the repository.
>   The change belongs with the re-run, not before it. `speakd_probe.py` DOES publish it
>   (`--owner-identity`, default on), because row 20's `killpg` is the site where a bare pid is
>   dangerous rather than merely wrong — see §4b(iv) and §5.
> - **A record that carries NO start time is UNVERIFIABLE, and an implementation must not
>   let it degrade to the pid test.** This is a migration clause and it is normative, because
>   the population of bare records is not hypothetical: every record written before this clause
>   existed is one, and so is every record written by an implementation that has the identity
>   check switched off. **Round 16 found the probe getting exactly this wrong**, in the code
>   round 15 added to fix it: `owner_identity()` guarded on `if option == "off" or st is None`,
>   so a bare record turned the check off **whatever the option said**. A recycled pid then
>   read as `same` and clause 7(iv) `killpg`'d a stranger's group — reachable from the one
>   input the falsification arm itself produces. The rule the clause states, and the probe now
>   implements, is that **the degradation keys on the OPTION and never on the record's shape**:
>   with the check on, a bare record yields a fourth verdict, and each consumer decides for
>   its own site. 7(iv) refuses to signal and leaves the marker standing.
>   **Round 24 adds a FIFTH verdict, `lookup_failed`, and it is a different fact from this one.**
>   A bare record is unverifiable *forever*; a failed `ps` is unverifiable *at this instant*. Both
>   are refused by every signaller, but the election must not treat them alike: for the bare record
>   it decides terminally on `kill(pid, 0)` because no better evidence will ever exist, while for a
>   failed lookup it **retries a bounded number of times and then loses**. Falling back to
>   `kill(pid, 0)` there would re-admit pid existence as an election input under an option that
>   says it is off — round 16's hole with a *transient failure* in place of a record shape as the
>   thing that silently decides whether the check happened. **The cost of losing is a worker that
>   does not start**, bounded by the retry budget, by the fact that a machine which cannot fork
>   `ps` could not have forked a player either, and by the refusal being recorded per attempt.
>   - **What the ELECTION does with it — replaced in round 21, because round 16's rule was
>     unsafe and its stated reason was false.** Round 16 said: supersede freely, *"since the
>     only destructive consequence of superseding is the pgid sweep, and the sweep refuses
>     this verdict on its own"*. **Superseding is not merely a licence to signal — it is the
>     licence to consume jobs.** A bare record may belong to a **live legacy worker**, and
>     nothing in the record says otherwise; supersede it and it goes on claiming from
>     `speak/job` and spawning players while the new owner does the same at `gen+1`. That is
>     **two owners and overlapping audio** — the one invariant this whole document exists to
>     hold — and the sweep declining to `killpg` does nothing about it, being a different act
>     against a different victim.
>   - **And superseding cannot be turned into a drain.** Nothing in this protocol observes
>     being superseded: the owner reads the lock once, at its own election, and never again.
>     So creating `gen+1` tells the incumbent nothing — and **no notice can be added that a
>     legacy worker would see, because a legacy worker is by definition one that predates any
>     notice we could add**. Announce-and-drain is unavailable in principle here, not merely
>     unimplemented. This is why the clause needs a policy rather than a mechanism.
>   - **The policy: SPLIT ON WHETHER THE PID IS STILL HELD.** The record cannot separate a
>     live legacy owner from a recycled pid — but `kill(pid, 0)` separates both of those from
>     a pid that names nothing, and a live legacy owner necessarily holds its pid.
>     - **pid VACANT → SUPERSEDE.** No process holds the number, so there is no live worker to
>       double up with, whoever wrote the record. This is the case round 16's liveness
>       argument was actually about, and it is the ordinary one: a stale bare record is
>       usually lying around because its worker died.
>     - **pid HELD → REFUSE.** Live legacy owner or recycled stranger, indistinguishable, and
>       the two demand opposite acts. Lose the election and consume nothing.
>   - **What refusing costs, stated rather than buried.** If the pid was in fact recycled, the
>     session **wedges**: no worker wins, no job is claimed, nothing is spoken, for as long as
>     some unrelated process holds that number. Three things bound it, and none of them makes
>     it free. (1) It is a **liveness** failure, and silence is the failure mode this document
>     accepts everywhere else; two owners is a **safety** failure, and audible. (2) It is
>     confined to **one session** — these records live under `$BUF_ROOT/<session_id>/speak/`,
>     so a wedged session cannot wedge the next, and an operator clears it by removing that
>     directory. (3) It is **loud**: every election records the refusal by pid, so a wedge is
>     diagnosable rather than a session that mysteriously went quiet.
>   - **Mixed-mode operation is OUT OF CONTRACT.** A bare-record worker and an identity-record
>     worker must not share a session. The supported upgrade is a **drained** one: stop the old
>     worker, or let the session end, then start the new one. This clause is what makes the
>     unsupported case fail visibly and safely; it is not a licence to run mixed.
>
>   **[inferred]**; the bench demonstration is in §5, seven arms, both directions.
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
>   with it. **This sentence used to continue *"and is precisely the hazard PR #27's §10.5
>   clause 6 exists to exclude by keeping the worker's idle exit strictly shorter than the sweep
>   window"*, and that clause of it is now MEASURED FALSE — corrected 2026-08-26.** Clause 6's
>   20-minute idle window was to be timed on `time.monotonic()`, which on Darwin is
>   `mach_absolute_time` and **does not advance while the system sleeps**, while `find -mmin` is
>   wall clock. One unplanned 40-minute idle sleep on this machine put **2324 s (38 min 44 s)**
>   of divergence between the two against a margin sized at **10 minutes**, and over this boot
>   the figure is **269.694 h**; `:117`'s predicate run verbatim selects a `speak/` that a
>   monotonic idle timer still calls **12.51 min** young **[measured-here]**. **A shorter number
>   is not a shorter window when the two are read off different clocks**, so clause 6 excludes
>   nothing until it mandates the wall clock — which PR #27's §10.5 clause 6 now does, from the
>   swept directory's own mtime, and its §13 row 24 is ship-blocking as a result.
>   **This strengthens the conclusion below rather than weakening it.** Not only is `:117` no
>   backstop for an *obsolete* generation, it is an active hazard to the **current** one on the
>   ordinary path, with no contention required: **generation cleanup has to be specified, and it
>   has to be ordered** — and it has to be specified against a `speak/` directory that can
>   vanish under the worker doing the cleaning.
> - **The ordering, stated. [inferred] and UNRUN.** A worker may unlink generation `g` **only
>   after both halves of its election sweep against `g`'s owner have reached a TERMINAL result**
>   — 7(iv) and 7(iv-a) — and **only the worker that created `g+1` may do it**.
>   **"Completed" is the wrong condition and would re-open the region it closes.** A sweep
>   completes when it has *attempted* the signal, and 7(iv) deliberately RETAINS the `.pending`
>   marker on `EPERM` or any other non-terminal `killpg` failure so that a later election can
>   retry. Unlinking `g` on mere completion throws away the one thing that retry needs: the
>   later sweep walks generations and finds `g` gone, `continue`s, and never reaches that
>   owner's group again — so the marker is kept for a retry that has been made impossible, and
>   an unnamed player survives permanently rather than until the next election. Terminal means
>   the group was signalled or is provably gone (`ESRCH`); it does not mean the call returned.
>   **The marker's retirement and the generation's unlink are therefore the same decision** and
>   must be taken together: retire the marker and unlink `g` only on a terminal result, keep
>   both otherwise. The reason is §5's own
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
>   an older player's reap unlinked a newer player's record on **8 proven destructions across
>   4 of 12 trials** — the 12/12 an earlier revision reported here was anchored on harness defect
>   4's bad `W` stamp and is withdrawn — and a hook firing in that window could not reach a live
>   player on those same **4/12** (`C14a`); with per-player names, 0/12
>   (`C14b`). **An append-only ledger must not be used either:** its truncate erased
>   registrations it had never signalled on 12 of 25 truncations (`C13a`).
>   - **THE RECORD'S CONTENT IS THE PLAYER'S OWN `<pid>.<starttime>`, AND THE NAME IS NOT
>     ENOUGH — round 21.** Round 20 tightened the record *name* to `<pid>.<8-hex-nonce>`,
>     matched anchored, so a `.pending` marker could not be parsed as a pid. That is a
>     **parsing** fix and it was read as though it were an **identity** fix. It is not: the
>     pid in the name is a number, and **nothing removes a player record when its player
>     dies**, so the record outlives the process for the rest of the session. The committed
>     `C12b` trace shows exactly this — the warm-up player's record `94309.c8debde7` is in
>     the election sweep's target list on **24 of its 25 elections**, `ESRCH` every time,
>     still there at `gen12r` **[trials]**. Harmless there, and not harmless the first time
>     that number names something else.
>   - **So every site that signals a pid taken from a player record must re-read that pid's
>     current start time and SKIP IN SILENCE on a mismatch — and, since round 24, on a
>     **lookup that failed** as well, which is not a mismatch and is not an absence. There are
>     THREE such sites, not
>     two:** the hook (§10.3 step 6), the election-time record sweep ((iv-a) below), and
>     **the worker's claim-time kill ((iii) below)** — which reads the same records through
>     the same code and whose `kill` is the same act. Guarding two of three is how this
>     repair would ship broken.
>   - **The start time rides in the CONTENT, not in the name**, and that is a deliberate
>     match to **PR #27's §10.5 clause 7(i)**, which specifies the same anchored name and
>     the same `<pid>.<starttime>` content. The two documents must describe **one** scheme,
>     and the nonce and the start time do different jobs — the nonce makes the *path*
>     unique, the start time makes the *pid* an identity.
>   - **Same shape as clause 2's owner record, and for the same reason, but it is a
>     SEPARATE test over a SEPARATE record.** Round 20's review already caught the owner's
>     start time being credited against a player's pid; one identity serving both records is
>     how that gets done again. A bare player record under the check is **`unverifiable`**,
>     never verified, and all three sites refuse it — the degradation keys on the option and
>     never on the record's shape, which is round 16's finding applied here before it could
>     be rediscovered. **`gone` still attempts the kill and reports `ESRCH`**, because
>     clause 7(i) says *mismatch*, and a vacant pid is not a mismatch; that keeps four
>     committed arms' accounting meaning what it meant.
>   - **[inferred]**, and the residual is named. `ps -o lstart=` resolves to **one second**,
>     so a pid recycled inside the same second as its predecessor still collides — the same
>     limit as clause 2's, and it is why this is not tagged `[measured]`. **To close:**
>     pre-seed a `playerdir/` record naming a recycled pid held by an unrelated live
>     process, drive one hook invocation, one worker claim and one election, and confirm all
>     three skip while a matching record is still killed — the same rig as row 20(c) in PR
>     #27, one seeded file, no pid-wrap needed because the record can be written by hand.
>     Both directions are bench-demonstrated in §5; neither is a run of the trial rig.
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
>   - **The two targets need DIFFERENT treatment under (i)'s identity rule, and this is the
>     third signalling site round 21 added it to.** The **handle** is a `Popen` object for a
>     child this process forked, so its pid is reserved until this process reaps it and can
>     never name a stranger — no test, and none is possible. The **record** is read from
>     disk and is exactly (i)'s case: re-read the start time, skip on mismatch. A reader who
>     guarded the sweep and the hook and left this one alone would keep a `kill` at an
>     arbitrary recycled pid on the ordinary claim path.
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
>   - **VALIDATE THE RECORDED OWNER'S IDENTITY BEFORE SIGNALLING ITS GROUP. A `.pending`
>     marker is a NECESSARY condition for `killpg` and never a sufficient one — round 15,
>     and the fourth distinct defect in this bound.** Only the **highest** generation's owner
>     is liveness-tested, by the election itself; every **lower** generation's pid goes from
>     `readlink` to `killpg` with no test at all, and a marker left by a player that was killed
>     before it published keeps that path open indefinitely. Using clause 2's `<pid>.<starttime>`
>     the sweep has **three** cases, not one:
>     - **start time matches** — the superseded owner is still running and `killpg(pid)` names
>       its own group. **Signal it.**
>     - **a process exists with that pid and a DIFFERENT start time** — the owner is gone *and*
>       its pid has been recycled. `killpg` here signals a **stranger's whole group**.
>       **Skip it, and EXPIRE the marker**: the owner is provably gone, so that marker can never
>       become actionable again, and leaving it standing is what keeps the gate open on every
>       later election.
>     - **no such process, CONFIRMED** — the owner is dead and its pid has **not** been handed
>       out again, so the group id is still reserved to it and any orphan of ours is still inside
>       it. **Signal it: this is the case the clause exists for.** **Round 24: "confirmed" is
>       normative and it is where the probe went wrong.** This verdict is the only negative one
>       that *acts*, so it must rest on an observation that distinguishes absence from a failure
>       to look. On Darwin that observation is `ps` exiting nonzero with **both streams silent**;
>       a nonzero exit *with* a diagnostic, a `ps` that cannot be exec'd, a fork that fails, and
>       an exit 0 with no row are all **failures to look** and belong to the fifth case below.
>     - **the record carries no start time at all** — a bare `<pid>`, written before this
>       clause existed or by an implementation with the check switched off. **Round 16: this
>       is a FOURTH case and it must not collapse into the first.** There is nothing to compare
>       against, so none of the three verdicts above can be reached honestly, and the round-15
>       probe reached the *most dangerous* of them: it fell through to `kill(pid, 0)`, called a
>       recycled pid `same`, and signalled the stranger's group — the precise failure this
>       clause was written to prevent, on the exact record shape the clause's own falsification
>       arm produces. **REFUSE TO SIGNAL, and do NOT expire the marker.** Expiry means *the
>       owner is provably gone*, which is true of the recycled case and is exactly what is not
>       known here; retiring the marker would discard the only record that an unswept generation
>       exists. The marker survives, the generation stays unswept, and every later election
>       re-reads and re-refuses it — a bounded, visible leak of one marker instead of an
>       unbounded signal at a stranger, and loud in the trace on purpose. Demonstrated on the
>       bench in §5, both directions.
>     - **the LOOKUP ITSELF FAILED** — the record carries a start time and the live side could not
>       be read. **Round 24: this is a FIFTH case, it is not the fourth, and it must not collapse
>       into the third.** Both readers of the start time treated every `ps` failure as "no such
>       process", so a transient failure took the *signalling* branch: fork pressure, EINTR or a
>       full process table was enough to make this clause `killpg` a pid whose owner may already
>       have been recycled — and the failure is likeliest under exactly the load that recycles
>       pids fastest. It differs from the fourth case in that the record **can** be verified, just
>       not now; the sweep's action is nevertheless the same — **REFUSE TO SIGNAL, and do NOT
>       expire the marker**, because expiry asserts the owner is provably gone and here nothing at
>       all is known. It is recorded under its own reason so an operator can tell "drain the
>       bare-record generations" from "the machine could not answer, and this will clear by
>       itself". The election's policy for this case is **not** the fourth case's `kill(pid, 0)`
>       split — see clause 2's migration paragraph and §5.
>     **The verdict test rests on one kernel property, named so it can be attacked:** that a pid is
>     not reallocated while it is still in use as a process-group id, which is what makes
>     "recycled pid" and "our group still has members" mutually exclusive. **[inferred]** — read
>     off BSD allocator behaviour, not off this machine. It is the same instrument as PR #27's
>     §10.5 clause 7(iv), and it **diverges from it as of round 24**: this clause now separates a
>     confirmed absence from a failed lookup and PR #27's wording does not. That is a gap in the
>     other document, not a disagreement about intent — the two must be reconciled before either
>     ships, and the reconciliation belongs to whoever owns PR #27.
>   - **Bound it with a generation-tagged `.pending` marker.** The worker creates
>     `playerdir/<gen>.<nonce>.pending` *before* the fork; the wrapper removes it by exact name
>     **after** its record is published, not as its first act — PR #27 clause 7(i) makes the
>     first-act form unsatisfiable, since publication is three operations and a marker dropped
>     before they finish is dropped inside the very window it bounds. `killpg` is sent **only to a superseded owner whose own generation has a
>     marker** — not merely while some marker exists anywhere — which confines its blast radius
>     to the generations in which an unnamed player can exist. **The tag is not decoration:
>     without the per-generation test a single marker authorises `killpg` on every historical
>     generation, including group ids the kernel may have recycled.** Measured under the
>     *untagged, boolean* form: skipped 25/25 when not needed (`C16b`), used 23/25 when needed
>     (`C16a`) — but that same trace shows the bound decaying as markers leak, so the 23/25 is
>     the defect, not the design. The tagged, per-generation form, its cleanup ordering and the
>     identity test above are **[inferred]**; §5 states them, states plainly that these are the
>     fourth and fifth of **seven** defects found in this one mechanism — the sixth in the
>     election half (round 21), the seventh in the `ps` reader both halves share (round 24) — and
>     gives the re-run that closes them.
>   - **Requires row 21's generation protocol, and now requires its RECORD SHAPE too.** (iv)
>     reads the *superseded* owner's pid. A lock protocol that deletes the record of the worker
>     it replaced cannot supply it, and one that publishes a **bare pid** cannot supply the
>     identity the verdict test needs — so §10.5 clause 2 and clause 7(iv) must ship together,
>     with clause 2 publishing `<pid>.<starttime>`.
> - **(iv-a) The same newly elected worker ALSO sweeps the published player records, in the same
>   election and also before the model load. REQUIRED. NOT an alternative to (iv).** One
>   `readdir` of `playerdir/`, then `kill(pid, TERM)` for every name that parses as a record —
>   **and, since round 21, only after (i)'s identity test passes on that record's content.**
>   Not a refinement: this is the sweep whose unbounded target list (below) accumulates every
>   record the session has ever published, so it is the site with the *most* stale pids in
>   hand, and it went from a number parsed out of a filename straight to `os.kill` with
>   nothing in between.
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
> [`preemption-and-lock-protocol.md`](preemption-and-lock-protocol.md) **[measured-here]**.
> **The `.pending` bound is NOT one of the measured parts and round 15 found the fourth distinct
> defect in it** — it tags a *generation* and validates no *process identity*, only the highest
> generation's owner is ever liveness-tested, and a marker never expires, so a superseded owner's
> pid recycled as an unrelated group leader is `killpg`'d by a stale marker. The repair is clause
> 2's `<pid>.<starttime>` and 7(iv)'s verdict test (signal on *match* and on *confirmed no such
> process*, skip and expire on *different start time*, skip and keep the marker on *no identity in
> the record* and on *the lookup failed*), **[inferred]**, unrun. **Round 16 found the fifth:
> in the repair itself.** The identity check keyed on `option == "off" OR the record has no
> start time`, so under the option a **bare or legacy record** turned the check off and
> `killpg`'d the stranger anyway. It now keys on the option alone and a bare record is
> `unverifiable`: the sweep refuses and keeps the marker. **Round 24 found the seventh, in the
> instrument both halves share:** `ps -o lstart=` was read two-valued, so a transient lookup
> failure was indistinguishable from a confirmed absence and took the verdict that signals and
> supersedes. A confirmed absence is now one specific `ps` shape and every other outcome is a
> fifth verdict, `lookup_failed`, refused by every signaller and retried-then-lost by the
> election. **Round 21 found the sixth, in the
> ELECTION half of that same repair:** round 16 had the election supersede an `unverifiable`
> owner unconditionally, on the ground that superseding is harmless because the sweep refuses
> separately — but superseding is the licence to **consume jobs**, so a bare record belonging to
> a live legacy worker yields **two owners**, and nothing in the protocol observes being
> superseded, so it cannot serve as a drain either. The election now supersedes only when the
> recorded pid is **vacant** and refuses while it is **held**, mixed-mode operation is out of
> contract, and the cost is a session that wedges on a recycled bare pid (§4a).
> **And the same round, one record over: the PLAYER records carried no identity at all** — the
> anchored name added in round 20 is a parsing fix, the record outlives its player for the whole
> session (`C12b`, **24 of 25** elections), and three sites signalled a pid straight out of it.
> The content is now `<pid>.<starttime>`, matching PR #27 clause 7(i), and the hook, the record
> sweep and the claim-time kill all verify it (§4b(i)). **[inferred]**, unrun |
> **YES** — the repair is measured but it is the third proposed repair in three rounds, its
> `.pending` bound has now failed review five times running, and the identity test that replaces
> that bound has had exactly one round of review, which found a hole in it |
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
> harness should be trusted to close it; (4) **clause 2's owner record is now
> `<pid>.<starttime>` and `lockrace.py` still publishes a bare pid**, so none of the 400 trials
> exercised the identity comparison the clause rests on. `lockrace.py` was deliberately left
> alone — editing the protocol under test without re-running would leave the 400/400 above
> describing a protocol that is no longer in the repository. Change it **with** the re-run of
> (3), and add one arm whose incumbent record names a recycled pid; (5) **the completeness rule
> the driver now enforces has never been applied to a real run** — `run_lock.sh` requires each
> expected participant to record exactly one terminal outcome, and the committed
> `lock-owners.tsv` predates it. It reproduces every committed sample log exactly, but "no trial
> was silently short a racer" is a property of the re-run, not of the existing data |

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
  does need one to verify. **Round 15 stopped naming it as a mitigation and specified it:**
  clause 2's owner record is now `<pid>.<starttime>`, read with `ps -o lstart= -p <pid>`,
  which is the existence test and the identity test in one call **[measured-here]** — and
  §4b(iv)'s sweep takes its verdict off it. **The mechanism is no longer the open
  item; its resolution is.** Round 24 added the other half of "in one call": the call has to be
  able to say that it *failed*, or a failure reads as a confirmed absence and the sweep signals on
  it. `ps -o lstart=` has no sub-second form, so two processes that
  occupy the same pid inside one second are indistinguishable to it, and the size of the pid
  space is not established here (`sysctl kern.pid_max` is *"unknown oid"* on this machine;
  `kern.maxproc` is **4000**, a live-process ceiling and not the pid space
  **[measured-here]**). So the margin is **[inferred]** and closes on the same pid-wrap drive.
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
    **THAT IS A BOUND ON *WHEN*, AND THE HAZARD IS ABOUT *WHAT*.** Round 15's review made the
    gap explicit and it is the fourth of seven defects in this mechanism (see below): the marker says
    *"generation `g` may have an unnamed player"*; it says nothing about whether the pid
    recorded for generation `g` still **is** generation `g`'s owner. Only the **highest**
    generation is liveness-tested, by the election; every lower generation's pid reaches
    `killpg` untested, and a marker has no expiry, so the interval between the owner's death
    and the election that acts on its marker is unbounded. What closes it is not a better
    marker but a **verifiable owner identity** — clause 2's `<pid>.<starttime>` and 4b(iv)'s
    verdict test, which skips a recycled pid and expires its marker. **[inferred]**; nothing
    here has run it.
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
    one place where the repair could do more damage than the defect it fixes — which is why
    7(iv-a)'s unboundedness is stated in the clause itself rather than left here.
    **What changed in round 15 is which mechanism is doing the work.** `.pending` used to be
    specified as normative *because* it was the only bound on the blast radius; it is not the
    bound, it never validated the identity of its own generation's owner, and §5's
    garbage-collection bullet below now argues it should be demoted to an optimisation. The
    bound is clause 2's `<pid>.<starttime>` and 4b(iv)'s verdict test — **[inferred]**, and
    the same wrap drive closes it. **The record sweep still has no equivalent**: PR #27's
    clause 7(i) puts `<pid>.<starttime>` inside the player record so 7(iv-a) can make the same
    check, and that is one round old and unrun on either branch.
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
    - **`killpg` only the generations that actually have a marker.** Tagging the marker made
      ownership *readable* without making the sweep **use** it: the sweep still read `.pending`
      as a boolean, so one marker left by `gen12` authorised `killpg` against `gen1 … gen11` as
      well — process-group ids the kernel is free to have recycled by then, belonging to
      generations that may never have had an unnamed player at all. That is the blast-radius
      bound the marker exists to provide, spent, one revision after the tag was added to provide
      it. Derive the marked set from the markers present and signal only the
      `(generation, owner_pid)` pairs in it; record a `kill_skipped` for every superseded owner
      the narrowing excludes, so the bound is visible in the trace rather than assumed.
      **Narrowing loses no coverage:** a player that published is reachable through clause
      7(iv-a)'s record sweep, which is exactly why (iv) and (iv-a) are both required.
    - **Signal FIRST, and remove each marker only once its own generation's group has been
      swept.** Removing before the `killpg` re-opens the region the marker exists to close: a
      worker that dies after the unlink and before signalling leaves the unnamed player alive,
      and the *next* election finds no marker, skips `killpg` by its own bound, and cannot reach
      that player by record either, because it never published one — `C12c` reconstructed out of
      the cleanup. Signalling first makes that crash window fail safe: the marker survives, the
      next election sweeps the group again, and a redundant `killpg` on a group that is already
      gone is an `ESRCH`. A generation whose `killpg` failed with anything *other* than `ESRCH`
      keeps its marker and is retried.
    - **All of it BEFORE the electing worker forks any player of its own.** Otherwise the GC
      deletes the marker for a fork that has not happened yet, the next election sees no
      `.pending`, skips `killpg`, and the design collapses into `C12c` — the record-sweep-only
      arm that fails 12/12. The two orderings compose: sweep, then reap, then fork. In the probe
      the whole election sweep precedes the 0.80–2.02 s model load, so the margin is large.
    - **A MARKER STILL DOES NOT BOUND `killpg`, BECAUSE IT VALIDATES NO IDENTITY — the FOURTH
      distinct defect, found in round 15.** The generation tag stopped one marker authorising
      *other* generations. It did nothing about the marker's authority over its **own**. The
      wrapper and its whole process group can exit before any replacement election; the marker
      has **no expiry** and stays on disk until an election retires it; by that election the
      recorded owner pid may have been **recycled as an unrelated group leader** — and only the
      *highest* generation's pid is ever liveness-tested, by the election itself, so every lower
      generation goes from `readlink` straight to `killpg`. The clause therefore still could not
      claim the bound it claimed. **The repair is the instrument PR #27's §10.5 clause 2 already
      built: `<pid>.<starttime>` as the owner record, and the verdict test of 4b(iv) before
      signalling** — signal on *matches* and on *no such process*, **skip and EXPIRE the marker**
      on *exists with a different start time*. Expiry is half the repair, not a tidy-up: without
      it the skip fixes the blast radius and leaves the accumulation, and an election that skips
      every marked generation leaves every marker standing forever. Implemented in
      `speakd_probe.py` (`--owner-identity`, `owner_identity()`, `kill_skipped
      reason=owner_pid_recycled`, `pending_expired`) and specified in §4a and §4b. **[inferred]**
      as a result, and the label is deliberate. **The code was executed against a hand-seeded rig
      during review and both directions behaved as specified** — with `--owner-identity off` a
      seeded stale marker's `killpg` killed an unrelated live process group; with it on, the sweep
      recorded `kill_skipped reason=owner_pid_recycled`, expired the marker and left that group
      alive; and a genuinely dead owner still drew its `killpg`. **That is a bench check, not an
      arm**: it produced no committed trace, it is not a configuration, no figure here derives
      from it, and it says nothing about whether the narrowing loses coverage in a real orphan
      race. Nothing in the committed evidence ran any of it. **To close:** stage a superseded
      generation whose recorded owner pid is held by an unrelated live group leader, with a
      `.pending` marker naming that generation, and confirm the sweep records `kill_skipped
      reason=owner_pid_recycled` and `pending_expired` and leaves the stranger's group alive;
      then the same rig with a genuinely dead owner, and confirm `killpg` still fires. Both arms
      must be in the committed traces before this stops being `[inferred]`.
    - **AND THE REPAIR ITSELF HAD A HOLE, FOUND IN ROUND 16 — the FIFTH distinct defect in this
      one bound, and the first one that is in the fix rather than in the mechanism.**
      `owner_identity()` was written `if option == "off" or st is None: <old pid test>`. The
      first disjunct is the deliberate falsification arm. The second is a **record shape**, and
      putting the two behind one `or` let the record decide whether the check happened: under
      `--owner-identity on`, a bare `<pid>` record — one written before the option existed, or
      by an `off` worker — degraded silently to `kill(pid, 0)`, reported a recycled pid as
      `same`, and let a pending marker authorise `killpg` against the stranger's group. **The
      option closed the hazard for records it had written and left it open for every record it
      had not**, which is the population that matters during any migration. The rule is now that
      **the degradation keys on the option and never on the record**: `off` behaves exactly as
      in round 14, and under `on` a bare record is a fourth verdict, `unverifiable` — the sweep
      refuses to signal it and leaves its marker standing (§4b(iv)), and the election **refuses
      to supersede it while a process still holds its pid** (§4a; round 16 superseded
      unconditionally here and round 21 replaced that — see below). **Bench-demonstrated in five
      arms, in both directions**, against
      a live unrelated group leader whose real pid was written into a superseded generation's
      record with a `.pending` marker naming that generation:

      | probe | gen-0 record | option | trace | the stranger's group |
      | --- | --- | --- | --- | --- |
      | round 15 | bare `<pid>` | `on` | `kill_attempt … sig=14 result=sent`, marker reaped | **killed** — the hole |
      | round 16 | bare `<pid>` | `on` | `kill_skipped … reason=owner_record_has_no_identity`, `groups=0`, marker **kept** | **alive** |
      | round 16 | `<pid>.<starttime>`, matching a live owner | `on` | `kill_attempt … sig=14 result=sent` | **killed** — correct |
      | round 16 | `<pid>.<starttime>`, owner dead | `on` | `kill_attempt … sig=14 result=ESRCH`, marker reaped | n/a — correct |
      | round 16 | bare `<pid>` | `off` | `kill_attempt … sig=14 result=sent` | **killed** — the falsification arm, unchanged |

      Still a bench check and still `[inferred]`: no committed trace, no configuration, and no
      figure in this document derives from it. It closes under the same re-run as the row above,
      with one arm added — a superseded generation whose record is a **bare pid**, which must
      produce `kill_skipped reason=owner_record_has_no_identity` and leave both the stranger's
      group and the marker intact.

    **ROUND 21, the SIXTH defect in this area, and the first one in the ELECTION rather than the
    sweep.** Round 16's rule above — supersede an `unverifiable` owner freely — rested on the
    claim that *"the only destructive consequence of superseding is the pgid sweep, and the
    sweep refuses this verdict on its own"*. That claim is false. **Superseding is the licence to
    consume jobs**, so if the bare record belongs to a live legacy worker the election produces
    **two owners and overlapping audio**, which the sweep's refusal does nothing about. And
    superseding cannot be made into a drain: nothing in the protocol re-reads the lock after it
    has won, so `gen+1` notifies no one, and no notice can reach a worker that predates it. §4a
    now splits on `kill(pid, 0)` — supersede when the pid is **vacant** (no live worker to double
    up with), refuse when it is **held** (live legacy owner or recycled stranger,
    indistinguishable) — and declares mixed-mode operation out of contract, at the cost of a
    session that **wedges** when a bare record's pid has been recycled. **Bench-demonstrated in
    seven arms, both directions**, driven through the real `speakd_probe.py`:

      | gen-0 record | option | outcome | trace |
      | --- | --- | --- | --- |
      | bare `<pid>`, pid **held** by a live process | `on` | **loses** — refuses to supersede | `owner_record_unverifiable … action=refused_pid_held`, `election_lost … reason=unverifiable_record_pid_held` |
      | bare `<pid>`, pid **vacant** | `on` | **wins** | `owner_record_unverifiable … action=superseded_pid_vacant`, `election_won gen=1` |
      | `<pid>.<starttime>`, start time **matches** | `on` | **loses** | `election_lost held_by=…` — unchanged |
      | `<pid>.<starttime>`, start time **differs** | `on` | **wins** | `owner_pid_recycled …`, `election_won gen=1` — unchanged |
      | `<pid>.<starttime>`, pid **gone** | `on` | **wins** | `election_won gen=1` — unchanged |
      | bare `<pid>`, pid **held** | `off` | **loses** | `election_lost` — falsification arm, unchanged |
      | bare `<pid>`, pid **vacant** | `off` | **wins** | `election_won` — falsification arm, unchanged |

    **And the same round, the player records — §4b(i)'s identity, at all three signalling
    sites.** A player record's pid was still a bare number: the name shape added in round 20 is a
    *parsing* fix, and the record outlives its player for the whole session (`C12b`'s warm-up
    record, **24 of 25** elections **[trials]**). The record's content is now `<pid>.<starttime>`
    and the hook, the election sweep and the claim-time kill all re-read it. **Both directions,
    nine arms on the hook and three on the sweep**, against live seeded processes:

      | site | record content | option | outcome |
      | --- | --- | --- | --- |
      | hook, per-player **and** shared | matches a live player | `on` | **killed** — correct |
      | hook, per-player **and** shared | start time differs (recycled) | `on` | **spared**, `record_skipped … verdict=recycled` |
      | hook, per-player **and** shared | bare pid (legacy) | `on` | **spared**, `record_skipped … verdict=unverifiable` |
      | hook, per-player | content pid ≠ name pid | `on` | **spared**, `record_skipped … verdict=unverifiable` |
      | hook, per-player **and** shared | bare pid | `off` | **killed** — falsification arm |
      | election sweep, per-player | three seeded records at once | `on` | `swept=1 rows=3 skipped=2` — the matching player killed, the recycled stranger and the legacy record both left **alive** |
      | election sweep, per-player | the same three | `off` | `swept=3 rows=3 skipped=0` — **all three killed, including both strangers.** The defect, reproduced |

    Both are bench checks and both stay **`[inferred]`**: no committed trace, no configuration,
    no published figure derives from either, and `ps -o lstart=`'s one-second resolution still
    leaves a same-second collision open. The closing conditions are in §4a and §4b(i).

    **ROUND 24, the SEVENTH defect in this area, and it is in the INSTRUMENT rather than in
    either consumer — so it reached every site at once.** Both readers of the start time
    (`speakd_probe.py:proc_starttime`, `hook_probe.sh:now_starttime`) collapsed **every** failure
    into "the pid is absent": a `subprocess` `OSError`, a nonzero `ps` status of any kind, an
    empty answer. Callers then read that as `gone`, and `gone` is the one negative verdict that
    still **acts** — the sweeps signal on it and the election supersedes on it. So a *transient*
    `ps` failure made the identity guard do the two things it was added to prevent: **the election
    supersedes a still-live owner (two owners), and the sweeps signal a possibly-recycled pid (a
    stranger, or at clause 7(iv) a stranger's whole process group).** The shell reader had the
    failure twice over: `s=$(ps … | tr …) || return 1` takes its status from `tr`, which always
    succeeds, so the `ps` status was not merely conflated with absence — it was **discarded**, the
    same pipeline-status trap this document warns about for `head`.

    **A confirmed absence is now one specific observation, measured on this machine** (Darwin
    25.6, `/bin/ps`): a nonzero exit with **nothing on `stdout` and nothing on `stderr`**. Every
    other shape is a **`lookup_failed`** verdict — `ps: process id too large` (rc 1 *with* a
    diagnostic), a missing `/bin/ps` (rc 127), a fork that fails, and rc 0 with no row, since `ps`
    cannot both succeed and decline to answer. `stderr` is therefore captured rather than
    discarded; discarding it is what made the diagnostic shapes look like the silent one.

    **What `lookup_failed` means differs by site, and the split is the substance of the repair.**
    Every signaller refuses it — the hook, the record sweep, the claim-time kill, and the pgid
    sweep, which also does **not** expire the marker, because expiry asserts the owner is provably
    gone and here nothing at all is known. **The election retries a bounded number of times and
    then loses.** It does *not* reuse the bare-record rule (`vacant → supersede`, `held →
    refuse`), and the reason is the difference between the two facts: a **bare record is
    unverifiable forever**, so the election must decide terminally on the weakest evidence that
    exists, whereas a **failed lookup is unverifiable only at this instant** and the response the
    bare-record case cannot have — ask again — is available. Falling back to `kill(pid, 0)` would
    also be actively wrong on three counts: it re-admits pid existence as an election input under
    `--owner-identity on`, which is the round-14 behaviour the option abolishes, through a path
    nothing exercises and where a *transient failure* rather than a record shape decides whether
    the check happened; its trigger correlates with its hazard, since `ps` fails under the fork
    pressure that recycles pids fastest; and its failure mode is silent, because
    `vacant → supersede` looks identical in the trace whether the owner was verified dead or
    never asked about. **The cost of refusing is stated:** the worker does not start. That is a
    liveness failure of one invocation, bounded by the retry budget for the transient case, by the
    fact that a machine which cannot fork `ps` could not have forked a player either, and by
    `owner_lookup_failed` being recorded per attempt so the refusal is attributable.
    **Bench-demonstrated in both directions at every site, driven through the real
    `speakd_probe.py` and the real `hook_probe.sh`:**

      | site | input | option | outcome |
      | --- | --- | --- | --- |
      | election | owner record whose pid cannot be looked up | `on` | **4 retries, then loses.** `owner_lookup_failed … action=retry` ×4, then `action=refused_lookup_unavailable` and `election_lost … reason=owner_lookup_failed`; **no `gen+1` is created and the worker exits 0** |
      | election | owner **confirmed** dead | `on` | **wins**, `election_won gen=1` — unchanged |
      | election | owner live, identity matches | `on` | **loses**, `election_lost held_by=…` — unchanged |
      | election | owner live, identity differs | `on` | **wins**, `owner_pid_recycled` — unchanged |
      | election | the same unlookupable record | `off` | `kill(pid, 0)` decides and it **supersedes** — falsification arm, **`ps` never consulted**, no `owner_lookup_failed` row |
      | pgid sweep 7(iv) | superseded owner unlookupable | `on` | `kill_skipped … reason=owner_lookup_failed`, **no `killpg` attempted**, marker **neither reaped nor expired**, `expired=0` |
      | pgid sweep 7(iv) | superseded owner **confirmed** dead | `on` | `killpg` attempted (`ESRCH`), marker **reaped** — the case the clause exists for, unchanged |
      | pgid sweep 7(iv) | superseded owner **recycled** | `on` | skipped **and marker expired** — the contrast that shows the two skips are not one branch |
      | pgid sweep 7(iv) | superseded owner **bare** | `on` | skipped, `reason=owner_record_has_no_identity`, marker kept — same action as a lookup failure, **different reason in the trace** |
      | pgid sweep 7(iv) | superseded owner unlookupable | `off` | `killpg` attempted — falsification arm, `ps` never consulted |
      | record sweep 7(iv-a) | player record unlookupable | `on` | `record_skipped … verdict=lookup_failed`, `swept=0 rows=1 skipped=1` |
      | record sweep 7(iv-a) | matching / same record under `off` | `on` / `off` | **signalled** / **signalled (ESRCH)** — good input accepted, falsification arm unchanged |
      | claim-time kill 7(iii) | player record unlookupable | `on` | `record_skipped by=worker-claim … verdict=lookup_failed`, **no kill reached that record** |
      | claim-time kill 7(iii) | matching / same record under `off` | `on` / `off` | **signalled** / **signalled (ESRCH)** |
      | hook, per-player **and** shared | player record unlookupable | `on` | **spared**, `record_skipped … verdict=lookup_failed` — and `result=nopid` keeps its meaning, so the `C14a` derivation cannot read a refusal as a destruction |
      | hook, per-player **and** shared | matching / recycled / bare / **confirmed absent** | `on` | **killed / spared / spared / kill attempted (ESRCH)** — every good input still accepted, and the hook still stamps `K`, `R`, `Rdone` and publishes its job in every case |
      | hook, per-player **and** shared | any of the above | `off` | round-14 behaviour, byte for byte — `ps` never consulted |

    A third bench check, **`[inferred]`** like the other two, and every row above is an execution
    of the shipped `speakd_probe.py` or `hook_probe.sh` rather than a reading of it. **The lookup
    failure is staged with a real reachable input, not a stub** — an out-of-range pid, which
    Darwin's `ps` refuses with a diagnostic and which `safe_pid` admits because it is decimal
    digits above 1 — plus a forced `OSError` for the fork-failure branch, which no input can
    reach. **One note on the bench itself, because it is the failure this document keeps finding
    in miniature:** the first draft of the `pgid` arms put the unlookupable record at the *highest*
    generation, so the election correctly refused, no sweep ran, and the arm "passed" by never
    executing the branch under test. It now stages a second generation whose owner is confirmed
    dead so the election wins, and asserts `election_won` before asserting anything about the
    sweep. The `off` arms are the load-bearing ones for the option: the falsification arm decides
    on `kill(pid, 0)` *before* the start time is read at all, so no outcome split in the instrument
    can reach it — verified at every site rather than argued.

    **Why an un-reaped marker is not merely untidy — measured, in `C16a`.** In the arm **as
    measured** the wrapper removed its own marker early in startup — that is what the committed
    probe did, and the specified ordering has since moved the removal after publication — so a
    `killpg` that *works* kills the wrapper **before** it gets there and strands the marker that
    authorised it. **The corrected ordering does not remove that property and is not meant to:**
    a player killed before it publishes *should* leave its marker standing, because the marker's
    presence is exactly the signal that an unnamed player may exist. What the correction changes
    is that the marker now provably outlives the whole publish sequence instead of being dropped
    inside it, so the leak is state the next election must reclaim rather than a hole. Every successful sweep leaked
    exactly one. The committed trace: **25 markers created, 0 removed**, `pending_found` climbing
    **1 → 12** across twelve generations, and `33f62e9b.pending` surviving from `gen1` to
    `gen12r`. The consequence is the opposite of the bound the marker was introduced to provide —
    **23 of 25 elections ran `killpg` although only 12 orphan windows were ever staged.** The
    marker did not bound the window; it accumulated, and after the first leak the gate is
    permanently open. The trace separates the two halves cleanly: the leaked names are exactly
    the killed players, while `6fad43e5.pending`, whose player published normally, never
    reappears.

    **FIVE distinct defects have now been found in this one bound, and each was found only
    after the previous one had been repaired — the fifth in the repair of the fourth.** State it
    plainly, because the pattern is the finding:

    | # | round | the defect in the `.pending` bound |
    | --- | --- | --- |
    | 1 | 5 | **not implementable as written** — *"the worker removes the entries it has just swept"*, over a marker read as a boolean |
    | 2 | 10 | **no determinable set** — removal by `listdir` membership still cannot say *whose* a marker is; hence the generation tag |
    | 3 | 14 | **unlink before signal** — the cleanup that used the tag ran on the wrong side of the `killpg`, re-opening the region the marker exists to close; and the sweep still read the directory as a boolean, so one marker authorised every historical generation |
    | 4 | 15 | **no identity for its own generation** — the tag says *which* generation, never that the pid recorded for it is still that generation's owner; markers do not expire, and only the highest generation is ever liveness-tested |
    | 5 | 16 | **the identity test degraded on the record's SHAPE** — `option == "off" OR st is None`, so a bare or legacy record switched the check off under an option that said it was on, and `killpg` reached the stranger anyway. The first of the five that is a defect in a *repair* rather than in the mechanism |

    The tag was added to make the un-determinable set determinable, then the sweep went on
    ignoring the tag, then the cleanup that used the tag ran on the wrong side of the signal, and
    then the tag turned out to identify a *generation* where the dangerous operation needs to
    identify a *process* — and then the identity test that fixed that let the *record's shape*
    switch it back off. The reaping, the narrowing, the identity test and the expiry are all
    implemented in `speakd_probe.py` (`pending_reaped` / `pending_reap_failed` / `kill_skipped` /
    `owner_identity()` / `pending_expired`), but all of it is **[inferred]** as a *result*: the
    committed traces predate every one of them and were produced under the un-tagged name, the
    boolean gate and the bare-pid owner record, so no arm here exercises any of it. To close:
    re-run `C12b`, `C16a` and `C16b` under the tagged marker and the `<pid>.<starttime>` record,
    with a pre-seeded stale `.pending`, a pre-seeded dead record, **and a pre-seeded generation
    whose owner pid is held by an unrelated live group leader**, and confirm four things —
    `pending_found` does not grow across generations; every `killpg` carries a generation that
    had a marker, with `kill_skipped` accounting for the rest; no `pending_reaped` precedes the
    `kill_attempt` for its own generation; and the recycled generation produces `kill_skipped
    reason=owner_pid_recycled` plus `pending_expired`, with the stranger's group still alive
    afterwards. **Round 16 adds a fifth thing to confirm and a fifth pre-seeded generation**:
    one whose record is a **bare pid** held by an unrelated live group leader, which must produce
    `kill_skipped reason=owner_record_has_no_identity`, leave that group alive, and leave its
    marker **standing** — the only verdict of the four that neither signals nor expires, because
    it is the only one in which the owner is not proven to be gone.

    **AND A JUDGEMENT, ASKED FOR AND GIVEN: after the identity test, `.pending` is no longer
    carrying its weight, and it should be demoted from a safety bound to an optimisation.**
    The reasoning, not the assertion:
    - **The safety property now comes from somewhere else.** The verdict test skips a recycled
      owner pid **whether or not a marker names its generation**. Once that is in, the marker
      adds no safety: everything it forbids, the identity test already forbids.
    - **What the marker still buys is narrowing — and the one arm that measured it shows the
      narrowing almost fully open.** `C16a`: **23 of 25** elections took the `killpg` path where
      only **12** orphan windows were ever staged. The gate was open 92 % of the time in the only
      run that has ever exercised it.
    - **Its cost is four defects in four rounds, in a mechanism whose whole job is to make a
      dangerous operation rarer.** By contrast clause 7(iv-a)'s record sweep — which `os.kill`s
      **every** name in `playerdir/` on **every** election, gated by nothing — has had no such
      bound proposed for it at all, and its target list grows monotonically to 12 pids inside a
      single 12-trial run. **The marker is bounding the safer of the two sweeps while the more
      dangerous one runs ungated.**
    - **What follows.** The identity discipline is the load-bearing repair and belongs on *both*
      sweeps — which is what PR #27's clause 7(i) now does for the player record, by putting
      `<pid>.<starttime>` in the record's content so every signaller can re-read it. `.pending`
      should stay in the probe as a switchable arm (it is how the C16 pair was measured) and
      should be **specified as an optimisation with a stated cost**, not as the thing that makes
      `killpg` safe. **This is a recommendation, not a measurement**; it is not acted on here
      because the arm that would settle it — 7(iv) with identity and *without* the marker, against
      7(iv) with both — has not been run, and it is named in the closing conditions above.

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
argument about labels — it is an induction over nine rounds of review.**

### What the nine rounds actually did

| round | the clause it examined | verdict |
| --- | --- | --- |
| PR #27 | *"a newer message kills stale playback"*, `[inferred]` | reviewer found **two races** in the lock clauses before anything was measured |
| PR #28 rev 1 | those clauses, measured | `current` **and** the spec-corrected protocol both produce 2–3 owners; clause (ii) mis-specified; the `P`→`W` region uncovered |
| PR #28 rev 2 | **the repair rev 1 proposed** | reviewer found the repair **was not the one measured**, and that the arm which "closed" the region **could not fail**. Staged properly, **rev 1's repair fails 12/12** — and two further protocol defects in it (shared-record TOCTOU, ledger truncation) both reproduce |
| PR #28 rev 2, self-review | **the repair THIS revision proposes** | `killpg` blast radius under pid reuse (bounded, measured); one `setsid()` defeats it (measured); and the sweep signal itself was a silent no-op under `nohup` (found only by chasing a null) |
| PR #28 rev 3 | **§4b as rev 2 wrote it, read as an implementer would** | **§4b specified ONE election-time action and its own data credits a second one with the kill** — `C15c` and `C16b` skip `killpg` 25/25 and are killed by the *record* sweep, which §4b never mentioned (clause 7(iv-a)). **§4b never required the worker to `setsid()`**, without which the sweep either signals nothing or signals the harness's own process group. **§4a's garbage collection cited `rewrite.sh:117`, which cannot reach a depth-3 symlink**, and specified no ordering against the sweep — the unordered interleaving is `C11b`/`C12c` at 12/12. **§5's `.pending` GC was not implementable as written.** Plus a fourth harness defect touching a published figure (`W` in the player-published arms), a parser that signalled a filename as a pid, a run script one round behind the document, and two derivations that did not derive what they claimed |
| **PR #28 rev 4** | **the probe tooling and the staging, the two things rev 3 did not re-examine** | **The committed harness could not be run from a checkout at all** — every driver resolved its helpers from a private bench directory and two invoked one user's absolute interpreter, so on the author's machine they could execute stale external copies of the very probes this PR commits. **`run_lock.sh` still staged three scenarios by a fixed sleep** — S3's incumbent (`:114`), S4 (`:145`) and S6 (`:181`) — which the previous round's barrier repair walked past, and that costs `proposed` **every one of its 100 reclamation trials** (§3.3). **Harness defect 4 had a second consumer nobody had looked for:** `C14a`'s publication→destruction lag, and with it the *count* — the TOCTOU is 4/12 trials and 8 unlinks, not 12/12 and 24 (§2.5). **§2.6's stale-player lifetime was published as an interval it is not** — timer-start→exit, not `Popen`→exit, differing 7× on the same row |
| **PR #28 rev 5** | **the repairs rev 4 made to the staging and the marker** | **Four of rev 4's own repairs were defective, and the staging was wrong for the fifth time.** The barrier staged the *observation* and not the **election read** — a racer acknowledged, waited for `GO`, and then performed a fresh read the winner could have already invalidated. The generation-tagged marker cleanup **unlinked before the `killpg`**, so a worker dying in between left an unnamed player unreachable — the `C12c` failure the marker exists to prevent. A single marker still authorised `killpg` on **every** historical generation, defeating the blast-radius bound the tag was added to provide. `await_barrier()` was called on one winner path and not the other, which would have made every fresh `proposed` S1/S2 trial `VOID`. And the completeness manifest was only *warned* about, not required, so publishing without it silently disarmed the guard. **The response is a change of kind, not a sixth mechanism**: the election read now self-reports whether it saw the window, matched by the lock directory's **inode**, and an S1/S2 trial where no racer's deciding read saw it is `VOID`. The inode match earned itself immediately — a smoke run produced three `saw_window=yes` reads of which **two were on a lock a racer had re-created**, not the winner's. The **0 ms cell is reclassified**: its window is zero-width, so no staging can place a read inside it, and `spec`'s *"clean to a 50 ms stall, 180/180"* is now stated as **120/180** of window evidence |
| **PR #28 rev 6** | **§4b's `killpg` bound itself, and the four scripts that decide what counts as a completed run** | **The `.pending` marker still does not bound `killpg`, and this is the FOURTH distinct defect in that one mechanism** — each found only after the previous one was repaired (§5 tabulates all four). The generation tag stopped one marker authorising *other* generations; it validates no identity for its **own**, only the highest generation's owner is ever liveness-tested, and a marker has no expiry — so a superseded owner's pid recycled as an unrelated group leader is `killpg`'d by a stale marker. **Shown on a bench rig, not measured as an arm:** with the round-14 code a seeded stale marker's `killpg` killed an unrelated live process group; with clause 2's `<pid>.<starttime>` and the three-way test it is skipped, the marker expired, and the group left alive — no committed trace, and the repair stays `[inferred]`. **This is the first round whose principal finding is in the DESIGN rather than the staging.** Alongside it, four validators each accepted a partial or stale run as a pass: `run_lock.sh` proved only that *one* racer finished, `collect.sh` accepted any non-zero number of reconstructed trials, `summarise.sh` annotated `VOID` and exited 0, `publish.sh` merged a new rig over a stale one, and one `analyse_round2.sh` block put its exit status on `head` — which was also silently dropping **30 of 50** output rows, 8 of the 12 erasures among them, so the 12/25 figure the document quotes from that block was not derivable from it |
| **PR #28 rev 7** | **rev 6's own repair of the `killpg` bound, and the four scripts that decide what may be published** | **The identity test rev 6 added had a hole in the shape of the thing it was added to close — the FIFTH distinct defect in this one bound, and the first that is in the fix rather than the mechanism.** `owner_identity()` guarded on `option == "off" OR the record has no start time`, putting the deliberate falsification arm and a **record shape** behind one `or` — so under `--owner-identity on` a **bare or legacy record** degraded silently to `kill(pid, 0)`, called a recycled pid `same`, and let a `.pending` marker authorise `killpg` on a stranger's whole group. The option closed the hazard for records it had written and left it open for every record it had not, which is the entire population during a migration. The degradation now keys on the **option** and never on the record; a bare record is a fourth verdict, `unverifiable`, and the two sites fail safe in **opposite** directions — the sweep refuses to signal and keeps the marker, the election supersedes without signalling. Bench-demonstrated in five arms, both directions, stranger alive where it must be and dead where it must be; still `[inferred]`. Alongside it, four validators: **`publish.sh`'s rollback destroyed the evidence it existed to protect** — `mv`ing `traces/` out of the live destination before the swap, so a failed swap restored a gutted directory and the `EXIT` trap deleted the only copy (**all 114 committed trace files, measured on the round-15 script**); **its required-file set omitted the producers of four of the committed TSVs**, `collect_real.sh` among them; **`verify_fires.sh` was a subset check, not an exact-set check**, so a re-run appended to `RUNS.txt` gave a duplicate configuration that passed and would have made the 312-trial denominator **324**; and **`assemble_pass1.sh` pinned `C3` to one historical timestamp**, so any other valid pass silently published **10 of 11** configurations while the aggregate guard succeeded. Plus two derivation defects: the attribution chain let the player's own log outrank the kernel's wait status (latent — **no published figure moves**, verified over every row), and `summarise.sh`'s header claimed to re-derive *every* published figure when the event counts come only from `analyse_round2.sh` |
| **PR #28 rev 8** | **the two derivations that carry `C14a`'s destruction count and row 21's denominator** | **Two findings, and both are the same shape: a published number whose own script does not establish it.** `analyse_round2.sh` printed *"PROVEN destructions of a published record: N + M"* by adding two **global** counters that share no key — not the trial, not the unlink — and then **asserted** that the two witnesses fell in the same trials and saw distinct unlinks. Neither half was derived, and the figure resting on it, **8 across 4 trials**, is itself the correction that replaced a withdrawn 24-across-12/12. The join keys were in the traces all along, including a **third file the block never opened**: `markers.tsv`'s `tNc entry` is the timestamp `hook-kills.log` does not carry. It is now a three-way join on `(trial, unlink timestamp)` that binds each hook-C witness to **one** unlink and prints the **union** with the intersection computed and each event's **rank** in its trial; the committed traces give intersection **0**, ranks **#1 and #2**, and the **same 8 across 4** — unchanged, now derived, and narrowing rather than asserting where a window is ambiguous. And `summarise.sh` checked only that `lock-owners.tsv` was **non-empty**, so an interrupted run or one missing a whole protocol × scenario cell re-derived the **1200-trial / 400-per-protocol** result over a smaller denominator and still exited 0. The matrix — **60 cells × 20 reps**, transcribed from `run_lock.sh` and deliberately *not* derived from the file under test — is now checked, rep numbers included, before any section prints. Its own first draft passed everything by **failing to run** (a literal newline in an `awk -v` assignment, which BWK awk rejects with no output); it now refuses when it cannot run |
| **PR #28 rev 9 (this), review round 21** | **the PROTOCOL, for the first time in ten rounds — two clauses and the derivation that carries `C14a`** | **Three findings, and the first two are in the design rather than in a script.** **(1) The player records never had an identity.** Round 20 anchored the record *name* to `<pid>.<8-hex>` so a `.pending` marker could not be parsed as a pid, and that parsing fix was read as though it made the pid an identity. It does not: nothing removes a player record when its player dies, so a record outlives its process for the whole session — the committed `C12b` warm-up record is in the election sweep's target list on **24 of its 25** elections — and **three** sites then signal a number taken straight from it (the hook, the election-time record sweep, and the claim-time kill the review did not name). The content is now the player's own `<pid>.<starttime>`, matching **PR #27 clause 7(i)** field for field so the two documents specify one scheme, and all three sites skip in silence on a mismatch. **(2) Superseding an `unverifiable` owner was not fail-safe, and the reason given for it was false.** Round 16 argued the election may supersede freely because the sweep refuses that verdict separately — but superseding is the licence to **consume jobs**, so a bare record belonging to a live legacy worker produces **two owners and overlapping audio**, which is the single invariant this document exists to hold. Nor can superseding be made into a drain: nothing in the protocol re-reads the lock after winning, and no notice can reach a worker that by definition predates it. The election now supersedes a **vacant** pid and refuses a **held** one, mixed-mode operation is declared **out of contract**, and the cost is stated — a session that **wedges** when a bare record's pid has been recycled, bounded to one session and loud in the trace. **(3) The repair for rev 8's own finding used an invalid bound.** The hook-C witness was bound to one unlink by `(W_pid_write[jNb], tNc entry)`, and `W` is the **parent's** deferral stamp taken after `Popen` returns while the wrapper is already running — harness defect 4, reintroduced as a bound by the block that had just withdrawn a lag figure for it. There is no observed publication instant in these traces to substitute, so the binding no longer needs one: it is now a **uniqueness** argument over `(S2_prespawn_stat[jNb], tNc entry)` with the trial filter removed. **The figure survives byte-identical at 8 across 4** — on this data the invalid bound happened to select the same events (nearest unlink **+41.258 ms**, bound uncertainty at most **2.687 ms**), so it was latent exactly as defect 7 was. All three are bench-demonstrated in both directions, 18 arms; all three stay **`[inferred]`** |

**Ten consecutive rounds, and every round found a real defect in the previous round's
confident answer.** Rev 5 was the sharpest form of the pattern in the staging: **four of its five
findings were defects in rev 4's repairs**, not in anything older. Rev 6 and rev 7 are the
sharpest form of it in the design: the `.pending` bound has now failed review **five** times,
each failure only visible once the previous repair was in place — and rev 7's is the first that
is a defect in the *repair* rather than in the mechanism, which is the staging's pattern arriving
in the design. **Rev 7 also repeats rev 5's lesson exactly: three of its four validator findings
are defects in code rev 6 had just written**, and one of those, `publish.sh`'s rollback, would
have destroyed all 114 committed trace files on the first failed swap. The staging alone has been wrong five
times in five different ways, four of them introduced by the fix to the one before — which is why
rev 5 stopped trying to stage the read correctly and started **detecting** an unstaged one instead. **Rev 8 moves the pattern one place further out.** Its two findings are not in the mechanism, nor in a repair to the mechanism, but in the **derivations** — the scripts that decide what the mechanism is allowed to have shown. `C14a`'s destruction count had been corrected once already and the correction was an assertion; row 21's denominator had never been checked at all. Neither figure moved when they were fixed, which is the point: the numbers were right and the reasons for believing them were not, and nothing in nine rounds of reviewing the protocol would have found that. **Rev 9 moves it back.** After nine rounds in which the findings were increasingly about the rig — the staging, the validators, the derivations — round 21's two principal findings are in the **protocol itself**, and both are of the kind inspection is worst at: a repair that closed a hazard for one record and left the identical hazard on the record next to it, and a clause whose stated justification was sound about the act it named (`killpg`) and silent about the act that actually matters (claiming jobs). Its third finding is the familiar shape — a defect in rev 8's own repair — and it too left the figure unmoved, for the third time on that one number.
An unverifiable mechanism was replaced by a falsifiable check; that is the only move that has not
yet been undone by the next round. Rev 1's own headline — *"a repair was built and measured: 12 of 12 orphans
killed"* — was wrong in the way that matters most: the repair specified was a single replaceable
record, the thing measured was an append-only ledger, and the arm that measured it had a 1.2 s
delay that guaranteed the sweep always ran after publication. When the ordering rev 1 claimed to
close was finally staged (`C11b`), **the single-record form failed.**

### So the counter-argument is now refuted nine times over

The original argument for non-blocking was that these clauses are *"cheap, obviously correct on
inspection, and their failure windows are microseconds wide."*

1. **"Obviously correct on inspection" has now failed on fourteen distinct clauses** — the two
   lock clauses, clause (ii)'s scope (twice: first mis-scoped, then credited to the wrong
   sweep), the shared-record lifecycle, the append-only ledger's truncate, the
   player-authored-record repair, the process-group sweep's own blast radius, the sweep's
   dependence on an unstated `setsid()`, the missing record sweep at election time, the
   generation GC's non-existent reclaimer, the `.pending` GC's undeterminable set, the
   `.pending` marker's absent owner **identity** — that one being a defect in the
   repair for the one before it, which is itself the third such in a row on that mechanism —
   and, in round 21, the **PLAYER record's** absent identity (three signalling sites taking a
   pid from a record that outlives its process, with an anchored *name* mistaken for an
   identity) and the **election's** treatment of an unverifiable owner (superseding read as
   harmless because the sweep refuses separately, when superseding is the licence to consume
   jobs and therefore the route to two owners).
   Inspection is what produced all fourteen. The player-authored-record repair is the sharpest
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
  `run_lock.sh` no longer stages anything by a clock — B's classification in S3, **B's hold on
  A's reclaim in S3**, and the dead
  incumbent's record in S3, S4 and S6 — but **the committed `lock-owners.tsv` predates every one
  of those fixes**, so on the committed data `proposed` has **exactly one confirmed reclamation
  trial** (§3.3): 100 of its 400 are the reclamation scenarios and all 100 were clock-staged, but
  `lock-S3_aba-proposed-r1.tsv` is a committed per-trial trace in which both racers classify the
  incumbent `pid_dead` and one supersedes it, so that trial did exercise the mechanism; 220 are
  structurally vacuous, and the remaining 80 answer the who-wins race. Nothing here suggests
  `proposed` fails — mis-staging can only hide failures — and the mechanism it exists to provide
  has been shown to run once, on a sample of one. **Six rounds have each found a staging defect in the previous
  round's repair of this one script** — round 24's is the second clock in `trial_aba`, the one the
  round-3 repair left standing — so this is not a gap further reading will close; it is a
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
