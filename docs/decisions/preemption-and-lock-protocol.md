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

**Row 20 — the two-kill design does NOT partition the timeline. It leaves one region
uncovered, and that region is measured, not argued.**

- Within the region the spec reasoned about, the design is **confirmed**. The adversarial
  ordering `R < S2 < R_b < P < W` was provoked and hit **48 of 48 trials** across four
  configurations; in every one of the 48 the hook's `speak/pid` kill hit **nothing**
  (`ESRCH`), and in the **36** of those where the claim-time kill was enabled it killed the
  exact player, every time **[measured-here]**.
- The clause is **load-bearing, and that is now demonstrated rather than asserted**: with
  the claim-time kill switched off and everything else identical, the stale player ran to
  completion — its full 2.5 s — on **12 of 12** trials, with nothing in the design
  touching it **[measured-here]**.
- **But the partition is not complete.** The spec's claim is that the two kills partition
  the timeline *at the `speak/pid` write*. `P` and `W` are two separate steps, and a
  worker that dies between them leaves a player that **no step in the design can reach**:
  the hook's kill reads a pid that predates the orphan, and a replacement worker's
  claim-time kill reads the same stale pid. Measured: **12 of 12 orphans played to
  completion**, the full 2.5 s **[measured-here]**. The window is narrow — `P`→`W` is
  **median 1.33 ms, range 0.31–9.74 ms**, n = 72 — and hitting it needs the worker to die
  inside it, so **this is a low-probability hole, and it should not be oversold**. What
  makes it worth fixing is not its rate: it is that §10.6 states there is no such region,
  and that the same repair also removes two hazards that are *not* rare (§2.5).
- A repair was built and measured: the **player** writes its own pid record, and a newly
  elected worker sweeps it *before* loading the model. **12 of 12 orphans killed**
  **[measured-here]**.

**Row 21 — the spec's two clauses do not hold, and they were already known not to hold
before this run started.** Copilot's review of PR #27 found two races in them; both
reproduce.

1200 trials, three protocols, six scenarios **[measured-here]**:

| protocol | trials | worst case | trials ≠ 1 owner | rate |
| --- | --- | --- | --- | --- |
| `current` — the residency probe's own | 400 | **3 owners** | 121 | **30.2 %** |
| `spec` — §10.5 clause 2 (a) + (b) | 400 | **3 owners** | 61 | **15.2 %** |
| **`proposed`** — atomic `symlink` owner record, superseded by generation | 400 | **1** | **0** | **0.0 %** |

- The **`current`** protocol fails as row 21 predicted — and **worse**: it reached **three**
  owners, not two.
- The **spec-corrected** protocol is a genuine improvement and still fails. It is clean up to
  a 50 ms stall (180/180, where `current` fails 60 of the same 180) and then fails **40/40 at
  200 ms and 1000 ms**, plus **20/20 on the quarantine ABA**. So clause 2 **narrows** the
  window; it does not close it.
- The **proposed** protocol was clean on **400/400**, including the who-wins race at N = 16.

**Both rows should stay ship-blocking.** Not because the clauses are unverified any more
— they are verified now — but because **two of the three clauses that were verified came
back false**, and the replacements have not been through review. See §6.

**And one thing that had not been asked about turns out to matter more than the hole.** Two
hazards found on the way are not rare and are not in §10.5 at all: `kill(2)` on an **unreaped
zombie succeeds**, so a worker that never `wait()`s its player makes every kill site report
success while killing nothing (`C7`, 12/12); and **nothing in the design ever unlinks
`speak/pid`**, so the hook read a pid that was not the current player on **48 of 48**
adversarial trials — harmless as `ESRCH`, a wrong-process kill once that number is recycled.
Both are fixed by the same change the hole needs.

---

## 1. What was run, and what it is not

**A synthetic harness, deliberately, and no driven `claude` session at all.** Both
mechanisms are worker-and-filesystem level. Driving real turns would have bought realistic
`Stop` timing and cost the only thing that matters here — control over the ordering. The
hook's own contribution to that ordering is a single measured constant, and it was already
measured from real hooks: **the kill-to-rename gap, 0.063–0.219 s, median 0.086 s**
**[hook]**, reproduced here by `HOOK_GAP_S=0.09` and landing at **median 123 ms, range
107–137 ms** measured, which is inside that band (§2.1). Nothing else about a real turn enters
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

