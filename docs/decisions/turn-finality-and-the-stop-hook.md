# Turn finality: the `Stop` hook settles #10

Closes out [#10](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/10), part of the
[Kokoro speech map (#1)](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/1).
Established 2026-08-25 against Claude Code **2.1.245**.

**#10 asked for a number and the answer is that there is no number.** The audition
([`min-length-audition.md`](min-length-audition.md#finding-2026-08-25-length-is-the-wrong-variable))
refuted the premise: the listener was not judging length, they were judging **status update vs
final message**. That left one factual question — *can the plugin tell which is which?* — and it now
has an answer: **yes, directly, from the `Stop` hook event.** Nothing has to be inferred, deferred,
or cancelled.

**This document is field names, event names, and two numbers.** It contains no measurement and no
listening. It does now contain **one observation**: a live `Stop` payload was captured on this
machine on 2026-08-25 by a throwaway hook, which was torn down in the same sitting.
[The observed payload is below](#what-was-observed), and it matched the compiled schema field for
field. Where the docs and the binary disagreed, **the binary was right**: the payload has no
`stop_reason` and no `model`, both of which the published docs list.

No LLM was called. **No plugin hook was touched** — `rewrite.sh`, `rewrite-md.sh`, `providers.sh` and
`hooks/` are unmodified. The probe hook lived in the user's own `settings.json` and no longer exists.

---

## How each fact below was established

Three sources, named per claim so the weak ones stay visible.

| tag | source | what it can and cannot prove |
| --- | --- | --- |
| **[docs]** | <https://code.claude.com/docs/en/hooks.md>, fetched 2026-08-25 | states intent; can lag or lead the installed build |
| **[bin]** | `/Users/francis.behnen/.local/share/claude/versions/2.1.245` (Mach-O arm64, 376 MB), read via `strings -n 6` | proves what **this** build contains — the compiled Zod schema and the dispatch code |
| **[inferred]** | reading the minified control flow | a reading of code, not a run of it |
| **[obs]** | two captures on 2.1.245, 2026-08-25, both by throwaway hooks since removed: **one** live `Stop` payload (everything below except Correction 3), and **28 fires across four driven block-loop runs** ([`stop-hook-block-mechanics.md`](stop-hook-block-mechanics.md), the source for Correction 3 and for the fire counts) | proves a field **was** present, with that value, in the turns actually observed; a single sample can never prove a field is always absent |

Offsets below are byte offsets into the `strings -n 6` output, which is reproducible:

```bash
strings -n 6 ~/.local/share/claude/versions/2.1.245 > /tmp/cc.strings
grep -c 'stop_hook_active' /tmp/cc.strings   # 6 lines
grep -c 'SubagentStop'     /tmp/cc.strings   # 67 lines
```

---

## The finding

**`Stop` carries the complete final assistant text of the turn, in a field built for exactly this.**

```
last_assistant_message   string, OPTIONAL
```

> "Text content of the last assistant message before stopping. Avoids the need to read and parse the
> transcript file." — **[bin]** @ 32880490, the compiled schema for `hook_event_name: "Stop"`

> "The assistant's final message text from this turn, as a single string. Use this instead of reading
> the transcript file, which is written asynchronously and may lag" — **[docs]**

Both sources say the same thing and the docs add the reason: **do not read `transcript_path` for
this.** The transcript is written asynchronously and can lag the in-memory conversation, so a hook
that parses it races the writer. `rewrite.sh` already reads `transcript_path` (for the user's
question, as rewrite context) and that use is fine — it wants an *older* message. Turn-final text is
the case where the lag bites.

### Why this is the discriminator the audition asked for

`MessageDisplay.final` is **message-level**, and the shipped schema says so in as many words:

> `final` — "True on the message's last flush. Exactly one flush per message has it."
> `delta` — "The newly completed lines since the prior flush. Always whole lines, except on the final
> flush which may end mid-line. The delta of the final flush is empty when the message ends on a
> newline; treat final as the end-of-message signal regardless."
> — **[bin]** @ 32885214

`rewrite.sh:9` describes it as "true on the last chunk" and `rewrite.sh:110` reads it as
`.final // false`. That comment is **correct** — and it is correct about the wrong scope. "Last flush
of this message" is not "last message of this turn". A turn that emits three narration messages and
two tool calls fires `final: true` three times.

`Stop` fires when the turn ends, carrying the text of the message that ended it. That *is* "final
message" in the listener's sense, with no lookahead and no window.

**One qualification, because "once per turn" is not unconditional.** `Stop` fires once per *attempt*
to end the turn. If any `Stop` hook blocks — exit code 2, or a blocking JSON decision — Claude
responds to the block and `Stop` fires again, with `stop_hook_active: true` and, because the model
has spoken since, potentially **different** `last_assistant_message` text. The first payload is
therefore an *attempted* final message, not a guaranteed one.

In the ordinary case — nothing in the user's config blocking on `Stop` — there is exactly one fire
per turn, and that is what was observed: one capture for the turn. What the plugin can and cannot
infer when a block does happen is
[settled below](#stop_hook_active-is-not-a-duplicate-detector); the short version is that the
re-fire usually carries the *newer* answer, so the second payload is the one worth speaking.

### Defer-and-cancel is dead

The audition offered two shapes and called it #11's choice. It is no longer a choice.
**Defer-and-cancel** — synthesize on every message, cancel if a tool use follows within a window —
was only ever a workaround for finality being unobservable. Finality is observable. The workaround
costs a timer, a cancel path, a window constant nobody can justify, and a race; it buys nothing.
Route speech off `Stop` and delete the idea.

---

## Correction 1 — `stop_hook_active` exists, and it is a re-entrancy flag

The research that preceded this document reported that "no `stop_hook_active` style re-entrancy flag
is documented." **That is wrong on both halves: the field exists in 2.1.245 and it is documented.**

```
stop_hook_active   boolean, REQUIRED
```

**[bin]** @ 32880490 compiles it as required on `Stop` (`stop_hook_active:i()`, no `.optional()`)
and @ 32881414 as required on `SubagentStop`. **[docs]** gives the semantics:

> "Boolean. `true` when a `Stop` hook is currently running and has blocked Claude from stopping (via
> exit code 2 or `permissionDecision: "block"`), to avoid infinite loops. When `true`, you should
> avoid blocking again or you'll prevent Claude from ever advancing. `false` on the first run and
> when no block is in effect"

### What it means for a TTS hook

The flag is about **blocking**, not about firing. A `Stop` hook that blocks the turn from ending gets
re-invoked after the model responds to the block, and on that second invocation `stop_hook_active` is
`true`. It is a "you are inside your own loop" marker.

The runtime does not trust hooks to respect it. **[bin]** @ 22997471, in the turn loop:

```
let Or = ee.CLAUDE_CODE_STOP_HOOK_BLOCK_CAP ?? 8;
if (Or > 0 && Fr > Or) return … yield DI(
  `A hook blocked the turn from ending ${Fr} consecutive times — overriding and ending turn. `
  + "For Stop/SubagentStop hooks, check stop_hook_active in the input and return success while "
  + "it's true. Set CLAUDE_CODE_STOP_HOOK_BLOCK_CAP to raise this limit.", "warning")
```

So: **the default block cap is 8** consecutive blocks — but read the comparison, not just the number.
`Fr > Or` is **strict**, so 8 blocks are *tolerated* and the **ninth** is the one overridden: a
blocking hook is invoked **nine** times, one initial fire plus eight re-fires. **[obs]** This document
originally read the 8 as the invocation count; see
[Correction 3](#correction-3--the-block-cap-counts-tolerated-blocks-not-invocations). Env override
`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`; `0` disables the cap — **[bin]** only, never exercised.

### Only exit code 2 blocks — an earlier revision of this document got this wrong

**An earlier revision of this section claimed that *any* non-zero exit from a `Stop` hook holds the
turn open. That is false, and the binary says so in as many words.** The correction is recorded here
rather than quietly deleted, because the wrong version also went out in the #10 close comment.

Exit status is sorted into three classes, not two. **[bin]** @ 9557061, the command-hook result
resolver:

```js
let h = e.status === 2 && Ln({ hookEvent: t, stdout: e.stdout, stderr: e.stderr });
…
if (e.status === 0) return { answer: {}, exitClass: "0", blocked: !1 };
if (e.status === 2) {
  if (h) return { answer: {}, exitClass: "2",
                  localWarning: `[${n}]: the hook script appears to be missing (…)`, blocked: !1 };
  return { answer: Me(t, `[${n}]: ${e.stderr || "No stderr output"}`), exitClass: "2", blocked: !0 };
}
return { answer: {}, exitClass: "other",
         localWarning: `[${n}]: failed with non-blocking status code ${e.status}: …`, blocked: !1 };
```

- **0** — success.
- **2** — `blocked: true`. **This is the only status that blocks.** And even it does not always: `h`
  is a heuristic that recognises "the script isn't there" and downgrades that exit 2 to a warning.
- **any other non-zero** — `exitClass: "other"`, and the harness's own word for it, in the warning
  string it emits, is **"non-blocking status code"**.

The consumer side confirms the classes have different consequences. **[bin]** @ 16573673, the `Stop`
branch of the turn loop:

```js
if ("hookEvent" in g && g.hookEvent === "Stop") {
  if (g.type === "hook_non_blocking_error") y.push(g.stderr || `Exit code ${g.exitCode}`);
  else if (g.type === "hook_error_during_execution") y.push(g.content);
}
if (h.blockingError) t.push(k({ content: n.getStopHookMessage(h.blockingError), isMeta: !0 })),
                     r = !0;                                    // r === requestQuery
…
if (y.length > 0) t.push(D(`Stop hook error: ${y.join("; ")}`, "warning"));
…
return { messages: t, requestQuery: r };
```

`requestQuery` — *"go back to the model, the turn is not over"* — is set **only** by `blockingError`,
or by `additionalContexts`. A non-blocking error is collected into `y` and rendered as one warning
line, `Stop hook error: …`, and the turn ends normally.

**The quoted `stop_hook_active` documentation above already said this, and this document failed to
read its own quote**: *"has blocked Claude from stopping (via exit code 2 or
`permissionDecision: "block"`)"* — exit code 2, named specifically.

### So what is the actual hazard?

Smaller than claimed, and differently shaped. The *fail-open* discipline the rest of this plugin is
built on still applies (`rewrite.sh` exits 0 on every error path so a display hook can never swallow
content, `rewrite.sh:23-24`), but the reason to keep it on `Stop` is narrower:

- A `set -e` trip under an unset var, a Kokoro import error, a missing binary — these exit 1, or 127,
  or 2 only by coincidence. They produce a visible `Stop hook error:` warning and **do not hold the
  turn**. Noisy, not looping.
- **`jq` is the one to watch — but not for the reason this bullet used to give.**

  > **CORRECTED 2026-08-25, measured rather than read.** This bullet said *"`jq` exits **2** on a usage or
  > compile error in the filter"*, and the same claim is repeated in the DECISION below as *"`jq` exits
  > 2 on a malformed filter"*. **The compile half is wrong: a malformed filter exits 3, not 2.**
  > Measured on `jq-1.7.1-apple` under Darwin 25.6.0 — a **bad option, a missing file, or
  > `--rawfile <missing>` exits 2**; a **malformed filter (program compile error) exits 3**; and
  > **unparseable JSON on stdin exits 5**. The table of record is in
  > [`speech-integration-spec.md`](speech-integration-spec.md) §5, SECOND CORRECTION, which also names
  > the other exit-2 route this bullet missed entirely: **a bash syntax error in the hook script**.
  >
  > **The conclusion is unchanged and is if anything better supported** — two real exit-2 routes exist
  > and one of them (the syntax error) is worse than the one cited, because it can block turn after turn
  > and speak nothing. But the *mechanism* named here was wrong, and the wording would send an
  > implementer to guard the wrong thing: the shape to guard is a `jq` invocation handed a **filename**
  > (`--rawfile`, `--slurpfile`, a positional file), not a filter typo.

  So: a `Stop` hook that hands `jq` a bad option or an unreadable file can hand the harness a genuine 2
  and really block — and then really get re-fired **eight** times, **nine invocations in all**
  (**[obs]**; [Correction 3](#correction-3--the-block-cap-counts-tolerated-blocks-not-invocations)).
  That is the loop to design against, and it is one specific mistake rather than a broad class.

Two rules follow, and they are still cheap — the second for a different reason than before:

1. **Exit 0 on every path**, as `rewrite.sh` already does. On `Stop` the rationale is not "non-zero
   blocks" but "make the `jq`-exits-2 case unreachable, and keep the transcript free of warning
   noise". It needs its own comment where the exit lives; the display hook's reason is not this one.
2. **Do not use `stop_hook_active` as an "already spoken" flag.** It does not mean that — next
   section.

### `stop_hook_active` is not a duplicate-detector

The rule this document previously stated — *"stay silent when `stop_hook_active` is `true`, because a
`true` means this turn's final message has already been spoken"* — **is wrong, and wrong in the
direction that costs the user their answer.**

`true` means only: *a previous attempt to end this turn was blocked.* It says nothing about whether
this plugin spoke on that attempt, and — the part that matters — **Claude responds to the block
before `Stop` fires again.** The second payload's `last_assistant_message` is therefore usually
*newer* text than the first's, and it is the one the user actually wants to hear. A hook that goes
silent whenever the flag is `true` speaks the answer that got rejected and suppresses the answer that
stood:

| fire | `stop_hook_active` | `last_assistant_message` | the old rule says | user hears |
| --- | --- | --- | --- | --- |
| 1 | `false` | the rejected answer | speak | the rejected answer |
| 2 | `true` | Claude's reply to the block | stay silent | nothing |

**The flag is a blocking-loop guard, not a de-duplication signal.** Deduplication, if wanted, has to
compare the *text* — and the payload carries the text, so hashing `last_assistant_message` against
the last thing spoken is both available and cheap. That also bounds the worst case properly — though
this document first bounded it one short, and in the wrong unit. The cap tolerates 8 blocks, so the
hook is invoked **nine** times
([Correction 3](#correction-3--the-block-cap-counts-tolerated-blocks-not-invocations)); nine is a
count of *fires*, and the utterances only match it if the text changes on every one of them and
nothing dedupes. Observed: a run whose text never changed produced nine fires and **one** distinct
string; a run whose stderr *asked* the model for a different word each fire produced nine fires and
**eight**. **[obs]** The second shows the text can move, not how often it moves unprompted.
([`stop-hook-block-mechanics.md`](stop-hook-block-mechanics.md).)

Speak-first, speak-on-change, or speak-last (which needs knowing a fire is the last one, and it
cannot) is a real choice with no obviously correct answer, and **it is #11's.** What is settled here
is only the constraint: `stop_hook_active` alone cannot make that choice.

---

## Correction 2 — `Stop` does **not** fire for subagents; `SubagentStop` does

The prior research reported that `Stop` fires on subagent completion because "subagents count as
turns." **That is wrong, and it matters more than the other correction**: this repo runs many
subagents, and a speech hook that announced every subagent's final message would talk continuously
through work the user delegated precisely so they would not have to watch it.

The two events are **mutually exclusive**, decided by one ternary. **[bin]** @ 25308665:

```js
async function* YB(e, t, n = Zs, r = !1, o, s, i, a) {
  let l = o ? "SubagentStop" : "Stop";
  …
  if (!c && !Rg(l, u, d)) return;                       // gate on the resolved event name
  …
  let y = o
    ? { …h, hook_event_name: "SubagentStop", stop_hook_active: r, agent_id: o,
          agent_transcript_path: mf(o), agent_type: a ?? "", last_assistant_message: f, …m }
    : { …h, hook_event_name: "Stop",        stop_hook_active: r,
          last_assistant_message: f, …m };
  yield* Td({ …, hookInput: y, timeoutMs: n, … });
}
```

`o` is the agent id, passed by the caller as `e.agentId` (**[bin]**, `executeStopHooks(_e(e).mode,
e.abortController.signal, void 0, !1, e.agentId, e, […])`). Present ⇒ `SubagentStop`. Absent ⇒
`Stop`. One payload or the other, never both, and the config gate `Rg(l, …)` is consulted with the
**resolved** name — so a `Stop` entry in `hooks/hooks.json` is simply never asked for on the subagent
path.

**[docs]** agrees twice: `Stop` is "When Claude finishes responding", `SubagentStop` is "When a
subagent finishes"; and for hooks declared in a subagent's own frontmatter, "Claude Code converts a
`Stop` hook here to `SubagentStop`, the event it fires when a subagent completes."

That conversion is visible in the binary as a debug line, and it is worth being precise about its
scope because it is easy to over-read. **[bin]** @ 23081481:

```js
if (o && i === "Stop") l = "SubagentStop",
  w(`Converting Stop hook to SubagentStop for ${r} (subagents trigger SubagentStop)`);
```

The enclosing function registers **frontmatter** hooks — those declared in an agent definition's own
`.md`. A `Stop` written there is rewritten to `SubagentStop`. **A `Stop` in a plugin's
`hooks/hooks.json` or in `settings.json` is not rewritten**; it is left as `Stop` and therefore only
ever matches the main thread. This plugin wants the un-rewritten behaviour, and gets it by default.

### The consequence for the design

**A `Stop` hook is exactly right, and `SubagentStop` must not be added.** One fire per user-visible
turn. Subagent chatter is silent for free — not by a filter this plugin has to write and maintain,
but because the event never fires. This is a better outcome than the design would have got by asking
for it.

**And this is now observed, not only read off a ternary.** The probe was deliberately run on a turn
that had a subagent in flight. Result: **one** capture for the whole turn, `hook_event_name: "Stop"`.
The subagent completed mid-turn and produced **no second capture** — no `Stop` fire for it. The
payload's `background_tasks` even held that subagent as a live entry, shape
`{ id, type: "subagent", status: "running", description, agent_type }`. So the turn ended with a
subagent registered as running, `Stop` fired exactly once, and it fired for the main thread.
**[obs]** — one sample, and it is the sample that mattered: a build where `Stop` fired for subagents
would have written a second file.

Two footnotes, so the claim is not overstated:

- **One narrow bypass exists.** The gate is `if (!c && !Rg(l, u, d)) return`, where
  `c = B2(s.agentContext)` and **[bin]** @ 21135594 defines
  `B2(e) => e.agentType === "subagent" && e.isBuiltIn === true && e.subagentName === uu`, with
  `uu = "web-fetch"` (**[bin]** @ 21136869). For the built-in `web-fetch` subagent the *config gate*
  is skipped. **This is not a `Stop` leak**: `l` is still `"SubagentStop"` on that path, so the
  payload's `hook_event_name` is unchanged. It means a `SubagentStop` hook may fire for `web-fetch`
  even when configuration would not have selected it. **[inferred]** — the reading is
  straightforward, but this is control flow, not a schema.
- **`agent_id` also appears on the common base**, where **[bin]** @ 32875048 describes it as
  "Subagent identifier. Present only when the hook fires from within a subagent (e.g., a tool called
  by an AgentTool worker). Absent for the main thread, even in `--agent` sessions. Use this field
  (not agent_type) to distinguish subagent calls from main-thread calls." A belt-and-braces
  `agent_id`-absent check is available if the design ever wants one; on `Stop` it is redundant, and
  the capture bears that out — `agent_id` and `agent_type` were both absent from the observed payload,
  on a turn that had a subagent running. **[obs]**

---

## Correction 3 — the block cap counts *tolerated* blocks, not invocations

**An earlier revision of this document read `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP ?? 8` as the number of
times a blocking hook runs. It is not, and the difference is one whole invocation.** Recorded here
rather than silently repaired, for the same reason as Corrections 1 and 2 — and because the same wrong
number reached [`speech-integration-spec.md`](speech-integration-spec.md) §5, which cites this document
for its **[bin]** reading of the cap.

The guard is `if (Or > 0 && Fr > Or)`. The comparison is **strict**, so a run of exactly 8 blocks is
tolerated and the **ninth** is the one refused — which means the ninth block *executes*, and the hook
has been invoked **nine** times by the time the runtime overrides it: **one initial fire plus eight
re-fires.**

This is now observed rather than read. A driven probe put a second `claude` session into the block
loop on purpose and captured every fire: **exactly nine invocations, three times independently** —
`exit 2`, varied-stderr, and the `{"decision":"block"}` JSON route all cap identically — with
`stop_hook_active` `false` on fire 1 and `true` on fires 2–9, and the post-cap warning line naming
the count as 9. **[obs]** The evidence is in
[`stop-hook-block-mechanics.md`](stop-hook-block-mechanics.md), the companion this document asked for
when it named the blocked-turn re-fire as the one part of `Stop` it had read but never seen.

**What this does not change:** the cap's default (8), the env override, the `0`-disables branch
(still **[bin]** only), and every conclusion in this document. Only the count moves, by one.

---

## The harness default timeouts, for `Stop` and for `MessageDisplay`

These are **harness defaults** — what a `command` hook gets when it declares no `timeout` of its own.
They are not caps, and nothing below is a contrast against one; see
[the paragraph on declared values](#a-declared-timeout-replaces-the-default) for why that framing
would be wrong.

| event | `command` hook harness default | where the number is |
| --- | ---: | --- |
| **`Stop`** / **`SubagentStop`** | **600 s** | `var Zs = 600000` — **[bin]** @ 21135182; reached as `YB(e, t, n = Zs, …)`, called with `n = void 0` |
| **`MessageDisplay`** | **10 s** | `var Ds = 10, Eo = 1000/Ds, $o = 3, Do = 1e4` — **[bin]** @ 7808981; both call sites pass `Do` as `timeoutMs` |
| `UserPromptSubmit` | 30 s | **[docs]** |
| everything else, `command` / `http` / `mcp_tool` | 600 s | **[docs]** |

**[docs]** states the same thing independently: "Defaults: 600 for `command`, `http`, and `mcp_tool`;
30 for `prompt`; 60 for `agent`" and "`UserPromptSubmit` lowers the `command`, `http`, and `mcp_tool`
default to 30, and `MessageDisplay` lowers it to 10."

### A declared `timeout` replaces the default

A hook that declares `timeout` gets that value instead of the harness default. One line decides it,
**[bin]** @ 25354456:

```js
let Ce = Z.timeout ? Z.timeout * 1000 : i,
    { signal: _e, cleanup: he } = _f(s, { timeoutMs: Ce });
```

`Z` is the hook's config entry, `i` is the harness default from the table above. `timeout` is in
**seconds** (**[bin]** @ 34081029: `timeout: H().positive().optional().describe("Timeout in seconds
for this specific command")` — `positive()`, no `.max()`).

**Whether the harness imposes any absolute ceiling is UNESTABLISHED.** No clamp appears at this call
site and none appears on the schema, but "not at the two places I looked" is not "nowhere", and a
strings sweep of 2.1.245 turned up no evidence either way. Treat it as an open question, not as a
proven absence. The one *documented* bound anywhere on this surface is `SessionEnd`, which shares a
1.5 s budget raisable by per-hook `timeout` "up to 60 seconds" (**[docs]**) — a per-event budget, not
a global cap.

### The 60 in this repo is a declared value, not a cap

**There is no *harness* 60 s cap to contrast a default against, and nothing in this document should
be read as doing so.** The 60 is this plugin's own declared value: `hooks/hooks.json:9` sets
`"timeout": 60` on `MessageDisplay` (also recorded in `README.md:457`), and `CLAUDISH_TIMEOUT`
(default 45) is deliberately kept under it. The same file declares **180** at `hooks/hooks.json:21`
for `PostToolUse`.

**That 180 is not evidence about a ceiling, and an earlier revision wrongly said it "disproves" one.**
A value the config schema accepts proves only that the schema accepts it — `timeout` is `positive()`
with no `.max()`, so 180 would validate whether or not the runtime clamps at execution time.
Configuration cannot establish runtime enforcement. Whether any absolute ceiling exists stays
**unestablished**, exactly as the previous section says, and this repo's declared numbers cannot
settle it in either direction. (`CLAUDISH_MD_TIMEOUT`'s 150 s default is not evidence either: nobody
has measured a hook actually running that long to completion.)

So the only honest comparison is *declared value vs harness default*: `MessageDisplay`'s harness
default is 10 s and this plugin declares 60; `Stop`'s harness default is 600 s and **a speech hook on
`Stop` would declare its own value** rather than inherit that. Cite `hooks/hooks.json` for the
declared numbers.

(Separately, `rewrite.sh:211`'s timeout hint has a real defect — it advises raising a timeout without
naming its own `hooks.json` ceiling, where `rewrite-md.sh:197` does. That asymmetry is
[#14](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/14)'s and is documented on
`task/provider-switch-traps`; it is not a cap conflict and not this document's.)

For a speech hook on `Stop`, no timeout is the real constraint. The constraint is that a blocking hook
holds the turn: the prompt does not come back until the hook returns. Kokoro's measured worst case in
[`voice-and-pipelining.md`](voice-and-pipelining.md) sits nowhere near any of these numbers, but
"under the timeout" is not "acceptable to wait". The command-hook schema carries the escape — **[bin]** @ 34014312 documents
`async`: "If true, hook runs in background without blocking" — and this is the flag the design should
be reaching for. **#11's call, not settled here.**

---

## What was observed

**One live `Stop` payload, captured 2026-08-25 on 2.1.245**, by a throwaway hook installed in
`~/.claude/settings.json`, fired on one turn, then removed along with its output directory.
[The probe as it was run](#the-probe-as-it-was-run) is below.

### The payload carried exactly eleven fields

```
session_id  transcript_path  cwd  prompt_id  permission_mode  effort
hook_event_name  stop_hook_active  last_assistant_message  background_tasks  session_crons
```

**This matches the compiled schema field for field.** Six from the common base (**[bin]** @ 32875048:
`session_id`, `transcript_path`, `cwd`, `prompt_id?`, `permission_mode?`, `effort?`) and five from the
`Stop` extension (**[bin]** @ 32880490). The base's two remaining optional fields, `agent_id` and
`agent_type`, were absent — which is exactly what the schema says to expect: *"Absent for the main
thread, even in `--agent` sessions."* Their absence is
[correction 2](#correction-2--stop-does-not-fire-for-subagents-subagentstop-does) observed from the
other side.

### The docs were wrong; the binary was right

- **`stop_reason` is absent.** **[docs]** lists it on `Stop` (`"end_turn" | "max_tokens"`). It is not
  in the payload, not in the compiled schema at @ 32880490, and the dispatcher at @ 25308665 never
  constructs one — every `stop_reason` in the binary is an API-message or SDK-result field, not a hook
  input. **This document predicted that divergence before the probe ran, and the prediction held.**
  That is the case for the method: where the two paper sources disagree, prefer the one compiled into
  the build you are actually running.
- **`model` is absent too.** Also listed by **[docs]**, also missing from the common base at
  @ 32875048, also missing from the payload. Same story, independent second instance.
- **`session_crons` is present** — in the binary, absent from the docs, and present on the wire.

So the docs describe a build that is not this one, in both directions. A design reading `stop_reason`
or `model` on 2.1.245 gets `null`.

### `last_assistant_message` arrived populated, and raw

**1511 characters, the full final assistant text of the turn, containing 29 markdown markers.** This
is the load-bearing observation, and it confirms two things at once:

1. **The field works as advertised.** No transcript read, no lag, no parse — the text was simply
   there, complete.
2. **The handoff problem is real, measured, and is this plugin's whole job.** What arrives is *raw
   markdown*: headings, emphasis, list bullets, fences, links — precisely the input `rewrite-md.sh`
   exists to deal with. A speech hook on `Stop` cannot hand `last_assistant_message` to a voice
   as-is; it has to go through sanitisation first. That was always the assumption. It is now 29
   markers in 1511 characters of one ordinary turn.

### `stop_hook_active` was `false`

As documented, on a first fire with nothing blocking.

### `background_tasks` was non-empty, and the subagent was in it

One entry, `{ id, type: "subagent", status: "running", description, agent_type }`, for a subagent
still running as the turn ended. Two consequences:

- It confirms the schema's stated purpose verbatim — letting hooks distinguish *"session is done"*
  from *"session is paused waiting for background work to wake it"*.
- **It makes #11's suppression question concrete rather than hypothetical.** "Should a non-empty
  `background_tasks` suppress a done-announcement?" — in this repo the *normal* working turn ends with
  background work registered. Whatever #11 decides, it decides for the common case.

### What one sample cannot do

**This is a single capture, from one session, on one build, with a subagent running.** It can prove a
field was present and what it held. **It cannot prove a field is always absent.** `stop_reason` and
`model` are absent *here*, consistent with the compiled schema — and one turn reaches no further than
that. Likewise:

- `last_assistant_message` is `optional()` in the schema, and @ 25308665 shows how it goes missing:
  `f = p ? Cs(p.message.content, "\n").trim() || undefined : undefined` — the text blocks of the last
  assistant message joined by newline, **collapsing to absent when that string is empty**. A turn
  whose last assistant message is tool-use-only, or empty, delivers no text. One populated
  observation does not retire that path: a speech hook must still treat the field as
  absent-by-default and exit 0 quietly. **[inferred]** from the minified expression.
- **Still unchecked:** whether `Stop` fires on user interrupt (Ctrl-C / Esc); the separate
  **`StopFailure`** event, whose compiled shape is
  `{hook_event_name, error, error_details?, last_assistant_message?}` over the same base
  (**[bin]** @ 32881159) and which was not exercised; and the blocked-turn path — nothing blocked
  during the probe, so `stop_hook_active: true` has still never been seen, and neither has a second
  fire with newer text. The table in
  [that section](#stop_hook_active-is-not-a-duplicate-detector) is read from the code, not from the
  wire.

### The probe as it was run

**Spent and torn down.** Recorded so the claims above are reproducible — not as work outstanding.
The hook went into `~/.claude/settings.json` with Francis' say-so, ran for one turn, and was removed
in the same sitting along with `~/.local/share/claudish-probe/`.

```bash
mkdir -p ~/.local/share/claudish-probe
cat > ~/.local/share/claudish-probe/stop-probe.sh <<'EOF'
#!/usr/bin/env bash
# THROWAWAY. Dumps one Stop payload and exits 0. Delete after reading.
# Exit 0 unconditionally: on Stop, exit code 2 blocks the turn (other non-zero
# statuses only warn — see "Only exit code 2 blocks" above).
d=~/.local/share/claudish-probe
mkdir -p "$d" 2>/dev/null
cat > "$d/stop-$(date +%s%N).json" 2>/dev/null
exit 0
EOF
chmod +x ~/.local/share/claudish-probe/stop-probe.sh
```

Then, in `~/.claude/settings.json`, this went into the `hooks` object — and came back out again
afterwards:

```json
"Stop": [
  {
    "hooks": [
      { "type": "command", "command": "/Users/francis.behnen/.local/share/claudish-probe/stop-probe.sh", "timeout": 5 }
    ]
  }
]
```

One turn was ended, the capture read, and the probe torn out:

```bash
ls -t ~/.local/share/claudish-probe/stop-*.json | head -1 | xargs jq 'keys'
ls -t ~/.local/share/claudish-probe/stop-*.json | head -1 | xargs jq '{stop_hook_active, has_last: (has("last_assistant_message")), has_stop_reason: (has("stop_reason")), has_session_crons: (has("session_crons")), agent_id, background_tasks}'
# then remove the "Stop" block from ~/.claude/settings.json and:
rm -rf ~/.local/share/claudish-probe
```

What it settled, all in the one turn: `stop_reason` **is** absent on 2.1.245 and so is `model`;
`session_crons` **is** present; `last_assistant_message` **does** arrive populated, with raw markdown
in it; and the complete key list is the eleven fields above, against which the schema reading checks
out exactly. [Findings above.](#what-was-observed)

**A subagent was deliberately delegated while the probe was live**, which is what turned correction 2
from a ternary reading into an observation: the probe stayed silent through the subagent's completion
and fired once, as `Stop`, at the end of the turn.

Two operational notes, kept because they would apply again:

- A global `Stop` hook fires on **every** turn in **every** project until removed. It writes one small
  file per turn under `~/.local/share/claudish-probe/`. It was removed in the same sitting.
- `"timeout": 5` was deliberate: a probe that hangs should not hold a turn for the 600 s default.

---

## DECISION (2026-08-25)

**#10 is settled and can be closed.** Not by answering the question it asked — that question has no
answer — but by establishing that the variable it named was the wrong one and that the right one is
available.

1. **`CLAUDISH_SPEAK_MIN_CHARS` is not the gate.** No value is set, and the knob may not need to
   exist. The audition's sweep tables stand as measurement and are not the rule.
2. **The rule is turn finality**, and it is read from `Stop.last_assistant_message` — a field whose
   stated purpose is to spare hooks the transcript race.
3. **Defer-and-cancel is withdrawn.** It was a workaround for a signal that turned out to be
   available.
4. **`Stop` only. Never `SubagentStop`.** Subagent silence is free.
5. **Exit 0 on every path** — but not for the reason an earlier revision gave. **Only exit code 2
   blocks** (**[bin]** @ 9557061; anything else non-zero is, in the harness's own words, a
   "non-blocking status code" that merely warns). The real trap is narrow, and **narrower than this
   document originally said**: `jq` exits 2 when it is handed a **bad option or a file it cannot read**
   — a malformed *filter* exits **3**, and unparseable JSON on stdin exits **5**, both measured and both
   non-blocking — see the correction under
   [what is the actual hazard](#so-what-is-the-actual-hazard). The other exit-2 route is a **bash syntax error in the hook
   script**. Either way a hook can hand the harness a genuine block and get re-fired **eight** times —
   **nine invocations in all**, not eight (**[obs]**;
   [Correction 3](#correction-3--the-block-cap-counts-tolerated-blocks-not-invocations)). An explicit
   `exit 0` makes the `jq` route unreachable; the syntax-error route needs `bash -n` before the file
   ships, because no runtime guard can run in a file the parser refuses to get past.
6. **Do not use `stop_hook_active` as an "already spoken" flag.** It means "a previous stop attempt
   was blocked", and Claude replies to the block *before* the re-fire — so the later payload usually
   carries the **newer** text, which is the one the user wants. Blanket silence on `true` would speak
   the rejected answer and suppress the real one. Dedupe on the text (the payload carries it) if
   dedupe is wanted; which policy, and whether any is needed, is #11's.
7. **Timeouts:** the **harness defaults** are 600 s for `Stop` / `SubagentStop` and 10 s for
   `MessageDisplay`. **There is no *harness* 60 s cap to compare against** — the 60 is this plugin's
   declared value at `hooks/hooks.json:9`, alongside 180 at `:21`. Those declared numbers are not
   evidence about a runtime ceiling in either direction; whether the harness imposes any absolute
   ceiling is **unestablished**. A speech hook on `Stop` declares its own value, and the real question
   for `Stop` is `async`, not the timeout.
8. **The payload is observed, not inferred.** One live capture on 2.1.245 carried exactly eleven
   fields and matched the compiled schema exactly; `last_assistant_message` held 1511 characters of
   raw markdown, so speech on `Stop` must go through the sanitiser; `stop_reason` and `model` — both
   listed by the published docs — were absent. The binary beat the docs, twice. **Single sample**: it
   proves presence, never permanent absence.

**What stays open, and belongs to [#11](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/11):**
whether the `Stop` hook runs `async`; whether a long *intermediate* message is ever worth speaking
(the listener's "maybe if there are way longer updates that would also make sense" — the only place a
length threshold could still live, as a secondary escape hatch); whether non-empty `background_tasks`
should suppress an announcement, which the observation shows is the *common* case in this repo and not
an edge; and what to do on a re-fire after another hook blocks — speak-first, speak-on-change, or
nothing.

**What no longer stays owed: the probe. It ran.** #10 does not close on two paper sources any more; it
closes on two paper sources plus one observation that agreed with the stricter of them, field for
field. The residual unobserved surface is named in
[what one sample cannot do](#what-one-sample-cannot-do) — the empty-message path, `StopFailure`, user
interrupt, and the blocked-turn re-fire — and none of it is load-bearing for #11's next step.
