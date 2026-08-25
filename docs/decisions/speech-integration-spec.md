# The speech integration spec

**This is the lock for [#11](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/11)**
— the destination artifact of the [Kokoro speech map (#1)](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/1).
Written 2026-08-25 against Claude Code **2.1.245**, and **revised the same day by the integration pass
that folded in four parallel measurements** — see *Then four measurements landed* below. It supersedes
`speech-trigger-spec-update.draft.md`, which was the checklist this was written from.

**What this document is.** A specification an implementer can build from in one session without
re-deriving a decision. Every section is marked **LOCKED** (decided, with the evidence that decided
it) or **OPEN** (undecided, with what would close it). Nothing is marked LOCKED on the strength of a
schema reading alone.

**What this document is not.** It is not an implementation and it does not contain one. **`speak.sh`
still does not exist**, and no hook was written or modified by this document or by the integration pass:
`rewrite.sh`, `rewrite-md.sh`, `providers.sh` and `hooks/` are unchanged, and `grep -n 'speak'
rewrite.sh` returns nothing across all 245 lines **[repo]**. The section-10 "implementation surface" is
a specification of names, paths and defaults — not code.

**What HAS changed under `bench/` since this document was first written, because a reader needs to know
which claims now have code behind them.** `bench/sanitizers.py` gained **rule B′** and the registered
`settled` variant (PR #24), which is what made §4.2's confirmation listen possible at all; the registry
is **28** sanitizers **[repo]**. That is the only shipped code any of this rests on. **Nothing in this
integration pass touched `bench/` or `corpus/`**, `COND_CUTOFF` stays at **4** (§13 row 5), and the
trailing-slash rule of §13 row 18 stays **unimplemented on purpose**. No audio was synthesised and no
LLM was called by any of it.

**Two decisions unblocked this lock, both made by the listener on 2026-08-25.**

1. **§3 — below `CLAUDISH_MIN_CHARS`, where no rewrite exists, the hook speaks the raw text, gated on
   hazard classes.** That **narrows a stated out-of-scope boundary** in #1. It is a deliberate
   narrowing, not an oversight, and §14a carries the replacement text for #1's bullet.
2. **§4.1 — axis 2 is closed as a *conditional* boundary**: `,` for runs of 3 items or fewer, `.` for
   4 or more. It had been carried as "deliberately undecided inside the noise floor"; that framing
   was wrong, and correcting it made the axis decidable.

**Then four measurements landed on 2026-08-25 and this revision is the pass that folds them in.** Each
was taken by a separate agent working a separate blocker, each was forbidden from editing this file so
that four writers could not collide on it, and each carried its proposed replacement text inside its
own decision doc. What they changed, in the order the sections appear:

| document | what it settles here | what it does **not** settle |
| --- | --- | --- |
| [`handoff-match-rate.md`](handoff-match-rate.md) | §3.2's key is **LOCKED** at the content hash — the rate is 35/35 byte-identical. And the finding that outranks it: **`Stop` does not wait for `MessageDisplay`**, so §3.5 adopts a **bounded wait** (§3.5.1) | the wait has never been implemented or measured end-to-end. §13 row 17 |
| [`settled-set-audition.md`](settled-set-audition.md) | §4.2 **closes** — the settled combination was built, registered and heard 9–0 blind. §4.1 clause 3 is corrected from **segments** to **boundaries** | `COND_CUTOFF`'s position, now *contradicted* at 4 (§13 row 5); a slash-terminated path, which has no rule at all (§13 row 18); and §4.3, which is **false as written** |
| [`worker-residency.md`](worker-residency.md) | §10.5 **closes** — a lazy, self-electing, per-session resident worker, with the first TTFA ever measured from a hook. §10.6 gains the two clauses that make its own rule true | ~~three measurements the mechanism's correctness clauses rest on are [inferred]~~ **two of the three have since been run and falsified four clauses** — [`preemption-and-lock-protocol.md`](preemption-and-lock-protocol.md). What is left from this file is the bench-to-hook gap (§13 row 22) |
| [`stop-hook-block-mechanics.md`](stop-hook-block-mechanics.md) | §5's cap is **nine invocations**, and nine is never an utterance count | `async: true`, `SubagentStop`, a raised cap, and two blocking hooks at once |
| [`preemption-and-lock-protocol.md`](preemption-and-lock-protocol.md) — **a fifth, later than the other four** | §13 rows 20 and 21 are **measured**: 1200 lock trials and 312 preemption trials ([`lock-owners.tsv`](lock-owners.tsv), [`preemption-trials.tsv`](preemption-trials.tsv)). §10.5 clause 2 is replaced, clause 7 goes from three hooks to five, §10.6's partition sentence is replaced | the generation unlink's ordering, and `killpg` under pid reuse — **neither is closed and both are new residues rather than survivals**. §13 rows 20 and 21 stay ship-blocking |

**Read §13 for the lock's own status.** **Six rows closed — 1, 2, 3, 4, 7 and 16 — and eight opened,
17 through 24**, verified against the table rather than carried over from an earlier draft: `main`'s
copy of this document has no row above 16 at all **[repo]**. The honest answer to *"can #11 lock?"* is
stated there rather than implied here, and **the count going up is not a regression** — the closed rows
were decisions nobody had made, the new ones are verifications of mechanisms that now exist on paper.
Three of the eight block shipping (17, 20, 21).

> **This sentence read *"three rows closed, three opened"* until review caught it.** It understated the
> closures by half and the openings by more than half, while sitting three paragraphs above the table
> that contradicts it. **Worth noticing as a class of defect rather than a typo**: a summary written
> before the table it summarises, and then not re-derived from it.

---

## 0. Where each fact comes from

| tag | source | what it can and cannot prove |
| --- | --- | --- |
| **[obs]** | a live `Stop` payload captured on 2.1.245, 2026-08-25 | what this build actually sends. The strongest evidence in the document. |
| **[bin]** | `strings` of the shipped 2.1.245 binary, via [`turn-finality-and-the-stop-hook.md`](turn-finality-and-the-stop-hook.md) | what the build's compiled schema says. Disagrees with the docs in both directions — see §2. |
| **[obs2]** | 32 paired captures from a **second, independently designed probe** on a second session, `haiku`, whose probe and output are both committed at [`handoff-timing-probe/`](handoff-timing-probe/) | the same class of evidence as **[obs]** with one property **[obs]** lacks: it is **re-runnable**. Used for §3.5's ordering numbers. Still one machine, one build. |
| **[hook]** | a `Stop` hook fired by Claude Code 2.1.245 in a driven session, its own clock read in-process, via [`worker-residency.md`](worker-residency.md) and [`residency-timings.tsv`](residency-timings.tsv) | what a **hook process** did on this machine on this build. It is the only tag in this table that measures the shipped trigger's own latency rather than a bench harness's. Not portable to other hardware. |
| **[rig]** | read out of a throwaway probe's own source — `speakd.py`, `speak-probe.sh`, `warm-probe.sh`, none of them in this repository | what the thing that produced a **[hook]** number actually did. It is evidence about the measurement, never about a shipped file, and the probe is not the specification. |
| **[heard]** | [`sanitizer-audition.md`](sanitizer-audition.md), [`sanitizer-audition-13.md`](sanitizer-audition-13.md), [`voice-and-pipelining.md`](voice-and-pipelining.md), [`min-length-audition.md`](min-length-audition.md) | blind A/B verdicts and stopwatch readings. Noise floor ~1 call in 12. |
| **[repo]** | the working tree, read directly; line numbers citable | what this plugin does today |
| **[measured-here]** | measurements taken while writing this document — existing scripts over existing files, plus exit codes read off `jq` and `bash` directly | stated inline with what produced them. No audio, no benchmark, no LLM. |
| **[trials]** | the offline instrumented probe at [`preemption-lock-probe/`](preemption-lock-probe/) — 1200 lock trials over three protocols and six scenarios, and 312 preemption trials over 26 switchable configurations, committed as [`lock-owners.tsv`](lock-owners.tsv) and [`preemption-trials.tsv`](preemption-trials.tsv) and re-derivable with `preemption-lock-probe/summarise.sh` | what these protocols do under contention, on this machine. **Not the shipped hook and not the shipped worker** — it is a Python model of the election and the preemption sites, which is what let the adversarial interleavings be provoked at all. It can falsify a protocol; it cannot confirm an implementation. |
| **[inferred]** | a reading, not a run — control flow followed through the binary, or a mechanism reasoned out and written down | the weakest tag in this document. Used where a thing could not be measured, and always with the measurement it is standing in for named. |

**The two unresolved links this section used to warn about now resolve.** `turn-finality-and-the-stop-hook.md`
landed via **PR #17** and `sanitizer-audition-13.md` / `audition-verdicts-13.tsv` via **PR #18**; both
are on `main`. The warning is removed rather than kept as a historical note, because a reader checking
a link is helped by nothing except the link working.

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

**And five claims this spec made itself did not survive the four measurements of 2026-08-25.** These
are listed separately from the ones above because they are not inherited mistakes — they are this
document's own, and each is corrected at the section rather than deleted:

- **§3.2's *"if the probe shows `MessageDisplay` carries `prompt_id`, prefer it"* is REVERSED.** It does
  carry one, it is the same one, and it is **still the weaker key** — it identifies a turn and
  `rewrite.sh` publishes per message (§3.2).
- **§3.5's last row was *silent* and is now a BOUNDED WAIT.** The row conflated "the rewrite failed"
  with "the rewrite has not happened yet", and the second turned out to be the common case (§3.5.1).
- **§4.1 clause 3 counted *segments* and the count is BOUNDARIES.** Read literally the old clause forced
  `.` on every list in the corpus and a trailing `,` on 31 one-line messages; the shipped code had been
  knowingly out of contract with it (§4.1 qualification 3).
- **§4.3's *"ships free of regression risk, a measured no-op on all twelve real rewrites"* is FALSE
  inside the settled set**, which is the only place `flag-pause` ships (§4.3, §13 row 19).
- **§10.5 was the section this document called its own biggest gap, and it is now LOCKED** — which is
  the one item on this list where the change is in the reassuring direction, and it still cost §4 its
  headline number (0.86 s is the bench's; 1.22 s is a hook's).

---

## 1. LOCKED — the architecture is two hooks

| | `MessageDisplay` → `rewrite.sh` | `Stop` → `speak.sh` (new) |
| --- | --- | --- |
| fires | once per streamed chunk of every assistant message (`rewrite.sh:5-10`) | once, when the turn ends **[obs]** |
| owns | the plain-English rewrite that appears **on screen**, **plus two things it did not own before**: publishing that rewrite into `speak/` (§3.1) and the worker warm-up (§10.5 clause 4) | **speech, and nothing else** |
| must not | fire speech, or synthesise, or play anything | touch the screen |
| ordering | — | **dispatched CONCURRENTLY with the final `MessageDisplay` invocation, not after it.** Median 6.7 ms behind it, positive 32/32, and the gap does not change when that hook is made 65× slower **[obs2]** — §3.5.1 |
| declared timeout | 60 s (`hooks/hooks.json:9`) | **10 s** — see §10.4 |
| harness default | 10 s **[bin]** | 600 s **[bin]** |
| fires for subagents | yes | **no** **[obs]** — §7 |
| exit status means | "hook failed"; content passes through | **exit 2 blocks the turn**; every other code is an explicitly *non-blocking status code* — §5 |

**Why the split is forced.** `MessageDisplay.final` is *message*-level: a turn that emits three
narration messages and two tool calls sets `final: true` three times, and there is no lookahead at
display time — the tool call that would mark a message intermediate has not happened yet. `Stop`
fires once per turn and carries the text of the message that ended it. **[bin]**, confirmed **[obs]**.

**Consequence for `rewrite.sh`: two additions, and a prohibition that still stands.** Its
**buffer-to-final logic is unchanged** and it must still never fire speech — the prohibition is stated
explicitly because a reader looking at `rewrite.sh:244`'s `emit "$out"` will otherwise see the obvious
place to put a `say` call. But the display hook is no longer untouched by this feature, and pretending
otherwise would send an implementer looking for the wrong diff:

1. **It publishes** the finished rewrite and the source hash into `speak/` (§3.1) — a separate write,
   guarded with `|| true`, placed where `$rewrite` is already in hand.
2. **It ensures the worker exists** (§10.5 clause 4) — one `[[ -d ]]` and one `kill -0`, payload-
   independent, placed **before** `rewrite.sh:127`'s non-final early return so that it runs on every
   invocation and not only the final one. This is the clause that moves the cold start off the
   user-visible path on the first turn of a session.

**Neither addition may change `rewrite.sh`'s exit path.** The display hook's fail-open contract
outranks the speech feature absolutely: both are guarded, and a full disk, an unwritable `TMPDIR` or a
missing Kokoro venv must leave the rewrite exactly as it would have been.

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

**The other side of the handoff, catalogued beside it: the `MessageDisplay` payload carries exactly ten
fields** **[obs]**, captured 94 times across 35 turns. It had never been captured at all when this
section was first written, which is why §3.2 had to hedge.

```
session_id  transcript_path  cwd  prompt_id  hook_event_name
turn_id  message_id  index  final  delta
```

- **All ten were present on all 94 payloads.** No field was optional in practice. **[obs]**
- **`prompt_id` is present, and it is the same value `Stop` carries for that turn — 35/35.** That
  answers the question §3.2 was hedging against. It does **not** make `prompt_id` the key; §3.2 says
  why. **[obs]**
- **`turn_id` is present here and ABSENT from `Stop`**, so it cannot be a handoff key in either
  direction.
- Against `Stop`'s eleven, `MessageDisplay` is missing `permission_mode`, `effort`,
  `stop_hook_active`, `last_assistant_message`, `background_tasks` and `session_crons`, and adds
  `turn_id`, `message_id`, `index`, `final` and `delta`. `agent_id` and `agent_type` were absent from
  both, as the schema says to expect on the main thread.
- **`rewrite.sh` reads six of the ten**, in two places: `message_id`, `session_id`, `index`, `final`
  and `transcript_path` at `:107-111`, and `delta` at `:124`. **The four it does not read are `cwd`,
  `prompt_id`, `hook_event_name` and `turn_id`** — all four are available to a publish step that wants
  them. **[repo]**

---

## 3. LOCKED — what gets spoken

This is the section the lock was waiting on. It has **four** parts: the handoff, the staleness key, the
raw-speech gate, and the decision table that joins them — plus **§3.5.1, the bounded wait**, which was
added on 2026-08-25 when the handoff turned out to be a race rather than a sequence. **§3.5.1 is the one
part of §3 that specifies a mechanism nobody has run.**

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
$BUF_ROOT/<session_id>/speak/            # depth-2 dir -> swept by rewrite.sh:117 after 30 min idle
$BUF_ROOT/<session_id>/speak/rw.<hash>   # the rewrite for the source text whose sha256 is <hash>
$BUF_ROOT/<session_id>/speak/prompt_id   # DIAGNOSTIC ONLY, off the correctness path (see 3.2)
```

**`rw.<hash>` is content-addressed and there is no `source` file.** The name carries the whole handoff
key: `<hash>` is the `sha256( trim( original text ) )` of §3.2, so **the path itself is the proof that
this rewrite belongs to that source text.** Two earlier drafts of this section instead published the
hash into a mutable `speak/source` and tried to order the reads around it; both were wrong, and §3.1's
"How the publish is installed" below is written so that its correctness argument does not mention read
order at all.

`speak.sh` writes one more file into the same directory — `job` (§10.5 clause 1) — and the **worker**
writes `spoken` (the dedup hash, §5.1 as amended by §3.5.1 clause 6), its owner records
(`worker.lock.<gen>`, §10.5 clause 2) and its player records (`playerdir/`, §10.6). **Both hooks write
into one depth-2 directory**, which is what keeps the whole feature inside a single sweep-reclaimed
path. **An earlier draft of this sentence said `speak.sh` writes `spoken` and `pid`** — a leftover from
the design in which the hook spawned the speech child, contradicting §10.2, §10.3 step 8b and §10.6
qualifier (1), all of which put those writes in the worker. The conclusion survives; the writer named
in it did not.

**Lifecycle: one `speak/` per session; one `rw.<hash>` per distinct rewritten message, never
overwritten with different provenance.** This is a change from an earlier draft that kept a single
`speak/rewrite` overwritten in place, and the reason for the change is in the install block below:
**a reused path is what made the mixed-generation race possible.** `speak.sh` never deletes anything;
the existing sweep does.

**What that costs, priced rather than waved past, because §3.1 rejected per-message files once
already.** `emit()`'s comment warns that per-message files *"would pile up in TMPDIR one per assistant
message"* — and that warning is about loose files at `$BUF_ROOT`'s **top level**, which the sweep
never reclaims (`$BUF_ROOT/$sid.notified` is the standing example). **These files are different in
kind: they live inside the depth-2 directory the sweep `rm -rf`s wholesale**, so the accumulation is
bounded by one session rather than unbounded in time. A rewrite is a few hundred to a couple of
thousand bytes, so a long session holds well under a megabyte **[inferred]**.

**The producer does NOT prune older generations, and that is a decision rather than an omission.** It
could unlink every `rw.*` but its own; it must not. A consumer still inside §3.5.1's bounded wait for
an older hash would then get `ENOENT`, wait to its deadline and go **silent** — safe under §3.2's
posture, but a real utterance lost to save a few kilobytes the sweep reclaims anyway. **The sweep is
the reclamation.**

**Publication point.** `rewrite.sh` obtains `$rewrite` before it builds `$out` at `:235`. The publish
is a **separate write** placed there, not a reuse of `$out`: `emit()` reads and then `rm -f`s its
argument (`:84-90`), so the file `emit` is handed does not survive the call. The publish must also be
guarded (`|| true`) so that a full disk or an unwritable `TMPDIR` cannot change `rewrite.sh`'s exit
path — the display hook's fail-open contract outranks the speech feature absolutely. **And it sits
behind `CLAUDISH_SPEAK`, normatively — §11.** A disabled user does not pay for the hash, the `mkdir` or
the renames below.

**The plugin's global switches need no separate check here, and that is a property of the placement
rather than luck.** `:100`'s `[ "$ENABLED" = "1" ] || pass_through` — which is `CLAUDISH_ENABLED` and
the `~/.claude/claudish-off` flag file, `rewrite.sh:57` and `:61` — sits far above `:235`, so a hook
that reaches the publish point has already passed both **[repo]**. **`speak.sh` gets no such
inheritance**: it is a different process on a different event and must test them itself, which it did
not until review — §10.3 steps 0a–0b.

**How the publish is installed, and this is normative. THIRD ITERATION — the first two were both
wrong, and the shape of the error is the reason this one is built differently.** The history matters
because it is the argument for the design:

| draft | mechanism | how it failed |
| --- | --- | --- |
| 1 | two plain writes, `rewrite` and `source`, unordered | `source` could land first, so a consumer matched the expected hash and read the **previous** turn's rewrite |
| 2 | rename-install, `source` written last as a commit marker, consumer re-reads `source` after `rewrite` | **still accepts a mixed generation.** From `source=A, rewrite=A`: publisher B renames `rewrite=B`, and before it commits `source=B` a consumer for A reads `source=A`, reads `rewrite=B`, re-reads `source=A` — unmoved — and accepts B. **A re-read cannot detect a change that has not been published yet**, which is the flaw in calling it a seqlock: a real seqlock needs the writer to invalidate *before* touching the data, and this writer only ever published *after* |
| 3 | **content-addressed immutable generation file, below** | correctness does not depend on read order, so there is no ordering left to get wrong |

**Two ordering-based attempts have now failed review, so the third does not order anything.**

1. **The rewrite is written to a path named by the hash of its own source text.** Write to a unique
   temp name **inside the same speak directory** — `rename(2)` is atomic only within a filesystem, and
   the depth-2 speak dir is the one place both hooks already share — then `rename` it onto
   `speak/rw.<sha256( trim( original text ) )>`. **This is the same primitive §10.5 clause 1 uses for
   the job drop**, and it is the idiom this project already reaches for.
2. **There is no commit marker, because there is nothing to commit *to*.** The consumer already knows
   the hash it wants: the hook computes it from `last_assistant_message` and the job carries it
   (§3.5.1 clause 1). So the consumer's test is `[[ -f speak/rw.<expected> ]]` and its read is that
   file — **it never reads a mutable file, compares two reads, or observes any other generation.**
3. **The correctness argument, stated without reference to read order.** A file at `rw.<H>` can only
   have been installed by a publisher that computed `H` over the text it rewrote, so **its contents are
   a rewrite of exactly that text.** The path is a function of provenance, so it is never reused for a
   different generation: **the mixed-generation state draft 2 admitted cannot be named**, and a
   consumer for `H` cannot reach a rewrite for any other hash even in principle. The rename makes
   appearance atomic, so no partial file is ever visible.
4. **Where "immutable" is loose, said plainly rather than glossed.** The *path-to-provenance* mapping is
   immutable; the bytes are not guaranteed unique. The same source text can be rewritten twice — an
   identical message on two turns, or a retry — and the LLM is not deterministic, so the second install
   may differ in wording. **Both are valid rewrites of that source text**, which is precisely what §3.2
   guarantees, so which one a consumer gets is immaterial; and rename-install means it gets one of them
   whole. **This is the one property a reader should check against intent**, because "immutable" would
   otherwise be read as "byte-stable".
5. **Fail-open still falls out of the structure.** A publisher that dies before its rename leaves no
   `rw.<H>` at all, so the turn reads as "not yet published" and §3.5.1's wait handles it — the same
   branch as a rewrite that timed out. A half-written temp file is never at a name anything looks up.

**What this removes, and it is the point.** `speak/source` is **gone from the correctness path and
from the file layout**. Draft 2 left it standing as the thing consumers keyed on; keeping a mutable,
reused, hash-bearing file in the design after two ordering failures is how a fourth iteration of this
defect would arrive. `prompt_id` stays, marked diagnostic, and **nothing keys on it** — §3.2 already
declined it as the key and §13 row 4 records why.

**All of this is [inferred]** — reasoned from `rename(2)` semantics and this file's own lifecycle, not
run. Nothing has published anything, so nothing has raced it. §13 row 17 is where the build-and-watch
that retires it lives, and its closing condition now names the property to check: **that no consumer
ever opens a path it did not compute from its own expected hash.**

**Only successful rewrites are published.** The below-threshold branch (`:147`), the notice branch
(`:210-225`) and every `pass_through` publish nothing. A stale `speak/` from an earlier message is
therefore possible, which is what §3.2 is for.

> **None of this publish exists yet, and saying so plainly matters twice over.** `grep -n 'speak'
> rewrite.sh` returns **zero matches across all 245 lines** **[repo]**. §3.1 is proposed spec, not
> shipped code — consistent with `speak.sh` not existing. It matters for the reader, who should not go
> looking for the write; and it mattered for §10.5, where an earlier residency draft proposed hanging
> the worker warm-up trigger on this publish point and cited a lead time that belonged to a different
> event. There was no publish point to attach anything to. See §10.5 clause 4.

**A stale `speak/` is not the exception. It is what `Stop` reads on almost every turn** — because
`Stop` is dispatched **concurrently with** the final `MessageDisplay` invocation and this publish
happens on the far side of an LLM call. Measured stale in **29 of 30** turns, holding the *previous*
turn's text **[obs]**. The publication point above is unchanged and is still the right place for the
write; what changes is that §3.2's comparison cannot be the whole mechanism, because on most turns it
has nothing but the previous message to compare against. **§3.5.1 is the repair, and it is a bounded
wait rather than a move of this write.** **[obs2]**

### 3.2 LOCKED — staleness matching, keyed on the content hash

**The requirement is locked and so is the key: `speak.sh` must prove the buffered rewrite belongs to
*this* turn's final message before speaking it, and stay silent rather than guess.** Speaking a stale
rewrite is worse than silence: it is a confident, fluent statement about the wrong turn.

**The key is `sha256( trim( text ) )` on the source text.** Measured, not assumed:

```
rewrite.sh publishes:  the rewrite -> speak/rw.<sha256( trim( assembled original text ) )>
speak.sh  computes:    H = sha256( trim( last_assistant_message ) )
speak/rw.<H> exists -> speak it.   absent -> §3.5, and §3.5.1's bounded wait
```

A hash, not the text, so nothing large is stored or compared. `trim` on both sides because the harness
itself trims (`…trim() || undefined`, **[bin]**).

**The key is unchanged by §3.1's third draft; only the file layout is.** The hash is still
`sha256( trim( source ) )` and it is still the only thing that authorises speech. What changed is that
the hash is now the rewrite's **filename** rather than the contents of a separate `speak/source`, which
turns "compare two files and hope the order held" into "open the one path your own hash names".
**§3.2's decision is untouched; §3.1 stopped implementing it unsafely.**

**The match rate is 35 of 35 — 100%, byte-identical, not merely trim-equal.** Measured 2026-08-25 on
2.1.245 by instrumenting both sides of one driven session: 35 `Stop` payloads against 35
`MessageDisplay` delta streams, across fences, tool calls, thinking blocks, subagents, multi-flush
messages and one-byte acknowledgements. Not one mismatch of any shape. **[obs]**
[`handoff-match-rate.md`](handoff-match-rate.md). *The sentence this paragraph replaces — "until it is
taken, the match rate is unknown and this spec does not claim it is high" — is discharged.*

> **Read the rate at the strength its evidence supports, which is two different strengths.** The 35
> rows **are not re-derivable**: their inputs were destroyed at teardown and nothing committed can
> rebuild them, so they are a **record of a measurement** and rest on the honesty of whoever took
> them. What *is* reproducible is the same comparison on new turns: the committed kit at
> [`handoff-timing-probe/`](handoff-timing-probe/) re-derives this section's question with
> `match.sh` and got **15 of 15 exact**, raw and trailing-newline-stripped alike, on a different
> session with a different probe and a different model. **The reproducible claim is 15/15; the 35/35
> stands behind it and does not replace it.** **[obs]** + **[obs2]**

**Why they agree, and the one edge still untested.** `last_assistant_message` is the **text blocks
only**, joined on `"\n"` and trimmed **[bin]**; `rewrite.sh`'s `$full` is the concatenation of
`MessageDisplay` deltas. **No message in 50 had two text blocks**, so the join has never had anything
to join. That is the untested edge rather than a passed test, and it is the only shape that could break
the equality. **[obs]**

**`prompt_id` is available on both sides and it is still the weaker key. Do not make it the key.**
This **reverses** the preference this section previously stated, on the evidence this section asked
for:

- `MessageDisplay` **does** carry `prompt_id`, on all 94 payloads, and it is the **same value** `Stop`
  carries, 35/35, a clean one-to-one with no orphans in either direction (§2). **[obs]**
- But **`prompt_id` identifies a *turn* and `rewrite.sh` publishes per *message***, overwriting
  `speak/` on every rewritten message. **10 of 35 turns held more than one message**; four of them
  held more than one *text-bearing* message. In such a turn every message shares one `prompt_id`, so a
  `prompt_id` key cannot tell *"the rewrite of this turn's final message"* from *"the rewrite of the
  narration three messages ago"*. **It would speak the wrong one and believe it was right.** **[obs]**
- §3.2's own stated requirement is the **message**-level claim, not the turn-level one. The content
  hash makes exactly that distinction and costs a `sha256` of a string the hook already holds.
- **So: hash as the key, `prompt_id` as a cheap pre-filter only.** A pre-filter is worth having — it
  rejects a buffer from an older turn without hashing anything — but it can never license speech on its
  own. `turn_id` cannot be a key at all: `Stop` does not carry it (§2).

**No normalisation, and this is a prohibition rather than an omission.** All three candidates were
tested against the 35 and every one was a no-op, so there is nothing to rescue **[obs]**:

| candidate | effect on these 35 | verdict |
| --- | --- | --- |
| `trim`, as specified above | no change — no message had edge whitespace | **keep**, defensive |
| collapse internal whitespace runs | no change | **do not add** — it lets genuinely different messages hash alike |
| hash a fixed-length prefix | no change | **do not add** — same objection, and it makes truncation invisible |

**Each of the two rejected candidates widens a key whose whole job is to be narrow.** `trim` keeps its
place and loses its emphasis: 44 message streams, zero edge whitespace, so it is defensive and
unexercised rather than load-bearing.

**One benign collision, named rather than mechanised.** Two of the 44 captured messages were
byte-identical to an earlier one — the same prompt re-driven, answered the same way — and both were
long enough to publish. A stale buffer therefore *can* produce a false hit. But it can only do so when
the earlier message had identical text, in which case the buffered rewrite is a rewrite of that same
text and **the utterance is correct anyway**. **[obs]** No mechanism is owed; this line is the whole
treatment.

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
| **hit** (§3.2 match — `speak/rw.<H>` exists) | any | any | speak that file — sanitized, pipelined |
| miss | `< MIN_CHARS` | none disqualifying | speak `last_assistant_message` **raw** — sanitized, pipelined |
| miss | `< MIN_CHARS` | ≥ 1 disqualifying | **silent** |
| miss | `≥ MIN_CHARS` | any | **BOUNDED WAIT (§3.5.1)**, then: publish arrives and matches → speak it; deadline passes → **silent** |

**The last row changed on 2026-08-25 and it is the largest change this revision makes.** It used to
read **silent**, on the reasoning that a missing rewrite above the threshold means the provider failed.
That reasoning is still right about a *failed* rewrite and it is now known to be wrong about the common
case: on almost every qualifying turn the rewrite has not failed, it has **not happened yet**, because
`Stop` is dispatched concurrently with the final `MessageDisplay` invocation rather than after it. A
row that cannot tell "never coming" from "not yet" silences the feature on the large majority of the
turns it exists for. §3.5.1 is that row.

**The fail-open ban is kept intact, and the wait is what makes it enforceable rather than accidental.**
Above the threshold a rewrite was due; if it genuinely did not arrive — the LLM provider failed, timed
out, or returned empty — #1's out-of-scope rule bans speech on that path, and the wait's timeout branch
is **silent** for exactly that reason. Nothing about the hazard narrowing touches it: the narrowing
licenses raw speech only where **no rewrite was ever attempted**, never where one was attempted and
failed. That distinction is the whole content of the amendment in §14. What the wait adds is the
ability to *tell the two apart*, which the old row could not do.

**Below `MIN_CHARS` the wait must never run.** `rewrite.sh:147` publishes nothing below the threshold —
not late, ever — so waiting there could only be waiting for something that will not come. Rows two and
three are unchanged and are decided in the hook, immediately.

**The sanitizer runs on both speaking rows.** Same settled set, same order (§4). There is no
raw-specific sanitizer.

**A wrinkle that only bites if this band ever grows.** #10 measured raw *short* text at a largest
batch of 265 phonemes against 510 **[heard]**, so the raw path cannot crash today. A **long** raw
assistant message has never had its batch sizes measured — and the table above never sends one to
synthesis. If a future change lets long raw text through, that measurement is owed first. **The wait in
§3.5.1 does not change this**: on the waiting row what eventually gets spoken is a *rewrite*, never
long raw text.

### 3.5.1 LOCKED — the bounded wait, and the race that forces it

**The race is CONFIRMED, and it was re-measured from scratch by an independent probe before anything
was built on it.** The committed kit at [`handoff-timing-probe/`](handoff-timing-probe/) reproduced it
over **32 clean turns** on a second session with a second design and a different model. Everything in
this subsection carrying a number is **[obs2]** unless marked otherwise.

**The ordering.** The `Stop` hook process starts a **median 6.7 ms** after the final-chunk
`MessageDisplay` hook process starts — **positive in 32 of 32**, range +1.9 ms to +322 ms, with 29 of
32 inside +1.9…+15.4 ms. `Stop` never once started first.

**Why that alone proves nothing, and what does.** A display hook that returns in 60 ms cannot
distinguish "the harness dispatched them concurrently" from "the harness waited for me". So the display
hook was held open **4 s** in one regime, and — this is the part that decides it — **a fast control was
run alongside**:

| regime | display-hook duration | dispatch gap (`Stop` start − display-hook start) | `Stop` start − display-hook **return** |
| --- | ---: | ---: | ---: |
| control (n=12) | 51.3 – 87.3 ms | +3.6 … +261.1 ms | −46.8 … −81.7 ms (one at +209.7) |
| held open (n=20) | 4,071 – 4,116 ms | +1.9 … +322.0 ms | **−3,774 … −4,114 ms** |

**The dispatch gap does not depend on the display hook's duration.** Make that hook 65× slower and the
gap stays in the same few-millisecond band. **That is the proof, and it is stronger than the 4 s figure
on its own: `Stop` is never sequenced after the display hook.** In the held-open regime `Stop` starts
3.8–4.1 s *before* the display hook returns; in the control regime it still starts 47–82 ms before a
~60 ms hook returns. Both regimes say the same thing.

**Staleness was then observed directly, not inferred from the clock.** The probe published the
assembled text twice per turn — immediately on entering the final chunk, and again after the 4 s hold,
which is where `rewrite.sh` really publishes — and `Stop` snapshotted both:

| where the display hook publishes | `Stop` read a **stale** buffer | read the current text |
| --- | ---: | ---: |
| after its slow work (what §3.1 specifies) | **29 of 30** | 1 |
| immediately, before any slow work | **27 of 30** | 3 |

**"Stale" here is identified by content, not assumed.** The buffer held the **previous turn's
message**: on the *Clocks* turn the slow-published buffer still read `# The History of the Compass`.

**Four consequences, each stated precisely, because three of them are easy to get wrong.**

1. **The buffer is not empty. It holds the previous message.** So the failure this creates is not
   "nothing to say" — it is that **a `speak.sh` which skipped §3.2's comparison would confidently
   speak the previous turn's answer aloud.** Silence is what the comparison buys, and the comparison
   did exactly the right thing at every one of those 29 reads.
2. **It is not "every turn", and stating it as a law invites a reader to disprove a real blocker with
   one counter-example.** A **~10% tail** of turns escapes: the +261 / +298 / +322 ms dispatch gaps are
   the same three turns where an immediate publish won. §3.2's benign repeated-text collision is a
   fourth kind of exception. **So it is a rate, not a law:** silent on the large majority of qualifying
   turns, unpredictably — which for a speech feature is no better than always and is harder to
   diagnose.
3. **`MessageDisplay` fires once per streamed chunk, not once per message** (`rewrite.sh:5-10`
   **[repo]**; the probe confirms `.index`/`.final` per fire), and **`Stop` reads the buffer a median
   24.2 ms after the display hook is entered** — 28 of 31 turns in 18–33 ms
   ([`latency.tsv`](handoff-timing-probe/latency.tsv)). **That 24.2 ms is the entire budget any
   publish-early repair has**, and it is the number that demotes publish-early from a fix to a race:
   the probe's own publish path — a payload write, one `zsh` fork and three `jq` forks — took a median
   **51.8 ms** and **lost 27 of 30**.
4. **There is no partial buffer to fall back on in the band that matters.** Chunking follows the
   streaming cadence, not length: replies of **440, 663, 692, 743, 762 and 772 bytes — every one above
   the default `MIN_CHARS` of 200 — each arrived in exactly ONE chunk.** For those the final chunk *is*
   the whole message and the buffer holds the entire previous one. On a 13.3 kB, 14-chunk reply the
   final chunk carried only 8.5%, so a per-chunk buffer would be *slightly truncated* rather than
   stale — but that is the easy case. **The hazard is worst precisely where the feature is aimed: long
   enough to be worth speaking, short enough to stream in one flush.**

**The three repairs, scored against the measurement rather than against taste.**

| repair | verdict |
| --- | --- |
| **a bounded wait in the speech path** for `speak/rw.<H>` to appear | **ADOPTED — the only one the measurement unconditionally supports.** It is the only option that does not depend on winning a race. Its cost is real and is priced below. |
| `rewrite.sh` publishes the **original hash** immediately at the final chunk, the rewrite later | **a race, not a fix — but a winnable one.** Lost 27 of 30 as instrumented. The budget is now known: get the bytes on disk **within ~20 ms of hook entry**, which means writing the delta concatenation *before* any metadata parsing. Permitted as an **optimisation** (it converts a wait into no wait on the turns it wins) and **forbidden as the mechanism**, because it can never be better than a race. |
| **move speech off `Stop`** onto whatever fires after the display hook completes | **unevaluated, and the measurement neither helps nor hurts it. No such event was found.** `MessageDisplay` firing per chunk makes "after the display hook completes" a per-chunk notion, so this needs an event that exists before it can be scored. Not adopted, and not refuted either. |

A fourth option the chunk-level finding opened — have the display hook append each delta to a
per-`message_id` buffer (`rewrite.sh:124` already does exactly this) and have `speak.sh` read *that* —
is **a mitigation for long replies, not a repair**: on multi-chunk replies the buffer is ~91% complete
at `Stop`'s read, but on the 440–772-byte single-chunk replies it is exactly as empty as the published
one. Not adopted.

#### The bounded wait, as specified

> **Where the wait runs: in the resident worker, never in the hook body.** The hook still drops its job
> and exits 0 without waiting (§10.3 step 9), so §6's non-blocking guarantee is **untouched** — the
> measured hook wall cost stays **0.063–0.219 s, median 0.086 s** **[hook]**. This is the whole reason
> the wait is affordable: §6 spends its length insisting the prompt is never held, and a wait in the
> hook would have spent that back. §10.5's worker already blocks on `kqueue(EVFILT_VNODE, NOTE_WRITE)`
> over this very directory, so the wait reuses **machinery that is already there**, not new machinery.

1. **The job carries an expectation, not a filename.** The hook writes a job to a temp name and
   renames it onto `$BUF_ROOT/<session_id>/speak/job` (§10.5 clause 1). The job carries: the hook's own
   **fire time**; the **expected source hash** `sha256( trim( last_assistant_message ) )`; and the
   **mode** — `buffered` (speak `speak/rw.<expected hash>` once it appears) or `raw`
   (speak this text, included inline, no wait). Rows one and four of §3.5's table are therefore the
   *same* job shape, differing only in how long the wait turns out to be — which is a simplification,
   not an extra case: on a buffer **hit** the worker simply finds the file already there, and it opens
   the same content-addressed path either way, so there is nothing to re-verify (§3.1 draft 3).
2. **What it waits on: `speak/rw.<expected hash>` coming into existence. Nothing else.** Not "the
   buffer changed", not a timestamp, not `prompt_id`, and **not a mutable `speak/source`** — that file
   no longer exists (§3.1). On each wake, `stat` the one path the job's expected hash names; if it is
   there, read it and speak. **There is no compare, no read ordering and no re-read**, because the path
   the worker opens is computed from the hash it is waiting for and can hold nothing else.
   - **Two earlier drafts of this clause DID order reads, and both were wrong.** Draft 1 read a mutable
     `source` and could speak the previous turn's rewrite; draft 2 added a re-read of `source` and still
     accepted a mixed generation, because a publisher can install the next `rewrite` before committing
     the next `source`, and **a re-read cannot detect a change that has not been published yet**. §3.1
     carries the table. **The lesson recorded here rather than only there: this clause should be
     suspected first if the wait ever speaks the wrong turn, and any future version of it that
     reintroduces a comparison between two files is reintroducing the bug.**
3. **The ceiling is derived from the thing it is waiting for, and no new knob ships.** The publish is
   bounded by `rewrite.sh`'s own LLM budget: `LLM_TIMEOUT="${CLAUDISH_TIMEOUT:-45}"` (`rewrite.sh:65`),
   enforced by `_llm_run_bounded`'s TERM → `sleep 2` → KILL (`providers.sh:146-172`) and by
   `curl --max-time` on the HTTP providers **[repo]**. **So a publish that will ever arrive arrives
   within about `CLAUDISH_TIMEOUT + 2` s of the final chunk**, plus the sanitize-and-emit tail; and
   `Stop` fires within milliseconds of that chunk. **Deadline: the job's fire time plus
   `CLAUDISH_TIMEOUT + 5` seconds** — 50 s at the default.
   - **Read from the same env var `rewrite.sh` reads, deliberately.** A `CLAUDISH_SPEAK_WAIT` of its
     own could drift out of agreement with the budget it is waiting on, and §9's posture is that a knob
     nobody has justified does not ship. `CLAUDISH_*` values are frozen at session launch
     (`rewrite.sh:58-60`), so both hooks see the same frozen number and the agreement is **structural
     rather than maintained**.
   - **The deadline is measured from the hook's fire time, not from when the worker claims the job**,
     so a cold worker start (1.33–2.02 s, §10.5) cannot silently extend the window.
   - **The one long rewrite anybody has timed is not a counterexample to this ceiling.** 52.50 s for
     ~1,300 words ([`provider-switch-traps.md`](provider-switch-traps.md)) was measured with
     `LLM_TIMEOUT=120` in a standalone script, **not through the hook**. At the default 45 that same
     call is TERMed and the rewrite **fails open and publishes nothing** — which is precisely the
     branch where the wait is *supposed* to give up. It is an example of the timeout branch, not a
     missed publish.
4. **On the deadline: give up, stay silent, exit 0. Nothing is announced, nothing reaches the screen.**
   Fail-open and silent is this project's existing posture on every other failure row (§10.7), and the
   reason is the one §3.2 gives: **a wrong utterance is worse than none.** Under `CLAUDISH_DEBUG=1` the
   give-up is written to `$BUF_ROOT/debug.log` and nowhere else.
5. **A wait is abandoned, never queued.** A newer job renamed onto `speak/job` while the worker is
   waiting means the turn the wait belongs to is over. The worker abandons the wait and claims the
   newer job; §10.6's claim-time kill covers any player. This is the same coalescing the producer
   rename already gives (§10.5 clause 1) and needs no new rule — but it does mean **at most one wait is
   ever outstanding per session**, which is what keeps §5.1's dedup a single-consumer check rather than
   a test-and-set.
6. **§5.1's dedup moves to the point of synthesis, which is where §5.1 already says it belongs.** On
   the waiting path the resolved text is not known when the hook exits, so the hook cannot hash it.
   The worker writes `speak/spoken` at the moment it sends text to synthesis — literally *"the text
   last actually sent to synthesis"*, §5.1's own words. Because clause 5 keeps exactly one consumer,
   no locking is needed. §10.3 records this as a change to step 8b.
7. **The worker RE-CHECKS both off-files at the point of synthesis, and this clause exists because
   moving the resolution into the worker opened a hole in the runtime mute.** §10.3 steps 0b and 2
   `stat` `claudish-off` and `claudish-speak-off` in the **hook**, before the job is enqueued — and
   §10.1's whole argument for having flag files at all is that `CLAUDISH_*` is frozen at session
   launch, **so only a file can stop a session that is already running**. Under clause 4 the worker
   then waits up to `CLAUDISH_TIMEOUT + 5` s — **50 s at the defaults** — between that check and the
   sound. **Without this clause, touching either file inside that window still results in speech** —
   which is precisely the promise `claudish-speak-off` is documented to make (§10.8: *"stops speech
   and keeps rewriting"*). So: **the worker `stat`s both files again immediately before `create()` and again
   before `Popen`, and discards the job silently if either exists.** Two `stat`s on a path that is
   almost always absent, once per utterance, against a 50-second window in which the user's mute does
   nothing. **[inferred]** — nothing has been muted mid-wait, because nothing implements the wait.
   The residual is the synthesis-to-playback interval itself, which the §10.6 kills already cover.

**What this costs, stated rather than buried.** The utterance now lands **after** the rewrite, so the
user hears the answer a rewrite-latency later than the turn ended — seconds, and on a slow provider
tens of seconds. That is a real regression against a design that spoke immediately, and it is the price
of speaking the *right* text. The alternative on offer is speaking the previous turn's answer, or
saying nothing at all. **The prompt is not held for any of it**, which is the part that would have been
unacceptable.

**What has NOT been established about this, and it is not a small residue.** The wait has never been
implemented, and **nothing end-to-end has been watched**: `speak.sh` does not exist, so nobody has seen
this go quiet, or come back late, or preempt correctly. What is measured is the ordering (**[obs2]**),
the buffer contents at `Stop`'s read (**[obs]**), the publication point (**[repo]**) and the worker's
kqueue wake and hook cost (**[hook]**). **Joining them into "the wait fixes it" is [inferred]**, and
the honest way to retire that is to build it and watch. **§13 row 17, and it blocks shipping.**

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

**TTFA on the chosen voice, measured from a real `Stop` hook: median 1.22 s, 28/30 under 3 s**
(n = 30, `bf_emma`, resident worker) **[hook]**. **Cold — no resident worker — is median 3.16 s, range
2.66–5.50 s (n = 7), and FAILS the 3 s line at 4 of 7 turns** **[hook]**.
[`worker-residency.md`](worker-residency.md), [`residency-timings.tsv`](residency-timings.tsv).

**The bench-harness figure is still correct for what it measures, and it is not what a hook delivers.**
**12/12 under 3 s, median 0.86 s, max 1.20 s** on `bench/first-sentence.py` **[heard]** #13; `bf_emma`
produces **0.927×** `af_heart`'s audio duration, so #9's margin, measured on the rejected voice, needs
no revision. **This closes the loose end #9 recorded** and the draft carried forward. **The ~0.37 s
difference between 0.86 s and 1.22 s is now decomposed rather than assumed: 0.08 s of it is hook
overhead** (the hook-to-worker handoff is a measured median 0.079 s) **and ~0.29 s is
`Kokoro.create()` running cooler outside a back-to-back loop** — median RTF **0.354** from a hook
against 0.242–0.295 on the bench. **"Resident" and "hot" are not the same state**, and §4's original
number was measured in the hotter one. The two medians will never match; that is expected, small, and
inside budget.

> **Read the warm figure with its load sensitivity attached, which is the honest replacement for the
> caveat this block used to carry.** The two warm failures were **4.014 s** at 1-minute load **11.9**
> and **3.829 s** during a machine spike — both **synthesis-time blowouts** (RTF 0.882 and 0.716), not
> hook overhead; the handoff on those turns was 0.133 s and 0.198 s, normal. **So warm TTFA is
> dominated by `Kokoro.create()`, which is CPU-contended, and it occasionally exceeds 3 s on a loaded
> machine.** What the data does *not* support is a claim that the warm path is unconditionally under
> the line. The machine during these runs carried three to four other Claude Code sessions — not a
> typical single-user deployment, and also not nothing. **[hook]**
>
> **The sentence that used to sit here — *"§10.5's unspecified worker lifecycle is what stands between
> the spec and that number"* — is now false and is deleted rather than softened.** §10.5 is specified
> and measured (a lazy, self-electing, per-session resident worker), and the mechanism moves the cold
> start off the user-visible path on the very first turn of a session: **median 1.71 s, range
> 1.37–3.83 s, 4/5 under the line** when the message streams in more than one chunk and its first
> chunk leads the end of the turn by more than the worker's 1.33–2.02 s startup **[hook]**. Where it
> does **not** cover the cold start is stated in §10.5 clause 4, not hidden here.
>
> **Every cold figure in this project is optimistic by an unmeasured margin, and this is where that
> belongs rather than only in a footnote.** "Cold" here means **no worker process resident**, with the
> 310 MB `kokoro-v1.0.onnx` and 27 MB `voices-v1.0.bin` still **warm in the page cache** from an
> earlier run. That applies to the 3.16 s median above, to its 2.66–5.50 s range, and to #6's **3.93 s**
> — which sits inside that range, so nothing here contradicts #6, it locates it. Purging the page cache
> needs `sudo`, which this machine's user does not have, so this is a **closed environment limitation
> and not an owed measurement**. It cannot flip a verdict: **cold already fails the 3 s budget at 4 of
> 7 turns without any page-cache penalty**, and a larger number makes an already-failing case fail
> harder.
>
> > **One arithmetic correction to the source document, made here because the data is committed and
> > checkable.** `worker-residency.md` states this as *"3 of 7 cold hook turns are over the line"*. Its
> > own table and [`residency-timings.tsv`](residency-timings.tsv) say otherwise: the `cold7` rows are
> > **5.441, 5.496, 4.489, 3.161, 2.954, 2.951, 2.657** s, so **4 are over 3 s and 3 are under**
> > **[measured-here]**. The pass count (3/7) and the fail count (4/7) were transposed in the prose.
> > **It changes nothing** — the conclusion is that cold fails the line either way — but the figure
> > used throughout this spec is **4 of 7 over**, and the source document's sentence should be
> > corrected when someone next touches it. **It is also the reason every cold-failure count in this
> > document has to be read against the data rather than against its neighbours: this file states the
> > pass count in one place (§10.5's alternatives table, "3 of 7 under the line") and the fail count in
> > five others, and both phrasings are correct.**
>
> **The residual case, on the record rather than implied: the first turn after a boot, or after genuine
> memory pressure, on a 16 GB machine — and the residency mechanism does not help there, because it
> only pays off once a worker exists.**
>
> #5's ~4.9 s first synthesis after a **sleep/wake** stands unchallenged and unmeasured here; nothing
> in this project has slept the machine. §13 row 12.

**The sanitizer set: #8's seven axes as amended by #13.** Rules A–K, with:

| axis | setting | margin |
| --- | --- | --- |
| 1 backticks | `tick-pause` — commas around each `` `span` `` | 2–0, 1 tie |
| 2 line breaks | **conditional: `,` for ≤ 3 boundaries, `.` for ≥ 4** — §4.1, rule B′, shipped as `lb-auto` | listener's call, 2026-08-25; **heard** on `s38` **[heard]** |
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

### 4.1 LOCKED — axis 2 is a **conditional** boundary: `,` for ≤ 3 boundaries, `.` for ≥ 4

**Axis 2 was carried as "deliberately undecided inside the noise floor" on a 1–1–1 tally. That
framing was wrong, and once corrected the axis was decidable.** It is now **closed**:

> **The line-break boundary is `,` when the run plants 3 boundaries between two items or fewer, and
> `.` when it plants 4 or more.** Decided by the listener directly, 2026-08-25. **The unit is
> boundaries, not segments** — that was corrected on 2026-08-25 and clause 3 below is the correction.

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

> **Rule B′ (conditional boundary).** For each run of line-break-separated items, count the
> **boundaries** the run plants between two items. Replace the line breaks with **`, `** if the count
> is **≤ 3**, and with **`. `** if the count is **≥ 4**. A line already ending in a `BOUNDARY_CHARS`
> member keeps it, unchanged from rule B's existing behaviour (`bench/sanitizers.py:157-159`). **A text
> with no boundary between two items has no run and takes the fixed `opts.boundary`** — see clause 3.

**Implemented and shipped**: `rule_Bprime_conditional`, `count_boundaries`, `COND_CUTOFF = 4`,
`Axes.boundary = "auto"` in `bench/sanitizers.py`, selectable as the variant `lb-auto` and composed
into `settled`. `count_boundaries` iterates **rule B's own compiled pattern**, `_B_BREAK_RE`, and
subtracts only the one intentional exclusion — a match reaching the end of the text — so a change to
what rule B treats as a break flows into the count instead of having to be mirrored. **[repo]**
[`settled-set-audition.md`](settled-set-audition.md).

Three qualifications, stated plainly rather than smoothed over.

**1. The cutoff's *position* is the listener's call, and it is now CONTRADICTED at 4 by the only wav
that has ever tested it.** The three original verdicts are consistent with it — `r09` paragraph-heavy
is indistinguishable either way, `s37` at 8 boundaries picks `.`, `s38` at 3 boundaries picks `,` — and
the corpus jumped 3 → 8 with nothing in between. **One wav now sits at the seam and it went against the
file.** `s04` has **4 boundaries**, where `COND_CUTOFF = 4` picks `.`; on that item B′'s `.` is
byte-identical to `base`, so the pair played was `base`'s full stop against a forced comma, and
**the comma won, blind** **[heard]**.

**`COND_CUTOFF` stays at 4, and that is a decision rather than an omission.** Three reasons, all of
them about what one wav can and cannot carry:

- **One wav cannot pick between the two repairs.** `s04` is a lead-in line, three bullets and a closing
  sentence: 4 boundaries, 3 bullets. **A cutoff of 5 explains the verdict; so does a count that
  excludes a trailing non-list line**, which would make `s04` count 3. Both predict `,` there, and they
  diverge only on shapes the corpus does not contain. Moving the constant would silently pick one.
- **It is one point at one end of a band that is still empty at 5, 6 and 7.**
- **Moving it costs a re-audition of two items — and NOT of the sweep that was just heard.** An
  earlier version of this bullet said a cutoff of 5 *"would invalidate the sweep"*, on the strength of
  `lb-comma` differing from `base` on **17 of 54** items. **That 17 is a measurement of a different
  question** — it is the reach of a *fixed* comma against a fixed full stop, which is the axis as #8
  originally posed it, and it says nothing about where the conditional rule's cutoff sits. **The
  figure that answers this question is 2.** Moving `COND_CUTOFF` from 4 to 5 changes `settled`'s
  output on **2 of the 54** corpus items — `s04` and `s05`, the only two the composed pipeline hands
  to B′ at exactly 4 boundaries — and on **none of the nine items in the 9–0 sweep**, whose boundary
  counts are 0, 0, 0, 1, 2, 3, 11, 11 and 17 **[measured-here]**. On B′ in isolation (`lb-auto`
  against `base`) the move reaches **3 of 54**: `s07` joins, because `settled`'s code-block rule
  collapses two of its four raw boundaries and B′ never sees them. **So the reason to leave the
  constant alone is the first bullet, not this one** — the sweep is not at risk, and one wav cannot
  pick between the two repairs.

So the band is **no longer merely unaudited — it is contradicted at 4**, and that is strictly worse
news than "unaudited" while being strictly better evidence. §13 row 5 carries it. What the next listen
on this axis wants: wavs at 5, 6 and 7, **and** an `s04` variant with the closing line removed, which
is the only pair that can separate the two repairs.

**2. B′ EXISTS. This qualification is discharged.** It used to read *"no registered sanitizer
implements this, so it has to be built"*, with the consequence that the §4.2 confirmation listen could
not include axis 2. **Both are now false.** B′ is implemented as `rule_Bprime_conditional`, registered
as the variant `lb-auto`, and composed into `settled`; the registry is **28** sanitizers, not 26
**[repo]**. **Axis 2's "never heard" caveat comes off with it:** B′ as shipped was played in isolation
against `base` on `s38` and **won, blind** **[heard]**. Axis 2 is no longer the one axis adopted
without a wav behind it.

**3. What the count counts — CORRECTED 2026-08-25, from segments to boundaries, and this was a live
violation of locked text until this revision.** The clause used to read *"the items of a run are the
non-empty segments a `\n+` split produces"*. That is wrong at **both** ends, measured
**[measured-here]**:

| what the old clause said, read literally | its scope in `corpus/spoken/` | what the shipped code does |
| --- | --- | --- |
| a list's segments include its lead-in line, so **every list counts ≥ 4 and takes `.`** | **8 of 8** bullet-carrying items — the segment count strictly exceeds the bullet count on every one | counts boundaries, so `s38` takes `,` and B′ can actually fire the `,` it exists to produce |
| a one-line message is **1 item, so ≤ 3, so `,`** — it would end on a comma | **31 of 54** items are single-segment | no boundary between two items means **no run**, so the fixed `opts.boundary` (`.`) applies |

**Both halves have to land together, and an amendment that only swapped the word "segments" for
"boundaries" would have left the second one broken** — 0 boundaries is also `≤ 3`. So the replacement
clause carries the no-run sentence as well as the count:

> **Count the boundaries a run plants between two items** — equivalently, the non-empty segments a
> `\n+` split produces, **minus one**. A break at the very end of the text separates the last item from
> nothing and is not counted. Replace the line breaks with `, ` below the cutoff and `. ` at or above
> it. **A text with no boundary between two items has no run and takes the fixed boundary.** A
> paragraph break is counted exactly like a list break; two long paragraphs therefore count **1**.
> Bullet markers are not required and are not counted: `MD-BULLET` is silent or an em-dash pause
> depending on the spaCy tag, so the count is over **breaks between lines**, never over `-`
> characters.

**Why the correction goes this way round, and why it is settled by ear rather than by argument.** The
old clause contradicted §4.1's own rule block (*"count the items the run holds"*, ≤ 3 → `,`) and its
own qualification 1 (*"`s38` at 3 bullets picks `,`"*, cited as the verdict the cutoff rests on): under
the segment reading `s38`'s lead-in line gives it **4 segments** and forces `.`, the opposite of what
the listener chose. **And `s38` is the only one of the 54 corpus items where the two readings pick
different characters at all** **[measured-here]** — `s04` (4 boundaries / 5 segments) and `s37` (8 / 9)
land on the same side either way. **So `s38` is the whole discriminator, it was played blind, and it
went to boundaries** **[heard]**. One item is a thin instrument for most questions; for this one it is
the *complete* instrument, because it is the only item the question can be asked of.

**The worked example is corrected with it.** The old clause said *"a paragraph-only run of two long
paragraphs therefore counts **2** and takes `,`"*. Under the boundary count it counts **1** and takes
`,` — the same outcome by different arithmetic. **The number was wrong; the outcome was not.**

**What is still unheard here, unchanged:** nothing about the paragraph case has ever been played on
this axis. `r09`'s tie from #8 is the only evidence in either direction, and §15 still names it the
likeliest place the rule is wrong. The choice made — one run per message, paragraph breaks counted like
list breaks, **no blank-line special case** — is the cheaper of the two to reverse (one function), and
the alternative was rejected for a concrete reason rather than a preference: blank lines delimiting
runs needs a rule for which character goes *at* a run boundary, and **no verdict anywhere bears on
that**.

### 4.2 CLOSED — the settled combination was built, registered and heard

**This section was the first of #11's three ship blockers and it is discharged.** It used to read
*"26 sanitizers are registered and not one of them is the settled set"*, with a requirement attached:
register the composition as a single named variant and give it one confirmation listen before speech
ships. **All three clauses are done** — [`settled-set-audition.md`](settled-set-audition.md),
[`audition-verdicts-11.tsv`](audition-verdicts-11.tsv):

1. **Rule B′ exists** (`rule_Bprime_conditional`, selectable as `lb-auto`) — §4.1 qualification 2.
2. **The composition is registered as one variant, `settled`**, with the nine axis values of §4's
   table composed in `_pipeline`'s order, no edits. The registry is **28** sanitizers **[repo]**.
3. **The confirmation listen happened: 2026-08-25, blind, `bf_emma`, 24 wavs, all 14 pairs scored.**

**The result: `settled` won every pair it was in — 9–0** **[heard]**. `r03`, `r06`, `r09`, `r11`,
`r13`, `s03`, `s13`, `s28`, `s38`. **Five of the nine are real rewrites**, and `base` never once beat
the composition. Sides alternated (`settled` was A on three and B on six **[repo]**), so the sweep is
not a side bias. **The sanity pair passed**: `r06:none`, `base` against untouched text, went to `base`
**[heard]** — sanitizing beats raw, so the instrument was measuring something.

**What that closes, exactly.** **No axis reopens** — every margin in §4's table stands and nothing in
the listen was a re-vote. The interaction the listen existed to catch was **found by text measurement
before anyone listened, is on a real item, and was then heard and tolerated** — see §4.3, which is
where it changes a claim. Group C's triangulation (`s03:tick-pause` and `s03:ext-word`, both to the
settled half **[heard]**) came back **consistent rather than diagnostic**: there was no bad pair to
attribute, so the triangulation was never needed, and it is recorded as the negative result it was
built to be able to have.

**Two measured results from building it that the spec depends on elsewhere.** **[measured-here]**

- **Crash safety re-verified over the composition, which is what §12's constraint actually needs.**
  Every one of the 54 items was phonemised under both `base` and `settled` with `kokoro-onnx`'s own
  tokenizer and split with `Kokoro._split_phonemes`: the **worst batch under `settled` is 509
  phonemes** (`r13`) and **nothing exceeds 510**. No synthesis and no model load were needed to
  establish it. Both `.` and `,` are members of `BOUNDARY_CHARS` — the splitter's own set — so B′
  switches prosody **without ever changing whether the text chunks** **[repo]**.
- **A latent rule-B bug was found and fixed while B′ was built, and it is the kind that would have been
  invisible in production.** `_B_BREAK_RE` was `(\S)[ \t]*\n+[ \t]*`, and **`\n+` stops at a line that
  is blank only to the eye**: a "blank" line holding one space or tab split the run, and rule B left a
  **raw newline in its own output** — `"a\n \n b"` sanitized to `"a. \n b"`, which is the
  `SPLIT-NEWLINE` hazard rule B exists to remove, produced by rule B. It is now
  `(\S)[ \t]*(?:\n[ \t]*)+`. **No item in `corpus/spoken/` contains a whitespace-only line**, so it
  could not fire on anything auditioned and no wav was affected — but **real assistant text is not
  guaranteed to be tidy**, so it was latent rather than harmless. §3.4's harmless classification of
  `SPLIT-NEWLINE` depends on rule B not doing this.

**What it does NOT close, stated so the 9–0 is not over-read.**

- **`COND_CUTOFF`'s position.** The one wav at the seam went against the file — §4.1 qualification 1,
  §13 row 5. The composition is confirmed; the constant inside it is contradicted.
- **B′'s reach on real text.** B′ is a **measured no-op on all 14 real rewrites and on 53 of the 54
  corpus items** — the only item it changes is `s38`, which is synthetic **[measured-here]**. **What
  the listen confirmed is the rule's direction, not its reach.** Its closing condition is the same
  shape as `flag-pause`'s: a real capture with a short list whose lines do not already end in
  punctuation. This is a **new** caveat of §4.3's class and it is recorded here rather than left out
  because the pair it rests on won.
  > **Two item counts are in play in §4 and they are different sets, so do not read one as
  > contradicting the other.** `corpus/spoken/` holds **54** items of which **14** are real, and that is
  > the set B′'s reach is measured over. #13's audition ran over **12** real rewrites, and that is the
  > set `flag-pause`'s no-op (§4.3) was measured over. **[repo]**
- **Anything about the paragraph case on axis 2**, `MD-FENCE-MULTI`, or `flag-pause`'s reach.
- **A defect in a shipped axis that no measurement here could see: a slash-terminated path gets no
  pause.** Found by ear during this listen, in axis 3, which ships at 4–0. §13 row 18 carries it in
  full; it is **deliberately parked**, not overlooked.

### 4.3 OPEN — `flag-pause` has no real carrier, and its "no regression risk" claim is FALSE inside the settled set

> **CORRECTED 2026-08-25.** This section used to say `flag-pause` *"ships free of regression risk: it
> cannot change a word of today's real output."* **That is true of `flag-pause` on `base` and false of
> `flag-pause` inside the settled set**, which is the only place it actually ships. The sentence is
> replaced rather than softened, and it is worth noticing *how* it was wrong: the no-op was measured
> one axis at a time, against `base`, which is exactly the reading §4.2 existed to warn about. **The
> composition was the thing that had to be measured, and when it was, this claim did not survive.**

**The original gap stands, unchanged.** `flag-pause`'s value rests entirely on output shapes production
has not produced. All four discriminating pairs are synthetic (`s15`, `s16`, `s17`, `s28`), and the
question `s28` raises — five commas in two sentences, help or stutter? — has been answered only on
`s28`. Same gap class as `MD-FENCE-MULTI`. **[heard]** #13.

**What is new is that the composition is not a no-op, on a real item, in both directions.**
**[measured-here]**:

| item | what happens inside `settled` that happens under neither rule alone |
| --- | --- |
| `r11` (**real**) | **axis 1 strips the backticks axis 8 relies on stepping over.** `` `$CLAUDISH_OLLAMA` `` becomes `, $, claudish_ollama,` and `` `curl -K` `` becomes `, curl , -K,` |
| `r14` (**real**) | **axis 7 removes the carrier before axis 8 sees it** — `cb-count` eats the fence, so `flag-pause` is a **no-op** on `r14` inside `settled`, symmetrically to `r11` |

**`r11` was heard blind and `settled` still won it** **[heard]**. **State that at its real strength:
the artifacts were not audible enough to lose a pair, on one item, to one listener. That is TOLERATED,
not harmless.** The shapes are still in the output and they are still the mechanism §4.2 warned about.

**And the `r14` half was never played at all**, which is why the old sentence stays false as written
rather than merely needing a hedge: **half of the inversion has a verdict and half of it does not.**
A claim of "no regression risk" needs both halves, and one of them is unheard.

**Closing conditions, now two rather than one:**

1. **The original:** a corpus capture that puts a bare flag or `_`-joined identifier *outside*
   backticks in a real message — the shape that gives `flag-pause` a real carrier at all.
2. **New:** `r14:settled` played against `r14:base`, which is the unheard half of the axis 1 × axis 7 ×
   axis 8 interaction. Cheap — one pair — and it is the pair that would let this section drop the
   qualifier.

**The fix, if it is ever wanted, is a rule-scope change and not a re-vote** — which rule steps over
which spans — and nothing here reopens an axis.

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
runtime overrides. **[bin]** **Read the comparison, not just the number.** The guard is
`if (Or > 0 && Fr > Or)` and `Fr > Or` is **strict** on *tolerated* blocks, so a run of exactly 8
blocks is tolerated and the **ninth block executes before it is refused**. The ceiling is therefore
**nine invocations of the hook — one initial fire plus eight re-fires — and nine counts invocations,
not utterances.** Measured at exactly nine in three independent driven runs (named in the THIRD
CORRECTION below), with `stop_hook_active` **`false` on fire 1 and `true` on fires 2–9** in every run.
**[obs]** See [`stop-hook-block-mechanics.md`](stop-hook-block-mechanics.md).

**So the hazard is not "any error holds the prompt hostage" — it is much more specific, and that
makes it more real, not less.** A speech hook that exits 1 because a binary was missing loses nothing
but the utterance. A speech hook that exits **2** holds the user's prompt open and is re-fired
**eight** times — **nine invocations in all. [obs]**

**Four further facts about the loop, all observed on the wire, and one of them adds a requirement this
section did not previously have.** **[obs]**
[`stop-hook-block-mechanics.md`](stop-hook-block-mechanics.md):

- **A blocking hook's stderr is PROMPT INPUT to the model.** It is delivered as a synthetic user
  message — `Stop hook feedback:` followed by `[<command>]: <stderr>` — and in the driven run **the
  model demonstrably acted on it**, saying a different word on each fire because the stderr asked it
  to. **Requirement: on `Stop`, stderr is not a diagnostic channel.** Anything `speak.sh` writes there
  can reach the model as an instruction. §10.1's `CLAUDISH_DEBUG` sink is already
  `$BUF_ROOT/debug.log` and it must stay a file — **do not add an `echo ... >&2` debug line to this
  hook, on any path.** This is a second, sharper reason for exit 0 on every path, independent of the
  block loop.
- **A NON-blocking hook's stderr is not prompt input.** The negative control: **exit 3 produced one
  fire, one warning line to the user, and nothing in the model's context.** So the retraction of "any
  non-zero exit blocks" is confirmed on the wire and not only in the resolver's source.
- **The post-cap override is invisible to the model and visible to the user**, as one `level:
  "warning"` line quoting the binary verbatim with the count interpolated. **A hook cannot detect that
  it has been overridden**, so no design may branch on having been capped.
- **`prompt_id` is constant across all fires of a turn.** Offered as an observation; §5.1's text hash
  already covers the case that matters, and §3.2 explains why `prompt_id` is a pre-filter rather than a
  key.

**Nine is an invocation ceiling, not an utterance count, and the two are different costs.** How much
the user actually hears depends on things the invocation count says nothing about: whether an
invocation reaches the speech call at all before it exits 2 — the bash-syntax-error bullet below is a
path where it does not — whether synthesis and playback then succeed, and §5.1's `spoken` hash, which
exits 0 on text it has already sent to synthesis. So **a message that does not change is spoken at
most once, however many times the hook runs**: the hash bounds duplicate *attempts*, and it cannot
promise even the one utterance. **This design cannot speak the same message nine times, or twice.**

**§3.5.1's bounded wait does not weaken that — but the chain that says so is weaker than an earlier
version of this paragraph claimed, and the overstatement is corrected here.** That version said the
producer rename, the abandoned wait and the single-outstanding-wait rule together make nine invocations
*"reach synthesis at most once even before §5.1's hash is consulted"*. **They do not.** The rename
coalesces only what is **unconsumed** — §10.5 clause 1 says so in as many words — and a `Stop` ladder is
not one burst: each re-fire follows another model response, seconds apart, so the worker has ample time
to claim, synthesise and play one job before the next arrives. On the raw path (§3.3) there is no wait
to abandon at all. **So the worker can reach synthesis several times over one ladder, and what bounds it
is not coalescing.** Three things bound it, in this order: **§5.1's `spoken` hash**, which is the only
one that makes *unchanged* text a single attempt however many jobs land; **§10.6's kills**, which stop a
superseded utterance rather than preventing it; and the rename, which settles the narrow unconsumed
case. **A reader who suspects the new mechanism turned an invocation ceiling into an utterance count
should follow that chain — it does not, but the load-bearing link is the hash, not the rename.**

Additional utterances require the resolved text to *change*, and **how often it changes on its own is
not established.** Two ladders have been observed and only one of them was left to itself. The
undriven run answered the same word on all nine fires — **nine fires, one distinct string [obs]**,
which §5.1's hash speaks at most once. The run that produced **eight distinct `last_assistant_message` values across the
nine fires [obs]** produced them because its stderr *instructed* the model to say a different word
each time. That second run proves the text **can** move — which is what makes additional utterances
possible at all, and what makes §5.1's rejected `stop_hook_active` rule unsafe — but it measures an
induced rate, not a natural one. Dedup suppresses genuine repeats; it cannot suppress a turn whose
text keeps moving, and §5.1 argues that it should not.

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
> was read wrong once, and the unit was carried wrong three times: in the original sentence, in the
> correction that fixed the count, and in the title of the branch that carried the correction, which
> read *"nine utterances, not eight"* until a reviewer noticed it contradicted the paragraph it was
> shipping. **The rule this section now holds to: nine is an invocation ceiling and never an utterance
> count; what reaches synthesis is §5.1's, and for text that does not change §5.1 permits at most
> one.** §5's conclusion is unaffected by any of it.

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
  not in either earlier version: an unbalanced `fi`, `done`, or quote does not fail one turn, it can
  **block turn after turn** — up to nine invocations each, and **zero utterances** wherever the broken
  construct encloses the speech call. Both halves are conditional on where the break landed relative
  to the code that runs first: a script that reaches an `exit 0` before the parser reaches the break
  exits **0** and does not block at all, measured below. It is also the single most likely defect in a
  shell script under edit. Mitigation is not a runtime guard
  — a guard cannot run in a file the parser refuses to get past — it is `bash -n` before the file
  ships, and keeping the file small.

  > **FOURTH CORRECTION — this bullet was wrong before this PR and wrong after it.** It said the error
  > "**blocks every turn** and speaks the same message 8 times each"; the correction above changed the
  > 8 to a 9 and left the mechanism untouched. **The two halves cannot both be true, and the utterance
  > half is the false one.**
  >
  > **The mechanism, at the granularity that actually decides it.** `bash` does not parse the whole
  > file before running any of it — but it does not proceed line by line either. **It parses one
  > complete top-level command at a time and executes that one, so the unit is the compound command,
  > not the line.** A complete top-level command that finished parsing before the break has already
  > run. A command *inside* the unterminated construct never runs — even though it sits textually
  > **before** the point where the parse fails. **[measured-here]**, `bash 3.2.57(1)-release` on Darwin
  > 25.6.0, every variant exiting **2** except the last:
  >
  > | script shape | does the body command run? | exit |
  > | --- | --- | ---: |
  > | `echo` as a complete top-level command *before* an unterminated trailing `if` | **yes** | 2 |
  > | `echo` **inside** that unterminated `if`, textually before EOF | **no** | 2 |
  > | `echo` *after* the unterminated `if` | **no** | 2 |
  > | `echo` before an unterminated quote | **yes** | 2 |
  > | `exit 0` reached before the break | n/a | **0** |
  >
  > **The first version of this correction got the mechanism wrong in the other direction**, claiming
  > everything textually before the break "has already run". Row 2 falsifies that, and row 2 is the row
  > that matters: a speech call in a hook is nearly always *inside* the `if`, `case` or loop that
  > broke, so it is exactly the command that does not run.
  >
  > So the real cost is **nine invocations and zero utterances whenever the parse fails before the
  > speech call has run** — the usual arrangement, since an unbalanced `fi`, `done` or quote generally
  > *encloses* the body it broke. Where the speech call is a complete top-level command that parsed
  > before the break, it does run on every fire, but §5.1's hash still speaks each distinct message at
  > most once. **Nine utterances of the same message was never reachable on any arrangement.**
  >
  > **Stating it accurately makes this hazard worse, not better.** Its likely shape is **silent**:
  > where it blocks at all, the prompt hangs through nine fires, the user hears nothing, and the only
  > surface is the runtime's single post-cap warning line. A hook that spoke nine times would at
  > least have announced itself. The same measurement settles the opposite tail — an `exit 0` the
  > script reaches *before* the parse failure exits **0** **[measured-here]**, so a broken file is not
  > even reliably a blocker;
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
> re-fires under `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`'s default of **8 tolerated blocks** (the comparison
> is strict, so the ninth block runs and is then refused), which is **nine invocations of the hook in
> total [obs]**. **Nine counts invocations and never utterances:** what reaches synthesis is §5.1's
> business, and for a message that does not change it is **at most one**. The two
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
fire 1 and `true` on fires 2–9, every run. **[obs]** That run's stderr *asked* the model for a
different word on each fire, so what it establishes is that the text **can** move across the ladder —
which is all this section's argument needs, since a rule that would speak the first value and swallow
the other seven is condemned by one such turn. It is **not** a measurement of how often the text moves
unprompted; §5 states that limit, and the sibling run whose text never changed is the case the hash is
for.
[`stop-hook-block-mechanics.md`](stop-hook-block-mechanics.md)

**Specification.**

- **`speak.sh` reads `stop_hook_active` for no behaviour at all.** Log it under `CLAUDISH_DEBUG` if
  useful; branch on it never.
- **Deduplication compares the message text**, and it reuses machinery §3.1 already specifies rather
  than adding any:

```
$BUF_ROOT/<session_id>/speak/spoken   # sha256 of the text last actually sent to synthesis
```

  Before speaking, hash the text about to be spoken and compare. Equal → stop, silently. Different →
  write the new hash, then speak. Same depth-2 directory, so `rewrite.sh:117`'s existing sweep reclaims
  it (§3.1); same hashing the handoff match already needs (§3.2).

  > **AMENDED 2026-08-25 — the check moved, the rule did not.** §3.5.1's bounded wait means the
  > resolved text is not known when the hook exits, so the hook cannot hash it. **The check happens at
  > the point of synthesis, in the worker** — which is what this section's own words already describe
  > (*"the text last actually sent to synthesis"*) and is where it should always have been. Two things
  > make that safe rather than a new race: §3.5.1 clause 5 keeps **at most one wait outstanding per
  > session**, so there is exactly one consumer and no test-and-set is needed; and the worker is the
  > only process that ever calls `create()`. §10.3 records it as a change to step 8b. **The rule is
  > unchanged: equal → silent, different → write and speak.**

**What this buys, stated precisely.** It suppresses a genuine re-fire of the **same** text — the case
the flag was reached for. It does **not** suppress the blocked-turn sequence, and that is correct: if
text A was already spoken and Claude then produces B, A cannot be un-spoken, so speaking B as well is
the best behaviour available. The old rule would have spoken A and swallowed B.

**One accepted cost:** if Claude legitimately ends two consecutive turns with byte-identical text, the
second is silent. Rare, and silence is the safe direction. **Observed twice in 44 captured messages**
(the same prompt re-driven, answered the same way) **[obs]**, so "rare" now has a number against it
rather than being an assertion — and in those two cases the buffered rewrite was a rewrite of that same
text, which is §3.2's benign collision seen from the other side.

**A scope note, so the blocked-turn ladder is not read into the ordinary case.** `stop_hook_active` was
**`false` on all 35 fires** of the handoff measurement **[obs]** — none of those turns was blocked. The
ladder in this section is a driven, deliberately provoked shape; nothing about it was observed to happen
on its own in 35 ordinary turns.

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

> **Measured, and this is the number this section has always wanted: 0.063–0.219 s, median 0.086 s.**
> Forty-seven hook processes, wall time from the hook's first in-process clock read to its last trace
> line, cold invocations inside that range rather than above it **[hook]**. §10.4's declared
> `"timeout": 10` therefore has at least **45× headroom** against the slowest hook observed.
>
> **§3.5.1's bounded wait does not spend any of that, and the design is arranged so that it cannot.**
> The wait lives in the resident worker, never in the hook body: the hook renames a job into place and
> exits. The residency mechanism does not change the number above either, because the hook drops a file
> and leaves **whether or not a worker exists** — measured directly by inserting a 20 s artificial
> delay before model load and driving a real turn against the 10 s declared timeout: **hook wall time
> 0.083 s, worker ready 21.1 s later, audio 23.3 s after the hook fired, turn ended normally, nothing
> on screen, no error** **[hook]**. **Late, not lost, is the failure mode**, and it is the right one —
> but it is a real cost and §10.5 says so out loud rather than leaving "what if a cold start outruns the
> timeout" as an open question.

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
killed mid-utterance. `setsid`-style detachment would prevent it. **Still unobserved**; closing
condition is one detached-sleep-and-check probe.

> **One side observation that touches this and does not close it.** §10.5's worker calls
> `os.setsid()` on its first line — macOS ships no `setsid(1)` in the base install, so it has to be
> done in-process — and after the driven session was exited with `/exit` the worker **was still alive
> and still resident** **[obs]**. That shows only that a `setsid()`-detached child survives the session
> that spawned it. **A non-detached child was never tested**, which is the actual question. §13 row 9
> stays open, and this is one more reason to detach rather than a reason to stop caring.

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

**The question behind it is now ANSWERED, and the answer is the benign one.** This section used to
say the default was cheap to reverse but rested on an unobserved question: *whether `Stop` fires again
when the woken session finishes.* **It does.** Two driven turns delegated to a subagent and each
produced **two** `Stop` fires, and the second was not a re-fire **[obs]**
[`handoff-match-rate.md`](handoff-match-rate.md):

- **fire 1** ends the turn with `background_tasks: [{type: "subagent", status: "running"}]` — the shape
  §2 records — and its own `prompt_id`;
- the subagent completes; the harness injects a `<task-notification>` **as a user message**, visible in
  the transcript; the main thread answers it;
- **fire 2 is an ordinary new turn**: new `prompt_id`, `background_tasks` empty,
  `stop_hook_active: false`, its own `MessageDisplay` stream, and §3.2's key matched it exactly like any
  other turn.

**So the wake is not an edge case the key has to survive — it is a turn, and the key handles it with no
special case.** **[obs]** on two samples.

**The observed consequence, written down as a consequence rather than left as a hope: a delegated turn
is announced ONCE, late.** Suppression silences fire 1 and lets fire 2 through, so the user hears the
answer when the subagent's result comes back rather than when the turn technically ended. **That is
very likely the wanted behaviour** — it is the behaviour the default was reaching for — but it was a
hoped-for outcome before this measurement and it is an observed one now. **Suppression can no longer
lose the announcement entirely**, which was the worst outcome the default was hedging against, so the
default's risk profile improved rather than merely being confirmed.

**It remains cheap to reverse — one condition.** Two samples is two samples.

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

**No variable is added for §3.5.1's bounded wait, and that is deliberate.** The wait's deadline is
`CLAUDISH_TIMEOUT + 5` seconds, read from the **same** env var `rewrite.sh:65` reads for the LLM call it
is waiting on. A `CLAUDISH_SPEAK_WAIT` of its own could be set to a value that disagrees with the budget
it is waiting for, at which point the wait either gives up on a publish that was still coming or waits
for one that can no longer arrive. **Deriving it makes the agreement structural**, and `CLAUDISH_*`
values being frozen at session launch (`rewrite.sh:58-60`) means both hooks see the same frozen number.
§9's posture applies: a knob nobody has justified does not ship.

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
| `$BUF_ROOT/<session_id>/speak/` | `rewrite.sh` and `speak.sh` write, the worker reads and writes | §3.1. Depth-2 directory so `rewrite.sh:117`'s existing sweep reclaims it. **Everything below lives under this one directory**, which is what keeps the whole feature inside a single sweep-reclaimed path. **It is no longer flat** — `playerdir/` is one level deeper (§10.5 clause 7(i)) — but the `rm -rf` that reclaims `speak/` reclaims it too, and nothing at depth 3 is separately selectable by `:117`'s `-maxdepth 2 -type d`. |
| `$BUF_ROOT/<session_id>/speak/rw.<hash>` | `rewrite.sh` writes, **behind `CLAUDISH_ENABLED`, the global off-file, and `CLAUDISH_SPEAK`** (§10.3, §11) | §3.1. **Content-addressed: `<hash>` is `sha256( trim( original text ) )`, so the path is the proof of provenance.** Installed by temp-file rename inside this directory. **Never overwritten with different provenance, and there is no `speak/source`** — a consumer opens the single path its own expected hash names and compares nothing. Not pruned by the producer; the sweep reclaims the directory. |
| `$BUF_ROOT/<session_id>/speak/prompt_id` | `rewrite.sh` writes, same gates | §3.1. **Diagnostic only — nothing keys on it** (§3.2, §13 row 4). |
| `$BUF_ROOT/<session_id>/speak/job` | `speak.sh` writes by atomic rename; the **worker** claims by renaming it to `job.taken.<pid>` | §3.5.1 clause 1, §10.5 clause 1. Carries the fire time, the expected source hash, and the mode. A read-then-unlink of `job` would lose a job renamed in between, irrecoverably. |
| `$BUF_ROOT/<session_id>/speak/worker.lock.<gen>` | the **worker** creates, by `symlink` | §10.5 clause 2. A **symlink whose target is the owner's pid**: `symlink(2)` publishes the record and its content in one exclusive-create, so there is no pid-less state to interpret. The owner is the creator of the **highest** generation; a dead owner is superseded by `<gen>+1`, never removed. **Not reclaimed by `rewrite.sh:117`** — a symlink at depth 3 is selected by neither `-maxdepth 2` nor `-type d`. |
| `$BUF_ROOT/<session_id>/speak/spoken` | the **worker** writes, at the moment text goes to synthesis | dedup hash (§5.1, as amended by §3.5.1 clause 6) |
| `$BUF_ROOT/<session_id>/speak/playerdir/<pid>.<nonce>` and `playerdir/<nonce>.pending` | the **player's wrapper** publishes its own record before it can make a sound; the **worker** writes the `.pending` marker before the fork | the preemption records (§10.6, §10.5 clause 7(i)). **One shared `speak/pid` must not be used**, and **the record must be unlinked by exact name only**: an older player's reap otherwise erases a newer player's registration, which is measured in [`preemption-and-lock-protocol.md`](preemption-and-lock-protocol.md) §4b(i) (`C14a` against `C14b`) and is not re-derivable from `preemption-trials.tsv` alone. **The writer changed twice**: §10.6 was written for a design where the hook spawned the speech child, and the single worker-written `speak/pid` that replaced it is itself superseded. |

`BUF_ROOT` is **not** redefined in `speak.sh` as a new constant with a new default — it is the same
`"${TMPDIR:-/tmp}/claudish-to-english"` string as `rewrite.sh:69`, and the two must not be able to
drift. A shared snippet or a literal with a comment pointing at `rewrite.sh:69`; the spec does not
care which, only that drift is impossible by inspection.

### 10.3 LOCKED — order of operations inside `speak.sh`

Specified as an order because the cheap rejections must precede everything, for §11's reason.

0a. **`CLAUDISH_ENABLED` is exactly `1`, else `exit 0`** — the plugin's **master** switch, tested the
   way `rewrite.sh:100` tests it: `[ "$ENABLED" = "1" ] || pass_through` **[repo]**. **Before reading
   stdin.**
0b. **The global off-file `${CLAUDISH_OFF_FILE:-$HOME/.claude/claudish-off}` does not exist, else
   `exit 0`** (`rewrite.sh:61`).
1. `CLAUDISH_SPEAK` is `1`, else `exit 0`. **Before reading stdin.**
2. `CLAUDISH_SPEAK_OFF_FILE` does not exist, else `exit 0`. **This check does not carry the whole mute
   promise on its own** — the worker re-checks both off-files at the point of synthesis, because the
   hook's `stat` can be up to `CLAUDISH_TIMEOUT + 5` s older than the sound (§3.5.1 clause 7).
3. `jq` present, else `exit 0`.
4. Read the payload; `exit 0` if empty.
5. **Not a `stop_hook_active` check** — see §5.1; that flag is read for no behaviour. Dedup happens at
   step 8b instead, on the text.
6. `background_tasks` has no `status: "running"` entry, else `exit 0` (§8).
7. `last_assistant_message` present and non-empty, else `exit 0` (§2).
8. **Classify via §3.5's decision table** — compute `prose_len`, compute
   `H = sha256( trim( last_assistant_message ) )`, test `[[ -f speak/rw.<H> ]]`, and run the eight-class
   hazard gate if the buffer missed and `prose_len` is below `MIN_CHARS`. `exit 0` if the table says
   silent. **The hit test is an existence check on one computed path, not a read-and-compare** (§3.1).
8b. **~~Dedup on the resolved text~~ — MOVED.** On the waiting row the resolved text is not known here,
   so the hook cannot hash it. The dedup check against `speak/spoken` happens in the worker, at the
   moment text goes to synthesis (§5.1 as amended, §3.5.1 clause 6). **Nothing in the hook reads or
   writes `speak/spoken`.**
8c. **Preemption, before the job is dropped:** `readdir` `speak/playerdir/` and `kill` each record's
   pid (§10.6, §10.5 clause 7(i)). The hook does this; the worker's claim-time kill covers the case
   where the read saw no record yet. **Every record is validated before it is signalled** — the name
   must match `<digits>.<nonce>` and the pid must parse as a positive integer; a record whose name
   does not parse is **skipped in silence, never signalled and never removed.** **The hook removes
   nothing at all**: unlinking is clause 7(v)'s, by exact name, after the worker reaps. A hook that
   tidied records it did not write would be the shared-`speak/pid` failure again, one level down.
   **The residual is pid reuse and it is [inferred], not measured** — a record left behind by a
   worker killed before it could reap names a pid the OS may have handed to something else, and this
   hook would then signal a stranger. `speak/` is per-session and reclaimed after 30 minutes, which
   bounds how long a record can outlive its player, but it does not bound the wrap-around.
   **Not closed here; §13 row 20's closing condition carries it**, and it is the same blast-radius
   question clause 7(iv)'s `.pending` bound answers on the worker's side.
9. **Write the job to a temp name and rename it onto `speak/job`** (§3.5.1 clause 1), ensure the worker
   exists (§10.5 clause 2 — one `readdir` for the highest `worker.lock.<gen>`, one `readlink` and one
   `kill -0`, and start it if not), and `exit 0` **without waiting for anything**: not for the worker,
   not for synthesis, not for the wait, not for playback.

**Steps 0a–0b are the whole of the *global* disable guarantee, and steps 1–2 the whole of the
off-by-default guarantee (§11) — but neither is the whole of the *runtime mute* guarantee**, which
needs the worker's re-check at the point of synthesis (§3.5.1 clause 7) because the hook's `stat` can
be 50 s stale by the time anything is audible; step 9 is the whole of the non-blocking guarantee
(§6). **Measured at
0.063–0.219 s, median 0.086 s, for the whole sequence** **[hook]** — a figure taken before steps 0a–0b
existed, and two more env-and-`stat` tests do not move it out of that range. **It also predates two
`readdir`s.** Step 8c and step 9 were a `stat` and a `[[ -d ]]` at fixed paths when that range was
measured; under §10.5 clause 2 and clause 7(i) they scan `speak/playerdir/` and `speak/` instead. **The
range is therefore a lower bound rather than a re-measured figure**, and §10.5 clause 4 states the same
caveat where the same scan runs five to seven times a turn. **[inferred]** that it stays inside
0.063–0.219 s; nothing has re-run the hook against a long session's directory.

> **Steps 0a and 0b were MISSING and that was a real hole, found in review.** `speak.sh` checked only
> the two speech-specific gates, so **a user who had switched the whole plugin off with
> `CLAUDISH_ENABLED=0` or a `~/.claude/claudish-off` file would still hear audio** — §10.8 promises
> *"`claudish-off` stops both"* and nothing implemented it. `rewrite.sh` returning early at `:100`
> does not help: `speak.sh` is a **separate process on a separate event**, and the two share no state
> but these files. **The raw path is what makes it bite.** §3.3 speaks the raw text below
> `CLAUDISH_MIN_CHARS` without needing any publish at all, so the master switch being off removes the
> *rewrite* the speech path would have waited for but not the speech: the hook would still elect a
> worker, still load a ~340 MB model, and still speak. **This is the same family as the
> `CLAUDISH_SPEAK` gap §11 fixed one round earlier, one level up** — that one was speech-specific,
> this one is the master switch.
>
> **`CLAUDISH_ENABLED` is read from the environment and the off-file is `stat`ed fresh** — from
> `rewrite.sh:57` and `:61` respectively, for the reason §10.1 gives: `CLAUDISH_*` is frozen at session
> launch, so only the flag file can stop a running session. **Neither is added to §10.1's table** —
> they are `rewrite.sh`'s existing vars, and inventing `CLAUDISH_SPEAK_ENABLED` beside them is exactly
> the drift §10.1 forbids.
>
> **The COMPARISON is normative and an earlier draft of step 0a got it wrong, which re-opened the hole
> it was written to close.** That draft said *"`CLAUDISH_ENABLED` is not `0`"* and cited
> `rewrite.sh:57`. **`:57` is not the gate** — it is `ENABLED="${CLAUDISH_ENABLED:-1}"`, the default
> assignment, and `:61` is the off-file clearing it to `0`. **The gate is `:100`, and it tests for
> exactly `1`** **[repo]**. Under the wrong comparison `CLAUDISH_ENABLED=false`, `=2` and `=yes` all
> **disable the rewrite and permit the speech** — the same off-by-default hole one value wide, in the
> hook whose whole purpose here is to close it. **Speech must be off wherever the rewrite is off, and
> the only way to guarantee that is to run the same test.**

**Steps 0a–2 must all precede step 3, and the ordering is load-bearing rather than stylistic.** Putting
an enable check after `jq` would make a speech-disabled user's turn depend on `jq` being installed and
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

### 10.5 LOCKED — the worker lifecycle

> **This heading read OPEN until 2026-08-25 and was called "the biggest gap in this spec".** Its own
> closing condition was *"pick a residency mechanism, then measure TTFA end-to-end from the hook, cold
> and warm, on `bf_emma`, against the 3 s line."* **That was done** —
> [`worker-residency.md`](worker-residency.md), [`residency-timings.tsv`](residency-timings.tsv), 39
> rows, every one produced by a hook process except the single offline concurrency race. **The result:
> cold from a hook is median 3.16 s and FAILS the line at 4 of 7 turns; warm is median 1.22 s and holds
> it 28 times in 30; cold-but-warmed-during-the-turn is median 1.71 s and holds it 4 times in 5.**
>
> **The last two are NOT disjoint populations, and the sentence above reads as though they were.** The
> 30-row warm set is 25 rows labelled `warm30` **plus** the five labelled `warm30+mdwarm5` — the
> warmed-during-the-turn rows are a **subset** of the warm rows, not a third arm beside them
> **[measured-here]**, [`residency-timings.tsv`](residency-timings.tsv). So **the 3.829 s failure is
> counted twice**: it is one of warm's two misses and the warmed set's single one. Nothing here is
> arithmetically wrong — 28/30 and 4/5 are both correct over their own rows — but "warm" is the
> superset and the reader should not add 30 and 5. On the 25 rows that are warm and *not*
> warmed-during-the-turn the median is **1.085 s** and the line holds **24 times in 25**.
> §4 carries the numbers and their limits. **The sentence "§4's TTFA table describes the bench
> harness's process, not this hook's" is retired: a hook's own table now exists.**

**LOCKED, unchanged:** the synthesis path is #5's **resident, torch-free `kokoro-onnx` worker** at
`$KOKORO_ROOT`, addressed through `$KOKORO_ROOT/venv/bin/python` — the same resolution `bench/bench:9-10`
already performs. The server branch is **declined on measured evidence** (#5), so there is no HTTP
transport and no port. Kokoro is driven as `kokoro.create(text, ...)` with **`is_phonemes=False`** —
never `True` — so `kokoro-onnx` phonemises through espeak and misaki/spaCy are not runtime
dependencies at all (#1).

**LOCKED, new: a lazy, self-electing, per-session resident worker, addressed by a file drop inside
`$BUF_ROOT/<session_id>/speak/`, started by whichever hook first finds it missing — and started from
*every* `MessageDisplay` invocation, not only from `Stop`.** Seven clauses:

**1. The address is a file, not a socket and not a port.** The hook writes the job to a temp name in the
speak dir and renames it onto `speak/job`; `rename(2)` within a directory is atomic and the directory is
already the depth-2 one §3.1 reclaims.

- **A Unix domain socket is rejected on MEASUREMENT, not on taste.** At the real path depth that
  address is **116 bytes** against Darwin's **104-byte `sun_path`**
  (`/…/MacOSX.sdk/usr/include/sys/un.h:79`), and `bind()` **fails**: `bind FAILED: OSError AF_UNIX path
  too long` **[obs]**. `TMPDIR` on macOS is a 49-byte per-user path, a session id is 36 bytes, and
  `/speak/sock` is 11 — **the sum is over the limit before anyone has done anything wrong.** The
  `chdir()`-and-bind-relative workaround does work (also observed) but it needs `nc -U` and a `cd` in
  the hook and buys nothing a file cannot do.
- **What the producer rename buys is COALESCING, and coalescing is not §10.6.** A rename onto
  `speak/job` replaces whatever is there, which settles exactly one of the three ways a newer job can
  arrive — the **unconsumed** one. It can neither un-claim a job inside a blocking `create()` nor stop a
  running player. Measured: eight simultaneous hooks against an empty speak dir produced **one**
  utterance, the newest job's — and the worker was cold, so all eight renames landed inside its startup
  and **nothing had been consumed while they raced** **[obs]**. That observation is silent about the
  other two rows, and §10.6 is where they are handled.
- **The consumer needs its own atomic step.** The worker claims by `rename(job, job.taken.<pid>)` and
  unlinks **only that private name**. A read-then-unlink of `job` loses a job renamed in between,
  irrecoverably.

**2. The election publishes a COMPLETE owner record atomically, it lives in the worker, and the hook's
pre-check is not the guarantee.** `symlink(str(os.getpid()), speak/worker.lock.<gen>)`.

- **Measured against the adversarial case, and unchanged by this replacement:** eight hook processes
  fired simultaneously → **8** decided to spawn, **8** workers launched, **1** election won, **7**
  exited immediately, **1** alive 12 s later **[obs]**. **The hook's own pre-check lost the race 8
  times out of 8.** Keep it — in the common case it saves a Python interpreter start on every turn —
  but **the exclusive-create inside the worker is the guarantee.** `symlink(2)` has the same
  exclusive-create property `mkdir` had: re-measured at N = 2, 4, 8 and 16 from an empty directory,
  **1 owner on 80 of 80** **[trials]**.
- **`symlink(2)` creates the object and its content in one step and fails `EEXIST` if the path
  exists.** There is no interval in which a lock exists without an owner, so the question the old
  clause (a) answered — *what does a pid-less lock mean* — cannot arise. `mkdir` followed by a pid
  write cannot have this property, because it is two steps.
- **Liveness is decided only by `kill(pid, 0)` on a complete record.** No backoff, no timeout. **This
  replaces clause (a), which is measured FALSE:** a bounded retry is a bet that a live process makes
  progress inside it, and an election must not make that bet. Clean to a 50 ms stall — **180/180**
  across N = 2, 4 and 8 at stalls of 0, 5 and 50 ms — and then **40/40 wrong at 200 ms and 1000 ms**,
  where a descheduled or `SIGSTOP`ped winner walks straight through it **[trials]**.
- **A dead owner is SUPERSEDED by creating generation `gen+1`, never by removing generation `gen`.**
  Nothing is unlinked from a contested path, so there is no path for an ABA to land on. **This
  replaces clause (b), which is also measured FALSE, 20/20:** `rename(2)` is atomic but it is
  *path*-addressed, so a reclaimer acting on a stale observation renames whatever is at the path now —
  including a fresh lock another process legitimately just created — and gets success rather than
  `ENOENT`. The committed trace shows a reclaimer logging `quarantined_pid=71461`, the other
  reclaimer's live lock (`lock-S3_aba-spec-r1.tsv:8`) **[trials]**. **This is the same third
  failure the old clause (b) claimed to fix**, arriving through `rename` instead of `rmdir`.
- **Ownership is "I created the highest generation record"**, read with one `readdir` for the highest
  `worker.lock.<gen>` and one `readlink`. **A `symlink` that loses with `EEXIST` restarts the read
  from the top** rather than concluding anything — that restart is what keeps two simultaneous
  reclaimers to one owner (S4, 20/20).
- **Generation records are NOT reclaimed by `rewrite.sh:117`.** That line is
  `find "$BUF_ROOT" -mindepth 2 -maxdepth 2 -type d -mmin +30 -exec rm -rf {} +` **[repo]**: a
  generation record is a symlink at depth 3, which neither `-maxdepth 2` nor `-type d` can select. The
  only thing `:117` removes is the whole `speak/` directory — which is clause 6's hazard, not a
  garbage collector. **A worker may unlink generation `g` only after it has completed BOTH halves of
  the election sweep against `g`'s owner (clause 7(iv) and 7(iv-a)), and only the worker that created
  `g+1` may do it.** The sweep reads *every* superseded generation's pid, so an unlink ordered before
  it destroys the target list and re-opens the orphan region. **This ordering is [inferred] and
  unrun** — `lockrace.py` never unlinks a generation, so all 400 trials ran with every generation
  present. §13 row 21's closing condition now includes it.
- **The worker makes itself a process-group leader at startup** — `os.setsid()` before it loads the
  model. This is a *clause 2* requirement, not only a clause 7 one: clause 7(iv)'s sweep addresses a
  superseded **owner's pid as a pgid**, which is only meaningful if the owner was a group leader.
  Without it the sweep is a silent no-op at best and signals the harness's own process group at
  worst. **Do it in-process rather than by shelling out** — macOS ships no `setsid(1)` in the base
  system (`/usr/bin/setsid` does not exist; the one on this machine's `PATH` is MacPorts', which a
  plugin must not assume) **[measured-here]**. **The player, by contrast, must never detach** —
  §10.5 clause 7(iv).

**Measured: exactly 1 owner on 400 of 400 trials** — against **121/400** wrong for the residency
probe's own protocol and **61/400** wrong for the two clauses this replaces, both with a worst case of
**3** owners, not 2. **[trials]**, [`preemption-and-lock-protocol.md`](preemption-and-lock-protocol.md),
[`lock-owners.tsv`](lock-owners.tsv).

**What is NOT changed:** the election stays inside the worker; the hook's pre-check stays a
best-effort optimisation; and the **8/8 `mkdir` result stands untouched**, because it is a result
about **who wins** a contended exclusive-create and this clause is about **misclassifying the
winner**. The two must not be conflated. **What IS changed and ships with it:** §10.2's file table,
§10.3 step 8c and step 9, §10.5 clause 4's cost note, §10.5 clause 6's mtime list and belt, §10.5
clause 7, §10.6's partition sentence, §13 rows 20 and 21, and §15's `[inferred]` enumeration, which
drops the two clauses this replaces — not because they were confirmed but because they were **measured
false** — and gains this clause's own generation-unlink residue. **Rows 20 and 21 can no longer be
signed off independently:** clause 7(iv) reads the superseded owner's pid, which only this clause
supplies.

**3. The wake is `kqueue`, and it costs nothing worth naming.** The worker blocks on
`kqueue(EVFILT_VNODE, NOTE_WRITE)` over the speak directory's fd, with a **1 s poll as a belt**. A
rename into the directory wakes it. **Measured hook-to-worker handoff, warm: median 0.079 s, range
0.059–0.198 s** **[hook]** — and that interval contains the *whole* hook plus the wake. Not the
bottleneck; no cleverness is owed here. **This is also the primitive §3.5.1's bounded wait runs on**,
which is why the wait needs no new machinery.

**4. The warm-up trigger is an ensure-worker step on EVERY `MessageDisplay` invocation, placed BEFORE
`rewrite.sh:127`'s early return — and NOT on §3.1's publish point.**

> **CORRECTED 2026-08-25, and the correction is three orders of magnitude wide.** An earlier residency
> draft named §3.1's publish point as the trigger and cited a **5.16–6.23 s** lead over `Stop` as its
> evidence. **Those are two different events.** The 5.16–6.23 s belongs to the **first**
> `MessageDisplay` invocation of a turn; the publish happens in the **final** one; and **the final
> invocation's lead over `Stop` is 0.006–0.012 s, median 0.008 s — and across all sixteen instrumented
> turns it runs −0.066 s to +0.086 s, median 0.0075 s, so it can go NEGATIVE** **[hook]**. The final
> `MessageDisplay` process and the `Stop` process are dispatched essentially simultaneously and which
> reads its clock first is a scheduling coin-flip — the same finding §3.5.1 measures from the other
> side. **A publish-point trigger would start the worker after `Stop` had already fired, which is
> strictly worse than triggering on `Stop`.**
>
> **And there was no publish point to attach a trigger to in the first place.** `grep -n 'speak'
> rewrite.sh` returns **zero matches across all 245 lines** **[repo]**. §3.1's publish is proposed
> spec, not shipped code.
>
> **Worse still, on short turns the publish never happens at all.** `rewrite.sh` gates on
> `prose_len < MIN_CHARS` (default **200**, `rewrite.sh:63`) and returns without producing a rewrite, so
> **a publish-point trigger gives exactly zero warm-up on precisely the turns that need it most**
> **[repo]**.
>
> **What the measurement actually measured is the trigger now specified.** The probe's
> `MessageDisplay` hook **parses no payload at all** — no `.final`, no `.delta`, no `jq` — and does one
> thing: ensure the worker exists, then append a trace line **[rig]**. So the 5.16–6.23 s lead belongs
> to a **payload-independent ensure-worker step running on every invocation**, which is real and
> implementable. **The error was invisible from inside the measurement**: every number was correct, the
> mechanism worked, and the sentence above the table described a different mechanism from the one that
> produced it.
>
> **And one thing the probe's shape does NOT transfer, found in review of this correction.** The probe
> parsed nothing because its `$SPEAK_DIR` was supplied by the harness that launched it **[rig]**.
> `rewrite.sh` has no such source and must read `session_id` out of the payload (`:108`) to know which
> session's worker to ensure **[repo]**. **The lead time measured is unaffected** — it is the lead of
> the *invocation*, and one `jq` field this hook already parses does not move a 5.16–6.23 s number —
> but "before any parsing" was a property of the probe's environment, not of the trigger. The clause
> below states the requirement as independence from the chunk role instead, which is what the
> measurement actually supports.

- **Placement is normative: after `rewrite.sh:108`, before `:127`'s non-final early return.** Non-final
  invocations `exit 0` at `:127-132`, so anything after that line runs only in the final invocation,
  which is the concurrent one — that is the constraint that fixes the lower bound. **The upper bound is
  `session_id`, and an earlier draft of this clause got it wrong.** It said the step must run "before
  any parsing", which **is not implementable**: the worker is per-session and its address is
  `$BUF_ROOT/<session_id>/speak/`, and `rewrite.sh` obtains `session_id` from **one place only — the
  payload, at `:108`** **[repo]**. There is no environment variable, no session file and no argument
  carrying it. **The probe never hit this because it was handed `$SPEAK_DIR` externally by the harness
  that launched it** **[rig]**; the specified implementation has no such source.
  - **What the clause actually requires, stated as the property rather than as a line number: the
    ensure decision must be independent of the payload's *chunk role*.** It must not read, branch on,
    or be reached only through `final` or `delta`, and it must not sit inside or after `:127`'s
    `if [ "$final" != "true" ]`. **Parsing `session_id` is not a violation of that; parsing `final`
    is.** The distinction is the whole point: "no parsing" was a proxy for "not gated on the chunk
    role", and the proxy is what failed, not the requirement.
  - **So: parse `session_id`, and nothing else, before the ensure.** In practice that costs **zero
    extra `jq` calls** — `:108` already parses it on every invocation, so the step reuses `$sid` and is
    strictly cheaper than the probe's shape, not more expensive. What remains is one `readdir`, one
    `readlink` and one `kill -0`, behind §11's `CLAUDISH_SPEAK` gate.
  - **The read got more expensive with §10.5 clause 2, and the cost is named here rather than left to
    be discovered.** This step used to be one `[[ -d ]]` and one `kill -0` — two syscalls at a fixed
    path. Under the generation protocol it is a `readdir` of `speak/`, and **§3.1 states normatively
    that the producer does NOT prune older `rw.*` generations**, so that directory grows for the whole
    session: one `rw.<hash>` per rewritten message, plus every `worker.lock.<gen>` no worker has
    unlinked, plus `playerdir/`. **This runs on every `MessageDisplay` invocation — five to seven per
    turn** — so the scan is paid five to seven times per turn against a directory whose size is
    monotone in the session's length. **Two things bound it and neither is a measurement.** The
    entries are names, not `stat`s, so the cost is a `getdirentries` over a few hundred short names in
    a `TMPDIR` filesystem; and `rewrite.sh:117` reclaims the whole directory after 30 minutes idle. It
    is **[inferred]** that this stays negligible: nothing has run a long session and timed the scan.
    **Clause 6 refused to put speech logic on the display hook's path, and this clause now puts a
    directory scan there** — the two are not in contradiction (clause 6's objection was to logic on
    the *disabled* user's path, and this sits behind `CLAUDISH_SPEAK`), but the asymmetry is worth
    seeing rather than being caught by.
  - **If `session_id` is absent, skip the ensure entirely.** `:108` defaults it to the literal
    `"nosession"` **[repo]**, and a worker elected under that key would be shared by every session
    that lacked one — which breaks the per-session scoping this clause exists to provide and makes
    §10.6's per-session `speak/playerdir/` meaningless. On all 94 observed payloads `session_id` was present
    **[obs]**, so this is a guard against a shape nobody has seen, not a live case.
  - **One consequence of the placement, on the record.** `:100`'s `[ "$ENABLED" = "1" ] || pass_through`
    sits above `:108`, so when the *rewriter* is disabled the hook leaves before the ensure and no
    worker is started. That is correct rather than a gap: with no rewrite there is nothing for §3.1 to
    publish and nothing for the worker to speak.
- **Measured, on a fresh session with no worker running, driving a 400-word streaming reply**
  **[hook]**: the first invocation fires **5.16–6.23 s** before `Stop`; the worker becomes ready
  **3.05–4.62 s** before `Stop`; `Stop` finds a resident worker (`started=no`) every time; and TTFA on
  that **first** turn is **1.37 / 1.66 / 1.71 / 2.23 / 3.83 s — median 1.71 s, 4 of 5 under the line.**
  In the trace the first of five to seven invocations logs `started=yes` and every later one
  `started=no`.
- **So the mechanism moves the cold start off the user-visible path on the FIRST turn of a session**,
  not merely on the second. That is the claim the blocker asked for.
- **STATED LIMIT, measured rather than hypothesised.** It covers the cold start **if and only if the
  turn's message streams in more than one chunk AND the first chunk arrives more than the worker's
  startup time (1.33–2.02 s, n = 8) before the turn ends.** Drive the same fresh session with a
  fifty-character reply and the lead disappears — the `Stop` hook started **64 ms first** **[hook]**,
  TTFA that turn **4.489 s, cold**. A very short, very fast first turn streams in one chunk, that chunk
  *is* the final one, it is concurrent with `Stop`, and **the first utterance is cold.** Tolerable
  **[inferred]**: a fifty-character first message is exactly the band §3.3 and §9 are about, and one
  late first utterance per session is the worst case. **Not tolerable to leave unstated**, which is
  what this section used to do.

**5. A warm-up synthesis at worker startup — REQUIRED, not recommended.** `kok.create("Warming up.")`
before announcing readiness; `bench/bench.py:471-475` already does this and says why **[repo]**.

> **STRENGTHENED in review, from "recommended" to required.** §10.5 is marked LOCKED and §13 row 2
> lists the startup warm-up as part of the **selected** mechanism, so leaving the clause advisory handed
> #23 a decision the lock claims is already made — over a choice worth 0.78–1.12 s of startup. Both
> statements cannot stand, and **the data says required.**

**It is not free** **[hook]**: the first `create()` on a freshly loaded model is markedly slower than
steady state — the same item took **2.13 s** as a worker's first synthesis against **1.41 s** on a
worker that had already spoken — so the warm-up **costs 0.78–1.12 s of startup**, pushing exec→ready
from 0.80–1.30 s to **1.33–2.02 s**, and therefore **lengthens the streaming lead clause 4 needs**.

- **The sentence that used to close this clause — *"a win when there is lead time, a wash when there is
  not"* — is CONTRADICTED by the only rows that test it, and is withdrawn.** The `cold7` set contains a
  near-controlled pair: `E-md-warmup` and `G-short-cold` both have the clause-4 ensure hook live, both
  get **no lead** (a fifty-character reply), and both synthesise the **same item** `r01` — 268 chars in,
  88 spoken, 5.06 s of audio — so their RTFs are directly comparable. The only difference in the run
  notes is the startup warm-up **[hook]**:

  | run | startup warm-up | TTFA | synthesis | RTF |
  | --- | --- | --- | --- | --- |
  | `A-stop-only` (no ensure hook either) | no | 5.441, 5.496 s | 4232, 3762 ms | 0.837, 0.744 |
  | `E-md-warmup` | **no** | 4.489 s | 3007 ms | 0.595 |
  | `G-short-cold` | **yes** | 2.657–3.161 s | 1218–1414 ms | **0.241–0.280** |

- **So the warm-up is a win even with no lead at all**, because the hook-to-worker interval on a cold
  start is itself **1.38–1.73 s** — enough to absorb the warm-up — which converts the *user-visible*
  synthesis from a cold first `create()` into a warm one and roughly halves it. **It is not a wash; it
  is the difference between failing the 3 s line and sitting just under it.**
- **The honest limit of that comparison: n = 1 on the `E` side**, and the two runs differ in their run
  label as well as in the warm-up, so this is **suggestive rather than controlled**. It is enough to
  settle *required versus recommended* — the direction is unambiguous and large — and not enough to
  quote as an effect size. Marked **[hook]**; the paired A/B that would make it controlled is the same
  shape as §13 row 22 and is not owed for this decision.

**6. Idle exit at 20 minutes — deliberately SHORTER than `rewrite.sh:117`'s 30-minute sweep, not equal
to it.** **Not measured** — the runs were minutes long. It re-introduces a cold start after twenty
minutes of silence, which is the honest cost.

> **CORRECTED in review. Matching the two windows at 30 minutes does not achieve what this clause
> claimed.** The earlier text set the idle exit to 30 minutes "matching `rewrite.sh:117`'s existing
> sweep window, so a worker never outlives the directory it depends on". **Equal timeouts do not order
> two events.** `:117` is opportunistic — it fires on whichever `MessageDisplay` invocation happens to
> arrive after the threshold — so on the first invocation past the 30-minute mark it can `rm -rf` the
> speak directory of a worker that is still live and has not yet reached its own exit. That loses the
> warm-up at best, and at worst destroys `speak/worker.lock.<gen>` **underneath a running worker**, so
> the next hook's `readdir` finds no generation at all, publishes generation 0 and elects a **second**
> worker — two processes, each holding a ~340 MB model, racing the claim-rename. **The generation
> protocol does not help here and it is worth being clear about why**: it makes a *superseded* owner
> unambiguous, and a swept directory has no owner to supersede. That is the same failure mode §10.5
> clause 2 exists to prevent, arriving by a different door.

- **The separation is what makes it safe, and the argument is arithmetic rather than a new mechanism.**
  A live worker's last job arrived within its idle window, and **a job arriving is a `rename` into the
  speak directory**, which updates that directory's mtime; so is the claim-rename, the `job.taken`
  unlink, and the `symlink` of `worker.lock.<gen>` at startup — a symlink created *in* the directory
  mutates the directory, exactly as the old `mkdir` did, so the inequality survives the change of
  primitive unaltered. **Therefore a live worker's speak directory has
  an mtime no older than its idle window**, and `find -mmin +30` cannot select it while the window is
  20 minutes. **No live worker is ever swept**, with no change to `rewrite.sh:117` at all.
- **The 10-minute margin is not decoration.** It absorbs `-mmin`'s minute granularity, the fact that
  the sweep fires at an arbitrary moment after the threshold rather than on a schedule, and any
  divergence between the worker's idle clock and the filesystem's mtime — **the worker's idle timer
  must therefore be monotonic**, so that a backward wall-clock step cannot age the directory past 30
  minutes while the worker still believes it is inside its window.
- **Why the sweep was NOT made worker-aware, which was the other available repair.** `:117` is a
  `find … -exec rm -rf` one-liner sitting above §11's speech gate: it serves the *rewriter's* own
  buffers and runs for every user with `CLAUDISH_ENABLED=1`, speech on or off. Teaching it to read
  `speak/worker.lock.<gen>` and `kill -0` would put **speech-specific logic on the disabled user's path**,
  on a hook that runs five to seven times per turn, to protect a case the inequality already excludes
  for free — and it would do that inside the fail-open display hook, which §5 makes inviolable. **The
  cheaper repair is also the one that keeps §11 true.**
- **A belt, because the inequality only covers the sweep.** A speak directory can also vanish for
  reasons this clause does not model — a manual `rm -rf`, an OS `TMPDIR` cleaner, a clock jump larger
  than the margin. **The worker treats the disappearance of its own `speak/worker.lock.<gen>` — or of
  the speak directory itself — as a terminal condition and exits**, rather than blocking forever on a
  `kqueue` over a deleted directory. **"Its own" is exact**: under clause 2 a worker owns one named
  generation, and a *higher* generation appearing means it has been superseded rather than swept,
  which is the same terminal condition by a different route. It re-checks on each wake, which
  clause 3's 1 s poll already provides.
- **All of this is [inferred]** — the mtime reasoning is read off `find`'s semantics and `rewrite.sh:117`
  **[repo]**, and nothing has been left idle for twenty minutes to watch it happen. **§13 row 24.**

**7. §10.5 owes §10.6 FIVE hooks, and two of the first revision's three were wrong.** They are
specified here because they live in the worker, and §10.6 is where the rule they serve is stated.
**Every clause below names the arm that measured it** — 312 trials over 26 switchable configurations,
[`preemption-and-lock-protocol.md`](preemption-and-lock-protocol.md),
[`preemption-trials.tsv`](preemption-trials.tsv), re-derivable with `preemption-lock-probe/summarise.sh`
**[trials]**:

- **(i) The pid record is per-PLAYER, at a unique path, published by the player before it can make a
  sound. REQUIRED.** `speak/playerdir/<pid>.<nonce>`, written by a wrapper that then `exec`s, and
  unlinked **only by exact name**. **One shared `speak/pid` must not be used** — an older player's
  reap otherwise erases a newer player's registration (`C14a` against `C14b`). **An append-only ledger
  must not be used either**: its truncate erases registrations it never signalled (`C13a`, which the
  attribution rule scores `NOTHING-ran-to-end` 12/12 at a full **2.50 s** of audible stale speech).
  **This replaces the first revision's *"the worker writes the player's pid to `speak/pid`"*,** which
  named the wrong writer and the wrong cardinality.
- **(ii) The pre-spawn re-`stat` of `speak/job` is an OPTIMISATION given (iv), and a correctness clause
  without it.** With the worker surviving, removing it changes nothing — `C5_norecheck` still kills
  before the player can `exec`, 12/12. With the worker dying after the spawn and no sweep, removing it
  **creates an orphan nothing kills**: `C15b` runs to completion 12/12 at 2.50 s, where `C15a` (the
  re-check present) spawns no player at all. With (iv) present the orphan is caught anyway — `C15c`,
  killed by the election sweep 12/12, audible **0.386–0.471 s**. **Keep it, and state the condition.**
- **(iii) The worker kills the current player the moment it claims a newer job. REQUIRED, and it must
  kill BOTH targets** — its own child handle *and* every published record. Load-bearing: `C4_noclaimkill`
  runs to completion 12/12 at 2.50 s. The two targets are indistinguishable while a record exists and
  opposite when none does — `C10a` (record only, no handle) kills **nothing**, 12/12 at 2.50 s;
  `C10b` (handle only, no record) kills 12/12 at 0.56–0.71 s.
- **(iv) A newly elected worker kills the PROCESS GROUP of each superseded owner, BEFORE it loads the
  model. REQUIRED, and it is the only thing that closes the spawn-to-record region.** Membership is
  established by `fork(2)` before the child executes an instruction, so it reaches a player that has
  published nothing and has never been scheduled. Measured on both sides of publication: `C12a` kills
  12/12 (audible 0.738–0.841 s) and `C12b` kills **before `exec`**, 12/12, **never started** — where
  the single-record and record-only repairs both fail 12/12 at full length (`C11b`, `C12c`). **The
  placement before the model load is normative**: exec-to-ready is **1.33–2.02 s** with clause 5's
  required warm-up **[hook]**, and a sweep after it would let the orphan talk through all of it. It
  requires clause 2's generation protocol, which is what supplies the superseded owner's pid, and
  clause 2's `os.setsid()`, which is what makes that pid a pgid.
  - **Bound `killpg` with a `.pending` marker.** The worker creates `playerdir/<nonce>.pending` before
    the fork; the wrapper renames it away as its first act; `killpg` is used only while such a marker
    exists. That confines the blast radius to the window in which an unnamed player can exist —
    `C16a` (sweep before publication) kills before `exec` 12/12, `C16b` (sweep after) never needs it
    and the record sweep does the work 12/12.
  - **Never detach the player.** `start_new_session=True`, or any `setsid()`, removes it from the
    group and defeats this clause completely: `C17_setsid_player` runs to completion 12/12 at 2.50 s.
    **Normative, not stylistic** — it is exactly the line an implementer adds for unrelated reasons.
- **(iv-a) The same election also sweeps the superseded owner's published player RECORDS**, by exact
  name, and that half is what covers a player which published before the sweep arrived — `C11a`,
  `C15c` and `C16b`, all 12/12, the arms the attribution rule scores `election-sweep-record`.
  **Both halves must complete before clause 2 permits generation `g` to be unlinked** — the record
  sweep reads the records, the pgid sweep reads the pid, and the generation record is what names the
  owner both of them address.
- **(v) The worker must `wait()` its player, and unlink that player's own record when it does.**
  `kill(2)` on an unreaped **zombie succeeds**, so an unreaping worker makes every kill site report
  success while killing nothing. In `C7_noreap` the hook's kill lands at 0.549–0.577 s and every later
  kill site then reports success too, on all 12 trials, against a process that is already dead — `C2`
  is the same arm with the worker reaping, and there the later sites report `ESRCH` instead. **A kill
  site that cannot fail is a kill site that proves nothing**, which is why this clause is here and not
  only in an implementation note. Unlink by exact name only; see (i).

**The first revision's *"Both are required"* about (i) and (iii) does not survive.** (iii) with both
targets covers every case in which the worker survives the spawn. (i) exists so that a *different*
process can do the killing, and its measured independent value is narrower and quantified: the hook
reaches the player a median **134 ms** sooner than the worker's next claim would (range 123–143 ms,
n = 12, `C2_hookside`) **[trials]**.

**What is still [inferred] in this clause**: the ordering between the two sweep halves and clause 2's
generation unlink (nothing has run an unlink), and pid reuse under `killpg` — the sweep addresses a
recorded pid as a pgid, and if that pid has been recycled as a group leader it signals strangers. The
`.pending` bound confines *when* `killpg` runs; it does not make the pid unambiguous. §13 row 20.

**The alternatives, and why each loses:**

| alternative | verdict | on what basis |
| --- | --- | --- |
| **fresh interpreter per turn** | rejected | #6's 3.93 s cold, and this run's cold rows from a hook (2.66–5.50 s) agree and are worse. "Spawn python, synthesise, exit" is **insufficient**, not merely slower |
| **worker started by `Stop` only** | rejected | **measured**: median cold **3.16 s**, 3 of 7 under the line. This is the mechanism the spec's shape implied before clause 4, and it is the one that fails |
| **HTTP server on a port** | rejected | #5 declined it on measured evidence; independently, a file drop answers every question a port raises without opening one |
| **Unix domain socket** | rejected, **on measurement** | `bind()` fails at the real path depth — 116 bytes against a 104-byte `sun_path` **[obs]**. The relative-path workaround works and buys nothing |
| **`launchd` user agent** | rejected, **not measured — this one is a JUDGEMENT** | it would be permanently resident and would survive machine sleep, which is genuinely better on latency. It loses on three other counts: it installs a background daemon for a feature that is **off by default** (§11); it sits outside `rewrite.sh:117`'s sweep so nothing reclaims it; and it has no per-session scoping, which makes §10.6's per-session player records meaningless. **This is the alternative a reviewer should push back on if they think the latency is worth the footprint** |

**What remains unmeasured about this mechanism, named here rather than only in §13 — and it is a much
shorter list than it was.** The two runs this paragraph used to owe **have been run**: 1200 lock trials
over three protocols and six scenarios, and 312 preemption trials over 26 configurations
([`lock-owners.tsv`](lock-owners.tsv), [`preemption-trials.tsv`](preemption-trials.tsv),
[`preemption-and-lock-protocol.md`](preemption-and-lock-protocol.md)). **They did not confirm the
clauses; they falsified four of them** — clause 2's initializing-lock retry (61/400 wrong, worst case
3 owners) and its quarantine rename (20/20 wrong on the ABA), and clause 7's single `speak/pid` and
its two-kill partition. The replacements are what §10.5 now specifies. **What is left [inferred] is
narrower and is enumerated where it lives:** clause 2's generation-unlink ordering, clause 7's pid
reuse under `killpg`, clause 6's mtime inequality, and §3.1's content-addressed publish. §13 rows 20,
21 and 24, and §15's enumeration.

### 10.6 LOCKED — preemption and barge-in

- **A newer message kills stale playback.** The owner record and the player records live in the same
  per-session scratch: `$BUF_ROOT/<session_id>/speak/worker.lock.<gen>` and
  `$BUF_ROOT/<session_id>/speak/playerdir/<pid>.<nonce>`, the latter read and `kill`ed by the next
  invocation before it starts. Same directory, same sweep, no new lifecycle.

  > **Two qualifiers, both added 2026-08-25 because this rule was written for a design that no longer
  > exists, and both since MEASURED.** §10.6 assumed the hook spawned the speech child and could
  > therefore kill the previous one itself. Under §10.5 there is **no per-turn speech child**. Neither
  > qualifier reopens a decision here; without them an implementer reads this bullet and finds nothing
  > left in the design that writes the file. **They were [inferred] when written; 312 trials over 26
  > configurations have since confirmed one of them, falsified the other's central claim, and replaced
  > the writer named in the first** **[trials]** —
  > [`preemption-and-lock-protocol.md`](preemption-and-lock-protocol.md),
  > [`preemption-trials.tsv`](preemption-trials.tsv),
  > [`worker-residency.md`](worker-residency.md).
  >
  > **(1) The mechanism is still right; the WRITER changed — twice.** *"Written by the speech child"*
  > became *"written by the resident worker, after it spawns the player"*, and **that is superseded too**:
  > the record is **per-player, at a unique path, published by the player's own wrapper before it can
  > make a sound** (§10.5 clause 7(i)). The next hook invocation then kills it exactly as this bullet
  > already says, and playback in progress dies within the hook's own wall cost — median **0.086 s**
  > **[hook]**. The measured value of the hook doing the killing at all is now quantified: it reaches
  > the player a median **134 ms** sooner than the worker's next claim would (123–143 ms, n = 12,
  > `C2_hookside`) **[trials]**.
  >
  > **(2) "A newer message kills stale playback" needs TWO more clauses to be true, not one.** A message
  > newer than a synthesis *in progress* is not covered by the pid kill at all: no player exists yet to
  > kill.
  >
  > - **The worker re-checks `speak/job` after `create()` and before `Popen`**, discarding the finished
  >   audio if a newer job is waiting. Residual: a job landing inside the **6–38 ms** between that check
  >   and the spawn still starts playing.
  > - **The worker also kills the current player the moment it claims a newer job**, and it must kill
  >   **both** targets — its own child handle and every published record. Without it the rule is **still
  >   false**, measured: `C4_noclaimkill` lets the stale player run to completion 12/12, a full 2.50 s
  >   of audio **[trials]**.
  >
  > **The two kills do NOT partition the timeline, and no record-based repair makes them.** This
  > qualifier used to close by saying they *"partition the timeline at the `speak/pid` write"*. **That
  > is false and it was measured false.** There are **three** regions, not two: a hook reading before
  > the record is published kills nothing (the worker's claim-time kill covers it); a hook reading
  > after it kills the player (covered); and **a worker that dies between spawning the player and the
  > record being published leaves the player unreferenced** — `C8_orphan`, plays to completion 12/12,
  > window median **1.41 ms**, range **0.43–5.61 ms**, n = 72 **[trials]** — the
  > **worker-published** trials only. The pooled n = 96 figure (median 1.27 ms, from 0.36 ms) is
  > **not quotable**: harness defect 4 stamps `W` in the parent right after `Popen` for the 24
  > player-published trials, so those measure two log writes rather than a publication. See
  > [`preemption-and-lock-protocol.md`](preemption-and-lock-protocol.md) §2.4. Publishing the
  > record from the *player* rather than the worker does not close that third region either: the
  > wrapper can stay descheduled between `Popen` and its own first instruction, and a sweep in that gap
  > sees nothing (`C11b`, `C12c`, both 12/12 at full length). **The third region closes on process-group
  > membership** — §10.5 clause 7(iv) — which `fork(2)` establishes before the child executes an
  > instruction: `C12b` kills the player **before it can `exec`**, 12/12, never started.
  >
  > **What this means for the atomic rename, stated flatly because it was claimed the other way.** An
  > earlier reading said latest-wins *"falls out for free from the producer rename, and it is exactly
  > §10.6"*. **That is wrong on both halves.** The producer rename settles the **unconsumed** case only
  > — it cannot un-claim a job inside a blocking `create()` and it cannot stop a running process
  > (§10.5 clause 1). **§10.6's preemption is not free; it is clause 7's five hooks, of which the two
  > above are the ones this bullet used to name.**
- **Cutting playback on a new prompt** requires a hook event that fires on prompt submission.
  `UserPromptSubmit` is the candidate (harness default timeout 30 s, **[bin]**), and this spec does
  **not** add it — a third hook entry is a scope increase, and `Stop`-driven preemption already
  covers the common case (the next turn's `Stop` kills the previous playback). **OPEN**, deliberately
  deferred, with the cost stated: until it exists, a long utterance keeps talking after you start
  typing.
- **Cancelling an in-flight `create()` stays OPEN, and its condition is now DISCHARGED rather than
  pending.** *"Cancellation is latency only, not correctness"* is true **only if** the worker's
  claim-time kill is in — and it is true only with clause 7(iii) killing **both** targets, clause 7(i)
  as per-player records, clause 7(iv) with its `.pending` bound, and clause 7(v)'s reaping. **All four
  are measured** **[trials]**. With them, the cost of not cancelling reduces to the newer
  utterance waiting out the older synthesis — latency, on the newer utterance, not a wrong utterance.
  **Do not quote the reassuring half of that sentence without naming the four clauses it rests on**,
  because with any one of them removed an arm of the run produces a stale utterance that plays to
  completion.
- **Escape / interrupt barge-in stays out of scope**, as #1 already records, because which events
  Claude Code fires on interrupt is unknown. Related and also unknown: **whether `Stop` fires on user
  interrupt at all**, and what the separate **`StopFailure`** event (carrying `error`,
  `error_details` and its own `last_assistant_message`, **[bin]**) does. Neither has been looked at.
  **OPEN.**

### 10.7 LOCKED — failure paths, all silent and harmless by construction

Every row exits 0 and speaks nothing. None writes to the screen.

**Read the column with one distinction in mind, added 2026-08-25.** Rows above the job drop are the
**hook's** and `exit 0` is literal. Rows at or below it are the **worker's**: by then the hook has
already exited 0 and the prompt is long released, so "silent" there means *the worker discards the job
and keeps waiting for the next one* — it can no longer affect the turn at all. **Nothing on either side
of that line reaches the screen, and nothing on either side writes to stderr** (§5: on `Stop`, stderr is
prompt input to the model).

| failure | behaviour |
| --- | --- |
| speech disabled, or off-file present | `exit 0` before reading stdin |
| `jq` missing, payload unparseable, `last_assistant_message` absent | `exit 0` |
| no rewrite buffered and the message is above the threshold | the hook drops a **`buffered` job and exits 0**; the worker waits, and stays silent if the deadline passes (§3.5.1) |
| the bounded wait reaches its deadline — `CLAUDISH_TIMEOUT + 5` s — with no matching publish | worker discards the job, **silent**. This is the fail-open ban's own path: a rewrite was due and did not arrive (§3.5, §3.5.1 clause 4) |
| buffered rewrite does not match this turn | never spoken. On the raw rows, `exit 0`; on the buffered row the worker keeps waiting until the deadline. **Silence beats a confident wrong utterance** |
| the worker is **not ready** when the job lands, or is slow to become ready | the job file **outlives the hook**, so the utterance is **late, not lost** — measured at 23.3 s late against a 10 s declared hook timeout, turn ended normally, nothing on screen **[hook]** |
| the worker **cannot start at all** — no venv, a Python that will not exec, an unwritable speak dir | **the job is LOST, silently, and "late, not lost" does not cover this row.** Nothing ever claims `speak/job`; it is overwritten by the next turn's rename (§10.5 clause 1) or removed with the directory by `rewrite.sh:117`. The 23.3 s observation is a *delayed startup that eventually succeeded* and says nothing about a startup that never does. Nothing on screen either way (§1), so the user-visible behaviour is silence — which is the fail-open posture, arrived at by accident rather than by design. **[inferred]**, and the reason the two rows are now separate: an earlier version of this table had one row and read the measured case as covering both |
| two hooks race to start a worker | the exclusive-create elects one; the losers exit immediately, one interpreter start each (§10.5 clause 2). Observed 8 → 1 with `mkdir` **[obs]**, and 1 owner on 80 of 80 with the `symlink` that replaced it, at N = 2, 4, 8 and 16 **[trials]** |
| a newer job arrives while an older one is unconsumed | the producer rename replaces it. *n* drops, one utterance (§10.5 clause 1) **[obs]** |
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
  `claudish-off` stops both. **This promise is now SPECIFIED, and specified is not implemented** —
  `speak.sh` checks `CLAUDISH_ENABLED` and the global off-file as steps 0a–0b (§10.3), which the spec
  did not say until review found the gap. **`speak.sh` does not exist**: `ls` finds no such file and
  `grep -n 'speak' rewrite.sh` returns zero matches across all 245 lines **[repo]**. The README bullet
  therefore ships **with** step 0a–0b, never before it. A README claim that no code honours is worse
  than no claim, and this document must not be the place the confusion starts.
- the residual cost of §11, in the user's own terms: one extra process per turn when speech is off.
- **that speech arrives AFTER the rewrite, not when the turn ends** — §3.5.1. This is the one piece of
  user-visible behaviour a reader would otherwise file as a bug: the answer appears on screen, then a few
  seconds later it is spoken. Say why (the spoken text *is* the rewrite, and the rewrite takes an LLM
  call), and say that after `CLAUDISH_TIMEOUT + 5` seconds it gives up silently.
- **that a background Python worker stays resident per session and exits after 20 minutes idle**
  (§10.5). A user who sees a `python` process holding a few hundred MB should find out here that it is
  expected, that it is per session, and that it goes away on its own.
- **no promise of Linux or Windows playback.** The player stays configurable with documented
  alternatives; only macOS is verified.

---

## 11. LOCKED — "off by default" is now enforced inside the hook

Before the two-hook split, speech was code *inside* `rewrite.sh`, so off-by-default cost nothing: the
branch was not taken. **After the split the plugin ships a second hook entry, and
`hooks/hooks.json` is not conditional** — a `Stop` block fires **on every turn, for every user of the
plugin, whether or not they ever enable speech.**

Therefore:

- the guarantee is enforced **inside** `speak.sh`: the plugin's **global** switches
  (`CLAUDISH_ENABLED`, `~/.claude/claudish-off`) and then `CLAUDISH_SPEAK` and its own runtime off-file
  are checked and `exit 0` taken **as the very first thing**, before `jq`, before reading stdin —
  §10.3 steps 0a–2. **The two global checks were missing until review**; §10.3 carries what that cost;
- **the same gate applies to `rewrite.sh`'s two new additions, and this is normative rather than
  advisory.** §10.5 clause 4's ensure-worker step runs on **every** `MessageDisplay` invocation — five
  to seven times per turn on a long reply — so it must sit behind `CLAUDISH_SPEAK` too, checked
  **before** the `[[ -d ]]` and the `kill -0`, exactly as the probe that measured it did **[rig]**.
  **Without that gate, "off by default" would cost a user who never enables speech two extra `stat`s
  per streamed chunk instead of nothing.**
- **The publish (§3.1) sits behind the same gate, and this too is normative.** An earlier draft of this
  section said the publish "may run either way — it is a small write a disabled user pays nothing else
  for — but gating it as well is cheaper and is preferred". **That was a contradiction of the sentence
  immediately above it and of this section's title**, and it is withdrawn rather than softened. A
  permission to run is not a preference: with it, a user who has never enabled speech pays a `sha256`
  over the whole assistant message, a `mkdir -p`, and **two temp-file-plus-rename installs** (§3.1),
  on every rewritten turn, for a directory nothing will ever read. **"Off by default" cannot mean
  "does the speech-specific work but makes no sound."** Both of `rewrite.sh`'s additions — the
  ensure-worker step and the publish — are inside `CLAUDISH_SPEAK`, and neither is optional; and
- **the residual cost is stated, not hidden: one bash process spawned per turn for users who never turn
  speech on.** It is small. It is new. It is not zero. **It has not grown with this revision** —
  the `MessageDisplay` additions are inside a hook that already runs, behind a gate that is one
  variable test, and no resident worker is ever started for a user who has not enabled speech.

---

## 12. LOCKED — the standing constraints #10 and #13 do not disturb

| constraint | status |
| --- | --- |
| **macOS only** | unaffected, and now **more deeply macOS than it was**. Nothing about `Stop` is platform-specific and `afplay`, `espeak-ng` and `sox`/`ffmpeg` are all unchanged — but §10.5's mechanism is built on **`kqueue(EVFILT_VNODE, NOTE_WRITE)`** for the wake and an in-process **`os.setsid()`** for detachment (macOS ships no `setsid(1)` in the base install), and the socket alternative was rejected because of **Darwin's 104-byte `sun_path`**. A Linux port would replace the wake primitive, not merely the player. **Every measurement in this document is from one Apple M3 with 16 GB; none of it is portable evidence.** |
| **`kokoro-onnx` `IndexError` at 510 phonemes** | unaffected, and now **checked against the composition rather than against single axes**: the worst batch under `settled` across all 54 corpus items is **509** phonemes (`r13`) and nothing exceeds 510 **[measured-here]** (§4.2). The sanitizer must **never** strip terminal punctuation, and `\n` must be **converted into** terminal punctuation rather than preserved — a requirement rule B was **latently violating** until the blank-line fix in §4.2. B′ cannot disturb this: both boundary characters are members of the splitter's own `BOUNDARY_CHARS`. |
| **espeak G2P, `is_phonemes=False`** | unaffected. misaki, spaCy and `en_core_web_sm` are not runtime dependencies. **Never install `misaki[en]`.** |
| **No pronunciation-override mechanism exists on the espeak path** | unaffected. `[text](/phonemes/)`, `[[...]]` and SSML are each read aloud as literal words; the `[...](...)` form is the worst-sounding input measured. **Never emit it** (rule M, a prohibition). |
| **Fail-open is inviolable** | in force, strengthened in reason, wording generalised — §5. |
| **This fork is not upstreamed** | unaffected. |

---

## 13. The full OPEN list, with closing conditions

Nothing below is papered over to make the spec look finished.

**Row numbers are stable across revisions and are cited by number elsewhere in this document, so a
closed row keeps its number rather than being deleted and the numbering never shifts.**

| # | open question | what closes it | blocks shipping? |
| --- | --- | --- | --- |
| 1 | ~~The settled sanitizer combination has never been synthesized, and now contains a rule that does not exist~~ (§4.2) | **CLOSED 2026-08-25.** B′ implemented as `lb-auto`; the combination registered as `settled`; 24 wavs; the confirmation listen happened blind on `bf_emma` and **`settled` won 9–0**, five of the nine real — [`settled-set-audition.md`](settled-set-audition.md), [`audition-verdicts-11.tsv`](audition-verdicts-11.tsv) **[heard]**. It closes on the **composition**; rows 5, 19 and 23 are what it did not close | **closed** |
| 2 | ~~The worker residency mechanism~~ (§10.5) | **CLOSED 2026-08-25.** Mechanism picked (lazy, self-electing, per-session, file-drop address, exclusive-create election — `mkdir` when this row closed, `symlink`ed generations since row 21 measured it, kqueue wake, every-invocation warm-up, startup warm-up synthesis, 20-minute idle exit — corrected from 30 in review, §10.5 clause 6) and TTFA measured **from a hook**: cold median **3.16 s** (fails, 4 of 7 over), warm median **1.22 s** (28/30), warmed-during-turn **1.71 s** (4/5) — [`worker-residency.md`](worker-residency.md), [`residency-timings.tsv`](residency-timings.tsv) **[hook]**. Rows 20, 21 and 22 are what it did not close | **closed** |
| 3 | ~~The §3.2 handoff match rate~~ | **CLOSED 2026-08-25. The rate is 35/35, byte-identical** — and re-derived at **15/15** by the committed kit, which is the reproducible half — [`handoff-match-rate.md`](handoff-match-rate.md) **[obs]** + **[obs2]**. **Closing it surfaced row 17, which is worse than the question this row asked** | **closed** |
| 4 | ~~Whether `MessageDisplay` carries `prompt_id`~~ (§3.2) | **CLOSED 2026-08-25: yes**, on all 94 payloads, the same value `Stop` carries, 35/35, ten fields catalogued in §2 **[obs]**. It did **not** become the key — §3.2 says why, and that reverses this spec's stated preference | **closed** |
| 5 | **Axis 2's cutoff position — STRENGTHENED 2026-08-25 from *unaudited* to CONTRADICTED at 4** (§4.1 qualification 1). One wav now exists at the seam and it went against the file: `s04`, 4 boundaries, `,` beat the shipped `.` blind **[heard]**. `COND_CUTOFF` stays at 4 deliberately — one wav cannot separate "the cutoff wants to be 5" from "the count should exclude a closing line", both predict `,` there. **The count that used to close this cell — *"would change `settled` on 17 of 54 items and invalidate the 9–0 sweep"* — was borrowed from a different measurement and is withdrawn.** 17 of 54 is `lb-comma`'s reach against `base`; the move from 4 to 5 changes `settled` on **2 of 54** (`s04`, `s05`) and on **none of the nine swept items** **[measured-here]**. The sweep is not at risk; the decision rests on the first reason alone | wavs at **5, 6 and 7** boundaries, **and** an `s04` variant with its closing line removed — that last pair is the only one that can separate the two repairs. Then one listen | no — the rule ships and the constant stays at 4 |
| 6 | `flag-pause` has no real carrier (§4.3) | a capture with a bare flag or `_`-joined identifier **outside** backticks in a real message | no — its **value** is unproven, not its safety; see row 19 for the safety half |
| 7 | ~~Whether `Stop` fires again after a background task wakes the session~~ (§8) | **CLOSED 2026-08-25: yes**, as an ordinary new turn with a new `prompt_id`, empty `background_tasks` and `stop_hook_active: false`, matching §3.2's key with no special case. Two samples **[obs]**. Observed consequence: a delegated turn is announced **once, late** | **closed** |
| 8 | The three `async: true` unknowns (§6) | one probe; **neither the `Stop` payload probe nor the block-loop probe covered them** | no — nothing is built on `async` |
| 9 | Whether the harness kills a hook's process group (§6) | one detached-sleep-and-check probe on a **non-detached** child. A `setsid()`-detached worker was observed surviving `/exit` **[obs]**, which is a different question | no, but it would explain truncated audio |
| 10 | Whether `Stop` fires on user interrupt; what `StopFailure` does (§10.6) | inspection plus one probe | no |
| 11 | Barge-in on a new prompt (§10.6) | decide whether a `UserPromptSubmit` entry is in scope | no |
| 12 | Warm-up-on-wake vs a late first utterance (§10.5) | a listening call. **The decision is now cheap** — §10.5 clause 4 already has a warm-up trigger and a wake handler would reuse it. Nothing here has slept a machine; #5's ~4.9 s post-wake figure stands unchallenged | no |
| 13 | Deeper leading-dot paths (`.github/workflows/ci.yml`) unauditioned | a corpus item | no |
| 14 | `session_crons` has not been looked at (§8) | one look | no |
| 15 | Whether any absolute hook-timeout ceiling exists (§6) | a wider read than the two call sites checked — **not** an argument from `hooks.json:21`, since config acceptance is not runtime enforcement | no |
| 16 | ~~The exit-2 block mechanics have never been observed~~ (§5) | **CLOSED 2026-08-25 — observed.** Four driven runs, 28 captured fires; the cap, the `blockingError` routing and the post-cap override all have a wire observation, and the schema reading was **off by one** (nine invocations, §5). **Still unobserved and named there rather than here:** `async: true`, `SubagentStop`, a raised or disabled cap, and two blocking hooks at once — [`stop-hook-block-mechanics.md`](stop-hook-block-mechanics.md) | **closed** — the invariant was specified to hold regardless, and does |
| **17** | **§3.5.1's bounded wait is specified and has never been implemented, run, or watched.** The race it repairs is confirmed and reproducible (`Stop` dispatched a median 6.7 ms after the final `MessageDisplay` chunk, positive 32/32, gap independent of that hook's duration; buffer stale 29 of 30) **[obs2]** + **[obs]**. But `speak.sh` does not exist, so **"the wait fixes it" is [inferred]** from an ordering, a buffer read and a publication point that have never been joined — and **two rounds of review found the publication point itself broken twice**: first unordered writes, then a commit-marker-plus-re-read that still accepted a mixed generation (§3.1's table). It is now content-addressed | build `speak.sh` and the worker's wait, then watch: measure the match rate **through the wait** over ~20 real turns, and record how often the deadline is reached. It should be the mirror of the 29-of-30 stale figure. **Widened twice in review to cover the producer half**, because the wait cannot be verified without it: §3.1's publish is now **content-addressed** — the rewrite is rename-installed at `speak/rw.<source hash>` and there is no `speak/source` — and that is **[inferred]** too. The property to check in the build is narrow and mechanical: **that no consumer ever opens a path it did not compute from its own expected hash**, which is a code-reading assertion rather than a race to provoke, and is why draft 3 is easier to verify than the two ordering-based drafts it replaces | **YES** — as specified before this revision the feature was silent on the large majority of turns above `MIN_CHARS`; the repair is now specified but unverified |
| **18** | **A slash-terminated path gets no rule at all, and it is audibly wrong.** Found by **ear**, in a shipped axis, by the listener: *"a pause is needed after the path if a `path/` ends with a slash. Now it sounds like `research/branches`"* **[heard]**. `_PATH_RE` requires `(?:SEG/)+SEG`, so `research/` and `~/research/` **never match at all**, and there is **no `rstrip("/")` or `endswith("/")` anywhere** in `bench/sanitizers.py` **[repo]**. The listener's own item escaped it only because axis 1 happened to set the backticked span off — outside backticks, `settled` leaves *"Saved to research/ branches"* untouched **[measured-here]** | **PARKED — the user's decision**, on the grounds that reopening axis 3 immediately after a 9–0 result costs more than it buys. To close: widen `_PATH_RE` to *see* a slash-terminated path, append a `BOUNDARY_CHARS` member after rule P, make `_tidy_commas` suppress the double where axis 1 already set the span off, then one listen | no — **parked deliberately, not overlooked.** Nothing is implemented and `COND_CUTOFF`-style constants are untouched |
| **19** | **`flag-pause` is NOT regression-free inside the settled combination, contrary to §4.3 as written.** On `r11` (a **real** item) axis 1 strips backticks that axis 8 steps over, producing `, $, claudish_ollama,` and `, curl , -K,` — shapes neither rule makes alone. Symmetrically, `r14` becomes a **no-op** because axis 7 eats the fence before axis 8 sees it **[measured-here]**. **`r11` was heard blind and `settled` still won it, so that half is HEARD AND TOLERATED, not harmless** **[heard]** | **the `r14` half was never played**, which is why §4.3's claim stays false as written rather than merely hedged. One pair — `r14:settled` against `r14:base` — closes it | no — one half is heard and tolerated; the other is a wording defect in §4.3, now corrected there |
| **20** | ~~§10.6's preemption rests on three worker-side hooks that are all [inferred]~~ **MEASURED and PARTLY FALSIFIED.** 312 trials over 26 switchable configurations **[trials]**, [`preemption-trials.tsv`](preemption-trials.tsv), re-derivable with `preemption-lock-probe/summarise.sh`. Confirmed: the claim-time kill is load-bearing (`C4` without it, stale audio runs to completion **12/12**, full 2.50 s). **Falsified: the two kills do not partition the timeline.** A worker dying between `Popen` and the record write orphans a player nothing reaches — `C8`, **12/12**, window median **1.41 ms**, range 0.43–5.61 ms, n = 72 (worker-published only; the pooled 96 include 24 synthetic `W` stamps — harness defect 4) — and neither a single player-written record (`C11b`) nor per-player records alone (`C12c`) closes it, both failing **12/12** at full length. The **process-group sweep** does: `C12b` kills before `exec`, **12/12**. §10.5 clause 7 is rewritten from three hooks to five, §10.6's partition sentence is replaced | **what is left**: (a) the ordering between clause 7's two sweep halves and clause 2's generation unlink — nothing has ever run an unlink, and `lockrace.py` never does one, so all 400 lock trials ran with every generation present; (b) **pid reuse under `killpg`** — the sweep addresses a recorded pid as a pgid, and a recycled pid names a stranger's group. The `.pending` marker bounds *when* `killpg` runs, not *what* it names. To close (b): drive a session long enough to wrap the pid space, or reason it away with a recorded start time per generation and reject a pid whose process is younger than the record. Then one run | **YES, still** — (b) can signal an unrelated process group, which is a worse failure than the one this clause fixed |
| **21** | ~~The stale-lock protocol's two clauses are [inferred]~~ **MEASURED and FALSIFIED — both of them.** 1200 trials, three protocols, six scenarios **[trials]**, [`lock-owners.tsv`](lock-owners.tsv). The residency probe's own protocol: **121/400** trials did not end with exactly one owner. The two clauses §10.5 clause 2 used to specify: **61/400**. **Worst case for both was 3 owners, not 2** — the cell above predicted 2 and was wrong about that as well. The initializing-lock retry is clean to a 50 ms stall (180/180) and then **40/40 wrong** at 200 ms and 1000 ms; the quarantine rename is **20/20 wrong** on the ABA, with a committed trace of a reclaimer quarantining the other reclaimer's *live* lock. The replacement — a `symlink`ed generation record, superseded rather than removed — is **0/400 wrong** | **what is left**: the generation **unlink** and its ordering against clause 7's two sweep halves, which is `[inferred]` and unrun — `lockrace.py` never unlinks a generation, so every trial ran with the full generation history present. To close: add an unlink arm to `lockrace.py`, staged both before and after the sweep, and confirm that the pre-sweep ordering re-opens the orphan region while the post-sweep one does not. Same rig, one more scenario | **YES** — an unlink ordered before the sweep destroys the target list clause 7(iv) reads, which puts back the orphan the process-group sweep exists to kill |
| 22 | The bench-to-hook TTFA gap (~0.37 s) is **decomposed by reasoning, not isolated by experiment** (§4). The control shares hardware but not load or cadence | **interleaved paired runs**: the same corpus item synthesized alternately through `bench/first-sentence.py` and through the hook, A/B/A/B in one session, so both arms see the same load and spacing | no — the gap is small, explained, and inside budget |
| 23 | **B′'s reach on real text is unproven.** It is a measured no-op on all 14 real rewrites and on **53 of the 54** corpus items; the only item it changes, `s38`, is synthetic **[measured-here]**. The listen confirmed the rule's **direction**, not its reach | a real capture with a short list whose lines do not already end in punctuation. Same shape as row 6 | no — a no-op cannot regress anything |
| **24** | **The worker's idle exit and `rewrite.sh:117`'s sweep are now separated by arithmetic that nothing has run** (§10.5 clause 6). The claim is that a live worker's speak directory always has an mtime newer than its 20-minute idle window — because every job arrival, claim-rename and `worker.lock.<gen>` `symlink` is a directory mutation — so `find -mmin +30` can never select it. Read off `find`'s semantics and `rewrite.sh:117` **[repo]**, **[inferred]**. Nothing in this project has been left idle for twenty minutes, let alone thirty | leave one session's worker resident and idle, sample `stat` on `$BUF_ROOT/<sid>/speak` and the worker's liveness once a minute across the 30-minute mark, and drive one `MessageDisplay` just past it to fire the sweep. Two things to record: that the directory survives while the worker is alive, and that the worker is gone by minute 21. **The same run also exercises the belt** — `rm -rf` the speak dir under a live worker and confirm it exits rather than blocking on a `kqueue` over a deleted directory | no — the failure needs twenty minutes of silence and costs a cold start or, at worst, a second worker that §10.5 clause 2 then has to survive. It is a **real** hole, but not one a first implementation is exposed to in a working session |

**Three of these still block shipping: 17, 20 and 21 — but rows 20 and 21 block for a different reason
than they did.** The experiment they used to owe **has been run**, twice: 1200 lock trials and 312
preemption trials, on an instrumented worker built for it. **It falsified four clauses this document
had marked LOCKED**, and what remains open in both rows is the residue of the *replacements* — a
generation unlink nothing has ordered, and `killpg` under pid reuse. **That is a smaller and better
characterised hole than "nothing measured drove a second job", and it is still a hole.** **Row 17
needs `speak.sh` to exist**, which makes it the first thing the implementation phase finishes rather
than the last.

**The rate is the finding, not any one falsification.** Rows 20 and 21 were written as *"these clauses
are reasoned but unmeasured"*. Measuring them did not confirm them; it showed **four of them wrong**,
including two that a review round had added specifically as repairs. A reviewer should read that as
evidence about how much weight the remaining `[inferred]` clauses can carry, which is §15's subject.

**Rows 1, 2, 3 — the three that blocked shipping before this revision — are all closed.** Two of the
three closures produced a new blocker of their own (row 3 → row 17, row 2 → rows 20 and 21), which is
what measurement usually does and is not a sign that the count is not moving: the new rows are about
mechanisms that now exist on paper, where the old ones were about decisions nobody had made.

**Row 24 is new and is NOT ship-blocking**, and the reason it is not is worth being explicit about
rather than leaving to the table cell: its failure needs twenty minutes of silence in one session, and
its worst outcome is a second worker that §10.5 clause 2 is separately specified to survive. **It is a
real hole and it is scheduled, not dismissed.**

### Can #11 lock?

**Yes — and what "lock" means here has to be said precisely, because it is not "ready to ship".**

**#11's lock is a specification lock: every section is either LOCKED with the evidence that decided it,
or OPEN with a closing condition that does not require re-deciding anything.** By that test this
document now passes, and it did not before this revision. **The four decisions #11 was actually waiting
on are made:**

1. **§3.5's last row** — the bounded wait, with its ceiling, its trigger and its timeout behaviour
   (§3.5.1). This was the only genuinely *new decision* the four measurements forced, and it is the one
   an implementer could not have derived.
2. **§4.1 clause 3** — boundaries, not segments, with the no-run clause. The implementation is back
   **in** contract; it had been knowingly out of contract with locked text since `settled` was
   registered.
3. **§10.5** — the residency mechanism, with its measured limit stated rather than implied.
4. **§5's unit** — nine invocations, never nine utterances.

**What #11 does NOT have, stated plainly so the lock is not read as more than it is.** Nothing in §13 is
a decision the listener still owes; rows 17, 20 and 21 are **verification of specified mechanisms**, and
row 18 is **parked by explicit decision** rather than unresolved. So #11 can lock and **#23 can start**
— but #23 finishes at row 17, not at "the hook runs". **An implementer who builds `speak.sh` and does
not measure the wait has not finished the ship blocker, they have moved it.**

**RE-EXAMINED THREE TIMES AND MEASURED ONCE, and the measurement is the one that matters.** The answer
above was written before anyone had read this revision back. Three independent review rounds have since
read it and one experiment has since exercised it, and between them they found **eleven correctness
defects in text this revision marked LOCKED** — with the second round finding defects **in the first
round's repairs**, and the experiment finding that **two of the first round's repairs were themselves
wrong**.

| round | finding | section |
| --- | --- | --- |
| 1 | publish not atomically ordered — a consumer could match the hash and read the previous turn's rewrite | §3.1 |
| 1 | the ensure-worker trigger was not implementable as written (needed `session_id` it had no source for) — the **second** correction to that one clause in a day | §10.5 cl. 4 |
| 1 | idle exit and sweep set equal, claiming an ordering equality does not give | §10.5 cl. 6 |
| 1 | the publish permitted to run while speech was off, contradicting the section title | §11 |
| **2** | **the round-1 repair was also wrong** — a commit marker plus a consumer re-read still accepts a mixed generation, because a re-read cannot detect an unpublished change | §3.1 |
| **2** | **`speak.sh` had no global disable check at all** — the plugin's master switch did not stop speech, though §10.8 promised it did | §10.3 |
| **M** | **the initializing-lock retry does not work** — a bounded backoff bets on a live process making progress; clean to 50 ms (180/180) and then **40/40 wrong** at 200 ms and 1000 ms. **A round-1 repair, falsified** | §10.5 cl. 2(a) |
| **M** | **the quarantine rename does not work** — `rename(2)` is path-addressed, so a reclaimer on a stale observation quarantines a *live* lock and gets success. **20/20 wrong** on the ABA. **A round-1 repair, falsified** | §10.5 cl. 2(b) |
| **M** | **the two kills do not partition the timeline** — a worker dying between `Popen` and the record write orphans a player nothing reaches, **12/12**; no record-based repair closes it | §10.6 |
| **3** | **the master switch used the wrong comparison** — step 0a tested `CLAUDISH_ENABLED` for *not `0`* and cited `rewrite.sh:57`, the default assignment. The gate is `:100` and it tests for exactly `1`, so `=false`, `=2` and `=yes` disabled the rewrite and **permitted the speech**. The round-2 repair, re-opened one value wide | §10.3 step 0a |
| **3** | **the runtime mute is unenforced for up to 50 s** — the hook `stat`s both off-files before enqueueing and the worker then waits `CLAUDISH_TIMEOUT + 5` s without re-checking them, so touching `claudish-speak-off` mid-wait still produces speech | §3.5.1 cl. 6 |

**The lock still holds on its own test, and the test is worth restating rather than assumed:** *every
section is either LOCKED with the evidence that decided it, or OPEN with a closing condition that does
not require re-deciding anything.* All six defects were repairable from evidence already in the
document; **not one needed a new decision from the listener**; and the two that needed a judgement
between competing repairs — clause 6's separation, and clause 5's required-versus-recommended — have
those judgements recorded with their costs. So #11 can lock and #23 can start.

**But the clean "yes" of the paragraph above is no longer the honest answer, and here is the precise
reason.** This document's stated purpose, in its own opening words, is to be *"a specification an
implementer can build from in one session without re-deriving a decision."* **An implementer who built
§3.1 from either of its first two drafts would have shipped a race** — the first speaking the previous
turn's text, the second speaking a mixed generation — and in both cases only a reviewer caught it.
§3.1 has now been wrong in three of its four drafts. **That is not a converged specification, and
calling it LOCKED without saying so would be the manufactured lock this document exists to avoid.**

**So the lock ships with a precondition, stated as a falsifiable commitment rather than a caution.**

1. **§3.1 and §10.3 get one more review pass before #23 writes code**, because both were repaired in
   the round that is still the most recent read, and nothing has read those repairs.
2. **If a third review of §3.1 finds a fourth defect, §3 should stop being marked LOCKED, and the
   publish should be settled by *building* it** — row 17 — rather than by a fifth draft. Two
   ordering-based drafts failed; content addressing is a different kind of answer, and if it fails too,
   the evidence will be that this mechanism cannot be settled on paper at all.
3. **The generalisable lesson, worth more than any of the six repairs, and it has since been
   VINDICATED by measurement:** both failed drafts tried to make a shared mutable path safe by
   **ordering access to it**, and the repair that held **removed the mutable path**. §10.5 clause 2
   was the other place that shape appeared — a lock file guarded by a retry-then-reclaim ordering rule
   — and §13 rows 20 and 21 pointed straight at it. **They were run, and both ordering rules failed:
   the retry 61/400, the quarantine rename 20/20 on the ABA.** The repair that held is the same shape
   as §3.1's: **stop mutating a contested path** — a generation record is created, never removed, and
   ownership is a name rather than a state. **Two independent instances now say the same thing, which
   is as close to a rule as this document has.**

**Neither row 24 nor the required warm-up changed the shipping count**: rows 17, 20 and 21 still block,
and all three need building or measuring rather than deciding.

**One thing a reviewer should attack rather than accept — and the argument against it is now dead.**
Rows 20 and 21 are marked ship-blocking on judgement, not on a rule. The argument for it: both are
cases where **this document states a rule that is false unless an unmeasured clause holds**, which is
exactly the shape §13 rows 1–3 had. **The argument against used to be that the clauses were cheap,
obviously correct on inspection, and their failure windows microseconds wide. Every part of that is
now measured false.** The windows were not microseconds — a 200 ms stall breaks the retry 20/20 and
the orphan window is milliseconds, not microseconds. The clauses were not obviously correct on
inspection — four of them are wrong, and two were themselves review repairs. **A reviewer who still
wants to move these rows to non-blocking must argue about the residue that survived the run** — the
generation unlink's ordering and `killpg` under pid reuse — **and not about the clauses that have
already failed.**

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

**Add the two qualifications this revision changed:** the cutoff is now **contradicted at 4** rather
than merely unaudited (§13 row 5), and **B′ exists** — implemented, registered as `lb-auto`, composed
into `settled`, and heard — so the "no registered sanitizer implements a conditional boundary" clause is
discharged rather than pending.

**`docs/decisions/sanitizer-audition.md` was deliberately not amended when this section was written**,
because that file was modified on `task/audition-13-followup-rules` (PR #18) and editing it from #19's
branch would have entangled the two. **#18 has merged, so that reason is spent**: axis 2's closure, the
boundaries correction, and the `s04` contradiction should now land in the #8 doc of record. **This
integration pass does not do it** — it is a different document's amendment, not this spec's content, and
it is named here so it does not go missing.

### 14f. One factual correction to the **#10** bullet in *Decisions so far*

The bullet says *"the rewrite **adds seconds** below ~600 raw chars and only pays for itself above
~1600"*. That is true of **spoken audio duration**, not of latency, and nine of the twelve pairs are
the duration law's predictions rather than stopwatch readings (only `r01`, `r03`, `r06` were
synthesised). Suggested wording: *"the rewrite's **audio is longer** below ~600 raw chars and only
gets shorter above ~1600 (three pairs measured, nine predicted by the duration law)"*.

### 14g. Two amendments this revision adds

- **The out-of-scope list needs one more narrowing, of the same shape as 14a and made for the same kind
  of reason.** #1's fail-open bullet bans speech "on the fail-open path", and §3.5's last row used to
  implement that as *silence whenever no rewrite is buffered above the threshold*. **That conflated "the
  rewrite failed" with "the rewrite has not happened yet",** and the second is the common case because
  `Stop` does not wait for `MessageDisplay` (§3.5.1). The ban is unchanged in substance — a **failed**
  rewrite is still silent — but #1 should say that the speech path **waits, bounded, for the rewrite it
  is going to speak**, because a reader of #1 alone would otherwise expect speech at the end of the turn
  and file the delay as a bug. → §3.5.1
- **#1's standing constraints should record that speech now has a resident worker.** A per-session
  Python process holding a few hundred MB, elected by an exclusive `symlink`, woken by `kqueue`,
  exiting after 20
  minutes idle (§10.5). It is not a knob and not a scope change — it is the mechanism behind the only
  latency figure #1 quotes — but it is a **new process in the user's session** and #1 is where the
  footprint of the feature is described. Include the rejected `launchd` alternative and the reason
  (off-by-default features do not install background daemons), because that is the decision a reader is
  most likely to want to re-litigate.

---

## 15. Where this spec is weakest

Stated so a reviewer can attack the right parts.

- **The load sensitivity of the warm path, which is the honest replacement for this section's old
  first bullet.** That bullet read *"§10.5 is the real gap … no TTFA has ever been measured from a
  hook."* **It has been now**, so the bullet is retired rather than reworded. What replaces it is
  smaller and real: **warm TTFA is dominated by `Kokoro.create()`, which is CPU-contended, and it
  exceeded 3 s twice in thirty turns** — 4.014 s at 1-minute load 11.9, and 3.829 s during a machine
  spike, both synthesis-time blowouts rather than hook overhead **[hook]**. §4 used to read as though
  the warm path were unconditionally under the line. **It is not, and the load average is a poor enough
  instrument that the buckets do not separate cleanly — the worst row is in the *quiet* bucket.**
- **Every cold figure in this project is optimistic by an unmeasured margin, and the margin cannot be
  measured here.** "Cold" means **no worker resident** with the 310 MB model still warm in the page
  cache; purging the page cache needs `sudo`, which this machine's user does not have. **This is a
  closed environment limitation rather than an owed measurement**, and it cannot flip a verdict — cold
  already fails the 3 s line at 4 of 7 turns without any page-cache penalty, and a bigger number makes
  an already-failing case fail harder. **The residual case is the first turn after a boot or real memory
  pressure on a 16 GB machine, and the residency mechanism does not help there**, because it only pays
  off once a worker exists.
- **§3.5.1's bounded wait is the newest and least-tested thing in this document, and it is load-bearing
  for the whole feature.** The race it repairs is measured twice and reproducible. **The repair is not
  measured at all.** It has never been implemented, and it is specified against a §6 guarantee it must
  not break — the arrangement that keeps it safe (the wait lives in the worker, not the hook) is
  reasoning, not an observation. If it is wrong somewhere, the most likely place is the interaction
  between an abandoned wait and §10.6's kills, which is the same timeline §13 row 20 is about. §13 row
  17.
- **FIVE [inferred] correctness clauses now ship, and they are enumerated here so the number is
  checkable rather than asserted.** (1) **§10.5 clause 2's generation unlink and its ordering** — a
  worker may unlink generation `g` only after both halves of the election sweep against `g`'s owner
  have completed; `lockrace.py` never unlinks, so all 400 trials ran with the full generation history
  present. (2) **§10.5 clause 7(iv)'s `killpg` under pid reuse**, and its hook-side twin at §10.3 step
  8c — a recorded pid that has been recycled names a stranger's process group, and the `.pending`
  marker bounds when `killpg` runs, not what it names. (3) **§10.5 clause 6, the idle-exit/sweep
  separation.** (4) **§3.1's content-addressed publish.** (5) **§3.5.1 clause 7, the worker's
  re-check of both off-files at the point of synthesis** — new in this revision, and the only one of
  the five that closes a hole rather than carrying a residue.
  **What the count deliberately EXCLUDES, so that a recount lands on five rather than eight.** Three
  other things in this document carry an `[inferred]` tag and are **not** correctness clauses: §10.5
  clause 4's claim that the `readdir` stays negligible on a long session's directory, §10.3's claim
  that the hook's 0.063–0.219 s range survives the two `readdir`s that replaced two `stat`s, and
  §10.7's row for a worker that can never start. The first two are latency, the third is a disclosed
  failure path. **A clause counts here only if a rule stated elsewhere in this document is FALSE
  without it.**
  **The count went 3 → 6 → 5, and the composition turned over almost completely.** It said "three"
  before the integration pass and was undercounting even then; review took it to six; and **the
  measurement round then removed four of those six by running them** — clause 2(a) and 2(b) were not
  confirmed but **falsified** (61/400 and 20/20), and clause 7(ii) and 7(iii) were confirmed by
  experiment and are no longer `[inferred]` at all. Three new residues arrived with the replacements.
  **The entries that survive are still the ones found by reading a mechanism rather than by a
  failure** — which is the good way to find them, and also the reason none has been provoked. **They
  are the clauses that make stated rules true**, so "unmeasured" here is a different weight than it is
  on a latency figure. §13 rows 17, 20, 21 and 24.
  - **What the falsifications say about the five that remain, stated because the arithmetic invites
    the wrong reading.** Two `[inferred]` clauses left this list by being **measured wrong**, not by
    being confirmed. The base rate this document has for "a correctness clause reasoned out and
    written down" is therefore **worse than a coin flip on the only sample that exists**, and a
    reader should price the remaining five accordingly rather than reading the smaller number as
    progress.
- **THREE review rounds and one measurement round have now found ELEVEN correctness defects in text
  this revision itself marked LOCKED, and the rate — not any one defect — is the weakness.** Counted so
  the number is checkable: **four in round one, two in round two, three in the measurement round, and
  two in round three.** *The measurement round*: §10.5 clause 2(a) and 2(b) — both of them **review
  repairs**, falsified 61/400 and 20/20 — and §10.6's two-kill partition, falsified 12/12 (§13 rows 20,
  21). *Round three*: **§10.3 step 0a tested `CLAUDISH_ENABLED` for *not `0`* where `rewrite.sh:100`
  tests for exactly `1`** — an off-by-default hole one value wide, in the step written to close an
  off-by-default hole, so `=false`, `=2` and `=yes` all disabled the rewrite and permitted the speech;
  and **§3.5.1 left the runtime mute unenforced for up to `CLAUDISH_TIMEOUT + 5` s**, because the hook
  `stat`s the off-files and the worker then waited 50 s without re-checking them. Round three also
  corrected four things that are misstatements rather than defects, and they are named where they live:
  §3.1 naming the hook as the writer of `spoken` and `pid`; §4.1 borrowing a 17-of-54 figure from a
  different measurement; §5 claiming coalescing bounds a `Stop` ladder to one synthesis; and §10.8
  calling a specified gate implemented. **The earlier rounds:** Round one: §3.1's publish was not
  atomically ordered, so §3.2's guarantee had a hole one layer below where §3.2 states it; §10.5
  clause 4's trigger was not implementable as written, for the second time in one day; §10.5 clause 6
  set two timeouts equal and claimed an ordering equality does not give; §11 permitted the publish to
  run while speech was off, contradicting its own title. **Round two, on the repairs themselves**:
  §3.1's replacement was *also* wrong — a re-read cannot detect an unpublished change — and `speak.sh`
  had **no global disable check at all**, so a user who had switched the whole plugin off would still
  have heard audio.
- **The §3.1 sequence is the one to learn from, and it is now the most-revised paragraph in this
  document: unordered writes → commit marker → seqlock → content addressing.** Three of those four were
  wrong, and the first two repairs were wrong *in the same way* — both tried to make a mutable reused
  path safe by ordering access to it. **The fix that held removed the mutable path instead.** A reviewer
  should generalise that rather than trust this paragraph: where this spec guards a shared mutable file
  with an ordering rule, the ordering rule is the smell. **§10.5 clause 2 was the other place that
  shape appeared, §13 rows 20 and 21 were pointed at it, and the run confirmed the smell** — both of
  its ordering rules failed, and the repair that held is §3.1's repair again: a record that is created
  and never mutated, with ownership carried by a name.
- **All eleven are repaired in place, none needed a new decision from the listener, and that is why §13
  still answers *"can #11 lock?"* with yes.** But three independent reads and one experiment on the same
  text found eleven real defects; the second read found defects **in the first read's repairs**; and the
  experiment found that **two of the first read's repairs were themselves wrong** — so the honest
  posture is that §3 and §10.5 have not converged, and **§13 now says a verification pass over them is
  a precondition for #23 rather than a nice-to-have.** This is the same lesson as the §5 bullet below,
  arriving from a different direction and rather more forcefully.
- **`launchd` was rejected on judgement, not on measurement**, and it is the alternative in §10.5 most
  worth pushing back on: it would be permanently resident and survive machine sleep, which is genuinely
  better on latency. The three reasons against it — a background daemon for an off-by-default feature,
  no sweep reclaiming it, no per-session scoping — are all real and none is a number.
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
- **§3.2's match rate is measured and passes; what is left is the one shape it never met.** Both of
  this section's old bullets on §3.2 — *"the match rate is unmeasured"* and *"`prompt_id` on
  `MessageDisplay` is an assumption the evidence does not carry"* — are answered and are replaced by
  this one. **35/35 byte-identical, and 15/15 re-derivable** — but the harness joins **text blocks
  only**, and **no message in 50 had two text blocks**, so the join has never had anything to join.
  **That is the untested edge, and it is the only shape that can break the equality.** The 35 rows are
  also **not re-derivable** (inputs destroyed at teardown); the reproducible claim is the 15.
- **The `EMOJI` judgement and the disqualifying/harmless cut line are unchanged and still the places to
  check against the listener's intent** — see the two bullets below, which this revision did not touch.
- **`async: true` remains the thinnest claim about the harness anywhere in this project** — one
  compiled-schema string. §6 is written so that nothing depends on it, which is the mitigation, not
  a resolution.
- **Axis 2's cutoff is now CONTRADICTED at 4, and the constant was deliberately not moved.** The
  conditional rule itself is confirmed by ear — B′ won `s38` blind, and `s38` is the only corpus item
  where the boundaries and segments readings differ at all. **The cutoff is a separate question and the
  one wav at the seam went against the file** (§4.1 qualification 1, §13 row 5). What *is* solid and
  verified in code: the variant could not have expressed the distinction (`\n+`, one boundary
  character), and neither boundary carries crash-safety weight. **The most likely error is still on
  paragraph runs**, where the only evidence remains one tie (`r09`) and where the choice made — one run
  per message, no blank-line special case — is unheard in either direction.
- **The 9–0 sweep is one listener, one sitting, one voice, and it is the strongest evidence in this
  document about the sanitizer.** It closed §4.2 and it should not be stretched further than that: it
  says the composition beats `base`, on nine pairs, five of them real. It does not say the composition
  is optimal, that the interactions inside it are inaudible (§13 row 19 says one of them is *tolerated*),
  or that any axis would survive a re-vote it was not given.
- **`path-short-nolead` rests on one genuinely combinational pair** (`s12`), and **`flag-pause` on
  four synthetic ones**. Both are adopted undefeated; neither margin is as thick as "4–0" reads. **And
  axis 3 now has a known defect it ships with**: a slash-terminated path gets no pause and no rule looks
  at one (§13 row 18, parked).
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