**Two independent passes, both committed.** `C1`–`C9` were run twice, ~17 minutes apart, 12
trials each. **Pass 2 is the published dataset and pass 1 is an independent replication**;
both are in the tree, and `preemption-lock-probe/compare_passes.sh` prints the two side by
side. They agree on **which step killed the player for every one of the nine configurations,
12/12 in both passes**.

Pass 1 was not discarded even though it has a known instrumentation defect — its stub player's
signal handler exited 0, so `rc` is uninformative there and attribution falls back to the
player's own log. Pass 2 re-raises the signal so `rc` and the log agree independently. **The
defect is disclosed rather than hidden because it is the reason two passes exist**, and because
the conclusions are identical either way.

Rig: [`preemption-lock-probe/`](preemption-lock-probe/README.md). Evidence:
[`preemption-trials.tsv`](preemption-trials.tsv) (pass 2 + `C10`),
[`preemption-trials-pass1.tsv`](preemption-trials-pass1.tsv),
[`lock-owners.tsv`](lock-owners.tsv). Every figure below re-derives from those files with `awk`
and `sort` only — `preemption-lock-probe/summarise.sh` is the derivation. Unlike the residency
run's `[rig]`, **this probe is in the repository**, so its protocol can be read as well as its
output.

---

## 2. Row 20 — preemption

### 2.1 The eleven configurations

One warm worker per configuration — it has already elected, loaded, synthesised and
played before the first trial. Then twelve trials of two `Stop` hooks. The second hook's
launch time is what selects the ordering; nothing is sampled and hoped for.

Nominal timeline of one trial, from hook A's rename `R_a = t0`, synth 1.0 s, pre-spawn
delay `D`:

```
S  = t0             claim: rename(job, job.taken.<pid>)
S2 = t0 + 1.0       pre-spawn re-stat of speak/job          (clause ii)
P  = t0 + 1.0 + D   player Popen
W  = P + ~0.7 ms    speak/pid write                          (clause i)
K_b = t0 + GAP                  hook B reads speak/pid and kills
R_b = t0 + GAP + 0.123          hook B renames its job into place
```

`GAP` is the only knob that changes between the first six configurations. The
kill-to-rename interval came out at **median 123 ms, range 107–137 ms** **[measured-here]**
— set by `HOOK_GAP_S=0.09` plus the marker writes — which sits inside the real hook's
measured **0.063–0.219 s** band **[hook]**. It is the middle of that band, not an
extreme of it; §5 names the sweep that would cover the tails.

| config | clause (ii) recheck | clause (iii) claim-kill | delay `D` | `GAP` | what it stages |
| --- | --- | --- | --- | --- | --- |
| `C1_prespawn` | on | pidfile | 0 | 0.4 s | `R_b` lands before `S2` |
| `C2_hookside` | on | pidfile | 0 | 1.6 s | `R_b` lands after `W` |
| `C3_adversarial` | on | pidfile | 1.0 s | 1.4 s | **`R_b` between `S2` and `P`, `K_b` before `W`** |
| `C4_noclaimkill` | on | **off** | 1.0 s | 1.4 s | the same, with (iii) removed — the falsification |
| `C5_norecheck` | **off** | pidfile | 1.0 s | 1.4 s | the same, with (ii) removed |
| `C6_handle` | on | **handle** | 1.0 s | 1.4 s | the same, with (iii) using the earlier probe's `_PREV_PLAYER.kill()` |
| `C7_noreap` | on | pidfile | 0 | 1.6 s | `C2`, with the worker never `wait()`ing its player |
| `C8_orphan` | on | pidfile | 1.0 s | 1.4 s | the worker **dies between `P` and `W`**; a replacement is elected |
| `C9_ledger` | on | pidfile | 1.0 s | 1.4 s | the same, with the proposed repair in |
| `C10a_nopid_pidfile` | on | pidfile | 0 | 1.6 s | **clause (i) removed** — no pid record is ever written |
| `C10b_nopid_handle` | on | **handle** | 0 | 1.6 s | the same, with (iii) holding a handle instead |

