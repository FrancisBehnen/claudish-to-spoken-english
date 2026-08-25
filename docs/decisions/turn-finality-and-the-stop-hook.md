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
listening. It also contains no observation: **nobody has yet seen a live `Stop` payload on this
machine.** Every field named below comes from the published schema plus the schema as it is compiled
into the shipped binary — two independent sources that agree, but neither of them is the thing
itself. [The gap is stated in full below](#what-has-not-been-observed), and
[the one-shot probe that would close it](#the-probe-that-would-close-the-gap) is written out but
deliberately not installed.

No LLM was called. No hook was touched. `rewrite.sh`, `rewrite-md.sh`, `providers.sh` and `hooks/`
are unmodified.

---

## How each fact below was established

Three sources, named per claim so the weak ones stay visible.

| tag | source | what it can and cannot prove |
| --- | --- | --- |
| **[docs]** | <https://code.claude.com/docs/en/hooks.md>, fetched 2026-08-25 | states intent; can lag or lead the installed build |
| **[bin]** | `/Users/francis.behnen/.local/share/claude/versions/2.1.245` (Mach-O arm64, 376 MB), read via `strings -n 6` | proves what **this** build contains — the compiled Zod schema and the dispatch code |
| **[inferred]** | reading the minified control flow | a reading of code, not a run of it |

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

`Stop` fires once, when the turn ends. One fire per turn, carrying the text of the message that ended
it. That *is* "final message" in the listener's sense, with no lookahead and no window.

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

So: **the default block cap is 8** consecutive blocks, after which the runtime overrides the hook and
ends the turn with a warning. Env override `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`; `0` disables the cap.

**The hazard for this plugin is small but it is not zero.** A speech hook has no reason to block —
it reads `last_assistant_message`, hands it to Kokoro, and exits 0. It never sets
`stop_hook_active`, so it never sees it `true`. The trap is the *fail-open* discipline the rest of
this plugin is built on: `rewrite.sh` exits 0 on every error path precisely so a display hook can
never swallow content (`rewrite.sh:23-24`). **On `Stop`, exit code 2 does not mean "hook failed", it
means "block the turn".** A speech hook that leaks a non-zero exit — a `set -e` under an unset var,
a `jq` parse failure, a Kokoro import error — does not merely fail to speak. It holds the turn open,
gets re-fired up to 8 times, and speaks the same message up to 8 times before the runtime forces the
turn to end. That is the loop to design against.

Two rules follow, and they are cheap:

1. **Exit 0 on every path**, as `rewrite.sh` already does — but on `Stop` the reason is different and
   stronger, so it needs its own comment where the exit lives, not a reference to the display hook's.
2. **Read `stop_hook_active` and stay silent when it is `true`.** Not to avoid blocking — the hook
   never blocks — but because a `true` means *this turn's final message has already been spoken*.
   Without the check, any other Stop hook the user installs that blocks (a lint gate, a test gate)
   makes this plugin repeat itself once per block, up to 8 times.

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
  `agent_id`-absent check is available if the design ever wants one; on `Stop` it should be redundant.

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

**There is no 60 s harness cap, and nothing in this document should be read as contrasting a default
against one.** The 60 is this plugin's own declared value: `hooks/hooks.json:9` sets `"timeout": 60`
on `MessageDisplay` (also recorded in `README.md:457`), and `CLAUDISH_TIMEOUT` (default 45) is
deliberately kept under it. The same file declares **180** at `hooks/hooks.json:21` for `PostToolUse`,
which on its own disproves any absolute 60 s ceiling — and `CLAUDISH_MD_TIMEOUT`'s 150 s default would
have been dead on arrival if one existed.

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

## What has not been observed

**Stated plainly, because everything above is inference from two paper sources.**

- **No live `Stop` payload has been captured.** Not one. Every field name, type and optionality above
  is the published schema plus the same schema compiled into the binary. Those are two sources, and
  they agree, and they are still both descriptions of the payload rather than the payload.
- **The two sources do not fully agree, which is the reason this caveat is not a formality.**
  **[docs]** lists `stop_reason` (`"end_turn" | "max_tokens"`) on both `Stop` and `SubagentStop`.
  **2.1.245 does not have it**: the compiled `Stop` schema at @ 32880490 is
  `hook_event_name` + `stop_hook_active` + `last_assistant_message` + `background_tasks` +
  `session_crons` over the common base, with no `stop_reason`, and the dispatcher at @ 25308665 does
  not construct one. Every `stop_reason` in the binary is an API-message or SDK-result field, not a
  hook input. Conversely **`session_crons` is in the binary and absent from the docs.** So the docs
  are describing a build that is not this one, in both directions. A design that reads
  `stop_reason` on 2.1.245 would read `null`.
- **`last_assistant_message` is optional, and the code says how it goes missing.** @ 25308665 computes
  it as `f = p ? Cs(p.message.content, "\n").trim() || undefined : undefined`, i.e. the text blocks of
  the last assistant message joined by newline, **collapsing to absent when that string is empty**. A
  turn whose last assistant message is tool-use-only, or empty, delivers no text. A speech hook must
  treat the field as absent-by-default and exit 0 quietly. **[inferred]** from the minified
  expression.
- **Not checked at all:** whether `Stop` fires on user interrupt (Ctrl-C / Esc); what fires when the
  turn ends in an error — there is a separate **`StopFailure`** event carrying `error`,
  `error_details` and its own `last_assistant_message` (**[bin]** @ 32880490 region), which has not
  been looked into; and whether `background_tasks` / `session_crons` being non-empty should suppress
  a "done" announcement. That last one looks like a real design question — the binary describes
  `background_tasks` as there to "let hooks distinguish 'session is done' from 'session is paused
  waiting for background work to wake it'" — and it is #11's, not this document's.
- **Nothing here was run.** No hook was installed, no settings file was touched, no turn was ended
  under observation.

### The probe that would close the gap

One throwaway `Stop` hook, one turn, and the real field list is on disk. **Not installed** — it
edits `~/.claude/settings.json`, which is the user's live config, and that needs Francis' say-so.

```bash
mkdir -p ~/.local/share/claudish-probe
cat > ~/.local/share/claudish-probe/stop-probe.sh <<'EOF'
#!/usr/bin/env bash
# THROWAWAY. Dumps one Stop payload and exits 0. Delete after reading.
# Exit 0 unconditionally: on Stop, a non-zero exit BLOCKS the turn.
d=~/.local/share/claudish-probe
mkdir -p "$d" 2>/dev/null
cat > "$d/stop-$(date +%s%N).json" 2>/dev/null
exit 0
EOF
chmod +x ~/.local/share/claudish-probe/stop-probe.sh
```

Then, in `~/.claude/settings.json`, add to the `hooks` object:

```json
"Stop": [
  {
    "hooks": [
      { "type": "command", "command": "/Users/francis.behnen/.local/share/claudish-probe/stop-probe.sh", "timeout": 5 }
    ]
  }
]
```

End one turn, then read it and tear the probe out:

```bash
ls -t ~/.local/share/claudish-probe/stop-*.json | head -1 | xargs jq 'keys'
ls -t ~/.local/share/claudish-probe/stop-*.json | head -1 | xargs jq '{stop_hook_active, has_last: (has("last_assistant_message")), has_stop_reason: (has("stop_reason")), has_session_crons: (has("session_crons")), agent_id, background_tasks}'
# then remove the "Stop" block from ~/.claude/settings.json and:
rm -rf ~/.local/share/claudish-probe
```

What it settles in one turn: whether `stop_reason` is really absent on 2.1.245; whether
`session_crons` is really present; whether `last_assistant_message` arrives populated; and the
complete key list, against which everything above becomes observed rather than inferred.

**Delegating one subagent while the probe is live would answer correction 2 empirically too** — a
`Stop`-only probe that stays silent through a subagent's completion and fires once at the end of the
turn is the direct observation. Worth doing in the same pass.

Two things to be aware of before installing it, neither a blocker:

- A global `Stop` hook fires on **every** turn in **every** project until removed. It writes one
  small file per turn under `~/.local/share/claudish-probe/`. Remove it in the same sitting.
- `"timeout": 5` is deliberate: a probe that hangs should not hold a turn for the 600 s default.

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
5. **Exit 0 on every path, and skip when `stop_hook_active` is true** — on `Stop`, a non-zero exit
   blocks the turn and gets the hook re-fired up to 8 times.
6. **Timeouts:** the **harness defaults** are 600 s for `Stop` / `SubagentStop` and 10 s for
   `MessageDisplay`. **There is no 60 s cap** — the 60 is this plugin's declared value at
   `hooks/hooks.json:9`, alongside 180 at `:21`. A speech hook on `Stop` declares its own. Whether
   the harness has any absolute ceiling is **unestablished**, and the real question for `Stop` is
   `async`, not the timeout.

**What stays open, and belongs to [#11](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/11):**
whether the `Stop` hook runs `async`; whether a long *intermediate* message is ever worth speaking
(the listener's "maybe if there are way longer updates that would also make sense" — the only place a
length threshold could still live, as a secondary escape hatch); and whether non-empty
`background_tasks` should suppress an announcement.

**What stays owed regardless of #11: the probe.** Closing #10 on two paper sources is defensible
because they are independent and they agree on the load-bearing field. It is not the same as having
seen it, and the `stop_reason` disagreement is proof that the docs and this build have drifted. One
turn closes that.
