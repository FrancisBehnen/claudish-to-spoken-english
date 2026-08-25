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

So the machine is the same machine. **Every difference between the bench column and the hook columns
below is caused by the hook, not by the hardware.**

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
the `MessageDisplay` publish point, not only from `Stop`.**

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
probe used, because the hook runs before the worker has noticed anything at all. The probe put the kill
in the worker (**[rig]**, `speak()`: `_PREV_PLAYER.kill()`), which works and is simpler, but pays the
newer job's entire synthesis first. **§10.6 as written is the better design on this axis and residency
should not quietly drop it.**

**What remains genuinely OPEN, and it is smaller than it looks.** Interrupting an in-flight `create()`
is not solved by any of (a)–(c), and I am **not** specifying it: the two candidates I can see both carry
costs nothing here has measured — synthesizing in a killable child forfeits the residency this document
just bought, since the child cannot hold the model, and chunking the text to check between chunks
interacts with `kokoro_onnx._split_phonemes` in ways nobody has looked at. But note what (b) and (c)
leave for it to do. With them, **no stale utterance is played and §10.6's semantics hold**; what
synthesis cancellation would additionally buy is only the *newer* utterance's latency — up to one wasted
`create()`, 0.49–4.23 s, of delay. That is a performance question, not a correctness one. **Routed to
§10.6 as OPEN with that reduced scope stated.** The measurement that would confirm or refute (b) and (c)
is named in *What I could not measure* below.

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

### 3. The wake is `kqueue`, and it costs nothing worth naming

The worker blocks on `kqueue(EVFILT_VNODE, NOTE_WRITE)` over the speak directory's fd, with a 1 s
timeout as a belt. A rename into the directory wakes it.

**Measured hook-to-worker handoff, warm: median 0.079 s, range 0.059–0.198 s** **[hook]**. That
interval contains the whole hook — `jq` three times, `shasum`, the job write, the rename — plus the
kqueue wake. It is not the bottleneck and no cleverness is owed here.

### 4. The warm-up trigger is `MessageDisplay`, and this is the part that closes the blocker

**A worker started by `Stop` is warm for turns 2..n and cold for turn 1.** That is the whole of the
residency problem, and started-by-`Stop` does not solve it: measured cold median **3.16 s**, over the
line.

But this plugin already has a hook that fires **during** the turn. §3.1 has `rewrite.sh` publishing
the finished rewrite into `speak/` from `MessageDisplay` — seconds before `Stop` fires. If the publish
also ensures the worker exists, the model load is paid **while the model is still talking**, and by
the time `Stop` arrives the worker is resident.

**Measured, on a fresh session with no worker running, driving a 400-word streaming reply:**

| | measured **[hook]** |
| --- | --- |
| first `MessageDisplay` hook fires, before `Stop` | **5.16 – 6.23 s** |
| worker becomes ready, before `Stop` | **3.05 – 4.62 s** |
| `Stop` finds a resident worker | yes, `started=no`, every time |
| TTFA on that first turn | **1.37 / 1.66 / 1.71 / 2.23 / 3.83 s** — median **1.71 s**, 4/5 under the line |

That is the claim the blocker asks for, and it is measured rather than argued: **the mechanism moves
the cold start out of the user-visible path on the first turn of a session, not merely on the second.**

**And here is where it fails, measured, not hypothesised.** Drive the same fresh session with a reply
of fifty characters and the lead disappears:

```
1787668956.179   Stop hook    process starts
1787668956.243   MessageDisplay hook process starts     <- 0.064 s LATER
```
**[hook]** — TTFA that turn: **4.489 s, cold**.

**The `MessageDisplay` hook process started 64 ms *after* the `Stop` hook process, on a turn whose
message had already been displayed.** I did not expect that and I cannot explain it from anything I
have read; hook *dispatch* order is evidently not message order when the whole turn takes a second.
It is recorded as observed and unexplained. The practical rule it yields is unambiguous and should go
in the spec as a stated limit:

> **Warm-up-on-`MessageDisplay` covers the cold start if and only if the turn's message streams for
> longer than the worker takes to start (**1.33–2.02 s** measured, n = 8). On a very short, very fast first turn
> it provides no lead at all and the first utterance is cold.**

That limit is tolerable, and here is why, stated as reasoning rather than measurement
**[inferred]**: a fifty-character first message is exactly the band §3.3 and §9 are about, and
whichever way §3.5's table resolves it, one late first utterance per session is the worst case. It is
not tolerable to leave *unstated*, which is what §10.5 does today.

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
inside that range, so nothing here contradicts #6 — it locates it.

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
   guarantee. Eight simultaneous hooks → one worker, observed.
