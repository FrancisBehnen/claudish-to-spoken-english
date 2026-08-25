# The `Stop` block loop, observed

Companion to [`turn-finality-and-the-stop-hook.md`](turn-finality-and-the-stop-hook.md), which closed
[#10](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/10) and named the blocked-turn
re-fire as the one part of `Stop` it had read but never seen. Part of the
[Kokoro speech map (#1)](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/1).
Established 2026-08-25 against Claude Code **2.1.245**.

**That gap is now closed for the mechanics this probe drove.** Four probe runs drove a second `claude`
session into the block loop on purpose and captured every fire. Everything the two prior documents said
about this area was read out of the binary; **the behaviour exercised here — the block itself, the
re-fire count, `stop_hook_active`, the post-cap override, the JSON route and what
`last_assistant_message` carries — now has a wire observation behind it, and one number in the spec is
off by one.** What the probe did not drive stays **[bin]**- or **[docs]**-only and is labelled that way
where it appears — the `0`-disables-the-cap branch, `async: true`, `SubagentStop` and the rest of the
[list below](#what-was-still-not-observed).

**No LLM was called for the plugin. No plugin hook was touched** — `rewrite.sh`, `rewrite-md.sh`,
`providers.sh` and `hooks/` are unmodified. The probe hook never entered
`~/.claude/settings.json`; it was scoped to one throwaway session and is gone. [Teardown is
recorded below.](#the-probe-as-it-was-run)

---

## How each fact below was established

| tag | source | what it can and cannot prove |
| --- | --- | --- |
| **[obs]** | 28 live `Stop` fires across four runs in one driven session on 2.1.245, 2026-08-25 | proves this build did this, in these turns. One session, one build, default settings — it cannot prove behaviour under a raised cap, multiple blocking hooks, or `SubagentStop`. |
| **[bin]** | `strings -n 6` over `~/.local/share/claude/versions/2.1.245` | what is compiled into the build actually running |
| **[docs]** | <https://code.claude.com/docs/en/hooks.md>, fetched 2026-08-25 | states intent; can lag or lead the installed build |

Everything below tagged **[obs]** comes from the raw fire log and the driven session's transcript,
both quoted in full in [the evidence](#the-raw-fire-log). Nothing here is inferred from a `strings`
hit alone.

---

## The seven answers, in one table

| # | question | answer | tag |
| --- | --- | --- | --- |
| 1 | Does exit 2 block, and is the stderr visible to the model? | **Yes and yes.** The stderr arrives as a synthetic user message, and the model *acted on it*. | **[obs]** |
| 2 | How many re-fires before the cap overrides? | **The hook is invoked 9 times** — one initial fire plus **8** re-fires. The 9th block is the one overridden. | **[obs]** |
| 3 | Does `stop_hook_active` flip to `true`, and when? | **Yes, on fire 2**, and it stays `true` through fire 9. | **[obs]** |
| 4 | What does the post-cap override look like? | **To the model: nothing.** To the user: one `level: "warning"` line, verbatim from the binary, with the count interpolated. | **[obs]** |
| 5 | Does `last_assistant_message` change between fires? | **Yes — it carries the newer text.** The prior reasoning is confirmed, not refuted. | **[obs]** |
| 6 | Exit 2 vs. `{"decision":"block"}`? | **Same loop, same nine invocations under the same cap of 8, same two surfaces for the text.** One cosmetic difference. | **[obs]** |
| 7 | Does exit 3 block? | **No.** One fire, no re-fire, no message to the model. | **[obs]** |

**All seven were answered.** None was left open for lack of time.

---

## 1 — Exit 2 blocks, and the stderr reaches the model as a user message

The block itself is not in doubt: **run A's hook exited 2 nine times and the turn did not end until the
runtime forced it.** **[obs]**

The interesting half is the routing. The stderr does not merely appear in the UI. It is appended to the
conversation as a **synthetic user message with `isMeta: true`**, in this exact shape — quoted from the
driven session's transcript **[obs]**:

```json
{"type":"user","isMeta":true,
 "message":{"role":"user","content":
   "Stop hook feedback:\n[/Users/francis.behnen/.local/share/claudish-blockprobe/probe.sh]: claudish block probe: deliberate exit 2, fire 4\n"}}
```

So the format is `Stop hook feedback:\n[<hook command>]: <stderr>`. The hook's **full command path** is
interpolated into text the model reads.

**The model does not merely receive it — it obeys it.** Run A2 varied the stderr on every fire, telling
the model to reply with a different NATO word each time. It ignored the first
demand and then complied, word for word, for six consecutive fires, before objecting to the game:

| the stderr on fire… | said | …and the message the next fire's payload carried |
| ---: | --- | --- |
| 1 | `…reply with exactly one word and nothing else: alpha` | `banana` — ignored, the model just re-answered |
| 2 | `…bravo` | `bravo` |
| 3 | `…charlie` | `charlie` |
| 4 | `…delta` | `delta` |
| 5 | `…echo` | `echo` |
| 6 | `…foxtrot` | `foxtrot` |
| 7 | `…golf` | `golf`, then an objection: *"That hook is rejecting every reply and handing back a new NATO word each time — it's an unconditional-rejection probe, not real feedback, so I'm stopping the ladder here rather than looping indefinitely."* |
| 8 | `…hotel` | *"I'm not continuing the chain — the probe rejects every response regardless of content, so each new word is just another rung."* |

**This is the strongest available proof that the channel is real**: not "the text was present in a log",
but "the model changed its output in response to it". **[obs]**

**The consequence for a speech hook is a security-shaped one and it is new here.** A `Stop` hook's
stderr on exit 2 is **prompt input**. Anything a speech hook writes to stderr while exiting 2 — an error
message, a stack trace, the contents of a variable — is read by the model as an instruction. The
plugin's existing *exit 0 on every path* rule already makes this unreachable, but the rule now has a
second reason behind it, and it is sharper than "noisy transcript".

---

## 2 — The cap tolerates **8 blocks**, so the hook fires **nine** times, and the spec's "8" is off by one

Three independent runs drove the loop to exhaustion. **All three stopped at exactly nine fires.**
**[obs]**

| run | mode | fires | first `stop_hook_active: true` | outcome |
| --- | --- | ---: | ---: | --- |
| A | `exit 2`, fixed stderr | **9** | fire 2 | runtime override |
| A2 | `exit 2`, varying stderr | **9** | fire 2 | runtime override |
| B | `{"decision":"block"}`, exit 0 | **9** | fire 2 | runtime override |
| C | `exit 3` | **1** | — | turn ended normally |

The probe's own hard rail sits at 12 and **was never reached in any run** — the runtime stopped the loop
first, in every case, on the ninth fire.

### Why nine and not eight

The binary reads **[bin]** @ 22997471:

```
let Or = ee.CLAUDE_CODE_STOP_HOOK_BLOCK_CAP ?? 8;
if (Or > 0 && Fr > Or) return … yield DI(
  `A hook blocked the turn from ending ${Fr} consecutive times — overriding and ending turn. …`)
```

`Fr` counts **blocks that have happened**, and the test is `Fr > 8`, not `Fr >= 8`. So the 9th block is
performed — the hook runs, reads its payload, writes its stderr — and *then* the runtime refuses to act
on it. The observed warning names the number itself: **"blocked the turn from ending 9 consecutive
times"**. **[obs]** The default value 8 is real; it is the number of blocks *tolerated*, and the hook
runs once more than that.

> **Correction to [`speech-integration-spec.md` §5](speech-integration-spec.md).** The spec says a
> blocking speech hook "gets re-fired up to 8 times, **speaking the same message up to 8 times**";
> [`turn-finality-and-the-stop-hook.md`](turn-finality-and-the-stop-hook.md) bounds the same worst case
> at "at most 8 fires, so at most 8 utterances". **The observed number is nine.** The reasoning was
> right and the arithmetic was one short: 8 is the cap on tolerated blocks, and the invocation count is
> 8 + 1.
>
> **Nine is the count of *fires*, and this document should not be read as saying nine utterances.**
> [Run A below](#5--last_assistant_message-carries-the-newer-text-confirmed-on-the-wire) is the case that settles
> it: nine fires, one distinct string — and under the spec's §5.1 text-hash dedup, **at most one
> utterance**. Fires and utterances are different quantities and only coincide where the text changes
> on every fire, nothing dedupes, and every synthesis attempt succeeds. Recorded here rather than silently patched, because #11 owns that document.

`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` was **unset** in the driven session's environment; 9 is the default
behaviour, not a configured one. **[obs]** The `0`-disables-the-cap branch was **not exercised** and
remains read-only knowledge. **[bin]**

### The counter resets per turn

Runs A2, B and C ran in the **same** driven session, one after another, and each got its own full
ladder — A2 reached 9, then B reached 9 again, then C fired once. **[obs]** `Fr` counts *consecutive*
blocks within one turn and starts again at the next prompt. A hook that blocks every turn does not
accumulate toward a session-wide ceiling; it pays the full price every turn.

---

## 3 — `stop_hook_active` flips on fire 2 and never flips back

Observed in all three blocking runs, identically **[obs]**:

```
fire 1  stop_hook_active=false
fire 2  stop_hook_active=true
fire 3..9  stop_hook_active=true
```

It is `false` exactly once per turn, on the fire that has not yet blocked anything, and `true` on every
fire thereafter including the one that gets overridden. This matches **[docs]** — *"`false` on the first
run and when no block is in effect"* — with no surprises.

---

## 4 — The post-cap override: a warning to the user, and **silence toward the model**

### To the user

One line in the TUI, rendered from a `system` transcript record. Full record, quoted **[obs]**:

```json
{"type":"system","subtype":"informational","level":"warning","isMeta":false,
 "content":"A hook blocked the turn from ending 9 consecutive times — overriding and ending turn. For Stop/SubagentStop hooks, check stop_hook_active in the input and return success while it's true. Set CLAUDE_CODE_STOP_HOOK_BLOCK_CAP to raise this limit."}
```

It is byte-identical to the template in the binary at @ 22997471, with `${Fr}` filled in as 9. The
binary reading was exactly right. In the pane it appears as a plain bullet under the last hook error,
in the same column as assistant output, and the TUI additionally offers the user a **suggested next
prompt** — observed as `disable the stop hook` after run A and `disable the block probe hook` after
run C. **[obs]** That suggestion is the harness's, not the model's; it is dim placeholder text in the
input box and is replaced by whatever the user types.

### To the model: nothing

**The model is never told the override happened.** The `informational` record is `type: "system"` —
a local transcript/UI entry, not part of the conversation sent to the API. There is no assistant turn
after it. **[obs]**

What the model *is* left with is stranger and worth stating plainly: **the fire-9 `Stop hook feedback:`
user message is appended to the conversation and never answered.** The transcript's tail, in order
**[obs]**:

```
assistant : "banana"
user      : "Stop hook feedback:\n[…]: … fire 9"     (isMeta: true)
system    : stop_hook_summary
system    : informational  ← the override warning
system    : turn_duration
```

So the turn ends with an unanswered meta user message in context. From the model's side the turn simply
stops mid-exchange; from the user's side a warning explains why. **A hook cannot detect that it has been
overridden** — the override happens after the hook has already exited, and nothing is fed back to it.
The only way a hook knows it is deep in a loop is `stop_hook_active`, which says `true` from fire 2 and
says nothing about how close the cap is.

---

## 5 — `last_assistant_message` carries the **newer** text. Confirmed on the wire.

**This is the observation the probe was really for.** Both prior documents rejected a design that used
`stop_hook_active` as a duplicate-detector, on the reasoning that *Claude replies to the block before
`Stop` fires again*, so the later payload holds newer text. That reasoning was **[bin]**-and-**[inferred]**
only, and the rejected design was the intuitive one. It is now **[obs]**.

Run A's ladder was inconclusive by construction: the model answered `banana` every time, so all nine
payloads carried `banana` — identical text is consistent with both hypotheses. Run A2 fixed that by
making the stderr demand a *different* word on each fire. The result, read straight out of the payload
files **[obs]**:

| fire | `stop_hook_active` | `last_assistant_message` |
| ---: | --- | --- |
| 1 | `false` | `banana` |
| 2 | `true` | `banana` |
| 3 | `true` | `bravo` |
| 4 | `true` | `charlie` |
| 5 | `true` | `delta` |
| 6 | `true` | `echo` |
| 7 | `true` | `foxtrot` |
| 8 | `true` | `golf` + *"That hook is rejecting every reply … I'm stopping the ladder here"* |
| 9 | `true` | `I'm not continuing the chain — the probe rejects every response regardless of content…` |

**The field updates on every re-fire and always holds the most recent assistant message.** A hook that
went silent whenever `stop_hook_active` was `true` would, in this run, have spoken `banana` and
suppressed the seven distinct messages that followed — including the one the model actually meant as
its answer.

> The rejected design is **confirmed rejected, for the stated reason**, and the reason is no longer
> inferred. [`speech-integration-spec.md` §5.1](speech-integration-spec.md) locks *"`speak.sh` reads
> `stop_hook_active` for no behaviour at all"* and specifies text-hash dedup instead. **That lock is
> now supported by observation.** Run A is the case the hash is for: nine fires, one distinct string,
> one utterance. Run A2 is the case the hash correctly does *not* suppress: nine fires, eight distinct
> strings, and the user wants to hear the last one.

### A field that is stable across the ladder, and might be useful

Every one of the nine payloads in run A2 is **identical field for field except `stop_hook_active` and
`last_assistant_message`** — verified by `diff` of the sorted JSON **[obs]**. In particular:

```
prompt_id  =  3f1f1ca1-3cd0-4b21-84a1-b381c8d87461   on fires 1, 5 and 9 alike
```

**`prompt_id` is constant across all fires of one turn.** It is not mentioned in either prior document
as anything but a key name. It gives a hook a per-turn identity that survives the re-fire loop and
changes at the next user prompt — which is exactly the scope a "have I already spoken for this turn?"
question needs, and it needs no hashing. **Offered as an observation, not a recommendation**: whether
`speak.sh` wants turn-scoped or text-scoped dedup is #11's call, and §5.1's text hash already handles
the case that matters. **Unobserved:** whether `prompt_id` is stable across a session resume, a
compaction, or `--continue`.

The payload also still carried **exactly eleven keys** on every fire, matching the earlier capture:

```
background_tasks cwd effort hook_event_name last_assistant_message
permission_mode prompt_id session_crons session_id stop_hook_active transcript_path
```

`stop_reason` and `model` were absent again, in all 28 fires. That is now 29 payloads on 2.1.245 with
no `stop_reason` — still not proof of permanent absence, but the docs' divergence is not a one-off.
**[obs]**

`background_tasks` was **empty** in every fire here, because the driven session ran no subagents — the
complement of the earlier capture, where it was non-empty. Both states are now observed. **[obs]**

---

## 6 — The JSON route is the same loop, with one cosmetic difference

Run B's hook exited **0** and printed `{"decision":"block","reason":"claudish block probe: JSON decision
block, fire N"}` on stdout. **[obs]**

- **Same loop.** Nine fires, `stop_hook_active` `false` then `true` from fire 2.
- **Same cap.** Eight blocks tolerated, the ninth overridden, with the identical warning text.
- **Same two surfaces for the text.** `reason` lands in exactly the places exit-2 stderr lands: the
  `hookErrors` array of the `stop_hook_summary` system record, and a `Stop hook feedback:` meta user
  message the model reads.
- **One difference, and it is presentation only.** Exit 2 prefixes the hook's command path; the JSON
  route does not.

| route | what the model sees | what the TUI shows |
| --- | --- | --- |
| `exit 2` | `Stop hook feedback:\n[/path/to/probe.sh]: <stderr>` | `Stop hook error: [/path/to/probe.sh]: <stderr>` |
| `{"decision":"block","reason":…}` | `Stop hook feedback:\n<reason>` | `Stop hook error: <reason>` |

So `reason` surfaces as an **error**, in the model's context and in the user's pane, whatever the word
"reason" suggests. There is no quieter blocking channel. **[obs]**

Two things about this route were **not exercised**: `decision: "block"` with no `reason` field, and the
`permissionDecision: "block"` spelling that **[docs]** uses when describing `stop_hook_active`. Only
`decision`/`reason` was tested, and it worked.

### The `stop_hook_summary` record, and one field not to read

Every fire also writes a `system` / `stop_hook_summary` record. Quoted whole from run A fire 1 **[obs]**,
because it names something the plugin should know about:

```json
{"type":"system","subtype":"stop_hook_summary","hookCount":2,
 "hookInfos":[{"command":"…/claudish-blockprobe/probe.sh"},{"command":"…wiki hot-cache hook…","durationMs":23}],
 "hookErrors":["[…/probe.sh]: claudish block probe: deliberate exit 2, fire 1\n"],
 "hookAdditionalContext":[],"preventedContinuation":false,"stopReason":"",
 "level":"suggestion"}
```

- **`hookCount: 2`** — a **pre-existing, unrelated `Stop` hook** was live on this machine the whole time
  (a wiki hot-cache updater from an installed plugin, ending in `|| true`). It exited 0 on all 28 fires
  and never blocked. It is noted so the "Ran 2 stop hooks" line in the evidence below is not mistaken
  for the probe firing twice. **Multiple hooks where more than one blocks was not tested.**
- **`preventedContinuation` was `false` on every single one of the 28 fires — including all 27 fires
  of the three blocking runs, A, A2 and B.** **[obs]** Whatever that field tracks, it is **not** "this
  hook blocked the turn". Recorded as
  observed-and-uninterpreted; nothing should be built on it without finding out what it means.

---

## 7 — Negative control: exit 3 does not block

Run C's hook exited **3** with stderr on an otherwise identical turn.

**One fire. No re-fire. Turn ended normally.** **[obs]** The count file read `1` and stayed there.

The transcript for that turn contains **no `Stop hook feedback:` user message at all** — the model was
told nothing:

```
user      : "Reply with exactly one word: pear. Do not use any tools."
assistant : "pear"
system    : stop_hook_summary  hookErrors: ["Failed with non-blocking status code: claudish block probe: deliberate exit 3, fire 1"]
system    : turn_duration
```

and the TUI showed one line **[obs]**:

```
⏺ Ran 2 stop hooks
  ⎿  Stop hook error: Failed with non-blocking status code: claudish block probe: deliberate exit 3, fire 1
```

**The harness's own phrase — "non-blocking status code" — is on screen.** The retraction carried in
[`turn-finality-and-the-stop-hook.md`](turn-finality-and-the-stop-hook.md#only-exit-code-2-blocks--an-earlier-revision-of-this-document-got-this-wrong)
and [`speech-integration-spec.md` §5](speech-integration-spec.md), which corrected the thrice-stated
claim that *any* non-zero exit blocks, is **confirmed on the wire**. The claim was false and the
correction is right.

One asymmetry worth keeping: a **blocking** hook's stderr becomes model-visible prompt text (§1); a
**non-blocking** hook's stderr does not. It is warning-only, user-visible, model-invisible. That is the
behaviour a fail-open speech hook wants, and it is what exit 0 and any accidental exit 1/127 will get.

---

## What was still not observed

Named so the next probe knows where to start, and so nothing here is read as broader than it is.

- **`async: true`.** The probe hook was synchronous. Whether an async `Stop` hook's exit code is read
  at all, whether it is subject to this cap, and whether its payload is identical are **all still
  open** — the three questions [PR #19](https://github.com/FrancisBehnen/claudish-to-spoken-english/pull/19)
  flagged as untested by this probe. It was right: this probe tests none of them. Everything measured
  here describes a **synchronous** hook.
- **`SubagentStop`** blocking behaviour. Not exercised at all. The cap string names both events; only
  `Stop` was driven.
- **A raised or disabled cap.** `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` was unset throughout. The `Or > 0`
  guard that disables the cap at `0` is **[bin]** only, and is exactly the setting that could wedge a
  session, so it was deliberately left alone.
- **Two blocking hooks at once.** `hookCount` was 2 but only one of them ever blocked.
- **`decision: "block"` with no `reason`**, and the `permissionDecision: "block"` spelling from
  **[docs]**.
- **What `preventedContinuation` actually means.** Observed `false` on all 28 fires, including the 27
  that came from the three blocking runs.
- **Interrupt during a block loop.** Esc / Ctrl-C mid-ladder was never needed and never tried.
- **`prompt_id` across resume, compaction, or `--continue`.**
- **`StopFailure`**, still unexercised, as it was after the first probe.
- **A block loop with a real, long assistant message.** Every payload here held one word or one
  sentence. Nothing about the loop should depend on length, but that is an assumption, not an
  observation.

---

## Where this sits

**Against [#1](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/1), the map:** this is
evidence, not a new decision. It changes no locked item.

**Against [#11](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/11), the spec that
cannot be locked:** [`speech-integration-spec.md`](speech-integration-spec.md) lists the block mechanics
as an open-but-non-blocking gap, and reasons about them from the binary in §5 and §5.1. **That gap is
closed and the reasoning held.** Specifically:

1. **§5.1's central claim — the re-fire carries newer text — is confirmed on the wire**, with a
   ladder of eight distinct strings across nine fires. The rejected duplicate-detector design stays rejected, now for an
   observed reason rather than an inferred one, and the text-hash dedup it specifies is shown to be
   correct in both directions: it suppresses run A's repetition and correctly does not suppress run
   A2's ladder.
2. **§5's worst case is 9 *invocations*, not 8** — the only factual correction this probe produces.
   **Not 9 utterances:** run A shows nine fires resolving to one distinct string, which §5.1's hash
   speaks at most once. The invocation ceiling and the audio cost are different numbers, and §5 has
   been corrected to say so.
3. **§5's fail-open rule gains a second, sharper reason.** A blocking hook's stderr is *prompt input*
   to the model, not just log noise.
4. Nothing in §3, §4, §6–§11 is touched.

**#11 remains unlockable for the reasons #11 already names** — the worker lifecycle (§10.5), the
unsynthesized settled combination (§4.2), `flag-pause`'s missing carrier (§4.3). **The block mechanics
are no longer on that list.**

No issue is opened or closed by this document. The spec edit implied by point 2 belongs to whoever next
touches #11, and is deliberately not made here.

---

## The raw fire log

Verbatim, four runs, one line per hook invocation, written by the probe itself at the moment it ran.
**[obs]**

```
=== run A — exit 2, fixed stderr ===
16:06:33 mode=exit2 fire=1 stop_hook_active=false
16:06:35 mode=exit2 fire=2 stop_hook_active=true
16:06:38 mode=exit2 fire=3 stop_hook_active=true
16:06:41 mode=exit2 fire=4 stop_hook_active=true
16:06:43 mode=exit2 fire=5 stop_hook_active=true
16:06:45 mode=exit2 fire=6 stop_hook_active=true
16:06:46 mode=exit2 fire=7 stop_hook_active=true
16:06:48 mode=exit2 fire=8 stop_hook_active=true
16:06:50 mode=exit2 fire=9 stop_hook_active=true
        → runtime override, turn ended

=== run A2 — exit 2, stderr demanding a different word each fire ===
16:08:22 mode=vary fire=1 stop_hook_active=false
16:08:24 mode=vary fire=2 stop_hook_active=true
16:08:33 mode=vary fire=3 stop_hook_active=true
16:08:35 mode=vary fire=4 stop_hook_active=true
16:08:36 mode=vary fire=5 stop_hook_active=true
16:08:38 mode=vary fire=6 stop_hook_active=true
16:08:40 mode=vary fire=7 stop_hook_active=true
16:08:49 mode=vary fire=8 stop_hook_active=true
16:08:53 mode=vary fire=9 stop_hook_active=true
        → runtime override, turn ended

=== run B — exit 0 with {"decision":"block","reason":…} on stdout ===
16:09:15 mode=json fire=1 stop_hook_active=false
16:09:17 mode=json fire=2 stop_hook_active=true
16:09:19 mode=json fire=3 stop_hook_active=true
16:09:21 mode=json fire=4 stop_hook_active=true
16:09:24 mode=json fire=5 stop_hook_active=true
16:09:26 mode=json fire=6 stop_hook_active=true
16:09:28 mode=json fire=7 stop_hook_active=true
16:09:29 mode=json fire=8 stop_hook_active=true
16:09:31 mode=json fire=9 stop_hook_active=true
        → runtime override, turn ended

=== run C — exit 3 (negative control) ===
16:10:01 mode=exit3 fire=1 stop_hook_active=false
        → turn ended normally, no re-fire
```

Whole ladders take **17–31 seconds** wall-clock: run A 16:06:33→16:06:50, run B 16:09:15→16:09:31.
Roughly two seconds per fire, dominated by the model's reply to each block, not by the hook. **[obs]**

## The payload diff, first fire against last

Run A2, `jq -S` on both, `diff`. **The entire difference is one field** — and
`last_assistant_message`, deleted before the diff, is [tabulated above](#5--last_assistant_message-carries-the-newer-text-confirmed-on-the-wire).
**[obs]**

```diff
--- A2-payload-1.json
+++ A2-payload-9.json
12c12
-   "stop_hook_active": false,
+   "stop_hook_active": true,
```

## What the user saw

Run A's pane, verbatim, ending at the override. `Ran 2 stop hooks` is the pre-existing plugin hook
plus the probe, [as explained above](#the-stop_hook_summary-record-and-one-field-not-to-read).
**[obs]**

```
❯ Reply with exactly one word: banana. Do not use any tools.

⏺ banana

⏺ Ran 2 stop hooks
  ⎿  Stop hook error: [/Users/francis.behnen/.local/share/claudish-blockprobe/probe.sh]: claudish block probe: deliberate exit 2, fire 1

⏺ banana

⏺ Ran 2 stop hooks
  ⎿  Stop hook error: [/Users/francis.behnen/.local/share/claudish-blockprobe/probe.sh]: claudish block probe: deliberate exit 2, fire 2

              … fires 3 through 8, identical in shape …

⏺ banana

⏺ Ran 2 stop hooks
  ⎿  Stop hook error: [/Users/francis.behnen/.local/share/claudish-blockprobe/probe.sh]: claudish block probe: deliberate exit 2, fire 9

⏺ A hook blocked the turn from ending 9 consecutive times — overriding and ending turn. For Stop/SubagentStop hooks, check stop_hook_active in the input
  and return success while it's true. Set CLAUDE_CODE_STOP_HOOK_BLOCK_CAP to raise this limit.
```

The status bar carried `Stop hook error occurred · ctrl+o to see` throughout. **[obs]**

---

## The probe as it was run

**Spent and torn down.** Recorded so the claims above are reproducible — not as work outstanding.

**The blocking hook never entered `~/.claude/settings.json`.** That file drives this session and the
user's other live sessions; a blocking `Stop` hook installed there would have wedged all of them. It
was checksummed before the probe and again after teardown:

```
b73f471a3f100d111d7a69387be3d0adaa8e37c6552b52362f7209fdbb3f945f   before
b73f471a3f100d111d7a69387be3d0adaa8e37c6552b52362f7209fdbb3f945f   after
```

Identical, and its `hooks` key held only `SessionStart` throughout. **[obs]**

### Scoping, and why a null result would have been trustworthy

The hook was scoped to **one** session by launching it with an explicit settings file over a throwaway
working directory:

```bash
mkdir -p "$SCRATCH/bp"
cat > "$SCRATCH/bp/settings.json" <<'JSON'
{ "hooks": { "Stop": [ { "hooks": [
  { "type": "command",
    "command": "/Users/francis.behnen/.local/share/claudish-blockprobe/probe.sh",
    "timeout": 10 } ] } ] } }
JSON
```

driven through a Herdr pane as a second `claude`:

```bash
herdr agent start blockprobe --kind claude --pane w1:pR -- --settings "$SCRATCH/bp/settings.json"
```

**Scoping was verified positively before any conclusion was drawn.** The hook fired 28 times, every
fire wrote a numbered payload, and the counts matched the driven session's turns exactly with no stray
fires from any other session. A hook that silently never ran would have left an empty log — the
negative control in run C is only meaningful *because* runs A, A2 and B had already proved the same
mechanism fires and blocks. **[obs]**

### The probe script

A single script, dispatching on a `mode` file so the four runs could share one driven session, with
counters reset between runs. It has a **hard rail at 12 fires** — an unconditional `exit 0` that no
mode can bypass, so no session could be permanently wedged whatever the cap turned out to be. **The
rail was never reached**; the runtime's own cap stopped every blocking run on its ninth fire.

```bash
d="$HOME/.local/share/claudish-blockprobe"
mode=$(cat "$d/mode" 2>/dev/null || echo exit2)
n=$(( $(cat "$d/count" 2>/dev/null || echo 0) + 1 ))
printf '%s' "$n" > "$d/count"
cat > "$d/payload-$n.json"                       # the whole stdin payload, per fire
printf '%s mode=%s fire=%s stop_hook_active=%s\n' "$(date +%H:%M:%S)" "$mode" "$n" \
  "$(jq -r '.stop_hook_active' "$d/payload-$n.json")" >> "$d/log"

# Hard safety rail: never block past 12 fires, whatever the cap turns out to be.
if [ "$n" -ge 12 ]; then printf 'probe: stopping at %s fires\n' "$n" >&2; exit 0; fi

case "$mode" in
  json)  printf '{"decision":"block","reason":"… fire %s"}\n' "$n"; exit 0 ;;
  vary)  w=$(printf 'alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima' | cut -d' ' -f"$n")
         printf 'Rejected. Reply again with exactly one word and nothing else: %s\n' "$w" >&2; exit 2 ;;
  exit3) printf '… deliberate exit 3, fire %s\n' "$n" >&2; exit 3 ;;
  *)     printf '… deliberate exit 2, fire %s\n' "$n" >&2; exit 2 ;;
esac
```

Each run reset `count`, `log` and the payload files first, so fire numbering is per-run and the log
above is exactly what the probe wrote.

### Teardown

The driven session was exited, the pane returned to a shell prompt and left in place (it was not
created by this probe), the throwaway settings file deleted, and the absence of any `Stop` hook
re-checked from a fresh read of every settings file on the machine. `~/.claude/settings.json`
re-checksummed to the same value. **No `Stop` hook exists anywhere on this machine as a result of this
probe.** **[obs]**

The prompts used were `Reply with exactly one word: banana` / `cherry` / `pear`, chosen so that every
captured payload contains nothing but throwaway text. All quoted message content in this document is
the complete content of those payloads.

---

## DECISION (2026-08-25)

1. **Exit 2 blocks; the block loop runs the hook nine times.** One initial fire, eight re-fires, the
   ninth block overridden. Measured three times, identically. **[obs]**
2. **`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` defaults to 8 and it counts *tolerated blocks*, so the
   invocation count is 9.** [`speech-integration-spec.md` §5](speech-integration-spec.md)'s "up to 8
   times" is off by one. The correction belongs to #11.
3. **A blocking hook's stderr is prompt input.** It reaches the model as
   `Stop hook feedback:\n[<command>]: <stderr>`, and the model demonstrably obeys it. Exit 0 on every
   path now has a second reason, sharper than transcript noise.
4. **A non-blocking hook's stderr is not.** Exit 3 produced one fire, one warning line, and nothing in
   the model's context. The retraction of "any non-zero exit blocks" is confirmed on the wire.
5. **`stop_hook_active` is `false` on fire 1 and `true` on fires 2–9.** As documented, no surprises.
6. **`last_assistant_message` carries the newest text on every re-fire — observed, not inferred.**
   Eight distinct strings across nine fires in one ladder. The duplicate-detector design stays rejected, and §5.1's
   text-hash dedup is shown correct in both directions.
7. **The JSON route is the same mechanism.** Same nine fires, same cap, same warning, `reason` landing
   in the same two places as stderr. There is no quieter way to block.
8. **The override is invisible to the model and visible to the user**, as one `level: "warning"` line
   quoting the binary verbatim. A hook cannot detect that it has been overridden.
9. **`prompt_id` is constant across all fires of a turn.** Offered as an observation. Whether it is
   useful to `speak.sh` is #11's call, and §5.1's text hash already covers the case that matters.
10. **The block mechanics are no longer an open gap in #11.** What remains unobserved is
    [named above](#what-was-still-not-observed), and none of it is load-bearing for the speech design.
