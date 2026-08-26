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
**They are disjoint and both are needed.** `summarise.sh` covers what the aggregate TSVs hold —
one row per trial. Figures that are counts of trace *events* (`record_unlinked`, `pending_found`,
the sweep skips) are in no TSV column, so `C14a`'s 8 destructions across 4 trials and the
`C15c`/`C16` 25-election `killpg` counts come only from `analyse_round2.sh`. Neither script is a
check on the other.

The helpers that address the author's archived **run tree** rather than the rig's scripts —
`gather_out.sh`, `clean_copies.sh`, `peek.sh`, `peek_one.sh`, `assemble_pass1.sh` — keep the
external path as their default, because those run directories are not in the repository. They
take the same overrides.

## Round 12: exit statuses mean something

This document's own subject is a step that measured nothing and reported success, and review
kept finding the same shape elsewhere in the rig one instance at a time. Round 12 swept the
whole directory for it rather than the named cases: **a step that fails, or produces nothing,
must not exit 0 and let the next step consume stale or absent input.** Concretely — the six
`run_*.sh` drivers no longer let `| tail -1` swallow the driver's exit status; `collect.sh`,
`collect_real.sh`, `assemble.sh` and `assemble_pass1.sh` refuse an empty or unparsable input
instead of publishing whatever an earlier collection left behind; `summarise.sh`,
`compare_passes.sh`, `analyse_round2.sh` and `analyse_c14.sh` fail rather than print empty
sections; `publish.sh` refuses to publish a rig without `expected-configs.txt`; `gather_out.sh`
names the configurations it cannot find instead of dropping them; `hook_probe.sh` no longer ends
in an unconditional `exit 0`, so a failed publish is not stamped `Rdone`; and `run_lock.sh`
scores a trial in which no process recorded an outcome as `VOID` rather than `owners=0`.
None of this is new evidence: the committed TSVs predate all of it, and `summarise.sh` over them
prints exactly what it printed before.

## Round 15: "it produced something" is not "it produced the whole thing"

Round 12 made a step that produced **nothing** fail. Round 15 is the next quantifier: a step that
produced **some** of what it promised was still exiting 0, and four of those steps are the ones
that decide whether a fresh run may be published.

- `run_lock.sh`'s `count_owners` proved only that *one* racer recorded an outcome. `wait` returns
  when the last background job exits, not when they all succeeded, so a racer that never started
  left the survivors looking like a clean `owners=1` trial — worst at the N=16 cells. It now
  requires the **expected number of participants** each to record **exactly one** terminal
  outcome. This forced a coupled change in `lockrace.py`: `elect_current()` could return on
  `rmdir_failed` recording no terminal outcome at all, which the new check cannot distinguish
  from a racer that never ran.
- `collect.sh` checked only for **zero** reconstructed trials. A run missing one worker claim
  still writes every hook marker, so it produced eleven rows out of twelve and exited 0, shrinking
  the published denominator in silence. It now compares the row count against the `t<N>a.entry`
  marker count, which the worker cannot influence.
- `summarise.sh` **annotated** `VOID` and exited 0, although its own comment said a run with any
  `VOID` is not a complete run. It now fails and names the voided cells. The committed evidence
  has no `VOID` rows and still exits 0.
- `publish.sh` treated every source file except the manifest as optional and never cleared the
  destination, so a missing `speakd_probe.py` was skipped while the branch's older copy survived
  and was reported by the closing `ls` — new code and stale code mixed, reported as a success. It
  now requires the runtime file set and stages into a fresh directory before swapping it in.
- `analyse_round2.sh`'s `C13a` block ended `| head -20` over **50** rows of output, so 30 rows —
  8 of the 12 erasures among them — were dropped, and the 12/25 figure the document quotes could
  not be derived from the script it cites. The pipe is gone, the count is printed, and every
  block's own exit status is now checked.

**And one design finding, which is not tooling.** The `.pending` marker still did not bound
`killpg`: the generation tag says *which* generation, never that the pid recorded for it is still
that generation's owner, only the highest generation is ever liveness-tested, and a marker never
expires. `speakd_probe.py` now publishes the owner record as `<pid>.<starttime>`
(`--owner-identity`, default on) and takes a verdict before signalling — signal on
*match* and on *confirmed no such process*, **skip and expire the marker** on *exists with a
different start time*, and (round 24) skip while **keeping** the marker on *the record carries no
identity* and on *the lookup itself failed*. It is the same instrument PR #27's §10.5 clause 2 specifies, so the two documents describe
one scheme. **Unrun**: the committed traces predate it, and the document tags it `[inferred]` with
the arms that close it.

## Round 16: a guard is not a guard until it has refused something

Round 15's answer to "produced only some of it" was four new checks. Three of them were wrong, and
one of the three would have deleted the committed evidence. Every fix below was executed against a
bad input **and** against the committed evidence, in both directions.

- **The identity test had a hole shaped like the thing it closes.** `owner_identity()` guarded on
  `option == "off" OR the record has no start time`, putting the deliberate falsification arm and
  a **record shape** behind one `or`. So under `--owner-identity on`, a bare `<pid>` record —
  written before the option existed, or by an `off` worker — degraded silently to `kill(pid, 0)`,
  reported a recycled pid as `same`, and let a `.pending` marker authorise `killpg` on a
  stranger's whole group. The degradation now keys on the **option** and never on the record;
  under `on` a bare record is a fourth verdict, `unverifiable`, and the two consumers fail safe in
  opposite directions because their unsafe acts differ in size: the sweep refuses to signal and
  **keeps** the marker (nothing here proves the owner gone, so nothing may expire it), while the
  election supersedes without signalling, since calling it live would restore the liveness failure
  the test exists to fix and buys no safety the sweep is not already providing. Bench-run in five
  arms against a live unrelated group leader; the stranger survives the bare record under `on`,
  dies under `off`, and a verified record still draws its `killpg`.
  **Round 21 replaced the election half of that** — see below.

## Round 21: the protocol, for the first time in ten rounds

Two of the three findings are in the design rather than in the rig, and both were reached by
reading a clause against the act it actually authorises rather than the act it names.

