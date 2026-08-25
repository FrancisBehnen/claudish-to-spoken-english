# The speech integration spec

**This is the lock for [#11](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/11)**
— the destination artifact of the [Kokoro speech map (#1)](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/1).
Written 2026-08-25 against Claude Code **2.1.245**. It supersedes
`speech-trigger-spec-update.draft.md`, which was the checklist this was written from.

**What this document is.** A specification an implementer can build from in one session without
re-deriving a decision. Every section is marked **LOCKED** (decided, with the evidence that decided
it) or **OPEN** (undecided, with what would close it). Nothing is marked LOCKED on the strength of a
schema reading alone.

**What this document is not.** It is not an implementation and it does not contain one. No hook was
written or modified; `rewrite.sh`, `rewrite-md.sh`, `providers.sh` and `hooks/` are unchanged.
`bench/` and `corpus/` are unchanged (open PRs own them). No audio was synthesised, no benchmark was
run, no LLM was called. The section-10 "implementation surface" is a specification of names, paths
and defaults — not code.

**Two decisions unblocked this lock, both made by the listener on 2026-08-25.**

1. **§3 — below `CLAUDISH_MIN_CHARS`, where no rewrite exists, the hook speaks the raw text, gated on
   hazard classes.** That **narrows a stated out-of-scope boundary** in #1. It is a deliberate
   narrowing, not an oversight, and §14a carries the replacement text for #1's bullet.
2. **§4.1 — axis 2 is closed as a *conditional* boundary**: `,` for runs of 3 items or fewer, `.` for
   4 or more. It had been carried as "deliberately undecided inside the noise floor"; that framing
   was wrong, and correcting it made the axis decidable.

---

## 0. Where each fact comes from

| tag | source | what it can and cannot prove |
| --- | --- | --- |
| **[obs]** | a live `Stop` payload captured on 2.1.245, 2026-08-25 | what this build actually sends. The strongest evidence in the document. |
| **[bin]** | `strings` of the shipped 2.1.245 binary, via [`turn-finality-and-the-stop-hook.md`](turn-finality-and-the-stop-hook.md) | what the build's compiled schema says. Disagrees with the docs in both directions — see §2. |

**Two of the links in this document do not resolve yet, and that is expected rather than an error.**
`turn-finality-and-the-stop-hook.md` lands on `main` via **PR #17**; `sanitizer-audition-13.md` and
`audition-verdicts-13.tsv` land via **PR #18**. Both are cited because they are the documents of
record for the evidence, and this branch is deliberately **not** rebased onto either — entangling
three PRs to fix a relative link would cost more than the broken link does. The links resolve when
those PRs merge.
| **[heard]** | [`sanitizer-audition.md`](sanitizer-audition.md), [`sanitizer-audition-13.md`](sanitizer-audition-13.md), [`voice-and-pipelining.md`](voice-and-pipelining.md), [`min-length-audition.md`](min-length-audition.md) | blind A/B verdicts and stopwatch readings. Noise floor ~1 call in 12. |
| **[repo]** | the working tree, read directly; line numbers citable | what this plugin does today |
| **[measured-here]** | measurements taken while writing this document — existing scripts over existing files, plus exit codes read off `jq` and `bash` directly | stated inline with what produced them. No audio, no benchmark, no LLM. |

**Four claims this spec was written from did not survive checking**, and the corrected versions are
used throughout:

- the rewrite-cost crossover measures **spoken audio duration**, not LLM latency, and nine of its
  twelve pairs are predictions rather than stopwatch readings (§3.3);
- `ack07` is **177 characters** *or* **147 prose characters** *or* **149 prose bytes** depending on
  the unit, and the units are not interchangeable — nor is #10's ~335-char threshold comparable to
  `CLAUDISH_MIN_CHARS` (§3.4);
- `rewrite.sh` **does** set shell options — `set -uo pipefail` at `rewrite.sh:55` — so "no `set -e`"
  understates what the `Stop` hook must avoid (§5);
- axis 2 was **not** a 1–1 tie inside the noise floor; the tally hid an item-count effect the variant
  could not express (§4.1);
- **only exit code 2 blocks the turn on `Stop`**, not any non-zero exit — and the replacement
  mechanism handed over with that correction (*"`jq` exits 2 on a malformed filter"*) is **also wrong
  on this machine**: a malformed filter exits **3**. The real exit-2 routes are a **bash syntax
  error** and **`jq` given a filename it cannot read**, both measured (§5);
- **`stop_hook_active` is not a duplicate-detector**, and a rule built on it would have spoken the
  rejected answer and suppressed the real one (§5.1).

The last two arrived after this spec had already locked its §5, and both are marked **CORRECTED** in
place rather than rewritten away.

---

## 1. LOCKED — the architecture is two hooks

| | `MessageDisplay` → `rewrite.sh` | `Stop` → `speak.sh` (new) |
| --- | --- | --- |
| fires | once per streamed chunk of every assistant message (`rewrite.sh:5-10`) | once, when the turn ends **[obs]** |
| owns | the plain-English rewrite that appears **on screen** | **speech, and nothing else** |
| must not | fire speech | touch the screen |
| declared timeout | 60 s (`hooks/hooks.json:9`) | **10 s** — see §10.4 |
| harness default | 10 s **[bin]** | 600 s **[bin]** |
| fires for subagents | yes | **no** **[obs]** — §7 |
| exit status means | "hook failed"; content passes through | **exit 2 blocks the turn**; every other code is an explicitly *non-blocking status code* — §5 |

**Why the split is forced.** `MessageDisplay.final` is *message*-level: a turn that emits three
narration messages and two tool calls sets `final: true` three times, and there is no lookahead at
display time — the tool call that would mark a message intermediate has not happened yet. `Stop`
fires once per turn and carries the text of the message that ended it. **[bin]**, confirmed **[obs]**.

**Consequence for `rewrite.sh`: none.** Its buffer-to-final logic is unchanged. What changes is that
speech is not its job, and the spec states that as a **prohibition**, because a reader looking at
`rewrite.sh:244`'s `emit "$out"` will otherwise see the obvious place to put a `say` call.

**Consequence for `speak.sh`: never read `transcript_path` for turn-final text.** The transcript is
written asynchronously and can lag the in-memory conversation; `last_assistant_message` exists to
spare hooks that race. `rewrite.sh` already reads `transcript_path` for the *user's question* and
that stays fine — it wants an older message. **[bin]**

---

## 2. LOCKED — the `Stop` payload, as observed

The live payload on 2.1.245 carries **exactly eleven fields** **[obs]**:

```
session_id  transcript_path  cwd  prompt_id  permission_mode  effort
hook_event_name  stop_hook_active  last_assistant_message  background_tasks  session_crons
```

- **`stop_reason` and `model` are ABSENT**, despite both appearing in the official docs. The docs are
  wrong for this build; the binary was the reliable source. **Any design that reads either gets
  nothing.** **[obs]**
- `last_assistant_message` carried the full final text — 1511 characters — **as raw markdown**. This
  is the observation that makes §3's handoff necessary rather than merely tidy. **[obs]**
- `stop_hook_active` was `false`, as documented. **[obs]**
- `background_tasks` held one entry: `{id, type: "subagent", status: "running", description,
  agent_type}` — a subagent still running at the moment the turn ended. **[obs]**
- `last_assistant_message` is **optional**: the binary computes it as
  `p ? Cs(p.message.content,"\n").trim() || undefined : undefined`, so a tool-use-only final message
  yields **absent, not empty string**. **[bin]**, marked `[inferred]` at source.

**Specification.** `speak.sh` treats `last_assistant_message` as absent-by-default and exits 0
quietly when it is missing or empty. It reads no field this list does not contain.

---

## 3. LOCKED — what gets spoken

This is the section the lock was waiting on. It has three parts: the handoff, the raw-speech gate,
and the decision table that joins them.

### 3.1 LOCKED — the handoff: `rewrite.sh` publishes, `speak.sh` consumes

`Stop.last_assistant_message` is Claude's raw markdown **[obs]**. The plain-English rewrite exists
only inside `rewrite.sh`, in a different process, on a different event. A `Stop` hook that speaks its
own payload text speaks un-rewritten Claudish.

**So `rewrite.sh` publishes its finished rewrite into a per-session buffer and `speak.sh` consumes
the latest.** The two rejected alternatives, for the record: `Stop` re-rewriting is a second LLM call
per turn on the turn-ending path for text already rewritten (#4 killed the parallel-LLM option for a
weaker version of this reason); and `Stop` speaking its own payload is the thing #1 bans.

**Buffer location — derived from the existing idioms, not invented.**

`rewrite.sh` already owns a scratch layout: `BUF_ROOT="${TMPDIR:-/tmp}/claudish-to-english"`
(`rewrite.sh:69`), per-message directories at `$BUF_ROOT/$sid/$mid` (`:120`), a per-message
`cleanup()` that `rm -rf`s the message dir (`:144`), and an opportunistic sweep (`:117-118`) that
removes **depth-2 directories** older than 30 minutes and then **empty depth-1 directories**.

That sweep is the constraint. It reclaims directories and never loose files — which is why
`emit()` explicitly unlinks its own argument (`rewrite.sh:84-86`: *"without this these would pile up
in TMPDIR one per assistant message"*), and why `$BUF_ROOT/$sid.notified` (`:210`) is a small
standing leak today. **[repo]**

**Therefore the buffer is a directory at exactly depth 2**, so the existing 30-minute sweep reclaims
it with no new cleanup code:

```
$BUF_ROOT/<session_id>/speak/          # depth-2 dir -> swept by rewrite.sh:117 after 30 min idle
$BUF_ROOT/<session_id>/speak/rewrite   # the finished rewrite, exactly as emitted, no separator
$BUF_ROOT/<session_id>/speak/source    # sha256 of the trimmed ORIGINAL assistant text
$BUF_ROOT/<session_id>/speak/prompt_id # the prompt_id, IF MessageDisplay carries one (see 3.2)
```

`speak.sh` writes two more files into the same directory — `spoken` (the dedup hash, §5.1) and `pid`
(the preemption PID, §10.6). **Both hooks write into one depth-2 directory**, which is what keeps the
whole feature inside a single sweep-reclaimed path.

**Lifecycle: one `speak/` per session, overwritten in place on every rewritten message.** Not one per
message — a per-message file would reproduce exactly the pile-up `emit()`'s comment warns about.
`speak.sh` never deletes it; the existing sweep does.

**Publication point.** `rewrite.sh` obtains `$rewrite` before it builds `$out` at `:235`. The publish
is a **separate write** placed there, not a reuse of `$out`: `emit()` reads and then `rm -f`s its
argument (`:84-90`), so the file `emit` is handed does not survive the call. The publish must also be
guarded (`|| true`) so that a full disk or an unwritable `TMPDIR` cannot change `rewrite.sh`'s exit
path — the display hook's fail-open contract outranks the speech feature absolutely.

**Only successful rewrites are published.** The below-threshold branch (`:147`), the notice branch
(`:210-225`) and every `pass_through` publish nothing. A stale `speak/` from an earlier message is
therefore possible, which is what §3.2 is for.

### 3.2 LOCKED (intent) / OPEN (key) — staleness matching

**The requirement is locked: `speak.sh` must prove the buffered rewrite belongs to *this* turn's
final message before speaking it, and stay silent rather than guess.** Speaking a stale rewrite is
worse than silence: it is a confident, fluent statement about the wrong turn.

**`prompt_id` is the natural key and it is OPEN whether it is available.** The `Stop` payload carries
`prompt_id` **[obs]**. Whether the `MessageDisplay` payload carries one has **never been observed** —
`rewrite.sh` reads `.message_id`, `.session_id`, `.index`, `.final`, `.delta`, `.transcript_path`
(`rewrite.sh:104-112`) and nothing else, and no capture of a `MessageDisplay` payload exists.
**The brief for this spec assumed `prompt_id` was the key; that assumption is not yet supported by
anything.** One probe closes it: the same throwaway-hook-writes-payload-to-disk technique that
settled the `Stop` payload, pointed at `MessageDisplay`.

**So the locked mechanism uses only fields both sides are observed to have: the source text.**

```
rewrite.sh publishes:  sha256( trim( assembled original text ) )   -> speak/source
speak.sh  computes:    sha256( trim( last_assistant_message ) )
match -> speak speak/rewrite.   mismatch or missing -> fall through to the decision table (3.5)
```

A hash, not the text, so nothing large is stored or compared. `trim` on both sides because the
harness itself trims (`…trim() || undefined`, **[bin]**).

**The failure mode is real and its rate is UNMEASURED.** `last_assistant_message` is the content
blocks joined on `"\n"` and trimmed **[bin]**; `rewrite.sh`'s `$full` is the concatenation of
`MessageDisplay` deltas. For a single text block these should be identical. For a final message that
mixes text with other content blocks they may not be, and **no one has compared the two strings on a
real turn.** A mismatch is safe (it silences that turn) but a systematically high mismatch rate would
silence the feature. **Closing condition: log both strings for ~20 turns and count exact matches.**
That measurement is cheap, it is not blocked on anything, and it should be taken before the
implementation is trusted. Until it is taken, the match rate is unknown and this spec does not claim
it is high.

**If the probe shows `MessageDisplay` carries `prompt_id`, prefer it** — it is an identity rather
than a content comparison, and it survives the content-block-join problem entirely. The hash path
stays as the fallback. Both are specified so the implementer is not blocked on the probe.

### 3.3 LOCKED — below `CLAUDISH_MIN_CHARS`, speak raw, gated on hazards

**The conflict this resolves.** Three commitments could not all hold:

1. **[heard]** #10's verdicts mark `ack07` **worth speaking**, and it is below the threshold.
2. **[repo]** `rewrite.sh:147` does not rewrite below `MIN_CHARS` (default 200, `rewrite.sh:63`) — it
   re-shows the original. Below the threshold **there is no rewrite to hand over.**
3. #1's out-of-scope list bans *"Speaking raw, un-rewritten Claudish … speech only ever carries a
   successful plain-English rewrite."*

**The user's decision, 2026-08-25: keep 1 and 2, narrow 3.** The out-of-scope rule's own stated
rationale is *"unreadable text is less listenable, not more"* — a claim about **hazards**, not about
provenance. So the rule narrows to **"never speak raw text that carries a disqualifying hazard
class"**, and clean short messages are spoken raw.

**This is a deliberate narrowing of a stated scope boundary, made by the user, not an oversight, and
not something an agent inferred.** §14 carries the replacement text for #1.

**Three pieces of supporting evidence, each stated at the strength it actually has.**

- **Rewriting a short message would not have shortened the listening.** Over the twelve real pairs,
  below ~600 raw characters the rewrite's audio is *longer*, in seven of the eight pairs (`r07` is
  the exception at −3.2 s); above ~1600 characters it is much shorter. Grouped: `r01`–`r04` 75.1 s
  raw / 77.7 s rewritten; `r05`–`r08` 154.2 / 169.8; `r09`–`r12` 656.7 / 516.2. **[heard]**
  `min-length-audition.md`.
  **Read this claim precisely.** It measures **spoken audio duration**, not LLM latency — the
  document ran zero LLM calls. And only **three** of the twelve pairs were synthesised and
  stopwatched (`r01` 15.2→16.5 s, `r03` 21.4→20.8 s, `r06` 30.9→34.7 s); the other nine are the
  duration law's *predictions*. So the honest statement is: *at the lengths this band is about, a
  rewrite is not expected to make the utterance shorter* — not *the rewrite costs wall-clock
  seconds*.
- **Raw short text cannot crash the synthesiser.** Largest phoneme batch across the sixteen real
  short items is **265 against the 510 line** (`fct08`, prose_len 194). **[heard]**
- **No length threshold reproduces the verdicts anyway** (§9), so "speak raw below 200" is not
  smuggling a threshold back in — 200 is `rewrite.sh`'s pre-existing *rewrite* gate, and the speech
  decision is downstream of it.

### 3.4 LOCKED — the disqualifying hazard classes

**The universe.** [`corpus/classes.tsv`](../../corpus/classes.tsv) defines **53** classes, sourced
from #3, #10's programming-text research and #8's espeak measurements.
[`corpus/bin/detect-hazards.sh`](../../corpus/bin/detect-hazards.sh) is the **checked reference
implementation** of their detection — it exists so the corpus coverage table is verified rather than
asserted.

**The derivation, and where it refines the brief.** The brief's criterion was *"a class a settled
sanitizer rule exists to fix is a class raw speech mishandles."* Applied literally that disqualifies
**23** classes — every class any settled rule touches. That is too broad, for a reason the sanitizer
decisions themselves supply:

> **The sanitizer runs on both paths.** It is a synthesis-layer guard (terminal punctuation is
> crash-preventing, #1), not a stand-in for the rewrite. So by the time text reaches Kokoro, every
> settled rule has already fired — on the raw path too. Disqualifying a class *because a rule fixes
> it* double-counts a fix that has already been applied.

**What the rewrite does that the sanitizer cannot** is remove *structure and density*. So the cut
line is the **losslessness of the settled remedy**:

- A rule that **adds** (commas, boundaries) or **re-voices** (lowercase, "dot", " point ") leaves the
  message's content intact. Raw text carrying that class, after sanitizing, says everything it said.
  **Harmless.**
- A rule that **deletes or replaces content** — a code block becomes a four-word announcement, a URL
  loses its path, a path loses its leading segments — leaves the listener a summary of something they
  cannot see. On rewritten text that is fine: the rewrite already said in prose what the construct
  meant. On raw text nothing said it. **Disqualifying.**

**The disqualifying set — eight classes:**

| class | the settled remedy | what is lost | evidence |
| --- | --- | --- | --- |
| `MD-FENCE` | axis 7 `cb-count` → "Code block, N lines." | the entire block | **4–0**, and it beat *reading the block out* on all four items **[heard]** #8 |
| `MD-FENCE-MULTI` | same rule, the line count is the variable | same | same axis; **0 real carriers** |
| `URL` | axis 6 `url-domain` → the host only | scheme, path, query | **2–0**; `url-full` lost **0–2** **[heard]** #8 |
| `PATH-SLASH` | axis 3 `path-short-nolead` → last two segments | every leading segment | **3–0** undefeated (#8), **4–0** (#13) **[heard]** |
| `PATH-ABS` | axis 3, the `nolead` half | the leading `/` | same axis |
| `PATH-TILDE` | axis 3, the `nolead` half | the `~/` root | same axis |
| `PATH-DOTDIR` | axis 3, the `nolead` half | the leading bare `.` | same axis; `s13` is its only hearing |
| `EMOJI` | rule H — deleted outright | a status glyph (`✅`, `⚠️`) | phoneme damage measured; **never auditioned as an axis** |

**`EMOJI` is the one judgement call in that list**, and it is the weakest member. Rule H's alternative
is espeak saying "white heavy check mark", which is worse than deletion — so deletion is right, but
that is an argument about the *rule*, not about disqualifying the *message*. It is included because
`✅`/`⚠️` are the plugin's own status vocabulary and a deleted status marker is a deleted claim. An
implementer who moves it to the harmless column changes nothing measurable: **`EMOJI` appears on two
corpus items, both of them real rewrites above the threshold, and on none of the sixteen short
items.** **[measured-here]**

**The harmless set — every other class, and specifically these fifteen**, which the two readings of
the criterion disagree about. Each has a settled rule; each rule is additive or re-voicing:

| class | settled remedy | why it is lossless |
| --- | --- | --- |
| `MD-BACKTICK` | axis 1 `tick-pause` — commas around the span | additive. `tick-strip` is **phoneme-identical** to leaving backticks in, so raw is not damaged, only unphrased **[heard]** #8 |
| `MD-ASTERISK`, `MD-HASH` | rules C, D — markers deleted | emphasis is lost, propositional content is not |
| `ID-SCREAM` | rule J — lowercased | the word survives; the fix is that espeak stops *spelling* `MIN` |
| `ID-SNAKE`, `FLAG-SHORT` | axis 8 `flag-pause` — commas | additive. **A measured no-op on all twelve real rewrites** **[heard]** #13 |
| `PATH-EXT`, `PATH-HYPHEN-EXT` | axis 9 `ext-word` — `.` → " dot " | re-voicing; it *deletes a spurious full stop* and adds a syllable **[heard]** #13, 5–0 |
| `NUM-THOUSANDS` | rule G — separator stripped | the number is unchanged |
| `NUM-VERSION`, `NUM-DECIMAL`, `NUM-CURRENCY` | rules E, F, K | re-voicing of punctuation |
| `SPLIT-NEWLINE` | rule B — `\n+` → `. ` | additive boundary |
| `CHUNK-510-NOPUNCT`, `CHUNK-LIST-NOPUNCT` | rules A + B | additive boundary. **Crash-preventing, and the crash is prevented, not merely detected** |

**The two crash classes deserve a note**, because leaving them in the harmless column looks reckless
and is not. Rules A and B *fix* them — that is measured, `s35`/`s37` crash under the `none` control
and synthesise under `candidate` (#6). And they are unreachable in the sub-threshold band anyway: the
crash shape needs a ~400-character run with no `. , ! ? ;`, and prose_len is under 200. **[heard]**
The one route in is a code fence inside a short message — which `MD-FENCE` already disqualifies.

**The gate, cross-checked against the verdicts.** Running the reference detector over #10's sixteen
real sub-threshold items **[measured-here]**
(`bash corpus/bin/detect-hazards.sh bench/audition-10/items/*.txt`):

| result | items |
| --- | --- |
| carry **no** hazard class at all | `ack01`–`ack06`, `fct01` (7) |
| carry only **harmless** classes | `fct02`–`fct08`, `ack07` (8) |
| carry a **disqualifying** class | **none** (0) |
| above the rewrite gate, so not in this band | `ack08` (prose_len 200, `PATH-SLASH`) |

**And the item the whole decision hangs on passes.** `ack07` — the single sub-threshold item the
listener marked **worth speaking** — carries **no hazard class whatsoever**. The gate lets it
through. Every other sub-threshold item was marked *not worth speaking*, so the gate silences nothing
the listener asked for.

**State that result honestly: the gate is a no-op on all measured sub-threshold data.** Its cost is
zero and its measured benefit is also zero. It is a guardrail that bounds an unmeasured future, not
a filter that a measured case demanded. Anyone who finds it over-engineered is looking at the same
numbers.

**A unit trap, stated because it silently invalidates comparisons.** `ack07` is **177 characters**
(the audition's `chars` column, `audition-verdicts.tsv`), **147 prose characters** (the doc's item
tables, whitespace stripped), and **149 prose *bytes*** — which is what `rewrite.sh` actually
compares, because `rewrite.sh:139-142` pipes through `wc -c` and an em-dash is three bytes.
**[measured-here]** All three are below 200 so nothing here turns on it, but:

- `CLAUDISH_MIN_CHARS` is **200 bytes of non-whitespace, fenced code excluded** — not 200 characters.
  Any documentation that says "characters" is wrong for non-ASCII text, which Claude's em-dash habit
  makes the common case.
- **#10's "best threshold ~335 chars" is in the `chars` unit and `MIN_CHARS` is in the prose-bytes
  unit. They are not comparable.** No spec decision rests on comparing them, and none may.

`min-length-audition.md` reports `ack07` as 147 at lines 111 and 357 and as 177 at line 464 without
flagging the change of unit; both are correct and the document should say which is which.

**Implementation constraint: do not shell out to `corpus/bin/detect-hazards.sh`.** It is a corpus
tool, not a runtime component — it takes file arguments, spawns roughly sixty `grep`s per file, lives
under a path another PR owns, and sets `set -uo pipefail` at line 23, which is forbidden in a `Stop`
hook (§5). **Specification: `speak.sh` carries its own minimal classifier for the eight disqualifying
classes only**, with the detection expressions **lifted verbatim** from `detect-hazards.sh` — the
eight relevant lines are `:42` (`MD-FENCE`), `:47-52` (`MD-FENCE-MULTI`), `:93` (`URL`), `:71`
(`PATH-SLASH`), `:72` (`PATH-ABS`), `:73` (`PATH-TILDE`), `:74` (`PATH-DOTDIR`), `:94` (`EMOJI`) —
so the runtime gate and the checked reference cannot drift silently. Eight `grep -qE` calls, no
pipeline whose status can escape.

### 3.5 LOCKED — the decision table

`speak.sh`, once past the enable checks (§8), computes `prose_len` on `last_assistant_message` using
**the same formula as `rewrite.sh:139-142`** (strip fenced blocks, delete whitespace, `wc -c`), so
the two hooks agree about the threshold without coordinating.

| buffer | prose_len | hazards | action |
| --- | --- | --- | --- |
| **hit** (§3.2 match) | any | any | speak `speak/rewrite` — sanitized, pipelined |
| miss | `< MIN_CHARS` | none disqualifying | speak `last_assistant_message` **raw** — sanitized, pipelined |
| miss | `< MIN_CHARS` | ≥ 1 disqualifying | **silent** |
| miss | `≥ MIN_CHARS` | any | **silent** |

**The last row is the fail-open ban, kept intact.** Above the threshold a rewrite was due. If it did
not arrive, the LLM provider failed, timed out, or returned empty — and #1's out-of-scope rule bans
speech on exactly that path. Nothing about the hazard narrowing touches it: the narrowing licenses
raw speech only where **no rewrite was ever attempted**, never where one was attempted and failed.
That distinction is the whole content of the amendment in §14.

**The sanitizer runs on both speaking rows.** Same settled set, same order (§4). There is no
raw-specific sanitizer.

**A wrinkle that only bites if this band ever grows.** #10 measured raw *short* text at a largest
batch of 265 phonemes against 510 **[heard]**, so the raw path cannot crash today. A **long** raw
assistant message has never had its batch sizes measured — and the table above never sends one to
synthesis. If a future change lets long raw text through, that measurement is owed first.

---

## 4. LOCKED — voice, pipelining, and the sanitizer set

**Voice: `bf_emma`.** Winner on all four real path-dense items, blind; `af_heart` — the assumed
default for this entire map, never heard against real content until #9's sitting — is **rejected**,
along with `af_nicole`, `af_bella`, `am_michael`. **[heard]** #9.

**First-sentence pipelining: required, not optional.** Without it `r11` (32.4 s) and `r12` (36.4 s)
exceed the hard 30 s ceiling and never speak at all. `kokoro-onnx`'s own `create_stream()` is not
enough — its granularity is the packed batch (≤509 phonemes, ~25 s of speech), giving 0/12 and a
median 5.41 s. The worker chooses sentence boundaries itself. Do **not** batch sentence one up to a
minimum length: `--min-chars 80` drops 12/12 to 10/12. **The splitter must run *after* markdown
stripping** — in `r10` the first full stop sits inside `**…find.**`, so splitting raw text yields a
219-char "first sentence" (3.58 s, FAIL) where splitting sanitized text yields 32 chars (0.50 s,
PASS). **[heard]** #9.

**TTFA on the chosen voice: 12/12 under 3 s, median 0.86 s, max 1.20 s**, and `bf_emma` produces
**0.927×** `af_heart`'s audio duration — so #9's margin, measured on the rejected voice, needs no
revision. **[heard]** #13. **This closes the loose end #9 recorded** and the draft carried forward.

> **Read the TTFA figure with its exclusion attached.** It excludes model load (0.53–0.83 s, reported
> separately) and it is a **warm** number. #6 measured the *cold* first synthesis at **3.93 s TTFA —
> over the 3 s line** — and #5 measured the first synthesis after a sleep/wake at **~4.9 s vs ~0.95 s
> warm**. So the 0.86 s median is a property of a **resident, already-loaded worker**, and §10.5's
> unspecified worker lifecycle is what stands between the spec and that number. This is the largest
> gap between what the spec claims and what has been measured end to end.

**The sanitizer set: #8's seven axes as amended by #13.** Rules A–K, with:

| axis | setting | margin |
| --- | --- | --- |
| 1 backticks | `tick-pause` — commas around each `` `span` `` | 2–0, 1 tie |
| 2 line breaks | **conditional: `,` for ≤ 3 items, `.` for ≥ 4** — §4.1 | listener's call, 2026-08-25 |
| 3 paths | **`path-short-nolead`** — last two segments, no leading bare dot | 4–0 (#13, amending #8's `path-shorten`) |
| 4 markdown | rules C + D — strip `*` and `#` | 5–0 |
| 5 `SCREAMING_SNAKE_CASE` | rule J — lowercase `_`-joined tokens | **7–0** |
| 6 URLs | `url-domain` — "github dot com" | 2–0 |
| 7 code blocks | `cb-count` — "Code block, N lines." | **4–0**, and it beat reading the block out |
| 8 flags / bare identifiers | **`flag-pause`** — axis 1's commas, generalised | 4–0, **all four synthetic** |
| 9 `name.ext` | **`ext-word`** — the `.` becomes "dot" | **5–0**, two of them real items |

**Rule order is normative, not incidental: paths before extensions.** `_pipeline` runs `rule_P_paths`
then `rule_X_extensions`, so a segment the path rule just shortened still gets its extension spoken.
`ext-word` does **not** step over backticked spans; `flag-pause` does. **A bare extension is left
alone** (`.sh` with no name in front is `PATH-EXTBARE`, where both frontends already agree).
**[heard]** #13.

**Rule L (respelling `lives`) does not ship.** Still gated behind `--respell`, still mis-fires on
"the lives of others", never auditioned. **No pronunciation table ships either** — for all 23
extensions the sanitizer recognises, espeak's reading is byte-identical after a `.` and after the
word "dot", and already correct. `.py` reads "pie" and `yml` reads "immel"; both are known and left
alone on purpose. `ext-word`'s win is **prosody, not pronunciation** — it deletes a full stop espeak
was planting mid-sentence. **"We added dot-word to fix pronunciation" is the wrong summary.**
**[heard]** #13.

### 4.1 LOCKED — axis 2 is a **conditional** boundary: `,` for ≤ 3 items, `.` for ≥ 4

**Axis 2 was carried as "deliberately undecided inside the noise floor" on a 1–1–1 tally. That
framing was wrong, and once corrected the axis was decidable.** It is now **closed**:

> **The line-break boundary is `,` when the run holds 3 line-break-separated items or fewer, and `.`
> when it holds 4 or more.** Decided by the listener directly, 2026-08-25.

**Why the tally was the wrong reading.** All three axis-2 verdicts, read out of
`audition-verdicts.tsv` **[measured-here]**:

| item | shape **[measured-here]** | `base` (`.`) vs `lb-comma` (`,`) |
| --- | --- | --- |
| `r09` | 1176 chars, 16 lines, 6 bullets — bullets embedded in prose paragraphs | **no audible difference** |
| `s37` | 653 chars, 9 lines, 8 bullets — a pure list | **`.` wins** |
| `s38` | 106 chars, 4 lines, 3 bullets — a pure list | **`,` wins** |

So it is **not a tie across comparable items.** Paragraph-heavy text is indistinguishable either way;
the only two items that discriminate are **both pure lists, differing 6.2× in size**. That reads as a
**length or item-count effect**, not as a coin landing on its edge: many items need real separation,
a few short ones are naturally one enumeration.

**The audition could not have expressed the answer, and that is why it looked tied.** `lb-comma` is
`_pipeline(text, opts, Axes(boundary=","))` (`bench/sanitizers.py:590-592`), and
`rule_B_newlines_to_punct` (`:152-163`) matches `(\S)[ \t]*\n+[ \t]*` — **`\n+`, one or more** — with
a **single** `boundary` character. A single newline (list item) and a double newline (paragraph break)
get the same replacement. **The audition forced one answer to what the verdicts show are two
questions.** Same failure shape as #10's premise (a length question that was really a kind question)
and axis 7's size dependence (`cb-long` wins only where N is large). **[repo]**

**Axis 2 carries no crash-safety weight either way, and that is what makes a conditional prosodic
rule safe to adopt at all.** `BOUNDARY_CHARS = ".,!?;"` at `bench/sanitizers.py:86`, annotated
*"exactly what `kokoro_onnx._split_phonemes` splits on"* — so **both** choices are valid batch split
points and **either one** prevents the 510-phoneme `IndexError`. The rule can switch boundary
character on a count without ever affecting whether the text chunks. The question is purely
prosodic. **[repo]**

#### The rule, as specified

> **Rule B′ (conditional boundary).** For each run of line-break-separated items, count the items
> the run holds. Replace the line breaks with **`, `** if the count is **≤ 3**, and with **`. `** if
> the count is **≥ 4**. A line already ending in a `BOUNDARY_CHARS` member keeps it, unchanged from
> rule B's existing behaviour (`bench/sanitizers.py:157-159`).

Three qualifications, stated plainly rather than smoothed over.

**1. The cutoff's *position* is the listener's call, not an audited result.** The three verdicts are
**consistent** with it — `r09` paragraph-heavy is indistinguishable either way, `s37` at 8 bullets
picks `.`, `s38` at 3 bullets picks `,` — but **no item between 4 and 7 bullets has ever been
synthesized.** The corpus jumps 3 → 8. So "4 and up" is **where the listener puts the boundary, not
where a wav proved it**, and the **4–7 band is unaudited**. Held to the same standard as
`flag-pause`'s zero real carriers (§4.3): adopted, and the gap recorded rather than footnoted.

**2. No registered sanitizer implements this, so it has to be built.** All 26 registered variants take
a **fixed** boundary character; `lb-comma` and `lb-period` differ only in which one. **A conditional
boundary is a new capability, not a variant selection** — rule B currently receives `boundary` as a
parameter and has no access to an item count. Consequence for §4.2: **the settled-set confirmation
listen cannot include axis 2 until rule B′ exists.** That listen was already an open item; this
**enlarges** it from "register a composition of existing rules" to "implement one new rule, then
register the composition".

**3. What "item" counts, specified so the implementation is not a judgement.** The items of a run are
the non-empty segments a `\n+` split produces — the same segments rule B already replaces between.
Bullet markers are not required and are not counted: `MD-BULLET` is silent or an em-dash pause
depending on the spaCy tag, so the count is over **lines**, not over `-` characters. A paragraph-only
run of two long paragraphs therefore counts 2 and takes `,`; this is untested and is the most likely
place the rule is wrong, because both discriminating verdicts came from pure lists and the one
paragraph-heavy item was a tie.

### 4.2 OPEN — the settled combination has never been synthesized

**26 sanitizers are registered and not one of them is the settled set.** Every pair on both audition
pages moves exactly one axis against `base` — which is what made them readable — so
**`tick-pause` + `flag-pause`** on one item, and **`path-short-nolead` + `ext-word`** on one path, are
compositions no wav on disk contains. Under the settled set a `` `hooks.json` `` reaches the model as
`, hooks dot json,` — axis 1's commas and axis 9's "dot" on the same token, a composition that has
never been heard. **[heard]** #13.

**Requirement, and it is a requirement rather than a nicety:** register the settled combination as a
**single named variant** and give it **one confirmation listen** before speech ships. **Not to
re-decide an axis** — every margin above stands — **but to catch an interaction.** If the listen is
clean, no axis reopens; if it is not, the interaction is the finding.

**§4.1 enlarges this item.** The settled set now contains a rule that **does not exist yet** — the
conditional boundary B′ — so the confirmation listen has two steps rather than one: **implement B′,
then register the composition.** Until B′ exists the settled set cannot be synthesized even in
principle, which makes this the first thing the implementation phase does rather than the last.

### 4.3 OPEN — `flag-pause` has no real carrier

`flag-pause` is a **measured no-op on all twelve real rewrites** — byte-identical, twelve for twelve
— because every flag and `_`-joined identifier in them already sits inside backticks, where
`tick-pause` puts the commas there by a different rule. So it ships **free of regression risk**: it
cannot change a word of today's real output. **But its value rests entirely on output shapes
production has not produced.** All four discriminating pairs are synthetic (`s15`, `s16`, `s17`,
`s28`), and the question `s28` raises — five commas in two sentences, help or stutter? — has been
answered only on `s28`. Same gap class as `MD-FENCE-MULTI`. **[heard]** #13.

**Closing condition:** a corpus capture that puts a bare flag or `_`-joined identifier *outside*
backticks in a real message. Recorded as a live caveat, not a footnote.

---

## 5. LOCKED — fail-open, and on `Stop` the reason is narrower and sharper than it first looked

> **CORRECTED 2026-08-25, and the correction is recorded rather than absorbed.** An earlier reading —
> carried in the draft this spec replaces, in the brief it was written from, and in the first version
> of this section — said *"on `Stop`, any non-zero exit blocks the turn."* **That is false.** The
> conclusion (exit 0 on every path) survives unchanged; the argument for it does not, and the
> replacement argument is **narrower, more specific, and easier to check**. Showing the change is the
> point: a spec that quietly upgraded its own reasoning would be asking to be trusted about the next
> thing too.

**What is actually true.** **Exit code 2 alone blocks the turn.** The result resolver returns
`blocked: true` for status **2** and labels every other code a *"non-blocking status code"* — a string
present in the 2.1.245 binary, 4 occurrences. The `Stop` consumer drives its retry **only** from
`blockingError`; any other failure renders as a **single warning line** and the turn ends normally.
Exit-2 blocks are counted and capped at `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP ?? 8`, after which the
runtime overrides. **[bin]** The cap counts *tolerated* blocks and the comparison against it is
**strict**, so the ninth block still runs before it is refused: the observed cost is **nine
invocations — one initial fire plus eight re-fires** — measured at exactly nine in three independent
runs. **[obs]** See [`stop-hook-block-mechanics.md`](stop-hook-block-mechanics.md).

**So the hazard is not "any error holds the prompt hostage" — it is much more specific, and that
makes it more real, not less.** A speech hook that exits 1 because a binary was missing loses nothing
but the utterance. A speech hook that exits **2** holds the user's prompt open and is re-fired
**eight** times — **nine invocations in all. [obs]**

**Nine is the loop's ceiling, not the audio's, and the two are different costs.** How much the user
actually hears depends on two things the invocation count says nothing about: whether an invocation
reaches the speech call at all before it exits 2 — the bash-syntax-error bullet below is a path where
it does not — and §5.1's `spoken` hash, which exits 0 on text it has already sent to synthesis. So
**a message that does not change is spoken once, however many times the hook runs**; this design
cannot speak the same message nine times. Additional utterances require the resolved text to
*change*, and the driven run shows that it usually does: **eight distinct `last_assistant_message`
values across the nine fires of one turn [obs]**, because Claude answers each block before the hook
re-fires. Dedup suppresses genuine repeats; it cannot suppress a turn whose text keeps moving — and
§5.1 argues that it should not.

> **THIRD CORRECTION, in two parts — the count and the unit.** *(a) The count.* This section
> previously said the hook is "re-fired up to 8 times", taking `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`'s
> default as the invocation count. It is **nine**: the cap bounds *tolerated* blocks under a strict
> comparison, so the ninth block executes and is then refused. Counted at exactly nine in three
> independent driven runs — `exit 2`, varied-stderr, and the `{"decision":"block"}` JSON route all
> cap identically. **[obs]** See [`stop-hook-block-mechanics.md`](stop-hook-block-mechanics.md).
> *(b) The unit.* The same sentence went on to say the hook speaks "the same message up to 8 times",
> and **the first version of this correction repeated that error at nine** instead of catching it: it
> scaled a number that counts invocations and reported the result as utterances. **The unit was wrong
> before this correction and wrong after it**, and it was caught on review of the very change that
> fixed the count. Both parts are recorded, because the second is the more instructive — the count
> was read wrong once, the unit was carried wrong twice. §5's conclusion is unaffected by either.

**And this plugin's own idiom can produce a 2 — but not by the route that was claimed.**

> **SECOND CORRECTION, measured here rather than inherited.** The replacement reasoning handed to this
> spec was *"`jq` exits 2 on a malformed filter."* **That is false on this machine.** Measured on
> `jq-1.7.1-apple`, `bash` under Darwin 25.6.0 **[measured-here]**:
>
> | cause | exit code | blocks the turn? |
> | --- | ---: | --- |
> | **bash syntax error in the hook script** | **2** | **yes** |
> | **`jq` bad option, missing file, or `--rawfile <missing>`** | **2** | **yes** |
> | `jq` malformed filter (program compile error) | 3 | no |
> | `jq` unparseable JSON on stdin | 5 | no |
> | `set -u` expansion of an unset variable | **1** | no |
> | command not found / missing script | 127 | no |
>
> So the conclusion holds and is if anything better supported — **two real exit-2 paths exist** — but
> the specific mechanism cited was wrong, and one leg of the argument collapses entirely. Recorded
> rather than smoothed over, for the same reason as the first correction.

**The two paths that genuinely reach exit 2:**

- **A bash syntax error in `speak.sh` is exit 2.** This is the strongest form of the hazard and it was
  not in either earlier version: an unbalanced `fi`, `done`, or quote does not fail one turn, it
  **blocks turn after turn** — up to nine invocations each, and typically **zero utterances**. It is
  also the single most likely defect in a shell script under edit. Mitigation is not a runtime guard
  — a guard cannot run in a file the parser refuses to get past — it is `bash -n` before the file
  ships, and keeping the file small.

  > **FOURTH CORRECTION — this bullet was wrong before this PR and wrong after it.** It said the error
  > "**blocks every turn** and speaks the same message 8 times each"; the correction above changed the
  > 8 to a 9 and left the mechanism untouched. **The two halves cannot both be true, and the utterance
  > half is the false one.** `bash` executes a script command by command *as it parses it*, so
  > execution stops where the parse fails: everything textually **before** that point has already run,
  > everything after it never runs at all. **[measured-here]** — `bash 3.2.57(1)-release`, Darwin
  > 25.6.0: a script whose trailing `if` is unterminated still ran its earlier `echo`; the same script
  > with that `echo` moved *after* the broken `if` printed nothing; an unterminated quote behaves like
  > the unterminated `if`; every variant exited **2**. So the real cost is **nine invocations and zero
  > utterances whenever the parse fails before the speech call** — the usual arrangement, since an
  > unbalanced `fi`, `done` or quote generally *encloses* the body it broke. Where the break sits
  > after the speech call the call does run on every fire, but §5.1's hash still speaks each distinct
  > message once. **Nine utterances of the same message was never reachable on either arrangement.**
  >
  > **Stating it accurately makes this hazard worse, not better.** Its likely shape is **silent**: the
  > prompt hangs through nine fires, the user hears nothing at all, and the only surface is the
  > runtime's single post-cap warning line. A hook that spoke nine times would at least have announced
  > itself. The same measurement settles the opposite tail — an `exit 0` the script reaches *before*
  > the parse failure exits **0** **[measured-here]**, so a broken file is not even reliably a blocker;
  > which turns block depends on where the break landed relative to the single `exit 0` the invariant
  > requires. That is an argument for `bash -n` as a ship gate, not for reasoning about where any
  > particular break fell.

- **`jq` invoked with a bad option or an unreadable file is exit 2** — and this *is* the plugin's own
  idiom: `rewrite.sh:87` is `jq -n --rawfile dc "$1"`, so a vanished temp file lands exactly here.
  `rewrite.sh` already guards it (`2>/dev/null || { rm -f "$1"; pass_through; }`), which is the
  precedent to copy rather than re-derive.

**What this costs the old argument: `set -uo pipefail` is no longer the blocking hazard.** `set -u` on
an unset variable exits **1**, which the resolver classes as *non-blocking* — so it costs the
utterance, not the turn. **`speak.sh` still sets no shell options**, but the honest reason is
robustness and predictability, **not** turn-blocking. A spec that kept claiming otherwise would be
citing a measurement that says the opposite.

> **INVARIANT (both hooks; the `Stop` hook especially).** Every hook this plugin ships exits **0 on
> every path, including every error path**. On `MessageDisplay` this is what keeps a display hook from
> swallowing the assistant's answer (`rewrite.sh:22-25`). On `Stop` the reason is different and
> narrower: **exit code 2 is not a failure report, it is a request to block the turn** — eight
> re-fires under `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`'s default of **8 tolerated blocks**, which is
> **nine invocations of the hook in total [obs]**. Nine is the loop's cost, not the audio's: what
> reaches synthesis is §5.1's business, and for a message that does not change it is one utterance.
> The two
> routes that actually produce a 2 are **a bash syntax error in the hook** and **`jq` given a bad
> option or an unreadable file** (`rewrite.sh:87`'s `--rawfile` shape). Every other failure code — 1,
> 3, 5, 127 — is explicitly *non-blocking* and costs only the utterance. **The `Stop` hook's exit must
> carry its own comment naming those two routes**; a cross-reference to the display hook's comment
> would document the wrong hazard, a comment saying "any non-zero exit blocks" would document a hazard
> that does not exist, and a comment blaming `set -u` would name a code (1) that does not block.

**`rewrite.sh` survives its own shell options** because it guards every pipeline with
`|| pass_through` **and** because on `MessageDisplay` a non-zero exit is harmless anyway. **Neither
protection transfers to `Stop`.**

**Specification for `speak.sh`:**

- **`bash -n speak.sh` must pass before the file ships**, and be re-run on every edit. This is the
  mitigation for the *only* exit-2 route a runtime guard cannot cover, and it is the one item on this
  list that is a process requirement rather than a code requirement.
- **Every `jq` invocation guarded** — `2>/dev/null || true`, or its status tested and discarded — with
  particular care wherever a **filename** is passed (`--rawfile`, `--slurpfile`, a positional file),
  because that is the shape that returns **2**. `rewrite.sh:87-90` is the precedent.
- **No `set -e`, no `set -u`, no `set -o pipefail`.** For robustness and predictability — **not**
  because they block the turn; `set -u` exits **1**, which is non-blocking. State that honestly in
  the comment rather than overstating it.
- Every expansion defaulted (`${VAR:-}`); every external call `|| true` or explicitly tested.
- A single `exit 0` reachable from every path, and **no `exit` with any other status anywhere in the
  file** — which makes the invariant checkable by `grep`, not by reasoning.

### 5.1 LOCKED — `stop_hook_active` is **not** a duplicate-detector, and must not be used as one

> **CORRECTED 2026-08-25.** The draft and the first version of this section specified *"read
> `stop_hook_active` and stay silent when it is `true`",* on the reasoning that `true` means this
> turn's final message has already been spoken. **That rule is not merely useless — it is inverted,
> and it is the most dangerous single thing this spec previously said.**

**Why it inverts.** Claude replies to a blocked turn **before** the hook re-fires, so the payload that
arrives with `stop_hook_active: true` usually carries the **newer** text. A "stay silent while
`stop_hook_active` is true" rule would therefore **speak the rejected answer and suppress the real
one** — the exact opposite of what it appears to do. **[obs]**

**This is now observed, not reasoned.** When this section was written the inversion was inferred from
the binary; a driven blocking run has since captured all nine payloads of a single turn and found
**eight distinct `last_assistant_message` values across the nine fires**, with fires 1 and 9 differing
in `stop_hook_active` and `last_assistant_message` and nothing else. `stop_hook_active` is `false` on
fire 1 and `true` on fires 2–9, every run. **[obs]**
[`stop-hook-block-mechanics.md`](stop-hook-block-mechanics.md)

**Specification.**

- **`speak.sh` reads `stop_hook_active` for no behaviour at all.** Log it under `CLAUDISH_DEBUG` if
  useful; branch on it never.
- **Deduplication compares the message text**, and it reuses machinery §3.1 already specifies rather
  than adding any:

```
$BUF_ROOT/<session_id>/speak/spoken   # sha256 of the text last actually sent to synthesis
```

  Before speaking, hash the text about to be spoken and compare. Equal → `exit 0`. Different → write
  the new hash, then speak. Same depth-2 directory, so `rewrite.sh:117`'s existing sweep reclaims it
  (§3.1); same hashing the handoff match already needs (§3.2).

**What this buys, stated precisely.** It suppresses a genuine re-fire of the **same** text — the case
the flag was reached for. It does **not** suppress the blocked-turn sequence, and that is correct: if
text A was already spoken and Claude then produces B, A cannot be un-spoken, so speaking B as well is
the best behaviour available. The old rule would have spoken A and swallowed B.

**One accepted cost:** if Claude legitimately ends two consecutive turns with byte-identical text, the
second is silent. Rare, and silence is the safe direction.

---

## 6. LOCKED — non-blocking rests on the plugin's own detachment, not on `async: true`

**The constraint is how long the prompt is held, and the honest number is not TTFA.**

| what is waited for | measured | source |
| --- | --- | --- |
| first-sentence TTFA | **0.86 s median, 1.20 s max**, 12/12 under 3 s, `bf_emma` | **[heard]** #13 |
| whole-message **audio duration** | **16.5 s (`r01`) – 172.8 s (`r12`)** across the 12 real rewrites | **[heard]** #9 |

If the hook merely *starts* playback and returns, it holds the prompt about a second — small, but a
real regression on a plugin whose promise is that it never makes you wait, and paid on **every** turn.
If it waits for playback to finish it holds the prompt for the **audio duration, up to ~173 s**. The
second is not a trade-off, it is a defect — and it is where the obvious shape ("synthesise, play,
exit") lands by default.

**The timeout is not the constraint, and that framing should be killed.** The harness defaults are
**600 s** on `Stop`/`SubagentStop` and **10 s** on `MessageDisplay` **[bin]**. Nothing about speech
comes near 600 s, so "under the timeout" was never the question.

**Two things this spec deliberately does *not* argue.** There is **no harness 60 s cap** to argue
against in the first place — the 60 is `hooks/hooks.json:9`, this plugin's own declared value.
And **the 180 at `:21` proves nothing about a ceiling**: config *acceptance* is not runtime
*enforcement*, so a plugin declaring 180 shows only that 180 passed validation. **Whether any
absolute ceiling exists is unestablished**, and it is left that way rather than argued from
`hooks.json`. **[bin]**

**LOCKED: the guarantee is carried by detachment, and detachment alone.** Speech is fired detached —
**stdio closed, disowned** — exactly as #1's standing constraint already commits. It is in this
plugin's own code, it is testable from here, and it is the mechanism the fail-open contract already
rests on.

**LOCKED: `async: true` is not load-bearing and the spec does not depend on it.** Its entire evidence
is one compiled-schema string — *"If true, hook runs in background without blocking"* **[bin]** — and
**three things about it are unobserved**:

1. whether an async hook's **exit status is read at all** (if not, §5's exit-2 hazard cannot fire for
   it);
2. whether an async hook's exit 2 is routed to `blockingError` and subject to the **block cap**;
3. whether an async hook receives the **same payload**, in particular a populated
   `last_assistant_message`.

**None of these was answered by the `Stop` probe that ran**, and §5's invariant is specified so that
it holds **either way** rather than resting on `async` making the hazard moot. **This is the thinnest
link in the whole evidence chain, which is why nothing is built on it.**

**Recommendation, stated as a preference and not a requirement:** declare `async: true` in
`hooks/hooks.json` as a **belt** — it is free and it makes the intent visible to anyone reading the
wiring — while the **guarantee** stays with detachment. Do not specify both and implement neither,
and do not assume either covers the other. If `async` is declared, nothing else in this spec changes.

**Watchdog precedent to copy, not reinvent:** `_llm_run_bounded` in `providers.sh:146-172` — TERM,
`sleep 2`, KILL, with the killed child's status mapped to a timeout code and `return 0` regardless.
There is **no `timeout(1)` on macOS**, so a subprocess needs its own watchdog (#12). **[repo]**

**OPEN, and it matters for a detached child:** whether the harness kills the hook's **process group**
when the hook's declared timeout expires or the turn ends. If it does, a detached child could be
killed mid-utterance. `setsid`-style detachment would prevent it. **Unobserved**; closing condition is
one detached-sleep-and-check probe.

---

## 7. LOCKED — `Stop` does not fire for subagents

**Confirmed empirically, not only from the ternary.** During the captured turn a delegated subagent
completed, and there was **one capture, `hook_event_name: "Stop"`, and none for the subagent's
completion**. **[obs]**

The mechanism agrees: `Stop` and `SubagentStop` are chosen by a single ternary on the agent id
*before* the config gate, and the gate is consulted with the **resolved** event name — so a `Stop`
entry in `hooks/hooks.json` is never asked for on the subagent path. The docs' "converts a `Stop`
hook here to `SubagentStop`" applies to hooks declared in **a subagent's own frontmatter**, not to a
plugin's `hooks.json`. **[bin]**

**This matters for this repo specifically.** The work here runs many subagents. A speech hook that
announced every subagent's final message would talk continuously through exactly the work that was
delegated so nobody had to watch it. That outcome arrives **for free** — not from a filter this
plugin writes and maintains, but because the event never fires.

**Two negative requirements, stated because a reader who sees no filter will add one:**

- **Never add a `SubagentStop` entry to `hooks/hooks.json`.** It is the one edit that turns free
  silence into continuous chatter.
- **Do not write a subagent filter.** There is nothing to filter. An `agent_id`-absent check is
  available (`agent_id` is documented "Absent for the main thread") and on `Stop` it is **redundant**;
  ship it only with a comment saying it is redundant and why it is there.

One footnote so the claim is not overstated: a narrow bypass exists for the built-in `web-fetch`
subagent where the *config gate* is skipped — but `hook_event_name` is still `SubagentStop` on that
path, so it is not a `Stop` leak. **[bin]**, `[inferred]` from control flow at source.

---

## 8. LOCKED — `background_tasks`: suppress the announcement while a subagent runs

**Default: when `background_tasks` contains an entry with `status: "running"`, stay silent.**

**Why this is a default and not a finding.** The probe caught exactly the motivating case: the
captured `Stop` carried one entry, `{id, type: "subagent", status: "running", description,
agent_type}`, for an agent still running when the turn ended **[obs]** — a case where "done" would
have been the wrong thing to say to someone who had walked away from the screen. The binary describes
the field as existing to let hooks distinguish *"session is done"* from *"session is paused waiting
for background work to wake it"* **[bin]**, which is precisely the distinction that decides whether a
done-announcement is **true**.

**It is cheap to reverse — one condition — and it is marked a default rather than a finding because
one question behind it is unanswered: whether `Stop` fires again when the woken session finishes.**
If it does, suppression costs nothing (the announcement arrives later). If it does not, suppression
**loses the announcement entirely**, which is the worst outcome available. **Unobserved.** Closing
condition: one turn that ends with a background task in flight, followed by that task waking the
session, with the payload capture still installed.

**Rejected, and worth recording as rejected:** a *distinct utterance* for "turn over, still waiting
on background work". That would be **text the plugin authored** rather than a rewrite of Claude's — a
new category nothing in #1 sanctions. If it is ever wanted it is a scope change, not a tweak.

**`session_crons` is read by nothing.** It is in the payload **[obs]** and has not been looked at.
Plausibly the same family of question; possibly unrelated. **OPEN**, and no behaviour depends on it.

---

## 9. LOCKED — there is no length gate, and `CLAUDISH_SPEAK_MIN_CHARS` does not ship

**No character threshold fits the verdicts.** The best single threshold is **~335 chars at 3 errors
out of 24** decided items, and it scores that only by silencing all three *shorter* items marked
worth speaking (`ack07`, `ack08`, `s15`). **Duration fails too**: `fct06` at **14.78 s** is "not
worth" while `ack07` at **10.50 s** is "worth". The duration law
(`0.355 + 0.05488 × phonemes`, R² 0.9950) still holds — it just predicts the wrong thing.
**[heard]** #10.

**What the listener was actually judging**, in their own words on `fct06`:

> "I feel like I'm selecting here for whether it's a status update or a final message from claude.
> From these small bits it feels like it would only make sense to verbalize the final message, but
> maybe if there are way longer updates that would also make sense."

**So the discriminator is status update vs final message — and `Stop` *is* that discriminator.** The
trigger implements the rule directly; no threshold is needed to approximate it.

**`CLAUDISH_SPEAK_MIN_CHARS` is specified as deliberately absent** — not present-and-zero, which
reads as a supported knob nobody has justified. #1's planned surface lists it; §14 proposes striking
it.

**The listener's aside is recorded as the reason it might come back, with its cost visible.** A
secondary escape hatch letting a long *intermediate* message speak is **not a knob — it is a second
trigger.** `Stop` fires once, at the end; intermediate messages are visible only on
`MessageDisplay`, the hook #10 just took speech *off*. Adding the hatch brings back everything the
move to `Stop` removed: chunk-level `final`, the defer-and-cancel ambiguity, and a synthesis call on
the display critical path. **And the evidence for it is one sentence about a shape the listener was
never played** — no audition item tested a long intermediate message. **If it is wanted, the honest
next step is an audition of long intermediate messages, not a number.**

---

## 10. The implementation surface — a specification, not code

### 10.1 LOCKED — configuration

Mirroring the existing idiom exactly: `CLAUDISH_*`, read from the environment with a safe default,
plus a **flag file** for anything that must change mid-session — because **`CLAUDISH_*` values are
frozen at session launch** (`rewrite.sh:58-60`; the `CLAUDISH_OFF_FILE` check at `:61` exists for
precisely this reason).

| variable | default | status | note |
| --- | --- | --- | --- |
| `CLAUDISH_SPEAK` | **`0`** | LOCKED | off by default (§11). The only var whose default is "feature off". |
| `CLAUDISH_SPEAK_OFF_FILE` | `$HOME/.claude/claudish-speak-off` | LOCKED | runtime mute, **separate from `claudish-off`**, so "stop talking, keep simplifying" is one `touch`. Checked fresh every invocation. |
| `CLAUDISH_VOICE` | **`bf_emma`** | LOCKED | §4 |
| `CLAUDISH_PLAYER` | `afplay` | LOCKED | macOS verified; `sox`/`ffmpeg` not needed, `wav` plays directly |
| `CLAUDISH_SPEAK_TIMEOUT` | **`30`** | LOCKED | bounds the **synthesis child**, not the hook. #9's hard ceiling. Must stay under §10.4's declared hook timeout only in the non-detached case — see the trap below. |
| `KOKORO_ROOT` | `$HOME/.local/share/kokoro` | LOCKED | already the name `bench/bench:9` uses; do not invent a second one |
| `CLAUDISH_SPEAK_MIN_CHARS` | — | **LOCKED ABSENT** | §9. Do not ship it. |
| `CLAUDISH_TTS_URL` | — | **LOCKED ABSENT** | #5 **declined the server branch on measured evidence**. There is no HTTP endpoint to point at. #11's "lazy server start" question is therefore void as posed and reappears as §10.5. |
| `CLAUDISH_DEBUG` | `0` | LOCKED | reuse `rewrite.sh:73`'s var and its `$BUF_ROOT/debug.log` sink. Do not add a second debug flag. |

**The timeout-hint trap, inherited from #14 and to be avoided by construction.** `rewrite.sh`'s
timeout hint tells the user to raise `CLAUDISH_TIMEOUT` without mentioning that the hook's own
declared timeout in `hooks/hooks.json` is the real ceiling. **Any speech-timeout message must name
both** the env var and the declared hook timeout, and say that moving the latter means editing a
plugin file. **[repo]**, `provider-switch-traps.md`.

**The cross-provider trap, likewise inherited.** `CLAUDISH_MODEL` is provider-agnostic, so a value
set for one provider silently carries into another. **If speech ever gains a second backend, scope
its override per backend** rather than assuming "unset is safe".

### 10.2 LOCKED — files

| path | owner | contents |
| --- | --- | --- |
| `speak.sh` (plugin root, beside `rewrite.sh`) | new | the `Stop` hook. Bash, `curl`/`jq` idiom, no `set` options (§5). |
| `$HOME/.claude/claudish-speak-off` | user | runtime mute flag; existence is the whole signal |
| `$BUF_ROOT/<session_id>/speak/` | `rewrite.sh` writes, `speak.sh` reads | §3.1. Depth-2 directory so `rewrite.sh:117`'s existing sweep reclaims it. |
| `$BUF_ROOT/<session_id>/speak/{rewrite,source,prompt_id}` | `rewrite.sh` writes | §3.1 |
| `$BUF_ROOT/<session_id>/speak/{spoken,pid}` | `speak.sh` writes | dedup hash (§5.1) and the preemption PID (§10.6) |

`BUF_ROOT` is **not** redefined in `speak.sh` as a new constant with a new default — it is the same
`"${TMPDIR:-/tmp}/claudish-to-english"` string as `rewrite.sh:69`, and the two must not be able to
drift. A shared snippet or a literal with a comment pointing at `rewrite.sh:69`; the spec does not
care which, only that drift is impossible by inspection.

### 10.3 LOCKED — order of operations inside `speak.sh`

Specified as an order because the cheap rejections must precede everything, for §11's reason.

1. `CLAUDISH_SPEAK` is `1`, else `exit 0`. **Before reading stdin.**
2. `CLAUDISH_SPEAK_OFF_FILE` does not exist, else `exit 0`.
3. `jq` present, else `exit 0`.
4. Read the payload; `exit 0` if empty.
5. **Not a `stop_hook_active` check** — see §5.1; that flag is read for no behaviour. Dedup happens at
   step 8b instead, on the text.
6. `background_tasks` has no `status: "running"` entry, else `exit 0` (§8).
7. `last_assistant_message` present and non-empty, else `exit 0` (§2).
8. Resolve the text via §3.5's decision table; `exit 0` if the table says silent.
8b. **Dedup on the resolved text** — hash it, compare against `speak/spoken`, `exit 0` if equal, else
   write the new hash (§5.1).
9. Fire the detached speech child (§6) and `exit 0` **without waiting**.

Steps 1–2 are the whole of the off-by-default guarantee (§11), and step 9 is the whole of the
non-blocking guarantee (§6).

**Steps 1–2 must precede step 3, and the ordering is load-bearing rather than stylistic.** Putting the
enable check after `jq` would make a speech-disabled user's turn depend on `jq` being installed and
would pay for payload parsing they never asked for — which contradicts §11's guarantee that the
bash-only rewrite path is unaffected for users who never enable speech. `rewrite.sh` already gets this
right and is the precedent: `[ "$ENABLED" = "1" ] || pass_through` at `rewrite.sh:100` comes **before**
`command -v jq` at `:101`. **[repo]** (This ordering error was present in the draft this spec replaces
and was caught in review of PR #19.)

### 10.4 LOCKED — the `hooks/hooks.json` entry

A `Stop` block alongside the existing `MessageDisplay` and `PostToolUse` blocks:

- `"command": "\"${CLAUDE_PLUGIN_ROOT}\"/speak.sh"` — same quoting as `hooks.json:7`.
- `"timeout": 10`. **Deliberately small.** The hook forks and exits; it never waits for synthesis or
  playback. A generous timeout here would only mask a violation of §6. It is a plugin choice, not a
  harness bound — the harness default on `Stop` is 600 s.
- `async: true` optional, per §6, changing nothing else.
- **No `matcher`**, and **no `SubagentStop` block, ever** (§7).

### 10.5 OPEN — the worker lifecycle, and it is the biggest gap in this spec

**LOCKED:** the synthesis path is #5's **resident, torch-free `kokoro-onnx` worker** at
`$KOKORO_ROOT`, addressed through `$KOKORO_ROOT/venv/bin/python` — the same resolution `bench/bench:9-10`
already performs. The server branch is **declined on measured evidence** (#5), so there is no HTTP
transport and no port. Kokoro is driven as `kokoro.create(text, ...)` with **`is_phonemes=False`** —
never `True` — so `kokoro-onnx` phonemises through espeak and misaki/spaCy are not runtime
dependencies at all (#1).

**OPEN, and everything about the latency claim depends on it:** *what keeps the worker resident, who
starts it, and what a second concurrent hook does.*

- **A fresh interpreter per turn does not meet the budget.** §4's 0.86 s median **excludes model
  load** (0.53–0.83 s) and is a **warm** number; #6 measured the cold first synthesis at **3.93 s
  TTFA, over the 3 s line**. So "spawn python, synthesise, exit" is specified as **insufficient**,
  not merely slower.
- **#5's ~4.9 s post-wake cold start is larger than the entire warm first-sentence budget**, and
  pipelining does not remove it — it **concentrates** the remaining risk there. Warm-up-on-wake
  versus a late first utterance is #11's choice and this spec does not make it.
- The sub-questions #11's body asked about a server reappear unchanged for a resident worker: who
  starts it, how a second concurrent hook avoids starting a second one, and what happens when a cold
  start outruns the timeout.

**Closing condition: a measurement, not a decision.** Pick a residency mechanism, then measure TTFA
end-to-end **from the hook**, cold and warm, on `bf_emma`, against the 3 s line. Until that exists,
**§4's TTFA table describes the bench harness's process, not this hook's.** That is the single place
where this spec would otherwise claim more than has been measured.

### 10.6 LOCKED — preemption and barge-in

- **A newer message kills stale playback.** The speaker lock and PID file live in the same per-session
  scratch: `$BUF_ROOT/<session_id>/speak/pid`, written by the speech child, read and `kill`ed by the
  next invocation before it starts. Same directory, same sweep, no new lifecycle.
- **Cutting playback on a new prompt** requires a hook event that fires on prompt submission.
  `UserPromptSubmit` is the candidate (harness default timeout 30 s, **[bin]**), and this spec does
  **not** add it — a third hook entry is a scope increase, and `Stop`-driven preemption already
  covers the common case (the next turn's `Stop` kills the previous playback). **OPEN**, deliberately
  deferred, with the cost stated: until it exists, a long utterance keeps talking after you start
  typing.
- **Escape / interrupt barge-in stays out of scope**, as #1 already records, because which events
  Claude Code fires on interrupt is unknown. Related and also unknown: **whether `Stop` fires on user
  interrupt at all**, and what the separate **`StopFailure`** event (carrying `error`,
  `error_details` and its own `last_assistant_message`, **[bin]**) does. Neither has been looked at.
  **OPEN.**

### 10.7 LOCKED — failure paths, all silent and harmless by construction

Every row exits 0 and speaks nothing. None writes to the screen.

| failure | behaviour |
| --- | --- |
| speech disabled, or off-file present | `exit 0` before reading stdin |
| `jq` missing, payload unparseable, `last_assistant_message` absent | `exit 0` |
| no rewrite buffered and the message is above the threshold | `exit 0` (§3.5) |
| buffered rewrite does not match this turn | `exit 0` — silence beats a confident wrong utterance |
| disqualifying hazard class on the raw path | `exit 0` |
| Kokoro venv missing at `$KOKORO_ROOT` | `exit 0`. **No notice** — see below |
| synthesis exceeds `CLAUDISH_SPEAK_TIMEOUT` | watchdog TERM→KILL (`providers.sh:146-172` pattern); `exit 0` |
| `kokoro-onnx` raises (including the 510-phoneme `IndexError`) | child dies; `exit 0` |
| player missing, or playback fails | `exit 0` |
| background task running | `exit 0` (§8) |
| resolved text identical to the last spoken text | `exit 0` (§5.1). **Not** a `stop_hook_active` check |
| `jq` given an unreadable filename (`--rawfile`) | guarded, so its **exit 2** cannot escape (§5); `exit 0` |
| `jq` filter malformed, or stdin unparseable | exits 3 / 5 — non-blocking; guarded anyway; `exit 0` |

**On-screen surfacing of speech failures: LOCKED as absent, and this is a real cost.** The plugin has
a `CLAUDISH_NOTICE` idiom for once-per-session provider warnings (`rewrite.sh:206-225`), but that
idiom works by **appending to `displayContent`** — a `MessageDisplay` affordance the `Stop` hook does
not have, and §1 forbids it from touching the screen. So a misconfigured speech setup is **silent in
both senses**: no audio and no explanation. `CLAUDISH_DEBUG=1` and `$BUF_ROOT/debug.log` are the only
diagnostic. **Stated rather than hidden**; #1's "Not yet specified" entry on this question is thereby
answered *no*, not left open.

### 10.8 LOCKED — README changes

The plugin documents its configuration in depth, so the surface above lands in `README.md`:

- a **Speech** section: what it does, that it is **off by default**, and the one-line enable.
- the §10.1 table verbatim, including the two `LOCKED ABSENT` rows **with their reasons** — a reader
  who wants a length knob should find out here that there deliberately is not one.
- **prerequisites**: macOS, `afplay`, and #5's provisioned venv at `$KOKORO_ROOT`. **`espeak-ng` is
  not a prerequisite** — verified on this machine; the `libespeak-ng.dylib` ships inside the
  `espeakng-loader` wheel.
- the **mute-vs-disable** distinction: `claudish-speak-off` stops speech and keeps rewriting;
  `claudish-off` stops both.
- the residual cost of §11, in the user's own terms: one extra process per turn when speech is off.
- **no promise of Linux or Windows playback.** The player stays configurable with documented
  alternatives; only macOS is verified.

---

## 11. LOCKED — "off by default" is now enforced inside the hook

Before the two-hook split, speech was code *inside* `rewrite.sh`, so off-by-default cost nothing: the
branch was not taken. **After the split the plugin ships a second hook entry, and
`hooks/hooks.json` is not conditional** — a `Stop` block fires **on every turn, for every user of the
plugin, whether or not they ever enable speech.**

Therefore:

- the guarantee is enforced **inside** `speak.sh`: `CLAUDISH_SPEAK` and the runtime off-file are
  checked and `exit 0` taken **as the very first thing**, before `jq`, before reading stdin (§10.3);
  and
- **the residual cost is stated, not hidden: one bash process spawned per turn for users who never
  turn speech on.** It is small. It is new. It is not zero.

---

## 12. LOCKED — the standing constraints #10 and #13 do not disturb

| constraint | status |
| --- | --- |
| **macOS only** | unaffected. Nothing about `Stop` is platform-specific; `afplay` unchanged; `espeak-ng` still not a prerequisite; `sox`/`ffmpeg` still not needed. |
| **`kokoro-onnx` `IndexError` at 510 phonemes** | unaffected. A synthesis-layer constraint downstream of the trigger. The sanitizer must **never** strip terminal punctuation, and `\n` must be **converted into** terminal punctuation rather than preserved. |
| **espeak G2P, `is_phonemes=False`** | unaffected. misaki, spaCy and `en_core_web_sm` are not runtime dependencies. **Never install `misaki[en]`.** |
| **No pronunciation-override mechanism exists on the espeak path** | unaffected. `[text](/phonemes/)`, `[[...]]` and SSML are each read aloud as literal words; the `[...](...)` form is the worst-sounding input measured. **Never emit it** (rule M, a prohibition). |
| **Fail-open is inviolable** | in force, strengthened in reason, wording generalised — §5. |
| **This fork is not upstreamed** | unaffected. |

---

## 13. The full OPEN list, with closing conditions

Nothing below is papered over to make the spec look finished.

| # | open question | what closes it | blocks shipping? |
| --- | --- | --- | --- |
| 1 | **The settled sanitizer combination has never been synthesized, and now contains a rule that does not exist** (§4.2) | implement conditional boundary **B′** (§4.1), register the combination as one variant, one confirmation listen | **yes** |
| 2 | **The worker residency mechanism** (§10.5) | pick one, then measure TTFA from the hook, cold and warm, against 3 s | **yes** — §4's latency claim rests on it |
| 3 | **The §3.2 handoff match rate** | log both strings for ~20 turns; count exact matches | **yes** — a low rate silences the feature |
| 4 | Whether `MessageDisplay` carries `prompt_id` (§3.2) | one payload-dump probe on `MessageDisplay` | no — the hash path works without it |
| 5 | **Axis 2's cutoff position is unaudited between 4 and 7 items** (§4.1) — the rule is LOCKED, the exact cutoff is the listener's call | a corpus item in the 4–7 band, then one listen | no — the rule ships |
| 6 | `flag-pause` has no real carrier (§4.3) | a capture with a bare flag outside backticks | no — measured no-op today |
| 7 | Whether `Stop` fires again after a background task wakes the session (§8) | one capture across a wake | no — the default is reversible |
| 8 | The three `async: true` unknowns (§6) | one probe; **the `Stop` probe did not cover them** | no — nothing is built on `async` |
| 9 | Whether the harness kills a hook's process group (§6) | one detached-sleep-and-check probe | no, but it would explain truncated audio |
| 10 | Whether `Stop` fires on user interrupt; what `StopFailure` does (§10.6) | inspection plus one probe | no |
| 11 | Barge-in on a new prompt (§10.6) | decide whether a `UserPromptSubmit` entry is in scope | no |
| 12 | Warm-up-on-wake vs a late first utterance (§10.5) | a listening call once residency exists | no |
| 13 | Deeper leading-dot paths (`.github/workflows/ci.yml`) unauditioned | a corpus item | no |
| 14 | `session_crons` has not been looked at (§8) | one look | no |
| 15 | Whether any absolute hook-timeout ceiling exists (§6) | a wider read than the two call sites checked — **not** an argument from `hooks.json:21`, since config acceptance is not runtime enforcement | no |
| 16 | **CLOSED 2026-08-25 — observed.** This row read *"the exit-2 block mechanics have never been observed (§5) … the block cap, the `blockingError` routing and the post-cap override are still schema reading."* A driven probe has since made a `Stop` hook exit 2 and counted the fires, and all three now have a wire observation behind them **[obs]** — the schema reading was off by one (§5, THIRD CORRECTION). **Still unobserved, and named there rather than here:** `async: true`, `SubagentStop`, a raised or disabled cap, and two blocking hooks at once | closed — [`stop-hook-block-mechanics.md`](stop-hook-block-mechanics.md), four driven runs, 28 captured fires | no — the invariant was specified to hold regardless, and does |

**Three of these — 1, 2, 3 — block shipping.** All three are cheap: one listen, one measurement, one
log. None needs a new decision from the listener.

---

## 14. Proposed amendments to #1 — **NOT applied**

A single writer owns #1's body; nothing below has been written to it. The two-hook split, the
fail-open invariant and the off-by-default enforcement are **already in #1** and are not repeated.

### 14a. Replace the third **Out of scope** bullet — the narrowing

Current text:

> - **Speaking raw, un-rewritten Claudish** — on the fail-open path or when the provider is down.
>   Unreadable text is less listenable, not more; speech only ever carries a successful plain-English
>   rewrite.

Proposed replacement:

> - **Speaking raw text that carries a disqualifying hazard class, and speaking raw text on any path
>   where a rewrite was attempted and failed.** **NARROWED 2026-08-25, deliberately, by the listener
>   — not an oversight.** The original bullet banned raw Claudish outright, and its stated reason was
>   that *"unreadable text is less listenable"* — a claim about **hazards**, not about provenance.
>   Held literally it was unsatisfiable: `rewrite.sh:147` never rewrites below
>   `CLAUDISH_MIN_CHARS` (200), so below the gate there is **no rewrite to carry** — and #10's
>   verdicts mark a 177-character acknowledgement (`ack07`, 10.50 s) **worth speaking**. So the rule
>   now bans the two cases the reason actually covers: **(a)** raw text carrying a class whose
>   settled sanitizer remedy is **lossy** — `MD-FENCE`, `MD-FENCE-MULTI`, `URL`, `PATH-SLASH`,
>   `PATH-ABS`, `PATH-TILDE`, `PATH-DOTDIR`, `EMOJI`, where the listener would hear a summary of
>   something they cannot see; and **(b)** raw text on the **fail-open path** — at or above
>   `CLAUDISH_MIN_CHARS`, where a rewrite was due and the provider timed out, errored or returned
>   empty. Clean short messages are spoken raw, sanitized. Supporting evidence: a rewrite would not
>   have shortened the listening anyway (below ~600 raw chars the rewrite's **audio** is longer, in
>   seven of eight real pairs), and raw short text cannot crash the synthesiser (largest batch 265
>   phonemes against 510). The gate is **implementable, not a runtime judgement** — the same eight
>   detection expressions `corpus/bin/detect-hazards.sh` already uses.
>   → [`docs/decisions/speech-integration-spec.md`](https://github.com/FrancisBehnen/claudish-to-spoken-english/blob/main/docs/decisions/speech-integration-spec.md) §3

### 14b. Amend the fail-open bullet in **Standing constraints** — the shell-options correction

The bullet reads *"Exit 0 on every path, no `set -e`, nothing that lets an unset variable or a `jq`
failure reach the exit status."* **`rewrite.sh:55` is `set -uo pipefail`**, so "no `set -e`"
understates the requirement. Proposed replacement for that sentence:

> Exit 0 on every path. **`speak.sh` sets no shell options at all** — not `-e`, and **not
> `-u`/`-o pipefail` either, despite `rewrite.sh:55` setting them**: `set -u` makes an unset
> expansion fatal and `pipefail` promotes a mid-pipeline failure to the exit status, and
> `rewrite.sh` survives both only because every pipeline is guarded with `|| pass_through` **and**
> because a non-zero exit is harmless on `MessageDisplay`. Neither protection transfers to `Stop` —
> though the honest reason to drop the options is **robustness, not turn-blocking**: measured on this
> machine, `set -u` on an unset variable exits **1**, which the resolver classes non-blocking. The two
> routes that actually reach the blocking **2** are a **bash syntax error** in the hook and **`jq`
> handed a bad option or an unreadable file** (`rewrite.sh:87`'s `--rawfile` shape). So `speak.sh`
> guards every `jq` that takes a filename, and `bash -n` gates the file.

**One further correction #1 will want.** #1's `#10` bullet says *"`jq` exits **2** on a malformed
filter, so a hook parsing stdin with `jq` … genuinely can block a turn by accident."* **Measured on
`jq-1.7.1-apple`, a malformed filter exits 3, not 2** (unparseable JSON input exits 5). The
conclusion survives — two other exit-2 routes exist and one of them is worse — but the cited
mechanism should be replaced with the measured table in §5, since the current wording would send an
implementer to guard the wrong thing.

**Otherwise #1 already carries the exit-2 correction** in the `#10` bullet and the `stop_hook_active`
bullet in *Standing constraints*, and this document is written to match that wording rather than
restate it differently. **This amendment is the shell-options sentence plus the `jq`-code fix.**

### 14c. Amend the planned config surface in **Standing constraints**

The surface lists `CLAUDISH_SPEAK_MIN_CHARS` and `CLAUDISH_TTS_URL`. Proposed replacement for that
sentence:

> Planned surface: `CLAUDISH_SPEAK`, `CLAUDISH_SPEAK_OFF_FILE`, `CLAUDISH_VOICE`,
> `CLAUDISH_SPEAK_TIMEOUT`, `CLAUDISH_PLAYER`, and `KOKORO_ROOT` (the name `bench/bench:9` already
> uses). **Two of the originally planned vars are specified ABSENT**: `CLAUDISH_SPEAK_MIN_CHARS`,
> because no character or duration threshold fits the verdicts and `Stop` *is* the discriminator; and
> `CLAUDISH_TTS_URL`, because #5 declined the server branch on measured evidence, so there is no HTTP
> endpoint to point at.

### 14d. Resolve two **Not yet specified** entries

- **"What the speech hook actually speaks"** is now specified — §3. Replace with a one-line pointer.
- **"Whether a non-empty `background_tasks` should suppress the announcement"** now has a **default**
  — suppress while an entry is `status: "running"` — with one question still open behind it (whether
  `Stop` fires again after the wake). Replace with that, marked reversible.
- **"On-screen surfacing of speech failures"** is now answered **no**, with a reason: the
  `CLAUDISH_NOTICE` idiom works by appending to `displayContent`, which is a `MessageDisplay`
  affordance the `Stop` hook does not have and is forbidden from using. Move it from open to decided.

### 14e. Axis 2 is closed — the `#8`/`#13` bullets say it is not

Both bullets record axis 2 as *"explicitly NOT settled"* / *"stays deliberately undecided"*. It is now
**closed** as a **conditional** rule (§4.1): `,` at ≤ 3 items, `.` at ≥ 4, decided by the listener
2026-08-25. The bullets should say so, with the two qualifications: **the cutoff position is the
listener's call and the 4–7 item band is unaudited**, and **no registered sanitizer implements a
conditional boundary**, so rule B′ has to be built before the settled set can be synthesized at all.

**`docs/decisions/sanitizer-audition.md` is deliberately NOT amended here.** That file is already
modified on `task/audition-13-followup-rules` (PR #18); editing it from this branch would create a
conflict between #18 and #19. Axis 2's closure is recorded in this document only, and the #8 doc of
record should be amended after #18 merges.

### 14f. One factual correction to the **#10** bullet in *Decisions so far*

The bullet says *"the rewrite **adds seconds** below ~600 raw chars and only pays for itself above
~1600"*. That is true of **spoken audio duration**, not of latency, and nine of the twelve pairs are
the duration law's predictions rather than stopwatch readings (only `r01`, `r03`, `r06` were
synthesised). Suggested wording: *"the rewrite's **audio is longer** below ~600 raw chars and only
gets shorter above ~1600 (three pairs measured, nine predicted by the duration law)"*.

---

## 15. Where this spec is weakest

Stated so a reviewer can attack the right parts.

- **§10.5 is the real gap, and §4's headline number depends on it.** "Median 0.86 s TTFA" is a warm,
  model-already-loaded, bench-harness number. No TTFA has ever been measured **from a hook**. If the
  worker is not resident, the honest figure is #6's cold **3.93 s** — a failure against the 3 s
  line — and the spec would be claiming a budget it does not meet.
- **The hazard gate has never fired.** Zero of the sixteen measured sub-threshold items carry a
  disqualifying class (§3.4). Its cost is measured at zero and so is its benefit. It is reasoning
  about a future, not a fix for an observed defect.
- **The cut line between disqualifying and harmless is my refinement of the brief's criterion, not
  the listener's decision.** The brief said *"a class a settled rule exists to fix"*, which yields
  **23** classes; this spec uses *"a class whose settled remedy is lossy"*, which yields **8**. The
  fifteen classes the two readings disagree about are named in §3.4 with the property that separates
  them. **The narrow reading passes `ack07` and so does the broad one**, so the motivating case does
  not decide it — but the broad reading silences 8 of the 16 short items, which would re-create by
  the back door the outcome the narrowing was meant to avoid. **This is the one place the spec should
  be checked against the listener's intent rather than trusted.**
- **`EMOJI` in the disqualifying list is a judgement call**, and the weakest member (§3.4).
- **§3.2's match rate is unmeasured.** The mechanism is sound and the failure direction is safe, but
  nobody has compared `last_assistant_message` against a buffered original on a real turn. If the
  content-block join differs from the delta concatenation more often than rarely, the feature is
  quiet for a reason no user will be able to diagnose.
- **`prompt_id` on `MessageDisplay` is an assumption the brief carried and the evidence does not.**
  It exists on `Stop` **[obs]**; nothing has ever observed a `MessageDisplay` payload.
- **`async: true` remains the thinnest claim about the harness anywhere in this project** — one
  compiled-schema string. §6 is written so that nothing depends on it, which is the mitigation, not
  a resolution.
- **Axis 2's conditional rule rests on three verdicts, one of which is a tie, and its cutoff is
  unaudited.** The item-count reading is the most plausible account of three data points, not a
  measurement, and **no wav exists between 4 and 7 items** — the corpus jumps 3 → 8, so the cutoff is
  the listener's placement inside a gap (§4.1). What *is* solid and verified in code: the variant
  could not have expressed the distinction (`\n+`, one boundary character), and neither boundary
  carries crash-safety weight. The most likely error is on **paragraph** runs, where the only
  evidence is the tie.
- **`path-short-nolead` rests on one genuinely combinational pair** (`s12`), and **`flag-pause` on
  four synthetic ones**. Both are adopted undefeated; neither margin is as thick as "4–0" reads.
- **`MD-FENCE-MULTI` has zero real carriers**, so `cb-count`'s line-count wording is justified by
  fixtures the corpus builder wrote.
- **Everything about the raw path above 200 characters is unmeasured**, by construction — §3.5 never
  sends long raw text to synthesis, and if that ever changes the phoneme-batch measurement is owed
  first.
- **§5 has now been wrong four times, and is the section to re-check hardest.** It locked "any
  non-zero exit blocks the turn" (false — only 2 does); it specified a `stop_hook_active` dedupe rule
  that was **inverted** (it would have spoken the rejected answer and suppressed the real one); the
  *replacement* mechanism it was handed — "`jq` exits 2 on a malformed filter" — is **also false**
  on this machine (that is a 3); and it read the block cap's default as the invocation count, which is
  off by one, **then priced the loop in utterances when the number that scales counts invocations**
  (§5, THIRD and FOURTH CORRECTIONS). All four are corrected in place. **Two came from outside this
  document** (a review pass on PR #17); the third was caught by running `jq` rather than quoting it;
  the fourth by a review of the PR that fixed the third. **The conclusion has been stable across all
  four corrections while every stated reason for it changed** — which is either reassuring or a sign
  that the conclusion is being defended rather than derived, and a reviewer should decide which.
  **The fourth is the one to learn from**: it was not a misreading of the binary but a misreading of
  what the binary's number *counted*, and it survived one correction aimed straight at it.
- **The block mechanics are no longer unobserved — and observing them falsified this bullet.** It used
  to read: *"the block cap, the `blockingError` routing and the post-cap override are
  schema-and-`strings` reading. Nobody has made a `Stop` hook exit 2 and counted the re-fires."*
  Somebody has. Four driven runs captured 28 fires, so all three are **[obs]**, and the cap reading
  was off by one — nine invocations, not eight (§13 row 16,
  [`stop-hook-block-mechanics.md`](stop-hook-block-mechanics.md)). **What remains unobserved is
  narrower and is named in that document:** `async: true`, `SubagentStop`, a raised or disabled cap,
  and two blocking hooks at once. None of it is load-bearing here — §6 is written to lean on `async`
  for nothing — but the `async: true` residue is the same gap **§13 row 8** already carries, and
  closing row 16 did not close row 8.
