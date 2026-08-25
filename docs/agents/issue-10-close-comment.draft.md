# DRAFT — not posted

Body for a comment on
[#10](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/10). **Nothing below has
been posted and #10 has not been closed** — both are the orchestrator's to do.

Post with:

```bash
R=FrancisBehnen/claudish-to-spoken-english
gh issue comment 10 -R $R --body-file docs/agents/issue-10-close-comment.draft.md   # strip this header first
gh issue close 10 -R $R
```

The `--body-file` above would include this header, so either cut everything above the rule or paste
the body by hand. **Recommendation: yes, close #10** — reasoning in the last section of the body.

Note the repo convention (`docs/agents/issue-tracker.md`): resolving a wayfinder child ticket is
comment → close → append a context pointer to the map's Decisions-so-far. **The map pointer is not
drafted here** — a single writer owns #1's body and this agent was told not to touch it.

---

## `Stop` settles this: turn finality is directly observable

The premise is refuted and the replacement is available. Written up in
[`turn-finality-and-the-stop-hook.md`](https://github.com/FrancisBehnen/claudish-to-spoken-english/blob/task/stop-hook-finality/docs/decisions/turn-finality-and-the-stop-hook.md)
on branch `task/stop-hook-finality`, not merged.

The previous comment established that the listener was judging **status update vs final message**, not
length, and left one blocking question: can the plugin tell? **It can, from one field.**

```
Stop.last_assistant_message   string, optional
```

> "The assistant's final message text from this turn, as a single string. Use this instead of reading
> the transcript file, which is written asynchronously and may lag"

The `Stop` event fires **once, when the turn ends**, carrying the text of the message that ended it.
That is "final message" in exactly the sense the audition note meant, with no lookahead and no
window. `MessageDisplay.final` was never going to work and the shipped schema says why: *"True on the
message's last flush. **Exactly one flush per message** has it."* — message-level, not turn-level, as
`rewrite.sh:9` correctly describes and `rewrite.sh:110` reads.

**Defer-and-cancel is withdrawn.** It existed only because finality looked unobservable. It costs a
timer, a cancel path, a window constant nobody could justify, and a race — for nothing.

### Three things the design has to carry, and two corrections to earlier research

**1. `Stop` only — never `SubagentStop`.** Earlier research claimed `Stop` fires on subagent
completion. It does not. One ternary decides it, and the events are mutually exclusive:

```js
let l = o ? "SubagentStop" : "Stop";     // o === the agent id
if (!c && !Rg(l, u, d)) return;          // config gate uses the RESOLVED name
```

The caller passes `e.agentId`; present ⇒ `SubagentStop`, absent ⇒ `Stop`. A `Stop` entry in
`hooks/hooks.json` is never asked for on the subagent path. (The docs' "converts a `Stop` hook here
to `SubagentStop`" applies to hooks declared in a **subagent's own frontmatter**, not to plugin
`hooks.json`.) **This repo runs many subagents and they will be silent for free** — not by a filter
we write, but because the event never fires. Better than we'd have got by asking.

**2. `stop_hook_active` exists, and exit codes mean something different on `Stop`.** Earlier research
said no such re-entrancy flag was documented. It is documented and it is required on the payload:
`true` when a `Stop` hook has blocked the turn from ending, so the hook can tell it is inside its own
loop. The runtime caps this at **8 consecutive blocks** (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP ?? 8`) then
overrides and ends the turn.

The hazard is our own fail-open discipline. `rewrite.sh` exits 0 on every path so a display hook can
never swallow content. **On `Stop`, exit 2 does not mean "hook failed" — it means "block the turn".**
A speech hook that leaks a non-zero exit doesn't just fail to speak: it holds the turn open and gets
re-fired up to 8 times, speaking the same message up to 8 times. So: exit 0 on every path (with its
own comment, because the *reason* differs from the display hook's), and skip when
`stop_hook_active` is true — because a `true` means this turn's text has already been spoken, and
without the check any other blocking Stop hook the user installs makes us repeat ourselves.

**3. Timeouts, since several numbers were circulating.** The **harness defaults** for a `command`
hook are **600 s** on `Stop` / `SubagentStop` and **10 s** on `MessageDisplay`. A declared `timeout`
(in seconds) replaces the default. **There is no 60 s cap**: the 60 is our own declared value at
`hooks/hooks.json:9`, and the same file declares 180 at `:21`, which settles it. Whether the harness
imposes any absolute ceiling is **unestablished** — no clamp appears at the call site or on the
schema, but that is not proof of absence. A speech hook on `Stop` would declare its own value rather
than inherit 600 s, so the harness default is not a design constraint here; `async` is the real
question, and that's #11's.

### The honest gap

**No live `Stop` payload has been captured.** Every field name above is the published schema plus the
same schema compiled into the shipped 2.1.245 binary — two independent sources that agree on the
load-bearing field, but both descriptions of the payload rather than the payload.

They do not agree on everything, which is why this matters: **the docs list `stop_reason` and
2.1.245 does not have it** (the compiled `Stop` schema has no such field and the dispatcher never
constructs one), while **`session_crons` is in the binary and absent from the docs**. The docs are
describing a build that isn't this one, in both directions. Also unchecked: whether `Stop` fires on
user interrupt, and what the separate **`StopFailure`** event does.

A ready-to-run one-turn probe — a throwaway `Stop` hook that dumps its stdin to a file — is written
out in the doc, **not installed**, because it edits `~/.claude/settings.json`. Running it with one
subagent delegated in flight would confirm correction 2 empirically in the same pass.

### Recommendation: close this

**#10 asked "what is the minimum length worth speaking?" and the answer is that the question has no
answer.** The audition refuted the premise, this establishes the replacement, and both are recorded.
Nothing further is decidable *under this ticket's framing* — there is no number to set, and
`CLAUDISH_SPEAK_MIN_CHARS` may not need to exist.

What's left is not #10's:

- **#11** — whether the `Stop` hook runs `async` so speech doesn't hold the turn; whether non-empty
  `background_tasks` should suppress an announcement; and whether a long *intermediate* message is
  ever worth speaking. That last one is the only place a length threshold could still live — the
  note's "maybe if there are way longer updates that would also make sense" — and it belongs to
  whoever specifies the trigger, as a secondary escape hatch rather than the primary gate.
- **The probe** — one turn, to make the field list observed rather than inferred. Worth doing before
  implementation regardless of which ticket owns it.

Closing #10 as **resolved by refutation**: the question was answered by being replaced, and the
replacement is specified.
