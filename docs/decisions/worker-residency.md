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

- `speak-probe.sh` — a throwaway `Stop` hook that walks §10.3's steps 1–9 and then drops a job and
  exits. Written in `zsh -f`, **not** bash, for one reason: bash 3.2 is the only bash on this machine
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
  the exact path §3.1 says `rewrite.sh` publishes. `rewrite.sh` is not running in a driven session, so
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
cost, **6–38 ms, median 8.9 ms** (n = 38). That narrows the race by two to three orders of magnitude.
It does not close it, and saying otherwise would repeat the mistake this subsection exists to correct.

**(c) Keep §10.6's `speak/pid` and its hook-side kill, and reassign only the writer.** **[inferred]**.
Row three — a newer message while the older is *playing* — is the case §10.6 already specifies, and its
mechanism survives residency intact: the pid file at `$BUF_ROOT/<session_id>/speak/pid`, killed by the
next hook invocation before it drops its job. What changes is **who writes it.** §10.6 says "the speech
child"; under residency there is no per-turn speech child, so **the worker writes the player's pid
there** after spawning it. With that, playback already in progress dies within the hook's own wall cost
— **median 0.086 s, max 0.219 s** measured — which is a *tighter* bound than the worker-side kill the
probe used, because the hook runs before the worker has noticed anything at all. **But it is not a
replacement for the worker-side kill, and an earlier draft of this document treated it as one.** That
error is corrected in (d).

**(d) Keep the worker-side kill as well, and move it to job-claim time. [inferred]** Review of this PR
found a hole in (b)+(c) taken together, and the hole is real. Write out the two orderings. The hook, per
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
worker's pre-spawn stat already passed. And R < S < P < W is not a hair-splitting window: the hook's own
wall cost between its kill and its rename is **0.063–0.219 s, median 0.086 s** measured, while the
worker's S→P gap is one `Popen` plus one small write. The wide window is the hook's, and it comfortably
contains the narrow one.

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
| after the worker writes `speak/pid` | the **hook**, directly — within its own wall cost, median **0.086 s** |

So (c) is a latency optimisation that fires when it happens to see a live pid; **(d) is the correctness
guarantee**, and it is the worker's, because the worker is the only party that knows it spawned a
player. Adding a post-spawn stat as well is cheap and worth doing — it catches the common case without
waiting for a wake — but it is not what makes the mechanism sound. **§10.6's semantics need both the pid
file and the worker-side kill; residency should drop neither.**

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
  the newer job is published** — bounded by the measured **0.079 s** and **0.086 s** respectively, plus
  a residual **6–38 ms** window between the pre-spawn stat and the spawn in which a player starts at all.
  On that reading §10.6's semantics hold.
- **Only then** is synthesis cancellation reduced to a latency question — the *newer* utterance waiting
  out up to one wasted `create()`, 0.49–4.23 s. **Without (d) it is a correctness question**, because a
  stale utterance plays to completion unkilled.

**Routed to §10.6 as OPEN with that reduced scope stated, and with the reduction explicitly conditional
on (d) shipping.** The measurement that would confirm or refute (b), (c) and (d) is named in *What I
could not measure* below.

### 2. The election is `mkdir`, and it lives in the worker

`os.mkdir($SPEAK_DIR/worker.lock)` with the pid written inside it, checked with `kill -0` and torn
down if stale. This is §10.6's lock/PID-file idiom, one directory over from the `speak/pid` the
preemption rule already puts there.

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

The worker blocks on `kqueue(EVFILT_VNODE, NOTE_WRITE)` over the speak directory's fd, with a 1 s
timeout as a belt. A rename into the directory wakes it.

**Measured hook-to-worker handoff, warm: median 0.079 s, range 0.059–0.198 s** **[hook]**. That
interval contains the whole hook — `jq` three times, `shasum`, the job write, the rename — plus the
kqueue wake. It is not the bottleneck and no cleverness is owed here.

### 4. The warm-up trigger is *every* `MessageDisplay` invocation — **not** §3.1's publish point

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
  whose default budget is `CLAUDISH_TIMEOUT=45` seconds (`rewrite.sh:66`). **[repo]**
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

**Worse, on short turns the publish point never fires at all.** `rewrite.sh:145-155` gates on
`prose_len < MIN_CHARS` (default **200**, `rewrite.sh:64`) and returns without producing a rewrite.
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
(median 7.5 ms across sixteen turns, sign not guaranteed), and a fifty-character reply streams in a
single chunk, so its only invocation *is* the final one. On turn 31 all three of its invocations landed
after `Stop`'s clock read, and all three found no worker and spawned one — the election then discarded
two. There is nothing left to explain about hook dispatch ordering; the ordering is a consequence of
chunk count, which is a consequence of message length.

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
| `warm30` | 30 | warm: median 1.216 s, range 0.573–4.014 s, 28/30 under 3 s |
| `warm30+mdwarm5` | 5 | warmed-during-turn: median 1.710 s, range 1.373–3.829 s, 4/5 under 3 s |
| `concurrency-probe`, `slow-cold-outlier` | 1 each | excluded from every aggregate above, by name |

`ready_lead_s` is `t_stop − t_worker_ready`: **positive means the worker was resident before `Stop`
fired**, which is the mechanism working. It is positive exactly on the five `mdwarm5` turns
(3.051–4.619 s) and negative on every cold turn (−1.382 to −1.734 s), which is the mechanism's whole
claim in one column.

### 5. The worker does a warm-up synthesis at startup

`kok.create("Warming up.")` before announcing readiness — `bench/bench.py:471-475` already does this
and says why (**[repo]**).