Eleven configurations, 12 trials each. `C1`–`C9` were run **twice**, ~17 minutes apart;
`C10a`/`C10b` were added after the first nine and ran once. **240 preemption trials**, plus 6
real-audio trials, plus 1200 lock trials for row 21.

### 2.2 Which step killed the player — the whole of row 20 in one table

Twelve trials per configuration, twice over. Attribution from the player's wait status,
cross-checked against its own log; the two agree on every row where both exist.

| config | ordering reached | **which step killed the player** | stale audio, s |
| --- | --- | --- | --- |
| `C1_prespawn` | `R<S2` (recheck) 12/12 | **no player spawned at all** 12/12 | none |
| `C2_hookside` | `W<R` 12/12 | **hook `speak/pid` kill** 12/12 | 0.529–0.585, med **0.561** |
| `C3_adversarial` | **`R<S2<R_b<P<W`** 12/12 | **worker claim-time kill** 12/12 | **0 — never started** 12/12 |
| `C4_noclaimkill` | **`R<S2<R_b<P<W`** 12/12 | **NOTHING** 12/12 | 2.501–2.508, **full length** |
| `C5_norecheck` | **`R<S2<R_b<P<W`** 12/12 | **worker claim-time kill** 12/12 | **0 — never started** 12/12 |
| `C6_handle` | **`R<S2<R_b<P<W`** 12/12 | **worker claim-time kill** 12/12 | **0 — never started** 12/12 |
| `C7_noreap` | `W<R` 12/12 | hook `speak/pid` kill 12/12 | 0.548–0.584, med 0.564 |
| `C8_orphan` | **`P<death<W`** 12/12 | **NOTHING** 12/12 | 2.501–2.508, **full length** |
| `C9_ledger` | **`P<death<W`** 12/12 | **newly-elected worker's sweep** 12/12 | 0.797–0.852, med **0.825** |

**[measured-here]**, and re-derivable: `summarise.sh` sections A and B over
`preemption-trials.tsv`.

**The adversarial ordering was reached, not sampled.** `R < S2 < R_b < P < W` held on all
**48** trials of `C3`–`C6`, and on all 48 the hook's own kill returned `ESRCH` — it targeted
a pid that was **not** the player about to be spawned. That is the precondition the brief
insisted on: *"a run where the hook's kill happened to see a live pid proves nothing."* No
trial in `C3`–`C6` saw a live pid.

### 2.3 Clause (iii) is load-bearing; clause (ii) is not

Two falsification arms, each removing exactly one clause from `C3` and changing nothing
else.

- **Remove the claim-time kill (`C4`): the mechanism breaks, cleanly.** The stale player ran
  its **entire** 2.5 s on 12 of 12 trials, and both the newer and the older utterance were
  live simultaneously. **Nothing in the design touched it** — that is the whole content of
  §10.6's *"leaving a stale player running that no other step touches"*, and it is now
  observed rather than reasoned. **Clause (iii) is required.**
- **Remove the pre-spawn re-`stat` (`C5`): nothing changes.** Identical to `C3` on all 12
  trials — the claim-time kill still reaches the player before it starts. **Clause (ii) is
  therefore an optimisation, not a correctness clause**, and §10.5 describes it as one of
  the things that makes the rule true. What it actually buys is skipping a
  spawn-and-immediate-kill pair.
- **`handle` versus `pidfile` (`C6`) does not distinguish them.** Identical to `C3`, 12/12.
  I expected `pidfile` to be the safer of the two because it would survive a worker restart.
  **It does not**, and §2.4 is why: the record the restarted worker reads was never written.
  So the `handle`/`pidfile` choice is *not* the load-bearing distinction it looks like —
  which is worth stating, because it is the distinction an implementer would reach for.

### 2.4 The hole: `P` and `W` are two steps, and §10.6 states the partition at one

§10.6 says the two kills *"partition the timeline at the `speak/pid` write"*. They partition
it at the **pid record's publication**, and under §10.5 clause 7(i) that is a *different*
instant from the spawn, because the worker writes the record **after** `Popen`. So there are
three regions, not two:

