# How Kokoro's G2P handles markdown, identifiers, paths, URLs and numbers

Research for [#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3), part of the
[Kokoro speech map (#1)](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/1).
Date: 2026-08-14.

## Scope and method

The question was what Kokoro's text frontend actually does with the kinds of text a plain-English
rewrite of a coding assistant's message contains. During charting it was **asserted** that markdown
"comes out as noise". That assertion turns out to be **partly right and partly wrong**, and the
detail matters for a sanitizer.

Sources, all primary:

| Source | Pin used |
| --- | --- |
| [hexgrad/kokoro](https://github.com/hexgrad/kokoro) | `dfb907a` (v0.9.4) |
| [hexgrad/misaki](https://github.com/hexgrad/misaki) | `fba1236` (v0.9.4) |
| `misaki-0.9.4-py3-none-any.whl` from PyPI | the code a `pip install` actually gets |
| [hexgrad/Kokoro-82M `config.json`](https://huggingface.co/hexgrad/Kokoro-82M/raw/main/config.json) | main |
| [espeak-ng `dictsource/en_list`](https://github.com/espeak-ng/espeak-ng/blob/master/dictsource/en_list) | main |
| [espeak-ng `docs/dictionary.md`](https://github.com/espeak-ng/espeak-ng/blob/master/docs/dictionary.md) | main |

Reading the source answered most of it. Where the source alone could not decide the answer — because
the outcome depends on how spaCy's statistical POS tagger labels a token — I **ran the real G2P**
rather than guess. The released `misaki` 0.9.4 `en.py` has no `torch`/`transformers` import
(the `FallbackNetwork` class exists only on git `main`, not in the release — see
[Version drift](#version-drift-on-main)), so the whole English G2P path runs in a plain venv with
`spacy`, `num2words`, `phonemizer-fork` and `espeakng-loader`, with no model weights and no audio.
Every "observed" line below is real output from that path, configured exactly as
`KPipeline` configures it (`kokoro/pipeline.py:123`): `en.G2P(trf=False, british=False,
fallback=EspeakFallback(british=False), unk='')`.

Audio was **not** generated. Nothing here is a claim about how it *sounds* — only about what
phoneme string the frontend produces. Prosody questions are flagged for the bench harness.

---

## The pipeline, in one pass

`KPipeline.__call__` ([`kokoro/pipeline.py:361-396`](https://github.com/hexgrad/kokoro/blob/main/kokoro/pipeline.py)):

1. **Split the input on `split_pattern`, default `r'\n+'`** (`pipeline.py:366`, and the CLI passes it
   explicitly at `kokoro/__main__.py:47`). Each segment is a separate generation with its own audio.
2. `self.g2p(graphemes)` → `misaki.en.G2P.__call__` ([`misaki/en.py:679-738`](https://github.com/hexgrad/misaki/blob/main/misaki/en.py)):
   - `G2P.preprocess` (`en.py:534-565`) — strips markdown-link syntax and turns it into per-token
     *features*. This is the override hook; see [§5](#5-hooks-lexicon-and-overrides).
   - `self.nlp(text)` — **spaCy `en_core_web_sm`, tokenizer + tagger only** (`en.py:529`). Every
     downstream decision keys off the spaCy POS tag.
   - `G2P.retokenize` (`en.py:601-643`) — splits each spaCy token into subtokens with the
     `SUBTOKEN_REGEX` (`en.py:57`) and assigns punctuation phonemes.
   - lexicon lookup → **espeak-ng fallback** for anything out of dictionary (`en.py:690-691`,
     `misaki/espeak.py:13-60`).
3. `KPipeline.en_tokenize` (`pipeline.py:205-231`) — chunks the phoneme stream at **510 phonemes**.
4. `KModel.forward` (`kokoro/model.py:121-138`) — maps phoneme chars to ids via `self.vocab`,
   **silently dropping any char not in the vocab** (`model.py:128`), then
   `assert len(input_ids)+2 <= self.context_length` (`model.py:130`).

Line numbers throughout refer to the pinned commits in the table above.

The model's `context_length` is `plbert.max_position_embeddings` = **512**
([Kokoro-82M `config.json`](https://huggingface.co/hexgrad/Kokoro-82M/raw/main/config.json)), which
is where the 510 comes from.

There is **no markdown awareness anywhere**. That part of the original framing was right.

---

## What's established

### 1. Markdown syntax

**Headline: the "markdown is noise" assertion is confirmed for `*` and `#`, refuted for `_`, `` ` ``,
`-` and `>` — and the `*` case is non-deterministic.**

| Input | Observed phonemes | Reads as |
| --- | --- | --- |
| `I made the **bold** change.` | `... ˈæstəɹɹˌɪskəstəɹɹˌɪsk bˈOld ˈæstəɹɹˌɪskəstəɹɹˌɪsk ...` | "asterisk asterisk **bold** asterisk asterisk" |
| `the *starred* one` | `ˈæstəɹɹˌɪsk stˈɑɹd ˈæstəɹɹˌɪsk` | "asterisk starred asterisk" |
| `**Done.** I fixed it.` | `dˈʌn. ˌI fˈɪkst ɪt.` | **silent** — asterisks vanish |
| `# Heading here` | `hˈæʃ hˈɛdɪŋ hˈɪɹ` | "hash Heading here" |
| `## Heading two` | `hˈæʃ hˈɛdɪŋ tˈu` | "hash Heading two" (one `#` swallowed) |
| `### Summary` | `hˈæʃhæʃ sˈʌməɹi` | "hash hash Summary" |
| `_italic_` | `ɪtˈælɪk` | clean |
| `` `rewrite.sh` `` | `“ɹᵻɹˈIt.ˌɛsˈAʧ”` | backticks → curly quotes (prosody, not words) |
| ` ```a fence``` ` | `“““ɐ fˈɛns“““` | three curly quotes each side |
| `- first bullet` | `— fˈɜɹst bˈʊlɪt` *or* ` fˈɜɹst bˈʊlɪt` | em-dash pause, or silence |
| `> quoted line` | ` kwˈOTᵻd lˈIn` | silent (`>` tagged `XX`) |
| `1. First step` | `wˈʌn. fˈɜɹst stˈɛp` | "one. First step" |
| `\|` (pipe) | `''` | silent |

The mechanism, and why `*` is non-deterministic:

- `retokenize` (`en.py:624-626`) blanks a token only when **spaCy tagged it as punctuation**:
  `tk.tag in PUNCT_TAGS` where `PUNCT_TAGS = frozenset([".",",","-LRB-","-RRB-","``",'""',"''",":","$","#",'NFP'])`
  (`en.py:70`). The phoneme it gets is `PUNCT_TAG_PHONEMES.get(tag, ''.join(c for c in tk.text if c in PUNCTS))`
  with `PUNCTS = frozenset(';:,.!?—…"“”')` (`en.py:66,71`) — so an asterisk, being outside `PUNCTS`,
  becomes the empty string **if it got a punctuation tag**.
- In `**Done.**` spaCy split the asterisks off as four separate `NFP` tokens → silent.
  In `the **bold** change` spaCy kept `**bold**` as **one token tagged `JJ`** → not a punctuation
  tag → lexicon miss → the whole string goes to espeak-ng, which has `*  ast@rIsk $max3` in its
  English symbol table ([`dictsource/en_list` line ~205](https://github.com/espeak-ng/espeak-ng/blob/master/dictsource/en_list))
  and voices it.
- Same for `#`: `#  haS $max3` in `en_list` line ~200. `$max3` = "Limit to 3 repetitions in
  pronunciation" ([`docs/dictionary.md`](https://github.com/espeak-ng/espeak-ng/blob/master/docs/dictionary.md)).
  In `## Heading`, spaCy tagged the first `#` as `$` (currency) — which `retokenize` blanks at
  `en.py:617-620` — and the second as `NN`, which reached espeak.
- `_`, `-`, `.`, `,`, `'`, `/` are in `SUBTOKEN_JUNKS = frozenset("',-._‘’/")` (`en.py:65`) and are
  set to empty phonemes at `en.py:661-663` / `en.py:717-719` when they end up as their own subtoken
  inside a word. That is why `_italic_` and `--dry-run` come out clean.
- Backticks and straight quotes get `PUNCT_TAG_PHONEMES['``'] = '“'` and `["''"] = '”'`
  (`en.py:71`). Both are in the model vocab, so they survive into the model as **prosodic** marks.

**So: asterisks and hashes are the real problem. Underscores, hyphens, backticks, pipes and
blockquote markers are already harmless.** And the asterisk outcome flips with the surrounding
sentence, because it depends on a statistical tagger — which is exactly why a sanitizer should strip
them rather than hope.

### 2. Identifiers

misaki's acronym handling is `Lexicon.get_NNP` (`en.py:159-165`): it looks up each letter's name in
the gold lexicon and joins them. It is reached from `Lexicon.lookup` (`en.py:230-234`) whenever a
word is all-caps, absent from `golds`, and tagged `NNP` — and from `get_word` for anything else
where the lowercase form also misses.

| Input | Observed | Reads as |
| --- | --- | --- |
| `CLAUDISH_MIN_CHARS` | `sˌiˌɛlˌAjˌudˌiˌIˌɛsˈAʧmˌɪnsˌiˌAʧˌAˌɑɹˈɛs` | "C-L-A-U-D-I-S-Hmin C-H-A-R-S", **run together, no pauses** |
| `CLAUDISH_SPEAK_OFF_FILE` | `sˌiˌɛlˌAjˌudˌiˌIˌɛsˈAʧspˌikˌɔffˈIl` | "C-L-A-U-D-I-S-Hspeakofffile" |
| `CLAUDISH_TTS_URL` | `sˌiˌɛlˌAjˌudˌiˌIˌɛsˈAʧtitiˌɛsjˌuˌɑɹˈɛl` | "…titi-es-U-R-L" |
| `snake_case` | `snˈAkkˌAs` | "snakecase", one compound word |
| `snake_case_with_many_parts` | `snˈAkkˌAswɪðmˈɛnipˈɑɹts` | one long compound |
| `camelCase` | `kˈæmᵊlkˌAs` | "camelcase" |
| `minChars` | `mˌɪnʧˈɑɹz` | "minchars" |
| `min_chars` | `mˌɪnʧˈɑɹz` | identical to `minChars` |
| `JSON` / `API` / `HTTP` / `TTS` | `ʤˌAˌɛsˌOˈɛn` / `ˌApˌiˈI` / `ˌAʧtˌitˌipˈi` / `tˌitˌiˈɛs` | spelled out |
| `npm` / `cd` / `jq` | `ˌɛnpˌiˈɛm` / `sˌidˈi` / `ʤˌAkjˈu` | spelled out (espeak spells vowel-less words) |
| `2c78a0f` (a SHA) | `tˈu sˈi sˈɛvənti ˈAt ˈA zˈɪɹO ˈɛf` | "two see seventy eight A zero F" |

Two separate effects:

1. **Separators disappear rather than becoming word breaks.** `subtokenize` (`en.py:57-59`) splits
   `snake_case` into `['snake','_','case']` and `camelCase` into `['camel','Case']`
   (the `\p{L}*?…\p{Ll}(?=\p{Lu})` alternative), but `G2P.resolve_tokens` (`en.py:652-655`) only
   inserts a space between subtokens when `prespace` is true, and `prespace` is
   `' ' in text or '/' in text or len({0 if c.isalpha() else (1 if is_digit(c) else 2) for c in text if c not in SUBTOKEN_JUNKS}) > 1`.
   For an all-alphabetic identifier that set has one element, so **`prespace` is false and the parts
   are concatenated with no gap**. `snake_case` and `camelCase` are therefore *indistinguishable* by
   ear from the concatenation — and from each other.
2. **Unknown all-caps segments are spelled letter by letter** via `get_NNP`. `CLAUDISH` and `CHARS`
   are not in the lexicon so they get spelled; `MIN` is, so it is spoken. The result is a mixture
   inside a single unbroken word.

`ADD_SYMBOLS`/`SYMBOLS` do **not** rescue this: they only apply to a subtoken that is exactly `.`,
`/`, `%`, `&`, `+` or `@` (`en.py:85-86`, `en.py:167-171`).

### 3. File paths and extensions

The dot's fate is **conditional on the spaCy tag and on whether espeak-ng is available**.

| Input | With espeak | Without espeak |
| --- | --- | --- |
| `rewrite.sh` (tagged `CD` or `ADD`) | `ɹᵻɹˈIt.ˌɛsˈAʧ` — "rewrite **[period]** S-H" | tag `ADD`: `ɹiɹˈItdˌɑt` "rewrite dot"; tag `CD`: `ɹiɹˈIt` — **`.sh` gone** |
| `providers.sh` | `pɹəvˈIdəɹz.ˌɛsˈAʧ` | `pɹəvˈIdəɹzdˌɑt` "providers dot" |
| `hooks/hooks.json` | `hˈʊks slˈæʃ hˈʊks.ʤˈAsˈɑn` — "hooks slash hooks[period]jason" | `hˈʊks hˈʊks` — **slash and `.json` gone** |
| `README.md` | `ɹˈidmi.ˌɛmdˈi` "readme[period] M-D" | `ˌɑɹˌiˌAdˌiˌɛmˈi` "R-E-A-D-M-E" |
| `rewrite-md.sh` | `ɹˌiɹItˌɛmdˌiˌɛsˈAʧ` "rewrite-M-D-S-H" | — |
| `~/Code/foo` | `tˈɪldəslˌæʃ kˈOd slˈæʃ fˈu` "tilde-slash Code slash foo" | — |
| `~/.claude/claudish-off` | `tˈɪldəslˌæʃ.klˈɔd slˈæʃ klˈɔdɪʃˈɔf` | — |

Established mechanics:

- misaki has an explicit `ADD_SYMBOLS = {'.':'dot', '/':'slash'}` (`en.py:85`) consumed by
  `Lexicon.get_special_case` (`en.py:167-169`) — **but only when the token's spaCy tag is `ADD`**
  (spaCy's tag for URL/email-like tokens). Observed firing: `rewrite.sh` tagged `ADD` produced
  "rewrite dot".
- That branch is usually **pre-empted by the espeak fallback**. In `G2P.__call__` (`en.py:711-722`)
  the left/right narrowing loop breaks to `should_fallback` the moment a non-junk subtoken misses
  the lexicon, and then hands the **whole original token** to espeak (`en.py:724-729`). With
  `EspeakFallback` configured — which is the kokoro default — the ADD_SYMBOLS path is rarely reached.
- espeak-ng is invoked with `preserve_punctuation=True` (`misaki/espeak.py:34-37`), so **it returns a
  literal `.` inside the phoneme string**. That `.` reaches the model as a sentence-final token, and
  it is also a chunk-boundary candidate for `waterfall_last` (`pipeline.py:184-199`). So
  `rewrite.sh` plants a full stop in the middle of a sentence.
- espeak voices `/` as "slash" (`dictsource/en_list`: `/  slaS $max3`) and `~` as "tilde"
  (`en_list`: `~  tIld@ $max3`), but leaves `.` as punctuation. That asymmetry is why
  `hooks/hooks.json` says the slash but only *pauses* at the dot.
- **Without espeak, path fragments silently vanish.** `KPipeline` constructs `en.G2P(..., unk='')`
  (`pipeline.py:123`), so an unresolved token contributes an empty string (`en.py:737`). A URL
  became `kˈɑm` — just "com" — with everything else dropped.

### 4. URLs, numbers, currency, versions

Number normalisation lives in `Lexicon.get_number` (`en.py:372-451`) and delegates to
[`num2words`](https://github.com/savoirfairelinux/num2words).

| Input | Observed | Reads as |
| --- | --- | --- |
| `0.3.0` | `zˈɪɹO θɹˈi zˈɪɹO` | "zero three zero" — **no "point"** |
| `v0.3.0` | `vˈi zˈɪɹO θɹˈi zˈɪɹO` | "v zero three zero" |
| `0.75` | `zˈɪɹO pYnt sˈɛvən fˈIv` | "zero point seven five" |
| `1.5` | `wˈʌn pYnt fˈIv` | "one point five" |
| `1,234` | `wˈʌn θˈWzᵊnd tˈu hˈʌndɹəd θˈɜɹTi fˈɔɹ` | "one thousand two hundred thirty four" |
| `1234` | `twˈɛlv θˈɜɹTi fˈɔɹ` | "twelve thirty four" — **year rule** |
| `2026` | `twˈɛnti twˈɛnti sˈɪks` | "twenty twenty six" |
| `8080` | `ˈATi ˈATi` | "eighty eighty" — **a port number read as a year** |
| `404` | `fˈɔɹ hˈʌndɹəd fˈɔɹ` | "four hundred four" |
| `100` | `wˈʌn hˈʌndɹəd` | "one hundred" |
| `$4.50` | `fˈɔɹ dˈɑləɹz ænd fˈɪfti sˈɛnts` | correct currency |
| `50%` | `fˈɪfti pəɹsˈɛnt` | correct |
| `3:45` | `θɹˈi:fˈɔɹTi fˈIv` | "three [colon] forty five" |
| `1.5s` | `wˈʌn pYnt fˈIvz` | "one point fives" (suffix pluralised, `en.py:445-450`) |
| `a & b` / `a @ b` / `a + b` | `ænd` / `æt` / `plˈʌs` | via `SYMBOLS` (`en.py:86`) |
| `https://github.com/hexgrad/kokoro` | `ˌAʧtˌitˈipˌiˈɛs:slˈæʃslæʃ ɡˈɪthʌb.kˈɑm slˈæʃ hˈɛksɡɹæd slˈæʃ kəkˈɔɹO` | "H-T-T-P-S colon slash slash github[period] com slash hexgrad slash kokoro" |
| `https://example.com/a/b?x=1&y=2` | `…bˈi?ˈɛks ˈikwᵊlz wˈʌn ænd wˈI ˈikwᵊlz tˈu` | query string read out in full, `?` and `:` land as phonemes |
| `✅` | `wˈIt hˈɛvi ʧˈɛk mˈɑɹk` | **"white heavy check mark"** — espeak reads emoji by Unicode name |

The rules worth remembering, all from `get_number`:

- **Version strings are digit-by-digit with no separator.** `word.count('.') > 1` takes the branch at
  `en.py:407-416`, which splits on `.` and — because each part starts with `0` or is not
  two digits — emits digits individually. Nothing pronounces the dots. `0.3.0` and `030` sound
  identical.
- **Any bare 4-digit number is read as a year** (`en.py:392-393`:
  `len(word) == 4 and currency not in CURRENCIES and is_digit(word)` → `num2words(..., to='year')`).
  This is a real hazard: ports, line counts, byte counts, and PR numbers in the thousands all get
  the year reading.
- A **comma** switches it back to full cardinal reading (`1,234` ≠ `1234`).
- Currency is handled properly, including cents and pluralisation (`en.py:417-428`).
- **URLs are read out in full and are the noisiest thing in the list**, and the `:`, `?` and `.`
  characters inside them land in the phoneme stream as punctuation, i.e. as pauses.

### 5. Hooks, lexicon and overrides

**Yes — three usable hooks exist. This is the highest-value finding.**

**(a) Inline phoneme / stress override via markdown-link syntax.** `G2P.preprocess`
(`en.py:534-565`) matches `LINK_REGEX = re.compile(r'\[([^\]]+)\]\(([^\)]*)\)')` (`en.py:63`),
keeps group 1 as the spoken text, and interprets group 2 as a feature applied to those tokens in
`G2P.tokenize` (`en.py:576-591`):

| Form | Meaning | Verified |
| --- | --- | --- |
| `[text](/phonemes/)` | replace phonemes outright, rating 5 | `[Kokoro](/kˈOkəɹO/) is nice.` → `kˈOkəɹO ɪz nˈIs.` |
| `[text](/ph1 ph2/)` | multi-word replacement works | `[CLAUDISH_MIN_CHARS](/klˈɔdɪʃ mˈɪn ʧˈɑɹz/)` → `klˈɔdɪʃ mˈɪn ʧˈɑɹz` |
| `[word](2)`, `[word](-1)`, `[word](0.5)` | stress override | `[really](2)` → `ɹˈiᵊli`; `[really](-1)` → `ɹˌiᵊli` |
| `[num](#flags)` | number-reading flags (`&`, `n`, `a`) consumed by `get_number` | accepted |

This is the documented usage in [misaki's own README](https://github.com/hexgrad/misaki/blob/main/README.md):
`text = '[Misaki](/misˈɑki/) is a G2P engine designed for [Kokoro](/kˈOkəɹO/) models.'`
The phoneme alphabet to write against is [`EN_PHONES.md`](https://github.com/hexgrad/misaki/blob/main/EN_PHONES.md).

Caveat: phonemes here are **not validated**. `Lexicon.__init__` asserts the bundled lexicon against
`US_VOCAB` (`en.py:150-157`) but overrides bypass that, and any char missing from the model vocab is
then **silently dropped** by `KModel.forward` (`kokoro/model.py:128`). Verified:
`[x](/kˈOkəɹOZZZ/)` → the three `Z`s are dropped with no warning.

**(b) Runtime lexicon injection.** `Lexicon.golds` / `Lexicon.silvers` are ordinary dicts
(`en.py:140-148`), so `pipeline.g2p.lexicon.golds['claudish'] = 'klˈɔdɪʃ'` works. Verified:

```
before: 'CLAUDISH is on.' -> sˌiˌɛlˌAjˌudˌiˌIˌɛsˈAʧ ɪz ˌɔn.     ("C-L-A-U-D-I-S-H")
after : 'CLAUDISH is on.' -> klˈɔdɪʃ ɪz ˌɔn.                     ("claudish")
```

One entry covers `claudish` / `Claudish` / `CLAUDISH`, because `Lexicon.lookup` lowercases all-caps
words (`en.py:232-234`) and `grow_dictionary` adds the capitalised form (`en.py:126-138`). It also
composes *inside* an identifier: after injection `CLAUDISH_MIN_CHARS` became
`klˈɔdɪʃmˌɪnsˌiˌAʧˌAˌɑɹˈɛs` — "claudish" and "min" now correct, `CHARS` still spelled, and **still
with no word gaps**. Keys containing `_` do **not** work (`snake_case` is split by `subtokenize`
before lookup). This is an undocumented internal, not a public API.

**(c) Custom `preprocess` callable.** `G2P.__call__(text, preprocess=...)` (`en.py:679-681`) accepts
any callable returning `(text, tokens, features)`, replacing `G2P.preprocess`. Verified: a
`lambda t: (t.replace('_',' '), [], {})` turns `CLAUDISH_MIN_CHARS` from
`klˈɔdɪʃmˌɪnsˌiˌAʧˌAˌɑɹˈɛs` into `klˈɔdɪʃ mˈɪn sˌiˌAʧˌAˌɑɹˈɛs` — separate words with proper gaps.
Note `KPipeline` calls `self.g2p(graphemes)` with the default (`pipeline.py:386`), so using this
through `KPipeline` means wrapping or replacing `pipeline.g2p`.

There is **no** config file, no user-lexicon path, and no supported extension point. All three of
these are library-level Python. **If speech is driven over HTTP (`CLAUDISH_TTS_URL`, e.g. a
Kokoro-FastAPI server) rather than in-process, only (a) — the inline `[text](/phonemes/)` syntax —
survives, because it travels in the text itself.** That is a genuine architectural constraint on the
design, and it makes (a) by far the most portable of the three.

### 6. Long text: chunking, truncation, sentence splitting

**Established: automatic chunking, no exception, no silent truncation on the normal path.**

- The model's hard ceiling is 512 (`plbert.max_position_embeddings` in
  [`config.json`](https://huggingface.co/hexgrad/Kokoro-82M/raw/main/config.json)), enforced by
  `assert len(input_ids)+2 <= self.context_length` in `KModel.forward` (`model.py:130`,
  with `context_length` set at `model.py:53`). Everything
  upstream targets **510 phonemes**.
- `KPipeline.en_tokenize` (`pipeline.py:205-231`) accumulates tokens and, when the running phoneme
  count would exceed 510, calls `waterfall_last` (`pipeline.py:184-199`) to back off to the last
  punctuation boundary, preferring `!.?…`, then `:;`, then `,—`, and nudging past a trailing `)`
  or `”`. Each chunk is yielded as a **separate `Result` with its own audio**.
- Observed on a 1296-char paragraph: three chunks of 431 phonemes each, every one ending at a
  sentence-final `.`.
- Observed on 1572 chars of **punctuation-free** text: it still chunks — 508 / 507 / 508 / 45 — just
  at arbitrary word boundaries, because `waterfall_last` returns `len(tokens)` when it finds no
  punctuation. Stripping all punctuation degrades chunk placement but does not break anything.
- The `len(ps) > 510` branch (`pipeline.py:390-392`) logs `"Unexpected len(ps) == ..."` and truncates
  to 510. It is an edge case reachable only when a *single* token phonemises to more than 510 chars.
  It is a warning, not an exception, and the audio for that chunk is quietly clipped.
- **Sentence splitting: no.** For English the pipeline splits only on `split_pattern` — default
  `r'\n+'` — and then chunks solely by the 510 budget. It does not emit one generation per sentence.
  (The `re.split(r'([.!?]+)', ...)` sentence-chunker at `pipeline.py:399-427` is in the
  **non**-English branch only.)

The `\n+` split has a direct consequence for us: a markdown bullet list is **already** one
generation per line, and a blank line between paragraphs already forces a boundary. That is free
first-sentence pipelining if the effort wants it.

---

## What needs an ear test

The source and the phoneme strings settle *what is produced*. These are the questions where the
phonemes are known but the listening judgement is not — all cheap to try on the bench harness.

1. **How much do stray punctuation phonemes cost?** `rewrite.sh` → `ɹᵻɹˈIt.ˌɛsˈAʧ` puts a full stop
   inside a word; `“ ”` from backticks and `:` from `3:45` are prosodic marks. Whether these read as
   a natural beat or as a stumble is not decidable from source. **This determines whether backticks
   need stripping at all.**
2. **Is a run-together compound acceptable?** `snˈAkkˌAs` ("snakecase") and
   `klˈɔdɪʃmˌɪnsˌiˌAʧˌAˌɑɹˈɛs` are legible-ish as phoneme strings, but only listening decides
   whether they need explicit word breaks. The `resolve_tokens` stress-halving logic
   (`en.py:666-677`) demotes half the stresses in a compound, which may or may not be enough.
3. **Are spelled-out acronyms good or bad here?** "J-S-O-N" and "A-P-I" are arguably *better* than
   "jason" and "appy"; "C-L-A-U-D-I-S-H" is clearly worse. There is no rule in the source that
   separates the two cases — it is whether the word is in the lexicon. A judgement call by ear,
   informed by which identifiers actually appear in rewrites.
4. **Does the `\n+`-driven chunk boundary sound like a paragraph break or a glitch?** Separate
   generations mean separate prosody contours and a hard seam at playback.
5. **Do the 510-phoneme chunk seams sound worse in the punctuation-free case** (arbitrary word
   boundary) than in the sentence-boundary case? This decides how hard a sanitizer must work to
   preserve terminal punctuation.
6. **Is the year-rule number reading actually confusing in context?** "eighty eighty" for `8080`
   looks bad on paper; in a sentence like "the server is on port eighty eighty" it may be fine.

## What I could not establish

- **spaCy tagger behaviour is not derivable from misaki's source**, and it is the pivot for markdown
  asterisks, for `#`, for whether `ADD_SYMBOLS` fires, and for whether a `-` bullet becomes an
  em-dash pause or silence. I probed it empirically and reported observations, but these are
  *observations on the sentences I tried*, not rules. A sanitizer must not be built on "spaCy will
  tag it as punctuation" — the observed flip between `**Done.**` (silent) and `the **bold** change`
  (voiced) is proof that it will not always.
- **Anything about audio.** No weights were downloaded, no waveform produced. Every prosody claim
  above is an inference from a phoneme string.
- **Whether Kokoro-FastAPI (or whatever server backs `CLAUDISH_TTS_URL`) preserves the markdown-link
  override syntax end to end.** It should, since it is plain text handled by `G2P.preprocess`, but
  that server is out of scope here and was not read.
- **The British (`lang_code='b'`) path** was not probed; `GB_VOCAB` and the `gb_*` lexicons differ
  (`en.py:89`, `en.py:145-148`) and `_ing`/`_ed` stemming branches differently.

---

## Environment findings (for the provisioning ticket)

Two things worth carrying into the install work:

- **Python 3.14 is not supported.** `misaki` declares `requires-python = ">=3.8, <3.14"` and
  `kokoro` declares `>=3.10, <3.14` (both `pyproject.toml`). This Mac's `python3` is 3.14.6, so the
  install needs an explicit 3.12/3.13 interpreter. A 3.12 venv was used here without incident.
- **The espeak-ng fallback failed to initialise out of the box, and it fails *silently*.** In a
  clean `uv` venv with `phonemizer-fork` 3.3.2 + `espeakng-loader`, `EspeakFallback(british=False)`
  raised, with espeak-ng printing
  `Error processing file '.../site-packages/phontab': No such file or directory` — the data path set
  by `EspeakWrapper.set_data_path(espeakng_loader.get_data_path())` (`misaki/espeak.py:8-10`) did
  not take effect. It was worked around by symlinking the `espeak-ng-data` contents into
  `site-packages`.

  This matters because of how kokoro handles it (`pipeline.py:116-123`): the exception is caught,
  logged as `"EspeakFallback not Enabled: OOD words will be skipped"`, and the pipeline continues
  with `fallback=None, unk=''` — i.e. **every out-of-dictionary word is dropped from the audio with
  no error**. The no-espeak columns in §3 show the damage: a full URL became "com"; `hooks/hooks.json`
  became "hooks hooks"; `providers.sh` lost `.sh`. Whatever install path the effort picks, it must
  **assert that `EspeakFallback` constructed successfully**, not trust that it did.

  (Reproduced on this machine, this venv. Not verified against the exact install method the effort
  will use — treat it as a risk to check, not as a property of every install.)

## Version drift on main

The `misaki` **git `main`** working tree adds a `FallbackNetwork` class (BART-based G2P from
`PeterReid/graphemes_to_phonemes_en_us`) and changes `G2P.__init__` to default to it:
`self.fallback = fallback if fallback else FallbackNetwork(british)`. The **released 0.9.4 wheel**
still has `self.fallback = fallback if fallback else None`. Diffing the two showed this is the *only*
difference in `en.py`, so every finding above holds for both — but a future release will change what
happens when espeak is unavailable (a neural fallback instead of silent dropping), which would
partly defuse the risk in the previous section. Worth re-checking at implementation time.

---

## What this implies for a sanitizer

Ordered by value.

**Must strip / rewrite — these are voiced as noise or read wrong:**

1. `*` and `**` — the only markdown characters actually voiced ("asterisk"), and non-deterministically
   so. Strip the markers, keep the content.
2. `#` heading markers — voiced as "hash", once per `#` up to espeak's `$max3`.
3. **URLs** — read out character-class by character-class, with `:`/`?`/`.` landing as pauses. Replace
   with something spoken, or drop.
4. **Bare 4-digit numbers** that are not years (`8080`, `1234`) — the year rule fires unconditionally.
   Inserting a comma (`1,234`) restores cardinal reading; that is a one-character fix.
5. **`SCREAMING_SNAKE_CASE` identifiers** — spelled letter by letter *and* run together. Split on `_`
   and lowercase (or title-case) the parts. The verified `preprocess` experiment shows splitting
   alone recovers word gaps.
6. **Emoji** — espeak reads them by full Unicode name ("white heavy check mark"). Strip.

**Leave alone — the concern was overstated:**

7. `_italics_`, `-` bullets, `>` blockquotes, `|` pipes, `--flags` — already silent or already a
   pause. Stripping them is harmless but buys nothing.
8. Backticks — become curly-quote *prosody*, not words. Defer to the ear test (item 1 above) before
   deciding.
9. Currency, percentages, commas-in-thousands, ordinals, `&`/`@`/`+` — all handled correctly by
   `get_number`/`SYMBOLS`. Do not touch.
10. Terminal punctuation `. ! ? : ; , —` — **actively load-bearing**: it is what `waterfall_last`
    uses to place chunk seams at sentence boundaries. A sanitizer that strips punctuation makes long
    messages chunk worse. Preserve it.

**Design consequences:**

11. **Preserve `\n`.** `KPipeline` splits on `\n+` before anything else, so newlines are the free,
    reliable way to force a generation boundary — one per bullet, one per paragraph. A sanitizer that
    flattens the message to one line throws that away.
12. **The `[text](/phonemes/)` override is the escape hatch that survives an HTTP transport.** For a
    small fixed set of terms this project says constantly — `claudish`, `Kokoro`, tool names, file
    extensions — emitting `[CLAUDISH_MIN_CHARS](/klˈɔdɪʃ mˈɪn ʧˈɑɹz/)` is strictly better than
    pre-mangling the text, because it fixes pronunciation without distorting the words. It needs a
    small hand-written phoneme table validated against `EN_PHONES.md` and the model vocab (bad
    phonemes are dropped silently).
13. **Runtime lexicon injection is the cleaner mechanism but only if speech runs in-process.** One
    dict assignment fixes a term everywhere, including inside identifiers, with no text distortion.
    If the design lands on an in-process Python worker rather than an HTTP server, prefer it. It
    cannot cross an HTTP boundary.
14. **Guard against the silent-espeak-failure mode** (see Environment findings) — otherwise a
    sanitizer's output is being judged against a frontend that is quietly deleting words.

## Reproducing

The probes are not committed — they were scratch. To rebuild: a Python 3.12 venv with
`spacy num2words addict regex numpy phonemizer-fork espeakng-loader` plus the `en_core_web_sm` 3.8.0
wheel, the `misaki-0.9.4-py3-none-any.whl` contents unpacked on `sys.path`, and

```py
from misaki import en, espeak
g2p = en.G2P(trf=False, british=False, fallback=espeak.EspeakFallback(british=False), unk='')
phonemes, tokens = g2p("your text here")
for tk in tokens:
    print(tk.tag, repr(tk.text), repr(tk.phonemes), tk._.rating)
```

`tk._.rating` identifies the source of each pronunciation: 5 = inline override, 4 = gold lexicon,
3 = silver lexicon / `get_NNP` spelling / punctuation, 2 = espeak fallback.