- **The PLAYER records never carried an identity, which is the owner-record defect one record
  over.** Round 20 anchored the record *name* to `^[0-9]+\.[0-9a-f]{8}$` so a `.pending` marker
  could not be parsed as a pid. That is a **parsing** fix and it was read as though it made the
  pid an identity. It does not: nothing removes a player record when its player dies, so the
  record outlives the process for the whole session — **`C12b`'s warm-up record `94309.c8debde7`
  is in the election sweep's target list on 24 of its 25 elections**, `ESRCH` every time, still
  there at `gen12r` — and after pid reuse three separate sites signal a stranger. The record's
  **CONTENT** is now the player's own `<pid>.<starttime>` (`--player-identity`, default on),
  written by whoever publishes the record, and every signaller re-reads the pid's current start
  time and **skips in silence on a mismatch**. The name shape is unchanged, because **PR #27's
  §10.5 clause 7(i)** puts the identity in the content and the two documents must specify one
  scheme. **Three sites, not the two the review named** — the hook, the election-time record
  sweep, and the worker's **claim-time kill**, which reads the same records through the same
  function; guarding two of three is how a repair ships broken. `gone` still attempts the kill and
  reports `ESRCH`, because clause 7(i) says *mismatch* and a vacant pid is not one, which keeps
  four committed arms' accounting meaning what it meant. Bench-run in nine hook arms and three
  sweep arms, both directions: under `on` the matching player dies while a recycled record, a bare
  record and a name/content mismatch are all spared; under `off` all three strangers die, which is
  the defect reproduced.
- **Superseding an `unverifiable` OWNER was not fail-safe, and the reason round 16 gave was
  false.** That reason was *"the only destructive consequence of superseding is the pgid sweep,
  and the sweep refuses this verdict on its own"*. Superseding is not merely a licence to signal —
  **it is the licence to consume jobs**. A bare record may belong to a live legacy worker, so
  superseding it yields **two owners and overlapping audio**, which the sweep's refusal does not
  touch. Nor can superseding be made into a drain: `MYGEN` is assigned once and `highest_gen()` is
  called from nowhere but `elect()`, so a worker that has won never looks at the lock again, and
  no notice could reach a worker that by definition predates it. The election now splits on
  `kill(pid, 0)` — **supersede a vacant pid, refuse a held one** — mixed-mode operation is out of
  contract, and the cost is a session that **wedges** when a bare record's pid has been recycled
  (bounded to one session, and recorded by pid on every election). Bench-run in seven arms, both
  directions, with the three other verdicts and the `off` arm confirmed unchanged.
- **The repair for round 17's finding used an invalid bound** — see the `analyse_round2.sh` row in
  the script table below. The figure survives byte-identical at **8 across 4**; the argument that
  carries it does not, and has been replaced by one that needs no publication timestamp.
- **`publish.sh`'s rollback destroyed what it existed to protect.** It `mv`'d `traces/` **out of**
  the live destination before the swap, so a failed `mv "$STAGE" "$DEST"` restored an `$OLD` whose
  traces were already gone while the `EXIT` trap deleted `$STAGE` — the only remaining copy.
  Measured on the round-15 script with a forced swap failure: **114 of 114 committed trace files
  destroyed.** It is now a `cp -Rp` verified by entry count before anything irreversible happens;
  the same forced failure leaves the destination byte-identical, and a failed rollback names the
  recoverable path instead of exiting silently.
- **`publish.sh`'s required set omitted the producers of four committed TSVs.** `collect_real.sh`
  is the only thing that rebuilds `real-audio-trials.tsv`, without which `summarise.sh` fails its
  whole re-derivation — and it was optional. So were `assemble.sh`, `assemble_pass1.sh`,
  `run_real.sh`, `compare_passes.sh` and `analyse_c14.sh`. All are required now.
- **`verify_fires.sh` was a subset check, not a completeness check.** It required every expected
  name to appear, never that each appear **once**. `run_c10.sh`, `run_c16.sh` and `run_tail.sh`
  append to `RUNS.txt`; only `run_pgid_rerun.sh` filters the old line first — so re-running one
  configuration left two lines naming it, the guard passed, and `assemble.sh` appended its twelve
  rows twice, turning the published 312-trial denominator into 324. Seen set must now **equal**
  the manifest: duplicates and unexpected names are both refused by name. **The five-`MISSING`
  refusal over `traces/` is unchanged and byte-identical.**
- **`assemble_pass1.sh` pinned `C3_adversarial` to one historical timestamp** while every other
  configuration globbed, so any other valid pass-1 tree published **10 of 11** configurations
  while the aggregate row guard succeeded. Every configuration is globbed now and each must match
  **exactly one** run directory — zero and two are both refusals, the second because a tree with
  two runs of one configuration is an ambiguity the script must not resolve by picking. The
  historical timestamp survives as `PASS1_C3_adversarial=…`.
- **`summarise.sh`'s attribution chain let the player's log outrank the kernel.** It tested
  `sig=="-15" || plog=="15"`, then `-30/30`, `-31/31`, `-14/14` — but `rc` is the parent's wait
  status and `plog` is the **last** value the player wrote, and the committed `C12b` log has one
  process writing `sig=14` then `sig=31` 69 µs apart. `sig` decides alone now; `plog` is the
  fallback for rows with no wait status. **No committed figure moves** — no row in
  `preemption-trials.tsv` has both fields present and disagreeing — so this is latent, not a
  correction.
- **`summarise.sh`'s header claimed more than the script does.** *"Every published figure"* was
  false: event counts (`record_unlinked`, `pending_found`, the sweep skips) are in no TSV, so
  `C14a`'s 8-destructions-on-4-trials and the `C15c`/`C16` 25-election `killpg` counts come only
  from `analyse_round2.sh` over the raw traces. The header now says which script derives what.

## Round 24: the instrument, the last clock, and the wrong instant

Three findings, one per layer: the thing the guard measures with, the thing the harness stages
with, and the thing the derivation reads.