| when the hook publishes | who covers it | measured |
| --- | --- | --- |
| before the record is written | the worker's claim-time kill | `C3`/`C5`/`C6`, 36/36 |
| after the record is written | the hook's own pid kill | `C2`, 12/12 |
| **worker dies between `P` and `W`** | **nobody** | `C8`, **12/12 played to completion** |

In `C8` the worker exits immediately after `Popen`, before writing the record. Then:

- hook B's kill reads `speak/pid`, which still names an earlier, dead player → `ESRCH`;
- the ensure-worker step elects a **replacement**, which claims job B and runs its
  claim-time kill against the *same* stale record → `ESRCH`;
- the orphan plays to completion, 12 of 12 **[measured-here]**.

**`C9` is the repair, and it works.** The player publishes its own pid, and a newly elected
worker kills whatever the record names *before* it loads the model. Every orphan was killed,
12 of 12, at **median 0.825 s** after it started talking — which is the replacement worker's
election-and-startup latency, not the sweep's. **The placement is load-bearing and was
learned here:** the model load is 0.80–2.02 s **[hook]**, so a sweep placed *after* it would
have let every one of these orphans talk for one to three seconds instead of 0.8.

**How much this matters.** The window is `P`→`W`: **median 1.33 ms, range 0.31–9.74 ms**,
n = 72 **[measured-here]**. Hitting it requires the worker to die inside it, so the rate is
(that window) × (worker death rate) and is very small. **The case for fixing it is not its
rate** — it is that a stated rule is false, and that the same one-line change removes two
hazards from §2.5 that are not small at all.

### 2.5 Three things the run found that nobody asked about

**1. `kill(2)` on an unreaped zombie SUCCEEDS, so "the kill succeeded" is not evidence the
player was alive.** In `C7` the worker never `wait()`s its player. Both kill sites then
reported success on all 12 trials — the hook's *and* the worker's claim-time kill — against
a process that was **already dead**, killed by the hook 0.56 s earlier. Compare `C2`, which
is identical except that the worker reaps: there the claim-time kill correctly reports
`ESRCH`. **A worker that does not reap makes its own preemption logic unfalsifiable from the
inside**, and §10.5 says nothing about reaping. **[measured-here]**

**2. The hook routinely kills a pid that is not the current player, and nothing unlinks the
record.** On all 48 adversarial trials the hook's kill returned `ESRCH` against a pid left
in `speak/pid` by an earlier trial. `ESRCH` is the harmless outcome; the harmful one is the
same read after that pid number has been **recycled**, at which point the hook kills an
unrelated process. Recycling was **not** observed and is **[inferred]** — but the stale read
that precedes it was observed 48 times out of 48, so this is not a hypothetical setup. **The
worker should unlink the record when it reaps the player**; §10.5 and §10.6 both leave the
record in place forever.

**3. Clause (i) and clause (iii) are coupled, and §10.5 has the coupling backwards.** §10.5
says of the two kills: *"The pid file bounds the case where the hook sees a live player; the
worker-side kill bounds the case where it does not. **Both are required.**"* Two
configurations remove clause (i) — the pid record — and the pair separates what (i) is
actually for:

| config | clause (iii) reads | which step killed the player | stale audio, s |
| --- | --- | --- | --- |
| `C10a_nopid_pidfile` | the pid record | **NOTHING** 12/12 | 2.501–2.508, **full length** |
| `C10b_nopid_handle` | an in-memory handle | worker claim-time kill 12/12 | 0.686–0.712, med **0.695** |

**[measured-here]**. Read together with `C6`:

- **`pidfile` and `handle` are indistinguishable while the record exists** (`C3` vs `C6`,
  24/24 identical), so an implementer choosing between them sees no difference.
- **They are opposite when the record does not** (`C10a` vs `C10b`, 12/12 each). A
  record-reading claim-kill has *nothing to read* and the stale player runs to completion; a
  handle-holding one does not care.
- **And clause (iii) with a handle still cannot reach a player its own worker did not spawn**
  — which is `C8`, and is why clause 7(iv) exists.

