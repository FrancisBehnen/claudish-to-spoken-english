# Worker residency, and the first TTFA ever measured from a hook

Closes ship blocker **row 2** of [`speech-integration-spec.md`](speech-integration-spec.md) §13 —
*"the worker residency mechanism (§10.5): pick one, then measure TTFA from the hook, cold and warm,
against 3 s"* — for [#11](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/11), part
of the [#1](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/1) map. Measured
2026-08-25 on **Apple M3, 16 GB**, Claude Code **2.1.245**, through the settled espeak /
`kokoro-onnx` path, voice `bf_emma`.

**The headline, before anything else.**

| | measured, from a real `Stop` hook | 3 s line |
| --- | --- | --- |
| **cold** — no worker resident when the hook fires | **median 3.16 s**, range 2.66–5.50 s, n = 7 | **3/7 pass — FAILS** |
| **warm** — worker resident | **median 1.22 s**, range 0.57–4.01 s, n = 30 | **28/30 pass — holds** |
| **cold, but warmed during the turn** (§the mechanism below) | **median 1.71 s**, range 1.37–3.83 s, n = 5 | **4/5 pass — holds** |

Every row is derivable from `residency-timings.tsv` — see *Reproducing the leads* in §4. **Both cold
rows assume the model file is already warm in the page cache** and are optimistic by an unmeasured
margin; the reason that is a closed limitation rather than an open one is at the end of this document.

**The second and third rows are NOT disjoint populations, and this table reads as though they were.**
The 30 warm rows are the 25 labelled `warm30` **plus** the five labelled `warm30+mdwarm5`: the
warmed-during-the-turn rows are a **subset** of the warm rows, not a third arm beside them. So the
**3.829 s** failure is counted twice — it is one of warm's two misses and the warmed set's single one —
and 30 and 5 must not be added. On the 25 rows that are warm and *not* warmed-during-the-turn the
median is **1.085 s** and the line holds **24 times in 25** — re-derived here by filtering
`residency-timings.tsv` on `set == "warm30"`, and stated as the same caveat against the same three rows
in spec §10.5. Nothing in the table is arithmetically wrong; each ratio is correct over its own rows.

**§4's headline number survives, but it has to be re-stated.** "Median 0.86 s" is not what a hook
delivers; **1.22 s** is, and the gap is real and explained below. What does *not* survive is any
reading of §4 that leaves the cold case implicit: **cold from a hook is a failure against the 3 s
line, and no residency mechanism can make it not be.** The mechanism's job is to make sure the user
does not stand in the cold case — and the one picked here does that, measurably, on the very first
turn of a fresh session, which is the only turn where the question arises.

**This is the first TTFA anyone has measured from a hook process.** §15 said so and it was correct.
Every figure in §4 came from `bench/first-sentence.py`. Every figure in the tables below came from a
`Stop` hook fired by Claude Code 2.1.245 against a driven session, with the hook's own clock read
in-process before it did anything else.

No plugin file was touched. `rewrite.sh`, `rewrite-md.sh`, `providers.sh` and `hooks/` are unmodified,
and `speak.sh` still does not exist. No LLM was called by any bench or corpus tool; the driven session
made about thirty two-word Haiku turns, whose only purpose was to make a hook fire.

---

## SUPERSEDED — this document's DESIGN is proposal, not specification; its MEASUREMENTS stand on their own

**Read this before every design section in this document — §1, §1b, §2, §2a, §3, §4 and §4a–c, §5, §6,
and the two routing subsections *§10.5 — the OPEN heading comes off* and *§10.6 — two qualifiers*.**
Everything in this document was written on 2026-08-25 as **proposed** content
for [`speech-integration-spec.md`](speech-integration-spec.md). They were folded in, and the two
protocols this document proposes have **since been run** — 1200 lock trials over three protocols and six
scenarios, and 312 preemption trials over 26 switchable configurations, the spec's **[trials]** arm, §13
rows 20 and 21 — and **four of the clauses proposed below were falsified.** The spec has replaced them. Nothing here was re-run by that,
so this document is **qualified rather than rewritten**: the sections below are the design that was
measured, not the design that is specified. **The distinction is stated once, here, and referenced from
each site rather than re-argued.**

### The rule, stated once — and it is a STANDING rule, not a list of sites

**Every round that has read this document against the spec has found more sites, and the count is kept
where it is checkable rather than restated here** — spec §13's note under the defect table, whose FOURTH,
FIFTH, SIXTH and SEVENTH entries all name this document. Those are not four unrelated errors; they are
one structural fact about what this document is, discovered four times site by site. The fact, stated as
a rule instead:

1. **No design sentence in this document is normative, and none of them ever was.**
   [`speech-integration-spec.md`](speech-integration-spec.md) §10.5 and §10.6 are the specification;
   every *"the mechanism is…"*, *"the step must…"*, *"the corrected protocol…"* and *"this is what
   §10.5 should say"* below is a **proposal made on 2026-08-25**, and the spec has since re-derived
   several of them from evidence this document does not carry. **Where the two agree, this document's
   version is redundant. Where they differ, the spec wins and this document is the record of what was
   measured against the older shape.** A reader who needs to know what to build reads the spec; a reader
   who needs to know what was observed reads this. That rule holds for a spec change nobody has made
   yet, which is the point of stating it as a rule.
2. **Every measurement in this document stands on its own**, because a measurement is a record of what
   a machine did on a date and no later decision can reach back and change it. The latency tables, the
   `bind()` failure, the eight-hook contention result, the handoff and spawn intervals, the lead times,
   the warm-up costs: none of these is superseded by anything, and **over-qualifying them would make
   this document useless as the evidence it exists to be.** Nothing below is hedged for the sake of
   symmetry.
3. **The trap is the THIRD category, and it is the only one a rule cannot pre-empt: a measurement whose
   NUMBER survives while its EVIDENTIAL SCOPE does not.** *What* was measured is fixed; *what it is
   evidence about* is a claim about the mechanism, and it goes stale exactly when the mechanism does.
   Item 3 below is the worked example — 0.079 s and 0.086 s are both still measured and neither bounds
   how long stale audio can last, because the region they bound is not the region the orphan runs in.
   **These are the sites that need re-qualifying, and there is no rule that finds them in advance**;
   they have to be checked against the spec each time a mechanism moves. The per-section verdicts below
   are that check, performed on 2026-08-26.

**What this document's own arm measured, and what therefore survives untouched.** Two things, and
neither is in question:

- **synthesis and playback latency from a seeded buffer** — the cold / warm / warmed-during-turn TTFA
  tables, `create()` at 0.49–4.23 s, the player spawn at 6–38 ms (median 9.15 ms, n = 38), the
  hook-to-worker handoff at median 0.079 s, the 1.33–2.02 s worker startup, and the model-load and
  warm-up costs;
- **the hook's own wall cost** — 0.063–0.219 s, median 0.086 s, already separately qualified by the
  as-of note under *What the hook itself costs*.

Both are facts about **latency**, and none of them depends on which file a player's pid is written to.

**What does NOT survive.**

1. **The single shared pid file is gone.** §1b (c), §10.5's clause 7 and §10.6 below all propose one
   path, `$BUF_ROOT/<session_id>/speak/pid`, written by the worker after it spawns the player. The spec
   now says **one shared `speak/pid` must not be used**: the record is **per player**, at
   `speak/playerdir/<pid>.<nonce>`, published by the **player's own wrapper** before it can make a sound
   and unlinked **only by exact name** — an older player's reap otherwise erases a newer player's
   registration — with a **process-group sweep** by each newly elected worker as the thing that reaches a
   player no record names (spec §10.5 clause 7(i) and 7(iv), §10.6).
2. **The two kills do NOT partition the timeline.** The table in §1b (d) and the closing sentence of the
   §10.6 subsection below both claim that a hook-side kill and a claim-time kill divide every publication
   instant between them at the `speak/pid` write. **That is measured false.** There are **three** regions,
   not two, and the third is a worker that dies between `Popen` and the record's publication, leaving a
   player **nothing reaches** — `C8`, plays to completion **12/12**, the window itself a median
   **1.41 ms**, range 0.43–5.61 ms, n = 72. Neither a single player-written record (`C11b`) nor per-player
   records alone (`C12c`) closes it, both failing 12/12 at full length; the process-group sweep does —
   `C12b` kills before `exec`, 12/12, never started.
3. **So neither 0.079 s nor 0.086 s bounds how long stale audio can last — and that is a tag-honesty
   correction, not a wording one.** Both figures stay measured; what changed is what they are evidence
   *about*. They bound the two regions in which **something still holds a reference to the player** — a
   published record, or the worker's own child handle — and they bound **nothing at all** in the third,
   where the orphan runs for the **full duration of its utterance** (2.50 s in the trial rig, the whole
   thing). Every sentence below of the form *"no stale utterance survives longer than one kqueue wake or
   one hook wall cost"* is wrong for that reason, not because either number is wrong.
   - **The same range was ALSO used the other way round, and that use is withdrawn as of the tenth
     review round.** §1b (d)'s interleaving argument cited 0.063–0.219 s as *"the hook's own wall cost
     between its kill and its rename"* to show the `R → W` window is **wide** enough to contain the
     worker's `S → P`. The range is `t0` to the hook's **last trace line** — the whole process — and
     `R → W` is a strict sub-interval, so the number does not measure that window; and a whole-hook
     duration is an **upper** bound on a sub-interval that ends inside the hook, which licenses no
     lower bound at all. **The direction is what has to be checked, not the presence of a caveat**: the
     same range used as a *ceiling* on time-to-kill (§1b (c), and the two-row table) is sound and is
     separately qualified; using it as a *floor* is not. The conclusion is carried by
     `C4_noclaimkill` — 12/12 at full length — and the site now says so.
4. **§2a's stale-lock recovery was falsified as well, both clauses.** The probe's own protocol ended
   without exactly one owner in **121/400** trials; **the two clauses §2a proposes, in 61/400.** The
   initializing-lock retry is clean to a 50 ms stall (180/180) and then **40/40 wrong** at 200 ms and
   1000 ms; the quarantine rename is **20/20 wrong** on the ABA, with a committed trace of a reclaimer
   quarantining the other reclaimer's *live* lock. **The worst case was 3 owners, not 2** — 2 is the
   number this document's own closing condition predicts, under *What I could not measure*. The replacement
   is a `symlink`ed generation record, superseded rather than removed: **0/400 wrong** (spec §10.5
   clause 2, §13 row 21) — **and that figure must not be quoted bare, because the path this replacement
   exists to provide is trace-confirmed on 1 trial of 100.** All **100** reclamation trials — S3 (20),
   S4 (20), S6 (60) — staged their dead incumbent by a **clock**, and the defect is asymmetric: a
   mis-staged trial yields exactly the `1 owner` a genuine pass yields, so a clean cell cannot by itself
   separate *"survived a stale-observation reclamation"* from *"never saw one"*. One of the hundred has a
   committed per-trial trace and it settles that trial — `lock-S3_aba-proposed-r1.tsv`, both racers
   classifying the incumbent `pid_dead` and one publishing `gen=1 superseded=0` and taking ownership —
   so the count is **1 confirmed, 99 unconfirmed**, not zero. **0/400 wrong is therefore true**
   (mis-staging can hide a failure, never invent one) **and is evidence for the reclamation path on a
   sample of one rather than on none**; row 21 stays ship-blocking on that arm (spec §13 row 21(b)).
   **§2's `mkdir`-under-contention result is untouched** — 8 hooks → 1 owner is a
   result about exclusive create under contention, and the replacement still elects by exclusive create.

**What the trials CONFIRMED, because it is the other half of the record.** The **claim-time kill of §1b
(d) is load-bearing**: without it the stale player runs to completion **12/12** (`C4_noclaimkill`), a
full 2.50 s. And the **hook-side kill of §1b (c) is a real latency win**, reaching the player a median
**134 ms** sooner than the worker's next claim would (123–143 ms, n = 12, `C2_hookside`). So (d) is
confirmed necessary and (c) confirmed valuable; what is falsified is the claim that the *pair* is
**sufficient**, and the file they were told to use.

### Every design section, checked against the spec — a snapshot dated 2026-08-26

Rule 1 above covers all of these without needing a row each; the rows exist because rule 3 does not, and
a reader deciding whether to trust a particular sentence needs to know which of the three categories it
falls in. **The verdict column is the snapshot and will go stale; the rule column will not.**

| section | its design, against the spec | its measurement |
| --- | --- | --- |
| **§1** — the address is a file | **RE-DERIVED UNCHANGED.** Spec §10.5 clause 1 and §10.2 specify the same temp-name-plus-`rename` onto `speak/job`, the same coalescing account, and the same consumer claim by `rename(job, job.taken.<pid>)` unlinked only by its private name | **stands on its own.** 116 bytes against a 104-byte `sun_path`, `bind()` fails **[obs]**. Nothing in the replacement shortens that path — the generation records and `playerdir/` go *deeper* than the flat `speak/` this was measured in (spec §10.2) — so the figure is a floor |
| **§1b** — coalescing and claiming | **(a) re-derived; (c) and (d) FALSIFIED**, items 1–3 above and the block already at that section. **(b) and (d)'s clause list re-scored in review round ten**: the pre-spawn re-check is an **optimisation given the election sweep**, not a requirement (spec §10.5 clause 7(ii)), and *"(i) and (ii) are both required"* is corrected at the site | the eight-hook coalescing result stands; the two intervals do **not** bound stale audio (rule 3, item 3), **and (d)'s use of the hook's whole-process range as a FLOOR on its own `kill`-to-`rename` sub-interval is withdrawn** — item 3's sub-bullet |
| **§2** — the election | **SUPERSEDED in its primitive.** `mkdir` with a pid written inside and checked by `kill -0` became a `symlink`ed `worker.lock.<gen>` carrying `<pid>.<starttime>`, superseded rather than removed (spec §10.5 clause 2). The two sentences that survive are which of the pre-check and the exclusive create is load-bearing, and that the pre-check is worth keeping anyway | **survives CONTINGENTLY, and the contingency is worth seeing rather than rediscovering: 8 hooks → 1 owner is a result about exclusive create under contention, and it survives only because the replacement also elects by exclusive create.** Had the spec elected by anything else the result would have been about a primitive nobody uses. It is also **no longer the only evidence for that property** — spec §10.5 clause 2 re-measured it on `symlink(2)` at N = 2, 4, 8 and 16, **1 owner on 80 of 80** **[trials]** |
| **§2a** — stale-lock recovery | **BOTH CLAUSES FALSIFIED**, item 4 above and the block already at that section | the *diagnosis* stands — the probe's own protocol ends without exactly one owner in 121/400 — and the *repair* does not, at 61/400 |
| **§3** — the `kqueue` wake | **RE-DERIVED UNCHANGED, and its role WIDENED.** Spec §10.5 clause 3 specifies the same `EVFILT_VNODE`/`NOTE_WRITE` over the speak directory with the same 1 s poll as a belt, and adds two jobs this document did not know it was doing: it is the primitive §3.5.1's bounded wait runs on, and the 1 s poll is the belt that fires when `rewrite.sh:117` sweeps a live worker's directory (spec §10.5 clause 6, §13 row 24). **A widened role owes no qualification** — nothing here is withdrawn | median 0.079 s, range 0.059–0.198 s **[hook]**, stands as a latency figure. Rule 3 applies to it and only there: it does **not** bound how long stale audio can last (item 3) |
| **§4, §4a–c** — the warm-up trigger | **THE TRIGGER SURVIVES; ITS PLACEMENT AND ITS LIVENESS CHECK DO NOT.** Detail in the clause-4 note under *§10.5 — the OPEN heading comes off*, and in §4b | **stands on its own, and it is the largest surviving block in the document**: the 5.16–6.23 s first-invocation lead, the 0.006–0.012 s final-invocation lead and its −0.066/+0.086 s spread over sixteen turns, the 3.05–4.62 s ready lead, the five first-turn TTFAs, turn 31 and the 4.489 s cold short turn. §4c's stated limit is the spec's STATED LIMIT, in the same terms and with the same n = 8 startup range |
| **§5** — the startup warm-up | **STRENGTHENED, not superseded**: *recommended* → **REQUIRED** (spec §10.5 clause 5). Its closing verdict is withdrawn by this document's own `cold7` pair | the 0.78–1.12 s cost and the 2.13-against-1.41 s first-synthesis pair stand |
| **§6** — the idle exit | **INTERVAL, REASON AND CLOCK all superseded**, and the reason measured false (spec §10.5 clause 6, §13 row 24) | *"not measured"* was true of this arm and stays true; the measurement that falsified it is not this document's |

**Where this leaves the file, stated rather than implied.** Rules 1 and 2 are closed: a future spec
change to the job file, the election, the wake, the trigger, the warm-up or the idle exit needs **no edit
here**, because rule 1 already disclaims every design sentence in the document as a class and by name,
and rule 2 already protects every measurement. **The residual is rule 3, and it is not closable by any
structure**: when a mechanism moves, some measurement in this document may turn out to have been evidence
about that mechanism rather than about latency, and only a read of the spec against the site can tell.
Three of the eight rows above carry a rule-3 note — §1b's two intervals, §2's contention result, and §3's
handoff, which is one of §1b's two seen from the other side — and §2's survives on a coincidence of
primitive rather than on anything anyone chose. **That is the honest residual: the
verdict table needs re-checking whenever §10.5 or §10.6 changes; the rest of this document does not.**

**Nothing below is deleted.** A measurement taken against a superseded mechanism is still evidence about
latency; it is simply not evidence about preemption coverage. The spec's §13 rows 20, 21 and 27 are where
the falsification and its remaining residues live.

---

## How each fact below was established

| tag | source | what it can and cannot prove |
| --- | --- | --- |
| **[hook]** | a `Stop` hook fired by Claude Code 2.1.245 in a driven session, 2026-08-25, its own clock read in-process | proves what **this** hook did on **this** machine on **this** build; a stopwatch reading, not a claim about other hardware |
| **[bench]** | `bench/first-sentence.py`, re-run the same afternoon on the same machine as a control | establishes that today's machine reproduces §4's published figures, so the two are comparable |
| **[obs]** | a one-off observation outside the driven session — a `bind()` that failed, eight processes racing, a pid still alive | proves a thing **happened once**; a single sample can never prove a thing always happens |
| **[rig]** | read out of the throwaway probe's own source — `speakd.py`, `speak-probe.sh`, `warm-probe.sh` — which is **not** in this repository | proves what the thing that produced the numbers above actually did; it is not evidence about any shipped file, and the probe is not the specification |
| **[repo]** | read out of this repository's own files | proves what the code says, not what it does |
| **[inferred]** | a reading, not a run | the weakest tag here; used where I could not measure |

**The rig**, so the numbers can be attacked:

- `speak-probe.sh` — a throwaway `Stop` hook that walks §10.3's ordered steps and then drops a job
  and exits. It walked what were then steps 1–9; §10.3 was renumbered when preemption moved above
  the content-based exits, so the range is quoted here as it stood when the probe ran rather than
  silently renumbered — the probe is not re-run by that edit. Written in `zsh -f`, **not** bash, for one reason: bash 3.2 is the only bash on this machine
  and has no in-process high-resolution clock, so `t0` would have had to come from a subprocess spawned
  *after* the thing being measured started. `zmodload zsh/datetime; t0=$EPOCHREALTIME` is read on the
  script's second line. The shipped `speak.sh` is specified as bash (§10.2) and this changes nothing
  about that — the substitution exists to get an honest `t0`, and the hook's own wall cost is reported
  separately below.
- `warm-probe.sh` — a throwaway `MessageDisplay` hook that does **one** thing: ensure the resident worker
  exists, then append a trace line. It **parses no payload** — it does not read `.final`, `.delta` or
  anything else, and never invokes `jq`. This matters more than it looks: it means the warm-up trigger
  the numbers below measure fires on **every** `MessageDisplay` invocation, not on §3.1's publish point,
  which is why §4a exists.
- `speakd.py` — a throwaway resident worker in the Kokoro venv, importing `bench/sanitizers.py` and
  `bench/first-sentence.py`'s `first_sentence()` so the text handed to `create()` is produced by
  literally the same code #9 and #13 ran. Neither bench file was edited.
- The text spoken is a **real corpus rewrite**, seeded into `$SPEAK_DIR/rewrite` — the exact file at
  the exact path §3.1 specified `rewrite.sh` publishes **at the time this ran**. Like the step range
  above, that path is quoted as-of: §3.1 has since replaced the mutable `rewrite` buffer with a
  content-addressed `speak/rw.<H>`, and this probe was not re-run against it. What the arm measures is
  synthesis and playback latency from a seeded buffer, which does not depend on how the buffer is
  named. `rewrite.sh` is not running in a driven session, so
  the driver seeds it; the hook then resolves text through §3.5's table and takes the buffered rewrite,
  which is the production path. The `last_assistant_message` of the driven turn is read, checked and
  logged (it is how the hook is proven to have fired) but is not what gets synthesized.
- **TTFA is defined exactly as `bench/README.md` defines it** — `sanitize` + `Kokoro.create()` +
  `soundfile.write()` + player spawn — **plus** everything the hook itself costs, which is the part
  §4 has never included. Model load is excluded from the warm rows and reported separately; in the
  cold rows it is inside the number, because that is what cold means.
- The player really is spawned (`afplay -v 0.02`), so unlike #9's figures these are not lower bounds
  by the spawn cost. `afplay`'s own latency between `Popen()` returning and sound leaving the speaker
  is **not** measured and is not in any number here — same exclusion `bench.py` makes.

**Positive proof the hook fired**, because a hook that silently never ran looks exactly like one that
measured zero: every invocation appends to a trace file before doing anything, and each trace line
carries the length of the payload's `last_assistant_message`. Driving the session with *"Reply with
exactly these three words and nothing else: cold turn one"* produced `lam_chars=13`. Thirteen is the
length of `cold turn one`. **[hook]**

---

## The control: today's machine reproduces §4

Before trusting any from-hook number, the bench harness was re-run on the same machine the same
afternoon, `bf_emma`, first-sentence mode, twelve real rewrites.

| | §4 (published, #13) | control, 2026-08-25 **[bench]** |
| --- | --- | --- |
| under 3 s | 12/12 | **12/12** |
| median TTFA | 0.86 s | **0.85 s** |
| max TTFA | 1.20 s | **1.25 s** |
| RTF | 0.22–0.29 | **0.242–0.295** |

So the machine is the same machine. **This is a comparability control, and that is all it is.** It
establishes that today's hardware reproduces §4's published figures, so the bench column and the hook
columns are measured against the same baseline and can be put side by side at all.

**It does not isolate the hook as the cause of the difference, and an earlier draft of this document
said it did.** That was wrong, it was caught in review of this PR, and the review was right. Same
hardware is not causal isolation. Two confounds are visible in this document's own data:

- **Load.** The paragraph immediately below reports the same bench item moving from **4.05 s to 1.25 s**
  on nothing but machine load. A confound that large swamps the ~0.37 s bench-to-hook gap the
  comparison is trying to attribute.
- **Cadence.** The bench harness runs twelve items back-to-back in one process; the driven session
  issued turns seconds to minutes apart. `Kokoro.create()` is measurably faster in a back-to-back loop
  — that is part of what the gap is made of — so the two columns differ in *how* they were run, not
  only in *whether a hook was involved*.

**What would actually license a causal claim**, and was not run: **interleaved paired runs** — the
same corpus item synthesized alternately through the bench harness and through the hook, A/B/A/B within
one session, so load and cadence are shared between the arms and only the hook differs. Until that
exists, read the bench-to-hook gap as *associated with* the hook path, decomposed below by reasoning
rather than by isolation. Listed in *What I could not measure*.

One caveat on the control and on every synthesis in this document: the sanitizer used is **`base`**,
not the settled #13 combination, because §13 row 1 is still open — *the settled combination has never
been registered as a variant and does not exist to call*. The sanitizer affects the `sanitize` phase,
measured at **0.2–9.2 ms** across every row here, and the length of the first sentence. It does not
move TTFA at this resolution. If row 1's implementation changes the split point materially, these
numbers are owed a re-run; I do not expect it to.

**A second caveat, and it is the one that bit hardest.** The control was run twice. The first run
returned 11/12, median 0.95 s, with `r01` at **4.05 s** — and `bench.py`'s own contention detector
flagged it (`RTF HIGH, rerun`). The second run, eight minutes later, returned the clean table above.
**Nothing changed but the machine's load.** Every number in this document has a 1-minute load average
attached in the raw data for exactly that reason, and the load-sensitivity section below is not a
footnote.

---

## The mechanism

**Picked: a lazy, self-electing, per-session resident worker, addressed by a file drop inside
`$BUF_ROOT/<session_id>/speak/`, started by whichever hook first finds it missing — and started from
*every* `MessageDisplay` invocation, including the non-final ones, not only from `Stop`.**

Every part of that sentence is doing work. Taken in order:

### 1. The address is a file, not a socket and not a port

> **NOTHING IN THIS SUBSECTION IS SUPERSEDED, and saying so is worth a line** because §1b, §2, §2a, §4,
> §5 and §6 all are (*SUPERSEDED* at the top). Spec §10.5 clause 1 and §10.2 re-derive the same job file,
> the same producer rename, the same coalescing account and the same consumer claim-rename. The 116-byte
> `bind()` failure is a measurement and stands regardless; the replacement mechanisms put records
> **deeper** than the flat `speak/` measured here, never shallower, so it is a floor.

**Measured, and it decides the question by itself.** The obvious shape for "a resident worker a hook
talks to" is a Unix domain socket at `$BUF_ROOT/<session_id>/speak/sock`. On this machine that path is
**116 bytes**, and Darwin's `sun_path` is **104**:

```c
char            sun_path[104];  /* [XSI] path name (gag) */
```
— `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/un.h:79`

```
path len 116
bind FAILED: OSError AF_UNIX path too long
relative bind OK
```
— **[obs]**, `bind()` attempted at the real `$BUF_ROOT` depth with a real session UUID

`$BUF_ROOT` is `"${TMPDIR:-/tmp}/claudish-to-english"` (`rewrite.sh:69`, **[repo]**), `TMPDIR` on macOS
is a 49-byte per-user path, a session id is 36 bytes, and `/speak/sock` is 11. The sum is over the
limit before anyone has done anything wrong. There is a workaround — `chdir()` into the directory and
bind the relative name, which the probe above confirms works — but it means the hook side needs
`nc -U` and a `cd`, and it buys nothing a file cannot do.

So: **the hook writes the job to a temp name in the speak dir and `mv`s it onto `speak/job`.** That is
`rewrite.sh`'s own idiom, it is inside the depth-2 directory §3.1 already reclaims, and `rename(2)`
within a directory is atomic.

**What the producer rename buys is coalescing, and coalescing is not §10.6.** An earlier draft of this
document said latest-wins "falls out for free, and it is exactly §10.6". That was wrong on both halves.
It was caught in review of this PR, the review was right, and the corrected account is the subsection
below — which is now the most intricate part of the mechanism and was previously its most hand-waved.

### 1b. Coalescing, claiming, and what §10.6 actually needs

A rename onto `speak/job` replaces whatever is at that path. That settles exactly one of the three ways
a newer job can arrive:

| a newer job arrives while the older one is… | what the producer rename settles |
| --- | --- |
| **unconsumed** — still sitting at `speak/job` | settled: the older text is replaced and never spoken. *n* drops, one utterance |
| **being synthesized** — claimed, inside a blocking `create()` | nothing. The rename cannot un-claim it |
| **playing** — `create()` done, player running | nothing. The rename cannot stop a process |

**[obs]** covers row one and only row one: eight simultaneous hooks against an empty speak dir produced
**one** utterance, and it was the newest job's. That is a *coalescing* result. The worker was cold, all
eight renames landed inside its 1.33–2.02 s startup, and **nothing had been consumed while they raced**
— so the observation is silent about rows two and three, which the driven session never exercised
either: turns were issued sequentially, one job per turn.

Rows two and three need three further things, and only the first of them was in the probe.

**(a)–(d) below are the design that was MEASURED and partly falsified, not the design that is specified**
— the shared `speak/pid` of (c) is replaced by per-player `playerdir/` records plus a process-group
sweep, and the partition claim of (d) is measured false. Read *SUPERSEDED* at the top of this document
once; the sites below point back at it rather than repeating it.

**(a) The consumer needs its own atomic step. The probe had one; the earlier draft failed to write it
down.** `speakd.py` claims a job by `os.rename(job, job.taken.<pid>)` and then unlinks *that private
name* — never `speak/job` (**[rig]**, `read_job()`). This is load-bearing rather than tidy: a worker
that read `speak/job` and then unlinked `speak/job` would delete a job a hook had renamed into place
between the read and the unlink, and that job is then **lost outright** — no further rename is coming,
and the kqueue event that announced it has already been spent. Review of this PR raised exactly that
failure mode. It does not occur in what was measured, but only because of a line the design text
omitted, so: **the claim rename is part of the mechanism, not an implementation detail.**

**(b) Re-check for a newer job after synthesis and before spawning the player.** **[inferred]** — this
is reasoned, not measured, and it is the piece that actually delivers row two. The probe's loop calls
`read_job()` only at the top, so a job arriving mid-`create()` goes unnoticed until the older utterance
has been synthesized *and spawned*; the stale audio starts, and dies only when the newer job's own
synthesis completes. One `stat()` of `speak/job` between `create()` returning and `Popen` fixes it: if a
newer job is waiting, **discard the finished wav and never play it.** The window in which a badly-timed
arrival still produces audible stale speech shrinks from the whole of `create()` — **0.49–4.23 s** on
the rows measured here — to the gap between that `stat()` and the spawn, which is the measured spawn
cost, **6–38 ms, median 9.15 ms** (n = 38 — the 39th row is the offline concurrency probe, excluded
from every aggregate in this document by name, and **8.9 ms** is what its inclusion gives). That
narrows the race by two to three orders of magnitude.
It does not close it, and saying otherwise would repeat the mistake this subsection exists to correct.

> **This clause SURVIVED the trials; only its status changed** (*SUPERSEDED* at the top). The spec keeps
> the re-check and reclassifies it: with the worker surviving, removing it changes nothing —
> `C5_norecheck` still kills before the player can `exec`, 12/12 — while with the worker dying after the
> spawn and no process-group sweep, removing it **creates an orphan nothing kills**: `C15b` runs to
> completion 12/12 at 2.50 s where `C15a`, the re-check present, spawns no player at all. So it is an
> optimisation given the sweep and a correctness clause without it. **The 6–38 ms residual measured
> above is this machine's spawn cost and is untouched by any of that**, and *"reasoned, not measured"* is
> no longer true of the clause — only of this document's evidence for it.

**(c) Keep §10.6's `speak/pid` and its hook-side kill, and reassign only the writer.** **[inferred]**.
Row three — a newer message while the older is *playing* — is the case §10.6 already specifies, and its
mechanism survives residency intact: the pid file at `$BUF_ROOT/<session_id>/speak/pid`, killed by the
next hook invocation before it drops its job. What changes is **who writes it.** §10.6 says "the speech
child"; under residency there is no per-turn speech child, so **the worker writes the player's pid
there** after spawning it. With that, playback already in progress dies within the hook's own wall cost
— **median 0.086 s, max 0.219 s** measured, which is a **historical baseline** and not a figure for the
specified hook, whose cost is **unmeasured** (see the as-of note under *What the hook itself costs*) —
and the *tighter* claim against the worker-side kill the probe used never rested on either number: it
rests on **order**, because the hook runs before the worker has noticed anything at all. **But it is not a
replacement for the worker-side kill, and an earlier draft of this document treated it as one.** That
error is corrected in (d).

> **HISTORICAL. What was measured, what replaced it, and what the measurement still establishes**
> (*SUPERSEDED* at the top). **Measured here:** the hook's own wall cost, median 0.086 s, max 0.219 s.
> **Replaced:** the file and the writer. `speak/pid` — one shared path, written by the worker after the
> spawn — **must not be used**; the record is per player at `speak/playerdir/<pid>.<nonce>`, published by
> the **player's own wrapper** before it can make a sound and unlinked only by exact name, and the region
> no record covers is closed by a **process-group sweep**, not by this kill (spec §10.5 clause 7(i),
> 7(iv)). **What still holds:** the *hook-side* kill is worth having, and the trials put a number on the
> value this paragraph argued for qualitatively — it reaches the player a median **134 ms** sooner than
> the worker's next claim would (123–143 ms, n = 12, `C2_hookside`). **What does not:** 0.086 s is not a
> bound on how long stale audio can last. It bounds the case where the hook finds a live record, which is
> one of three regions, and bounds nothing in the region where no record exists.

**(d) Keep the worker-side kill as well, and move it to job-claim time. [inferred]** Review of this PR
found a hole in (b)+(c) taken together, and the hole is real.

> **The RULE this subsection derives is CONFIRMED; the PARTITION it closes with is FALSIFIED**
> (*SUPERSEDED* at the top). The claim-time kill is load-bearing, measured: without it the stale player
> runs to completion **12/12**, a full 2.50 s (`C4_noclaimkill`). The interleaving argument below is
> therefore sound as far as it goes, and the ordering walk-through is the reasoning that found a real
> hole. **What is false is the closing move** — that (c) and (d) between them *partition* the timeline at
> the `speak/pid` write. There is a **third** region neither reaches, and the paths below are read against
> a file the spec has since removed: read the walk-through's `speak/pid` as *"the player's published
> record"* throughout, and the two-row table as *two of three regions*.

Write out the two orderings. The hook, per
§10.6, does *kill the pid in `speak/pid`*, then *rename the job onto `speak/job`*. The worker, per (b),
does *`create()`*, then *`stat(speak/job)`*, then *`Popen`*, then *write `speak/pid`*. Now let the hook
read the pid at time **R** and publish at time **W** (R < W), and let the worker stat at **S** and write
the pid at **P**. The interleaving **R < S < P < W** is unguarded:

1. The worker finishes `create()` for job J1 and stats `speak/job` — empty. It will spawn.
2. The hook for J2 reads `speak/pid` — absent, or a pid from a player that already exited. **Its kill
   hits nothing.**
3. The worker spawns player P1 for the *stale* J1 and writes P1's pid to `speak/pid`.
4. The hook renames J2 onto `speak/job`.

**P1 is now playing stale audio and no specified step kills it.** The hook's one kill is spent; the
worker's pre-spawn stat already passed.

> **The interval arithmetic that used to close this paragraph is WITHDRAWN, and the trials carry the
> conclusion instead.** It read: *"R < S < P < W is not a hair-splitting window: the hook's own wall
> cost between its kill and its rename is 0.063–0.219 s, median 0.086 s measured … the wide window is
> the hook's, and it comfortably contains the narrow one."* **Two things are wrong with it.** The range
> is `t0` to the hook's **last trace line** (*What the hook itself costs*) — the whole process — and
> `R → W` is `kill` to `rename`, a strict **sub-interval** of it, so the number was cited for a
> quantity it does not measure. And the argument needs `R → W` to be **large** enough to contain
> `S → P`; a whole-hook duration is an **upper** bound on a sub-interval that ends inside the hook and
> therefore licenses no lower bound at all. Nothing in this document measures `R → W`, and the `S → P`
> side had no number here either (the spawn is measured at **6–38 ms, median 9.15 ms**, n = 38, under
> §1b (b), but a comparison needs both sides). **What does carry it is `C4_noclaimkill`: with the
> claim-time kill removed, the stale player runs to completion 12/12 at a full 2.50 s** **[trials]** —
> which the review block at the head of **(d)** already says, and which is a demonstration that the
> hole is reachable rather than an argument that the window is wide. **Third instance of one shape in this document** —
> the 0.079 s / 0.086 s pair quoted as a bound on how long stale audio can last (item 3 above), the
> withdrawn *"lower bound"* on the specified hook, and now this: a measured number cited for a quantity
> it does not measure. **The direction is the thing to check.** The same
> range used as a *ceiling* on a sub-interval that ends inside the hook — §1b (c) and the table below —
> is sound in direction, and is separately qualified as a historical baseline; it is using it as a
> *floor* that has no support.

A *post*-spawn stat — repeating the check after writing `speak/pid` — closes step 3/4 but not this
ordering, because the hook's rename can still land after that second stat. What closes it is not another
stat but a standing rule:

> **The worker kills the currently playing player as soon as it claims a newer job, before synthesizing
> it** — the probe's `_PREV_PLAYER.kill()` (**[rig]**, `speak()`), retained, but hoisted from spawn time
> to *claim* time.

With that, the timeline has no gap, because the two kills partition it at the `speak/pid` write:

| J2 published… | who kills the stale player |
| --- | --- |
| before the worker writes `speak/pid` | the **worker**, on claiming J2 — one kqueue wake after publication (handoff median **0.079 s**) |
| after the worker writes `speak/pid` | the **hook**, directly — within its own wall cost, median **0.086 s** measured on the hook the probe ran; the specified hook's cost is unmeasured and this cell has no number for it (as-of note under *What the hook itself costs*) |

> **FALSIFIED, 12/12, and this table is the sentence the trials were pointed at** (*SUPERSEDED* at the
> top; spec §13 row 20). There is a **third row** it does not have: **the worker dies between `Popen` and
> the record's publication**, which leaves a player nothing reaches — the record was never written, so no
> hook can find it, and the worker that held the child handle is gone. `C8`, plays to completion
> **12/12**; the window itself is a median **1.41 ms**, range 0.43–5.61 ms, n = 72. **So the two figures
> in this table bound two of three regions and bound nothing in the third**, where the stale player runs
> for the whole of its utterance — 2.50 s in the trial rig. Both numbers stay measured; what is withdrawn
> is their use as a bound on staleness. Nor does moving the write into the player close the third region:
> a single player-written record (`C11b`) and per-player records alone (`C12c`) both fail 12/12 at full
> length, because the wrapper can stay descheduled between `Popen` and its own first instruction. **What
> closes it is process-group membership**, which `fork(2)` establishes before the child executes an
> instruction — `C12b` kills before `exec`, 12/12, never started.

So (c) is a latency optimisation that fires when it happens to see a live pid; **(d) is the correctness
guarantee**, and it is the worker's, because the worker is the only party that knows it spawned a
player. Adding a post-spawn stat as well is cheap and worth doing — it catches the common case without
waiting for a wake — but it is not what makes the mechanism sound. **§10.6's semantics need both the pid
file and the worker-side kill; residency should drop neither.** (Both halves of that last sentence hold
in the spec's replacement — a record and a claim-time kill — but *"neither"* was one short: it needs the
election-time process-group sweep as well, and the sweep rather than the record is what makes it sound.)

**What remains genuinely OPEN, and it is smaller than it looks — but not as small as the earlier draft
claimed.** Interrupting an in-flight `create()` is not solved by any of (a)–(d), and I am **not**
specifying it: the two candidates I can see both carry costs nothing here has measured — synthesizing in
a killable child forfeits the residency this document just bought, since the child cannot hold the
model, and chunking the text to check between chunks interacts with `kokoro_onnx._split_phonemes` in
ways nobody has looked at.

**The earlier draft said (b) and (c) leave "no stale utterance played" and reduce cancellation to
"latency only, not correctness". That was wrong, because it depended on the hole (d) closes.** The
corrected statement, and it is **[inferred]** throughout — none of (b), (c) or (d) has been measured:

- With (a)–(d), **no stale utterance survives longer than one kqueue wake or one hook wall cost after
  the newer job is published** — bounded by the measured **0.079 s** and **0.086 s** respectively, the
  second of them a **historical baseline** rather than any bound on the specified hook, whose cost is
  **unmeasured** (as-of note under *What the hook itself costs*), plus
  a residual **6–38 ms** window between the pre-spawn stat and the spawn in which a player starts at all.
  On that reading §10.6's semantics hold.
- **Only then** is synthesis cancellation reduced to a latency question — the *newer* utterance waiting
  out up to one wasted `create()`, 0.49–4.23 s. **Without (d) it is a correctness question**, because a
  stale utterance plays to completion unkilled.

> **The first of those two bullets is FALSE and the trials are what made it false** (*SUPERSEDED* at the
> top). It is the same claim as (d)'s table and it fails the same way: in the orphan region — worker dead
> between `Popen` and the record's publication — the stale utterance survives **for its full duration**,
> so **no** figure measured in this document bounds it. That makes this a tag-honesty defect and not a
> phrasing one: **0.079 s and 0.086 s are honest [hook] measurements of a wake and of a hook, and were
> never measurements of staleness.** The second bullet's *"without (d) it is a correctness question"* is
> confirmed — `C4_noclaimkill`, 12/12 at full length — and its 0.49–4.23 s `create()` range is this
> document's own measurement and stands. The corrected statement is the spec's: five worker-side hooks,
> not three, with the process-group sweep of §10.5 clause 7(iv) as the only thing that reaches the third
> region.

**Routed to §10.6 as OPEN with that reduced scope stated, and with the reduction explicitly conditional
on (d) shipping.** The measurement that would confirm or refute (b), (c) and (d) is named in *What I
could not measure* below. **That measurement has since been made** — 312 preemption trials over 26
configurations — and the verdict is not one word per clause: it **kept** (b), reclassified as an
optimisation given the sweep; **confirmed** (d)'s rule and **falsified** (d)'s partition; **quantified**
the hook-side kill (c) argued for while **replacing** (c)'s shared `speak/pid` and its writer; and
falsified the reduction this paragraph routes. See *SUPERSEDED* at the top and the spec's §13 row 20.

### 2. The election is `mkdir`, and it lives in the worker

`os.mkdir($SPEAK_DIR/worker.lock)` with the pid written inside it, checked with `kill -0` and torn
down if stale. This is §10.6's lock/PID-file idiom, one directory over from the `speak/pid` the
preemption rule already puts there. **Both of those paths are gone from the spec** — the lock is a
`symlink`ed `worker.lock.<gen>` carrying `<pid>.<starttime>` and the preemption record is a
`playerdir/` entry per player (*SUPERSEDED* at the top) — **but the measurement in this subsection is
about exclusive create under contention, and the replacement still elects by exclusive create.**
**That is a contingency and not a guarantee, which is worth naming rather than leaving to be
rediscovered:** the 8/8 result survives *because* `symlink(2)` shares `mkdir`'s exclusive-create
property, and had the spec elected by anything else it would be a result about a primitive nobody uses.
It is also **no longer the only evidence for that property** — spec §10.5 clause 2 re-measured it on the
replacement at N = 2, 4, 8 and 16, **1 owner on 80 of 80** **[trials]**, so this subsection's n = 1
adversarial run is corroborated rather than load-bearing on its own.

**Measured against the adversarial case.** Eight hook processes fired simultaneously against an empty
speak dir:

| | |
| --- | --- |
| hooks that decided to spawn a worker | **8** |
| worker processes launched | **8** |
| elections won | **1** |
| elections lost, exiting immediately | **7** |
| workers alive 12 s later | **1** |
| utterances produced | **1** (the newest job — that is coalescing of unconsumed jobs, not preemption; §1b) |

**[obs]** — and the interesting half is the first row. The hook's own `[[ -d worker.lock ]] && kill -0`
pre-check is a **race-prone optimisation and it lost the race eight times out of eight**. It is worth
keeping, because in the common case it saves a Python interpreter start on every single turn, but
**it is not the guarantee.** The guarantee is the `mkdir` inside the worker, and the seven losers cost
one interpreter start each and were gone in under a second. The spec should say which of the two is
load-bearing, because they look interchangeable and are not.

#### 2a. The `mkdir` is sound. The *stale-lock recovery* around it is not.

Review of this PR found a second race, downstream of the one measured above, and it is real. The
`mkdir` decides the election correctly — that part is measured 8/8. What is unsound is what a *loser*
does next. The probe's protocol, read out of its own source **[rig]**:

```python
try:
    os.mkdir(LOCK)
except FileExistsError:
    try:
        pid = int(LOCK_PID.read_text().strip())
    except (OSError, ValueError):
        pid = -1                      # <-- lock exists but has no pid yet
    if pid > 0:
        ... kill(pid, 0) ... return False
    # stale: tear it down and retry once
    LOCK_PID.unlink(missing_ok=True)
    os.rmdir(LOCK)
    continue
LOCK_PID.write_text(f"{os.getpid()}\n")   # <-- winner writes the pid HERE
return True
```

**The winner's `mkdir` and its pid write are two steps, and a loser that arrives between them sees a
lock directory with no pid inside.** `read_text()` raises, `pid` becomes `-1`, the `pid > 0` branch is
skipped, and the loser falls straight into *"stale: tear it down"*. It `rmdir`s the live winner's lock,
`mkdir`s a replacement, writes its own pid, and returns `True`. **Two workers now believe they own the
session**, both holding a ~340 MB model, both racing `read_job()`'s claim-rename for every job. This is
not the same race as the 8/8 result above: that one is about who wins `mkdir`, this one is about a lock
being *misclassified as abandoned while its owner is starting up*.

It did not fire in anything measured here, and the reason is timing, not design: the winner's pid write
follows its `mkdir` by microseconds, while the seven losers in the eight-hook race each had a whole
Python interpreter start ahead of them. **A window that small is still a window**, and the mechanism is
supposed to survive the adversarial case rather than the lucky one.

**The corrected protocol, in two clauses. [inferred] — reasoned, not measured.**

> **BOTH CLAUSES WERE SUBSEQUENTLY MEASURED AND BOTH ARE FALSIFIED** (*SUPERSEDED* at the top; spec §13
> row 21). 1200 lock trials over three protocols and six scenarios. **What the diagnosis above still
> establishes:** the race is real — the probe's own protocol ends without exactly one owner in
> **121/400** trials — and the misclassification of an initializing lock as abandoned is its mechanism.
> **What the repair does not:** the two clauses below leave **61/400** wrong. Clause 1's bounded backoff
> is clean to a 50 ms stall (180/180) and then **40/40 wrong** at 200 ms and 1000 ms, because a bounded
> wait bets on a live process making progress. Clause 2's quarantine rename is **20/20 wrong** on the
> ABA, because `rename(2)` is path-addressed: a reclaimer acting on a stale observation quarantines a
> *live* lock and gets success — there is a committed trace of one reclaimer quarantining the other's live
> lock. **And the worst case was 3 owners, not the 2 this document predicts.** The replacement is
> §3.1's shape applied here: a record that is created and never mutated, with ownership carried by a name
> — a `symlink`ed `worker.lock.<gen>` holding the owner's `<pid>.<starttime>`, superseded rather than
> removed, **0/400 wrong — a figure that is true and that does not certify the reclamation path on its
> own.** All **100** of the replacement's reclamation trials — S3 (20), S4 (20), S6 (60) — staged their
> dead incumbent by a **clock**, and a mis-staged trial yields exactly the `1 owner` a genuine pass
> yields, so those cells cannot separate *"survived a stale-observation reclamation"* from *"never saw
> one"*. **Exactly 1 of the 100 is trace-confirmed** — `lock-S3_aba-proposed-r1.tsv`, both racers
> classifying the incumbent `pid_dead` and one superseding it — so it is **1 confirmed, 99 unconfirmed**,
> which is not zero and is not a hundred. That is why §13 row 21 stays ship-blocking on arm (b) even
> though the protocol this subsection's two clauses lost to is the one that ships (spec §13 row 21(b)).
> **The generalisation, which is the part worth keeping:** where this document
> guards a shared mutable path with an ordering rule, the ordering rule is the smell — and both clauses
> below are ordering rules over one mutable path.

1. **A lock with no pid file yet is *initializing*, not stale, and must be retried rather than
   reclaimed.** Absence of a pid is not evidence of an abandoned lock; it is the default state of a lock
   for the first few microseconds of its life. Retry the read on a short bounded backoff — a handful of
   attempts over a few tens of milliseconds is orders of magnitude more than the observed write
   latency — and only if the pid is *still* absent at the end of it treat the lock as genuinely
   abandoned, which is the narrow real case of a worker killed between its `mkdir` and its write.
2. **Serialize stale reclamation with an atomic rename into quarantine, never `rmdir`-then-`mkdir`.**
   To reclaim, first `rename(worker.lock, worker.lock.dead.<pid>.<nonce>)` — a unique target name, so no
   two reclaimers can collide on it. `rename(2)` on a directory is atomic and the source path can only
   be consumed once: exactly one racer's rename succeeds, every other gets `ENOENT` and restarts the
   whole election from the top. Only the winner of the quarantine rename then `mkdir`s the fresh lock.
   Clean up the quarantined directory afterwards, and let the 30-minute sweep of §6 catch any it misses.

The `rmdir`-then-`mkdir` sequence the probe used has no such interlock: two reclaimers can both `rmdir`
(one succeeds, one gets `ENOENT` and, in the probe, `return False` — which is at least safe) and, worse,
a reclaimer can `rmdir` a lock that a *third* process has meanwhile legitimately re-`mkdir`'d. The
rename makes "I am the one reclaiming this specific lock" a single atomic fact, which is the same
property the `mkdir` gives the election itself.

**Note what is *not* being changed.** The election stays `mkdir`, in the worker, and the hook's
pre-check stays a best-effort optimisation. The measured 8/8 result is untouched — it is a result about
`mkdir` under contention, and `mkdir` is still the guarantee.

### 3. The wake is `kqueue`, and it costs nothing worth naming

> **NOT SUPERSEDED — re-derived unchanged, and its role WIDENED** (*SUPERSEDED* at the top). Spec §10.5
> clause 3 specifies the same primitive over the same directory with the same 1 s poll, and gives it two
> jobs this subsection did not know it was doing: it is the primitive §3.5.1's bounded wait runs on, and
> **the 1 s poll is the belt that fires when `rewrite.sh:117` sweeps a live worker's directory** (spec
> §10.5 clause 6, §13 row 24) — which is why that belt is the sole guarantee on the sleep path until
> clause 6's repair ships. **One thing the handoff figure below does NOT bound**, and it is the one place
> rule 3 at the top reaches this subsection: how long a stale utterance can last. The 0.079 s bounds the
> region in which something still holds a reference to the player, and `C8`'s orphan is outside it.

The worker blocks on `kqueue(EVFILT_VNODE, NOTE_WRITE)` over the speak directory's fd, with a 1 s
timeout as a belt. A rename into the directory wakes it.

**Measured hook-to-worker handoff, warm: median 0.079 s, range 0.059–0.198 s** **[hook]**. That
interval contains the whole hook — `jq` three times, `shasum`, the job write, the rename — plus the
kqueue wake. It is not the bottleneck and no cleverness is owed here.

### 4. The warm-up trigger is *every* `MessageDisplay` invocation — **not** §3.1's publish point

> **THE TRIGGER IN THIS HEADING IS THE SPEC'S; TWO OF ITS IMPLEMENTATION PROPERTIES ARE NOT**
> (*SUPERSEDED* at the top; spec §10.5 clause 4). Every measurement in §4, §4a, §4b and §4c stands, and
> so does §4c's stated limit — the spec restates it in the same terms. What is superseded sits in §4b's
> inference and in clause 4 of the routing section below: the step's placement is **after `session_id` is
> parsed**, because *"before any parsing"* is not implementable, and its liveness check is a
> `readdir`/`readlink`/`ps` under clause 2's generation record rather than one `[[ -d ]]` and one
> `kill -0`. Each is qualified where it appears.

**A worker started by `Stop` is warm for turns 2..n and cold for turn 1.** That is the whole of the
residency problem, and started-by-`Stop` does not solve it: measured cold median **3.16 s**, over the
line.

But this plugin already has a hook that fires **during** the turn. `MessageDisplay` is invoked once per
streamed chunk, and on a long reply that is five to seven times before the turn ends. If one of those
invocations ensures the worker exists, the model load is paid **while the model is still talking**, and
by the time `Stop` arrives the worker is resident.

**Which invocation, though? That question is the whole of this subsection, and an earlier draft of this
document got it wrong.**

#### 4a. The correction: the publish point has no lead at all

The earlier draft said the trigger was §3.1's publish point — *"`rewrite.sh` publishing the finished
rewrite into `speak/` from `MessageDisplay`, seconds before `Stop` fires"* — and cited the 5.16–6.23 s
lead as evidence for it. **Review of this PR pointed out that the measurement does not measure that
trigger. The review was right, and the gap is three orders of magnitude.** Read `rewrite.sh`:

- **Non-final invocations return before doing anything else.** `rewrite.sh:127-132` — `if [ "$final"
  != "true" ]; then ... emit_empty; else pass_through; fi`, and both of those `exit 0`. **[repo]**
- **The rewrite is published only from the final invocation**, after reconstruction (`rewrite.sh:134`),
  after the prose-length gate, and — decisively — **after `llm_complete` returns** (`rewrite.sh:192`),
  whose default budget is `CLAUDISH_TIMEOUT=45` seconds (`rewrite.sh:65`). **[repo]**
- **There is in fact no `speak/` publish in `rewrite.sh` at all today.** `grep -n 'speak' rewrite.sh`
  returns nothing across all 245 lines. §3.1's publish is proposed spec, not shipped code — consistent
  with `speak.sh` not existing. **[repo]**

So the publish point is the *last* thing that happens in a turn's final `MessageDisplay` invocation.
How much lead does that leave? The rig's own trace answers it, and the answer is: **none.**

| trigger placement, same 5 turns | lead before `Stop` **[hook]** |
| --- | --- |
| **first** `MessageDisplay` invocation of the turn | **5.16 – 6.23 s** |
| **last (final)** `MessageDisplay` invocation of the turn | **0.006 – 0.012 s**, median **0.008 s** |

Across all sixteen turns that had the `MessageDisplay` hook installed, the final invocation's lead is
**−0.066 s to +0.086 s, median 0.0075 s** (n = 16) — it can be *negative*. The final `MessageDisplay` hook process
and the `Stop` hook process are dispatched essentially simultaneously; which one reads its clock first
is a scheduling coin-flip. Every figure here is derivable from `residency-timings.tsv` columns
`t_stop`, `t_first_md`, `t_last_md` (see *Reproducing the leads* below).

**And §3.1's publish is later still than the final invocation's start**, by the whole of the LLM
round-trip. A publish-point trigger would therefore start the worker *after* `Stop` has already fired,
which is strictly worse than triggering on `Stop`.

**Worse, on short turns the publish point never fires at all.** `rewrite.sh:147-156` gates on
`prose_len < MIN_CHARS` (default **200**, `rewrite.sh:63`) and returns without producing a rewrite.
A fifty-character reply produces no publish, ever — so a publish-point trigger provides exactly zero
warm-up on precisely the turns that need it most. **[repo]**

#### 4b. What was actually measured, and what it does support

**The result stands; only the trigger's description changes.** The `MessageDisplay` hook the rig ran is
`warm-probe.sh`, and it **parses no payload at all** — no `.final`, no `.delta`, no `jq`. It does one
thing: ensure the worker exists, then append a trace line. **[rig]**

```zsh
[[ "$CLAUDISH_SPEAK" == "1" ]] || exit 0
mkdir -p "$SPEAK_DIR" 2>/dev/null
started=no
if [[ -d "$SPEAK_DIR/worker.lock" ]] && kill -0 "$(<"$SPEAK_DIR/worker.lock/pid" 2>/dev/null)" 2>/dev/null; then
  :
else
  "$PY" "$RES/speakd.py" "$SPEAK_DIR" "$REPO" </dev/null >>"$SPEAK_DIR/speakd.stderr" 2>&1 &
```
— `warm-probe.sh`, in full but for the clock and the trace line **[rig]**

So what the 5.16–6.23 s lead measures is a **payload-independent ensure-worker step that runs on every
`MessageDisplay` invocation**. That is a real, implementable trigger — and it is the one this document
now specifies. In the trace it is visible directly: on each of those turns the *first* of five to seven
invocations logged `started=yes` and every later one logged `started=no`. **[hook]**

**The mechanism therefore has to be placed before `rewrite.sh:127`'s early return**, not at the publish.
It is cheap enough to belong there: one `[[ -d ]]` test and one `kill -0` in the common case, on a hook
that already runs `jq` several times.

> **Two words in that account do not transfer, and the spec's clause 4 is where each is corrected — the
> LEAD is untouched either way** (*SUPERSEDED* at the top, rule 3; spec §10.5 clause 4). **(1)
> *"payload-independent"* is a property of the RIG, not of the trigger.** `warm-probe.sh` parses nothing
> because the harness that launched it handed it `$SPEAK_DIR` **[rig]**; `rewrite.sh` has no such source
> and must read `session_id` out of the payload at `:108` to know which session's worker to ensure. So
> the specified step parses `session_id` **first** and the requirement is restated as independence from
> the payload's **chunk role** — not from parsing. **(2) *"one `[[ -d ]]` test and one `kill -0`"* is no
> longer the step's cost: clause 2's generation record made it a `readdir`, a `readlink` and a `ps`
> fork, offset by reusing the `$sid` `:108` already parsed. **The code block above is left exactly as
> the rig ran it** — it is the record of what produced the numbers, and editing it would break the only
> thing it is for.

**Measured, on a fresh session with no worker running, driving a 400-word streaming reply:**

| | measured **[hook]** |
| --- | --- |
| first `MessageDisplay` invocation fires, before `Stop` | **5.16 – 6.23 s** |
| worker becomes ready, before `Stop` | **3.05 – 4.62 s** |
| `Stop` finds a resident worker | yes, `started=no`, every time |
| TTFA on that first turn | **1.37 / 1.66 / 1.71 / 2.23 / 3.83 s** — median **1.71 s**, 4/5 under the line |

That is the claim the blocker asks for: **the mechanism moves the cold start out of the user-visible
path on the first turn of a session, not merely on the second** — provided the trigger sits on every
invocation. It is measured rather than argued, and the trigger it is measured for is now the trigger
that is specified. The earlier draft's headline was not supported by its own data; this one is.

#### 4c. Where it still fails, measured, not hypothesised

Drive the same fresh session with a reply of fifty characters and the lead disappears:

```
1787668956.179   Stop hook            process starts
1787668956.243   MessageDisplay hook  process starts     <- 0.064 s LATER
```
**[hook]** — turn 31, TTFA that turn: **4.489 s, cold**.

The earlier draft recorded this as *unexplained*. **It is no longer unexplained, and §4a is the
explanation.** The expectation it violated was that `MessageDisplay` precedes `Stop` by seconds — but
that is only true of the *non-final* invocations. The final invocation is concurrent with `Stop`
(median 7.5 ms across sixteen turns, sign not guaranteed), and a very short reply streams in few enough
chunks that none of them leads the end of the turn. **Read that carefully against the data, because two
routes to the same outcome were being described as one.** On turns 37–40 the short reply produced
`n_md = 1`, so its only invocation *is* the final one, which is the concurrent one. **On turn 31 there
were three** — `n_md = 3`, not 1 — and all three landed after `Stop`'s clock read, all three found no
worker and spawned one, and the election discarded two. So more than one chunk is **not** sufficient:
turn 31 satisfies the first half of the stated limit below and fails the second, because its first chunk
did not lead the end of the turn at all. There is nothing left to explain about hook dispatch ordering;
the ordering is a consequence of when the chunks arrive, which is a consequence of message length.

The practical rule is unchanged and should go in the spec as a stated limit:

> **Warm-up-on-`MessageDisplay` covers the cold start if and only if the turn's message streams in
> more than one chunk *and* the first chunk arrives more than the worker's startup time
> (**1.33–2.02 s** measured, n = 8) before the turn ends. On a very short, very fast first turn there
> is one chunk, it is the final one, it is concurrent with `Stop`, and the first utterance is cold.**

That limit is tolerable, and here is why, stated as reasoning rather than measurement
**[inferred]**: a fifty-character first message is exactly the band §3.3 and §9 are about, and
whichever way §3.5's table resolves it, one late first utterance per session is the worst case. It is
not tolerable to leave *unstated*, which is what §10.5 does today.

#### Reproducing the leads

Every number in §4 is derivable from `residency-timings.tsv` with `awk`, which was not true before this
revision — the file previously carried no absolute timestamps at all. The relevant columns are
`t_stop`, `n_md`, `t_first_md`, `t_last_md`, `t_worker_ready`, the three pre-differenced `*_lead_*`
columns, and `set`, which names the rows behind each published aggregate:

| `set` | rows | reproduces |
| --- | --- | --- |
| `cold7` | 7 | cold: median 3.161 s, range 2.657–5.496 s, 3/7 under 3 s |
| `warm30` **plus** `warm30+mdwarm5` | 25 + 5 = 30 | warm: median 1.216 s, range 0.573–4.014 s, 28/30 under 3 s |
| `warm30` alone | 25 | warm and *not* warmed-during-turn: median 1.085 s, 24/25 under 3 s |
| `warm30+mdwarm5` | 5 | warmed-during-turn: median 1.710 s, range 1.373–3.829 s, 4/5 under 3 s |
| `concurrency-probe`, `slow-cold-outlier` | 1 each | excluded from every aggregate above, by name |

**The label `warm30` selects 25 rows, not 30, and the row above used to say 30** — the warm aggregate is
the union of the two labels, because the five warmed-during-turn rows are warm rows as well. A reader who
filtered on `set == "warm30"` and expected the published 30 got 25 and a median of 1.085 s, which is the
subset caveat at the top of this document arriving as a reproducibility defect rather than as a reading
hazard.

`ready_lead_s` is `t_stop − t_worker_ready`: **positive means the worker was resident before `Stop`
fired**, which is the mechanism working. It is positive exactly on the five `mdwarm5` turns
(3.051–4.619 s) and negative on **every cold turn that carries the column — five of the seven**
(−1.382 to −1.734 s); turns 1 and 7 predate the `t_worker_ready` instrumentation and the cell is empty
there, so *"every cold turn"* is a claim about 5 rows and not about 7. That is the mechanism's whole
claim in one column.

### 5. The worker does a warm-up synthesis at startup

`kok.create("Warming up.")` before announcing readiness — `bench/bench.py:471-475` already does this
and says why (**[repo]**).

**Measured, and it is not free either way.** The first `create()` on a freshly loaded model is
markedly slower than the steady state: the same item (`r01`, 88 chars spoken) took **2.13 s** as a
worker's first synthesis versus **1.41 s** on a worker that had already spoken. The warm-up costs
**0.78–1.12 s** of startup, which pushes exec→ready from 0.80–1.30 s to **1.33–2.02 s** and therefore
lengthens the streaming lead the mechanism needs.

> **The verdict this subsection closed with is WITHDRAWN, and the data that withdrew it is the table in
> *Cold* below — this document's own.** It read *"Net: a win when there is lead time, a wash when there
> is not. Recommended, with the trade named."* **Both halves are gone.** The `cold7` set holds a
> near-controlled pair with **no** lead on either side and the **same** item `r01` — 268 chars in, 88
> spoken, 5.06 s of audio — named in `residency-timings.tsv`'s `run` column: `E-md-warmup`, no
> startup warm-up, TTFA **4.489 s** at RTF 0.595, against `G-short-cold`, warm-up present, TTFA
> **2.657–3.161 s** at RTF **0.241–0.280**. So it is **a win even with no lead at all** — the
> hook-to-worker interval on a cold start is itself **1.38–1.73 s**, enough to absorb the warm-up — and
> the difference is between failing the 3 s line and sitting just under it, not a wash. The honest limit
> of the comparison is **n = 1 on the `E` side** and the two runs differ in their run label as well as
> in the warm-up, so it settles the *direction* and is not an effect size **[hook]**. And the spec has
> **STRENGTHENED the clause from *recommended* to REQUIRED** on that reading: §10.5 is LOCKED and §13
> row 2 lists the startup warm-up as part of the *selected* mechanism, so leaving it advisory handed the
> implementer a decision the lock claims is already made (spec §10.5 clause 5).

### 6. Idle exit at 30 minutes

Matching `rewrite.sh:117`'s existing sweep window, so a worker never outlives the directory it
depends on. **Not measured** — the runs here are minutes long. Stated as a design choice, and it does
re-introduce a cold start after half an hour of silence, which is the honest cost.

> **The interval, the reason and the clock are all superseded, and the reason was measured FALSE.** The
> spec's clause 6 is **20 minutes**, and *"matching `rewrite.sh:117`'s sweep"* is precisely the reasoning
> it rejected, because **equal timeouts do not order two events**. Worse, *"a worker never outlives the
> directory it depends on"* is the claim a measurement then falsified: `find -mmin` is **wall clock**
> while the spec's clause 6 went on to mandate `time.monotonic()`, which on Darwin does not advance
> across sleep,
> so one unplanned 40-minute idle sleep put **38 min 44 s** of divergence against a 10-minute margin and
> `:117`'s verbatim predicate selects a directory whose worker's own timer reads **12.51 min**. The
> repair is to read idleness off the speak directory's own mtime against `time.time()`; the residual is
> a forward clock jump, bounded by the 1 s poll rather than by however long the machine slept. **That
> measurement is not this document's** — nothing here has slept a machine — and it moved **§13 row 24
> into the ship-blocking set**, where the deterministic cost is that the first turn after any sleep over
> thirty minutes is served **cold** (spec §10.5 clause 6, §13 row 24). The *"not measured"* above stays
> true of this arm and is no longer true of the clause.

---

## The alternatives, and why each loses

| alternative | verdict | on what basis |
| --- | --- | --- |
| **fresh interpreter per turn** | rejected | already rejected by the spec on #6's 3.93 s; this run's cold rows (2.66–5.50 s from a hook) agree and are worse |
| **HTTP server on a port** | rejected | #5 declined it on measured evidence; independently, a file drop answers every question a port raises without opening one |
| **Unix domain socket** | rejected | **[obs]** `bind()` fails at the real path depth — 116 bytes against a 104-byte `sun_path`. The relative-path workaround works but needs `nc -U` in the hook and buys nothing |
| **`launchd` user agent** | rejected, **not measured** | it would be permanently resident and would survive machine sleep, which is genuinely better on latency. It loses on three other counts: it installs a background daemon for a feature that is **off by default** (§11), it is outside `rewrite.sh:117`'s sweep so nothing reclaims it, and it has no per-session scoping, which makes §10.6's per-session player records meaningless — *pid file* was the name when this row was written, and one shared `speak/pid` is exactly what the trials removed (*SUPERSEDED* at the top); the judgement is unaffected, because it turns on per-session scoping and not on the record's shape. **This is a judgement, not a measurement**, and it is the alternative a reviewer should push back on if they think the latency is worth the footprint |
| **worker started by `Stop` only** | rejected | measured: median cold **3.16 s**, 3/7 under the line. This is the mechanism the spec's shape implies today, and it is the one that fails |

---

## The measurements

Raw data: [`residency-timings.tsv`](residency-timings.tsv), 39 rows, every one produced by a hook
process except the single row marked `offline` (the eight-way concurrency race).

### Cold — no worker resident when `Stop` fires

| turn | run | TTFA | hook→worker | model load | synth | RTF | load1 |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | stop-only | **5.441 s** ❌ | 1.196 s | 1.003 s | 4232 ms | 0.837 | — |
| 7 | stop-only | **5.496 s** ❌ | 1.699 s | 1.433 s | 3762 ms | 0.744 | 6.95 |
| 31 | md-warmup, message too short | **4.489 s** ❌ | 1.465 s | 1.295 s | 3007 ms | 0.595 | 6.48 |
| 37 | short-cold | **3.161 s** ❌ | 1.734 s | 0.739 s | 1414 ms | 0.280 | 2.43 |
| 38 | short-cold | **2.954 s** ✅ | 1.614 s | 0.666 s | 1329 ms | 0.263 | 2.48 |
| 39 | short-cold | **2.951 s** ✅ | 1.720 s | 0.799 s | 1218 ms | 0.241 | 3.14 |
| 40 | short-cold | **2.657 s** ✅ | 1.383 s | 0.547 s | 1262 ms | 0.250 | 3.45 |
| | | **median 3.161 s** | | | | | **3/7 pass** |

Turns 37–40 pay a startup warm-up synthesis that turns 1, 7 and 31 do not; that is why their `synth` is
far shorter. **The rest of that sentence used to read *"that is why their `hook→worker` is longer … it
roughly cancels"*, and neither half survives its own column.** `hook→worker` on turns 37–40 is
**1.383–1.734 s** against 1.196 s, 1.699 s and 1.465 s on turns 1, 7 and 31 — overlapping, not longer:
turn 40's 1.383 s is shorter than turn 7's 1.699 s. And it does not cancel. Turn 31 and turns 37–40 are
the near-controlled pair — both have the clause-4 ensure hook live, both get no lead, all five
synthesise `r01` — and the warm-up arm lands at **2.657–3.161 s** against **4.489 s**, RTF 0.241–0.280
against 0.595. The **1.38–1.73 s** hook-to-worker interval absorbs the warm-up rather than paying for
it, which is why §5's *"a wash when there is no lead"* is withdrawn above and why the spec makes the
warm-up REQUIRED (spec §10.5 clause 5).

**The honest reading: cold from a hook straddles the 3 s line and does not clear it.** On a quiet
machine it lands at 2.7–3.2 s; on a busy one it goes to 5.5 s. #6's cold figure of **3.93 s** sits
inside that range, so nothing here contradicts #6 — it locates it. **All of these figures, #6's
included, were measured with the model file already warm in the page cache and are optimistic by an
unmeasured margin** — which pushes an already-failing case further over the line, never back under it.

### Warm — worker resident

Thirty rows, `bf_emma`, every one of the fourteen real rewrites covered at least once.

| | measured **[hook]** | §4 / control **[bench]** |
| --- | --- | --- |
| n | 30 | 12 |
| min | 0.573 s | 0.45 s |
| **median** | **1.216 s** | **0.85 s** |
| max | 4.014 s | 1.25 s |
| under 3 s | **28/30** | 12/12 |
| RTF | 0.254–0.882, median 0.354 | 0.242–0.295 |

**The hook costs about 0.37 s of median TTFA, and only 0.08 s of it is the hook.** The
hook-to-worker handoff is a measured median of 0.079 s. The other ~0.29 s is in `Kokoro.create()`
itself — median RTF **0.354** from a hook against **0.242–0.295** on the bench. That difference is
not the hook's doing: the bench synthesizes twelve items back to back in a hot loop, while a hook
synthesizes one item after an idle gap of seconds. **"Resident" and "hot" are not the same state**,
and §4's number was measured in the hotter one. This is a small effect and it is entirely inside the
budget, but it is the reason the two medians will never match and it should be written down rather
than rediscovered.

**The two failures, both named rather than dropped.** 4.014 s at 1-minute load **11.9**, and 3.829 s
during a machine spike. Both are synthesis-time blowouts (RTF 0.882 and 0.716), not hook overhead —
the handoff on those turns was 0.133 s and 0.198 s, normal. Split by load:

| | n | median | max | under 3 s |
| --- | ---: | ---: | ---: | ---: |
| load1 < 4 | 10 | 1.389 s | 3.829 s | 9/10 |
| load1 ≥ 6 | 9 | 1.106 s | 1.628 s | 9/9 |

The 1-minute load average is a poor instrument and these buckets do not separate cleanly — the worst
row is in the *quiet* bucket. **What the data supports is only this: warm TTFA is dominated by
`Kokoro.create()`, which is CPU-contended, and it occasionally exceeds 3 s on a loaded machine. What
it does not support is a claim that the warm path is unconditionally under the line.** §4 currently
reads as though it is.

The machine during these runs was carrying three to four other Claude Code sessions. That is not a
typical single-user deployment, and it is also not nothing — a user running one agent session while
speech synthesizes is the normal case, and it is what the load1 ≥ 6 bucket looks like.

### What the hook itself costs, cold and warm alike

Forty-seven hook processes, wall time from `t0` to the last trace line:

**0.063 – 0.219 s, median 0.086 s** — and the cold invocations are inside that range, not above it.
**[hook]**

This is the number §6 actually cares about — how long the prompt is held — and the residency mechanism
does not change it, because the hook drops a file and leaves whether or not a worker exists. §10.4's
`"timeout": 10` has at least **45× headroom** against the slowest hook observed.

**AS-OF, and every use of this figure as a BOUND below inherits it.** The measurement stands as a
measurement — it is what a hook process did on this machine on this build. But it measured the hook the
probe ran, and [`speech-integration-spec.md`](speech-integration-spec.md) has since put **two
`readdir`s and a `ps` fork** into the hook body where there were two `stat`s: §10.3 step 6 and step 12
now scan `speak/playerdir/` and `speak/`, and step 12's liveness test validates identity with
`ps -o lstart=` rather than a builtin `kill -0`. So this range is a **HISTORICAL BASELINE** — what that
hook body cost — and **the cost of the hook as specified is UNMEASURED**. Wherever this document uses
the range or the median as a **bound on how fast the specified hook does something, there is no such
bound**, and the sentence's claim has to survive on something other than the number.

> **This note was introduced to stop the figure being read as current, and it overshot in the opposite
> direction.** It arrived saying *"a **lower bound**, not a re-measured figure"* — and a lower bound is
> not available either: *adding operations increases work* holds only **under otherwise identical
> conditions**, and two wall-time samples taken on two different hook bodies under different scheduling,
> load and cache state are not that comparison. **An old observed range cannot mathematically bound a
> future one in either direction** — 0.063 s is a fact about forty-seven processes that ran, not a floor
> under processes that have not. What survives is the **direction and not the magnitude**: the specified
> hook does more work than the measured one did, all else equal, so expect it to cost more.
> **[inferred]**, and only a re-run settles the size. The spec carries the same reasoning at §10.3 and
> counts the *lower bound* framing as a defect in its own LOCKED text at §13 row 9.

### The cold start that outruns the timeout

§10.5 asks what happens "when a cold start outruns the timeout". Measured directly, by inserting a
20 s artificial delay before model load and driving a real turn against a **10 s declared hook
timeout**:

| | measured **[hook]** |
| --- | --- |
| hook process wall time | **0.083 s** |
| declared hook timeout | 10 s |
| worker ready | 21.1 s after the hook fired |
| **audio** | **23.304 s after the hook fired** |
| turn | ended normally; nothing on screen; no error |

**The answer is: nothing bad, and the utterance is not lost.** The job file outlives the hook, the
hook was long gone before its own timeout could matter, and the audio arrived twenty-three seconds
late. **Late, not lost, is the failure mode** — which is the right one, but it is a real cost and
§10.5 should say it out loud rather than leaving "outruns the timeout" as an unanswered question.

### A side observation that touches §13 row 9

The worker calls `os.setsid()` on its first line — macOS has no `setsid(1)` in the base install (the
one on this machine is a MacPorts artifact), so it must be done in-process. **[obs]**: after the driven
session was exited with `/exit`, the worker process was still alive and still resident.

This does **not** answer §13 row 9 (*does the harness kill a hook's process group?*). It shows only
that a `setsid()`-detached child survives the session that spawned it. A non-detached child was never
tested. Row 9 stays open, and this is one more reason to detach rather than a reason not to care.

---

## What §10.5 and §4 need to say

**Not applied here.** #11 owns `speech-integration-spec.md` and two sibling agents are working the
other blockers; a single integration pass folds this in. This is the proposed content.

**It was applied, and then two of its clauses were run and replaced.** This whole section is the
**proposal as it stood on 2026-08-25** and is kept as the record of what was proposed off what was
measured. **Clause 2's stale-lock recovery and clause 7's three preemption hooks are the two that did not
survive** — see *SUPERSEDED* at the top for what replaced each and what the measurements behind them
still establish. **Clauses 1 and 3 are the spec's; clause 4 is NOT, and this sentence used to say it
was.** What survives of clause 4 is its **every-invocation trigger** and nothing else about the step:
both of the implementation properties the clause states — its placement *before any parsing* and its
liveness check of one `[[ -d ]]` plus one `kill -0` — are superseded, the first as **impossible** rather
than merely superseded. The clause's own note below carries the detail. **Clause 5 is the spec's only after a
STRENGTHENING and a withdrawal**: *recommended* became **REQUIRED**, and the *"a win when there is lead
time, a wash when there is not"* it closed with is contradicted by this document's own `cold7` pair and
withdrawn (§5 above, spec §10.5 clause 5). **Clause 6 is the spec's only after TWO
corrections, not one, and the interval is the one this sentence used to leave out**: its *window* went
from the 30 minutes below to **20** in review — so *"matching `rewrite.sh:117`'s sweep"*, which is the
reason clause 6 gives for its number, is precisely the reasoning the spec rejected, because equal
timeouts do not order two events — and its *clock* was then corrected from a monotonic one to the wall
clock by a measurement that is not this document's (spec §10.5 clause 6, §13 row 24).

### §10.5 — the OPEN heading comes off, with the limits attached

The mechanism, in seven clauses — **and *"each measured above"*, which this line used to claim, is false
of clause 7, whose own text says its hooks are all `[inferred]` and none measured.** Clauses 1–6 are
measured above; clause 7 is reasoned from §1b:

1. **Address**: a job file at `$BUF_ROOT/<session_id>/speak/job`, written to a temp name and `mv`d
   into place. **Not a socket** — the path is 116 bytes against Darwin's 104-byte `sun_path` and
   `bind()` fails, observed. The producer rename **coalesces unconsumed jobs** — *n* drops, one
   utterance, observed — and buys nothing about a job already claimed. **The consumer needs its own
   atomic step**: the worker claims by `rename(job, job.taken.<pid>)` and unlinks only that private
   name. A read-then-unlink of `job` loses a job renamed in between, irrecoverably (§1b).
2. **Election**: `mkdir $BUF_ROOT/<session_id>/speak/worker.lock` with the pid inside, performed
   **by the worker**. The hook's pre-check is an optimisation that loses races; the `mkdir` is the
   guarantee. Eight simultaneous hooks → one worker, observed. **Stale-lock recovery needs two clauses
   of its own or it breaks the singleton the `mkdir` just won (§2a):** a lock whose `pid` file does not
   exist yet is **initializing** and must be retried on a short bounded backoff, *never* classified as
   stale — otherwise a racer arriving between the winner's `mkdir` and its pid write tears down a live
   worker's lock and a second worker starts. And reclamation of a genuinely abandoned lock must be
   **serialized by an atomic `rename` into a unique quarantine name** before a fresh lock is created,
   never `rmdir`-then-`mkdir`; the rename can only succeed once, so exactly one reclaimer proceeds.
   **Both of those two clauses are FALSIFIED — 61/400, worst case 3 owners** (*SUPERSEDED* at the top,
   §2a's block). What survives is the first three sentences: eight simultaneous hooks → one worker, the
   pre-check as a race-losing optimisation, and exclusive create as the guarantee.
3. **Wake**: `kqueue`/`NOTE_WRITE` on the speak dir, 1 s poll as a belt. Handoff median 0.079 s.
4. **Warm-up trigger**: an ensure-worker step on **every `MessageDisplay` invocation**, placed **before
   `rewrite.sh:127`'s non-final early return** — *not* on §3.1's publish point. The publish point is
   unusable for this: non-final invocations exit at `rewrite.sh:127-132`, the publish happens only in the
   final invocation and only after `llm_complete` returns, and the final invocation is **concurrent with
   `Stop`** — measured lead 0.006–0.012 s, median 0.008 s, and negative on one turn — against
   5.16–6.23 s from the first invocation. Below `MIN_CHARS` (200) `rewrite.sh` publishes nothing at all,
   so a publish-point trigger gives zero warm-up on short turns. The step must be payload-independent:
   one `[[ -d ]]` and one `kill -0`, before any parsing. **Stated limit:** this covers the cold start
   only when the message streams in more than one chunk and the first chunk leads the end of the turn by
   more than the worker's 1.33–2.02 s startup; on a very short first turn there is a single chunk, it is
   the final one, and the first utterance is cold.
   - **SUPERSEDED IN PART: the every-invocation trigger is the spec's; the two implementation properties
     stated above are not.** What carries over unchanged is the trigger itself and the reasoning that
     picked it — an ensure-worker step on **every** `MessageDisplay` invocation, above `rewrite.sh:127`'s
     non-final early return, and *not* on §3.1's publish point, for the three reasons given (the final
     invocation's concurrency with `Stop`, the publish's position after `llm_complete`, and the
     `MIN_CHARS` gate) — together with the **Stated limit**, which the spec restates as its own STATED
     LIMIT in the same terms (spec §10.5 clause 4). Two things do not carry over:
     - **"Before any parsing" is not implementable, and the spec says so in those words.** The step's
       address is `$BUF_ROOT/<session_id>/speak/`, and `rewrite.sh` has exactly one source for
       `session_id` — the payload, parsed at `:108`; no environment variable, no session file, no
       argument. The specified placement is therefore **after `session_id` is parsed** and before
       `:127`'s early return, and the requirement this document meant is restated as the property rather
       than as an ordering: **the ensure decision must be independent of the payload's *chunk role*** —
       it must not read or branch on `final` or `delta` and must not sit inside or after `:127`'s test.
       **Parsing `session_id` is not a violation of that; parsing `final` is.** *"No parsing"* was a
       proxy for *"not gated on the chunk role"*, and the proxy is what failed. Why this document could
       not see it: the probe parsed nothing because its `$SPEAK_DIR` was handed to it by the harness that
       launched it **[rig]**, so payload-independence was a property of the *rig's environment* and not
       of the trigger. The spec also records the consequence of the placement — `:100`'s enabled-check
       sits above `:108`, so a disabled rewriter starts no worker — and the guard for an absent
       `session_id`, neither of which is in this document (spec §10.5 clause 4).
     - **"One `[[ -d ]]` and one `kill -0`" is superseded by clause 2's replacement, not by anything
       about clause 4.** Two syscalls at a fixed path became **one `readdir` of `speak/`, one `readlink`
       and one identity-validated liveness test** — a `ps` fork, because the generation record carries
       `<pid>.<starttime>` and a bare pid is no longer trusted (spec §10.5 clause 2 and clause 4). The
       spec prices the difference rather than leaving it to be found: the `readdir` runs five to seven
       times a turn against a directory that grows for the whole session, and that it stays negligible
       is **[inferred]**, nothing having timed it. **The `jq` count is the other half of the price and
       it moves the other way** — the step reuses `:108`'s already-parsed `$sid`, so it costs **zero**
       extra `jq` calls and is *cheaper* than the probe's shape on that axis while being dearer on this
       one.
     - **Neither correction touches a number in §4.** The leads, the ready lead, the five first-turn
       TTFAs and turn 31 are all measurements of *when invocations fire and when a worker becomes
       ready*, and no change to what the step does inside an invocation reaches them.
5. **Startup warm-up synthesis**, per `bench/bench.py:471-475`. Costs 0.78–1.12 s of startup, saves
   ~0.7 s on the first real utterance.
6. **Idle exit** at 30 minutes, matching `rewrite.sh:117`'s sweep. Re-introduces a cold start after
   half an hour of silence.
7. **Preemption is §10.6's, not §10.5's**, but §10.5 owes it three hooks, all **[inferred]** and none
   measured — §1b. (i) The worker writes the player's pid to `speak/pid` so §10.6's hook-side kill still
   has something to kill. (ii) The worker re-checks `speak/job` after `create()` and before `Popen`,
   discarding the audio if a newer job is waiting. (iii) **The worker also kills the currently playing
   player the moment it claims a newer job**, before synthesizing it. (iii) is not redundant with (i):
   a hook that reads `speak/pid` *before* the worker writes it kills nothing, and can then publish its
   job *after* the worker's pre-spawn re-check — leaving a stale player running that no other step
   touches (§1b (d)). The pid file bounds the case where the hook sees a live player; the worker-side
   kill bounds the case where it does not. **Both are required.**
   - **SUPERSEDED: three hooks became FIVE, and the last sentence of this clause is the falsified one**
     (*SUPERSEDED* at the top; spec §10.5 clause 7, §13 row 20). **Its *"Both are required"* about (i)
     and (iii) does not survive either, and the spec withdraws it by name**: (iii) with both targets
     covers every case in which the worker survives the spawn, and (i) exists so that a *different*
     process can do the killing — a measured latency value, not an independent necessity. What is
     falsified outright is the **partition**: *"the case where the hook sees a live player"* and *"the
     case where it does not"* are not
     the whole timeline, because a worker that dies between `Popen` and the record's publication leaves a
     player in neither case — `C8`, 12/12 at full length. (i)'s single `speak/pid` is replaced by a
     per-player `playerdir/<pid>.<nonce>` published by the player's own wrapper; (ii) survives as an
     optimisation-given-the-sweep; (iii) survives and is now measured load-bearing; and **the two hooks
     that were added are (iv) the election-time sweep — its process-group half plus (iv-a)'s
     published-record half, which the spec numbers as one hook in two halves — and (v) the worker's
     `wait()` of its own player, with the unlink of that player's record.** Without (v), `kill(2)` on an
     unreaped zombie succeeds, so every kill site in the clause reports success while killing nothing.
     **The `.pending` marker is not a hook at all** — it is a bound *inside* (iv), and naming it as one
     of the two additions both invents a fifth mechanism and hides the one that was really added.
   - **"None measured" is no longer true of this clause. "All of it was measured" is not true either,
     and on an evidence document the difference is the whole point.** What the 312 trials over 26
     switchable configurations reached is the **ROLE of each of the five hooks, which is NOT the
     necessity of all five** — and claiming necessity contradicted both the bullet directly above (*"(ii)
     survives as an optimisation-given-the-sweep"*) and the spec, where (ii) is an **optimisation given
     (iv) and a correctness clause only without it**. **Necessity was measured for two of the five; the
     third had its shape measured and its independent necessity withdrawn; and the remaining two were
     each measured into something other than necessity.** **Per hook, as the arms scored
     them** (spec §10.5 clause 7):
     - **(iii) the claim-time kill — MEASURED LOAD-BEARING.** `C4_noclaimkill` runs to completion
       **12/12** at 2.50 s, and it needs *both* targets: `C10a` (published record only, no child handle)
       kills **nothing**, 12/12 at 2.50 s; `C10b` (handle only, no record) kills 12/12 at 0.56–0.71 s.
     - **(iv) the election-time process-group sweep — MEASURED LOAD-BEARING, and the only hook that
       reaches the spawn-to-record region.** `C12a` kills 12/12 (audible 0.738–0.841 s) and `C12b` kills
       **before `exec`**, 12/12; the two repairs that omit it fail 12/12 at full length (`C11b`, `C12c`).
       Its record half **(iv-a)** covers the player that published before the sweep arrived — `C11a`,
       `C15c`, `C16b`, all 12/12.
     - **(i) the per-player record — the SHAPE is measured; the hook's independent necessity is not.**
       Both alternatives were run and both fail: one shared `speak/pid` (`C14a` against `C14b`) and an
       append-only ledger (`C13a`, scored `NOTHING-ran-to-end` 12/12 at a full 2.50 s). But the spec
       withdrew the first revision's *"both are required"* about (i) and (iii) — (iii) with both targets
       covers every case in which the worker survives the spawn — so what the trials put a number on is
       (i)'s **latency** value: the hook reaches the player a median **134 ms** sooner than the worker's
       next claim would, 123–143 ms, n = 12, `C2_hookside`.
     - **(ii) the pre-spawn re-`stat` — MEASURED TO BE AN OPTIMISATION, not a requirement.** With the
       worker surviving, removing it changes nothing: `C5_norecheck` still kills before the player can
       `exec`, 12/12. With the worker dying after the spawn and **no** sweep it *is* a correctness clause
       — `C15b` runs to completion 12/12 at 2.50 s where `C15a` (re-check present) spawns no player at
       all — but with (iv) present the orphan is caught anyway: `C15c`, killed by the election sweep
       12/12, audible 0.386–0.471 s. **Keep it and state the condition; do not call it necessary.**
     - **(v) the `wait()` of its own player — what the trials establish here is about EVIDENCE, not
       audio.** `C7_noreap` produced no surviving utterance; what it produced is a kill that cannot fail
       — the hook's kill lands at 0.549–0.577 s and every later kill site then reports success, on all 12
       trials, against a process already dead, where `C2` (the same arm with the worker reaping) reports
       `ESRCH` instead. So (v) is measured necessary for the other four to be **checkable**, which is a
       different claim from stopping stale audio and is the one the arms support.
     - and **the `.pending` leak itself** (`C16a` — 25 markers created, none removed).

     What **no** committed arm ran is the identity-and-cleanup layer built on those hooks, all of it still
     `[inferred]`: (i)'s `<pid>.<starttime>` record content and its *signal only on a positive match*
     rule (spec §13 row 20(c)); (iv)'s four-case owner test and the kernel property its middle two
     cases rest on (row 20(b)); the required **order** of (iv) before (iv-a) — every measured arm
     happened to run that order and none ran the reverse, so the 12/12 results are evidence *for* the
     order while the *requirement* is unrun (row 20(a)); and the generation-tagged `.pending` cleanup,
     **implemented in no committed trial and ship-blocking** (row 27). **So: every hook's ROLE is
     measured and two of them as necessity; the identities and the cleanup are not measured at all.**

And the closing condition §10.5 set for itself is now met, with this result:
**cold from a hook is 2.66–5.50 s (median 3.16 s) and fails the 3 s line; warm from a hook is
0.57–4.01 s (median 1.22 s) and holds it 28 times in 30.**

### §10.6 — two qualifiers, and its pid file survives residency

**Its pid file did NOT survive, and the heading above is the shortest statement of what this document got
wrong** (*SUPERSEDED* at the top). Both qualifiers were folded into the spec as **[inferred]**, and 312
preemption trials over 26 configurations then **confirmed one of them, falsified the other's central
claim, and replaced the writer named in the first** — a shared `speak/pid` written by the worker became a
per-player `playerdir/<pid>.<nonce>` published by the player's own wrapper, plus an election-time
process-group sweep. The subsection is kept as written because the *reasoning* in qualifier 2 is what
identified the hole that the trials then measured; only its closing sentence is false. Spec §10.6 and
§13 row 20 carry the replacement.

§10.6 stays LOCKED and this document reopens none of its decisions. It needs two qualifiers, both from
§1b, because §10.6 was written for a design in which the hook spawned the speech child and could
therefore kill the previous one itself.

1. **Its `speak/pid` mechanism is still the right one; it now has a different writer.** §10.6 says the
   pid is "written by the speech child". Under §10.5's mechanism there is no per-turn speech child, so
   **the resident worker writes the player's pid there** after spawning it, and the next hook invocation
   kills it exactly as §10.6 already says. Playback in progress therefore dies within the hook's own
   wall cost, median **0.086 s** measured — a **historical baseline**, with the specified hook's cost
   **unmeasured**, per the as-of note under *What the hook itself costs*. **A *lower* bound is what that
   note used to offer here and it was the wrong direction for this sentence anyway**: *"dies within"*
   wants a ceiling, and a floor licenses none. Without this sentence an implementer reads §10.6 and finds nothing
   left in the design that writes the file.
   - **The WRITER changed twice and the MECHANISM was not "still the right one".** *"Written by the
     speech child"* → *"written by the resident worker"* → **published by the player's own wrapper, at a
     unique per-player path, before the player can make a sound**; one shared `speak/pid` must not be
     used at all, because an older player's reap erases a newer player's registration. **What this
     paragraph still gets right is its reason for existing** — without a named writer an implementer
     finds nothing in the design that writes the record — and **what it still gets right about the
     number** is that the hook killing directly is faster than waiting for the worker's next claim,
     now measured at a median **134 ms** sooner, 123–143 ms, n = 12 (`C2_hookside`). **What it gets wrong is *"dies
     within"***: 0.086 s bounds this path only when a record exists to be found.
2. **"A newer message kills stale playback" needs two more clauses to be true, not one.** A message
   newer than a synthesis *in progress* is not covered by the pid kill — no player exists yet to kill.
   (i) The worker re-checks `speak/job` after `create()` and before `Popen`, **discarding** the finished
   audio if a newer job is waiting; residual, a job landing inside the **6–38 ms** between that check and
   the spawn still starts playing. (ii) **The worker also kills the current player when it claims a
   newer job.** Without (ii) the rule is still false: the hook's kill and the worker's re-check can both
   miss the same job — the hook reads `speak/pid` before the worker writes it, and publishes after the
   worker re-checked — and the stale player then plays to completion with nothing specified to stop it
   (§1b (d)). With (ii) the two kills partition the timeline at the `speak/pid` write and every
   publication instant is covered by one of them.
   - **The last sentence is the falsified one, and it is falsified 12/12** (*SUPERSEDED* at the top; spec
     §13 row 20). Everything before it holds *as a description of the hole*, and the hole this paragraph
     identifies is real — but **the two clauses are not both required, and saying they are contradicts
     this document's own per-hook restatement** (*§10.5 — the OPEN heading comes off*, clause 7, its
     bullet for hook (ii)) **and spec §10.5 clause 7(ii)**. **(ii), the claim-time kill, is required and measured
     load-bearing**: `C4_noclaimkill` runs to completion 12/12 at 2.50 s. **(i), the pre-spawn
     re-check, is an OPTIMISATION given the election sweep**: `C5_norecheck` still kills before the
     player can `exec`, 12/12, and where the worker dies after the spawn the sweep catches the orphan
     anyway — `C15c`, 12/12, audible 0.386–0.471 s — while `C15b` (no re-check, **no** sweep) runs to
     completion 12/12 at 2.50 s against `C15a`, which spawns no player at all. **Keep it; do not call
     it required.** §1b (b)'s own review note says the same and this cell said the opposite; that is a
     defect in the commit that wrote §1b (b)'s note, one commit old. **But "every publication instant is covered by one of them" is false** — a worker that dies
     between `Popen` and the record's publication leaves a player nothing reaches, `C8`, which plays to
     completion. So this rule needs **three** more clauses to be true, not two, and the third is the
     election-time **process-group sweep**: `C12b` kills before `exec`, 12/12, never started.

Cancelling an in-flight `create()` stays **OPEN** and stays in §10.6 rather than §10.5. **Its scope
reduces to the newer utterance's latency rather than the older one's suppression only once clause (ii)
above is in — without it, stale suppression is itself unsolved and the OPEN is a correctness OPEN, not
a performance one** — §1b. **That reduction is conditional on the sweep as well, not on (ii) alone**, for
the reason in the bullet above; cancelling an in-flight `create()` is itself still OPEN in the spec.

### §4 — the headline number survives, restated

§4's TTFA paragraph currently reads as a property of the feature. It is a property of the bench
harness, and the difference has now been measured rather than assumed. Proposed shape:

> **TTFA on the chosen voice, measured from the hook: median 1.22 s, 28/30 under 3 s** (n = 30,
> `bf_emma`, resident worker). The bench-harness figure of 0.86 s median remains correct for what it
> measures; the ~0.37 s difference is 0.08 s of hook overhead and ~0.29 s of `Kokoro.create()` running
> cooler outside a back-to-back loop. **Cold — no resident worker — is 2.66–5.50 s and fails the
> line**; §10.5's mechanism exists to ensure the user is not in that case, and measurably succeeds on
> the first turn of a session when the message streams in more than one chunk and its first chunk leads
> the end of the turn by more than the worker's 1.33–2.02 s startup. **Both cold figures assume the
> model file is already warm in the page cache and are optimistic by an unmeasured margin.**

§4's existing block-quoted caveat (*"read the TTFA figure with its exclusion attached"*) should stay
and get shorter: the sentence *"§10.5's unspecified worker lifecycle is what stands between the spec
and that number"* is now false and should go. What replaces it is the load caveat, which is new:
**the warm path exceeded 3 s twice in thirty turns, both times because `Kokoro.create()` was
CPU-contended, not because of anything in the hook.**

### §13 and §15

Row 2 closes. §15's first bullet — *"no TTFA has ever been measured from a hook"* — stops being true
and should be replaced by the load-sensitivity weakness, which is now the honest version of the same
worry.

**Row 2 did close, and it opened three.** The spec's row 2 now reads *"Rows 20, 21 and 22 are what it did
not close"*, and **rows 20 and 21 are the two whose measurement falsified the clauses this document
proposed** — spec §13 rows 20 and 21, and *SUPERSEDED* at the top. That is the honest shape of what this
document delivered: a closed ship blocker on the TTFA question it was asked, and two ship-blocking rows on
the two protocols it proposed alongside.

§13 **row 12** (warm-up-on-wake vs a late first utterance) is untouched and stays open and
non-blocking, as it was scoped. Nothing here measures a sleep/wake; #5's ~4.9 s post-wake figure
still stands unchallenged. What this document does change about row 12 is that the *decision* is now
cheap: the mechanism already has a warm-up trigger and a wake handler would reuse it.

---

## What I could not measure, and why

- **Sleep/wake.** Requires actually sleeping the machine, which was out of scope and disruptive to
  four live sessions. #5's ~4.9 s stands unmeasured-here. §13 row 12 unchanged. **A machine has since
  slept — unplanned, on 2026-08-26 — and it settled a DIFFERENT question, so this bullet is still owed
  rather than discharged**: no worker was resident across that sleep (`speak.sh` does not exist), so
  what it measured is the platform's clock behaviour and it falsified §10.5 clause 6's idle-exit/sweep
  separation, moving §13 row 24 into the ship-blocking set. Row 12's listening call — a *warm* worker
  across a wake — is untouched by it, which is why row 12 is *"unchanged"* here rather than closed
  (spec §13 rows 12 and 24, §10.5 clause 6, and §6 above).
- **The settled #13 sanitizer combination**, because §13 row 1 has not shipped it. `base` was used;
  the sanitize phase is 0.2–9.2 ms and does not move the result.
- **The shipped hook in bash.** The probe is `zsh -f`, for the clock. The hook's measured wall cost
  (0.063–0.219 s, median 0.086 s) is dominated by three `jq` invocations and a `shasum`, not by the interpreter, so I
  expect bash to land in the same band — **but that is an expectation, not a measurement.** The
  composition claim is also as-of: the specified hook has since added two `readdir`s and a `ps` fork
  (as-of note under *What the hook itself costs*), so "three `jq`s and a `shasum`" describes what was
  measured, not what will ship.
- **The hook's causal contribution to the bench-to-hook gap**, because the control shares hardware but
  not load or cadence — see *The control* above. What is owed is **interleaved paired runs**: the same
  corpus item synthesized alternately through `bench/first-sentence.py` and through the hook, A/B/A/B in
  one session, so both arms see the same load and the same spacing. Until then the ~0.37 s gap is
  decomposed by reasoning, not isolated by experiment.
- **Preemption, in every case except coalescing. THIS EXPERIMENT HAS SINCE BEEN RUN, and it did not
  confirm the clauses — it falsified TWO of them** (*SUPERSEDED* at the top): 312 preemption trials over
  26 switchable configurations, spec §13 row 20. The design below is right about *what to record* — the
  interleaving does turn on which kill fired — and the run's finding is a region this list did not think
  to ask about: a worker dying between `Popen` and the record's publication, `C8`, 12/12 at full length.
  **The two it falsified are (c)'s shared `speak/pid` and (d)'s two-kill partition** — the same two the
  *SUPERSEDED* block lists, which is why that block's count is four across both protocols and two here.
  What it did *not* falsify: (d)'s rule is confirmed, (b) is kept as an optimisation given the sweep,
  and the hook-side kill (c) argued for is quantified even though (c)'s file and writer are gone.
  Read the rest of this bullet as the experiment that was owed, not one still owing. Nothing here drove a second job at a worker that had
  already claimed the first: the driven session issued turns sequentially, and the eight-hook race
  dropped all eight before any worker was ready. So §1b's rows two and three are **reasoned, not
  measured**, and §1b's (b), (c) and (d) are proposals rather than results. **The experiment owed is
  larger than the earlier draft's version of it, because (d) changed what has to be recorded.** Firing
  two `Stop` hooks ~0.5 s apart at a warm worker is still the setup, but "was the older utterance
  audible" is no longer a sufficient observation — the interleaving in §1b (d) turns on *which* kill
  fired, and a run can pass by luck with the mechanism still broken. What must be recorded per run:
  1. the timestamps of the hook's `speak/pid` read and its job rename (**R** and **W**);
  2. the timestamps of the worker's pre-spawn `stat`, its `Popen`, and its `speak/pid` write
     (**S**, and **P**);
  3. **which** step actually killed the first player — the hook's pid kill, the worker's claim-time
     kill, or neither — not merely that it died;
  4. whether the first utterance was audible, and for how long.
  A run in which the hook's kill happened to see a live pid tells us nothing about (d); the case that
  matters is deliberately provoking **R < S < P < W**, which means publishing the second job while the
  first is *mid-`create()`* and timing the rename to land just after the worker's pre-spawn check. That
  probably needs an instrumented `speakd.py` with a settable delay between the pre-spawn `stat` and the
  `Popen`, so the window can be widened to something a shell script can reliably hit.
- **The stale-lock recovery protocol in §2a. THIS EXPERIMENT HAS ALSO BEEN RUN, and both clauses are
  FALSIFIED** (*SUPERSEDED* at the top): 1200 lock trials over three protocols and six scenarios, spec
  §13 row 21. **The design of the experiment below is exactly what was done** — a worker stalled before
  its pid write, N racers, count the owners — and the prediction attached to it was wrong in both
  directions: the probe's protocol produced **121/400** wrong outcomes and the two corrected clauses
  **61/400**, and **the worst case was 3 owners, not the 2 this bullet's closing sentence predicts.**
  **Read the rest of this bullet as the plan that was owed, not one still owing — and read its two
  clauses as measured false, not as `[inferred]`, which is what they were when it was written.**
  HISTORICALLY: *provoking the real window means pausing a winning worker between its `mkdir` and its
  pid write, which again needs an instrumented worker. Worth doing in the same run as the preemption
  experiment: start N workers against a lock held by a worker deliberately stalled before its pid write,
  and count how many end up believing they own the session. The current protocol should produce 2; the
  corrected one, 1.* **That is exactly the rig that ran — `lockrace.py`, N racers against a stalled
  incumbent — and the closing prediction is disproved in both halves:** the worst case was **3** owners
  for both protocols, and the corrected protocol did not produce one owner throughout but a wrong count
  in **61 of 400** trials. **What is still owed here is not this experiment but two arms of its
  successor**, and they belong to the replacement rather than to these clauses: the generation
  **unlink** and its ordering against the election sweep, which `lockrace.py` never ran, and a
  barrier-staged re-run of the reclamation scenarios, of which exactly 1 of 100 is trace-confirmed
  (spec §13 row 21(a) and 21(b)).
- **Whether any of this holds on hardware that is not an M3.** Nothing here is portable evidence.

### One thing that cannot be measured here, and does not need to be

**A genuinely cold page cache — closed as an environment limitation, not owed.** Purging it needs
`sudo`, which this machine's user does not have, and Darwin has no reliable userland equivalent. The
sudo-free workaround — reading tens of gigabytes to force eviction — thrashes the machine for minutes
and still yields an imprecise answer, so it was not attempted.

State the consequence precisely, because it is what makes this acceptable rather than a hole:

- **Every "cold" figure in this project means *no worker process resident*, with the 310 MB
  `kokoro-v1.0.onnx` and 27 MB `voices-v1.0.bin` still warm in the file-system cache from an earlier
  run.** So all cold numbers — the **3.16 s** median here, its 2.66–5.50 s range, and #6's **3.93 s** —
  are **optimistic by an unmeasured margin.** That phrasing belongs wherever a cold figure is quoted,
  not only in this section.
- **It cannot flip any verdict the spec depends on.** Cold TTFA already exceeds the 3 s budget without
  any page-cache penalty — 4 of 7 cold hook turns are over the line. A larger cold number makes an
  already-failing case fail harder. There is no decision in §10.5, §10.6 or §13 whose outcome turns on
  the size of the margin, which is precisely why an unmeasured quantity is acceptable here rather than
  blocking.
- **The residual scenario, on the record rather than implied:** the first turn after a boot, or after
  genuine memory pressure — a large build, Docker, a heavy browser — on a 16 GB machine. **The residency
  mechanism does not help there**, because it only pays off once a worker exists, and that is exactly the
  case where no worker does.

## Two places my expectation was contradicted

**1. `MessageDisplay` does not precede `Stop` by seconds — only its non-final invocations do.** I
expected the whole event to lead `Stop`, because the message is displayed before the turn ends. On a
fifty-character reply it did not: the `Stop` hook process started 64 ms first. The mechanism still
works, but it works *because the message is long enough to stream in several chunks*, not because the
event ordering guarantees anything. Had I only tested long replies I would have written a stronger claim
than the evidence supports, and the short-reply case was an afterthought that turned out to be the
interesting one.

**2. The lead I measured did not belong to the trigger I specified, and I did not notice until review
said so.** The earlier draft named §3.1's publish point as the trigger and cited the 5.16–6.23 s lead
as its evidence. Those are two different events: the lead is the *first* `MessageDisplay` invocation's,
the publish happens in the *final* one, and the final one's lead is **8 ms**. The probe never measured
the publish point at all — its `MessageDisplay` hook parses no payload, so it could not have
distinguished final from non-final even in principle.

What makes this worth recording rather than quietly fixing: **the error was invisible from inside the
measurement.** Every number was correct, the mechanism worked, the table reproduced — and the sentence
above the table described a different mechanism from the one that produced it. The 64 ms observation in
(1) was the visible symptom, and the earlier draft filed it as *unexplained* rather than treating it as
evidence that the event model was wrong. **An anomaly recorded honestly but not chased is still a missed
finding**, and the cost was a headline claim the data did not support surviving into a PR. Both are
corrected in §4a; the correction weakened nothing but the description, because the every-invocation
trigger is what was measured and it is implementable.

## Safety record

- **`~/.claude/settings.json` was not modified.** SHA-256 before and after:
  `b73f471a3f100d111d7a69387be3d0adaa8e37c6552b52362f7209fdbb3f945f` — identical. Its `hooks` key still
  holds exactly one `SessionStart` entry.
- Every hook used here lived in a throwaway settings file passed with `claude --settings`, over a
  scratchpad directory created for the purpose, and is gone.
- The driven session ran in a pane created for this work and closed after it. `herdr server stop` was
  never run. No other agent's pane was touched.
- All worker processes were killed at teardown; `pgrep -f speakd.py` returns nothing.
- The only approval dialog answered was the folder-trust prompt for the scratchpad directory this
  session created.