- **`ps -o lstart=` was read two-valued, so the identity guard failed open on exactly the input
  it exists to be careful about.** Both readers — `speakd_probe.py`'s `proc_starttime()` and
  `hook_probe.sh`'s `now_starttime()` — collapsed *every* failure into "the pid is absent", and
  every caller read that as `gone`. `gone` is the one negative verdict that **acts**: the sweeps
  signal on it, the election supersedes on it. So a *transient* `ps` failure — fork pressure,
  `EINTR`, a full process table — made the guard do both things it was added to prevent, and did
  so most readily under the load that recycles pids fastest. The shell side had the defect twice:
  `s=$(ps … | tr …) || return 1` takes its status from `tr`, which always succeeds, so the `ps`
  status was **discarded**, not merely conflated — the pipeline-status trap this rig has already
  been bitten by with `head`. A confirmed absence is now one measured shape (nonzero exit with
  **both streams silent**, which is what `ps -o lstart= -p 99999` gives on this machine); every
  other shape is a fifth verdict, `lookup_failed`. `stderr` is captured rather than discarded,
  because discarding it is what made a diagnostic indistinguishable from silence. **Every
  signaller refuses `lookup_failed`** — the hook, the record sweep, the claim-time kill, and the
  pgid sweep, which also does **not** expire the marker, since expiry asserts the owner is
  provably gone and here nothing is known. **The election retries and then loses.** It does not
  reuse the bare-record `kill(pid, 0)` split, because a bare record is unverifiable *forever*
  while a failed lookup is unverifiable *at this instant*, and falling back would re-admit pid
  existence as an election input under an option that says it is off — round 16's hole with a
  transient failure in place of a record shape. The cost is a worker that does not start, bounded
  by the retry budget and recorded per attempt. Bench-run end to end at all five sites, both
  directions, `off` arm verified unchanged at each; the failure is staged with a real reachable
  input (an out-of-range pid, which `ps` refuses with a diagnostic) plus a forced `OSError` for
  the fork-failure branch. **The first draft of the `pgid` arm passed by never running** — it put
  the unlookupable record at the highest generation, so the election correctly refused and no
  sweep executed. It now stages a second, confirmed-dead generation and asserts `election_won`
  before asserting anything about the sweep.
- **S3's staging was still a clock, and this is the sixth staging repair to `run_lock.sh`.**
  Waiting for B's `classified_stale` proves B **observed** a dead generation; it does not prove A
  **reclaimed** before B's 120 ms classify stall expired. A slow or descheduled A means B reclaims
  first and A merely loses — `owners=1`, which for `proposed` is indistinguishable from a genuine
  pass. Replaced by a **release barrier** in the S1/S2 barrier's own two-phase file-token shape
  rather than a seventh mechanism: B parks after `classified_stale`, A drops the `GO` token only
  after its election has returned a successful reclaim, B is released and commits the ABA act.
  `classify_hold_timeout` (B waited out the guard) and `classify_hold_norelease` (A had nothing to
  release) each `VOID` the trial, and so does a log with **neither** marker and no barrier records
  at all — "the barrier did not fail" and "the barrier ran" are different statements. Bench-run
  through the real `trial_aba` on all three protocols, with the ordering read off the log
  (`A's reclaim < B's go_seen < B's terminal outcome`, and B never reclaiming first), and each
  failure driven through the real `lockrace.py`. **The committed `lock-owners.tsv` predates this
  like every other staging fix here.**