So the honest statement is neither §10.5's *"both are required"* nor *"(i) is only latency"*:
**(iii) should kill BOTH targets — its own handle and whatever the record names.** The handle
covers the live-worker case with no dependency on a file; the record covers the
worker-restart case; and clause (i)'s remaining independent value is measured separately: in
`C2` the hook's own kill reached the player **median 127 ms sooner** than the worker's claim
would have (range 115–141 ms, n = 12) **[measured-here]** — the hook's kill-to-rename gap plus
the kqueue wake. Worth keeping for that alone.

Also confirmed, and it is the one part of §10.6 that needed no repair: **playback in progress
dies fast.** From the hook's kill marker to the player's own death record: **median 0.77 ms,
range 0.49–2.35 ms**, n = 24 **[measured-here]**. §10.6 bounds this by the hook's whole wall
cost (0.086 s); the real figure is two orders of magnitude smaller.

### 2.6 The real-audio arm

Real Kokoro synthesis on `bf_emma`, `is_phonemes=False`, `/usr/bin/afplay` as the player, two
distinguishable utterances (*"one, two, three…"* against *"alpha, bravo, charlie…"*), the `C3`
ordering, 3 trials per arm. **This arm exists only to answer audibility** — the stub arms
establish the ordering and the attribution, and 12 trials each of those is worth more than 12
of these.

| arm | result |
| --- | --- |
| claim-time kill **on** | `afplay` for the stale utterance lived **13, 19 and 19 ms** before `SIGUSR1`, against a **5.7 s** wav. The newer utterance then played in full, 3/3 |
| claim-time kill **off** | both `afplay`s ran to completion and **overlapped for 3.25, 3.26 and 3.50 s**, 3/3 |

**[measured-here]**, and the second row is the one that matters: *"a newer message kills stale
playback"* is not merely late without clause (iii) — **two utterances talk over each other for
three and a half seconds.**

**One honest limit on the first row.** What is measured is that the `afplay` process lived
13–19 ms. Whether 13 ms is short enough that no sample reached the output device is
**[inferred]** — `afplay`'s own time-to-first-sample was not measured, and nothing in this rig
listens. The inference is safe (a 5.7 s utterance truncated to 13 ms of process life, before
CoreAudio has been handed a buffer) but it is an inference, and the experiment that removes it
is a loopback capture rather than a longer run.

---

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
is simply seen as alive. The scenarios that genuinely test it are **S3, S5 and S6**, and those
are 180 of its 400 trials.

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

### 4b. §10.5 clause 7 — four hooks, and the status of each changes

> **7. §10.5 owes §10.6 four hooks. Three are measured; one is new.**
>
> - **(i) The pid record is written by the PLAYER, not by the worker. REQUIRED.** Spawn the
>   player through a wrapper that publishes its own pid and then `exec`s — e.g.
>   `sh -c 'echo $$ > pid.tmp && mv pid.tmp pid && exec afplay "$1"' _ file.wav`. **A
>   worker-authored record is what creates the hole:** `Popen` and the write are two steps,
>   and a worker that dies between them leaves a player that no other step in the design can
>   reach. Measured, 12/12 orphans playing to completion.
> - **(ii) The pre-spawn re-`stat` of `speak/job` is an OPTIMISATION, not a correctness
>   clause.** Measured: with (iii) in place, switching (ii) off changed no outcome across 12
>   adversarial trials. What it buys is avoiding a spawn-and-immediate-kill pair. Keep it;
>   stop describing it as load-bearing.
> - **(iii) The worker kills the current player the moment it claims a newer job. REQUIRED,
>   measured load-bearing rather than argued — and it must kill BOTH targets.** With it, the
>   stale player was killed before it produced any audio at all, 36/36 across the three
>   configurations that enable it. Without it, in the identical ordering, the stale player ran
>   to completion 12/12 with nothing in the design touching it. **Which target it kills
>   matters, and §10.5 does not say:** an in-memory handle and the pid record are
>   indistinguishable while the record exists (24/24) and **opposite** when it does not (12/12
>   each way, `C10a` vs `C10b`) — and neither alone reaches a player spawned by a *previous*
>   worker. So (iii) kills its own handle **and** whatever the record names. Two `kill`s, no
>   branch, no ordering assumption.
> - **§10.5's *"Both are required"* about (i) and (iii) is imprecise and should go.** What is
>   true: (iii) with both targets covers every case in which the worker survives the spawn;
>   (i) exists so that a *different* process can do the killing, and its measured independent
>   value is that the hook reaches the player **median 127 ms sooner** than the worker's next
>   claim would (range 115–141 ms, n = 12).
> - **(iv) A newly elected worker kills whatever the pid record names BEFORE it loads the
>   model. REQUIRED, and new.** This is the only step that can reach a player orphaned by a
>   dead worker. The placement is normative and was learned from the measurement: the model
>   load is 0.80–2.02 s **[hook]**, and a sweep after it would let the orphan talk through
>   the whole of it.
> - **The worker must `wait()` its player, and unlink the pid record when it does.** Both
>   are measured consequences, not tidiness: `kill(2)` on an unreaped **zombie succeeds**,
>   so an unreaped player makes every kill site report success while killing nothing; and a
>   record left behind after the player dies is a **live pid the next hook will kill** as
>   soon as the number is recycled.