3. **Wake**: `kqueue`/`NOTE_WRITE` on the speak dir, 1 s poll as a belt. Handoff median 0.079 s.
4. **Warm-up trigger**: the `MessageDisplay` publish point already specified in §3.1 also ensures the
   worker. **Stated limit:** this covers the cold start only when the message streams longer than the
   worker's 1.33–2.02 s startup; on a very short first turn it provides no lead and the first utterance
   is cold.
5. **Startup warm-up synthesis**, per `bench/bench.py:471-475`. Costs 0.78–1.12 s of startup, saves
   ~0.7 s on the first real utterance.
6. **Idle exit** at 30 minutes, matching `rewrite.sh:117`'s sweep. Re-introduces a cold start after
   half an hour of silence.
7. **Preemption is §10.6's, not §10.5's**, but §10.5 owes it two hooks: the worker writes the player's
   pid to `speak/pid` so §10.6's hook-side kill still has something to kill, and the worker re-checks
   `speak/job` after `create()` and before `Popen`, discarding the audio if a newer job is waiting.
   Both **[inferred]**, neither measured — §1b.

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
2. **"A newer message kills stale playback" needs one more clause to be true.** A message newer than a
   synthesis *in progress* is not covered by the pid kill — no player exists yet to kill. It is covered
   by the worker re-checking `speak/job` after `create()` and before `Popen` and **discarding** the
   finished audio if a newer job is waiting. Add that clause, and state the residual: a job landing
   inside the **6–38 ms** between that check and the spawn still plays.

Cancelling an in-flight `create()` stays **OPEN** and stays in §10.6 rather than §10.5, with its scope
reduced to the newer utterance's latency rather than the older one's suppression — §1b.

### §4 — the headline number survives, restated

§4's TTFA paragraph currently reads as a property of the feature. It is a property of the bench
harness, and the difference has now been measured rather than assumed. Proposed shape:

> **TTFA on the chosen voice, measured from the hook: median 1.22 s, 28/30 under 3 s** (n = 30,
> `bf_emma`, resident worker). The bench-harness figure of 0.86 s median remains correct for what it
> measures; the ~0.37 s difference is 0.08 s of hook overhead and ~0.29 s of `Kokoro.create()` running
> cooler outside a back-to-back loop. **Cold — no resident worker — is 2.66–5.50 s and fails the
> line**; §10.5's mechanism exists to ensure the user is not in that case, and measurably succeeds on
> the first turn of a session when the message streams for more than ~2 s (the worker needs 1.33–2.02 s to start).

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
- **A cold page cache.** Purging it needs `sudo`. Every "cold" row here has the 310 MB model file warm
  in the page cache, so **every cold figure in this document is optimistic**, including #6's 3.93 s,
  which was measured under the same condition. A genuinely cold first synthesis after a reboot is
  slower than 5.5 s by an unknown amount.
- **The settled #13 sanitizer combination**, because §13 row 1 has not shipped it. `base` was used;
  the sanitize phase is 0.2–9.2 ms and does not move the result.
- **The shipped hook in bash.** The probe is `zsh -f`, for the clock. The hook's measured wall cost
  (0.063–0.219 s, median 0.086 s) is dominated by three `jq` invocations and a `shasum`, not by the interpreter, so I
  expect bash to land in the same band — **but that is an expectation, not a measurement.**
- **Why `MessageDisplay`'s hook process started after `Stop`'s on a short turn.** Observed, twice,
  reproducibly; unexplained. I did not read the binary for hook dispatch ordering.
- **Preemption, in every case except coalescing.** Nothing here drove a second job at a worker that had
  already claimed the first: the driven session issued turns sequentially, and the eight-hook race
  dropped all eight before any worker was ready. So §1b's rows two and three are **reasoned, not
  measured**, and §1b's (b) and (c) are proposals rather than results. The measurement owed is small and
  specific — **fire two `Stop` hooks roughly 0.5 s apart at a warm worker and record whether the older
  utterance is audible at all** — and it needs the hook-probe rig, which another agent holds an
  exclusive lease on, so it was not run.
- **Whether any of this holds on hardware that is not an M3.** Nothing here is portable evidence.

## One place my expectation was contradicted

I expected `MessageDisplay` to always precede `Stop` by seconds, because the message is displayed
before the turn ends. **On a fifty-character reply it did not** — the `Stop` hook process started
64 ms first. The mechanism still works, but it works *because the message is long*, not because the
event ordering guarantees anything. Had I only tested long replies I would have written a stronger
claim than the evidence supports, and it is worth saying that the short-reply case was an
afterthought that turned out to be the interesting one.

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