- **The live-player witness was checked at the wrong instant, in two scripts.** `analyse_round2.sh`
  and `analyse_c14.sh` both tested liveness at the hook's `entry` marker — the hook's *first*
  act — while the `nopid` observation happens after `K` and the record scan. A player that exited
  in between counted as live at an observation it was not alive for. The scan lies strictly inside
  `(K, R)` and its instant is unobserved, so the blind rows now require liveness **across** the
  interval: `player_start <= K` and `player_end > R`. The uniqueness interval's upper end moves the
  same way, `tNc entry` → `tNc R`, which can only add candidates and so can only make the naming
  refuse. **`reached`/`sent` rows take no across-the-scan check, and that is the opposite
  finding** — the hook's kill is what *ends* the player, so a reached player cannot outlive `R`
  (0.6–2.0 ms after `K`, 113.2–140.4 ms before it), and requiring it to would have destroyed every
  reached count in the document. For those rows the kill is the evidence, and it is now checked as
  such: the target must be that trial's own b-player, live at `K`. **8 across 4, 4 of 12 and 12 of
  12 all survive** — verified, with the blind trials live 1519.8–1562.6 ms past `R`. Both
  directions demonstrated, including the one input that separates the old predicate from the new
  (a blind trial's `player_end` moved into `(K, R)`).

## Round 26: the exempted kill site, and the arm that catches what the last repair evicted

Both findings are consequences of earlier repairs in this same PR, and both are of the shape this
rig keeps producing: the fix landed, and the thing it displaced went somewhere it should not have.

- **The `Popen` handle is not a reservation, and `C10b` was already the evidence.** Clause (iii)
  kills two targets, and `kill_player` exempted the in-memory handle from round 21's identity test
  on the ground that *"the pid is reserved until this process reaps it"*. Reaping is precisely what
  **releases** the pid, `reap()` calls `proc.wait()`, and nothing cleared the global — so the
  handle went on naming a reaped child until the next `Popen` replaced it. **`C10b_nopid_handle`
  has 24 `via=handle` rows and 12 of them are `result=ESRCH`**, one per `jNa` claim, each
  signalling the previous trial's b-player about **2.6 s** after its `player_exit`. Nothing was
  harmed because the kernel did not recycle those pids inside 2.6 s, which is the same
  "harmless until the number names something else" this rig records about the hook. It is the
  **fifth** pid-reuse site — after the owner record, the player record's content, the per-player
  filename and the hook — and the only one whose exemption was argued instead of measured.
  **The repair makes the premise true rather than testing for its failure:**
  `os.waitid(P_PID, pid, WEXITED | WNOWAIT)` waits for the child to become waitable **without
  consuming it**, so the pid is still reserved when it returns; the handle is retired and the
  child reaped under `player_lock`, and `kill_player` holds that same lock across its `os.kill`,
  which is what removes the read-then-descheduled-then-kill window a bare clear would leave.
  `proc.wait()` under the lock cannot block, because `waitid` has already established the status
  is there. A generation counter or an identity re-read would only **detect** the stale handle,
  and the re-read would put a `ps` fork at one-second resolution on the claim path where this is
  exact; **`os.pidfd_open` does not exist on Darwin** and `EVFILT_PROC` must be armed with the pid
  it watches, so it inherits the race. Because the reservation is load-bearing, the option that
  selects the site **refuses to run** without it: `--claim-kill handle|both` with no
  `waitid(WNOWAIT)` records `FATAL` and exits **5**, beside the `SIG_IGN` check and before the
  election. Both directions run on the committed rig, neither published as an arm: a 12-trial
  `C10b_nopid_handle` still kills through the handle **12/12** (`via=handle … result=sent`, the
  player dying by the claim signal) while `via=handle` rows fall **24 → 12** and `ESRCH`
  **12 → 0**, every `jNa` claim now recording `no_target` after `handle_retired … reserved=1`; a
  12-trial `C10a_nopid_pidfile` reproduces the committed record path exactly, 25 `no_target` and
  25 players at `rc=0`; and with `os.waitid` removed, `--claim-kill handle` refuses while
  `--claim-kill pidfile` runs to `idle_exit`. **Unrun as an arm, `[inferred]`**; the closing
  condition is a re-run of `C10b_nopid_handle` and `C6_handle`.
- **Round 25's narrowing of `analyse_c14.sh` moved the misclassification instead of removing it.**
  Round 25 was right that only `result=sent` may count as a reach — the branch's premise is that
  the kill returned 0 — but **`blind` was the `else`**, so the rows it evicted did not leave the
  derivation. `esrch` (a record found, its pid gone) and `record_skipped` (a record found and
  **deliberately not signalled**, carrying `verdict=` and no `result=` at all, so the field parses
  empty) both landed in the arm whose meaning is *"the hook found NO record"*. An identity-enabled
  re-run could therefore have published a **record destruction** on a trial whose record was
  intact — close to the opposite claim. Round 21 had already repaired this exact shape in three
  `hook-kills.log` parsers inside `analyse_round2.sh` by testing the event column first;
  `analyse_c14.sh` reads the same file and never got that test. **Blind now requires `nopid` or
  `norecord` by name; every other outcome is excluded by name and printed with the outcome that
  caused it; a trial with more than one hook-C row is excluded with both outcomes shown rather
  than silently reduced to its last; and the block asserts its arms plus its exclusions sum to the
  12 trials it iterates, exiting 2 rather than printing a note.** On the committed traces the only
  hook-C outcomes are `nopid` (4) and
  `sent` (20) and every trial has exactly one row, so **4 of 12 and 0 of 12 are unchanged** —
  verified, not assumed. Both directions on a synthetic 12-trial fixture: a `record_skipped …
  verdict=recycled` and an `esrch` row are each named and excluded where round 25's script counted
  both as destructions (**4 blind → 2**), a two-row trial is excluded where round 25's kept the
  last row and called it a reach, and `nopid`, `norecord` and `sent` are all still accepted. The
  accounting check is demonstrated firing by mutation rather than by input — one exclusion
  counter's increment removed gives `ACCOUNTING ERROR: 10 of 12` and **exit 2** — and the
  pre-existing missing-input refusal still exits 2 on a traces directory lacking `markers.tsv`
  and `hook-kills.log`.

## Round 29: an event nothing reads is an outcome nobody knows happened

Round 12 made a step that produced nothing fail. Round 29 is the same question asked of the
**trace vocabulary** rather than of exit statuses: the two probes emit **59** distinct `rec()`
event names, and the question is which of them any consumer actually keys on.

The reason to ask is harness defect 6. Round 25 added a fail-closed path — `publish_refused`,
recorded when the worker cannot obtain the player's identity, stops the player through the
`Popen` handle and publishes **no** record. **Nothing consumed it.** `collect.sh` read the
`W_pid_write` beside it through a blind `else`, stamped `W` as though the record had been
published, and the `SIGTERM` that refusal sends then attributed to `hook-pid-kill` — a void
trial published as affirmative evidence for hook preemption. So the general form of the question
had to be asked, not just the instance fixed.

Counted programmatically over the rig (an event counts as *consumed* only where a script selects
on it — an `awk` field comparison, a `grep` pattern, or a name assigned to a variable that is
then grepped, as `run_lock.sh`'s `await_publication()` does; a mention in prose is not a
consumer):

| | count |
| --- | --- |
| event names emitted by `speakd_probe.py` and `lockrace.py` | **59** |
| keyed on by at least one consumer | **32** |
| **written and never read** | **27** |

Of the eight events added during this PR and asked about by name in review:

| event | consumer |
| --- | --- |
| `record_skipped` | `collect.sh` (counts and reports to stderr), `analyse_round2.sh` (excluded from the hook-read verdict) |
| `barrier_timeout` | `run_lock.sh:185` → the trial is `VOID` |
| `observe_timeout` | `run_lock.sh:185` → the trial is `VOID` |
| `release_timeout` | `run_lock.sh:185` → the trial is `VOID` |
| `publish_refused` | **none — this was harness defect 6.** `collect.sh` now rejects the run |
| `pending_reaped` | **none** |
| `election_gave_up` | **none** |
| `owner_lookup_failed` | **none** — README prose only |

**`publish_refused` is the only one of the twenty-seven that this round closed, and the other
twenty-six are disclosed and left as they are. The distinction is what a missing consumer would
cost.** `publish_refused` had to be closed because a consumer read the event *beside* it and drew
a false conclusion: the gap produced a wrong published row. (It is therefore no longer on the
never-read list — the twenty-seven below is the count *after* that fix, and `collect.sh` is its
consumer.) Two of the twenty-seven are false positives of the census, named at the end of this
section (`ready`, `FATAL`), leaving twenty-five genuinely unconsumed and harmless. **Twenty-one
of those are diagnostics that no consumer reads and no consumer misreads**, and nothing derives a
figure from their absence:
`signal_dispositions`, `synth_done`, `idle_exit`, `handle_retired`, `kill_skipped`,
`classify_hold_wait`, `publish_lost`, `rmdir_ok`, `rmdir_failed`, `barrier_ack`,
`barrier_released`, `quarantine_won`, `quarantine_lost`, `election_won`, `election_lost`,
`pending_expire_failed`, `pending_reap_failed`, `record_unlink_failed`,
`owner_record_unverifiable`, `owner_record_unreadable`, `owner_pid_recycled`.

**The remaining four are the ones a future round should look at first**, because each records a
**terminal outcome** that a consumer could plausibly want to treat as a void rather than as a
measurement:

- **`election_gave_up`** — the budget-exhaustion outcome round 27 added. §1's derivation list
  records that this path previously left *no* trace record at all; it now leaves one, and
  nothing reads it.
- **`pending_reaped`** / **`pending_expired`** — the two ways a `.pending` marker leaves the
  disk. `analyse_round2.sh` counts `pending_created` and `pending_found` and neither of these.
- **`owner_lookup_failed`** — the election-side twin of the failure `publish_refused` reports on
  the publication side. It is the one on this list closest in shape to harness defect 6.

`ready` is on the never-read list and is a false positive worth naming: the readiness handshake
every driver waits on is the `$SD/ready` **file**, not the trace record of the same name, so the
record is redundant rather than unconsumed. `FATAL` is the same shape in reverse — the drivers
print their own `FATAL:` messages, which is why a substring search appears to find a consumer and
does not.

## Round 30: the rig made the mistake it was built to measure

**Any place this rig terminates something, ask what that thing's children are in.**

That is the whole of this round, and it is worth more than the two edits that came out of it.

Round 27 gave `run_real.sh` and `run_preempt.sh` an `EXIT` trap, because four fatal paths were
leaving a worker running under `--idle-exit-s 600` — harness defect 5. The trap did
`kill -TERM "$WPID"`. But `speakd_probe.py` calls `os.setsid()` before it elects, so the worker
**leads its own process group** and every player it forks is in *that* group. A signal to the
worker's pid reaches the player not at all. On a fatal readiness or hook path the worker died and
its `afplay` process ran to the end of the 5.7 s wav, or its stub kept sleeping, and the immediate
retry — which is what an operator does with a failed run — started with the previous run's
processes still holding the audio device.

**§4b clause 7(iv) is the process-group sweep, and it exists precisely because killing a worker's
pid does not reach that worker's player.** The cleanup path of this rig made the same error one
function away from the code that measures it, and arrived at it *through* the fix for defect 5.
`C17_setsid_player` — the arm that exists to show clause 7(iv) failing — was outside even the
worker's group and outside anything the trap could name.

The rule, the guards and the residuals now live in **`cleanup.sh`**, one copy sourced by both
drivers, for the reason `attrib.sh` is one file: a repair applied to one site and not to its
sibling is this document's single most frequent disclosure.

**The over-kill direction is the dangerous one**, and it is why the pgid is derived and not
assumed. `os.setsid()` makes the worker's pgid equal its pid — *but only from the instant it
reaches that call*. Measured on this machine: a plain `cmd &` child reports the **invoking shell's**
pgid, not its own pid. So `kill -TERM -<pgid>` against a worker that died in argparse, or that has
not been scheduled yet, names **this driver's own group** — killing the driver, the wrapper that
invoked it, and the shell above that. `pgid_of()` therefore returns *nothing* for a dead pid, and
the group kill fires on one conjunction: the pid is live, its pgid parses, `pgid > 1`,
`pgid == pid` (which *is* the verification that `os.setsid()` ran, since only a group leader's pgid
is its own pid), and `pgid != the driver's own pgid`. Anything else falls back to the plain pid
kill, which at worst is `ESRCH`. Both directions were demonstrated: a fatal path leaving nothing
behind, and the happy path completing with the driver, its wrapper and the harness all alive.

Two populations are outside the worker's group, and both are staged deliberately:
`--player-setsid on` (C17) makes the player its own session leader, and `--die-after popen` leaves
the group with no live leader, so the guard above correctly refuses to name it. Both are reaped
from the trace's `P_popen` pids — the only *complete* list, because a per-player record appears
only after the wrapper's `mv` and the arms that matter stage the worker's death before it — with a
live-argv identity check against `$SID`, so a recycled pid running a stranger's program is not
signalled. **C17 is cleaned up**: what it defeats is the process-group *mechanism*, not this
cleanup, which does not rely on the group.

`cleanup.sh` also carries a **per-site verdict for every other termination site in the rig**,
including the ones that were already correct — an audit listing only its defects cannot be checked
for coverage. Two entries there are worth repeating: `run_preempt.sh`'s **per-trial** kill is a pid
kill *on purpose* and must not be "fixed", because it is staging rather than cleanup — the previous
generation's orphaned player is the subject of the trial, and a group kill would destroy what the
trial measures. And `speakd_probe.py`'s `idle_exit` path exits without signalling a player still in
its group: a real gap, reached by no configuration (`--idle-exit-s 600` exceeds every run and every
player is bounded), recorded rather than closed.

## Files

| file | what it is |
| --- | --- |
| `speakd_probe.py` | the instrumented resident worker. §10.5's shape (file-drop job address, election with the owner pid recorded, `kqueue` wake, claim by `rename`), with every preemption clause independently switchable. Round 2 adds `--pid-mode {worker,shared,perplayer}` (who publishes the player's identity and where), `--publish-delay-ms` (the wrapper stays descheduled after `Popen`, so a sweep can land *before* publication), `--sweep-mode {off,record,pgid,both}`, `--sweep-gap-ms`, `--reap-delay-ms` and `--unlink-on-reap`. **Round 11 corrected the `.pending` sweep twice:** `killpg` now goes only to superseded owners whose **own generation** has a marker (one marker used to authorise every historical generation, spending the blast-radius bound the marker exists to provide), and each marker is retired only **after** its generation's group has been signalled (removing first left a crash window in which the next election finds no marker, skips `killpg`, and cannot reach the unnamed player by record either — `C12c` rebuilt out of the cleanup). Both are unrun. **Round 15 adds `--owner-identity`** (default on): the generation record's target is `<pid>.<starttime>` rather than a bare pid, and both the election's liveness test and clause 7(iv)'s `killpg` re-read the pid's current start time — a mismatch means the owner is gone and its pid was recycled, so the record authorises nothing and the marker naming its generation is **expired** (`kill_skipped reason=owner_pid_recycled`, `pending_expired`). `off` is the round-14 bare-pid arm, kept as the falsification. Also unrun. **Round 21 adds `--player-identity`** (default on): the PLAYER record's **content** is `<pid>.<starttime>` — the name shape is untouched, matching PR #27 clause 7(i) — and all three sites that signal a recorded player pid (the hook, the election record sweep, the claim-time kill) re-read the pid's start time and emit `record_skipped … verdict=recycled|unverifiable` instead of signalling. Round 21 also **replaces the election's handling of an `unverifiable` owner**: supersede only when the recorded pid is vacant, refuse while it is held (`action=refused_pid_held`), because superseding is the licence to consume jobs and nothing in the protocol observes being superseded. **Round 24 splits the `ps` reader's outcomes three ways** — present, *confirmed* absent, and lookup error — because collapsing them made every `ps` failure read as `gone`, which is the verdict that signals and supersedes. A lookup error is a fifth verdict, `lookup_failed`: every signaller refuses it (`record_skipped … verdict=lookup_failed`, `kill_skipped … reason=owner_lookup_failed`, marker kept and not expired), and the election retries `LOOKUP_RETRIES` times and then loses (`owner_lookup_failed … action=retry`, then `refused_lookup_unavailable`). `off` is untouched at every site: it decides on `kill(pid, 0)` before the start time is read at all. **Round 26 gives `--claim-kill handle` the reservation its exemption from all of the above assumed:** the reaper waits for the child with `waitid(WNOWAIT)`, which leaves it unreaped, retires the handle and reaps under `player_lock`, and `kill_player` holds that lock across its `os.kill` — so a handle is only ever signalled while its pid is still reserved, live or zombie. `handle_retired … reserved=1` records each retirement, `--claim-kill handle|both` **refuses to start** (`FATAL`, exit 5) where `waitid(WNOWAIT)` is absent, and the iteration after `Popen` uses its own local handle because the global may be retired under it at any instant. All unrun |
| `player_probe.py` | stub player. Stands in for `afplay` so the probe can record *why* playback ended. Also self-registers in the player ledger |
| `hook_probe.sh` | stand-in for `speak.sh`'s `Stop` body, in **bash**, doing only the two things §10.6 gives the hook: read `speak/pid` and kill (**K**), then publish by atomic rename (**R**). **Round 28 fixed a contradiction it emitted about its own invocation:** the round-26 unsafe-pid domain gate on the per-player path printed `record_skipped … verdict=unsafe_pid` and `continue`d without setting `found`, so the loop then also printed `result=norecord` — one hook call claiming both that a record was found and refused and that no record existed. `analyse_round2.sh`'s C14b hook-read line counts those two with independent per-line counters, so the invocation appeared in **both** buckets, and `analyse_c14.sh` saw two hook-C rows and dropped the trial from both denominators. Latent: no committed trace carries a `record_skipped` row of any verdict. The three `continue`s beside it were audited and are right as they stand — `recycled`/`unverifiable`/`lookup_failed` are one branch that already sets `found=1`, and a `.pending` marker or an unparseable name is not a player record, so `norecord` is the honest reading there |
| `lockrace.py` | row 21. Three election protocols — `current`, `spec`, `proposed` — plus a winner that can be stalled in the `mkdir`→pid-write window and racers that can be held *after* classifying a lock stale. **Round 11:** every election read is self-reporting (`election_read … saw_window=` plus the inode of the lock it read), so `run_lock.sh` can tell a trial that entered the staged window from one that quietly degenerated into a live-owner check. **Round 24 replaces S3's hold with a release barrier** (`--classify-hold-dir`, `--classify-hold-role {hold,release}`, `--classify-hold-timeout-s`): the held racer waits for a `GO` token that the reclaiming racer writes **only after its own election returns a successful reclaim**, so the ABA ordering is a fact rather than a 120 ms bet. `--classify-stall-ms` survives as the fallback for a hand-run trial and stages nothing. Either side failing records its own marker (`classify_hold_timeout`, `classify_hold_norelease`) and the driver `VOID`s the trial |
| `run_preempt.sh` | row 20 driver. One warm worker per configuration; the second hook's launch time picks which ordering the trial lands in |
| `run_all_preempt.sh` | all **twenty-six** configurations in sequence. Round 3 fixed it: the loop listed 24, omitting `C15c_norecheck_death_pgid` and `C17_setsid_player`, so a fresh run did not reproduce the published set |
| `run_real.sh` | real-audio confirmation: real Kokoro synthesis on `bf_emma`, `afplay` as the player |
| `run_lock.sh` | row 21 driver. **Six** scenarios (S1 `init`, S2 `longstall`, S3 `aba`, S4 `dualreclaim`, S5 `scratch`, S6 `deadN`) × three protocols × N × stall. **Nothing in it is staged by a clock any more, and none of that is re-run.** Round 3 replaced S3's flat 4 ms wait for the second reclaimer with a wait on `classified_stale`. **Round 5 found the fixed sleeps that repair walked past** — the 50 ms staging the dead incumbent's own record in S3, S4 and S6 — which let those trials degenerate into S5's control while still producing `owners=1`. All three now gate on `pid_written`/`published` and emit `VOID` on timeout. **Round 11 found that the S1/S2 barrier stages the *observation* and not the *election read*** — after the `GO` token the winner writes its pid while each racer performs its own second, deciding read, and nothing orders the two. The answer is detection rather than a sixth staging mechanism: `trial_init` emits `VOID` unless some racer's `election_read` saw the pid-less state **and** the winner's own lock inode. **Expect that to void most of the `stall=0` cell**, because at 0 ms the window is zero-width and no staging can put a read inside it. **Round 24 found the second clock in `trial_aba`, the one the round-3 repair left standing:** waiting for B's `classified_stale` proves B observed a dead generation and never that A reclaimed within B's 120 ms stall, so a slow A produced the same false `owners=1`. `trial_aba` now stages a per-trial **release barrier** and `VOID`s on `classify_hold_timeout`, on `classify_hold_norelease`, and on a log carrying no barrier records at all. The committed `lock-owners.tsv` predates **every** one of these fixes |
| `collect.sh` | joins the marker files, `kills.log`, `player.log` and `worker.trace` into one `trials.tsv` per run. **Round 28** corrected two things in its own header. Its coverage claim — *"everything published derives from `trials.tsv` with awk/sort and nothing else"* — was derivation defect 8's sentence, fixed in `summarise.sh` in round 16 and then written into the script that *writes* the file: `trials.tsv` is one row per **trial** and carries no trace event, so the header now names the boundary by consumer. And the column it published as **`audible_s`** is now **`pstart_to_pend_s`**: the stub player process's own start-to-end interval, `p_end_ts − p_start_ts`, from a `sleep` that opens no audio device. Header cell only — the committed TSVs differ from their previous versions on line 1 and no other line. **Round 29:** its `W_pid_write` branch tested `result != "disabled"` — a blind else — so the round-25 `publish_refused` path (identity lookup failed, player stopped through the `Popen` handle, **no record published**) stamped `W` as a successful publication; the resulting `rc=-15` then attributed to `hook-pid-kill` with no hook involved. A run containing `publish_refused` or `publish_refused_kill_failed` is now **rejected** — every caller already checks this script's exit status — and the branch names every `result` value rather than defaulting to *published*. Zero occurrences in the committed traces (harness defect 6) |
| `collect_real.sh` | turns the `REAL-*` traces into `real-audio-trials.tsv`, so section 2.6's figures re-derive like every other figure. **Round 5:** it now accepts the flat committed `traces/REAL-*.worker.trace` as well as live run directories — round 3 added the file but no way to rebuild it from anything committed — and it emits **both** bounds on the stale player's lifetime, because it had published `alive_s` as "`Popen` → exit" and that is not what `alive_s` measures. **Round 29:** its three completeness checks were all **counts**. The loop re-keys the arm from each directory name, so three run directories each yielding only trial 1 give three `REAL-off` rows numbered 1 and `n_off == 3` passes. Trial IDs are now required to be 1..`REAL_TRIALS` exactly once per arm (derivation defect 16) |
| `attrib.sh` | **the kill-attribution rule, sourced not executed — new in round 29.** It was written **three times**, in `summarise.sh`, `compare_passes.sh` and `peek_one.sh`, each reading `rc` and `player_log_sig` to answer the same question. Round 16 found the defect — the player's log could outrank the kernel's wait status — fixed the copy in `summarise.sh`, and left the other two, which were still wrong thirteen rounds later; `peek_one.sh` had the chain in the *worse* order and `compare_passes.sh` omitted `SIGALRM` altogether. A rule with three copies cannot be fixed once, so it has one copy and every consumer sources it and **refuses to run** if it is missing or defines nothing — an empty `awk` program is a legal one and would have normalised every row to the same blank value and passed. See derivation defect 7's recurrence note |
| `cleanup.sh` | **the drivers' fatal-path cleanup, sourced not executed — new in round 30.** The round-27 `EXIT` trap terminated only `$WPID`, and the worker's players are not the worker: `os.setsid()` makes the worker a group leader, so a pid kill left `afplay` holding the audio device into the next run. `kill_worker_group` derives the pgid and group-kills only on `live && parses && pgid>1 && pgid==pid && pgid!=driver pgid` — because a plain `cmd &` child reports the *invoking shell's* pgid, so an assumed pgid kills the driver and its wrapper. `reap_stray_players` then takes the players no group kill can reach (`--player-setsid on`, and `--die-after popen` where the leader is already gone) from the trace's `P_popen` pids, which is the only complete list, gated on a live-argv match against `$SID` so a recycled pid is not signalled. Sourced at the **top** of both drivers, before any worker exists, so an unreadable `cleanup.sh` fails while there is still nothing to leak — the round-30 draft sourced it at the trap, thirty lines after the worker launch, which is defect 5 re-armed by its own repair. Carries a per-site verdict for every other termination site in the rig, the ones that were already right included, and states its three residuals rather than claiming the cleanup is total |
| `summarise.sh` | the published figures **that live in the committed TSVs**, with `awk` and `sort` only — sections A-F and nothing else; the trace-event counts come from `analyse_round2.sh` (round 16 narrowed a header that claimed *every* figure).  **Round 16:** the attribution chain checks the kernel's wait status first and consults the player log only where there is none, because the log keeps the *last* of two signals and `C12b` records a process that took two. No committed figure moves. **Medians average the two middle observations** — round 1 took the lower middle, which for these even-sized samples was not the median. Round 3 added section F (the `Rdone`→`P` adversarial margin) and split section C's `P`→`W` window by who published, both because the document quoted a figure the script did not print. **Round 17:** row 21's **denominator** is validated before any section prints. The only prior check on `lock-owners.tsv` was "not empty", so a truncated run, or one missing a whole protocol × scenario cell, re-derived the 1200-trial / 400-per-protocol result over a smaller denominator and still exited 0. The expected matrix is transcribed from `run_lock.sh` — **60 cells × 20 reps** — and deliberately **not** derived from the file under test, which would make the check vacuous; rep numbers are checked too, so a merged or resumed run is caught even at the right row count. `VOID` rows still count toward the matrix, keeping this and the `VOID` check orthogonal. The validated shape now prints above row 21/A. **Round 29:** two changes. Its **section E** guard counted rows and never read the trial column, so an arm with trials `1,1,2` passed at `want=3` with trial 3 absent and the medians below read trial 1 twice — on the committed data that reads **5.4803** against the true **5.4824**; IDs are now checked as rounds 17 and 19 already check theirs (derivation defect 16). And the **attribution rule moved out of this file** into `attrib.sh`, unchanged: section A is byte-identical, and the rule is no longer one of three copies that can be fixed singly |
| `analyse_round2.sh` | the round-2 protocol facts, from the committed `traces/`. Round 3 added the `C12b` attribution (the `killpg`s actually sent, and the record sweep's unbounded target list), a `C14a` publish→destroy lag, and `C15c` alongside `C16`. **Round 5 removed that lag** — it anchored on `W_pid_write`, which in `C14a`'s `pid_mode=shared` is the parent's deferral stamp, so it never measured from publication — and replaced it with two soundly-ordered counts, which also cut the `C14a` destruction count from 24 unlinks to **8**, on **4** trials rather than 12. **Round 17 made that 8-and-4 a derivation instead of an assertion:** the two counts were global and shared no key, so their *sum* was printed as the destruction total and the sentence *"they fall in the same trials and are distinct unlinks"* was stated rather than derived. The `C14a` block now takes a **third input**, `<cfg>.markers.tsv` — `hook-kills.log` tags its rows `tNc` but carries **no timestamp**, and `tNc entry` is that timestamp — and joins on `(trial, unlink timestamp)`, binding each hook-C witness to **one** unlink. **Round 21 replaced the binding argument**: round 17 used the window `(W_pid_write[jNb], tNc entry)`, whose lower end is the *parent's* deferral stamp taken after `Popen` returns while the wrapper is already running — harness defect 4, reintroduced as a bound by the block that had withdrawn a lag figure for it. No observed publication instant exists in these traces, so the binding is now a **uniqueness** argument that needs none: the record was certainly published before the player's own `player_start`, hook C read nothing while that player was live, and the reaper's `os.unlink` is the only thing in this arm that removes a record — so **exactly one** `record_unlinked` between the b-job's spawn and hook C names the destroyer. The interval is `(S2_prespawn_stat[jNb], tNc R)`, whose lower end is emitted before `Popen` and therefore before the fork, and the trial filter is gone because an unlink from another trial in that interval is a genuine candidate. `W_pid_write` is no longer read by the block at all. **Round 24 moved the upper end out from `tNc entry` and moved the liveness test with it:** `entry` is the hook's first act while the read happens after `K` and the record scan, so the b-player must be shown live **across** `(K, R)` rather than at `entry`, and the candidate interval must reach `R` because that is the latest the scan can have been. Both changes can only make the check refuse. It prints the **union** of distinct events with the intersection computed, the distinct **trial** count, and each event's **rank** within its trial. The committed traces give 0 intersection, ranks #1 and #2, and the same **8 across 4** — byte-identical output through all three repairs. An ambiguous interval or an absent marker **narrows** — the trial counts, the event does not. The hook-read tally block above it no longer claims a live player either: it reads only `hook-kills.log`, which carries no timestamps, so it states the count and points at the witness that can settle liveness |
| `verify_fires.sh` | every hook stamps `$TAG.entry` before it does anything, so a hook that never ran is distinguishable from one that measured zero. **Round 5:** it read a `RUNS.txt` that exists only in a live run tree, so pointed at `traces/` it iterated over nothing and printed *"all hooks fired"* — a null reported as a pass, by the guard against exactly that. It now reads the committed `<cfg>.markers.tsv` too and exits 2 over zero inputs. **Round 10** added `expected-configs.txt` so a *partial* set could not read as a pass either, and that is where the committed evidence stands: **`verify_fires.sh traces 12` prints 21 `OK` lines, then `MISSING` for `C1_prespawn`, `C2_hookside`, `C5_norecheck`, `C6_handle` and `C7_noreap`, and exits 2.** The five have their twelve trial rows in `preemption-trials.tsv`; what they lack is the hook-fired marker evidence, so for those five alone a hook that never fired is indistinguishable from one that measured nothing. **The right response is to re-run them, not to loosen the guard.** **Round 16** made it an EXACT-SET check: a name may appear neither twice nor at all outside the manifest, because three of the four run scripts append to `RUNS.txt` and a re-run therefore left a duplicate that this guard passed and `assemble.sh` counted twice. **Round 29** added a **tag** check beside the count: `entry=25` passed whether the tags were `warmup + t1..t12` or a set with `t3a` twice and `t7b` never — *"all hooks fired"* over a trial whose hook did not. The expected tag set comes from the hook contract in this script's header, not from the file under test. Deliberately a narrower claim than its two siblings: in a live tree the tags are filenames and unique by construction. The committed evidence is unaffected — still 21 `OK`, the same five `MISSING`, exit 2 |
| `analyse_c14.sh` | hook C's reachability of a live player in the `C14` arms. **Corrected in round 3** — it had tested only that an END record existed, which every completed player satisfies — and **again in round 24**, because `tNc entry` is the instant the hook *started* and the `nopid` read happens after `K` and the record scan. Blind rows now require the b-player live **across** the scan (`start <= tNc K` and `end > tNc R`); reached rows are joined to their own trial's b-player by the kill itself, which is the only evidence available since the kill is what ends that player. **Round 25 narrowed `reached` to `result=sent` and round 26 found that this MOVED the misclassification rather than removing it:** `blind` was the `else`, so `esrch` and `record_skipped` rows — a record found and skipped is the *opposite* of an absence, and it carries no `result=` at all — landed in the arm that means *"the hook found no record"*, where they would have been published as record destructions. `blind` now requires `nopid` or `norecord` **by name**, every other outcome is excluded **by name and printed**, a trial with more than one hook-C row is excluded instead of silently reduced to its last row, and the arms plus the exclusions are asserted to sum to 12. All figures unchanged, **4 of 12** and **0 of 12**. Reads the committed `traces/` directly: `analyse_c14.sh traces` |

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
real-audio arm (`run_real.sh`) runs that same ordering against a **real player decoding a
real wav** instead of a `sleep`.

**It does not answer audibility, and this section used to say it did** — *"the one thing
the stub cannot: whether the stale utterance is audible"*. Round 27: **nothing in this rig
listens.** Every figure the arm produces is an `afplay` **process** stamp, `afplay`'s
time-to-first-sample is instrumented nowhere, and a newer `afplay` process existing does
not establish when its output became audible. Audibility needs a loopback capture of the
output device, which no script here performs; see the decision document's §2.6 and its
derivation defect 14, which lists every site that had the wording wrong.

**And the STUB arms carried the same wording in the schema until round 28** — derivation
defect 15. Column 18 of both committed preemption TSVs was named `audible_s` across **444
rows** whose player is `player_probe.py`, a `sleep` that opens no audio device at all;
`collect.sh` wrote that header, `summarise.sh` section B was headed *"was the stale utterance
audible, and for how long"*, and `player_probe.py`'s own docstring called its `player_start`
an *"audible from"* stamp. Round 27's correction was a list of **sentences** and a column name
is not a sentence, which is why it survived where a consumer would read it. The column is
`pstart_to_pend_s` now, `0(never_started)` says what it actually bounds — the kill landed
inside interpreter startup — and **no value changed**.

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
