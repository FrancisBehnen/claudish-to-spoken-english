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
spec does not model: **`Stop` does not wait for the `MessageDisplay` hook.** Held open deliberately
for 4 s, the display hook was still running when `Stop` fired — 3 to 12 ms after the display hook
*started*, roughly 4.1 s before it *returned*. `rewrite.sh` publishes its buffer only after an LLM
call that takes seconds, so at the moment `speak.sh` runs, `speak/source` holds the **previous**
message. The hashes then correctly disagree, §3.5's last row fires, and the feature is silent — for
a reason that has nothing to do with the match rate and everything to do with ordering.
[Section 4](#4--the-finding-that-outranks-the-rate-stop-does-not-wait-for-messagedisplay) is that
measurement. **It is a new ship blocker, and this document proposes it rather than filing it.**

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
| **[bin]** | `strings -n 6` over `~/.local/share/claude/versions/2.1.245` | what is compiled into the build actually running |
| **[repo]** | `rewrite.sh` and `hooks/hooks.json` in this checkout | what the plugin does today |
| **[docs]** | <https://code.claude.com/docs/en/hooks.md> | states intent; can lag or lead the installed build |

Every number below comes from the raw capture, which is [tallied in full](#the-raw-tally). **The
message bodies are not in this repository and are not in this document** — the repo is public and the
captures are real assistant output. Hashes, byte counts, flush counts and diff shapes are what
crossed the line; the bodies stayed in the scratchpad and went with the teardown.

---

## The four answers, in one table

| # | question | answer | tag |
| --- | --- | --- | --- |
| 1 | Does `Stop.last_assistant_message` equal `rewrite.sh`'s delta concatenation? | **Yes. 35/35, byte-identical.** Not one mismatch of any shape. | **[obs]** |
| 2 | Why do they agree — and where could they stop agreeing? | The harness joins **text blocks only**, on `"\n"`. **No message in 50 had two text blocks**, so the join has never had anything to join. That is the untested edge, not a passed test. | **[bin]** + **[obs]** |
| 3 | Does `MessageDisplay` carry `prompt_id`? | **Yes**, on all 94 payloads, and it is **the same value** `Stop` carries, 35/35. §13 row 4 closes. | **[obs]** |
| 4 | Is the buffer *there* when `Stop` reads it? | **No.** `Stop` fires ~9 ms after the final display flush begins and does not wait for the hook. The publish lands seconds later. | **[obs]** |

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

The two hooks fire, in wall-clock terms, together. Across the 35 turns, the `Stop` hook process
started a **median of 9 ms** after the final-flush `MessageDisplay` hook process started
(range −5 ms to +58 ms). That alone proves nothing: a hook that returns in 30 ms, as the probe did,
cannot distinguish "the harness dispatched them concurrently" from "the harness waited for me".

**So the probe was made slow on purpose.** A 4-second delay was added to the display probe's final
branch — well inside its declared 8 s timeout — and three more turns were driven:

| run | `Stop` start − display-hook **start** | `Stop` start − display-hook **return** |
| --- | ---: | ---: |
| 33 | +9 ms | **−4,105 ms** |
| 34 | +3 ms | **−4,146 ms** |
| 35 | +12 ms | **−4,124 ms** |

**`Stop` fired about 4.1 seconds before the `MessageDisplay` hook returned.** The harness does not
wait. (All three still matched exactly — the delay changed the timing, not the strings.)

### Why this breaks §3.1's handoff as written

§3.1 has `rewrite.sh` publish `speak/rewrite` and `speak/source` at its publication point, which is
after `$rewrite` has been obtained — that is, **after the LLM call**. `CLAUDISH_TIMEOUT` defaults to
45 s (`rewrite.sh:65`) **[repo]**, `hooks/hooks.json:9` declares a 60 s timeout for the display hook
**[repo]**, and the one end-to-end rewrite anybody has timed took
[**52.50 s**](provider-switch-traps.md) for ~1,300 words. Whatever the provider, the publish is
**seconds** after the final flush, and `Stop` is **milliseconds** after it.

§10.3 has `speak.sh` read the buffer at step 8 and exit at step 9 without waiting. So on a turn whose
final message is long enough to be rewritten:

1. final flush arrives; `rewrite.sh` starts its LLM call;
2. ~9 ms later `Stop` fires; `speak.sh` reads `speak/source`, which still holds the **previous**
   published message's hash;
3. the hashes disagree — **correctly**, that buffer really is stale;
4. §3.5's last row applies: buffer miss, `prose_len ≥ MIN_CHARS` → **silent**;
5. seconds later the rewrite is published, into a buffer nothing will read until the next turn.

**This is §15's own nightmare arriving by a different road**: *"the feature is quiet for a reason no
user will be able to diagnose."* The match rate is not the road. **The mechanism as specified speaks
on approximately no long turn at all**, and the 100% rate measured here is the rate of a comparison
that, in production, would not get the chance to run.

**Two things this is not.** It is not a fault in the hash — the hash did exactly the right thing at
step 3. And it is **not observed end-to-end**: `speak.sh` does not exist, so nobody has watched it go
silent. What is observed is the ordering (**[obs]**, the table above) and the publication point
(**[repo]**, `rewrite.sh`). The conclusion joins them and is therefore **[inferred]** — a firm
inference from two measured facts, but an inference, and the honest way to retire it is to build
`speak.sh` and watch.

**What could fix it, none of it decided here.** A short bounded wait in `speak.sh` for a matching
`speak/source` (cheap, but it puts a wait on a hook §6 spends its length keeping non-blocking); or
`rewrite.sh` publishing the *original* hash immediately at the final flush and the rewrite text later,
so `speak.sh` can tell "mine, not ready yet" from "not mine" and choose; or speech moving off `Stop`
onto whatever fires after the display hook completes. **Which one is #11's call.** The measurement
says only that the current text cannot work.

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
   *"`Stop` fires ~9 ms after the final `MessageDisplay` flush and does not wait for the display hook,
   so the buffer §3.1 specifies is published seconds too late for §3.2 to ever hit. What closes it:
   pick one of the three repairs in `handoff-match-rate.md` §4 and measure it end-to-end. Blocks
   shipping: yes — as specified, the feature is silent on every turn above `MIN_CHARS`."*
6. **§15's `prompt_id` bullet and its match-rate bullet both go**, replaced by the section-4 hazard,
   which is the same worry with a different and now-measured cause.
7. **§3.2's `trim` keeps its place but loses its emphasis** — 44 message streams, zero edge whitespace.
8. **§8 gains an observed consequence**, not a new rule: a delegated turn announces once, on the
   post-wake fire. [Section 6.](#6--stop-fires-again-when-a-background-task-wakes-the-session--13-row-7-closes)

---

## The raw tally

One row per `Stop` payload. `msgs in turn` is how many assistant messages shared that `prompt_id`;
`flushes` is how many `MessageDisplay` payloads built the final one. Rows 33–35 are the slow-probe
runs of [section 4](#4--the-finding-that-outranks-the-rate-stop-does-not-wait-for-messagedisplay).

| # | `prompt_id` | msgs in turn | flushes | bytes MD | bytes `Stop` | fences | paras | `sha256(trim(MD))` | `sha256(trim(Stop))` | verdict |
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

---

## The probe as it was run

**Spent and torn down.** Recorded so the numbers are reproducible, not as work outstanding.

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

```json
{ "model": "sonnet",
  "env": { "CLAUDISH_ENABLED": "0" },
  "hooks": {
    "MessageDisplay": [ { "hooks": [ { "type": "command", "command": "<scratch>/md-probe.sh", "timeout": 8 } ] } ],
    "Stop":           [ { "hooks": [ { "type": "command", "command": "<scratch>/stop-probe.sh", "timeout": 5 } ] } ] } }
```

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
   hook — measured at 4.1 s early against a deliberately slowed hook — so §3.1's buffer is published
   seconds after §3.2 would have read it, and §3.5's last row would silence every long turn.
   **The strings agree. The timing does not.** Filing it, and choosing among the three repairs
   sketched in section 4, is #11's.
