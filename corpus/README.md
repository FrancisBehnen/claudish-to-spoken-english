# Speech corpus: real rewrites plus a synthetic hazard set

The text the listening tickets judge against. Built for
[#7](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/7), part of the
[Kokoro speech map (#1)](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/1).
Assembled 2026-08-15.

**Nothing here is a claim about how anything sounds.** No audio was synthesised and nothing was
listened to while building this. The hazard classes are taken from the two measured research docs;
this directory only assembles text that contains them.

**54 items: 14 real, 40 synthetic.** Each half covers the other's blind spot, which is measurable
rather than rhetorical — **20 of the 53 hazard classes appear in no real item at all** (see
[Coverage](#coverage)). Fourteen real messages really would have missed them.

> **Corrected 2026-08-15.** The chunking items and their explanation were first written against
> `kokoro-text-handling.md`, which measures **`KPipeline`** — the torch/`hexgrad-kokoro` path. The
> project settled on **espeak via `kokoro-onnx`**, a different codebase, and
> [`espeak-sanitizer-rules.md`](../docs/research/espeak-sanitizer-rules.md) is authoritative for
> chunking. The `\n+` boundary claim was wrong on the chosen path; see
> [Chunking](#chunking-s34-s38). Items `s37` and `s38` were added for the crash shape that omission
> had left uncovered.

> **Extended 2026-08-17.** Items `s39` and `s40` and the class `MD-FENCE-MULTI` were added because
> every fence in the corpus held a **one-line** body, which made
> [#8](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/8)'s code-block wording axis
> unjudgeable — see [Multi-line code blocks](#multi-line-code-blocks-s39-s40).

> **Extended 2026-08-25.** `MD-FENCE-MULTI` was **synthetic-only**, so axis 7's count wording had been
> settled by ear on a shape production had never been shown to produce. It does produce it: a scan of
> every transcript on this machine found **258 real assistant messages** carrying a fence with two or
> more non-blank body lines, 9 of them in this repo's own sessions. Two of those messages are now in
> `source/` as `r13` and `r14`, **their rewrites were captured the same day** (two subscription calls,
> both `rc=0`), and the measured size distribution is recorded in
> [Multi-line code blocks](#multi-line-code-blocks-s39-s40). The corpus is **54 items**, and
> `MD-FENCE-MULTI` now reads **`2 real, 2 synthetic`**; `ID-SHA`, `PATH-ABS` and `NUM-THOUSANDS` came off
> zero real with it, as a side effect. What is still open is **audio**: no real multi-line block has been
> synthesised or heard.

---

## Layout

```
corpus/
  README.md        this file
  manifest.tsv     one row per item: id, kind, measurements, hazard classes, origin, note
  classes.tsv      the 53 hazard classes and what each one names, with doc citations
  notes.tsv        hand-maintained per-item origin and intent (input to manifest.tsv)
  capture-log.tsv  one row per subscription rewrite call actually spent
  spoken/          THE CORPUS: 54 plain-text files, the text a speech path would say
    r01.txt .. r14.txt   real  — the plain-English rewrite of a real assistant message
    s01.txt .. s40.txt   synthetic — hand-authored, one or a few hazard classes each
  source/          the real assistant messages the rNN rewrites were produced from
    r01.txt .. r12.txt   captured 2026-08-15
    r13.txt, r14.txt     captured 2026-08-25 for MD-FENCE-MULTI, rewritten the same day
  bin/             the scripts that built and verify all of the above
```

**Why this shape.** A harness consumes `corpus/spoken/*.txt` and nothing else — one glob, one file
per utterance, no parsing, no front matter inside the text. Metadata that would otherwise have to be
embedded in the files (and would then be spoken) lives in `manifest.tsv` beside them. `source/` is
kept separate rather than interleaved so that glob stays clean: a real item's `source/rNN.txt` is its
input and `spoken/rNN.txt` is its output, sharing an id.

Three distinctions worth keeping straight:

| File | What it is | Role |
| --- | --- | --- |
| `source/rNN.txt` | a real assistant message, verbatim | the rewrite hook's **input** |
| `spoken/rNN.txt` | the plain-English rewrite of it | hook **output** = speech **input** |
| `spoken/sNN.txt` | hand-authored fixture | speech **input** directly; not a rewrite of anything |

So most synthetic items are short and carry the `LEN-UNDER` class: they sit below the rewrite hook's
200-character gate and would never be *produced* as rewrites. That is not a defect. They are
speech-path fixtures, not hook inputs. `s32` and `s33` are the two items that deliberately probe the
200-character boundary itself, at prose_len 199 and 201.

Every hazard token sits in a carrier sentence rather than a bare word list, because both research
docs establish that outcomes depend on context — spaCy's tagger drives misaki's decisions, and espeak
spelled `MIN` and `MAX` in a sentence but spoke them in isolation.

## The real half

14 genuine assistant messages from real Claude Code sessions in this repo, rewritten by the real
plugin path.

**Twelve were assembled 2026-08-15; `r13` and `r14` were added 2026-08-25.** The two late ones were
captured to give `MD-FENCE-MULTI` a real item, and their rewrites were paid for the same day — two
`claude-cli` calls, both `rc=0`, logged in `capture-log.tsv` exactly like the other twelve. What that
measured, including the one class that did *not* survive the rewrite, is in
[Multi-line code blocks](#multi-line-code-blocks-s39-s40).

### How they were captured

The ticket asked for the least invasive way to capture finished rewrites. **Read the session
transcript.** The assistant message `rewrite.sh` reconstructs from streamed `MessageDisplay` deltas is
already persisted verbatim in `~/.claude/projects/<project>/<session>.jsonl`, so no hook needed
changing, no `tee` was inserted, no debug flag was left on, and there is nothing to un-install. The
three alternatives were all worse: `CLAUDISH_DEBUG=1` logs diagnostics but not the finished rewrite;
a temporary `tee` inside `emit` means editing a display hook that must never break; and the buffers
under `${TMPDIR}/claudish-to-english/<session>/<message>/` are deleted by `cleanup` on the same run
that produces the rewrite, so they hold only in-flight fragments.

**The rewrites themselves could not be harvested from history and had to be produced.** The plugin
was installed and firing throughout those sessions — `${TMPDIR}/claudish-to-english/<session>.notified`
exists, which is the once-per-session provider-failure marker — but `ollama` on this machine has zero
models pulled, so every live rewrite failed open and no rewritten text was ever generated to capture.
`bin/capture-real-rewrites.sh` therefore ran the real path over each captured message.

That script does **not** re-implement `rewrite.sh`. It sources the plugin's own `providers.sh` and
calls `llm_complete` with the system prompt string copied verbatim from `rewrite.sh:170`, so what
landed in `spoken/` is what the plugin would actually have put on screen.

### Provider, model, cost

| | |
| --- | --- |
| Provider | `claude-cli` (`CLAUDISH_PROVIDER=claude-cli`) |
| Model | `haiku` — the CLI alias, which is `providers.sh`'s default for this provider |
| CLI version | `claude` 2.1.233 |
| Timeout | `LLM_TIMEOUT=120` (raised from the plugin's 45s default; nothing here is on a display critical path and the longest source is ~4 KB) |
| Calls spent | **14** — one per item, no retries (12 on 2026-08-15, then `r13` and `r14` on 2026-08-25) |
| Failures | none: `rc=0`, `ratelimited=0`, `truncated=0` on all 14 |
| Wall time | 6–13s per item, 133s total |

`claude-cli` was the only working route: it runs on this machine's Claude Code **subscription**, and
the `ollama` default cannot answer with no models pulled. **Every call consumed the same 5-hour and
7-day subscription windows as real work**, which is why the capture is capped (`MAX_ITEMS`, default
20), stops immediately on `ratelimited=1`, and skips any item already captured so nothing is paid for
twice. Per-call outcomes are in `capture-log.tsv`.

One trap the script exists to defuse: this machine exports
`CLAUDISH_MODEL=qwen3:4b-instruct-2507-q4_K_M` for the ollama path. Left set, `providers.sh` hands
that string to the CLI as `--model` and every rewrite fails. The script unsets it.

### Known deviation from the live hook

`rewrite.sh:184-190` also reads the preceding **user** message off `.transcript_path` and appends it
to the system prompt as context. **All 14 rewrites were produced without it.** Selecting user
prompts out of a transcript is blocked by this machine's permission classifier, and that was not
worked around. The no-context path is one `rewrite.sh` supports explicitly — *"Missing/unreadable
transcript -> no context, still rewrites"* (`rewrite.sh:20`) — so these are valid rewrites, but they
are the no-context variant. Anyone regenerating the corpus with transcript access should expect
slightly more on-topic output and should re-record that fact here.

### Provenance

Full origin per item is in `manifest.tsv` (`origin` column): the session id, the message uuid, and
the timestamp. The original 12 come from two prior working sessions on this repo
(`d51e4ee0…` and `62d419ff…`, 2026-08-14 and 2026-08-15) — deliberately not from the session that
built this corpus. They were picked for a realistic spread of length (prose_len 204 → 3309 on the
source side) and for resembling what the plugin actually rewrites, **not** for hazard coverage; that
is the synthetic half's job, and keeping the selection independent of it is what makes the coverage
table's empty real-item classes meaningful.

`r13` and `r14` break that last rule on purpose, and they are the **only** two that do: they come from
session `62d419ff` on **2026-08-25** (the same session five of the twelve came from, continued) and
they were selected **for** a hazard class — `MD-FENCE-MULTI`, the one class the coverage table could
not fill from real output. Everything else about the selection was kept the same: main-chain assistant
messages, this repo's own sessions, above the 200-character gate, of a length the plugin really does
rewrite. Their arrival is why the empty-real count is **20** rather than the 24 the corpus shipped
with — `MD-FENCE-MULTI` plus three incidental classes — and the 20 that remain are still untargeted,
because nothing has ever been picked to fill them.

## The synthetic half

40 hand-authored items, `s01`–`s40`, each targeting one or a few named hazard classes so that every
class is present at least once regardless of what the real messages happened to contain. Per-item
intent is the `note` column of `manifest.tsv` (maintained in `notes.tsv`).

These are **authored source data, not generated output**. There is no script to regenerate them; edit
the `.txt` files and re-run `bin/build-manifest.sh`.

Grouped roughly: `s01`–`s07` markdown syntax, `s08`–`s14` paths and code locations, `s15`–`s20`
identifiers, `s21`–`s25` numbers, `s26`–`s29` URLs, emoji, glyphs, flags and symbols, `s30` a
prose-only control, `s31` the inline phoneme override, `s32`–`s33` the 200-character gate,
`s34`–`s38` the five chunking cases, and `s39`–`s40` the two multi-line fenced code blocks.

Several items are deliberately **controls** — classes both research docs found already correct
(`s09` bare extensions, `s16` the `NAME=0` form, `s25` percentages and currency, the `FLAG-LONG` half
of `s28`, `s30` plain prose). A corpus that only contains known-bad tokens can confirm a sanitizer but
never refute one.

### Chunking (`s34`–`s38`)

Authority for this section is
[`espeak-sanitizer-rules.md`](../docs/research/espeak-sanitizer-rules.md) §10 and §11, the only
research measured against **`kokoro-onnx`** — the frontend the project settled on. Three facts drive
all five items:

- **`Kokoro.create()` splits on `. , ! ? ;` and nothing else** (`_split_phonemes`,
  `kokoro_onnx/__init__.py:136-168`). `:` and `—` are in the vocab and reach the model but are **not**
  boundaries, so a lead-in colon does not create one.
- **`\n` is not in `DEFAULT_VOCAB` and is silently deleted.** It is neither a boundary nor a pause,
  and `\n\n` collapses to nothing as well. Lines fuse into one run (words do not glue together —
  espeak inserts a space — but there is no seam).
- **A run reaching 510 phonemes raises**, not truncates: `IndexError: index 510 is out of bounds for
  axis 0 with size 510`, an off-by-one in `_create_audio`. **509 phonemes is the last safe batch.**

So the risk metric is the **longest run containing no `. , ! ? ;`, measured after newlines are
deleted** — reported as `max_run` in `manifest.tsv`. At the measured ~1.02 phonemes per input
character, the danger point is a run of roughly 500 characters.

| item | shape | `max_run` | expected on `kokoro-onnx` |
| --- | --- | --- | --- |
| `s34` | 1313 B, one line, fully punctuated | 104 | needs several batches, **splits cleanly** |
| `s35` | 1281 B, one line, no `. , ! ? ;` at all | 1280 | **raises `IndexError`** |
| `s36` | 7 short lines, each ending in a full stop | 64 | safe — the **stops** make the boundaries, not the newlines |
| `s37` | 9-line bullet list, no terminal punctuation, lead-in colon | 644 | **raises `IndexError`** — the realistic crash shape |
| `s38` | 4-line bullet list, no terminal punctuation, short | 102 | safe — control isolating shape from length |

`s37` is the item that matters most, because it is the shape a real rewrite takes when it emits
bullets without full stops: the newlines vanish, the bullets fuse into one 644-character run, and
there is no boundary anywhere in it. `s38` proves the shape alone is not the fault — the same
structure at 102 characters is fine. `s36` and `s38` together isolate the two variables.

**Superseded:** an earlier version of this section claimed only a single long line could reach the
chunker, because `KPipeline` splits on `\n+` first. That is true of the **torch** path and false here;
`kokoro-onnx` has no such split. The `\n+` split is why `SPLIT-NEWLINE` is now documented as buying
nothing rather than as free pipelining.

### Multi-line code blocks (`s39`–`s40`)

Added 2026-08-17 for [#8](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/8)
axis 7, *how a skipped code block is announced*. That a block is skipped and announced is settled; the
wording is not, and the candidate wordings differ mainly in whether they say a **line count**
(`rule_N_code_block` in `bench/sanitizers.py`). The corpus could not judge that. `r07` and `s07` were
the only items with a fence and **both bodies are one line**, so every wording said "one line" and the
ticket's own "twelve-line code block" example had nothing behind it.

| item | fence body | `max_run` | what the count wording says |
| --- | --- | --- | --- |
| `s39` | **12** non-blank lines — a shell function, in a paragraph that proposes moving the chunk guard into the worker | 215 | `twelve` |
| `s40` | **3** non-blank lines — the same guard expressed as sanitizer calls, in the same carrier | 171 | `three` |

They are a pair for the reason `s36` and `s38` are a pair: everything but the one variable is held
still. Same carrier prose, same subject, same block language — so `Code block, twelve lines.` against
`Code block, three lines.` moves the number word and nothing else, and either can be set against
`Code block.` to ask whether the count earns its words at all. Both blocks sit mid-paragraph after a
colon lead-in, which is how `r07` really emits one.

**Both are safely under the chunk budget, and that is itself a finding.** A 12-line shell block fuses
into a 215-character run once the newlines are deleted — well short of the detector's 400-character
flag and of the ~500-character danger point (see [Chunking](#chunking-s34-s38)). The crash shape does
not come free with a long code block; it needs `s37`'s length. Neither item carries
`CHUNK-LIST-NOPUNCT`, and both `notes.tsv` rows record the `max_run` so that is not a surprise later.

#### The shape is real — measured 2026-08-25

`s39` and `s40` were authored on the assumption that a multi-line fenced block is something real
assistant messages emit. Nobody had checked. Checking it is free — the messages are already on disk —
so it was checked, over **every** transcript under `~/.claude/projects/`, matching fenced blocks in
**assistant message text only** (not tool inputs, not tool results, not file content echoed back):

| | |
| --- | --- |
| transcripts scanned | **886** top-level session files across 30 project directories (1,395 counting the `subagents/` files) |
| assistant records in them | **70,543** (95,887 counting subagents) |
| …carrying a text block | **14,991** |
| …whose text holds a triple-backtick fence | 420 |
| …whose fence body holds **2+ non-blank lines** | **258 distinct messages**, holding 291 such blocks |
| in this repo's own sessions | **9 messages**, all main-chain, fence bodies of 2–5 lines |

So the shape is not hypothetical: roughly **1 in 58** assistant messages that say anything at all
carries a multi-line fenced block, and this project's own sessions produced nine of them.

**The size distribution is the part that bears on axis 7.** Of the 291 blocks: median **4** non-blank
lines, p90 40, max 121; **69% are 2–5 lines** and **19% are 12 or more**. So `s39`'s twelve-line block
is a real magnitude but a tail one, `s40`'s three-line block is the *modal* one, and in this repo's own
history nothing genuine exceeded **five** lines — the only bigger block in these sessions was a
resumed-session state dump with no prose around it at all, which the 200-character gate would never
have sent to a model. Whatever axis 7 settles on has to read well at N = 3 or 4 first, and at N = 12
second.

**The two captured messages.** Both are from this repo's own sessions, both main-chain, and both meet
every criterion `r01`–`r12` met: real assistant text, above the 200-character gate, of a length the
plugin actually rewrites. The one criterion they do **not** share is independence from the coverage
table — unlike the twelve, these two were picked **for** `MD-FENCE-MULTI` (see
[Provenance](#provenance)). Measured on the rewrite **input**:

| item | fence bodies | `prose_len` | bytes | `max_run` | origin |
| --- | --- | --- | --- | --- | --- |
| `r13` | **1 line + 4 lines** — a push result, then the four `/plugin` commands after a colon lead-in | 965 | 1358 | 341 | `62d419ff:e9314dee` 2026-08-25T09:31:35Z |
| `r14` | **2 + 2 + 3 lines** — an ollama error, a token-budget sum, three `OLLAMA_*` settings | 2042 | 2834 | 260 | `62d419ff:bf63018e` 2026-08-25T09:38:31Z |

Those are `bin/detect-hazards.sh` over `source/`. The `spoken/` numbers are the ones `manifest.tsv`
carries, because the manifest is built from `spoken/` — and they came out different:

| item | fence bodies in `spoken/` | `prose_len` | bytes | `max_run` |
| --- | --- | --- | --- | --- |
| `r13` | **1 line + 4 lines**, both byte-identical to `source/` | 864 | 1243 | **342** |
| `r14` | **2 lines** — the first block only; the other two were rewritten away | 1133 | 1474 | 189 |

`r13` pairs a one-line and a multi-line fence inside one message, which no other item does. `r14` was
picked as the multi-block case and did not stay one. Both also carried tokens of classes that had **no**
real item at all — `ID-SHA` and `PATH-ABS` in `r13`, `MD-HASH` and `NUM-THOUSANDS` in `r14`. **Three of
those four survived** and moved off `0 real`; **`MD-HASH` did not** — `r14`'s three `##` headings are
gone from its spoken half, so that class is still synthetic-only (`s02`). Either way that was a side
effect, not the reason the two were picked.

**What the rewrite did to the fences — measured, not expected.** The rewrite system prompt says *"Leave
fenced code blocks unchanged"* (`rewrite.sh:170`, copied verbatim into `bin/capture-real-rewrites.sh`),
and before these two the only evidence was `r07`, whose **one-line** fence body is byte-identical in
`source/` and `spoken/`. Two multi-line items now say more, and they do not say the same thing:

- **`r13` — the prompt held.** Both bodies, the one-line push result and the four `/plugin` commands,
  survive byte for byte. A four-line block really does reach the speech path as four lines, which is
  exactly the input `rule_N_code_block` counts and pluralises.
- **`r14` — one of three blocks survived.** The 2-line ollama error is byte-identical. The 2-line
  token-budget sum and the 3-line `OLLAMA_*` listing are **gone**, along with the prose that framed
  them: the model compressed 2,042 characters of prose to 1,133 and dropped those passages wholesale
  rather than editing the fences inside them.

So the guarantee is narrower than "a body's line count survives". A fence the rewrite **keeps**, it
keeps intact — but it is free to drop a paragraph and take that paragraph's fence with it. For axis 7
that is harmless, since `rule_N_code_block` only ever counts blocks that reach it; for anyone building
on the assumption that every `source/` fence reappears in `spoken/`, it is not.

**What is still missing, precisely: audio, not text.** `MD-FENCE-MULTI` now reads **`2 real, 2
synthetic`** and `spoken/r13.txt` carries a genuine four-line body, so a real multi-line block is in the
corpus a harness reads. **Nothing has synthesised it.** Every multi-line code-block wav in
[the audition](../docs/decisions/sanitizer-audition.md) is still of `s39`/`s40`, so axis 7's caveat
survives in a narrower form: *the wording was chosen by ear at an authored magnitude, and the real
magnitudes now sitting in `spoken/` — four lines and two — have never been heard.* Closing that needs a
synthesis run, not a subscription call.

### Why `MD-FENCE-MULTI` is a class

`MD-FENCE` names a phoneme fact — three backticks become three curly quotes on each side — and that
fact is identical for a one-line body and a twelve-line one. On the taxonomy's own terms the
distinction therefore does not belong in it, and the honest alternative was to add nothing and let
`manifest.tsv` speak.

It was added anyway, for one reason: **the coverage table is how this corpus checks itself, and it
read `MD-FENCE 1 real, 1 synthetic` while being unable to answer the only question axis 7 asks.** The
gap was invisible in the one place built to make gaps visible. A class costs one row here and one
`awk` in `bin/detect-hazards.sh`; not seeing the gap cost an audition axis.

The alternative was rejected on measurement, not taste: `manifest.tsv`'s `lines` column counts the
whole item, not the fence body — `s07` is 5 lines with a one-line block — so nothing derivable from
the manifest separated the two shapes.

Two caveats kept explicit. The class carries **no doc citation**, because neither research doc
measures it; `GLYPH` is the precedent for carrying a class defensively rather than because a doc
measured it. And it is **not a claim about sound** — it says a fence body holds more than one non-blank
line, which is exactly the input `rule_N_code_block` counts and pluralises.

## Coverage

53 hazard classes, taken from
[`docs/research/kokoro-text-handling.md`](../docs/research/kokoro-text-handling.md) (#3, misaki, from
source plus a real G2P run),
[`docs/research/kokoro-programming-text-audio.md`](../docs/research/kokoro-programming-text-audio.md)
(#10, both frontends on the installed ONNX path) and
[`docs/research/espeak-sanitizer-rules.md`](../docs/research/espeak-sanitizer-rules.md) (#8, measured
against `kokoro-onnx` with the real model loaded — **authoritative wherever the three disagree**,
because it is the only one measuring the frontend that ships). `classes.tsv` holds the definition and
the section citation for each. **Every class has at least one item; there are no gaps.**

Regenerate this table with `bin/coverage.sh`, which reads the class list from `classes.tsv` rather
than from the items, so a class nobody covers still gets a row.

Three things to read out of it.

**20 classes have zero real items** — every one would have been missed by a real-messages-only corpus.
It was 24 before `r13` and `r14` landed; see [Provenance](#provenance) for why the remaining 20 still
mean something.

**The classes with the *most* real items are a frequency signal the synthetic half cannot give:**
`SPLIT-NEWLINE` 13, `MD-BACKTICK` 11, `CHUNK-510-PUNCT` 10, `PATH-SLASH` 8, then `MD-ASTERISK`,
`PATH-EXT` and `NUM-UNIT` at 6 each. Those are what real rewrites are actually full of and should be
weighted accordingly in #8. Note
in particular that **backticks survive the rewrite** — the model was asked for plain English and kept
them anyway — so the ear test on backtick prosody is not a corner case.

**No real item would crash, but the margin is thinner than it looks.** Real `max_run` values top out
at **342** — `r13`, added 2026-08-25, whose four-line `/plugin` block fuses into the longest run any
real rewrite has produced (the previous high was `r10`'s 251). Against a ~500-character danger point
all 14 are still safe, and 10 of them are long enough to need batching and get it — but `r13` sits
below the detector's own 400-character flag by 58 characters, which is the thinnest real margin in the
corpus and came from an ordinary four-line code block. `r09` shows the other edge — it already carries
`CHUNK-LIST-SAFE`: a real rewrite does emit bullet lines without terminal punctuation, and it is short
only by luck. The crash shape is one
longer bullet list away, which is exactly why `s37` had to be added rather than assumed absent.

| class | real | synthetic | items |
| --- | --- | --- | --- |
| `MD-ASTERISK` | 6 | 1 | r05, r06, r09, r10, r11, r12, s01 |
| `MD-HASH` | 0 | 1 | s02 |
| `MD-UNDERSCORE` | 3 | 4 | r11, r12, r14, s01, s15, s31, s39 |
| `MD-BACKTICK` | 11 | 4 | r01, r04, r05, r06, r07, r08, r10, r11, r12, r13, r14, s03, s07, s39, s40 |
| `MD-FENCE` | 3 | 3 | r07, r13, r14, s07, s39, s40 |
| `MD-FENCE-MULTI` | 2 | 2 | r13, r14, s39, s40 |
| `MD-BULLET` | 3 | 3 | r09, r10, r13, s04, s37, s38 |
| `MD-ORDERED` | 2 | 1 | r05, r09, s05 |
| `MD-BLOCKQUOTE` | 2 | 1 | r10, r14, s06 |
| `MD-PIPE` | 1 | 1 | r11, s06 |
| `ID-SCREAM` | 3 | 3 | r11, r12, r14, s15, s16, s31 |
| `ID-SNAKE` | 2 | 6 | r04, r14, s03, s14, s16, s17, s39, s40 |
| `ID-CAMEL` | 4 | 1 | r04, r09, r10, r13, s17 |
| `ID-KEBAB` | 0 | 1 | s17 |
| `ID-ACRONYM` | 4 | 2 | r08, r10, r11, r13, s18, s25 |
| `ID-VOWELLESS` | 3 | 5 | r09, r11, r12, s03, s08, s09, s14, s19 |
| `ID-ASSIGN` | 2 | 1 | r04, r14, s16 |
| `ID-SHA` | 1 | 1 | r13, s20 |
| `PATH-EXT` | 6 | 7 | r03, r06, r10, r11, r12, r13, s03, s08, s10, s11, s13, s14, s26 |
| `PATH-EXTBARE` | 0 | 1 | s09 |
| `PATH-SLASH` | 8 | 6 | r05, r06, r08, r09, r10, r11, r12, r13, s10, s11, s12, s13, s14, s26 |
| `PATH-ABS` | 1 | 1 | r13, s11 |
| `PATH-TILDE` | 2 | 1 | r07, r10, s12 |
| `PATH-DOTDIR` | 0 | 1 | s13 |
| `PATH-LINEREF` | 0 | 1 | s14 |
| `PATH-DBLCOLON` | 0 | 1 | s14 |
| `PATH-HYPHEN-EXT` | 2 | 2 | r06, r11, s08, s10 |
| `NUM-4DIGIT` | 2 | 1 | r11, r14, s21 |
| `NUM-THOUSANDS` | 1 | 1 | r14, s22 |
| `NUM-VERSION` | 1 | 1 | r10, s23 |
| `NUM-DECIMAL` | 0 | 1 | s24 |
| `NUM-UNIT` | 6 | 6 | r03, r07, r09, r11, r12, r14, s02, s04, s07, s22, s24, s36 |
| `NUM-PERCENT` | 2 | 1 | r09, r12, s25 |
| `NUM-CURRENCY` | 0 | 1 | s25 |
| `NUM-ORDINAL` | 0 | 1 | s25 |
| `NUM-STATUS` | 0 | 2 | s16, s25 |
| `NUM-TIME` | 0 | 1 | s29 |
| `NUM-HYPHEN` | 0 | 1 | s29 |
| `URL` | 1 | 1 | r09, s26 |
| `EMOJI` | 2 | 1 | r12, r14, s27 |
| `GLYPH` | 0 | 1 | s27 |
| `FLAG-SHORT` | 0 | 1 | s28 |
| `FLAG-LONG` | 0 | 1 | s28 |
| `SYM` | 2 | 1 | r12, r13, s29 |
| `PROSE-LIVES` | 0 | 3 | s12, s13, s30 |
| `OVERRIDE` | 0 | 1 | s31 |
| `LEN-UNDER` | 0 | 32 | s01, s02, s03, s04, s05, s07, s08, s09, s10, s11, s12, s13, s14, s15, s16, s17, s18, s19, s20, s21, s22, s23, s24, s25, s27, s28, s29, s31, s32, s38, s39, s40 |
| `LEN-OVER` | 2 | 4 | r01, r02, s06, s26, s30, s33 |
| `CHUNK-510-PUNCT` | 10 | 1 | r05, r06, r07, r08, r09, r10, r11, r12, r13, r14, s34 |
| `CHUNK-510-NOPUNCT` | 0 | 1 | s35 |
| `CHUNK-LIST-NOPUNCT` | 0 | 1 | s37 |
| `CHUNK-LIST-SAFE` | 1 | 2 | r09, s04, s38 |
| `SPLIT-NEWLINE` | 13 | 10 | r02, r03, r04, r05, r06, r07, r08, r09, r10, r11, r12, r13, r14, s02, s04, s05, s06, s07, s36, s37, s38, s39, s40 |

### What the coverage table does not tell you

- **It is a textual detector, not a phonemiser.** `bin/detect-hazards.sh` answers "does this item
  contain a token of class X". It says nothing about what any frontend does with it, and it cannot,
  because it never runs a G2P.
- **`max_run` is a character count standing in for a phoneme count, and it can under-protect.** The
  ~1.02 phonemes per character ratio is measured on ordinary prose; dense token-heavy text runs
  higher, and an all-caps identifier spelled letter by letter is far worse. So a run can cross 510
  phonemes at well under 500 characters. The detector therefore flags at **400**, the same
  conservative bound `espeak-sanitizer-rules.md` §10 rule A recommends — but only a real phonemiser
  can settle any specific item, and the `CHUNK-*` classes are candidates rather than verdicts.
- **Frontend-specific classes are marked in `classes.tsv`, not in the table.** `NUM-4DIGIT` and
  `ID-SCREAM` are misaki problems that espeak does not have, and `NUM-THOUSANDS` is the case where
  #3's recommended fix makes the chosen espeak frontend *worse*. Since #1 settled on espeak, coverage
  of those classes is about confirming the inversion holds, not about finding a bug.
- **`GLYPH` is carried defensively and is not in either research doc.** Box-drawing characters were
  never measured. The class exists because the plugin's own on-screen divider is made of them and
  sits immediately above the rewrite.
- **No claim is made that these 53 classes are exhaustive.** They are the classes the two docs name,
  plus `GLYPH` and `MD-FENCE-MULTI`, which are carried defensively.
  `kokoro-programming-text-audio.md` is explicit that its espeak column is "observations on these 48
  tokens", not a specification.

## Regenerating

```bash
# 1. Re-extract candidate real source messages from local transcripts (free).
#    Writes all.jsonl + scored.tsv; selection into source/rNN.txt was manual.
corpus/bin/extract-real-sources.sh \
  ~/.claude/projects/-Users-francis-behnen-Code-claudish-to-spoken-english /tmp/claudish-ex

# 2. Re-run the rewrites. COSTS SUBSCRIPTION QUOTA — one call per missing item.
#    Delete the spoken/rNN.txt you want redone first; existing ones are skipped.
#    As of 2026-08-25 all 14 are captured, so this is a no-op and costs nothing.
MAX_ITEMS=20 corpus/bin/capture-real-rewrites.sh

# 3. Rebuild the manifest after any item or note changes (free, no model calls).
corpus/bin/build-manifest.sh

# 4. Re-verify coverage (free). Prints a gap count to stderr.
corpus/bin/coverage.sh
```

The synthetic half has no regeneration step — the `.txt` files are the source.

`bin/detect-hazards.sh` can also be run directly on any file to see which classes it contains,
which is the quick way to check a newly added item before writing its `notes.tsv` row.

## Not in here

- **Audio.** Nothing was synthesised, and the repo has no LFS; the wavs from #10 are ~2.5–2.9 MB
  each and live unversioned in `~/.local/share/kokoro/`.
- **A sanitizer, or any sanitized variant of these items.** The corpus is the input a sanitizer will
  be judged on. Deciding the rules is #8.
- **Voice or prosody metadata.** Everything in #10 was `af_heart`; voice selection is #9.
- **Expected output.** No item carries a "correct" pronunciation, because nobody has listened yet and
  writing one down from a phoneme string would be inventing the answer the listening tickets exist to
  find.
