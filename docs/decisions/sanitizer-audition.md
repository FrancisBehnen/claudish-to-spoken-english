# Sanitizer audition: the listening script for #8

The audio [#8](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/8) is decided from.
Built 2026-08-16 against the corpus from
[#7](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/7) and the harness from
[#6](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/6). **Extended 2026-08-17**:
axis 7 had no multi-line code block to audition, so corpus items `s39` and `s40` were authored and ten
wavs added — 88 in all. **Addendum 2026-08-25**: those two were authored on an unchecked assumption,
which has now been checked — the multi-line block is a real shape (258 real assistant messages carry
one) but a smaller one than was auditioned (median 4 body lines, not 12). No wav changed and no
decision moved; see [Axis 7](#axis-7--how-a-skipped-code-block-is-announced).

**This document decides nothing, and it contains no claim about how anything sounds.** Every "what it
does" below is a text diff, a phoneme count or a duration; every "what to listen for" is a question,
put to whoever has the ear. Nothing here was played back. #8 stays open.

**Decision 1 of the ticket — sanitizer versus a parallel LLM call — is already settled and is not
re-opened here.** [#4](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/4) measured
the concurrency gates and failed all three; the map records the parallel-LLM option as dead and the
deterministic sanitizer as the path. What is left is decision 2: **how far the sanitizer goes.**

---

## How to listen

Every wav is in one directory, one file per (corpus item × variant):

```
~/.local/share/kokoro/bench/audition-8/<item>.<variant>.af_heart.wav
```

so a pair is `afplay` twice with one word changed:

```bash
cd ~/.local/share/kokoro/bench/audition-8
afplay r01.base.af_heart.wav        # the reference
afplay r01.tick-pause.af_heart.wav  # one axis moved
```

Regenerate any row — the wavs are not committed (~2.5 MB each, no LFS here):

```bash
bench/bench --id r01 -s none,base,tick-strip,tick-pause          # plays each in turn
bench/bench --id r01 -s base,tick-pause --show-text --play none  # prints the sanitized text
bench/bench --list-sanitizers                                     # all variants + rule order
```

Voice is `af_heart` throughout, which is the harness default and **unauditioned** — that is
[#9](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/9)'s question, not this one.

### The three things every pair contains

- **`none`** — the control: the text handed to Kokoro untouched. A corpus that only ever runs through
  a sanitizer can confirm one but never refute it, so `none` is present in every axis below.
- **`base`** — the reference: rule-for-rule the `candidate` pipeline from
  [`espeak-sanitizer-rules.md`](../research/espeak-sanitizer-rules.md) §"Candidate rule list", with
  one named default per open axis.
- **the variant** — `base` with **exactly one** axis moved. That is what makes each pair a test of one
  thing.

`base`'s defaults, which are the thing under examination:

| axis | `base` does | rules |
| --- | --- | --- |
| markdown | strips `*` and `#` heading markers | C, D |
| URLs | replaces with "a link" | I |
| `SCREAMING_SNAKE_CASE` | lowercases `_`-joined identifiers | J |
| paths | nothing at all — espeak says every "slash" | — |
| code blocks | reads them out; the fence itself is silent | — |
| backticks | leaves them in place (espeak emits nothing for them) | — |
| line breaks | replaces with `. ` | B, A |

Everything else in `base` is uncontested and constant across every row: emoji stripped (H), thousands
separators stripped (G), currency reordered (K), version dots spaced (E), decimal dots spoken (F), and
a guaranteed chunk boundary every 400 characters (A). Rule L (respelling `lives`) is **not** in any
variant — its trigger condition is still unestablished, and it still mis-fires on "the lives of
others".

### Order

The axes are in **real-corpus frequency order**, so the most consequential is heard first. The counts
are the coverage table in [`corpus/README.md`](../../corpus/README.md) **as it stood when this audition
was built**: how many of the **12 real rewrites** then in the corpus carried the hazard. The corpus is 14
real since 2026-08-25 and the counts have moved; the order has not. See the
[axis 7 addendum](#axis-7--how-a-skipped-code-block-is-announced).

| # | axis | real items | minutes |
| --- | --- | --- | --- |
| 1 | backtick prosody | `MD-BACKTICK` **9 / 12** | ~4 |
| 2 | line-break replacement, and the crash | `CHUNK-510-PUNCT` 8, `SPLIT-NEWLINE` 11 | ~5 |
| 3 | paths | `PATH-SLASH` 7, `PATH-EXT` 5 | ~6 |
| 4 | markdown: swallowed or stripped | `MD-ASTERISK` 6 | ~4 |
| 5 | `SCREAMING_SNAKE_CASE` | `ID-SCREAM` 2 | ~4 |
| 6 | URLs | `URL` 1 | ~3 |
| 7 | how a skipped code block is announced | `MD-FENCE` 1, `MD-FENCE-MULTI` **0** | ~8 |

If there is time for one axis only, it is axis 1. If there is time for two, add axis 2 — it is the one
that can crash `create()`.

---

## Axis 1 — backtick prosody

**`MD-BACKTICK` is in 9 of the 12 real rewrites: the single most frequent real hazard.** The model was
asked for plain English and kept the backticks anyway, so this is not a corner case.

**espeak emits nothing at all for a backtick** (measured, `espeak-sanitizer-rules.md` §8) — so
stripping them is a phoneme-level no-op and the real question is *what happens to the words around
them*. Three treatments:

| variant | what the transformation does |
| --- | --- |
| `none` | control |
| `base` | leaves the backtick characters in the text |
| `tick-strip` | removes the backtick characters (expected to be phoneme-identical to `base`) |
| `tick-pause` | sets each span off with the chunker's own boundary character: `` `ollama list` `` → `, ollama list,` |

| item | what it carries | wavs |
| --- | --- | --- |
| `r01` | real, 268 ch, three inline spans, one of them `ollama list` | `r01.none` · `r01.base` · `r01.tick-strip` · `r01.tick-pause` |
| `r04` | real, 369 ch, spans that are identifiers: `` `chunks=2` ``, `` `prose_len=298` ``, `` `displayContent` `` | `r04.none` · `r04.base` · `r04.tick-strip` · `r04.tick-pause` |
| `s03` | synthetic, five spans in two sentences — the densest case | `s03.base` · `s03.tick-strip` · `s03.tick-pause` |

What `r01` actually becomes:

```
base        … and `ollama list` is empty. … I piped it through `tr` and `tail`.
tick-strip  … and ollama list is empty. … I piped it through tr and tail.
tick-pause  … and , ollama list, is empty. … I piped it through , tr, and , tail.
```

`tick-pause` inserts no comma directly after an opening bracket, so `r04`'s
`` (`chunks=2`, `prose_len=298`) `` becomes `(chunks=2, prose_len=298)`.

**Measured before you listen:** `base` and `tick-strip` phonemise to **byte-identical strings** on all
three items (290 / 440 / 206 phonemes), so that pair is a controlled test of nothing but this
document's own honesty. `tick-pause` adds 9 phonemes to `r01`, 3 to `r04` and 17 to `s03`.

**What to listen for**

1. `base` vs `tick-strip`: is there *any* audible difference? The phoneme strings are identical, so if
   anything differs it is a defect in this document, not in espeak.
2. `base` vs `tick-pause`: does the comma set the code span off as a quoted thing, or does it chop the
   sentence into fragments? `s03` is the stress case — five spans in two sentences means five pauses.
3. In `r04`, whether an identifier span (`prose_len=298`) wants the set-off more or less than an
   English-word span (`ollama list`) in `r01`.
4. Whether a comma before a *short* span (`` `tr` ``, `` `dbg` ``) is worth its cost at all.

---

## Axis 2 — the line-break replacement, and the crash

`SPLIT-NEWLINE` is in **11 of 12** real rewrites and `CHUNK-510-PUNCT` in **8** — but `\n` is not in
kokoro-onnx's vocabulary and is silently deleted, so a multi-line rewrite arrives at the model as one
fused run. Rule B replaces every line break with terminal punctuation. **Which punctuation is open.**

This is also the axis where the sanitizer is not cosmetic: a fused run reaching 510 phonemes raises
`IndexError` instead of speaking.

| variant | what the transformation does |
| --- | --- |
| `none` | control — line breaks vanish, lines fuse |
| `base` | every line break becomes `. ` (rule B), plus a `.` every 400 characters (rule A) |
| `lb-comma` | the same two rules, inserting `, ` instead |

`lb-period` is registered as an explicit name for the `.` side and is byte-identical to `base`; the
wavs use `base`.

| item | what it carries | wavs |
| --- | --- | --- |
| `r09` | real, 1176 ch: bullet lines, `**bold**` headers ending in `:`, an ordered list | `r09.none` · `r09.base` · `r09.lb-comma` |
| `s37` | the realistic crash shape: a 9-line bullet list, no terminal punctuation anywhere, 644-char fused run | `s37.none` · `s37.base` · `s37.lb-comma` |
| `s38` | the same shape at 102 characters — the control that isolates shape from length | `s38.none` · `s38.base` · `s38.lb-comma` |

`s37.none` **does not exist, and that is the finding**: it raises
`IndexError: index 510 is out of bounds for axis 0 with size 510`. Both sanitized variants synthesise.
That is the crash-vs-survive signal in audible form — there is nothing to play for the control because
the control produces no audio at all.

What `s37` becomes (first two lines):

```
none       Here is everything that changed in this pass:⏎- the retry logic moved out …⏎- the timeout is now …
base       Here is everything that changed in this pass:. - the retry logic moved out …. - the timeout is now ….
lb-comma   Here is everything that changed in this pass:, - the retry logic moved out …, - the timeout is now …,
```

**Measured before you listen:** `s37` under `none` is 653 phonemes in one 653-phoneme batch and
raises; under either sanitizer it is 662 phonemes in two batches, largest **439**, 38 seconds of audio.
`s38` survives all three (108 / 112 / 112 phonemes) — that is the control that says length, not shape,
is the fault. On `r09`, `base` and `lb-comma` are the same length in phonemes (1277) and differ only
in which mark sits at each seam.

**What to listen for**

1. `s38.none` vs `s38.base`: what the deleted newline costs when the text is short enough to survive
   it. This is the pair that says whether rule B is worth anything beyond crash prevention.
2. `base` vs `lb-comma` on `r09`: does a list of bullets want full stops (each bullet a sentence) or
   commas (the whole list one sentence)? `r09`'s bullets are full sentences; `s37`'s are clauses.
3. The `:` seam. A line ending in a colon gets punctuation appended, giving `pass:.` or `pass:,` —
   espeak reaches the model with both marks. Whether that reads as a lead-in or as a stumble is
   audible and is not decidable from the phoneme string.
4. `lb-comma` ends the whole utterance on a comma. Whether that trails off unacceptably.

---

## Axis 3 — paths

`PATH-SLASH` is in **7 of 12** real rewrites, `PATH-EXT` in **5**. espeak voices every `/` as "slash"
and treats the `.` of an extension as a sentence-final mark, planting a full stop mid-sentence
(`espeak-sanitizer-rules.md` §"PATH-EXT"). The ticket's question — *spoken as-is, expanded,
basename-only, or shortened* — plus leading slashes.

| variant | what the transformation does |
| --- | --- |
| `none` | control |
| `base` | no path rule at all: the path is spoken exactly as written |
| `path-nolead` | drops a leading `~/`, `/`, `./` and a leading bare dot: `~/.local/share/kokoro/venv` → `local/share/kokoro/venv` |
| `path-basename` | last segment only: `docs/research/kokoro-deployment.md` → `kokoro-deployment.md` |
| `path-shorten` | last two segments: → `research/kokoro-deployment.md` |
| `path-expand` | separators become the word, the extension becomes spelled letters: `hooks/hooks.json` → `hooks slash hooks dot J S O N` |

| item | what it carries | wavs |
| --- | --- | --- |
| `s10` | three relative multi-segment paths, `.json` / `.md` extensions | `s10.none` · `s10.base` · `s10.path-basename` · `s10.path-shorten` · `s10.path-expand` |
| `s11` | absolute paths with a leading `/` — `/usr/bin/afplay`, `/tmp/claudish.log`, `/opt/homebrew/share` | `s11.none` · `s11.base` · `s11.path-nolead` · `s11.path-basename` · `s11.path-expand` |
| `s12` | `~/` paths, including `~/.local/share/kokoro/venv` and `~/.claude/claudish-off` | `s12.none` · `s12.base` · `s12.path-nolead` · `s12.path-basename` · `s12.path-shorten` · `s12.path-expand` |
| `r06` | real, 611 ch, a path inside backticks in ordinary prose | `r06.none` · `r06.base` · `r06.path-basename` · `r06.path-shorten` · `r06.path-expand` |

What `s12` becomes:

```
base            The virtual environment lives in ~/.local/share/kokoro/venv. …
path-nolead     The virtual environment lives in local/share/kokoro/venv. …
path-basename   The virtual environment lives in venv. …
path-shorten    The virtual environment lives in kokoro/venv. …
path-expand     The virtual environment lives in ~/.local slash share slash kokoro slash venv. …
```

**Measured before you listen:** `base` is phoneme-identical to `none` on `s10`, `s11` and `s12` —
`base` has no path rule, and these items carry nothing else it touches. Play `none` **or** `base`, not
both. What the variants cost in seconds of audio:

| item | `base` | `path-nolead` | `path-shorten` | `path-basename` | `path-expand` |
| --- | --- | --- | --- | --- | --- |
| `s10` | 14.0s | — (no leading marks) | 12.4s | 10.0s | 14.9s |
| `s11` | 12.7s | 11.3s | — | 6.8s | 12.9s |
| `s12` | 16.5s | 13.3s | 12.0s | 9.0s | 16.5s |
| `r06` | 34.7s | — | 33.5s | 31.5s | 34.8s |

`path-expand` costs the same seconds as `base` while saying different words — it trades espeak's
"slash" and its planted full stop for explicit words. On `r06`, one path in 611 characters, every
option lands within 3 seconds of every other.

**What to listen for**

1. **`s12.base` vs `s12.path-nolead` is the leading-slash question on its own.** `~/` is "tilde slash"
   and a leading `.` is another mark; whether dropping them loses information you need.
2. `path-basename` throws information away: `s12` becomes "lives in venv", `s11` becomes "logged to
   claudish.log". Is the file name enough, or does the location matter?
3. `path-shorten` is the middle: does one directory of context buy back what the basename lost?
4. `path-expand` is the *longest* option — it adds a word per separator and spells the extension. It
   removes the mid-sentence full stop that `.md` plants. Whether that is worth the length.
5. `r06` is the reality check: one path in 611 characters of prose. An axis that matters on `s10`
   (three paths in two sentences) may not matter at real density.

---

## Axis 4 — markdown: swallowed or stripped

`MD-ASTERISK` is in **6 of 12** real rewrites. espeak voices every `*` as the word "asterisk" and every
`#` as "hash" — that much is measured and not in doubt. What is open is whether stripping is the right
answer, and whether the *silent* markdown (`-` bullets, `>`, `|`, `_italic_`) is worth stripping too.

| variant | what the transformation does |
| --- | --- |
| `none` | control |
| `base` | strips `*` and line-anchored `#` markers (rules C, D) |
| `md-swallow` | `base` minus C and D: `*` and `#` reach espeak and are voiced |
| `md-strip-plus` | `base` plus the already-silent markdown: `-` bullets, `>` markers, `\|` table pipes, `_italic_` |

| item | what it carries | wavs |
| --- | --- | --- |
| `s01` | `**bold**`, `*starred*`, sentence-initial `**Done.**`, `_underscored_` | `s01.none` · `s01.base` · `s01.md-swallow` · `s01.md-strip-plus` |
| `s02` | `#`, `##`, `###` heading markers on their own lines | `s02.base` · `s02.md-swallow` |
| `s06` | a `>` blockquote and a `\|` pipe table — the silent-markdown case | `s06.base` · `s06.md-strip-plus` |
| `r09` | real, 1176 ch: six `**bold**` headers, bullets, an ordered list | `r09.base` · `r09.md-swallow` · `r09.md-strip-plus` |

`s06` is unchanged by `md-swallow` (it contains no `*` or `#`), which is why its pair is
`base` vs `md-strip-plus`.

**Measured before you listen:** on `s01`, swallowing the markdown costs **101 phonemes and 6.0
seconds** on 171 characters of text — 263 phonemes / 14.7s against 162 / 8.7s. On the real item `r09`
it is 196 phonemes and 8.9 seconds (1473 / 76.6s against 1277 / 67.7s). And `s06.base` is
**phoneme-identical** to `s06.md-strip-plus` (282 both): `>` and `|` really do reach the model as
nothing, so that pair tests whether "already silent" survives an ear.

**What to listen for**

1. `s01.base` vs `s01.md-swallow` is the whole question in 170 characters: "the asterisk asterisk bold
   asterisk asterisk change" against "the bold change".
2. `s02` does the same for `#`, where the marker count varies (`#` / `##` / `###`).
3. `s06.base` vs `s06.md-strip-plus`: the research says `>` and `|` are already silent, so this pair
   should be indistinguishable. If it is not, the research is incomplete. The table row `| --- | --- |`
   is the sharpest test.
4. `r09.base` vs `r09.md-strip-plus`: the bullets. Rule B has already turned the line break into a
   full stop, so `md-strip-plus` only removes the `-` itself — does anything change?

---

## Axis 5 — `SCREAMING_SNAKE_CASE`

`ID-SCREAM` is in **2 of 12** real rewrites (`r11`, `r12`) but is the plugin's own vocabulary —
`CLAUDISH_SPEAK`, `CLAUDISH_MIN_CHARS` and friends are what this feature will be talked about with.
The measured fact behind rule J: in a sentence, `MIN` phonemises as `ˌɛmˌaɪˈɛn` and `min` as `mˈɪn`.

Every variant here is **narrowed to `_`-joined tokens**, because the map records that widening it
regresses `SHA-256` to "shah" and `RAM` to "ram".

| variant | what the transformation does |
| --- | --- |
| `none` | control |
| `base` | lowercases the token (rule J): `CLAUDISH_MIN_CHARS` → `claudish_min_chars` |
| `scream-asis` | `base` minus J: the token reaches espeak in upper case |
| `scream-spell` | spells it: `CLAUDISH_MIN_CHARS` → `C L A U D I S H, M I N, C H A R S` |
| `scream-drop` | deletes the token from the sentence |

| item | what it carries | wavs |
| --- | --- | --- |
| `s15` | four env vars in two sentences: `CLAUDISH_MIN_CHARS`, `CLAUDISH_SPEAK_OFF_FILE`, `ANTHROPIC_API_KEY`, `MAX_RETRIES` | `s15.none` · `s15.base` · `s15.scream-asis` · `s15.scream-spell` · `s15.scream-drop` |
| `s16` | the assignment form `CLAUDISH_ENABLED=0`, plus lowercase `curl_rc=28` as a control | `s16.base` · `s16.scream-spell` · `s16.scream-drop` |
| `r11` | real, 2384 ch, env vars inside a long technical message | `r11.base` · `r11.scream-asis` · `r11.scream-spell` |

What `s15` becomes:

```
base          Raise claudish_min_chars if short replies are getting spoken. …
scream-asis   Raise CLAUDISH_MIN_CHARS if short replies are getting spoken. …
scream-spell  Raise C L A U D I S H, M I N, C H A R S if short replies are getting spoken. …
scream-drop   Raise  if short replies are getting spoken. …
```

**Measured before you listen, and it narrows the question:**

- On `s15`, `base` and `scream-asis` genuinely differ — 228 phonemes against 251, and the first
  divergence is exactly the documented one: `mˈɪn` against `ˌɛmˌaɪˈɛn`.
- On `r11`, **`base` and `scream-asis` phonemise to byte-identical strings** (2939 phonemes both).
  `r11`'s identifiers are `$CLAUDISH_OLLAMA`, `$CLAUDISH_ANTHROPIC_URL`, `$CLAUDISH_OPENAI_URL`, and
  espeak says a pronounceable segment as a word whichever case it is in. **So rule J's value is not
  "lowercase identifiers" but "lowercase the segments espeak would otherwise spell"** — `MIN`, `MAX`,
  `API`, `KEY`, `OFF`. The `r11` pair is in the set anyway, because a variant that changes nothing on
  a real message is itself a finding.
- `scream-spell` costs 170 phonemes and 7.7 seconds on `s15` (398 / 21.4s against 228 / 13.7s);
  `scream-drop` saves 91 phonemes and 5.5 seconds (137 / 8.2s).

**What to listen for**

1. `scream-asis` vs `base` is rule J's whole case — on `s15`, where it fires. It is the only pair here
   where the *text* differs by nothing but capitalisation.
2. `scream-spell` triples the length of every identifier. Is a spelled identifier usable, or is it the
   misaki failure mode the frontend choice was made to avoid — a wall of letter names?
3. **`scream-drop` produces sentences with holes**: "Raise if short replies are getting spoken", and in
   `s16`, "Set =0 to turn the whole thing off". Listen for whether a dropped identifier is recoverable
   from context or simply wrong.
4. `r11` is the density check — a handful of identifiers in 2384 characters of prose, which is what a
   real rewrite looks like. `base` and `scream-asis` are the same audio there by measurement; the pair
   worth playing is `base` against `scream-spell`, which is 141 phonemes longer.

---

## Axis 6 — URLs

`URL` is in **1 of 12** real rewrites, but it is documented as the noisiest single class in both
frontends: read out character class by character class, with `:` `?` `.` landing as pauses.

| variant | what the transformation does |
| --- | --- |
| `none` | control |
| `base` | rule I: the whole URL becomes `a link` |
| `url-full` | `base` minus I: the URL is read out |
| `url-domain` | the host only, dots spoken: `https://github.com/hexgrad/kokoro` → `github dot com` |

| item | what it carries | wavs |
| --- | --- | --- |
| `s26` | three URLs: a GitHub repo, a deep Hugging Face raw path ending in `config.json`, and `http://localhost:11434` | `s26.none` · `s26.base` · `s26.url-full` · `s26.url-domain` |
| `r09` | real: a markdown link whose target is a GitHub issue URL, inside a sentence | `r09.base` · `r09.url-full` · `r09.url-domain` |

What `s26` becomes:

```
base        The source is at a link and the model config is at a link. The local server answers on a link unless …
url-full    The source is at https://github.com/hexgrad/kokoro and the model config is at https://huggingface.co/… 
url-domain  The source is at github dot com and the model config is at huggingface dot co. The local server answers on localhost …
```

**Measured before you listen:** `s26`'s three URLs are **284 phonemes — 17 of its 24 seconds**. Read in
full it is 416 phonemes / 24.4s; as "a link" 132 / 7.4s; as domains 167 / 9.7s. On `r09`, one URL in
1176 characters costs 118 phonemes and 7.0 seconds.

**What to listen for**

1. `url-full` is the do-nothing option and the longest by far. Whether it is merely long or actually
   unfollowable.
2. `base` collapses three different URLs to the same three words. In `s26` the listener hears "a link"
   three times in two sentences — is that ambiguity acceptable, or does the domain need to survive?
3. `url-domain` keeps the host and drops the path. Does "huggingface dot co" tell you what "a link"
   did not?
4. `r09` is a URL inside a **markdown link**, and the link syntax survives every variant:
   `[Corpus: real rewrites plus a synthetic hazard set](a link)`. The label is spoken either way, so
   the question there is whether the target adds anything at all — and whether the bracket-and-paren
   scaffolding around it is audible.

---

## Axis 7 — how a skipped code block is announced

That code blocks are skipped and announced is **settled**; the wording is open. When this axis was
auditioned, `MD-FENCE` was in 1 of the 12 real rewrites and `MD-FENCE-MULTI` — a fence body of more
than one line — in **none** of them. Both counts have since moved (`3 real` and `2 real`); see the
[addendum](#addendum-2026-08-25--the-shape-is-real-and-the-magnitude-that-was-auditioned-is-the-tail)
at the end of this section.

| variant | what the transformation does |
| --- | --- |
| `none` | control — the fence characters are silent, the code is read out |
| `base` | the same: no code-block rule at all |
| `cb-long` | `Then a twelve line code block.` — the count is of non-blank body lines, so the number is per item |
| `cb-count` | `Code block, twelve lines.` |
| `cb-short` | `Code block.` |
| `cb-silent` | a bare `.` — nothing but a pause. kokoro-onnx has no pause primitive other than punctuation, so "a pause" *is* a full stop with no words |

| item | what it carries | wavs |
| --- | --- | --- |
| `r07` | real, 669 ch: a **one-line** dependency chain in a fenced block, mid-message | `r07.none` · `r07.base` · `r07.cb-long` · `r07.cb-count` · `r07.cb-short` · `r07.cb-silent` |
| `s07` | the same one-line shape in 250 characters | `s07.base` · `s07.cb-long` · `s07.cb-count` · `s07.cb-short` · `s07.cb-silent` |
| `s39` | **a 12-line block** — a shell function after a colon lead-in, 185 characters of carrier prose. Authored 2026-08-17 for this axis | `s39.base` · `s39.cb-long` · `s39.cb-count` · `s39.cb-short` · `s39.cb-silent` |
| `s40` | **the same carrier with a 3-line block** — the control that isolates the number from everything else. Authored with `s39` | `s40.base` · `s40.cb-long` · `s40.cb-count` · `s40.cb-short` · `s40.cb-silent` |

**`s39` and `s40` are the pair the count wording turns on, and they exist because it could not be heard
otherwise.** Until 2026-08-17 every fence in the corpus held a single line, so all four wordings said
"one line" and the ticket's own "twelve-line code block" example had no material behind it. The two are
held still in everything but the block: same carrier shape, same subject, same language, a colon
lead-in in both. `r07` and `s07` stay in the set because the one-line block is the case the real corpus
actually contains.

What `r07` becomes around the block:

```
base       … Ollama needs a lot of dependencies:. ```. ollama → mlx-c → mlx → python@3 point 14 → openssl@3, sqlite, xz, zstd, …. ```. It's been running …
cb-long    … Ollama needs a lot of dependencies:. Then a one line code block. It's been running …
cb-count   … Ollama needs a lot of dependencies:. Code block, one line. It's been running …
cb-short   … Ollama needs a lot of dependencies:. Code block. It's been running …
cb-silent  … Ollama needs a lot of dependencies:. . It's been running …
```

What `s39` becomes — the twelve-line case:

```
base       … over there:. ```. split_on_budget() {. local text="${1}". local budget="${2:-400}". local out="". while [ "${#text}" -gt "$budget" ]. do. local head="${text:0:budget}". out="$out$head. ". text="${text:budget}". done. printf '%s%s' "$out" "$text". }. ```. The sanitizer already does …
cb-long    … over there:. Then a twelve line code block. The sanitizer already does …
cb-count   … over there:. Code block, twelve lines. The sanitizer already does …
cb-short   … over there:. Code block. The sanitizer already does …
cb-silent  … over there:. . The sanitizer already does …
```

and `s40`, whose only job is to move the number:

```
cb-long    … already a helper:. Then a three line code block. Nothing else has to change …
cb-count   … already a helper:. Code block, three lines. Nothing else has to change …
```

**Measured before you listen:**

- **What the block costs when it is read out.** On `s39`, 414 phonemes — **22 of its 35 seconds** (652 /
  34.6s under `base`, 238 / 12.8s under `cb-silent`). On `s40`, 172 phonemes, 9 of 20 seconds (376 /
  20.3s against 204 / 11.4s). On `s07`, 179 phonemes, 10 of 21 seconds (382 / 20.9s against 203 /
  10.9s).
- **The count word is nearly free.** `cb-count` against `cb-short` is 15 phonemes on `s39` and 14 on
  `s40` — about a second either way (14.7s vs 13.6s; 13.2s vs 12.2s). The four wordings span 32
  phonemes end to end on `s39` (238 / 250 / 265 / 270), 31 on `s40` (204 / 216 / 230 / 235) and 30 on
  `s07` (203 / 215 / 227 / 233).
- **Skipping the block takes `s39` from two batches to one.** `s39.base` is 652 phonemes in two
  batches, largest 455; every skipping variant fits in a single batch of 238–270. `r07` needs two
  batches in every variant, and `r07.base` — the block read out — is at **509**, `_split_phonemes`'
  packing ceiling, which its skipping variants drop to 436–467.
- **A long block is not a crash on its own.** `s39`'s `max_run` is **215**: the twelve lines fuse into
  one 215-character run when the newlines are deleted, well under the corpus detector's 400-character
  flag. The crash shape needs `s37`'s length, which is axis 2's business, not this axis's.

**What to listen for**

1. `base` is the "don't skip it" control. On `s39` that is twelve lines of shell read aloud — braces,
   `${2:-400}`, `"${#text}"` — for 22 of 35 seconds; on `r07` it is the arrows, `python@3 point 14` and
   `openssl@3` in full. Confirm the skip is worth doing before choosing how to word it.
2. **`s39` against `s40` is the count on its own.** `Code block, twelve lines.` and `Code block, three
   lines.` sit in the same carrier and the only thing that moved is the number. Does twelve tell you
   something three does not, or is any number the same information?
3. Whether the **line count** earns its words at all — `cb-count` against `cb-short`, on both new items.
   It costs about a second.
4. `cb-long` is a full sentence with a verb-less subject ("Then a twelve line code block"); `cb-count`
   and `cb-short` are fragments. Which one survives being heard twenty times a day?
5. The lead-in is a colon in every item — `dependencies:` in `r07`, `over there:` in `s39` — so the
   sentence already promises something. Does `cb-silent` leave that promise dangling, or is the pause
   enough? `s39` is the harder case, because what was promised is twelve lines long.
6. Whether a **one**-line block wants different wording from a twelve-line one: `s07` or `r07` against
   `s39`, where `cb-long` is "Then a one line code block" against "Then a twelve line code block".

**The gap this section used to record is closed.** It previously stated that neither corpus item had a
multi-line fenced block, so every wording said "one line". `s39` and `s40` were authored for exactly
that, `MD-FENCE-MULTI` was added to `corpus/classes.tsv` so the coverage table can show the absence
next time, and the ten new wavs are in the same directory as the rest of this audition.

### Addendum 2026-08-25 — the shape is real, and the magnitude that was auditioned is the tail

`s39` and `s40` were **authored**, so the numbers this axis was heard at — twelve lines and three —
were assumptions about what production emits. Those assumptions have now been checked against the
transcripts on this machine, for free, over **assistant message text only** (not tool inputs, not
tool results, not file content echoed back):

| | |
| --- | --- |
| transcripts scanned | **886** top-level session files, 30 project directories (1,395 counting `subagents/`) |
| assistant records | **70,543** (95,887 counting subagents) |
| …carrying a text block | **14,991** |
| …whose text holds a triple-backtick fence | 420 |
| …with a fence body of **2+ non-blank lines** | **258 messages**, 291 such blocks |
| in this repo's own sessions | **9 messages**, fence bodies of 2–5 lines (a 10th held a 64-line resumed-session dump with no prose at all, which the 200-character gate would never have sent to a model) |

**The multi-line block is real** — about 1 in 58 assistant messages that say anything at all has one.
**Its size is smaller than what was auditioned:** median **4** non-blank lines, **69% at 2–5 lines**,
**19% at 12 or more** (p90 40, max 121). So `s40`'s three-line block was the representative case and
`s39`'s twelve-line block the tail one, not the other way round — and in this repo's own history
nothing genuine went past **five** lines.

**This does not disturb the decision; it explains why the decision is the safe one.** `cb-count` won
at N = 1 (`r07`, `s07`), N = 3 (`s40`) and N = 12 (`s39`) — 4–0 — while `cb-long` won only where N was
large. The real distribution is concentrated exactly where `cb-long` lost, so choosing `cb-count` for
robustness across sizes was choosing it for the sizes that actually occur.

**What is still not heard.** Two of the 258 messages are now in the corpus as `corpus/source/r13.txt`
(fence bodies of 1 and 4 lines) and `corpus/source/r14.txt` (2, 2 and 3 lines), byte-identical to the
transcript, and **both have been rewritten** — two subscription calls, so `MD-FENCE-MULTI` reads
`2 real, 2 synthetic` in the coverage table. What the rewrite did to the fences is now measured rather
than assumed, and it is mixed: `spoken/r13.txt` keeps **both** bodies byte-identically, so a real
four-line block does reach the speech path as four lines; `spoken/r14.txt` keeps only the first
two-line block and drops the other two along with the prose around them. The prompt's *"Leave fenced
code blocks unchanged"* therefore holds for a block the rewrite keeps, but the rewrite is free to drop
a passage and its fence with it.

**What has still not happened is synthesis.** No wav in this audition was made from `r13` or `r14`.
Every multi-line code-block sample here is `s39` or `s40` — authored text — so axis 7 was still settled
by ear at an authored magnitude, and the real magnitudes now sitting in `corpus/spoken/` (four lines
and two) have never been heard. Closing that needs a synthesis run, not a subscription call.

---

## What this audition cannot settle

- **Anything about how any of it sounds.** Nothing here was played back while it was built.
- **Whether the corpus's *other* shapes are the ones that matter.** The multi-line code block was
  missing until 2026-08-17 and axis 7 was unjudgeable because of it; nothing rules out a second
  omission of the same kind. `corpus/classes.tsv` is the only place that can surface one, and it is
  hand-maintained.
- **Rule L, the `lives` respelling.** It stays gated behind `--respell`, its trigger condition is still
  unestablished, and it still mis-fires on "the lives of others". No variant includes it, so no wav
  here is affected by it — but the defect is in the audio: `s12`, in the path axis, carries
  `PROSE-LIVES` and every one of its six wavs speaks it with espeak's reading of the verb.
- **Voice, speed and pipelining.** `af_heart` at 1.0 throughout; #9's questions.
- **Timing.** Other work was running on this machine while these wavs were made — the harness's `rtf`
  column drifted to 0.32–0.35 against the ~0.23 it reports on a quiet machine — so no latency figure
  is published here. Every duration in the appendix is a **length of audio**, which the contention does
  not affect. #6's committed run is the authority on latency and nothing here amends it.
- **Combinations.** Every variant moves exactly one axis. If two choices interact — a comma boundary
  under `lb-comma` plus comma-set-off backticks under `tick-pause`, for instance — that pair is not in
  this set.

## One behaviour change to the shared `candidate` pipeline

Rule I matched `https?://\S+`, and `\S+` runs to the next whitespace — so a URL that ended a sentence
took the full stop with it, deleting a chunk boundary. `s26` under `candidate` lost a sentence
boundary that way. The rule now hands any trailing `.,;:!?)"'` back to the text. This is a change to
the `candidate` sanitizer #6 measured; it affects only items whose URL ends a sentence (`s26`, `r09`).
The rule's own worked example in the research doc keeps its full stop, so this is the rule doing what
it was written to do.

## Appendix: what was measured

One row per wav. `phon` phonemes, `bat` batches, `maxb` largest batch (510 raises), `audio_s` the
length of the audio. No timing column: see above.

| axis | item | variant | wav | chars | phon | bat | maxb | audio_s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 backticks | `r01` | `none` | `r01.none.af_heart.wav` | 268 | 290 | 1 | 290 | 16.5 |
| 1 backticks | `r01` | `base` | `r01.base.af_heart.wav` | 268 | 290 | 1 | 290 | 16.5 |
| 1 backticks | `r01` | `tick-strip` | `r01.tick-strip.af_heart.wav` | 262 | 290 | 1 | 290 | 16.5 |
| 1 backticks | `r01` | `tick-pause` | `r01.tick-pause.af_heart.wav` | 270 | 299 | 1 | 296 | 17.1 |
| 1 backticks | `r04` | `none` | `r04.none.af_heart.wav` | 369 | 440 | 1 | 440 | 24.2 |
| 1 backticks | `r04` | `base` | `r04.base.af_heart.wav` | 368 | 440 | 1 | 440 | 24.2 |
| 1 backticks | `r04` | `tick-strip` | `r04.tick-strip.af_heart.wav` | 362 | 440 | 1 | 440 | 24.2 |
| 1 backticks | `r04` | `tick-pause` | `r04.tick-pause.af_heart.wav` | 365 | 443 | 1 | 442 | 24.1 |
| 1 backticks | `s03` | `base` | `s03.base.af_heart.wav` | 184 | 206 | 1 | 207 | 12.3 |
| 1 backticks | `s03` | `tick-strip` | `s03.tick-strip.af_heart.wav` | 174 | 206 | 1 | 207 | 12.3 |
| 1 backticks | `s03` | `tick-pause` | `s03.tick-pause.af_heart.wav` | 188 | 223 | 1 | 219 | 12.7 |
| 2 line breaks | `r09` | `none` | `r09.none.af_heart.wav` | 1176 | 1580 | 4 | 499 | 85.0 |
| 2 line breaks | `r09` | `base` | `r09.base.af_heart.wav` | 1099 | 1277 | 3 | 491 | 67.7 |
| 2 line breaks | `r09` | `lb-comma` | `r09.lb-comma.af_heart.wav` | 1099 | 1277 | 3 | 491 | 67.3 |
| 2 line breaks | `s37` | `none` | **none — IndexError** | 653 | 653 | 2 | **653** | — |
| 2 line breaks | `s37` | `base` | `s37.base.af_heart.wav` | 661 | 662 | 2 | 439 | 38.3 |
| 2 line breaks | `s37` | `lb-comma` | `s37.lb-comma.af_heart.wav` | 661 | 662 | 2 | 439 | 37.9 |
| 2 line breaks | `s38` | `none` | `s38.none.af_heart.wav` | 106 | 108 | 1 | 108 | 6.1 |
| 2 line breaks | `s38` | `base` | `s38.base.af_heart.wav` | 109 | 112 | 1 | 112 | 6.7 |
| 2 line breaks | `s38` | `lb-comma` | `s38.lb-comma.af_heart.wav` | 109 | 112 | 1 | 112 | 6.4 |
| 3 paths | `s10` | `none` | `s10.none.af_heart.wav` | 172 | 225 | 1 | 228 | 14.0 |
| 3 paths | `s10` | `base` | `s10.base.af_heart.wav` | 171 | 225 | 1 | 228 | 14.0 |
| 3 paths | `s10` | `path-basename` | `s10.path-basename.af_heart.wav` | 139 | 156 | 1 | 159 | 10.0 |
| 3 paths | `s10` | `path-shorten` | `s10.path-shorten.af_heart.wav` | 161 | 199 | 1 | 202 | 12.4 |
| 3 paths | `s10` | `path-expand` | `s10.path-expand.af_heart.wav` | 218 | 252 | 1 | 252 | 14.9 |
| 3 paths | `s11` | `none` | `s11.none.af_heart.wav` | 144 | 199 | 1 | 200 | 12.7 |
| 3 paths | `s11` | `base` | `s11.base.af_heart.wav` | 143 | 199 | 1 | 200 | 12.7 |
| 3 paths | `s11` | `path-nolead` | `s11.path-nolead.af_heart.wav` | 140 | 182 | 1 | 183 | 11.3 |
| 3 paths | `s11` | `path-basename` | `s11.path-basename.af_heart.wav` | 115 | 113 | 1 | 114 | 6.8 |
| 3 paths | `s11` | `path-expand` | `s11.path-expand.af_heart.wav` | 179 | 214 | 1 | 214 | 12.9 |
| 3 paths | `s12` | `none` | `s12.none.af_heart.wav` | 189 | 257 | 1 | 259 | 16.5 |
| 3 paths | `s12` | `base` | `s12.base.af_heart.wav` | 188 | 257 | 1 | 259 | 16.5 |
| 3 paths | `s12` | `path-nolead` | `s12.path-nolead.af_heart.wav` | 180 | 221 | 1 | 221 | 13.3 |
| 3 paths | `s12` | `path-basename` | `s12.path-basename.af_heart.wav` | 149 | 155 | 1 | 155 | 9.0 |
| 3 paths | `s12` | `path-shorten` | `s12.path-shorten.af_heart.wav` | 169 | 197 | 1 | 197 | 12.0 |
| 3 paths | `s12` | `path-expand` | `s12.path-expand.af_heart.wav` | 218 | 257 | 1 | 259 | 16.5 |
| 3 paths | `r06` | `none` | `r06.none.af_heart.wav` | 611 | 654 | 2 | 504 | 35.0 |
| 3 paths | `r06` | `base` | `r06.base.af_heart.wav` | 608 | 645 | 2 | 495 | 34.7 |
| 3 paths | `r06` | `path-basename` | `r06.path-basename.af_heart.wav` | 596 | 616 | 2 | 508 | 31.5 |
| 3 paths | `r06` | `path-shorten` | `r06.path-shorten.af_heart.wav` | 603 | 632 | 2 | 504 | 33.5 |
| 3 paths | `r06` | `path-expand` | `r06.path-expand.af_heart.wav` | 625 | 652 | 2 | 501 | 34.8 |
| 4 markdown | `s01` | `none` | `s01.none.af_heart.wav` | 171 | 263 | 1 | 264 | 14.7 |
| 4 markdown | `s01` | `base` | `s01.base.af_heart.wav` | 160 | 162 | 1 | 162 | 8.7 |
| 4 markdown | `s01` | `md-swallow` | `s01.md-swallow.af_heart.wav` | 170 | 263 | 1 | 264 | 14.7 |
| 4 markdown | `s01` | `md-strip-plus` | `s01.md-strip-plus.af_heart.wav` | 158 | 162 | 1 | 162 | 8.7 |
| 4 markdown | `s02` | `base` | `s02.base.af_heart.wav` | 202 | 231 | 1 | 231 | 13.3 |
| 4 markdown | `s02` | `md-swallow` | `s02.md-swallow.af_heart.wav` | 211 | 255 | 1 | 255 | 15.1 |
| 4 markdown | `s06` | `base` | `s06.base.af_heart.wav` | 267 | 282 | 1 | 281 | 16.4 |
| 4 markdown | `s06` | `md-strip-plus` | `s06.md-strip-plus.af_heart.wav` | 233 | 282 | 1 | 281 | 16.4 |
| 4 markdown | `r09` | `none` | `r09.none.af_heart.wav` | 1176 | 1580 | 4 | 499 | 85.0 |
| 4 markdown | `r09` | `base` | `r09.base.af_heart.wav` | 1099 | 1277 | 3 | 491 | 67.7 |
| 4 markdown | `r09` | `md-swallow` | `r09.md-swallow.af_heart.wav` | 1119 | 1473 | 3 | 502 | 76.6 |
| 4 markdown | `r09` | `md-strip-plus` | `r09.md-strip-plus.af_heart.wav` | 1081 | 1265 | 3 | 479 | 67.1 |
| 5 SCREAM | `s15` | `none` | `s15.none.af_heart.wav` | 203 | 251 | 1 | 251 | 15.3 |
| 5 SCREAM | `s15` | `base` | `s15.base.af_heart.wav` | 202 | 228 | 1 | 228 | 13.7 |
| 5 SCREAM | `s15` | `scream-asis` | `s15.scream-asis.af_heart.wav` | 202 | 251 | 1 | 251 | 15.3 |
| 5 SCREAM | `s15` | `scream-spell` | `s15.scream-spell.af_heart.wav` | 259 | 398 | 1 | 398 | 21.4 |
| 5 SCREAM | `s15` | `scream-drop` | `s15.scream-drop.af_heart.wav` | 129 | 137 | 1 | 137 | 8.2 |
| 5 SCREAM | `s16` | `base` | `s16.base.af_heart.wav` | 161 | 248 | 1 | 248 | 13.8 |
| 5 SCREAM | `s16` | `scream-spell` | `s16.scream-spell.af_heart.wav` | 175 | 292 | 1 | 292 | 16.2 |
| 5 SCREAM | `s16` | `scream-drop` | `s16.scream-drop.af_heart.wav` | 145 | 229 | 1 | 229 | 12.5 |
| 5 SCREAM | `r11` | `base` | `r11.base.af_heart.wav` | 2384 | 2939 | 6 | 502 | 153.9 |
| 5 SCREAM | `r11` | `scream-asis` | `r11.scream-asis.af_heart.wav` | 2384 | 2939 | 6 | 502 | 153.9 |
| 5 SCREAM | `r11` | `scream-spell` | `r11.scream-spell.af_heart.wav` | 2441 | 3080 | 7 | 506 | 159.0 |
| 6 URLs | `s26` | `none` | `s26.none.af_heart.wav` | 229 | 416 | 1 | 419 | 24.4 |
| 6 URLs | `s26` | `base` | `s26.base.af_heart.wav` | 129 | 132 | 1 | 132 | 7.4 |
| 6 URLs | `s26` | `url-full` | `s26.url-full.af_heart.wav` | 228 | 416 | 1 | 419 | 24.4 |
| 6 URLs | `s26` | `url-domain` | `s26.url-domain.af_heart.wav` | 152 | 167 | 1 | 167 | 9.7 |
| 6 URLs | `r09` | `none` | `r09.none.af_heart.wav` | 1176 | 1580 | 4 | 499 | 85.0 |
| 6 URLs | `r09` | `base` | `r09.base.af_heart.wav` | 1099 | 1277 | 3 | 491 | 67.7 |
| 6 URLs | `r09` | `url-full` | `r09.url-full.af_heart.wav` | 1161 | 1395 | 3 | 477 | 74.7 |
| 6 URLs | `r09` | `url-domain` | `r09.url-domain.af_heart.wav` | 1107 | 1289 | 3 | 503 | 68.2 |
| 7 code blocks | `r07` | `none` | `r07.none.af_heart.wav` | 669 | 872 | 2 | 501 | 46.9 |
| 7 code blocks | `r07` | `base` | `r07.base.af_heart.wav` | 682 | 891 | 2 | 509 | 47.0 |
| 7 code blocks | `r07` | `cb-long` | `r07.cb-long.af_heart.wav` | 625 | 739 | 2 | 467 | 40.3 |
| 7 code blocks | `r07` | `cb-count` | `r07.cb-count.af_heart.wav` | 619 | 733 | 2 | 461 | 40.4 |
| 7 code blocks | `r07` | `cb-short` | `r07.cb-short.af_heart.wav` | 609 | 721 | 2 | 449 | 39.8 |
| 7 code blocks | `r07` | `cb-silent` | `r07.cb-silent.af_heart.wav` | 599 | 709 | 2 | 436 | 39.2 |
| 7 code blocks | `s07` | `base` | `s07.base.af_heart.wav` | 259 | 382 | 1 | 382 | 20.9 |
| 7 code blocks | `s07` | `cb-long` | `s07.cb-long.af_heart.wav` | 205 | 233 | 1 | 233 | 13.1 |
| 7 code blocks | `s07` | `cb-count` | `s07.cb-count.af_heart.wav` | 199 | 227 | 1 | 227 | 12.6 |
| 7 code blocks | `s07` | `cb-short` | `s07.cb-short.af_heart.wav` | 189 | 215 | 1 | 215 | 11.9 |
| 7 code blocks | `s07` | `cb-silent` | `s07.cb-silent.af_heart.wav` | 179 | 203 | 1 | 202 | 10.9 |
| 7 code blocks | `s39` | `base` | `s39.base.af_heart.wav` | 471 | 652 | 2 | 455 | 34.6 |
| 7 code blocks | `s39` | `cb-long` | `s39.cb-long.af_heart.wav` | 260 | 270 | 1 | 270 | 15.0 |
| 7 code blocks | `s39` | `cb-count` | `s39.cb-count.af_heart.wav` | 255 | 265 | 1 | 265 | 14.7 |
| 7 code blocks | `s39` | `cb-short` | `s39.cb-short.af_heart.wav` | 241 | 250 | 1 | 250 | 13.6 |
| 7 code blocks | `s39` | `cb-silent` | `s39.cb-silent.af_heart.wav` | 231 | 238 | 1 | 237 | 12.8 |
| 7 code blocks | `s40` | `base` | `s40.base.af_heart.wav` | 299 | 376 | 1 | 376 | 20.3 |
| 7 code blocks | `s40` | `cb-long` | `s40.cb-long.af_heart.wav` | 223 | 235 | 1 | 235 | 13.3 |
| 7 code blocks | `s40` | `cb-count` | `s40.cb-count.af_heart.wav` | 218 | 230 | 1 | 230 | 13.2 |
| 7 code blocks | `s40` | `cb-short` | `s40.cb-short.af_heart.wav` | 205 | 216 | 1 | 216 | 12.2 |
| 7 code blocks | `s40` | `cb-silent` | `s40.cb-silent.af_heart.wav` | 195 | 204 | 1 | 203 | 11.4 |

---

## DECISION (2026-08-25)

Settled by Francis listening to all 67 pairs blind, one sitting, verdicts exported to
`~/.local/share/kokoro/bench/audition-verdicts.tsv`. **67/67 pairs judged, no gaps** (verified
against the wavs on disk in both directions). Tallies below **exclude the 12 byte-identical control
pairs**, which carry no signal.

The sanitizer is `candidate`'s rules A–K, with these seven axes fixed:

| axis | decision | margin | note |
| --- | --- | --- | --- |
| 1 backticks | **`tick-pause`** — set each `` `span` `` off with commas | 2–0, 1 tie | the win is the **commas**, not the character removal: `tick-strip` is phoneme-identical to leaving backticks in |
| 2 line breaks | **conditional: `,` at 3 bullets or fewer, `.` at 4 and up** — **amended after this audition, see below** | 1–1, 1 tie here | this audition read as a tie because **the axis was mis-posed**: every variant on it applies ONE character to every line break, so a conditional answer had to look like a coin-flip. Settled directly by ear on 2026-08-25; the three verdicts here fit the rule rather than tie (`s38`, 3 bullets → `,`; `s37`, 8 bullets → `.`; `r09`, paragraph-heavy → no difference). **No sanitizer implements a conditional boundary**, and nothing between 4 and 7 bullets has been synthesized — see [`sanitizer-audition-13.md`](sanitizer-audition-13.md) |
| 3 paths | **`path-short-nolead`** — last two segments, and no leading bare dot — **amended by #13, see below** | 3–0 here | `path-shorten` won this audition 3–0 and `path-nolead` was also undefeated (2–0), but the combination was never heard here. [#13](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/13) auditioned it as `path-short-nolead`: 4–0, undefeated, and it **replaces `path-shorten`** as the axis-3 default |
| 4 markdown | **keep rules C+D** (strip `*` and `#`) | 5–0 | letting `*`/`#` reach espeak (`md-swallow`) lost 0–3; stripping the already-silent markdown (`md-strip-plus`) is a no-op |
| 5 `SCREAMING_SNAKE_CASE` | **keep rule J** (lowercase `_`-joined tokens) | **7–0** | the most decisive axis. Spelling lost 0–3, deleting lost 0–2, leaving it uppercase lost 0–1 |
| 6 URLs | **`url-domain`** — a URL becomes its host, "github dot com" | 2–0 | beats rule I's "a link"; reading the URL in full lost 0–2 |
| 7 code blocks | **`cb-count`** — "Code block, N lines." | **4–0** | and it beat *reading the block out* on all four items, which confirms the skip-and-announce decision as well as fixing the wording |

Two results worth keeping visible:

- **Sanitizing beats not sanitizing everywhere it was tested.** The `none` control lost every
  informative pair it appeared in (axes 2, 3, 4, 5, 6 — 0–6 overall). The sanitizer path is
  confirmed by ear, not just by phoneme damage.
- **`cb-long` ("Then an N line code block.") wins only where N is large.** It took `s39`/`s40`
  (12-line, 3-line) and lost `r07`/`s07` (both one-line), where the phrasing has to say "one line".
  `cb-count` won all four, so it is chosen for robustness across block sizes, not because it won by
  more on any single item.

### Calibration — read this before trusting a narrow margin

12 of the 67 pairs were the same wav compared against itself, blinded. **11 were correctly called
"no audible difference"; 1 was not** — `r01:tick-strip` was recorded as "A is better" (preferring
`base`) on byte-identical audio. That is a normal blind-A/B error rate and it sets the resolution
limit of this session: roughly **1 call in 12 is noise**. Axes 4, 5 and 7 are decided by margins far
wider than that. **Axis 2 was inside the noise and was explicitly not settled here** — it has since
been settled off this page, and the reason it read as a tie turned out to be the shape of the axis
rather than the noise floor. See the axis-2 row above.

### Still open after this decision

- ~~**`.` versus `,` as the line-break replacement**~~ (axis 2) — **closed off this page**, by ear, as
  a **conditional** rule: `,` at 3 bullets or fewer, `.` at 4 and up. Three things go with it. The
  cutoff's position is a judgement, not a measurement — nothing between **4 and 7** bullets has ever
  been synthesized. **No registered sanitizer implements a conditional boundary**, so this is a
  capability to build before it can be heard. And it is prosody only: `_split_phonemes` splits on
  `. , ! ? ;`, so either character is a valid batch seam and both avert the 510-phoneme `IndexError`.
  Recorded in full in [`sanitizer-audition-13.md`](sanitizer-audition-13.md).
- ~~**`path-shorten` combined with `path-nolead`**~~ — **closed by #13.** Auditioned as
  `path-short-nolead`, 4–0 undefeated, and the axis-3 row above is amended to it. Read
  [`sanitizer-audition-13.md`](sanitizer-audition-13.md)'s DECISION before leaning on that margin:
  the combination is text-identical to `path-shorten` on two of the four winning pairs and to
  `path-nolead` on a third, so exactly **one** pair (`s12`) separates it from both parents.
- **Rule L** (respelling mis-POS'd words) stays gated behind `--respell`; it still mis-fires on
  "the lives of others" and was not auditioned.
- **No *real* multi-line code block has been heard** (axis 7). The shape was confirmed real on
  2026-08-25 — 258 real assistant messages carry one, median 4 body lines — and two of those messages
  are now in the corpus as `r13`/`r14`, rewrites included, so `MD-FENCE-MULTI` is no longer
  synthetic-only. What is missing is **audio**: nothing has been synthesized from them, so every
  multi-line wav in this audition is still of authored text. See the addendum in
  [Axis 7](#axis-7--how-a-skipped-code-block-is-announced).

### Listener notes left during the audition (3)

Recorded verbatim; all three are **additive refinements within the chosen directions**, none reverses
a decision above. Two are new rules that were **never auditioned** and would need their own ear check.

**That ear check is built.** The two new rules became
[#13](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/13) and are on the page as
`flag-pause` and `ext-word`, section 4 —
[`sanitizer-audition-13.md`](sanitizer-audition-13.md). One finding from building them belongs here,
because it bears on how much the first note is worth: **no real rewrite carries an un-backticked flag
or `_`-joined identifier** (0 of 12), so on real output the settled `tick-pause` is already setting
those tokens off via their backticks.

**That ear check is now done, and both rules are adopted** — `flag-pause` 4–0, `ext-word` 5–0, both
undefeated, verdicts in [`audition-verdicts-13.tsv`](audition-verdicts-13.tsv). Two results from it
change how the notes above should be read:

- **`ext-word` won for prosody, not pronunciation.** The note asked for a pronunciation fix and #13
  assumed a pronunciation table. There is none and none is needed: espeak already reads all 23
  extensions correctly, after a `.` and after the word "dot" alike. The rule wins because it deletes
  a full stop espeak was planting mid-sentence, which re-phrases the stream — so "we added dot-word
  to fix pronunciation" would be the wrong summary.
- **`flag-pause` won on synthetic fixtures only.** All four of its winning pairs are `sNN` items; the
  0-of-12 finding above means it is a measured no-op on every real rewrite, so it ships free of
  regression risk and its benefit is contingent on shapes real output has not yet produced.

The third note needs no audio and is #11's: sanitizer output is speech-only, the screen keeps the
unshortened rewrite.

| pair | note | status |
| --- | --- | --- |
| `s10:path-expand` | "`hooks.json` should become 'hooks dot json' so that 'json' is pronounced" | **→ adopted as `ext-word`, 5–0, by #13.** **new sub-rule.** `path-expand` spells `.md` as " dot M D"; the ask is that a pronounceable extension be said as a word. Not covered by `path-shorten` (the axis-3 winner), which shortens but does not touch extensions |
| `s12:path-shorten` | "if the original text is shown but B is the spoken text, I think that would be the perfect combination" | **spec confirmation, not a sanitizer change.** Sanitizer output is speech-only; the screen keeps the unshortened rewrite. Worth stating explicitly in #11 so nobody routes sanitized text to the display |
| `s15:scream-drop` | "B would be even better if it gets a comma before and after the flag name I think, like what you did with variables in `backticks`" | **→ adopted as `flag-pause`, 4–0 (all synthetic), by #13.** **new rule, unauditioned when this was written.** Generalises axis 1's winning `tick-pause` (commas around `` `spans` ``) to **flag names and bare identifiers**. The axis-1 result — that the win was the commas, not the backtick removal — is direct evidence this is worth hearing |
