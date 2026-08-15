# Speech corpus: real rewrites plus a synthetic hazard set

The text the listening tickets judge against. Built for
[#7](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/7), part of the
[Kokoro speech map (#1)](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/1).
Assembled 2026-08-15.

**Nothing here is a claim about how anything sounds.** No audio was synthesised and nothing was
listened to while building this. The hazard classes are taken from the two measured research docs;
this directory only assembles text that contains them.

**48 items: 12 real, 36 synthetic.** Each half covers the other's blind spot, which is measurable
rather than rhetorical — **22 of the 50 hazard classes appear in no real item at all** (see
[Coverage](#coverage)). A dozen real messages really would have missed them.

---

## Layout

```
corpus/
  README.md        this file
  manifest.tsv     one row per item: id, kind, measurements, hazard classes, origin, note
  classes.tsv      the 50 hazard classes and what each one names, with doc citations
  notes.tsv        hand-maintained per-item origin and intent (input to manifest.tsv)
  capture-log.tsv  one row per subscription rewrite call actually spent
  spoken/          THE CORPUS: 48 plain-text files, the text a speech path would say
    r01.txt .. r12.txt   real  — the plain-English rewrite of a real assistant message
    s01.txt .. s36.txt   synthetic — hand-authored, one or a few hazard classes each
  source/          the real assistant messages the rNN rewrites were produced from
    r01.txt .. r12.txt
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

12 genuine assistant messages from real Claude Code sessions in this repo, rewritten by the real
plugin path.

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
| Calls spent | **12** — one per item, no retries |
| Failures | none: `rc=0`, `ratelimited=0`, `truncated=0` on all 12 |
| Wall time | 6–13s per item, 116s total |

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
to the system prompt as context. **These 12 rewrites were produced without it.** Selecting user
prompts out of a transcript is blocked by this machine's permission classifier, and that was not
worked around. The no-context path is one `rewrite.sh` supports explicitly — *"Missing/unreadable
transcript -> no context, still rewrites"* (`rewrite.sh:20`) — so these are valid rewrites, but they
are the no-context variant. Anyone regenerating the corpus with transcript access should expect
slightly more on-topic output and should re-record that fact here.

### Provenance

Full origin per item is in `manifest.tsv` (`origin` column): the session id, the message uuid, and
the timestamp. All 12 come from two prior working sessions on this repo
(`d51e4ee0…` and `62d419ff…`, 2026-08-14 and 2026-08-15) — deliberately not from the session that
built this corpus. They were picked for a realistic spread of length (prose_len 204 → 3309 on the
source side) and for resembling what the plugin actually rewrites, **not** for hazard coverage; that
is the synthetic half's job, and keeping the selection independent of it is what makes the coverage
table's 22 empty real-item classes meaningful.

## The synthetic half

36 hand-authored items, `s01`–`s36`, each targeting one or a few named hazard classes so that every
class is present at least once regardless of what the real messages happened to contain. Per-item
intent is the `note` column of `manifest.tsv` (maintained in `notes.tsv`).

These are **authored source data, not generated output**. There is no script to regenerate them; edit
the `.txt` files and re-run `bin/build-manifest.sh`.

Grouped roughly: `s01`–`s07` markdown syntax, `s08`–`s14` paths and code locations, `s15`–`s20`
identifiers, `s21`–`s25` numbers, `s26`–`s29` URLs, emoji, glyphs, flags and symbols, `s30` a
prose-only control, `s31` the inline phoneme override, `s32`–`s33` the 200-character gate, and
`s34`–`s36` the three chunking cases.

Several items are deliberately **controls** — classes both research docs found already correct
(`s09` bare extensions, `s16` the `NAME=0` form, `s25` percentages and currency, the `FLAG-LONG` half
of `s28`, `s30` plain prose). A corpus that only contains known-bad tokens can confirm a sanitizer but
never refute one.

`s34`, `s35` and `s36` are the chunking set, and the distinction between them is load-bearing:
`KPipeline` splits on `\n+` **before** anything else, so only a **single long line** can reach the
510-phoneme chunker at all. `s34` is 1313 bytes on one punctuated line (seams should fall at sentence
boundaries), `s35` is 1281 bytes on one line with no punctuation whatsoever (seams fall on arbitrary
word boundaries), and `s36` spreads comparable content over 7 short lines so the newline split
pre-empts the chunker entirely. The ~1 phoneme per character ratio these lengths rely on is from
`kokoro-text-handling.md` §6, where a 1296-character paragraph produced 3 chunks of 431 phonemes.

## Coverage

50 hazard classes, taken from
[`docs/research/kokoro-text-handling.md`](../docs/research/kokoro-text-handling.md) (#3, misaki, from
source plus a real G2P run) and
[`docs/research/kokoro-programming-text-audio.md`](../docs/research/kokoro-programming-text-audio.md)
(#10, both frontends on the installed ONNX path). `classes.tsv` holds the definition and the section
citation for each. **Every class has at least one item; there are no gaps.**

Regenerate this table with `bin/coverage.sh`, which reads the class list from `classes.tsv` rather
than from the items, so a class nobody covers still gets a row.

Two things to read out of it. **22 classes have zero real items** — every one of those would have
been missed by a real-messages-only corpus. And the classes with the *most* real items
(`MD-BACKTICK` 9, `PATH-SLASH` 7, `MD-ASTERISK` 6, `PATH-EXT` and `NUM-UNIT` 5 each, plus
`SPLIT-NEWLINE` in 11 of 12) are a frequency signal the synthetic half cannot give: those are what
real rewrites are actually full of, and they should be weighted accordingly when the sanitizer is
specified in #8. Note in particular that **backticks survive the rewrite** — the model was asked for
plain English and kept them anyway — so the ear test on backtick prosody
(`kokoro-text-handling.md` "what needs an ear test" item 1) is not a corner case.

| class | real | synthetic | items |
| --- | --- | --- | --- |
| `MD-ASTERISK` | 6 | 1 | r05, r06, r09, r10, r11, r12, s01 |
| `MD-HASH` | 0 | 1 | s02 |
| `MD-UNDERSCORE` | 2 | 3 | r11, r12, s01, s15, s31 |
| `MD-BACKTICK` | 9 | 2 | r01, r04, r05, r06, r07, r08, r10, r11, r12, s03, s07 |
| `MD-FENCE` | 1 | 1 | r07, s07 |
| `MD-BULLET` | 2 | 1 | r09, r10, s04 |
| `MD-ORDERED` | 2 | 1 | r05, r09, s05 |
| `MD-BLOCKQUOTE` | 1 | 1 | r10, s06 |
| `MD-PIPE` | 1 | 1 | r11, s06 |
| `ID-SCREAM` | 2 | 3 | r11, r12, s15, s16, s31 |
| `ID-SNAKE` | 1 | 4 | r04, s03, s14, s16, s17 |
| `ID-CAMEL` | 3 | 1 | r04, r09, r10, s17 |
| `ID-KEBAB` | 0 | 1 | s17 |
| `ID-ACRONYM` | 3 | 2 | r08, r10, r11, s18, s25 |
| `ID-VOWELLESS` | 3 | 5 | r09, r11, r12, s03, s08, s09, s14, s19 |
| `ID-ASSIGN` | 1 | 1 | r04, s16 |
| `ID-SHA` | 0 | 1 | s20 |
| `PATH-EXT` | 5 | 7 | r03, r06, r10, r11, r12, s03, s08, s10, s11, s13, s14, s26 |
| `PATH-EXTBARE` | 0 | 1 | s09 |
| `PATH-SLASH` | 7 | 6 | r05, r06, r08, r09, r10, r11, r12, s10, s11, s12, s13, s14, s26 |
| `PATH-ABS` | 0 | 1 | s11 |
| `PATH-TILDE` | 2 | 1 | r07, r10, s12 |
| `PATH-DOTDIR` | 0 | 1 | s13 |
| `PATH-LINEREF` | 0 | 1 | s14 |
| `PATH-DBLCOLON` | 0 | 1 | s14 |
| `PATH-HYPHEN-EXT` | 2 | 2 | r06, r11, s08, s10 |
| `NUM-4DIGIT` | 1 | 1 | r11, s21 |
| `NUM-THOUSANDS` | 0 | 1 | s22 |
| `NUM-VERSION` | 1 | 1 | r10, s23 |
| `NUM-DECIMAL` | 0 | 1 | s24 |
| `NUM-UNIT` | 5 | 6 | r03, r07, r09, r11, r12, s02, s04, s07, s22, s24, s36 |
| `NUM-PERCENT` | 2 | 1 | r09, r12, s25 |
| `NUM-CURRENCY` | 0 | 1 | s25 |
| `NUM-ORDINAL` | 0 | 1 | s25 |
| `NUM-STATUS` | 0 | 2 | s16, s25 |
| `NUM-TIME` | 0 | 1 | s29 |
| `NUM-HYPHEN` | 0 | 1 | s29 |
| `URL` | 1 | 1 | r09, s26 |
| `EMOJI` | 1 | 1 | r12, s27 |
| `GLYPH` | 0 | 1 | s27 |
| `FLAG-SHORT` | 0 | 1 | s28 |
| `FLAG-LONG` | 0 | 1 | s28 |
| `SYM` | 1 | 1 | r12, s29 |
| `PROSE-LIVES` | 0 | 3 | s12, s13, s30 |
| `OVERRIDE` | 0 | 1 | s31 |
| `LEN-UNDER` | 0 | 29 | s01, s02, s03, s04, s05, s07, s08, s09, s10, s11, s12, s13, s14, s15, s16, s17, s18, s19, s20, s21, s22, s23, s24, s25, s27, s28, s29, s31, s32 |
| `LEN-OVER` | 2 | 4 | r01, r02, s06, s26, s30, s33 |
| `CHUNK-510-PUNCT` | 2 | 1 | r11, r12, s34 |
| `CHUNK-510-NOPUNCT` | 0 | 1 | s35 |
| `SPLIT-NEWLINE` | 11 | 6 | r02, r03, r04, r05, r06, r07, r08, r09, r10, r11, r12, s02, s04, s05, s06, s07, s36 |

### What the coverage table does not tell you

- **It is a textual detector, not a phonemiser.** `bin/detect-hazards.sh` answers "does this item
  contain a token of class X". It says nothing about what any frontend does with it, and it cannot,
  because it never runs a G2P.
- **Frontend-specific classes are marked in `classes.tsv`, not in the table.** `NUM-4DIGIT` and
  `ID-SCREAM` are misaki problems that espeak does not have, and `NUM-THOUSANDS` is the case where
  #3's recommended fix makes the chosen espeak frontend *worse*. Since #1 settled on espeak, coverage
  of those classes is about confirming the inversion holds, not about finding a bug.
- **`GLYPH` is carried defensively and is not in either research doc.** Box-drawing characters were
  never measured. The class exists because the plugin's own on-screen divider is made of them and
  sits immediately above the rewrite.
- **No claim is made that these 50 classes are exhaustive.** They are the classes the two docs name.
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
