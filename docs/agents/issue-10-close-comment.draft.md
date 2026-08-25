# POSTED — historical record, not a draft, do not re-post

**This is the comment that went out on
[#10](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/10), kept verbatim.** Posted
2026-08-25 as
[`issuecomment-5409452853`](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/10#issuecomment-5409452853);
#10 was **closed** the same minute. Nothing here is outstanding, and the file is not a template — it
is the record of what was published.

The former "post with `gh issue comment … --body-file`" recipe has been **removed rather than
fixed**: it would have published this header along with the body, and the work it described is done.
A future draft that wants a copy-pasteable command should extract the body itself
(`sed '1,/^---$/d' FILE | gh issue comment N -R … --body-file -`) rather than pointing `--body-file`
at a file that has a header in it.

Repo convention (`docs/agents/issue-tracker.md`) for a wayfinder child ticket is comment → close →
append a context pointer to the map's Decisions-so-far. The first two are done. **The map pointer is
not drafted here** and was not written by this agent — a single writer owns #1's body.

## Errata: the body below is superseded in three places

The body is preserved **as posted, errors included.** A record of a published comment that has been
quietly corrected is no longer a record, so the corrections live here instead. The live source of
truth is [`turn-finality-and-the-stop-hook.md`](../decisions/turn-finality-and-the-stop-hook.md),
which now says:

1. **Only exit code 2 blocks.** The body's *"exit 2 does not mean 'hook failed' — it means 'block the
   turn'"* is correct; the sentence after it, that a hook which *"leaks a non-zero exit"* holds the
   turn open, is not. Every other non-zero status is classed `"other"` and is, in the harness's own
   warning string, a *"non-blocking status code"*: it renders one `Stop hook error:` warning and the
   turn ends normally. The narrow real trap is `jq`, which exits **2** on a malformed filter — so
   exit-0-on-every-path is still the rule, for that reason rather than the stated one.
2. **`stop_hook_active` is not a duplicate-detector.** The body's *"skip when `stop_hook_active` is
   true — because a `true` means this turn's text has already been spoken"* is wrong in the direction
   that costs the user their answer. `true` means only that a *previous stop attempt was blocked*, and
   Claude replies to the block **before** the re-fire, so the later payload usually carries the
   **newer** text. Blanket silence would speak the rejected answer and suppress the real one.
   Deduplication, if wanted, has to compare the text — the payload carries it.
3. **The 180 does not settle the ceiling question.** The body's *"the same file declares 180 at `:21`,
   which settles it"* overclaims: a value the config schema accepts proves only that the schema
   accepts it, never that the runtime does not clamp at execution time. There is no *harness* 60 s cap
   to argue against — the 60 is this repo's own declared value at `hooks/hooks.json:9` — and whether
   any absolute ceiling exists stays **unestablished**, which this repo's declared numbers cannot
   settle either way.

**The body's "honest gap" section is also out of date, in the plugin's favour.** *"No live `Stop`
payload has been captured"* was true when posted and no longer is. The probe ran on 2.1.245 and was
torn down: the payload carries exactly **eleven** fields, matching the compiled schema field for
field; `last_assistant_message` arrived populated with **1511 characters of raw markdown** (29
markdown markers), which measures the sanitiser handoff rather than assuming it; `stop_reason` **and**
`model` — both listed by the published docs — are **absent**, so the body's claim that the docs
describe a different build held on two counts; and a subagent still running as the turn ended produced
**no second fire**, confirming the `Stop`-not-`SubagentStop` correction by observation instead of by
ternary. It is one sample: it proves presence, never permanent absence.

---

<!-- Everything below this line is the comment text exactly as posted on 2026-08-25.
     Do not edit it to reflect later findings — record those in the Errata above. -->

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
