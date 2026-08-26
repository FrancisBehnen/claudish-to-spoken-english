# The §3.2 handoff, measured: the strings agree and the timing does not

Closes ship blocker **3** of [#11](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/11)
— [the spec's](speech-integration-spec.md) §13 row 3, *"the §3.2 handoff match rate"*. Also closes
**row 4** (does `MessageDisplay` carry `prompt_id`?) and **row 7** (does `Stop` fire again after a
background task wakes the session?), both of which fell out of the same instrumentation for free.
Part of the [Kokoro speech map (#1)](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/1).
Established 2026-08-25 against Claude Code **2.1.245**.

**The rate is 35 of 35 — 100%, byte-identical, not merely trim-equal.** §3.2's content-hash key
survives exactly as specified, and no normalisation is needed to rescue it. That was the question
this blocker asked, and it is answered.

**It is also no longer the interesting question.** Instrumenting both sides surfaced something the
spec does not model: **`Stop` does not wait for the `MessageDisplay` hook.** It is dispatched
concurrently with the final streamed chunk — a median of 6.7 ms after that hook starts, and
**crucially, by a gap that does not change when the hook is made 65× slower**. `rewrite.sh` publishes
its buffer only after an LLM call that takes seconds, so at the moment `speak.sh` runs, the buffer
holds the **previous** message: measured stale in 29 of 30 turns, identified by content. (This was
measured against the mutable `speak/source` the spec then had; §3.1 has since replaced it with a
content-addressed `speak/rw.<H>`. **Two results have to be separated here, and an earlier revision of
this note ran them together.** The **timing** survives the change untouched: it is a fact about when
`Stop` runs relative to the publish, and the publish is still seconds after the final chunk. The
**staleness** does not, and cannot: under content addressing a consumer for `H` finds `rw.<H>`
**absent** until publication — it cannot read the previous message from that path at all, unless
identical text was published earlier — so the 29-of-30 "the buffer held the previous message" figure
is **historical**, and what the same timing now implies is a **miss**, not a stale read.
**The distinction is not pedantry: it is why the current design is in a better position than the
measured one.** With a mutable buffer §3.2's compare is what stops the wrong answer being spoken;
with content addressing there is no wrong answer at that path to speak, because the path is not
there. Every remaining analysis of `speak/source` in this document is historical.) The hashes
then correctly disagree, §3.5's last row fires, and the feature is quiet — for a reason that has
nothing to do with the match rate and everything to do with ordering.
[Section 4](#4--the-finding-that-outranks-the-rate-stop-does-not-wait-for-messagedisplay) is that
measurement. **It is a new ship blocker, and this document proposes it rather than filing it.**

**That section was re-measured from scratch before this document was trusted.** A second, independently
designed probe on a second session — committed and runnable at
[`handoff-timing-probe/`](handoff-timing-probe/) — reproduced the ordering over 32 turns and tightened
it. It also **withdrew** one claim (a "−5 ms" lower bound implying `Stop` sometimes went first: not
reproducible, 32 of 32 positive) and **narrowed** another (not "every turn" — a ~10% tail of turns
escapes). Section 4 carries both corrections.

**No plugin hook was touched** — `rewrite.sh`, `rewrite-md.sh`, `providers.sh` and `hooks/` are
unmodified. **`~/.claude/settings.json` was never written**; the probe hooks were scoped to one
throwaway `claude --settings` session, in a throwaway directory, and are gone.
[Teardown is recorded below.](#the-probe-as-it-was-run) **No LLM was called by any bench or corpus
tooling.** Thirty-three synthetic prompts were driven through a second `claude` session — the method
#11's own blocker prescribes — which with two background-task wakes produced the 35 turns. Nothing
else spent a call.

---

## How each fact below was established

| tag | source | what it can and cannot prove |
| --- | --- | --- |
| **[obs]** | 35 paired captures — one `Stop` payload and the matching `MessageDisplay` delta stream — from one driven session on 2.1.245, 2026-08-25, plus a 3-turn pilot on an earlier probe build | proves this build did this, on these turns, with this model. One session, one build, `sonnet` at high effort. It cannot prove behaviour under another model, a blocked turn, or an interrupt. |
| **[obs2]** | 32 paired captures from a **second, independently designed probe** on a **second session**, 2026-08-25, `haiku` — probe and output both committed at [`handoff-timing-probe/`](handoff-timing-probe/) | the section-4 re-verification. Same build, different probe, different model, different session, and it is **reproducible**: anyone can re-run the kit. Still one machine and one build. |
| **[bin]** | `strings -n 6` over `~/.local/share/claude/versions/2.1.245` | what is compiled into the build actually running |
| **[repo]** | `rewrite.sh` and `hooks/hooks.json` in this checkout | what the plugin does today |
| **[docs]** | <https://code.claude.com/docs/en/hooks.md> | states intent; can lag or lead the installed build |

Every number below comes from the raw capture, which is [tallied in full](#the-raw-tally). **The
message bodies are not in this repository and are not in this document** — the repo is public and the
captures are real assistant output. What crossed the line, exactly: byte counts, chunk counts, diff
shapes, **the first 12 hex characters of each `sha256`**, and **the first 8 hex characters of each
`prompt_id`**. The bodies stayed in the scratchpad and went with the teardown.

The two truncated identifier columns are committed deliberately, and are worth being precise about
rather than filed under "hashes". The `prompt_id` prefixes are there so the multi-message turns can be
seen grouping (rows 25–26 and 31–32 share their turn with a sibling), and the `sha256` prefixes so a
reader can check the MD and `Stop` columns agree row by row without being handed the text. Neither is
a body and neither reverses into one: a truncated digest is not invertible, and a `prompt_id` is a
harness-internal handle for a turn in a session that no longer exists. But both **are** identifiers,
so calling them out here is the accurate disclosure — the earlier wording named only "hashes, byte
counts, flush counts and diff shapes", which did not cover the `prompt_id` column at all.

---

## The four answers, in one table

| # | question | answer | tag |
| --- | --- | --- | --- |
| 1 | Does `Stop.last_assistant_message` equal `rewrite.sh`'s delta concatenation? | **Yes. 35/35, byte-identical.** Not one mismatch of any shape. | **[obs]** |
| 2 | Why do they agree — and where could they stop agreeing? | The harness joins **text blocks only**, on `"\n"`. **No message in 50 had two text blocks**, so the join has never had anything to join. That is the untested edge, not a passed test. | **[bin]** + **[obs]** |
| 3 | Does `MessageDisplay` carry `prompt_id`? | **Yes**, on all 94 payloads, and it is **the same value** `Stop` carries, 35/35. §13 row 4 closes. | **[obs]** |
| 4 | Is the buffer *there* when `Stop` reads it? | **Almost never — 29 of 30 turns it held the previous message.** `Stop` starts a median 6.7 ms after the final chunk's display hook and does not wait for it; the publish lands seconds later. Re-measured over 32 turns with a committed probe. | **[obs]** |

---

## 1 — The rate is 35/35, and the matches are byte-identical

**Method.** Two throwaway hooks in one scoped settings file. The `MessageDisplay` probe wrote each
`.delta` to `<message>/<index>.part` and, on `final: true`, concatenated the parts in index order —
**the same assembly `rewrite.sh:135` performs**, down to the command substitution. The `Stop` probe
dumped the whole payload. Nothing else: the display hook emitted no stdout, so what was on screen was
untouched, and both probes exit 0 on every path.

**The comparison is the one §3.2 specifies**, `sha256(trim(x))` on both sides, with `trim` implemented
as JavaScript's `String.prototype.trim` character set so it matches the harness's own
`.trim()` **[bin]**.

**Result: 35 exact matches out of 35 Stop payloads. Rate 100%.** [Full tally below.](#the-raw-tally)
A 3-turn pilot on an earlier build of the same probe gave 3/3 and is not counted in the 35.

**Every match was byte-identical before the trim was applied.** The trim never had to do anything:
across the **44** captured message streams, **none** carried leading or trailing whitespace in its
delta concatenation. So `sha256(trim(x))` and `sha256(x)` agreed everywhere, and §3.2's `trim` is
**defensive and unexercised** rather than load-bearing. Keep it — the harness's own `.trim()` is
**[bin]**-confirmed and a future build could start emitting a trailing newline — but do not believe
it is what makes the rate 100%.

### The mix, stated so the rate can be discounted properly

A rate measured only on short prose would be worthless. What was actually driven, over 35 turns:

| shape | turns |
| --- | ---: |
| final message carrying at least one fenced block | **9** (32 fences total; **6 in one message**) |
| three or more paragraphs in the final message | 11 |
| final message under 20 bytes (bare acknowledgements) | 7 |
| turns with at least one tool call | 10 (16 `tool_use` blocks) |
| turns with more than one assistant message | 10 — of which **4** had more than one *text-bearing* message |
| turns with a subagent | 2 |
| turns whose final message arrived in more than one flush | 16 (up to **9 flushes**) |
| turns with a `thinking` block | 8 |
| final-message size | min 1, median 413, max 3,770 bytes |

The fence case was targeted deliberately, because §15 records `r14` keeping only 1 of 3 fences and a
dropped paragraph taking its fence with it. **Nothing was dropped.** The 668-byte message carrying
**six** fence markers and the 3,770-byte message carrying six more both reproduced exactly, fences
included, across five and nine flushes respectively.

Multi-flush is the case worth naming, because it is the only place the concatenation can go wrong at
all: 16 of 35 final messages arrived in more than one `MessageDisplay` flush, and the deltas
reassembled byte-for-byte every time. The schema's warning — *"the delta of the final flush is empty
when the message ends on a newline"* **[bin]** — never produced a divergence, because the newline had
already arrived in the preceding delta.

---

## 2 — Why they agree, and the one edge that is still untested

`last_assistant_message` is built by one function. **[bin]**:

```js
let p = i ? bb(i) : void 0,
    f = p ? Cs(p.message.content, `\n`).trim() || void 0 : void 0;
```

with

```js
function bb(e){ return e.findLast((t) => t.type === "assistant") }
function Cs(e, t = ""){ return e.filter((n) => n.type === "text").map((n) => n.text).join(t) }
```

So the field is: **the last assistant message; its `text` blocks only; joined on `"\n"`; trimmed;
collapsing to `undefined` when empty.** Three consequences, all of them now confirmed on the wire:

- **`thinking` blocks are filtered out.** 8 of the driven turns carried one, and **6** messages
  carried a `thinking` block in the same message as the answer text. All matched exactly, so
  `MessageDisplay` does not stream thinking into `.delta` either. **[obs]**
- **`tool_use` blocks are filtered out.** 16 tool calls across 10 turns, and — the case worth
  having — **9 messages of shape `text+tool_use`**, where narration and a tool call share one
  message. The narration reached the display stream, the tool call reached neither string, and every
  one matched. **[obs]**
- **The `"\n"` join is the risk, and it never fired.** Of **50** assistant messages in the driven
  transcript, **not one had two `text` blocks.** The complete shape census over the 50 assistant
  messages the 35 turns produced: `text` 29, `text+tool_use` 9, `thinking+text` 6, `tool_use` 3,
  `thinking+tool_use` 2, `tool_use+tool_use` 1. **[obs]**

**One byproduct worth recording, because §3.1 depends on it.** Exactly **44** of those 50 messages
carried at least one `text` block, and exactly **44** `MessageDisplay` streams were captured — a
clean one-to-one. **`MessageDisplay` fires once per text-bearing assistant message and not at all for
a `tool_use`-only one**. That is why 10 turns held more than one assistant message but only 4 held
more than one message `rewrite.sh` would ever see. **[obs]**

**This is the honest caveat on the 100%.** §3.2 worried that *"for a final message that mixes text
with other content blocks they may not be [identical]"*. Mixed messages occurred and were fine — the
filter handles them. What did **not** occur is the case the `join("\n")` exists for: a single message
with **two or more separate text blocks**. Thirty-five turns did not produce one. So the join is
**unexercised**, and if a build or a mode ever emits interleaved `text … text` in one message, the
delta stream would have to reproduce that same single `"\n"` between them for the hash to hold.
**Nobody has seen that happen, in either direction.** The rate is 100% over the shapes that occur;
it is not evidence about the shape that did not.

---

## 3 — `MessageDisplay` carries `prompt_id` — §13 row 4 closes

The spec called this *"an assumption the brief carried and the evidence does not"* (§15), because no
`MessageDisplay` payload had ever been captured. One has now been captured 94 times.

### The payload carries exactly ten fields

```
session_id  transcript_path  cwd  prompt_id  hook_event_name
turn_id  message_id  index  final  delta
```

**All ten were present on all 94 payloads** — no field was ever optional in practice. Catalogued the
way §2 catalogues `Stop`'s eleven, with `delta` redacted:

| field | type | note |
| --- | --- | --- |
| `session_id` | string | same value as `Stop.session_id` |
| `transcript_path` | string | the session's `.jsonl` |
| `cwd` | string | |
| `prompt_id` | string | **the same UUID `Stop` carries for that turn** |
| `hook_event_name` | string | `"MessageDisplay"` |
| `turn_id` | string | **not present on `Stop`** |
| `message_id` | string | the key `rewrite.sh:107` already reads |
| `index` | number | flush index, 0-based |
| `final` | boolean | true on the last flush of the message |
| `delta` | string | the newly completed lines |

Against `Stop`'s eleven fields (§2), `MessageDisplay` is missing `permission_mode`, `effort`,
`stop_hook_active`, `last_assistant_message`, `background_tasks` and `session_crons`, and adds
`turn_id`, `message_id`, `index`, `final` and `delta`. `agent_id` and `agent_type` were absent from
both, as the schema says to expect for the main thread.

### `prompt_id` matches, 35/35 — and it is still the weaker key

Every one of the 35 `Stop` payloads found its `MessageDisplay` stream by `prompt_id` alone, with no
orphans in either direction: 35 distinct `prompt_id`s on the display side, 35 on the `Stop` side, a
clean one-to-one.

**§3.2 says to prefer `prompt_id` if the probe finds it. This document recommends against making it
the key, on evidence the probe also produced.**

`prompt_id` identifies a **turn**. `rewrite.sh` publishes per **message**, overwriting `speak/` on
every rewritten message, and a turn can contain several — four of the driven turns did. In such a
turn every message shares one `prompt_id`, so a `prompt_id` key cannot tell *"the rewrite of this
turn's final message"* from *"the rewrite of the narration three messages ago"*. It would speak the
wrong one and believe it was right. The content hash makes exactly that distinction, and §3.2's
stated requirement — *"prove the buffered rewrite belongs to this turn's **final message**"* — is the
message-level claim, not the turn-level one.

**So: keep the hash as the key, and use `prompt_id` as a cheap pre-filter.** Both are now known to be
available and both are now known to agree; the hash is strictly stronger and costs a `sha256` of a
string the hook already holds. `turn_id` cannot be a key at all — `Stop` does not carry it.

**One collision worth naming.** Two of the 44 captured messages were byte-identical to an earlier one
(the same prompt re-driven, answered the same way), and both were long enough to publish. A stale
buffer therefore *can* produce a false hit — but only when the earlier message had identical text, in
which case the buffered rewrite is a rewrite of that same text and the utterance is correct anyway.
Benign, and worth a line in §3.2 rather than a mechanism.

---

## 4 — The finding that outranks the rate: `Stop` does not wait for `MessageDisplay`

> **Re-measured from scratch, by a second probe, on a second session.** This section was originally
> written from three slow-probe turns. Because everything downstream of it changes if it is wrong, it
> was re-measured independently with a freshly designed probe
> ([`handoff-timing-probe/`](handoff-timing-probe/), committed and runnable) over **32 captured
> turns**. The ordering claim **held, and tightened**. Two of the conclusions drawn from it did not,
> and are corrected below. The full per-turn table is
> [`handoff-timing-probe/runs.tsv`](handoff-timing-probe/runs.tsv). Everything in this section carrying
> a number is **[obs2]** unless marked otherwise.

The two hooks fire, in wall-clock terms, together. Across 32 turns the `Stop` hook process started a
**median of 6.7 ms** after the final-chunk `MessageDisplay` hook process started — **positive in
32 of 32**, range +1.9 ms to +322 ms, with 29 of 32 inside +1.9…+15.4 ms. `Stop` never once started
first. That alone proves nothing, though: a display hook that returns in 60 ms cannot distinguish
"the harness dispatched them concurrently" from "the harness waited for me".

**So the display hook was made slow on purpose, and — this is the part that decides it — a fast
control was run alongside.** The final branch was held open 4 s in one regime and 0 s in the other:

| regime | display-hook duration | dispatch gap (`Stop` start − display-hook start) | `Stop` start − display-hook **return** |
| --- | ---: | ---: | ---: |
| control (n=12) | 51.3 – 87.3 ms | +3.6 … +261.1 ms | −46.8 … −81.7 ms (one at +209.7) |
| held open (n=20) | 4,071 – 4,116 ms | +1.9 … +322.0 ms | **−3,774 … −4,114 ms** |

**The dispatch gap does not depend on the display hook's duration.** Make the hook 65× slower and the
gap stays in the same few-millisecond band. That is the proof, and it is stronger than the 4 s figure
on its own: `Stop` is dispatched concurrently with the final `MessageDisplay` invocation and is not
sequenced after it. **The harness does not wait** — and in the control regime it does not wait
either, starting `Stop` 47–82 ms before a 60 ms display hook returned.

Two further facts the original measurement did not have, both of which matter for §4's repairs:

- **`MessageDisplay` fires once per streamed chunk, not once per message** (`rewrite.sh`'s own header
  says so; the probe confirms `.index` / `.final` per fire). Only the **final** chunk's invocation is
  in flight when `Stop` runs. Every earlier chunk has long since completed.
- **`Stop` reads the buffer a median of 24.2 ms after the display hook is entered** (28 of 31 turns
  in 18–33 ms; [`latency.tsv`](handoff-timing-probe/latency.tsv)). That is the entire budget a
  display hook has to get text on disk if it wants to be read. The probe's own publish path — a
  payload write, one `zsh` fork and three `jq` forks — took a median of 51.8 ms and **lost by about
  28 ms**.

### What was measured about the buffer itself, not just the clock

The probe published the assembled text twice per turn: once **immediately** on entering the final
chunk, and once **after** the 4 s hold, which is where `rewrite.sh` really publishes (after the LLM
call). `Stop` then snapshotted both and compared them against its own `last_assistant_message`:

| where the display hook publishes | `Stop` read a **stale** buffer | read the current text |
| --- | ---: | ---: |
| after its slow work (what §3.1 specifies) | **29 of 30** | 1 |
| immediately, before any slow work | **27 of 30** | 3 |

"Stale" here is not an inference. The buffer held the **previous turn's message**, identified by
content: on the *Clocks* turn the slow-published buffer still read `# The History of the Compass`.

**All three fresh reads in the second row are the same three turns** — the +261 / +298 / +322 ms tail
of the dispatch-gap distribution. When `Stop` is dispatched late enough, an immediate publish wins.
That is ~10% of turns here, and it is a race, not a guarantee.

### One severity split the original measurement missed

How bad the stale read is depends on **how many chunks the message arrived in**, because only the
final chunk is still in flight:

- On a 13.3 kB, 14-chunk reply the final chunk carried **8.5%** of the text. A buffer appended
  per-chunk would be *slightly truncated*, not stale.
- **A single-chunk message puts 100% of itself in the final chunk.** And chunking follows the
  streaming cadence, not length: replies of **440, 663, 692, 743, 762 and 772 bytes — all well above
  the default `MIN_CHARS` of 200 — each arrived in exactly one chunk.** For these the buffer holds
  the *entire previous message*, and there is nothing partial to fall back on.

So the hazard is worst precisely in the band the feature is aimed at: a message long enough to be
worth speaking, short enough to stream in one flush.

### The anomaly this section used to carry is withdrawn

The original text gave the dispatch-gap range as "−5 ms to +58 ms", the −5 ms implying `Stop`
sometimes started first. **Across 32 turns the gap was positive every time**, minimum +1.9 ms, so
that lower bound is not reproducible and nothing here should rest on it. The likely origin is a
reference-point slip: in the fast-hook control regime `Stop` starts **47–82 ms before the display
hook returns** (one control turn measured −64.8 ms), which is easy to record as "`Stop` went first"
while in fact being the same concurrency finding. Either way the direction of the finding is
unchanged, and the corrected statement is the stronger one.

### Why this breaks §3.1's handoff as written

**As written when this was measured** — §3.1 then had `rewrite.sh` publish `speak/rewrite` and
`speak/source` at its publication point, which is after `$rewrite` has been obtained, that is
**after the LLM call**. §3.1 has since replaced both with a content-addressed `speak/rw.<H>`, and
the qualification below applies to this whole subsection, not only to the step numbers: the
mechanism named here is the one that was measured, not the locked design. **What the measurement
establishes survives the change untouched, because it is a fact about WHEN the publish happens
relative to `Stop`, not about which path it writes** — and the publish is still after the LLM call
under content addressing. `CLAUDISH_TIMEOUT` defaults to
45 s (`rewrite.sh:65`) **[repo]**, `hooks/hooks.json:9` declares a 60 s timeout for the display hook
**[repo]**, and the one end-to-end rewrite anybody has timed took
[**52.50 s**](provider-switch-traps.md) for ~1,300 words. Whatever the provider, the publish is
**seconds** after the final flush, and `Stop` is **milliseconds** after it.

§10.3 had `speak.sh` read the buffer at **step 8** and exit at **step 9** without waiting. **Both the
step numbers and the mechanism below are quoted as they stood when this was measured, and neither is
the locked protocol any more** — §10.3 renumbered when preemption moved above the content-based exits
(the hook no longer reads a buffer at all — step 10 classifies and tests for `rw.<H>`, step 12
enqueues, and the resident worker does the eventual read), and §3.1 replaced the mutable
`speak/source` this scenario
walks with a content-addressed `speak/rw.<H>`. Renumbering the sentence alone would make superseded
evidence read as a description of the current design. **What the measurement establishes is the
timing** — that `Stop` reads milliseconds after the display hook is entered and the publish lands
seconds later — and that survives both changes untouched, because it is a fact about dispatch order,
not about which path is read. So on a turn whose final message is long enough to be rewritten:

1. final chunk arrives; `rewrite.sh` starts its LLM call;
2. ~7 ms later `Stop` fires, and ~24 ms after the display hook was entered `speak.sh` reads
   `speak/source`, which still holds the **previous** published message's hash;
3. the hashes disagree — **correctly**, that buffer really is stale;
4. §3.5's last row applies: buffer miss, `prose_len ≥ MIN_CHARS` → **silent**;
5. seconds later the rewrite is published, into a buffer nothing will read until the next turn.

Step 2 is the step that was in doubt and is now measured directly rather than inferred: the buffer at
`Stop`'s read held the previous turn's text in **29 of 30** turns, identified by content.

**This is §15's own nightmare arriving by a different road**: *"the feature is quiet for a reason no
user will be able to diagnose."* The match rate is not the road. **On the great majority of turns
above `MIN_CHARS` the mechanism as specified would be silent** — and the 100% rate measured here is
the rate of a comparison that, in production, would mostly not get the chance to run.

**Not "every turn", and the difference matters.** Three of 32 turns had a dispatch-gap tail long
enough for an immediate publish to win, and one of those was late enough that `Stop` started after the
display hook had wholly returned. §2's benign collision adds another exception: when the source text
repeats verbatim, a stale buffer hashes equal and speaks correctly anyway. So the honest claim is
**"silent on the large majority of qualifying turns, unpredictably"** — which for a speech feature is
no better than always, and is worse to diagnose. It is not an exceptionless law, and stating it as one
invites a reader to disprove the blocker with a single counter-example.

**Three things this is not.** It is not a fault in the hash — the hash did exactly the right thing at
step 3. It is not *silence* in the sense of nothing being available: the buffer is not empty, it holds
the **wrong** message, so a `speak.sh` that skipped §3.2's comparison would confidently **speak the
previous turn's answer**. Silence is what the comparison buys. And it is still **not observed
end-to-end**: `speak.sh` does not exist, so nobody has watched it go quiet. What is observed is the
ordering, the buffer contents at `Stop`'s read (**[obs]**, both tables above) and the publication
point (**[repo]**, `rewrite.sh`). Joining them to the silence verdict remains **[inferred]**, and the
honest way to retire it is to build `speak.sh` and watch.

### The three repairs, re-scored against the measurement

| repair | verdict after re-measurement |
| --- | --- |
| a bounded wait for the matching text to appear — **AS-OF, and the selected design moves BOTH halves of this cell.** The proposal on the table when this was written was a wait inside `speak.sh` — the `Stop` hook itself — for a mutable `speak/source`. The design that was selected puts the wait in §10.5's resident worker rather than in the hook body, and what it waits for is the content-addressed `speak/rw.<H>`; `speak/source` no longer exists. **The verdict is unchanged**, because it turns on not needing to win a race — not on where the wait runs, and not on which path it waits for. | **the only one the measurement supports.** It is the only option that does not depend on winning a race. **The cost is real, and the proposal and the selected design price it DIFFERENTLY — reading them as one hands an implementer the wrong placement and the wrong cost together.** *As proposed here*, the wait sat in the hook, so its cost was **blocking**: it would have spent the non-blocking guarantee §6 spends its length defending. *As selected*, it does not — [`speech-integration-spec.md`](speech-integration-spec.md) §3.5.1 puts the wait in the resident worker **precisely so the hook drops its job and exits 0 without waiting**, and the measured hook wall cost stays **0.063–0.219 s, median 0.086 s**. What remains is latency and complexity rather than a held prompt: the utterance lands a rewrite-latency after the turn ends, and the wait still needs a deadline and a give-up-and-stay-quiet branch rather than an unbounded block. **The deadline is not this cell's number either.** The locked ceiling is `min( CLAUDISH_TIMEOUT + 2, MD_TIMEOUT ) + 3` — **50 s at the defaults** — and that spec reads the 52.50 s rewrite cited here ([`provider-switch-traps.md`](provider-switch-traps.md), measured standalone at `LLM_TIMEOUT=120` rather than through the hook) as **an example of the timeout branch the wait is supposed to give up on**, not as a publish the wait must sit through. |
| `rewrite.sh` publishes the **original** hash immediately at the final chunk, the rewrite later | **now known to be a race, not a fix — but a winnable one.** As instrumented it lost 27 of 30, because publishing cost ~52 ms against `Stop`'s ~24 ms read. The budget is now known: **get the bytes on disk within ~20 ms of hook entry.** That means writing the delta concatenation *before* any metadata parsing — the probe's three `jq` forks came first, which is why it lost. Viable only if measured at the real publish path, and it can never be better than a race, so it needs the wait above as a backstop. |
| move speech off `Stop` onto whatever fires after the display hook completes | **unevaluated, and the measurement neither helps nor hurts it.** No such event was identified in this probe. `MessageDisplay` firing per chunk means "after the display hook completes" is a per-chunk notion, so this needs an event that exists before it can be scored. |

A fourth option the chunk-level finding opens up, not previously on the list: **have the display hook
append each delta to a per-`message_id` buffer as it arrives** (`rewrite.sh:124` already does exactly
this) **and have `speak.sh` read that buffer rather than a published-on-completion one.** On
multi-chunk replies that buffer is ~91% complete at `Stop`'s read, so the failure degrades from *wrong
message* to *slightly truncated message*. It does **not** rescue the single-chunk case — 440–772-byte
replies arrived in one chunk, where the per-chunk buffer is exactly as empty as the published one —
so it is a mitigation for long replies, not a repair. **Which one is #11's call.** The measurement now
says more than "the current text cannot work": it says the wait is the only unconditional fix, and it
gives the ~20 ms budget any publish-early variant has to hit.

---

## 5 — Normalisation was tested and is not needed

§13 row 3 anticipated that a low rate might be rescued by normalising before hashing. **The raw rate
is 100%, so there is nothing to rescue, and no normalisation should be added.** For the record, the
three candidates and what they would have bought:

| candidate | effect on these 35 | verdict |
| --- | --- | --- |
| trim (as §3.2 already specifies) | no change — no message had edge whitespace | keep, defensive |
| collapse internal whitespace runs | no change | **do not add** — it would let genuinely different messages hash alike |
| hash a fixed-length prefix | no change | **do not add** — same objection, and it would make truncation invisible |

The last two are worth naming only to reject them: both widen the key, and a wider key on a
staleness check trades silence (safe) for speaking the wrong turn (the thing §3.2 exists to prevent).
**A 100% exact rate is the argument for keeping the key at its narrowest.**

---

## 6 — `Stop` fires again when a background task wakes the session — §13 row 7 closes

Two of the driven turns delegated to a subagent. Both produced **two** `Stop` fires, and the second
was not a re-fire:

- fire 1 ends the turn with `background_tasks: [{type: "subagent", status: "running"}]` — the shape
  §2 already records — and its own `prompt_id`;
- the subagent completes; the harness injects a `<task-notification>` **as a user message**, visible
  in the transcript; the main thread answers it;
- fire 2 is a **new turn**: new `prompt_id`, `background_tasks` empty, `stop_hook_active: false`, its
  own `MessageDisplay` stream, and it matched exactly like any other. **[obs]**

So the wake is not an edge case the key has to survive — it is an ordinary turn and the key handles
it with no special case. **[obs]** on two samples.

Two things follow for the spec. §13 row 7 (*"whether `Stop` fires again after a background task wakes
the session"*) is **answered: yes**, and the answer is benign for §3.2. And §8's suppression rule —
*"a non-empty `background_tasks` suppresses the announcement"* — now has an observed cost: it
suppresses fire 1 and lets fire 2 through, so a delegated turn is announced **once**, late, when the
subagent's result comes back. That is very likely the wanted behaviour, but it should be written down
as the observed consequence rather than left as a hoped-for one. `stop_hook_active` was `false` on all
35 fires, so nothing here touches the blocked-turn path settled in
[`stop-hook-block-mechanics.md`](stop-hook-block-mechanics.md).

---

## What was not observed

Named so nothing above reads as broader than it is.

- **A message with two `text` blocks.** The one shape that could break the join. Zero in 50 assistant
  messages. [Section 2.](#2--why-they-agree-and-the-one-edge-that-is-still-untested)
- **`last_assistant_message` absent.** The schema's empty-collapse path **[bin]** never fired: all 35
  payloads carried text. A tool-use-only final message stays theoretical, and §2's
  absent-by-default rule stays the right one.
- **Any mismatch at all**, of any shape. There is no measured mismatch taxonomy in this document
  because there were no mismatches to characterise. The shapes the brief asked about — leading and
  trailing whitespace, block joining, markdown fences, interleaved tool-use, thinking blocks,
  truncation — were each *present in the corpus* and each *survived*; none produced a divergence to
  describe.
- **`speak.sh` going silent.** Section 4's consequence is inferred from two measured facts, not
  watched. The hook does not exist yet.
- **Any model but `sonnet`, any effort but high, any build but 2.1.245.** Block structure is a
  harness-and-model property and this is one of each.
- **A blocked turn, an interrupt, or `StopFailure`.** Untouched here; the first is settled elsewhere.

---

## What §3.2 and §13 will need to say

**#11 owns [`speech-integration-spec.md`](speech-integration-spec.md) and this document does not edit
it.** For the integration pass:

1. **§3.2's OPEN(key) resolves to LOCKED, unchanged.** The content hash is the key. Record the rate as
   **35/35 exact, byte-identical, 2026-08-25, 2.1.245** and delete *"until it is taken, the match rate
   is unknown and this spec does not claim it is high."*
2. **Reverse §3.2's `prompt_id` preference.** The sentence *"if the probe shows `MessageDisplay`
   carries `prompt_id`, prefer it"* should become: it does carry one, it is the same one, and it is
   **still the weaker key** because it identifies a turn and `rewrite.sh` publishes per message. Use
   it as a pre-filter, not as the key. [Section 3.](#3--messagedisplay-carries-prompt_id--13-row-4-closes)
3. **§13 row 4 can be struck.** Answered: yes, `prompt_id` is present on every `MessageDisplay`
   payload. Add the ten-field catalogue beside §2's eleven.
4. **§13 row 7 can be struck.** Answered: yes, and as a new turn with a new `prompt_id`.
5. **§13 row 3 can be struck — and replaced.** The rate is measured and it passes. **A new
   ship-blocking row is owed**, and this document proposes its wording rather than filing it:
   *"`Stop` is dispatched concurrently with the final `MessageDisplay` chunk — a median of 6.7 ms
   after it starts, positive in 32 of 32 turns, and independent of how long that hook runs — so it
   does not wait for the display hook. The buffer §3.1 specifies is therefore published after §3.2
   has already read it: measured stale in 29 of 30 turns, holding the previous turn's text. What
   closes it: adopt the bounded wait in `handoff-match-rate.md` §4, the only repair that does not
   depend on winning a ~20 ms race, and measure it end-to-end. Blocks shipping: yes — as specified
   the feature is silent on the large majority of turns above `MIN_CHARS`, unpredictably rather than
   always, which is harder to diagnose and no better to use."*
6. **§15's `prompt_id` bullet and its match-rate bullet both go**, replaced by the section-4 hazard,
   which is the same worry with a different and now-measured cause.
7. **§3.2's `trim` keeps its place but loses its emphasis** — 44 message streams, zero edge whitespace.
8. **§8 gains an observed consequence**, not a new rule: a delegated turn announces once, on the
   post-wake fire. [Section 6.](#6--stop-fires-again-when-a-background-task-wakes-the-session--13-row-7-closes)

---

## The raw tally

One row per `Stop` payload. **`text msgs in turn` is how many *text-bearing* assistant messages shared
that `prompt_id`** — not how many assistant messages the turn held. The distinction is load-bearing
and the column was mislabelled in the first version of this document: the column sums to **44** across
the 35 rows, with **4** rows above 1, which are §2's 44 text-bearing messages and its 4 turns holding
more than one of them. The turn-level figures are different numbers — **50** assistant messages across
**10** multi-message turns — and a column summing to 44 was never counting those. `MessageDisplay`
does not fire for a `tool_use`-only message (§2), so the 6-message gap is exactly the messages this
column cannot see and `rewrite.sh` would never process.

`flushes` is how many `MessageDisplay` payloads built the final message of that turn; it sums to 84,
which is not the 94 payloads captured overall because the earlier messages of a multi-message turn
also flush and are not counted here. Rows 33–35 are the slow-probe runs of the original
[section 4](#4--the-finding-that-outranks-the-rate-stop-does-not-wait-for-messagedisplay) measurement;
section 4's re-measurement is a separate 32-turn capture and is tabulated in
[`handoff-timing-probe/runs.tsv`](handoff-timing-probe/runs.tsv), not here.

| # | `prompt_id` | text msgs in turn | flushes | bytes MD | bytes `Stop` | fences | paras | `sha256(trim(MD))` | `sha256(trim(Stop))` | verdict |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |
| 1 | `ecec80bc` | 1 | 1 | 2 | 2 | 0 | 1 | `2689367b205c` | `2689367b205c` | **exact** |
| 2 | `e6b35ccb` | 1 | 3 | 1919 | 1919 | 0 | 3 | `81e7530c0332` | `81e7530c0332` | **exact** |
| 3 | `0f17385b` | 1 | 5 | 668 | 668 | 6 | 7 | `78b3920b1e49` | `78b3920b1e49` | **exact** |
| 4 | `bc57651d` | 1 | 1 | 257 | 257 | 0 | 1 | `3380c8b10060` | `3380c8b10060` | **exact** |
| 5 | `401d4b4a` | 1 | 1 | 542 | 542 | 0 | 1 | `244614526b8a` | `244614526b8a` | **exact** |
| 6 | `8deeb60e` | 1 | 1 | 88 | 88 | 0 | 1 | `6db0cf6380be` | `6db0cf6380be` | **exact** |
| 7 | `ea49d12d` | 1 | 1 | 82 | 82 | 0 | 1 | `72a6e33e2324` | `72a6e33e2324` | **exact** |
| 8 | `5eede743` | 1 | 4 | 647 | 647 | 0 | 4 | `1235cb64808b` | `1235cb64808b` | **exact** |
| 9 | `1325fdd8` | 1 | 3 | 16 | 16 | 2 | 1 | `c396a6b64d49` | `c396a6b64d49` | **exact** |
| 10 | `74242320` | 1 | 4 | 481 | 481 | 0 | 1 | `1e0d4df9e035` | `1e0d4df9e035` | **exact** |
| 11 | `a4dbfccf` | 1 | 4 | 522 | 522 | 0 | 1 | `33f8336527f8` | `33f8336527f8` | **exact** |
| 12 | `071e2a5f` | 1 | 1 | 1 | 1 | 0 | 1 | `4b227777d4dd` | `4b227777d4dd` | **exact** |
| 13 | `c267ba7f` | 1 | 1 | 1503 | 1503 | 0 | 1 | `5a97b0b3ccd8` | `5a97b0b3ccd8` | **exact** |
| 14 | `81e402f6` | 1 | 3 | 153 | 153 | 2 | 3 | `533e0de7b1fb` | `533e0de7b1fb` | **exact** |
| 15 | `61330a00` | 1 | 4 | 2737 | 2737 | 4 | 6 | `0309ddfeba27` | `0309ddfeba27` | **exact** |
| 16 | `10818182` | 1 | 1 | 986 | 986 | 0 | 1 | `43fea9582f97` | `43fea9582f97` | **exact** |
| 17 | `8c98494c` | 1 | 1 | 5 | 5 | 0 | 1 | `c45d306afebe` | `c45d306afebe` | **exact** |
| 18 | `1d45406f` | 1 | 1 | 7 | 7 | 0 | 1 | `98e58e120cc3` | `98e58e120cc3` | **exact** |
| 19 | `8be2775a` | 1 | 1 | 571 | 571 | 0 | 1 | `b78a968275b5` | `b78a968275b5` | **exact** |
| 20 | `791c9944` | 1 | 5 | 532 | 532 | 2 | 6 | `d2f9b156e7ad` | `d2f9b156e7ad` | **exact** |
| 21 | `cde88073` | 1 | 1 | 112 | 112 | 0 | 1 | `4746e1fef2b9` | `4746e1fef2b9` | **exact** |
| 22 | `f08fb36a` | 1 | 2 | 799 | 799 | 0 | 3 | `a898a23722d5` | `a898a23722d5` | **exact** |
| 23 | `58e8ea71` | 1 | 1 | 255 | 255 | 0 | 1 | `b797fd20cb53` | `b797fd20cb53` | **exact** |
| 24 | `72d9280c` | 1 | 3 | 101 | 101 | 0 | 1 | `91e8fc17508e` | `91e8fc17508e` | **exact** |
| 25 | `1d20b899` | 4 | 1 | 316 | 316 | 0 | 1 | `71cad13fba91` | `71cad13fba91` | **exact** |
| 26 | `0b034e3a` | 4 | 1 | 413 | 413 | 0 | 1 | `9adde04ce20f` | `9adde04ce20f` | **exact** |
| 27 | `22095f80` | 1 | 9 | 3770 | 3770 | 6 | 8 | `f5388789e5a5` | `f5388789e5a5` | **exact** |
| 28 | `1f2f046b` | 1 | 6 | 2777 | 2777 | 2 | 5 | `a9e469d4ba37` | `a9e469d4ba37` | **exact** |
| 29 | `8d2faeec` | 1 | 1 | 1 | 1 | 0 | 1 | `3973e022e932` | `3973e022e932` | **exact** |
| 30 | `fdb0831d` | 1 | 2 | 14 | 14 | 2 | 1 | `ca085cd63717` | `ca085cd63717` | **exact** |
| 31 | `ac449ae8` | 2 | 1 | 542 | 542 | 0 | 1 | `b9703030d39f` | `b9703030d39f` | **exact** |
| 32 | `8eb56e8a` | 3 | 1 | 266 | 266 | 0 | 1 | `35d9b8edd04a` | `35d9b8edd04a` | **exact** |
| 33 | `ccfc83a2` | 1 | 3 | 1919 | 1919 | 0 | 3 | `81e7530c0332` | `81e7530c0332` | **exact** |
| 34 | `0d054b66` | 1 | 5 | 668 | 668 | 6 | 7 | `78b3920b1e49` | `78b3920b1e49` | **exact** |
| 35 | `88805401` | 1 | 1 | 268 | 268 | 0 | 1 | `11678ce4ad04` | `11678ce4ad04` | **exact** |

**35 of 35 exact. Rate 100%.** Every one is byte-identical before the trim, not merely trim-equal.

A separate 3-turn pilot on an earlier probe build gave **3/3 exact** and is excluded from the 35.

**Read this table as a record, not as a derivation.** Its inputs were destroyed at teardown, so no
reader can rebuild these 35 rows from anything committed here — see
[the probe section](#the-probe-as-it-was-run). What *is* rebuildable is the same comparison on new
turns, with the committed kit: [`handoff-timing-probe/match.sh`](handoff-timing-probe/match.sh)
re-derived **15 of 15 exact** on a later session, which corroborates the 100% without inheriting its
sample size.

---

## The probe as it was run

**Spent and torn down.** Recorded so the method is repeatable — which is not the same as the numbers
being re-derivable, and the difference is worth stating plainly.

> **What is and is not reproducible here.** The 35 rows above **cannot be re-derived from anything in
> this repository.** The raw captures were deleted at teardown, no machine-readable artifact was
> committed alongside them, and the listing below is an abridged sketch with the parsing elided — it
> will not run as printed. Those 35 rows are a **record of a measurement**, resting on the honesty of
> the person who took them, and they should be read at that strength and no higher.
>
> **The re-measurement in [section 4](#4--the-finding-that-outranks-the-rate-stop-does-not-wait-for-messagedisplay)
> is different, and deliberately so.** Its probe is committed complete and runnable at
> [`handoff-timing-probe/`](handoff-timing-probe/) — both hooks, the throwaway-settings generator, the
> per-turn driver, and the three analysis scripts — together with its 32-turn output as
> [`runs.tsv`](handoff-timing-probe/runs.tsv) and [`latency.tsv`](handoff-timing-probe/latency.tsv).
> Anyone can re-run it and get their own table.
>
> That kit also re-derives **this** section's question independently: `match.sh` compares
> `Stop.last_assistant_message` against the delta concatenation, byte for byte, exactly as the 35 rows
> did. Re-running it produced **15 of 15 exact**, raw and trailing-newline-stripped alike, with
> `concat_bytes == lam_bytes` on every turn. That is a smaller n than 35 and it does not inherit the
> original's authority — but it is a reproducible 15/15 standing behind an unreproducible 35/35, from
> a different probe on a different session, and it agrees.

The sketch below is kept as a description of the original probe's shape. **For a runnable version, use
the committed kit; for the parsing this listing elides, see
[`handoff-timing-probe/md.sh`](handoff-timing-probe/md.sh) and
[`stop.sh`](handoff-timing-probe/stop.sh), which define `d`, `idx` and `fin` in full.**

**`~/.claude/settings.json` was never modified.** Its sha256 was
`b73f471a3f100d111d7a69387be3d0adaa8e37c6552b52362f7209fdbb3f945f` before the work and
`b73f471a3f100d111d7a69387be3d0adaa8e37c6552b52362f7209fdbb3f945f` after it. Its `hooks` key holds
only `SessionStart`, as it did throughout. The probe hooks lived in a throwaway file passed to one
session with `--settings`, which is why no other session on this machine ever saw them.

```bash
# Throwaway MessageDisplay probe. Emits nothing on stdout, so the display is untouched.
T0="$(date +%s%N)"; D=<scratch>/cap
p="$(cat)" || exit 0
[ -f "$D/md-payload-sample.json" ] || printf '%s' "$p" > "$D/md-payload-sample.json"
# ... session_id / message_id / index / final / prompt_id / turn_id via one jq -r @tsv ...
printf '%s' "$p" | jq -j '.delta // ""' > "$d/$(printf '%08d' "$idx").part"
if [ "$fin" = "true" ]; then
  cat "$d"/*.part > "$d/RAW"                 # byte-exact concatenation
  full="$(cat "$d"/*.part)"                  # rewrite.sh:135's assembly, trailing newlines stripped
  printf '%s' "$full" > "$d/FULL"
  [ -f "$D/SLOW" ] && perl -e 'select(undef,undef,undef,4)'   # section 4's ordering experiment
fi
exit 0

# Throwaway Stop probe. No jq runs before the payload is on disk: jq exits 2 on a
# malformed filter and 2 is the one status that blocks a turn.
T0="$(date +%s%N)"; D=<scratch>/cap
mkdir -p "$D/stop"; cat > "$D/stop/$T0.json"; exit 0
```

> **The comment in that second probe is quoted verbatim and it is wrong on one detail.** *"`jq` exits 2
> on a malformed filter"* is false on this machine: a malformed filter exits **3**. The exit-2 routes are
> `jq` handed a **bad option or an unreadable file**, and a **bash syntax error** in the hook — measured
> table in [`speech-integration-spec.md`](speech-integration-spec.md) §5. **The probe was safe on both
> routes, but only one of them is the write ordering's doing.** Writing the payload before running any
> `jq` does preserve the capture — but it does not stop a later `jq` status 2 from escaping, and what
> actually made the probe safe on that route is that it reaches its explicit `exit 0`. **Nor does the
> write ordering cover a bash syntax error**, and an earlier version of
> this note claimed it did: a syntax error in the same compound command or enclosing construct is a
> **parse**-time failure, so the parser executes none of it and there is nothing written before the
> hook exits 2. What actually covers that route here is that **these probes are syntax-valid** —
> `bash -n` returns 0 on the quoted body above and on the committed
> [`stop.sh`](handoff-timing-probe/stop.sh) and [`md.sh`](handoff-timing-probe/md.sh)
> **[measured-here]** — which is the check
> [`turn-finality-and-the-stop-hook.md`](turn-finality-and-the-stop-hook.md) requires before a hook
> ships, *"because no runtime guard can run in a file the parser refuses to get past."* Nothing measured
> here is affected either way. The comment is left as written rather than retouched, because it is a
> record of what the probe said; this note is the correction.

```json
{ "model": "sonnet",
  "env": { "CLAUDISH_ENABLED": "0" },
  "hooks": {
    "MessageDisplay": [ { "hooks": [ { "type": "command", "command": "<scratch>/md-probe.sh", "timeout": 8 } ] } ],
    "Stop":           [ { "hooks": [ { "type": "command", "command": "<scratch>/stop-probe.sh", "timeout": 5 } ] } ] } }
```

### The aggregation, the comparison, and how hook-return time is recorded

The original listing had none of these, which is most of why its numbers could not be checked. The
committed kit does; these are the commands, in the form the re-measurement actually used.

**Recording hook *return* time at all** is the piece with a trap in it. bash 3.2 has no in-process
hi-res clock, and shelling out to `date` charges a fork to the very interval being measured. The kit
takes every timestamp as a **file mtime**, stamped by the kernel at nanosecond resolution, using a
bare builtin redirection that forks nothing:

```bash
: > "$P/ev/MD.$$.t0"      # first statement in the hook: entry, fork-free
# ... hook body ...
: > "$P/ev/MD.$$.t2"      # last statement: return
```

Three consecutive such redirections land ~90 µs apart, so the resolution is far finer than the
millisecond effects being measured. Read them back, all on one clock, and sort:

```bash
stat -f '%Fm %N' "$P"/ev/* | sort -n          # the whole turn, one ordered timeline
```

**Aggregation and comparison** are then `collect.sh` (ordering, one row per turn), `latency.sh` (the
in-hook budget) and `match.sh` (the §3.2 string comparison):

```bash
PROBE_DIR=/tmp/handoff-probe ./collect.sh     # -> runs.tsv
PROBE_DIR=/tmp/handoff-probe ./latency.sh     # -> latency.tsv
PROBE_DIR=/tmp/handoff-probe ./match.sh tag   # -> exact | MISMATCH, raw and assembled
```

Because the clock is mtimes, **`cp` without `-p` silently destroys the measurement** — it rewrites
every mtime to the copy time and flattens all intervals to zero. This bit the re-measurement once and
is why `collect.sh` parses each run's saved `analysis.txt` rather than trusting copied marker files.

Four operational notes, kept because they would apply again:

- **`CLAUDISH_ENABLED=0` in the driven session was deliberate.** The plugin is enabled globally, so
  without it `rewrite.sh` would have run alongside the probe on the same event — a second hook on
  `MessageDisplay`, a local LLM call per message, and an open question about whether one hook's
  `displayContent` reaches the next. The measurement is of the harness's two string constructions;
  the plugin had no business in it.
- **`"timeout": 8` on the display probe** is under the harness default of 10 s for `MessageDisplay`
  **[bin]** and comfortably over the ~30 ms the probe actually took. Section 4's 4 s delay was chosen
  to sit inside it.
- **Both hooks were verified to fire before any null result was read.** The first driven turn produced
  one `MessageDisplay` capture and one `Stop` capture, checked by hand, before the battery ran.
- **Turn boundaries were taken from the arrival of a new `Stop` capture**, not from the driver's idea
  of when a turn ended. An earlier pass that trusted the driver interleaved two prompts into one turn
  and was discarded; the pilot's 3 clean turns are all that survived it.

### What the re-measurement learned the hard way

Five traps found while re-measuring section 4, all of which would silently produce a plausible wrong
number rather than an error. They are documented in the kit's README and encoded in its scripts.

- **`zsh -f` does not autoload `zsh/datetime`, so a bare `$EPOCHREALTIME` expands to the empty
  string.** Verified on zsh 5.9: `zsh -fc 'print -r -- "[$EPOCHREALTIME]"'` prints `[]`, and so does
  the same line under the interactive config. It needs `zmodload zsh/datetime` first. A probe timing
  itself this way measures nothing and says so only if someone checks for the empty value. The kit
  cross-checks its mtime clock against zsh's and reports a missing reading explicitly. (On this
  machine `date +%s%N` *does* yield real nanoseconds — BSD `date` has gained `%N` — so the original
  probe's clock was sound; that was the first suspicion and it was wrong.)
- **`cp` without `-p` destroys an mtime-based measurement**, as above.
- **Hash inside the bracket you are timing.** The `Stop` probe first snapshotted the buffers between
  its two read markers but hashed the *live* files afterwards. The hashes then described a later
  instant than the one measured, and three turns reported a fresh buffer beside a stale bracketed
  read. Copying inside the bracket and hashing the copies removed the contradiction.
- **A hook that never ran is indistinguishable from one that measured zero.** Every hook here drops a
  marker on entry, so absence is loud: the collector prints `INCOMPLETE`, not a row of zeroes. **Three
  of 35 driven turns did fail to fire** — the driver typed the prompt but the submission did not take,
  so no turn happened — and were dropped rather than scored. Without the entry markers those three
  would have looked like three turns in which `Stop` and `MessageDisplay` both did nothing.
- **The plugin's own hook is user-scope and fires everywhere.** `claudish-to-english` is installed at
  user scope, so its `MessageDisplay` → `rewrite.sh` hook runs in *any* session, including a probe
  session in a throwaway directory with its own `--settings`. Left enabled it would have added an LLM
  call per message to every interval measured. `CLAUDISH_ENABLED=0`, as the original probe also did.

Teardown: the driven session was exited, the pane closed, the scratch directory removed with the raw
captures in it, and the git worktree this document was written in removed. The prompts were 30
synthetic instructions written for shape coverage (*"three separate fenced code blocks"*,
*"announce in one short sentence what you are about to do before each tool call"*, *"reply with only a
single hyphen"*) against four throwaway files in a temporary directory. **No repository content and
no user data was read by the driven session**, which is why the tally can be published at all.

---

## DECISION (2026-08-25)

1. **§13 row 3 is closed. The rate is 35/35 — 100%, byte-identical.** §3.2's content hash works
   exactly as specified across fences, tool calls, thinking blocks, subagents, multi-flush messages
   and one-byte acknowledgements.
2. **No normalisation.** The raw rate leaves nothing to rescue, and every candidate widens a key whose
   whole job is to be narrow. §3.2's `trim` stays, unexercised and defensive.
3. **§13 row 4 is closed: `MessageDisplay` carries `prompt_id`**, on all 94 payloads, matching
   `Stop`'s 35/35. The payload's ten fields are catalogued in section 3.
4. **`prompt_id` does not become the key.** It identifies a turn; `rewrite.sh` publishes per message;
   four driven turns had several. The hash is strictly stronger. Use `prompt_id` as a pre-filter.
   **This reverses §3.2's stated preference, on evidence §3.2 asked for.**
5. **§13 row 7 is closed: a background-task wake produces a second `Stop`**, as a new turn with a new
   `prompt_id`, and the key handles it with no special case.
6. **A new ship blocker is owed, and section 4 is it.** `Stop` does not wait for the `MessageDisplay`
   hook — re-measured over 32 turns, and proved by a control rather than by the 4 s figure alone: the
   dispatch gap does not change when the display hook is made 65× slower. So §3.1's buffer is
   published after §3.2 would have read it, measured stale in 29 of 30 turns. §3.5's last row then
   silences **the large majority of qualifying turns** — not all of them: a ~10% dispatch-gap tail and
   §2's repeated-text collision both let a turn through, which is why the blocker is stated as a rate
   and not as a law. **The strings agree. The timing does not.** Filing it is #11's; section 4 now
   also says which of the repairs the measurement actually supports.