**Measured, and it is not free either way.** The first `create()` on a freshly loaded model is
markedly slower than the steady state: the same item (`r01`, 88 chars spoken) took **2.13 s** as a
worker's first synthesis versus **1.41 s** on a worker that had already spoken. The warm-up costs
**0.78–1.12 s** of startup, which pushes exec→ready from 0.80–1.30 s to **1.33–2.02 s** and therefore
lengthens the streaming lead the mechanism needs. Net: **a win when there is lead time, a wash when
there is not.** Recommended, with the trade named.

### 6. Idle exit at 30 minutes

Matching `rewrite.sh:117`'s existing sweep window, so a worker never outlives the directory it
depends on. **Not measured** — the runs here are minutes long. Stated as a design choice, and it does
re-introduce a cold start after half an hour of silence, which is the honest cost.

---

## The alternatives, and why each loses

| alternative | verdict | on what basis |
| --- | --- | --- |
| **fresh interpreter per turn** | rejected | already rejected by the spec on #6's 3.93 s; this run's cold rows (2.66–5.50 s from a hook) agree and are worse |
| **HTTP server on a port** | rejected | #5 declined it on measured evidence; independently, a file drop answers every question a port raises without opening one |
| **Unix domain socket** | rejected | **[obs]** `bind()` fails at the real path depth — 116 bytes against a 104-byte `sun_path`. The relative-path workaround works but needs `nc -U` in the hook and buys nothing |
| **`launchd` user agent** | rejected, **not measured** | it would be permanently resident and would survive machine sleep, which is genuinely better on latency. It loses on three other counts: it installs a background daemon for a feature that is **off by default** (§11), it is outside `rewrite.sh:117`'s sweep so nothing reclaims it, and it has no per-session scoping, which makes §10.6's per-session pid file meaningless. **This is a judgement, not a measurement**, and it is the alternative a reviewer should push back on if they think the latency is worth the footprint |
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

Turns 37–40 pay a startup warm-up synthesis that turns 1, 7 and 31 do not; that is why their
`hook→worker` is longer and their `synth` far shorter. It roughly cancels.

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

### §10.5 — the OPEN heading comes off, with the limits attached

The mechanism, in six clauses, each measured above:

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

And the closing condition §10.5 set for itself is now met, with this result:
**cold from a hook is 2.66–5.50 s (median 3.16 s) and fails the 3 s line; warm from a hook is
0.57–4.01 s (median 1.22 s) and holds it 28 times in 30.**

### §10.6 — two qualifiers, and its pid file survives residency

§10.6 stays LOCKED and this document reopens none of its decisions. It needs two qualifiers, both from
§1b, because §10.6 was written for a design in which the hook spawned the speech child and could
therefore kill the previous one itself.

1. **Its `speak/pid` mechanism is still the right one; it now has a different writer.** §10.6 says the
   pid is "written by the speech child". Under §10.5's mechanism there is no per-turn speech child, so
   **the resident worker writes the player's pid there** after spawning it, and the next hook invocation
   kills it exactly as §10.6 already says. Playback in progress therefore dies within the hook's own
   wall cost, median **0.086 s**. Without this sentence an implementer reads §10.6 and finds nothing
   left in the design that writes the file.
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

Cancelling an in-flight `create()` stays **OPEN** and stays in §10.6 rather than §10.5. **Its scope
reduces to the newer utterance's latency rather than the older one's suppression only once clause (ii)
above is in — without it, stale suppression is itself unsolved and the OPEN is a correctness OPEN, not
a performance one** — §1b.

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

§13 **row 12** (warm-up-on-wake vs a late first utterance) is untouched and stays open and
non-blocking, as it was scoped. Nothing here measures a sleep/wake; #5's ~4.9 s post-wake figure
still stands unchallenged. What this document does change about row 12 is that the *decision* is now
cheap: the mechanism already has a warm-up trigger and a wake handler would reuse it.

---

## What I could not measure, and why

- **Sleep/wake.** Requires actually sleeping the machine, which was out of scope and disruptive to
  four live sessions. #5's ~4.9 s stands unmeasured-here. §13 row 12 unchanged.
- **The settled #13 sanitizer combination**, because §13 row 1 has not shipped it. `base` was used;
  the sanitize phase is 0.2–9.2 ms and does not move the result.
- **The shipped hook in bash.** The probe is `zsh -f`, for the clock. The hook's measured wall cost
  (0.063–0.219 s, median 0.086 s) is dominated by three `jq` invocations and a `shasum`, not by the interpreter, so I
  expect bash to land in the same band — **but that is an expectation, not a measurement.**
- **The hook's causal contribution to the bench-to-hook gap**, because the control shares hardware but
  not load or cadence — see *The control* above. What is owed is **interleaved paired runs**: the same
  corpus item synthesized alternately through `bench/first-sentence.py` and through the hook, A/B/A/B in
  one session, so both arms see the same load and the same spacing. Until then the ~0.37 s gap is
  decomposed by reasoning, not isolated by experiment.
- **Preemption, in every case except coalescing.** Nothing here drove a second job at a worker that had
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
- **The stale-lock recovery protocol in §2a.** Both clauses are **[inferred]**. Provoking the real
  window means pausing a winning worker between its `mkdir` and its pid write, which again needs an
  instrumented worker. Worth doing in the same run as the preemption experiment: **start N workers
  against a lock held by a worker deliberately stalled before its pid write, and count how many end up
  believing they own the session.** The current protocol should produce 2; the corrected one, 1.
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
  any page-cache penalty — 3 of 7 cold hook turns are over the line. A larger cold number makes an
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
