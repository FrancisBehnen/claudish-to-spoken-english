# The speech trigger moves to `Stop`: what #10's outcome forces on the spec

**DRAFT — input to [#11](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/11), not
the spec and not a lock.** Part of the
[Kokoro speech map (#1)](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/1).
Written 2026-08-25 against Claude Code **2.1.245**.

**#11 cannot be locked today, and this document does not try.** It still waits on
[#13](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/13)'s listening verdicts —
being recorded as this is written — and on a `Stop` payload nobody has yet seen. So this does exactly
one thing: it records the changes [#10](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/10)'s
closure **forces** on the spec, each marked settled or open, so whoever writes the lock has a
checklist instead of a re-derivation. Where a question is genuinely undecided it is **posed, not
answered** — an invented answer here would be worse than a gap, because the lock would inherit it
silently.

Nothing here was measured, heard, or run. No LLM was called, no audio was synthesised, no hook was
touched. `rewrite.sh`, `rewrite-md.sh`, `providers.sh` and `hooks/` are unmodified; `bench/` and
`corpus/` are untouched (they belong to open PRs #15 and #18).

---

## Where each fact below comes from

| tag | source | what it can and cannot prove |
| --- | --- | --- |
| **[#10]** | [`turn-finality-and-the-stop-hook.md`](turn-finality-and-the-stop-hook.md) (lands on `main` via **PR #17**) | its own `[docs]` / `[bin]` / `[inferred]` tagging on 2.1.245. **Inherited here, not re-verified** — no `strings` sweep was re-run for this draft. |
| **[repo]** | the working tree, read directly | what this plugin actually does today; line numbers are citable |
| **[heard]** | [`min-length-audition.md`](min-length-audition.md), [`sanitizer-audition.md`](sanitizer-audition.md), [`voice-and-pipelining.md`](voice-and-pipelining.md) | closed listening decisions and stopwatch readings |

Every item below carries one of three markers:

- **SETTLED** — #10 decided it; the lock copies it.
- **OPEN** — #10 exposed it and did not decide it; the lock must decide it, and this draft says what
  the decision hangs on.
- **UNOBSERVED** — asserted only from schema and code reading. Not false, not seen.

---

## 1. SETTLED — the architecture is **two hooks**, not one

The spec was written on the assumption that speech is fired from inside `rewrite.sh`, off the
`MessageDisplay` path, just before `emit`. **That is no longer the shape.** #10 moved the trigger to
`Stop`, and `Stop` is a different event with a different process, a different payload and a different
exit-code contract. The plugin now has two hook entries that must be specified separately.

| | `MessageDisplay` → `rewrite.sh` | `Stop` → the speech hook (new) |
| --- | --- | --- |
| **fires** | once **per streamed chunk** of **every** assistant message (`rewrite.sh:5-10`) | **once, when the turn ends** |
| **owns** | the plain-English rewrite that appears **on screen** | **speech, and nothing else** |
| **reads** | `.message_id`, `.index`, `.final`, `.delta`; buffers deltas to disk and calls the LLM on the final chunk | `last_assistant_message` |
| **must not own** | speech | anything on screen |
| **declared timeout** | **60 s** (`hooks/hooks.json:9`) | its own, still to be chosen |
| **harness default** | 10 s | 600 s |
| **fires for subagents** | yes (any assistant message) | **no** — see §3 |
| **non-zero exit means** | "hook failed"; content passes through | **"block the turn"** — see §2 |

**Why the split is forced and not a preference.** `MessageDisplay.final` is *message*-level and the
shipped schema says so: "True on the message's last flush. Exactly one flush per message has it."
`rewrite.sh:9` describes it correctly as "true on the last chunk" — and that is the wrong scope for
this feature. A turn that emits three narration messages and two tool calls sets `final: true` three
times. There is no lookahead at display time: the tool call that would mark a message intermediate has
not happened yet. `Stop` fires once per turn and carries the text of the message that ended it. **[#10]**

**Consequence for the display hook: none.** `rewrite.sh` keeps its buffer-to-final logic verbatim.
Nothing about the rewrite changes. What changes is that speech is no longer *its* job, and the spec
should say that as a prohibition — a future reader looking at `rewrite.sh:emit` will otherwise see the
obvious place to put a `say` call.

**Consequence for the speech hook: do not read `transcript_path` for turn-final text.** The docs give
the reason — the transcript is written asynchronously and can lag the in-memory conversation, so a
hook that parses it races the writer; `last_assistant_message` exists to spare hooks exactly that.
`rewrite.sh` already reads `transcript_path` (for the user's question, as rewrite context) and that
use stays fine: it wants an *older* message. **[#10]**

### 1a. OPEN, and created by the split — the speech hook cannot see the rewrite

**This is the largest new question in this draft and it does not appear in #11's body, because before
#10 the two things lived in one process.**

`Stop.last_assistant_message` is **Claude's own raw markdown**. The plain-English rewrite exists only
inside `rewrite.sh`, in a different process, on a different event. A `Stop` hook that speaks its own
payload speaks **raw Claudish** — which #1's out-of-scope list bans outright: *"Speaking raw,
un-rewritten Claudish … speech only ever carries a successful plain-English rewrite."*

So the spec must specify a **handoff**, and there are at least three shapes:

1. **`rewrite.sh` publishes, `Stop` consumes.** The display hook writes its finished rewrite into the
   existing `$BUF_ROOT/<session>/` scratch layout; the `Stop` hook reads the most recent one and
   speaks it, ignoring its own payload text. Open sub-questions: the key (message id? sequence?), how
   the `Stop` hook knows the file corresponds to *this* turn's last message rather than a stale one,
   and what it does when the file is absent.
2. **`Stop` matches its payload against the published rewrite** and speaks the rewrite only on a
   match. Safer against staleness, costs a comparison against text the LLM deliberately changed.
3. **`Stop` re-rewrites.** Rejected on sight: a second LLM call per turn, on the turn-ending path,
   for text that was already rewritten. #4 already killed the parallel-LLM option for a weaker
   version of this reason.

**And there is a sharp edge underneath it.** `rewrite.sh:147` skips the LLM entirely below
`CLAUDISH_MIN_CHARS` (default 200), so **short messages are never rewritten and there is no rewrite to
hand over.** #10's audition was built entirely out of *raw* sub-200 messages — all sixteen items —
precisely because that is what speaking them would mean. So the lock has to choose:

- **stay silent below `CLAUDISH_MIN_CHARS`**, which is consistent with #1's out-of-scope ban and
  throws away the case #10 spent its whole audition on; or
- **relax the ban for short raw messages**, which needs #1's out-of-scope list edited (a single
  writer owns it — proposed text in §9), and which drags the sanitizer onto un-simplified Claude
  output; or
- **rewrite short messages for speech only**, which is a new LLM call on a path that currently has
  none.

**Not decided here.** It needs the listener, not an agent — the same kind of judgement #10 turned out
to be.

---

## 2. SETTLED — on `Stop`, a non-zero exit is a **control signal**, and fail-open becomes an invariant
for a new reason

**On `Stop`, exit code 2 does not mean "the hook failed". It means "block the turn".** The runtime
counts consecutive blocks, caps them at `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP ?? 8`, and then overrides the
hook and ends the turn with a warning. `stop_hook_active` is `true` on any invocation that follows a
block, so a hook can tell it is inside its own loop. **[#10]**

**For a speech hook the failure mode is loud, literally.** A leaked non-zero exit — `set -e` under an
unset variable, a `jq` parse error, a missing player, a Kokoro import failure — does not merely fail to
speak. It **holds the turn open and gets the hook re-fired up to 8 times, speaking the same message up
to 8 times**, before the runtime forces the turn to end.

**The plugin is already correct here, and that is worth stating carefully, because it is correct by
accident.** `rewrite.sh` exits 0 on every path — `pass_through() { dbg "pass_through"; exit 0; }` at
`rewrite.sh:77`, plus `exit 0` at `:91` and `:97`, and **no `set -e` anywhere in the file** (**[repo]**,
grep). The stated reason is the display contract, `rewrite.sh:22-25`:

> "FAIL-OPEN CONTRACT: on ANY problem (disabled, no jq, parse error, LLM down, timeout, empty rewrite)
> we emit nothing and exit 0, which leaves Claude's ORIGINAL text on screen. A display hook must never
> be able to swallow the assistant's answer."

**On `Stop` there is no text on screen to swallow.** The reason the discipline is required is
different and, if anything, stronger: the exit status is read by the runtime's turn loop as a
decision about whether the user gets their prompt back. Same rule, different justification. The spec
should therefore promote it from a display-hook contract to a **stated invariant of the plugin**, and
the wording has to generalise — the current phrasing is about swallowing the answer and does not cover
this case at all.

**Proposed invariant text for the spec:**

> **INVARIANT (both hooks, and the `Stop` hook especially).** Every hook this plugin ships exits **0
> on every path, including every error path**. No `set -e`, no unguarded pipeline, no path on which an
> unset variable, a missing binary or a `jq` parse failure can reach the exit status. On
> `MessageDisplay` this is what keeps a display hook from swallowing the assistant's answer
> (`rewrite.sh:22-25`). On `Stop` it is a different and stronger requirement: **a non-zero exit is not
> a failure report, it is a request to block the turn**, and a leaked one holds the user's prompt
> hostage and repeats the same utterance up to `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` (default 8) times.
> The `Stop` hook's exit must carry its own comment stating **this** reason; a cross-reference to the
> display hook's comment would document the wrong hazard.

**Second rule, cheap and separate: read `stop_hook_active` and stay silent when it is `true`.** Not to
avoid blocking — this hook never blocks — but because `true` means *this turn's final message has
already been spoken*. Without the check, any other blocking `Stop` hook the user installs (a lint
gate, a test gate) makes this plugin repeat itself once per block. **[#10]**

**OPEN, and it interacts with §4:** if the hook is declared `async`, it is not established that the
runtime reads its exit status at all — see §4. The invariant must be specified so that it holds
either way, rather than resting on `async` making the hazard moot.

---

## 3. SETTLED — `Stop` does not fire for subagents, so they are silent for free

`Stop` and `SubagentStop` are **mutually exclusive**, decided by a single ternary on the agent id
*before* the config gate, and the gate is consulted with the **resolved** event name. A `Stop` entry in
`hooks/hooks.json` is therefore never asked for on the subagent path. The docs' "converts a `Stop`
hook here to `SubagentStop`" applies to hooks declared in **a subagent's own frontmatter**, not to a
plugin's `hooks.json`. **[#10]**

**This matters for this repo specifically.** The work here runs many subagents. A speech hook that
announced every subagent's final message would talk continuously through exactly the work that was
delegated so nobody had to watch it. That outcome arrives **for free** — not from a filter this
plugin writes and maintains, but because the event never fires.

**Two things the spec must state as negative requirements**, because a later reader who sees no filter
will be tempted to add one:

- **Do not add a `SubagentStop` entry to `hooks/hooks.json`.** Ever, for this feature. It is the one
  edit that would turn the free silence into continuous chatter.
- **Do not write a subagent filter.** There is nothing to filter. An `agent_id`-absent check is
  available as belt-and-braces (`agent_id` is documented on the common base as "Absent for the main
  thread") and on `Stop` it should be redundant; if the spec wants it, it should say it is redundant
  and why it is there anyway.

One footnote so the claim is not overstated: a narrow bypass exists for the built-in `web-fetch`
subagent, where the *config gate* is skipped — but `hook_event_name` is still `SubagentStop` on that
path, so it is not a `Stop` leak. **[#10]**, tagged there as `[inferred]` from control flow.

---

## 4. OPEN, leaning **require** — `async: true`

**The question.** A blocking `Stop` hook holds the turn: the user's prompt does not come back until
the hook returns. `async: true` is the command-hook flag that removes that ("If true, hook runs in
background without blocking", **[#10]** from the compiled schema). Should the spec **require** it?

**The timeout is not the constraint, and it is worth killing that framing first.** The harness default
on `Stop` is **600 s**, and a declared `timeout` replaces the default rather than being clamped by it
(**[#10]**; whether any absolute ceiling exists is explicitly unestablished there). Nothing about
speech comes near 600 s. "Under the timeout" was never the question.

**The constraint is how long the prompt is held, and the honest number is not TTFA.**

| what is being waited for | measured | source |
| --- | --- | --- |
| first-sentence **TTFA** (time to *first audio*) | **0.39–1.22 s, median 0.85 s** (0.82 s on an independent re-measure), 12/12 real rewrites under 3 s | **[heard]** `voice-and-pipelining.md` |
| whole-message **audio duration** (time to *finish speaking*) | **16.5 s – 172.8 s** across the same 12 real rewrites | **[heard]** same table |

**That is the whole argument.** If the hook merely *starts* playback and returns, it holds the prompt
for about a second — small, but a real regression on a plugin whose central promise is that it never
makes you wait, and it is a cost paid on **every** turn. If the hook waits for playback to finish, it
holds the prompt for the **audio duration**, which reaches **~173 s** on real content. The second case
is not a trade-off, it is a defect; and it is the case a naive blocking implementation lands in by
default, because the obvious shape is "synthesise, play, exit".

**Recommendation for the lock: require non-blocking, and name which mechanism carries the guarantee.**
`async: true` and #1's already-committed **detachment** (speech fired detached, stdio closed,
disowned) are two different mechanisms for the same property. The risk is specifying both and
implementing neither, or assuming one covers the other. Suggested split:

- **Detachment is load-bearing.** It is in this plugin's own code, it is testable from here, and #1
  already commits to it as part of the inviolable fail-open contract.
- **`async: true` is the declared-config belt**, added because it is free and because it makes the
  intent visible in `hooks/hooks.json` to anyone reading the wiring.

**Why this stays OPEN rather than settled, and it is not pedantry:** three things about `async` are
**UNOBSERVED**, and one of them could change §2.

1. Whether an async hook's **exit status is read at all**. If it is not, the 8× repeat hazard cannot
   fire for an async hook. That would be good news — and it must not be assumed, because §2's
   invariant is cheap and the assumption is not.
2. Whether an async hook is subject to the **block cap** / `stop_hook_active` machinery at all.
3. Whether an async hook receives the **same payload**, in particular whether
   `last_assistant_message` is populated identically.

All three are one probe away, and none of them is answered by the `Stop` probe as currently written
(§8) — which is worth noting, because that probe is about to be run and will not cover this.

**One inherited loose end that lands on this table:** every TTFA number above was measured on
`af_heart`, and the chosen voice is `bf_emma`, whose duration ratio was never measured (#9's own
recorded loose end). The margin is wide, so this is a check rather than an expected reversal — but the
lock should not bank a TTFA figure measured on a rejected voice.

---

## 5. OPEN — `background_tasks` on `Stop`: what does "done" mean when the session is only paused?

**Posed, not answered.** The binary describes `background_tasks` as being there to "let hooks
distinguish 'session is done' from 'session is paused waiting for background work to wake it'"
(**[#10]**). For a feature whose entire purpose is a **done**-announcement to someone who is looking
away from the screen, that is precisely the distinction that decides whether the announcement is true.

At least three defensible answers, and the choice needs evidence none of us has:

1. **Speak regardless.** The assistant's turn is over; that is the event the listener asked to hear
   about, and background work is not the assistant talking.
2. **Stay silent when `background_tasks` is non-empty.** "Done" is a lie if a background task is going
   to wake the session and produce more output — and the listener who walked away is exactly the
   person that lie costs.
3. **Say something different.** A distinct utterance for "turn over, still waiting on background
   work". Note this is a **new category** for the plugin: text the plugin authored rather than a
   rewrite of Claude's, which nothing in #1 currently sanctions.

**What has to be known before choosing**, and none of it is:

- **What actually populates `background_tasks`** in this workflow — backgrounded `Bash` commands?
  subagents in flight? something else? The field's *existence* is established; its *contents* on this
  machine are not.
- **Whether `Stop` fires again** when the woken session finishes. If it does, answer 2 costs nothing
  (the announcement just arrives later). If it does not, answer 2 loses the announcement entirely,
  which is the worst outcome available.
- **`session_crons`**, which is in the binary and absent from the docs (**[#10]**), and has not been
  looked at at all. Plausibly the same family of question; possibly unrelated.

**Explicitly not decided here, and it should not be decided from the schema.** It needs one
observation of a real `Stop` with a background task in flight.

---

## 6. OPEN — the one surviving home for a length threshold, and it costs more than it looks

`CLAUDISH_SPEAK_MIN_CHARS` is **not** the primary gate. That is settled: no character threshold fits
the verdicts (best ~335 chars, **3 errors in 24**, and it scores that only by silencing three
*shorter* items the listener marked worth speaking), and duration fails too (`fct06` 14.78 s "not
worth" against `ack07` 10.50 s "worth"). **[heard]** `min-length-audition.md`.

The one place it could still live is the listener's own aside — *"maybe if there are way longer updates
that would also make sense"* — i.e. a **secondary escape hatch that lets a long *intermediate* message
speak**, on top of the always-speak-the-final-message rule.

**Two problems the lock has to weigh, and the first is structural rather than a matter of picking a
number.**

1. **On a `Stop`-only architecture there is no event that carries intermediate messages to speech.**
   `Stop` fires once, at the end. Intermediate messages are visible only on `MessageDisplay` — the hook
   #10 just took speech *off*. So this escape hatch does not add a threshold; it **puts speech back on
   the display hook for a subset of messages**, and brings back with it everything the move to `Stop`
   removed: chunk-level `final`, the defer-and-cancel ambiguity, and a synthesis call on the display
   critical path. That is a second trigger, not a knob.
2. **The evidence is one sentence.** No audition item tested a long intermediate message. The note is a
   listener's speculation about a shape they were not played.

**Proposal (OPEN, for the lock to accept or reject): specify it as deliberately absent.** Do not ship
`CLAUDISH_SPEAK_MIN_CHARS` at all — not present-and-zero, which reads as a supported knob nobody has
justified. Record the listener's note in the spec as the reason it may come back, and record that
returning it means adding a second trigger, so the cost is visible when someone proposes it. If the
listener wants it, the honest next step is an audition of long intermediate messages, not a number.

---

## 7. SETTLED — the standing constraints #10 does **not** disturb

Confirmed unaffected, with the one wording change #10 forces called out.

| constraint | status after #10 | note |
| --- | --- | --- |
| **Fail-open is inviolable** | **unaffected in force, strengthened in reason, and the wording must generalise** | §2. The current phrasing ("a display hook must never be able to swallow the assistant's answer") does not cover the `Stop` hazard at all — there is nothing on screen to swallow. Same rule, wider scope. |
| **Speech off by default** | **unaffected — but it now has to be enforced differently** | See below. |
| **macOS only** | **unaffected** | Nothing about `Stop` is platform-specific. `afplay` is unchanged; `espeak-ng` is still not a prerequisite; `sox` / `ffmpeg` still not needed. |
| **`kokoro-onnx` `IndexError` at 510 phonemes** | **unaffected** | A synthesis-layer constraint, downstream of whatever triggers speech. Terminal punctuation stays crash-preventing, the sanitizer still must never strip it, and `\n` must still be converted into terminal punctuation rather than preserved. One wrinkle below. |

**"Off by default" changes shape, and this is a real forced change.** Before #10, speech was code
*inside* `rewrite.sh`, so off-by-default cost nothing: the branch was not taken. After #10, the plugin
ships a **second hook entry**, and `hooks/hooks.json` is not conditional — a `Stop` block there fires
**on every turn, for every user of the plugin, whether or not they ever enable speech.** Therefore:

- the guarantee has to be enforced **inside** the speech hook: check `CLAUDISH_SPEAK` (and the runtime
  off-file) and `exit 0` immediately, before anything else, as the very first thing after `jq`; and
- the spec should **acknowledge the cost that remains**: one bash process spawned per turn for users
  who never turn speech on. It is small, but it is new, and it is not zero — and it is the kind of
  thing that is fair to state rather than discover.

**The 510-phoneme wrinkle, conditional on §1a.** If the raw-vs-rewrite handoff ever resolves toward
speaking `last_assistant_message` directly, the text distribution changes: raw Claude markdown instead
of a rewrite. #10's audition measured raw *short* messages at a largest batch of **265 phonemes against
510**, so short raw text is not a crash risk (**[heard]**). A **long** raw assistant message has never
had its batch sizes measured. Only relevant if §1a resolves that way; worth naming so it is not
discovered at implementation time.

---

## 8. What still blocks locking #11

**Two hard blockers, in order.**

1. **#13's listening verdicts.** #13 natively blocks #11. Two rules the #8 notes asked for were never
   auditioned: commas around flag names (generalising axis 1's winner) and pronounceable file
   extensions (`.json` → "dot json"). The audition for them is built on PR #18 and the verdicts are
   being recorded now. **Nothing in this draft depends on them**, and nothing in this draft unblocks
   them.
2. **The unobserved `Stop` payload.** Every field name in §§1–5 is the published schema plus the same
   schema compiled into the shipped 2.1.245 binary — two independent sources that agree on the
   load-bearing field, and **both of them descriptions of the payload rather than the payload**. That
   the caveat is not a formality is proved by where they *disagree*: the docs list `stop_reason` and
   2.1.245 does not have it; `session_crons` is in the binary and absent from the docs. The docs are
   describing a build that is not this one, in both directions. **[#10]**

   The probe written out in **[#10]** settles, in one turn: the complete key list; whether
   `stop_reason` is really absent; whether `session_crons` is really present; whether
   `last_assistant_message` arrives populated; and — with one subagent delegated in flight — that
   `Stop` stays silent for subagents and fires once at the end.

   **What that probe does *not* settle, and the lock needs**: the three `async` questions in §4;
   whether `Stop` fires on user interrupt (Ctrl-C / Esc); what `StopFailure` does; and what actually
   populates `background_tasks` (§5).

**Open inside #11's own scope, not created by #10, listed so the checklist is complete.** The
rewrite-handoff question (§1a) — the one genuinely new design question here. `bf_emma`'s duration ratio
against the `af_heart` TTFA figures (#9's recorded loose end). #5's ~4.9 s post-wake cold start, larger
than the entire warm first-sentence budget. And everything #11's body already lists: the detachment
contract, the speaker lock and PID file, preemption on a new prompt, the full `CLAUDISH_*` surface,
the failure paths, and the README.

---

## 9. Proposed text for #1 — **NOT applied**

A single writer owns #1's body, so nothing below has been written to it. Three edits are proposed; the
first is not optional, because the existing bullet now asserts the opposite of the truth.

### 9a. Replace the `#10` bullet in **Decisions so far**

The current bullet ends *"the real signal is not observable from the hook; **#10 stays OPEN**"*. Both
halves are now false. Proposed replacement (the existing measurement detail is worth keeping; this
replaces the bullet's **head** and its **closing** two sentences):

> - **#10 — CLOSED: there is no minimum length, and turn finality is directly observable from `Stop`**
>   (settled 2026-08-25). The premise was refuted before this — the listener was judging **status
>   update vs final message**, not length (no character threshold fits: best ~335 chars, 3 errors in
>   24, and only by silencing three *shorter* items marked worth speaking; duration fails too). That
>   left one factual question — *can the plugin tell?* — and the answer is **yes, from one field**:
>   `Stop` fires **once per turn** and carries `last_assistant_message`, the complete final assistant
>   text, in a field whose stated purpose is to spare hooks the transcript-lag race. **So the
>   architecture is now two hooks**: `MessageDisplay` keeps the on-screen rewrite, `Stop` owns speech.
>   **Defer-and-cancel is withdrawn** — it only ever existed because finality looked unobservable.
>   **`Stop` does not fire for subagents** (`SubagentStop` is a separate event, picked by a
>   mutually-exclusive ternary before the config gate), so this repo's many subagents are silent for
>   free, and a `SubagentStop` entry must never be added. **On `Stop` a non-zero exit means "block the
>   turn", not "hook failed"** — capped at `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP ?? 8` consecutive blocks
>   before the runtime overrides — so a leaked non-zero exit would hold the prompt open and speak the
>   same message up to 8 times; the plugin's existing exit-0-everywhere discipline is already correct,
>   for a different and stronger reason than it was adopted for. **`CLAUDISH_SPEAK_MIN_CHARS` is not
>   the gate and may not need to exist**, surviving only as a possible secondary escape hatch for long
>   *intermediate* messages — which would mean a second trigger, not a knob. **Owed regardless: no live
>   `Stop` payload has been observed** (docs and the 2.1.245 binary agree on `last_assistant_message`
>   but disagree on `stop_reason` and `session_crons`), and a one-turn probe is written out.
>   → [`docs/decisions/turn-finality-and-the-stop-hook.md`](https://github.com/FrancisBehnen/claudish-to-spoken-english/blob/main/docs/decisions/turn-finality-and-the-stop-hook.md),
>   [`docs/decisions/min-length-audition.md`](https://github.com/FrancisBehnen/claudish-to-spoken-english/blob/main/docs/decisions/min-length-audition.md)

### 9b. Add to **Standing constraints**

> - **SETTLED 2026-08-25: the speech trigger is a second hook, not a branch inside `rewrite.sh`.**
>   `MessageDisplay` → `rewrite.sh` owns the on-screen rewrite and **must not** fire speech;
>   `Stop` → the speech hook owns speech and **must not** touch the screen. `MessageDisplay.final` is
>   message-level and cannot express turn finality; `Stop.last_assistant_message` can. Consequences:
>   **never read `transcript_path` for turn-final text** (written asynchronously, races the writer);
>   **never add a `SubagentStop` entry** (subagent silence is free because the event never fires);
>   and **the `Stop` hook must be non-blocking** — the cost of blocking is not TTFA (median 0.85 s) but
>   whole-message **audio duration**, 16.5–172.8 s on real rewrites.
> - **The fail-open invariant now covers both hooks, and on `Stop` it means something stronger.**
>   Exit 0 on every path, no `set -e`, nothing that lets an unset variable or a `jq` failure reach the
>   exit status. On `MessageDisplay` this stops a display hook swallowing the answer
>   (`rewrite.sh:22-25`). On `Stop` a non-zero exit **blocks the turn** — up to
>   `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP ?? 8` re-fires, speaking the same message each time — so the
>   `Stop` hook's exit needs its own comment naming **this** hazard.
> - **"Off by default" now has to be enforced inside the speech hook.** `hooks/hooks.json` is not
>   conditional, so a `Stop` entry fires on every turn for every user of the plugin. The hook checks
>   `CLAUDISH_SPEAK` (and the runtime off-file) and exits 0 immediately. Residual cost, stated rather
>   than hidden: one process spawn per turn for users who never enable speech.

### 9c. Add to **Not yet specified**

> - **What the speech hook actually speaks.** `Stop.last_assistant_message` is Claude's **raw
>   markdown**; the plain-English rewrite lives in a different process on a different event, and
>   #1 bans speaking raw Claudish. So a handoff has to be specified (`rewrite.sh` publishes into
>   `$BUF_ROOT/<session>/`, `Stop` consumes), together with what happens below `CLAUDISH_MIN_CHARS`
>   where **no rewrite is ever produced** — which is the entire case #10's audition was built out of.
> - **Whether a non-empty `background_tasks` should suppress the announcement.** The binary describes
>   the field as distinguishing "session is done" from "session is paused waiting for background work
>   to wake it" — exactly the distinction that decides whether a done-announcement is true. Cannot be
>   chosen from the schema: it needs to be known what populates the field here, and whether `Stop`
>   fires again when the woken session ends.

---

## 10. Where this draft is weakest

Stated so a reviewer can attack the right parts.

- **Everything about `Stop` is inherited and unobserved.** §§1–5 rest on **[#10]**, which rests on the
  docs plus a `strings` read of the 2.1.245 binary. **No `strings` sweep was re-run for this draft**
  and no payload has been seen. The `stop_reason` / `session_crons` disagreement is direct evidence
  that at least one of those two sources is wrong about *something*.
- **`async` is the thinnest claim in the document and §4 leans on it.** Its semantics come from a
  single compiled-schema description quoted in **[#10]** ("If true, hook runs in background without
  blocking"). Whether an async hook's exit code is read, whether it is subject to the block cap, and
  whether its payload is identical are all **unknown**, and the probe now in flight does not test any
  of them.
- **§1a is an inference about this plugin, not about the harness, and it is the least reviewed thing
  here.** The claim that the `Stop` hook cannot see the rewrite follows from process separation and is
  hard to see around — but no one has yet tried to design the handoff, so its difficulty is asserted
  rather than demonstrated.
- **§6's recommendation rests on one sentence from one listener about a shape they were never
  played.** "Specify it as absent" is a judgement, not a finding.
- **The `bf_emma` duration ratio is still unmeasured**, so §4's TTFA table describes a voice that was
  rejected.