### 4c. §10.6 — the partition sentence is false as written

> **Replace** *"the two kills partition the timeline at the `speak/pid` write and every
> publication instant is covered by one of them"* **with:**
>
> **The two kills partition the timeline at the pid record's publication — which is why the
> record must be published by the player and not by the worker.** With a worker-authored
> record there are *three* regions, not two, and the middle one is uncovered: a hook whose
> read falls before the record is written kills nothing (covered by the worker's claim-time
> kill), a hook whose read falls after it kills the player (covered), **and a worker that
> dies between spawning the player and writing the record leaves the player unreferenced —
> the hook reads a pid that predates it, and a replacement worker's claim-time kill reads
> the same stale pid.** Measured: the window is sub-millisecond, and when it is hit the
> orphan plays to completion every time. With a player-authored record and clause 7(iv) the
> region closes: measured, every orphan killed.
>
> **And *"cancellation is latency only, not correctness"* is now true, with its condition
> discharged rather than pending** — conditional on 7(iii) **and** 7(i)+7(iv), all three of
> which are measured. The residual cost is the newer utterance waiting out the older
> synthesis.

### 4d. §13 — proposed row text

> | **20** | ~~§10.6's preemption rests on three worker-side hooks that are all [inferred]~~ |
> **MEASURED 2026-08-25 and PARTLY FALSIFIED.** 240 trials over 11 configurations, two passes
> that agree. The adversarial `R < S2 < R_b < P < W` was provoked **48/48** with the hook's kill
> hitting nothing every time; clause (iii) is confirmed load-bearing (stale audio killed before
> it starts, 36/36) and its absence confirmed fatal (**12/12 played to completion**; in real
> audio two utterances overlapped for **3.25–3.50 s**). **But the two-kill partition has a
> region the spec asserts it does not have:** a worker dying between `Popen` and the
> `speak/pid` write orphans a player nothing can reach, **12/12**. Also measured: clause (ii) is
> an optimisation not a correctness clause; `kill` on an unreaped **zombie succeeds**, so an
> unreaping worker cannot tell a live player from a dead one; and the hook killed a
> **non-current pid on 48/48** adversarial trials with nothing ever unlinking the record.
> Repair specified and measured (player-authored pid record + sweep before the model load,
> 12/12 orphans killed) —
> [`preemption-and-lock-protocol.md`](preemption-and-lock-protocol.md) **[measured-here]** |
> **YES** — the repair is measured but has not been reviewed |
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
- **A worker dying at any point other than the two staged (`P`→`W`, and after `W`).** The
  rig can kill at exactly the points it was told to. A worker that dies *inside* `create()`,
  or between the claim and the claim-time kill, was not staged. To close: extend
  `--die-after` to every step of the loop and sweep it. Expected outcome from the design,
  **[inferred]**: everything before `P` leaves no player and therefore no orphan.
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
- **The proposed protocol's GARBAGE COLLECTION was neither implemented nor measured.** What
  was measured is the election and the supersession; `lockrace.py` never unlinks an obsolete
  generation, so every trial ran with all generations present. The argument that unlinking
  generation `g` once `g+1` exists is safe — the highest generation always exists while its
  owner lives, because an owner only ever removes generations *below* its own — is
  **[inferred]**. To close: add the unlink and re-run S3, S4 and S6 with a reclaim delay
  straddling it. **This is the most likely place for a fourth race to be hiding**, and it is
  the same shape as the two that were already found: a cleanup step acting on a path.

### One thing this run deliberately did not re-open

**The 8/8 `mkdir` pre-check result is untouched.** That measurement asked *who wins a
contended election*, and its answer — the hook's `[[ -d ]]` pre-check lost 8/8, the
`mkdir` inside the worker is the guarantee — is unaffected by anything here. Row 21 asks
the different question of whether a protocol can **misclassify the winner**. Scenario S5
re-runs the who-wins race against all three protocols precisely so the two sit side by side
and cannot be conflated.

---

## 6. Should rows 20 and 21 stay ship-blocking?

**Both should stay ship-blocking — and the reason has changed, which matters more than the
answer.**

The integration agent's argument was: *the spec states rules that are false unless an
unmeasured clause holds.* It flagged that calling them non-blocking is defensible but means
shipping two `[inferred]` correctness clauses, and that this should be an explicit choice.
It also offered the counter-argument that the clauses are *"cheap, obviously correct on
inspection, and their failure windows are microseconds wide."*

**That counter-argument is now refuted on all three of its clauses, and this is the single
most important output of this run:**

1. **Not obviously correct on inspection.** Two of the three clauses under test were found
   *wrong* — one by review, one by measurement. §10.5 clause 2(a) and 2(b) do not close the
   race they were written for; §10.5 clause 7(i) creates a hole of its own. Inspection is
   exactly what had already been applied to them, and inspection is what produced them.
2. **Not microseconds wide.** The `P`→`W` window genuinely is (median 1.33 ms), and §2.4 says
   so plainly rather than inflating it. But the *pid-less lock* window is as wide as the
   winner's scheduling delay — **unbounded**, not microseconds, which is review finding 1 —
   and the ABA window is as wide as a reclaimer's own delay between deciding and acting. The
   clearest number: **at N = 8 with no stall injected at all, the ABA fired on its own in
   1 trial out of 60, under both `current` and `spec`.** That is a 2 % failure rate on the
   unprovoked case.
3. **Not cheap, in the sense that matters.** The clauses are cheap to *write*. Getting them
   right took three protocol variants and a falsification arm per clause. A reviewer waving
   them through on cost would have shipped the two that are wrong.

**So the honest framing of the choice is now the opposite of the one on the table.** It is
not *"is it acceptable to ship two `[inferred]` correctness clauses?"* — it is *"is it
acceptable to ship two clauses now known to be false, plus replacements that have had a
measurement but not a review?"* The first question was arguable. The second is not.

**What would take them off the blocking list.** Not more measurement — the measurements are
done. For each row, one review pass over the proposed replacement text in §4 by someone who
did not write it, on the same standard that found the two races in the clauses it replaces.
The failure mode this run demonstrates is *plausible-and-wrong*, and the only thing that
caught it both times was an adversarial reader. **Row 20 and row 21 should move to
non-blocking when §4's text has survived that, and not before.**

**Two smaller notes for whoever owns that call.**

- **Row 20's repair is a new mechanism, not a tweak.** Clause 7(iv) — a newly elected worker
  sweeping the pid record before it loads the model — did not exist in §10.5 in any form. It
  is measured, but it is also the newest thing in this document and therefore the least
  reviewed.
- **Row 21's replacement changes the lock's on-disk shape** from `worker.lock/` (a directory
  with a pid inside) to `worker.lock.<gen>` (a symlink whose target is the pid). Anything
  that greps for the old name — including the hook's pre-check and any sweep — has to move
  with it. That is a small, mechanical, easily-missed edit, which is the kind this project
  has been bitten by before.
