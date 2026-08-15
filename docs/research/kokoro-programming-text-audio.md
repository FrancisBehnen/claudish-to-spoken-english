# Programming text through both frontends: phonemes measured, audio rendered

Material for [#9](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/9)
(voice and pipelining) and evidence for [#8](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/8)
(the sanitizer decision), extending
[#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3)'s source analysis onto the
installed ONNX path from [#5](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/5).
Measured 2026-08-15 on the venv described in
[`kokoro-onnx-provisioning.md`](kokoro-onnx-provisioning.md).

**Nothing in this document is a claim about how anything sounds.** Four wav files exist and are
playable; nobody has listened to them. Every claim here is a phoneme string, a duration, or a byte
count. The one existing perceptual data point — that `bench-espeak.wav` reads `.sh` more naturally
than `bench-misaki.wav` — is **the user's**, reported by ear, and §2 examines what the phonemes can
and cannot say about it.

---

## Why this exists

[#5](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/5) established that
`kokoro-onnx` ships its **own** G2P (espeak via `phonemizer-fork`) and that misaki's can be
substituted with `is_phonemes=True`. So the project has a real choice of frontend, and
[#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3)'s entire sanitizer analysis
was done against only one of them. The user then reported one perceptual difference on a single
token. Two batches of programming-shaped text were built to turn that into evidence.

## Method

- **32 carrier sentences** (15 paths/locations, 17 identifiers/flags/numbers) covering **48 tokens**.
  Each token sits in a sentence a rewrite would plausibly produce, not in a bare word list, so the
  measurement includes the context that drives spaCy's tagger and espeak's clause handling. Both
  batches deliberately mix cases [#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3)
  predicted would misbehave (`SCREAMING_SNAKE_CASE`, bare 4-digit numbers, URLs, `*`/`#`, emoji) with
  cases it predicted were fine — so the test can refute as well as confirm.
- **misaki phonemes** from `en.G2P(trf=False, british=False, fallback=EspeakFallback(british=False), unk="")`,
  configured exactly as `kokoro/pipeline.py:123` does. `EspeakFallback` construction is asserted, not
  assumed — [#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3) showed it fails
  silently and then deletes words.
- **espeak phonemes** reproduced from `kokoro_onnx/tokenizer.py:70-79` verbatim:
  `phonemizer.phonemize(text, "en-us", preserve_punctuation=True, with_stress=True)`, then filtered to
  `kokoro_onnx.config.DEFAULT_VOCAB` — the same filter the real synthesis path applies. So these are
  the strings the model actually receives, not an approximation of them.
- The two frontends **write the same sounds differently**: misaki's compact US alphabet uses `A I O W Y`
  for `eɪ aɪ oʊ aʊ ɔɪ`, `ʧ ʤ` for `tʃ dʒ`, `T` for the flap `ɾ`, `ᵊ` for syllabic `ə`, and no length
  marks; espeak writes `ɚ` and `ː`. Comparing raw strings therefore flags **everything** as different
  and is useless. All comparisons below normalise misaki's notation to espeak's IPA and strip stress
  and length marks first. Two further tiers separate **word-gap** differences (same phoneme sequence,
  different word boundaries — the hazard
  [#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3) flagged for identifiers)
  from **notation** residue (r-colouring and unstressed vowel quality — same words in a different
  accent transcription). What survives both is a genuinely different spoken item.

## Headline

Across 32 sentences: **3 sentences are phoneme-identical in both frontends, 21 differences are accent
notation, 5 are word-boundary placement, and 18 are substantive** — a different word, an extra word,
or an extra punctuation mark. Two of those 18 (`everything`, `for the`) are function-word syllable
reductions rather than different words, so the defensible substantive count is **16**.

They cluster, and the clustering is the finding:

| Category | Verdict |
| --- | --- |
| File extensions (`.sh` `.py` `.md` `.json` `.wav`) | **Phoneme-identical.** Zero substantive differences. |
| Paths and code locations | Near-identical. Two real differences, both about leading `/` and `~`. |
| `SCREAMING_SNAKE_CASE` / `camelCase` identifiers | **Sharply different. espeak splits into words, misaki concatenates.** |
| Numbers | **Different, and the two frontends fail on opposite inputs.** |
| Version strings | Different: espeak plants a full stop between every component. |
| Markdown `*` `#`, emoji, URLs | **Identical.** Both equally bad, exactly as [#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3) predicted. |

Neither frontend dominates. That matters for
[#8](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/8): the sanitizer cannot be
made unnecessary by picking a frontend.

---

## 1. Paths and extensions phonemise the same in both frontends

All five bare extensions are **identical after notation normalising**:

| Token | misaki | espeak |
| --- | --- | --- |
| `.sh` | `.ˌɛsˈAʧ` | `.ˌɛsˈeɪtʃ` |
| `.py` | `.pˈI` | `.pˈaɪ` |
| `.md` | `.ˌɛmdˈi` | `.ˌɛmdˈiː` |
| `.json` | `.ʤˈAsˈɑn` | `.dʒˈeɪsˈɑːn` |
| `.wav` | `.wˈæv` | `.wˈæv` |

`.wav` is byte-identical; the other four differ only in how `eɪ`, `aɪ` and vowel length are written.
The whole sentence *"It handles .sh, .py, .md, .json and .wav files."* is phoneme-identical in both
frontends — one of only three such sentences in the set.

So is `README.md`, `providers.sh:129`, `hooks/hooks.json`, `docs/agents/issue-tracker.md`,
`tests/test_rewrite.py::test_short`, `src/index.ts`, `src/main.ts`, `bench-espeak.wav`,
`bench-misaki.wav` and `Makefile`. Both frontends voice `/` as "slash" and leave `.` as a punctuation
phoneme, so a path reads as *"docs slash research slash kokoro-deployment [full stop] M D"* in both.

Two substantive path differences exist, and both concern a **leading** separator:

| Input | misaki | espeak |
| --- | --- | --- |
| `/usr/bin/afplay` (in sentence) | `ˈʌsəɹ slˈæʃ bˈɪn slˈæʃ əfplˈA` — 2 slashes | `slˈæʃ ˈʌsɚ slˈæʃ bˈɪn slˈæʃ ɐfplˈeɪ` — **3 slashes** |
| `rewrite-md.sh` (in sentence) | `ɹˌiɹItˌɛmdˌiˌɛsˈAʧ` — no stop | `ɹᵻɹˈaɪtˌɛmdˈiː.ˌɛsˈeɪtʃ` — **full stop before `.sh`** |

The `rewrite-md.sh` row is the one worth staring at: **espeak keeps a `.` inside the token and misaki
drops it.** `.` is in the model vocab and reaches the model as a sentence-final mark.

A third difference is context-dependent and was nearly mis-reported. In **isolation** misaki drops a
leading `~` and `/` entirely (spaCy tags them `NFP`/`.`, and `retokenize` blanks them —
[#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3) §1), so bare
`~/.local/share/kokoro/venv` loses its tilde while espeak says "tilde slash". **Inside a sentence
both say "tilde slash"**, and both say the leading "slash" of `/tmp/claudish.log` — but misaki still
drops the leading slash of `/usr/bin/afplay`. Same character, three different outcomes depending on
what spaCy tagged. This is
[#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3)'s
"do not build a sanitizer on what spaCy will tag" warning reproducing on new inputs.

## 2. What the phonemes say about the user's `.sh` observation

The user reported that `bench-espeak.wav` pronounces `.sh` more naturally than `bench-misaki.wav`.

**What is established:** for `.sh` in isolation and inside a sentence, the two frontends produce
**the same phoneme sequence** — `.ˌɛsˈAʧ` and `.ˌɛsˈeɪtʃ` are the same three sounds in two notations.
There is no phonemic difference to explain a perceived one.

**What follows:** the difference the user heard cannot be attributed to how the extension is
phonemised. Candidate explanations that remain live, none of them tested here:

1. The surrounding token differed. `bench-*.wav`'s text is not recorded in
   [`kokoro-onnx-provisioning.md`](kokoro-onnx-provisioning.md), so the `.sh` in it may have sat next
   to something that *did* differ — as `rewrite-md.sh` does, where espeak adds a full stop and misaki
   does not, changing the pause immediately before "S-H".
2. Prosody differs even where phonemes match, because the two streams differ *elsewhere* in the same
   generation and Kokoro's contour is computed over the whole chunk.
3. It is a general voice-quality preference between the two streams, not about `.sh` at all.

**This is why the batches matter more than a rerun.** Position 1 and 2 of batch 1 put the
add-a-full-stop case and the phoneme-identical case back to back, so the next listen can separate
these three.

## 3. Identifiers: espeak inserts word boundaries, misaki does not

This is the largest substantive difference in the set, and it inverts
[#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3)'s worst finding.

| Input | misaki | espeak |
| --- | --- | --- |
| `CLAUDISH_MIN_CHARS` (isolated) | `sˌiˌɛlˌAjˌudˌiˌIˌɛsˈAʧmˌɪnsˌiˌAʧˌAˌɑɹˈɛs` — "C-L-A-U-D-I-S-H-min-C-H-A-R-S", one unbroken run | `klˈɔːdɪʃ mˈɪn tʃˈɑːɹz` — "claudish min chars", **three words** |
| `CLAUDISH_MIN_CHARS` (in sentence) | same as above | `klˈɔːdɪʃ ˌɛmˌaɪˈɛn tʃˈɑːɹz` — "claudish **M-I-N** chars" |
| `snake_case` | `snˈAkkˌAs` — one word | `snˈeɪk kˈeɪs` — **two words** |
| `camelCase` | `kˈæmᵊlkˌAs` — one word | `kˈæməl kˈeɪs` — **two words** |
| `kebab-case` | `kəbˈɑbkˌAs` | `kəbˈɑːbkˈeɪs` — also one word (identical) |
| `getUserById` | `ɡɛtjˈuzəɹbˌIˈɪd` — one word | `ɡɛt jˈuːzɚ baɪ aɪdˈiː` — **"get user by I-D"**, four words |
| `MAX_RETRIES` (in sentence) | `mˌæksɹitɹˈIz` — one word | `ˌɛmˌeɪˈɛks ɹˈiːtɹaɪz` — "**M-A-X** retries" |
| `CLAUDISH_ENABLED=0` | `klˈɔdɪʃ ɛnˈAbᵊld ˈikwᵊlz zˈiəɹO` | identical |

Three mechanisms, all reproducible:

- **espeak splits on `_` and on camel boundaries; misaki does not.**
  [#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3) traced misaki's cause
  precisely (`resolve_tokens` only inserts a gap when `prespace` is true, and for an all-alphabetic
  identifier it never is). espeak has no such rule, so `snake_case` and `camelCase` come out as two
  words. **`snake_case` and `camelCase` remain indistinguishable from each other in both frontends** —
  what changes is only whether the seam is audible as a gap.
- **misaki spells unknown all-caps segments letter by letter and glues the result together.** That is
  `Lexicon.get_NNP`. `CLAUDISH_MIN_CHARS` is the worst case measured anywhere in this effort: 14
  letter names with no gaps.
- **espeak also spells all-caps segments, but only some of them, and only in context.** `MIN` and
  `MAX` are spelled inside a sentence (`ˌɛmˌaɪˈɛn`, `ˌɛmˌeɪˈɛks`) but spoken as words when the token
  stands alone. `CLAUDISH`, `CHARS` and `RETRIES` are spoken as words in both positions. **So espeak's
  identifier handling is context-dependent too** — it is better here, but it is not a rule the design
  can lean on.
- `CLAUDISH_ENABLED=0` is **identical** in both, because the `=` and the digit make misaki's
  `prespace` true and route the whole token to its own espeak fallback. A one-character difference in
  the input decides which of two very different code paths runs.

Duration evidence that the difference is real and not a notation artifact: sentence 2.1 is the only
sentence in the set where **misaki's audio is longer than espeak's** (4.12 s vs 3.71 s) — consistent
with spelling out 14 letters.

## 4. Numbers: the two frontends fail on opposite inputs

| Input | misaki | espeak |
| --- | --- | --- |
| `8080` | `ˈATi ˈATi` — "eighty eighty" (the year rule) | `ˈeɪt θˈaʊzənd ˈeɪɾi` — "eight thousand eighty" |
| `1234` | `twˈɛlv θˈɜɹTi fˈɔɹ` — "twelve thirty four" (the year rule) | `wˈʌn θˈaʊzənd tˈuːhˈʌndɹɪd θˈɜːɾi fˈɔːɹ` — **correct** |
| `1,234` | `wˈʌn θˈWzᵊnd tˈu hˈʌndɹəd θˈɜɹTi fˈɔɹ` — **correct** | `wˈʌn,tˈuːhˈʌndɹɪd θˈɜːɾi fˈɔːɹ` — "one **[comma]** two hundred thirty four" — **"thousand" is gone** |
| `429` | "four hundred twenty nine" | same words |
| `510` | "five hundred ten" | same words |
| `SHA-256` | `ˌɛsˌAʧˈA tˈu fˈɪfti sˈɪks` — "S-H-A two fifty six" | `ˌɛsˌeɪtʃˈeɪ tˈuːhˈʌndɹɪd fˈɪfti sˈɪks` — "S-H-A two hundred fifty six" |
| `16 GB` | "sixteen G-B" | identical |
| `0.24x` | `zˈɪɹO pYnt tˈu fˈɔɹ ˈɛks` — "zero point two four ex" | `zˈiəɹoʊ.twˈɛnti fˈɔːɹ ˈɛks` — "zero**[.]**twenty four ex" — **no "point"** |

Two findings, both new:

1. **The 4-digit year rule is misaki-specific.**
   [#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3) established it from
   `Lexicon.get_number` (`num2words(..., to='year')` for any bare 4-digit number) and listed it as
   sanitizer must-fix #4. espeak does not have it: `8080` is "eight thousand eighty", `1234` is read
   in full. **On the espeak frontend, the comma-insertion fix
   [#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3) recommends is not only
   unnecessary, it is actively harmful** — espeak drops the "thousand" from `1,234`. A sanitizer rule
   written for one frontend breaks the other.
2. **espeak reads `.` inside a number as punctuation rather than "point".** `0.24x` loses the word
   "point" entirely and gains a full stop. misaki says "point" correctly. So for decimals misaki is
   the better frontend, and for 4-digit integers espeak is.

## 5. Version strings: espeak plants a full stop between components

| Input | misaki | espeak |
| --- | --- | --- |
| `v0.3.0` | `vˈi zˈɪɹO θɹˈi zˈɪɹO` — "v zero three zero" | `vˈiː zˈiəɹoʊ.θɹˈiː.zˈiəɹoʊ` — "v zero**.**three**.**zero" |
| `torch 2.13.0` | `tˈɔɹʧ tˈu θˌɜɹtˈin zˈɪɹO` — "torch two thirteen zero" | `tˈɔːɹtʃ tˈuː.θˈɜːtiːn.zˈiəɹoʊ` — "torch two**.**thirteen**.**zero" |

Both frontends agree on the digits and neither says "point" or "dot" —
[#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3) established that for
misaki, and it holds for espeak. The difference is that espeak leaves **two sentence-final `.`
phonemes inside a single version number**. Those `.` marks are in the model vocab and they are also
chunk-boundary candidates, so on a long message espeak can place a 510-phoneme seam *inside* a
version string. Sentence 2.7 is the largest duration gap in the set — espeak 5.61 s versus misaki
4.48 s, +25 % — which is what two extra full stops buy.

## 6. Markdown, emoji and URLs: identical, and both bad

Every prediction [#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3) made about
these reproduces on the espeak frontend, unchanged:

| Input | Both frontends |
| --- | --- |
| `**bold**` in a sentence | `ˈæstəɹɹˌɪskəstəɹɹˌɪsk bˈOld ˈæstəɹɹˌɪskəstəɹɹˌɪsk` — "asterisk-asterisk bold asterisk-asterisk" |
| `# heading` | `hˈæʃ hˈɛdɪŋ` — "hash heading" |
| `✅` | `wˈIt hˈɛvi ʧˈɛk mˈɑɹk` — "white heavy check mark" |
| `https://github.com/hexgrad/kokoro` | `ˌAʧtˌitˈipˌiˈɛs:slˈæʃslæʃ ɡˈɪthʌb.kˈɑm slˈæʃ hˈɛksɡɹæd slˈæʃ kəkˈɔɹO` |

Both frontends voice **all four** asterisks of `**bold**` in a sentence. The
[#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3) non-determinism also
reproduced: on the **bare** token `**bold**` misaki voiced exactly **one** trailing asterisk
(`bˈOld ˈæstəɹɹˌɪsk`) while espeak voiced all four. Same input, different sentence, different number
of spoken asterisks — further confirmation that stripping `*` is the only safe option.

**Consequence for [#8](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/8): items
1, 2, 3 and 6 of [#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3)'s
must-strip list (`*`, `#`, URLs, emoji) are frontend-independent and stay exactly as written. Items 4
(4-digit numbers) and 5 (`SCREAMING_SNAKE_CASE`) are misaki-specific and must be gated on which
frontend ships.**

## 7. Defects found that neither ticket predicted

1. **misaki injects a literal `)` before a single-letter flag.** `"I passed --max-time 30 and -p to curl."`
   → `… ænd )pˈi tə kˈɜɹl.` spaCy tagged both the `-` and the `p` of `-p` as `-RRB-` (right bracket),
   and misaki's `PUNCT_TAG_PHONEMES['-RRB-']` is `)`, which **is** in the model vocab. espeak produces
   a clean `pˈiː`. Short flags are common in rewrites ("I ran it with -p"), so this is worth a
   sanitizer rule.
2. **espeak reads the verb "lives" as the noun `laɪvz`.** Both *"The virtual environment lives in …"*
   and *"The permission lives in …"* come out as `lˈaɪvz` (rhyming with "hives") from espeak and
   correctly as `lˈɪvz` from misaki. This is **ordinary prose**, not a code token, and it is the
   clearest single-word wrongness in the whole set. It is a hint that misaki's spaCy POS tagging buys
   something real on prose, which is where most of a rewrite's words are.
3. **espeak doubles `ɹ` across some word boundaries**: `pɹəvˈaɪdɚɹ ˈænsɚd`, `sˈɜːvɚɹ ɪz`. Two
   occurrences, both before a vowel-initial next word. Harmless-looking; noted because it is a real
   extra segment in the stream.
4. **espeak drops word gaps that misaki keeps**, both between function words and inside numbers:
   `ɪnðə` ("in the"), `ʌvðə` ("of the"), `fəɹðə` ("for the"), `fˈɔːɹhˈʌndɹɪd` ("four hundred"),
   `fˈaɪvhˈʌndɹɪd` ("five hundred"). Five occurrences, all against misaki's two words.

## 8. Nothing crashed, and nothing was silently dropped

Explicitly checked, because
[#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3) warned about both failure
modes:

- **48 tokens × 2 frontends and 32 sentences × 2 frontends: zero exceptions, zero empty phoneme
  strings.** Not one token defeated either G2P. `✅`, `::`, `=`, `~`, `**`, `#` and a full URL all
  survived.
- **Zero characters were removed by the `DEFAULT_VOCAB` filter** on either frontend, for any input.
  `. , : ; ? ! ( ) “ ” —` are all in the vocab, so the punctuation both frontends emit reaches the
  model rather than being dropped.
- **No sentence came close to the 510-phoneme limit.** The longest was 122 phonemes (espeak, sentence
  2.13). So nothing here exercises chunking, and `Tokenizer.tokenize`'s `ValueError` at
  `MAX_PHONEME_LENGTH` was never approached.

---

## The audio

Four files, **24 kHz mono 16-bit**, voice `af_heart`, in `~/.local/share/kokoro/`. Each sentence is a
**separate generation**, concatenated with a fixed 0.45 s silence, so position *N* is the same
sentence in all four files and the two frontends can be A/B'd position by position. Positions are
numbered below; only the sentences where the phonemes differ (plus a few identical controls) were
rendered, to keep each file listenable.

| File | Duration | Sentences | Synthesis wall time |
| --- | --- | --- | --- |
| `batch1-paths-espeak.wav` | 54.4 s | 11 | 11.6 s |
| `batch1-paths-misaki.wav` | 51.4 s | 11 | 10.5 s |
| `batch2-idents-espeak.wav` | 61.4 s | 13 | 17.3 s |
| `batch2-idents-misaki.wav` | 57.3 s | 13 | 14.9 s |

espeak's audio is **longer in both batches** (+3.0 s and +4.1 s over the same sentences), driven by
the extra full stops in version numbers and the extra spoken words in numbers. The one sentence where
misaki is longer is 2.1, `CLAUDISH_MIN_CHARS`.

The files are **not committed** — they are ~2.5-2.9 MB each and the repo has no LFS. Regenerate with
the harness in [Reproducing](#reproducing).

### Listening script

```bash
K=~/.local/share/kokoro
afplay "$K/batch1-paths-espeak.wav"
afplay "$K/batch1-paths-misaki.wav"
afplay "$K/batch2-idents-espeak.wav"
afplay "$K/batch2-idents-misaki.wav"
```

`afplay` has no seek flag, so the timestamps below are for scrubbing in QuickTime, or use
`afplay -t <seconds>` from the start. Batch 2 carries most of the substantive differences; if there is
time for only one comparison, do batch 2.

**Batch 1 — paths, extensions, code locations.** Offsets: espeak / misaki.

| # | at | sentence | what to judge |
| --- | --- | --- | --- |
| 1.1 | 0:00 / 0:00 | `rewrite-md.sh` … `README.md` | espeak inserts a **full stop before `.sh`**, misaki does not. Does that read as a beat or a stumble? `README.md` in the same sentence is phoneme-identical — a built-in control. |
| 1.2 | 0:05 / 0:04 | `.sh, .py, .md, .json, .wav` | **Phonemes are identical here.** If these still differ to your ear, the cause is voice/prosody, not the extension — which would resolve §2. |
| 1.3 | 0:09 / 0:08 | `providers.sh:129` | Identical in both. The `:` is a punctuation phoneme: judge whether a pause inside a file:line reference is acceptable at all. |
| 1.4 | 0:15 / 0:14 | `~/.claude/claudish-off` | Both say "tilde slash dot claude slash claudish off". Is `~/` worth speaking, or should the sanitizer rewrite it? |
| 1.5 | 0:20 / 0:18 | `/usr/bin/afplay` | **Count the slashes: espeak 3, misaki 2.** espeak speaks the leading `/`, misaki drops it. |
| 1.6 | 0:24 / 0:22 | `docs/research/kokoro-deployment.md` | Identical apart from accent. A 3-segment path with an extension — judge whether it is tolerable at all, or whether the sanitizer should say "the deployment doc". |
| 1.7 | 0:29 / 0:27 | `~/.local/share/kokoro/venv` | Four slashes, the longest path in the set. Also: **espeak says "lives" wrongly**, as `laɪvz`. |
| 1.11 | 0:35 / 0:33 | `tests/test_rewrite.py::test_short` | Identical. `::` survives as two colon phonemes — judge the double pause. |
| 1.12 | 0:39 / 0:37 | `src/index.ts` → `src/main.ts` | Identical. `src` is spelled "S-R-C" and `.ts` "T-S" by both. Is spelling right here? |
| 1.13 | 0:46 / 0:43 | `/tmp/claudish.log` | Both speak the leading slash here (unlike #5). "tmp" is spelled "T-M-P". |
| 1.15 | 0:50 / 0:48 | `.claude/settings.json` | Leading bare `.`; espeak again says `laɪvz` for "lives". |

**Batch 2 — identifiers, flags, versions, numbers.** Offsets: espeak / misaki.

| # | at | sentence | what to judge |
| --- | --- | --- | --- |
| 2.1 | 0:00 / 0:00 | `CLAUDISH_MIN_CHARS` | **The headline comparison.** misaki spells 14 letters with no gaps; espeak says "claudish M-I-N chars". This is [#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3)'s ear-test question 3. |
| 2.2 | 0:04 / 0:05 | `CLAUDISH_ENABLED=0` | Identical in both — the control that shows `=` plus a digit routes misaki through its own espeak fallback. |
| 2.3 | 0:08 / 0:08 | `snake_case, camelCase, kebab-case` | Same sounds, **different word gaps**: espeak splits the first two, misaki runs them together. [#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3)'s ear-test question 2. `kebab-case` is run together in both. |
| 2.4 | 0:13 / 0:12 | `--max-time 30`, `-p` | Listen just before "p": **misaki emits a literal `)`**. Is it audible? |
| 2.7 | 0:15 / 0:15 | `v0.3.0`, `torch 2.13.0` | **espeak puts a full stop between every component.** espeak's sentence is 1.13 s longer for the same words. |
| 2.8 | 0:21 / 0:20 | `port 8080` | misaki "eighty eighty"; espeak "eight thousand eighty". Which is less confusing in a sentence? |
| 2.9 | 0:25 / 0:23 | `16 GB`, `0.24x realtime` | `16 GB` identical. For `0.24x`: misaki says "point", **espeak omits it** and inserts a stop. |
| 2.10 | 0:30 / 0:28 | `SHA-256` | "S-H-A two fifty six" (misaki) vs "S-H-A two hundred fifty six" (espeak). |
| 2.11 | 0:34 / 0:32 | `JSON`, `jq`, `stdin` | misaki spells **"J-S-O-N"**, espeak says **"jason"**. Both spell "J-Q" and "S-T-D-in". |
| 2.13 | 0:38 / 0:36 | `1234` and `1,234` | The mirror failure, both readings in one sentence. misaki gets the comma form right and the bare form wrong; espeak the reverse. |
| 2.14 | 0:45 / 0:42 | `getUserById`, `MAX_RETRIES` | espeak says "get user by I-D" and "M-A-X retries"; misaki runs each into one word. |
| 2.15 | 0:50 / 0:46 | `**bold**`, `# heading` | Identical: four asterisks and a "hash" in both. Confirm by ear that this is as bad as it looks. |
| 2.16 | 0:55 / 0:51 | the GitHub URL | Identical: read out in full, `:` and `.` as pauses. |

---

## What this means for the open decisions

**For [#8](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/8), the sanitizer:**

- The frontend-independent rules stand: strip `*`, strip `#` markers, replace or drop URLs, strip
  emoji. Both frontends voice them identically and badly.
- **Two of [#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3)'s six must-fix
  rules are frontend-specific and one of them backfires.** The 4-digit-number rule and the
  `SCREAMING_SNAKE_CASE` rule exist because of misaki's `get_number` and `get_NNP`. espeak has neither
  problem, and the recommended comma fix for `1,234` makes espeak *worse*. **The sanitizer must be
  written after the frontend is chosen, not before.**
- New rule candidates: rewrite a bare `-p` style flag (misaki's `)` injection), and decide whether
  leading `~/` and `/` should be spoken at all — both frontends say "tilde slash" and "slash", which
  is at best noise.

**For [#9](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/9), voice and
pipelining:**

- Voice was **not** varied. Everything here is `af_heart`. Auditioning alternative voices against this
  corpus is still to do, and these four files are the fixture for it.
- On pipelining, one relevant number: **synthesising 11-13 sentences took 10.5-17.3 s wall**, i.e.
  0.95-1.33 s per sentence, matching
  [#5](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/5)'s warm figures. A
  single-sentence rewrite is well inside the 3 s tolerance; a 13-sentence one is not. Nothing here
  changes the gate, it just reconfirms the per-sentence cost on path-heavy text.
- **espeak is consistently slower to synthesise the same sentences** (11.6 vs 10.5 s, 17.3 vs 14.9 s),
  because its phoneme strings are longer. That is a second-order argument, not a decisive one.

---

## Could not establish

- **Anything about how any of this sounds.** Four wavs exist; no ear has heard them. Every
  "better"-shaped word in this document is about phoneme count, word count, or duration.
- **Whether the user's `.sh` observation is explained by anything measured here.** §2 rules out a
  phonemic cause for the extension itself and lists three untested alternatives. Deciding between them
  needs the text of `bench-*.wav`, which was not recorded, plus a listen.
- **Whether espeak's identifier splitting survives on identifiers not tested.** espeak spelled `MIN`
  and `MAX` but spoke `CLAUDISH`, `CHARS` and `RETRIES`, and its behaviour changed between isolated
  and in-sentence positions. No rule was derived from espeak's source — `en_list`/`en_rules` were not
  read for this. Treat the espeak column as **observations on these 48 tokens**, not as a
  specification.
- **Voice comparison.** Only `af_heart`. No other voice was synthesised.
- **Chunking and the 510-phoneme seam.** Longest sentence measured was 122 phonemes. Both the misaki
  and espeak chunkers were untouched.
- **misaki's `[text](/phonemes/)` override on the ONNX path.** Not exercised here.
  [#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3) verified it against
  `KPipeline`; whether it behaves the same when phonemes are handed to `kokoro-onnx` with
  `is_phonemes=True` was not tested.
- **British English.** `british=False` / `en-us` throughout.

## Reproducing

Three throwaway harnesses in the session scratchpad (not committed):

| Harness | What it does |
| --- | --- |
| `batches.py` | the 32 carrier sentences and 48 tokens, plus which sentences are rendered to audio |
| `phon.py` | both frontends over every token and sentence → JSON with phonemes, spaCy tags, misaki ratings, and any vocab-filtered characters |
| `norm.py` | misaki→IPA notation normalisation and the three-tier difference classifier |
| `gen.py` | the four wavs, per-sentence durations and start offsets |

The one piece worth keeping verbatim, because getting it wrong is what makes a comparison meaningless
— the espeak side must be reproduced exactly as `kokoro_onnx/tokenizer.py` does it, including the
vocab filter:

```py
import phonemizer
from kokoro_onnx.config import DEFAULT_VOCAB

raw = phonemizer.phonemize(text, "en-us", preserve_punctuation=True, with_stress=True)
espeak_phonemes = "".join(c for c in raw if c in DEFAULT_VOCAB).strip()
```

and the misaki side exactly as `kokoro/pipeline.py:123` does it, with the fallback asserted:

```py
from misaki import en, espeak
fb = espeak.EspeakFallback(british=False)
assert fb is not None
g2p = en.G2P(trf=False, british=False, fallback=fb, unk="")
phonemes, tokens = g2p(text)
```

`tk._.rating` on each returned token identifies where the pronunciation came from — 5 inline
override, 4 gold lexicon, 3 silver lexicon or `get_NNP` spelling, 2 espeak fallback. In this set,
rating 2 (fallback) covers almost every path token and rating 3 (`get_NNP`) covers
`CLAUDISH_MIN_CHARS`.

---

## Appendix: every measurement

### A. Each token on its own

`#` is batch.position, matching the sentence ids used throughout. The last column is the
mechanical verdict after normalising misaki's compact notation to espeak's IPA (see
[Method](#method)) and stripping stress and length marks. `differs` here is coarse: it covers
substantive differences and accent-notation residue alike, and is not split further for isolated
tokens — the substantive/notation split was computed only for the sentences, in
[Word-level inventory](#word-level-inventory-of-every-sentence-difference).

| # | input | misaki phonemes | espeak phonemes | |
| --- | --- | --- | --- | --- |
| 1.1 | `rewrite-md.sh` | `ɹiɹˌItˌɛmdˌiˌɛsˈAʧ` | `ɹᵻɹˈaɪtˌɛmdˈiː.ˌɛsˈeɪtʃ` | differs |
| 1.1 | `README.md` | `ɹˈidmi.ˌɛmdˈi` | `ɹˈiːdmiː.ˌɛmdˈiː` | identical |
| 1.2 | `.sh` | `.ˌɛsˈAʧ` | `.ˌɛsˈeɪtʃ` | identical |
| 1.2 | `.py` | `.pˈI` | `.pˈaɪ` | identical |
| 1.2 | `.md` | `.ˌɛmdˈi` | `.ˌɛmdˈiː` | identical |
| 1.2 | `.json` | `.ʤˈAsˈɑn` | `.dʒˈeɪsˈɑːn` | identical |
| 1.2 | `.wav` | `.wˈæv` | `.wˈæv` | identical |
| 1.3 | `providers.sh:129` | `pɹəvˈIdəɹz.ˌɛsˈAʧ:wˈʌnhˈʌndɹɪd twˈɛnti nˈIn` | `pɹəvˈaɪdɚz.ˌɛsˈeɪtʃ:wˈʌnhˈʌndɹɪd twˈɛnti nˈaɪn` | identical |
| 1.4 | `~/.claude/claudish-off` | `.klˈɔd slˈæʃ klˈɔdɪʃˈɔf` | `tˈɪldəslˌæʃ.klˈɔːd slˈæʃ klˈɔːdɪʃˈɔf` | differs |
| 1.5 | `/usr/bin/afplay` | `ˈʌsəɹ slˈæʃ bˈɪn slˈæʃ əfplˈA` | `slˈæʃ ˈʌsɚ slˈæʃ bˈɪn slˈæʃ ɐfplˈeɪ` | differs |
| 1.6 | `docs/research/kokoro-deployment.md` | `dˈɑks slˈæʃ ɹᵻsˈɜɹʧ slˈæʃ kəkˈɔɹOdᵻplˈYmənt.ˌɛmdˈi` | `dˈɑːks slˈæʃ ɹᵻsˈɜːtʃ slˈæʃ kəkˈɔːɹoʊdᵻplˈɔɪmənt.ˌɛmdˈiː` | differs |
| 1.7 | `~/.local/share/kokoro/venv` | `.lˈOkᵊl slˈæʃ ʃˈɛɹ slˈæʃ kəkˈɔɹO slˈæʃ vˈɛnv` | `tˈɪldəslˌæʃ.lˈoʊkəl slˈæʃ ʃˈɛɹ slˈæʃ kəkˈɔːɹoʊ slˈæʃ vˈɛnv` | differs |
| 1.8 | `hooks/hooks.json` | `hˈʊks slˈæʃ hˈʊks.ʤˈAsˈɑn` | `hˈʊks slˈæʃ hˈʊks.dʒˈeɪsˈɑːn` | identical |
| 1.9 | `bench-espeak.wav` | `bˈɛnʧˈispik.wˈæv` | `bˈɛntʃˈiːspiːk.wˈæv` | identical |
| 1.9 | `bench-misaki.wav` | `bˈɛnʧmɪsəki.wˈæv` | `bˈɛntʃmɪsɐki.wˈæv` | identical |
| 1.10 | `Makefile` | `mˈAkfIl` | `mˈeɪkfaɪl` | identical |
| 1.11 | `tests/test_rewrite.py::test_short` | `tˈɛsts slˈæʃ tˈɛst ɹᵻɹˈIt.pˈI::tˈɛst ʃˈɔɹt` | `tˈɛsts slˈæʃ tˈɛst ɹᵻɹˈaɪt.pˈaɪ::tˈɛst ʃˈɔːɹt` | identical |
| 1.12 | `src/index.ts` | `ˌɛsˌɑɹsˈi slˈæʃ ˈɪndɛks.tˌiˈɛs` | `ˌɛsˌɑːɹsˈiː slˈæʃ ˈɪndɛks.tˌiːˈɛs` | identical |
| 1.12 | `src/main.ts` | `ˌɛsˌɑɹsˈi slˈæʃ mˈAn.tˌiˈɛs` | `ˌɛsˌɑːɹsˈiː slˈæʃ mˈeɪn.tˌiːˈɛs` | identical |
| 1.13 | `/tmp/claudish.log` | `tˌiˌɛmpˈi slˈæʃ klˈɔdɪʃ.lˈɔɡ` | `slˈæʃ tˌiːˌɛmpˈiː slˈæʃ klˈɔːdɪʃ.lˈɔɡ` | differs |
| 1.14 | `docs/agents/issue-tracker.md` | `dˈɑks slˈæʃ ˈAʤənts slˈæʃ ˈɪʃutɹˈækəɹ.ˌɛmdˈi` | `dˈɑːks slˈæʃ ˈeɪdʒənts slˈæʃ ˈɪʃuːtɹˈækɚ.ˌɛmdˈiː` | identical |
| 1.15 | `.claude/settings.json` | `.klˈɔd slˈæʃ sˈɛTɪŋz.ʤˈAsˈɑn` | `.klˈɔːd slˈæʃ sˈɛɾɪŋz.dʒˈeɪsˈɑːn` | identical |
| 2.1 | `CLAUDISH_MIN_CHARS` | `sˌiˌɛlˌAjˌudˌiˌIˌɛsˈAʧmˌɪnsˌiˌAʧˌAˌɑɹˈɛs` | `klˈɔːdɪʃ mˈɪn tʃˈɑːɹz` | differs |
| 2.2 | `CLAUDISH_ENABLED=0` | `klˈɔdɪʃ ɛnˈAbᵊld ˈikwᵊlz zˈiəɹO` | `klˈɔːdɪʃ ɛnˈeɪbəld ˈiːkwəlz zˈiəɹoʊ` | identical |
| 2.3 | `snake_case` | `snˈAkkˌAs` | `snˈeɪk kˈeɪs` | word gaps only |
| 2.3 | `camelCase` | `kˈæmᵊlkˌAs` | `kˈæməl kˈeɪs` | word gaps only |
| 2.3 | `kebab-case` | `kəbˈɑbkˌAs` | `kəbˈɑːbkˈeɪs` | identical |
| 2.4 | `--max-time` | `mˌækstˈIm` | `mˈækstˈaɪm` | identical |
| 2.4 | `-p` | `pˈi` | `pˈiː` | identical |
| 2.5 | `curl_rc=28` | `kˈɜɹl ˌɑɹsˈi ˈikwᵊlz twˈɛnti ˈAt` | `kˈɜːl ˌɑːɹsˈiː ˈiːkwəlz twˈɛnti ˈeɪt` | differs |
| 2.6 | `HTTP 429` | `ˌAʧtˌitˌipˈi fˈɔɹ hˈʌndɹəd twˈɛnti nˈIn` | `ˌeɪtʃtˌiːtˌiːpˈiː fˈɔːɹhˈʌndɹɪd twˈɛnti nˈaɪn` | differs |
| 2.7 | `v0.3.0` | `vˈi zˈɪɹO θɹˈi zˈɪɹO` | `vˈiː zˈiəɹoʊ.θɹˈiː.zˈiəɹoʊ` | differs |
| 2.7 | `torch 2.13.0` | `tˈɔɹʧ tˈu θˌɜɹtˈin zˈɪɹO` | `tˈɔːɹtʃ tˈuː.θˈɜːtiːn.zˈiəɹoʊ` | differs |
| 2.8 | `8080` | `ˈATi ˈATi` | `ˈeɪt θˈaʊzənd ˈeɪɾi` | differs |
| 2.9 | `16 GB` | `sˌɪkstˈin ʤˌibˈi` | `sˈɪkstiːn dʒˌiːbˈiː` | identical |
| 2.9 | `0.24x realtime` | `zˈɪɹO pYnt tˈu fˈɔɹ ˈɛks ɹˈiəltIm` | `zˈiəɹoʊ.twˈɛnti fˈɔːɹ ˈɛks ɹˈiːəltaɪm` | differs |
| 2.10 | `SHA-256` | `ˌɛsˌAʧˈA tˈu fˈɪfti sˈɪks` | `ʃˈɑː tˈuːhˈʌndɹɪd fˈɪfti sˈɪks` | differs |
| 2.11 | `jq` | `ʤˌAkjˈu` | `dʒˌeɪkjˈuː` | identical |
| 2.11 | `stdin` | `ˌɛstˈidˈɪn` | `ˌɛstˈiːdˈɪn` | identical |
| 2.12 | `510` | `fˈIv hˈʌndɹəd tˈɛn` | `fˈaɪvhˈʌndɹɪd tˈɛn` | differs |
| 2.13 | `1234` | `twˈɛlv θˈɜɹTi fˈɔɹ` | `wˈʌn θˈaʊzənd tˈuːhˈʌndɹɪd θˈɜːɾi fˈɔːɹ` | differs |
| 2.13 | `1,234` | `wˈʌn θˈWzᵊnd tˈu hˈʌndɹəd θˈɜɹTi fˈɔɹ` | `wˈʌn,tˈuːhˈʌndɹɪd θˈɜːɾi fˈɔːɹ` | differs |
| 2.14 | `getUserById` | `ɡɛtjˈuzəɹbˌIˈɪd` | `ɡɛt jˈuːzɚ baɪ aɪdˈiː` | differs |
| 2.14 | `MAX_RETRIES` | `mˌæksɹitɹˈIz` | `mˈæks ɹˈiːtɹaɪz` | word gaps only |
| 2.15 | `**bold**` | `bˈOld ˈæstəɹɹˌɪsk` | `ˈæstɚɹˌɪskɐstɚɹˌɪsk bˈoʊld ˈæstɚɹˌɪskɐstɚɹˌɪsk` | differs |
| 2.15 | `# heading` | `hˈæʃ hˈɛdɪŋ` | `hˈæʃ hˈɛdɪŋ` | identical |
| 2.16 | `https://github.com/hexgrad/kokoro` | `ˌAʧtˌitˈipˌiˈɛs:slˈæʃslæʃ ɡˈɪthʌb.kˈɑm slˈæʃ hˈɛksɡɹæd slˈæʃ kəkˈɔɹO` | `ˌeɪtʃtˌiːtˈiːpˌiːˈɛs:slˈæʃslæʃ ɡˈɪthʌb.kˈɑːm slˈæʃ hˈɛksɡɹæd slˈæʃ kəkˈɔːɹoʊ` | identical |
| 2.17 | `✅` | `wˈIt hˈɛvi ʧˈɛk mˈɑɹk` | `wˈaɪt hˈɛvi tʃˈɛk mˈɑːɹk` | identical |

### B. Each token inside its carrier sentence

Same numbering and same verdict column as table A. Every `differs` row here is broken down word
by word, and classified, in
[Word-level inventory](#word-level-inventory-of-every-sentence-difference).

| # | input | misaki phonemes | espeak phonemes | |
| --- | --- | --- | --- | --- |
| 1.1 | `I renamed rewrite-md.sh but left README.md alone.` | `ˌI ɹinˈAmd ɹˌiɹItˌɛmdˌiˌɛsˈAʧ bˌʌt lˈɛft ɹˈidmi.ˌɛmdˈi əlˈOn.` | `aɪ ɹᵻnˈeɪmd ɹᵻɹˈaɪtˌɛmdˈiː.ˌɛsˈeɪtʃ bˌʌt lˈɛft ɹˈiːdmiː.ˌɛmdˈiː ɐlˈoʊn.` | differs |
| 1.2 | `It handles .sh, .py, .md, .json and .wav files.` | `ˌɪt hˈændəlz .ˌɛsˈAʧ, .pˈI, .ˌɛmdˈi, .ʤˈAsˈɑn ænd .wˈæv fˈIlz.` | `ɪt hˈændəlz .ˌɛsˈeɪtʃ, .pˈaɪ, .ˌɛmdˈiː, .dʒˈeɪsˈɑːn ænd .wˈæv fˈaɪlz.` | identical |
| 1.3 | `The bug is at providers.sh:129, right in the retry branch.` | `ðə bˈʌɡ ɪz æt pɹəvˈIdəɹz.ˌɛsˈAʧ:wˈʌnhˈʌndɹɪd twˈɛnti nˈIn, ɹˈIt ɪn ðə ɹitɹˈI bɹˈænʧ.` | `ðə bˈʌɡ ɪz æt pɹəvˈaɪdɚz.ˌɛsˈeɪtʃ:wˈʌnhˈʌndɹɪd twˈɛnti nˈaɪn, ɹˈaɪt ɪnðə ɹˈiːtɹaɪ bɹˈæntʃ.` | word gaps only |
| 1.4 | `Speech is off because ~/.claude/claudish-off exists.` | `spˈiʧ ɪz ˈɔf bəkˈʌz tˈɪldəslˌæʃ.klˈɔd slˈæʃ klˈɔdɪʃˈɔf ɪɡzˈɪsts.` | `spˈiːtʃ ɪz ˈɔf bɪkˈʌz tˈɪldəslˌæʃ.klˈɔːd slˈæʃ klˈɔːdɪʃˈɔf ɛɡzˈɪsts.` | differs |
| 1.5 | `Playback goes straight through /usr/bin/afplay.` | `plˈAbˌæk ɡˈOz stɹˈAt θɹˈu ˈʌsəɹ slˈæʃ bˈɪn slˈæʃ əfplˈA.` | `plˈeɪbæk ɡoʊz stɹˈeɪt θɹuː slˈæʃ ˈʌsɚ slˈæʃ bˈɪn slˈæʃ ɐfplˈeɪ.` | differs |
| 1.6 | `I wrote the findings to docs/research/kokoro-deployment.md.` | `ˌI ɹˈOt ðə fˈIndɪŋz tu dˈɑks slˈæʃ ɹᵻsˈɜɹʧ slˈæʃ kəkˈɔɹOdᵻplˈYmənt.ˌɛmdˈi.` | `aɪ ɹˈoʊt ðə fˈaɪndɪŋz tə dˈɑːks slˈæʃ ɹᵻsˈɜːtʃ slˈæʃ kəkˈɔːɹoʊdᵻplˈɔɪmənt.ˌɛmdˈiː.` | differs |
| 1.7 | `The virtual environment lives in ~/.local/share/kokoro/venv.` | `ðə vˈɜɹʧəwəl ənvˈIɹənmᵊnt lˈɪvz ˈɪn tˈɪldəslˌæʃ.lˈOkᵊl slˈæʃ ʃˈɛɹ slˈæʃ kəkˈɔɹO slˈæʃ vˈɛnv.` | `ðə vˈɜːtʃuːəl ɛnvˈaɪɹənmənt lˈaɪvz ɪn tˈɪldəslˌæʃ.lˈoʊkəl slˈæʃ ʃˈɛɹ slˈæʃ kəkˈɔːɹoʊ slˈæʃ vˈɛnv.` | differs |
| 1.8 | `The hook is registered in hooks/hooks.json.` | `ðə hˈʊk ɪz ɹˈɛʤəstəɹd ˈɪn hˈʊks slˈæʃ hˈʊks.ʤˈAsˈɑn.` | `ðə hˈʊk ɪz ɹˈɛdʒɪstɚd ɪn hˈʊks slˈæʃ hˈʊks.dʒˈeɪsˈɑːn.` | differs |
| 1.9 | `Compare bench-espeak.wav against bench-misaki.wav.` | `kəmpˈɛɹ bˈɛnʧˈispik.wˈæv əɡˈɛnst bˈɛnʧmɪsəki.wˈæv.` | `kəmpˈɛɹ bˈɛntʃˈiːspiːk.wˈæv ɐɡˈɛnst bˈɛntʃmɪsɐki.wˈæv.` | identical |
| 1.10 | `Line 42 of the Makefile is the culprit.` | `lˈIn fˈɔɹTi tˈu ʌv ðə mˈAkfIl ɪz ðə kˈʌlpɹət.` | `lˈaɪn fˈɔːɹɾi tˈuː ʌvðə mˈeɪkfaɪl ɪz ðə kˈʌlpɹɪt.` | differs |
| 1.11 | `Only tests/test_rewrite.py::test_short is failing.` | `ˈOnli tˈɛsts slˈæʃ tˈɛst ɹᵻɹˈIt.pˈI::tˈɛst ʃˈɔɹt ɪz fˈAlɪŋ.` | `ˈoʊnli tˈɛsts slˈæʃ tˈɛst ɹᵻɹˈaɪt.pˈaɪ::tˈɛst ʃˈɔːɹt ɪz fˈeɪlɪŋ.` | identical |
| 1.12 | `I moved the entry point from src/index.ts to src/main.ts.` | `ˌI mˈuvd ði ˈɛntɹi pˈYnt fɹʌm ˌɛsˌɑɹsˈi slˈæʃ ˈɪndɛks.tˌiˈɛs tu ˌɛsˌɑɹsˈi slˈæʃ mˈAn.tˌiˈɛs.` | `aɪ mˈuːvd ðɪ ˈɛntɹi pˈɔɪnt fɹʌm ˌɛsˌɑːɹsˈiː slˈæʃ ˈɪndɛks.tˌiːˈɛs tʊ ˌɛsˌɑːɹsˈiː slˈæʃ mˈeɪn.tˌiːˈɛs.` | differs |
| 1.13 | `Everything is logged to /tmp/claudish.log.` | `ˈɛvəɹiθˌɪŋ ɪz lˈɔɡd tə slˈæʃ tˌiˌɛmpˈi slˈæʃ klˈɔdɪʃ.lˈɔɡ.` | `ˈɛvɹɪθˌɪŋ ɪz lˈɔɡd tə slˈæʃ tˌiːˌɛmpˈiː slˈæʃ klˈɔːdɪʃ.lˈɔɡ.` | differs |
| 1.14 | `Read docs/agents/issue-tracker.md before you touch the tracker.` | `ɹˈid dˈɑks slˈæʃ ˈAʤənts slˈæʃ ˈɪʃutɹˈækəɹ.ˌɛmdˈi bəfˈɔɹ ju tˈʌʧ ðə tɹˈækəɹ.` | `ɹˈiːd dˈɑːks slˈæʃ ˈeɪdʒənts slˈæʃ ˈɪʃuːtɹˈækɚ.ˌɛmdˈiː bᵻfˌɔːɹ juː tˈʌtʃ ðə tɹˈækɚ.` | differs |
| 1.15 | `The permission lives in .claude/settings.json now.` | `ðə pəɹmˈɪʃən lˈɪvz ˈɪn .klˈɔd slˈæʃ sˈɛTɪŋz.ʤˈAsˈɑn nˈW.` | `ðə pɚmˈɪʃən lˈaɪvz ˈɪn .klˈɔːd slˈæʃ sˈɛɾɪŋz.dʒˈeɪsˈɑːn nˈaʊ.` | differs |
| 2.1 | `Raise CLAUDISH_MIN_CHARS if short replies get spoken.` | `ɹˈAz sˌiˌɛlˌAjˌudˌiˌIˌɛsˈAʧmˌɪnsˌiˌAʧˌAˌɑɹˈɛs ɪf ʃˈɔɹt ɹᵻplˈIz ɡɛt spˈOkən.` | `ɹˈeɪz klˈɔːdɪʃ ˌɛmˌaɪˈɛn tʃˈɑːɹz ɪf ʃˈɔːɹt ɹᵻplˈaɪz ɡɛt spˈoʊkən.` | differs |
| 2.2 | `Set CLAUDISH_ENABLED=0 to turn the whole thing off.` | `sˈɛt klˈɔdɪʃ ɛnˈAbᵊld ˈikwᵊlz zˈiəɹO tə tˈɜɹn ðə hˈOl θˈɪŋ ˈɔf.` | `sˈɛt klˈɔːdɪʃ ɛnˈeɪbəld ˈiːkwəlz zˈiəɹoʊ tə tˈɜːn ðə hˈoʊl θˈɪŋ ˈɔf.` | differs |
| 2.3 | `The code mixes snake_case, camelCase and kebab-case names.` | `ðə kˈOd mˈɪksᵻz snˈAkkˌAs, kˈæmᵊlkˌAs ænd kəbˈɑbkˌAs nˈAmz.` | `ðə kˈoʊd mˈɪksᵻz snˈeɪk kˈeɪs, kˈæməl kˈeɪs ænd kəbˈɑːbkˈeɪs nˈeɪmz.` | word gaps only |
| 2.4 | `I passed --max-time 30 and -p to curl.` | `ˌI pˈæst mˌækstˈIm θˈɜɹTi ænd )pˈi tə kˈɜɹl.` | `aɪ pˈæst mˈækstˈaɪm θˈɜːɾi ænd pˈiː tə kˈɜːl.` | differs |
| 2.5 | `It reported curl_rc=28, which means the request timed out.` | `ˌɪt ɹəpˈɔɹTᵻd kˈɜɹl ˌɑɹsˈi ˈikwᵊlz twˈɛnti ˈAt, wˌɪʧ mˈinz ðə ɹəkwˈɛst tˈImd ˈWt.` | `ɪt ɹᵻpˈɔːɹɾᵻd kˈɜːl ˌɑːɹsˈiː ˈiːkwəlz twˈɛnti ˈeɪt, wˌɪtʃ mˈiːnz ðə ɹᵻkwˈɛst tˈaɪmd ˈaʊt.` | differs |
| 2.6 | `The provider answered HTTP 429, so I backed off.` | `ðə pɹəvˈIdəɹ ˈænsəɹd ˌAʧtˌitˌipˈi fˈɔɹ hˈʌndɹəd twˈɛnti nˈIn, sˌO ˌI bˈækt ˈɔf.` | `ðə pɹəvˈaɪdɚɹ ˈænsɚd ˌeɪtʃtˌiːtˌiːpˈiː fˈɔːɹhˈʌndɹɪd twˈɛnti nˈaɪn, sˌoʊ aɪ bˈækt ˈɔf.` | differs |
| 2.7 | `This is v0.3.0, and torch 2.13.0 never got installed.` | `ðˌɪs ɪz vˈi zˈɪɹO θɹˈi zˈɪɹO, ænd tˈɔɹʧ tˈu θˌɜɹtˈin zˈɪɹO nˈɛvəɹ ɡɑt ɪnstˈɔld.` | `ðɪs ɪz vˈiː zˈiəɹoʊ.θɹˈiː.zˈiəɹoʊ, ænd tˈɔːɹtʃ tˈuː.θˈɜːtiːn.zˈiəɹoʊ nˈɛvɚ ɡɑːt ɪnstˈɔːld.` | differs |
| 2.8 | `The server is listening on port 8080.` | `ðə sˈɜɹvəɹ ɪz lˈɪsənɪŋ ˌɔn pˈɔɹt ˈATi ˈATi.` | `ðə sˈɜːvɚɹ ɪz lˈɪsənɪŋ ˌɔn pˈɔːɹt ˈeɪt θˈaʊzənd ˈeɪɾi.` | differs |
| 2.9 | `It fits in 16 GB and runs at 0.24x realtime.` | `ˌɪt fˈɪts ɪn sˌɪkstˈin ʤˌibˈi ænd ɹˈʌnz æt zˈɪɹO pYnt tˈu fˈɔɹ ˈɛks ɹˈiəltIm.` | `ɪt fˈɪts ɪn sˈɪkstiːn dʒˌiːbˈiː ænd ɹˈʌnz æt zˈiəɹoʊ.twˈɛnti fˈɔːɹ ˈɛks ɹˈiːəltaɪm.` | differs |
| 2.10 | `The SHA-256 checksum matched the published one.` | `ði ˌɛsˌAʧˈA tˈu fˈɪfti sˈɪks ʧˈɛksˌʌm mˈæʧt ðə pˈʌblɪʃt wˈʌn.` | `ðɪ ˌɛsˌeɪtʃˈeɪ tˈuːhˈʌndɹɪd fˈɪfti sˈɪks tʃˈɛksəm mˈætʃt ðə pˈʌblɪʃt wˌʌn.` | differs |
| 2.11 | `I piped the JSON through jq and read it from stdin.` | `ˌI pˈIpt ðə ʤˌAˌɛsˌOˈɛn θɹu ʤˌAkjˈu ænd ɹˈid ɪt fɹʌm ˌɛstˈidˈɪn.` | `aɪ pˈaɪpt ðə dʒˈeɪsˈɑːn θɹuː dʒˌeɪkjˈuː ænd ɹˈiːd ɪt fɹʌm ˌɛstˈiːdˈɪn.` | differs |
| 2.12 | `Each chunk is capped at 510 phonemes.` | `ˈiʧ ʧˈʌŋk ɪz kˈæpt æt fˈIv hˈʌndɹəd tˈɛn fˈOnˌimz.` | `ˈiːtʃ tʃˈʌŋk ɪz kˈæpt æt fˈaɪvhˈʌndɹɪd tˈɛn fˈoʊniːmz.` | differs |
| 2.13 | `The queue held 1234 items, or 1,234 if you write the comma.` | `ðə kjˈu hˈɛld twˈɛlv θˈɜɹTi fˈɔɹ ˈITəmz, ɔɹ wˈʌn θˈWzᵊnd tˈu hˈʌndɹəd θˈɜɹTi fˈɔɹ ɪf ju ɹˈIt ðə kˈɑmə.` | `ðə kjˈuː hˈɛld wˈʌn θˈaʊzənd tˈuːhˈʌndɹɪd θˈɜːɾi fˈɔːɹ ˈaɪɾəmz, ɔːɹ wˈʌn,tˈuːhˈʌndɹɪd θˈɜːɾi fˈɔːɹ ɪf juː ɹˈaɪt ðə kˈɑːmə.` | differs |
| 2.14 | `The helper getUserById ignores MAX_RETRIES entirely.` | `ðə hˈɛlpəɹ ɡɛtjˈuzəɹbˌIˈɪd ɪɡnˈɔɹz mˌæksɹitɹˈIz əntˈIəɹli.` | `ðə hˈɛlpɚ ɡɛt jˈuːzɚ baɪ aɪdˈiː ɪɡnˈɔːɹz ˌɛmˌeɪˈɛks ɹˈiːtɹaɪz ɛntˈaɪɚli.` | differs |
| 2.15 | `I made the **bold** change and added a # heading.` | `ˌI mˌAd ðə ˈæstəɹɹˌɪskəstəɹɹˌɪsk bˈOld ˈæstəɹɹˌɪskəstəɹɹˌɪsk ʧˈAnʤ ænd ˈædᵻd ɐ hˈæʃ hˈɛdɪŋ.` | `aɪ mˌeɪd ðɪ ˈæstɚɹˌɪskɐstɚɹˌɪsk bˈoʊld ˈæstɚɹˌɪskɐstɚɹˌɪsk tʃˈeɪndʒ ænd ˈædᵻd ɐ hˈæʃ hˈɛdɪŋ.` | differs |
| 2.16 | `See https://github.com/hexgrad/kokoro for the source.` | `sˈi ˌAʧtˌitˈipˌiˈɛs:slˈæʃslæʃ ɡˈɪthʌb.kˈɑm slˈæʃ hˈɛksɡɹæd slˈæʃ kəkˈɔɹO fɔɹ ðə sˈɔɹs.` | `sˈiː ˌeɪtʃtˌiːtˈiːpˌiːˈɛs:slˈæʃslæʃ ɡˈɪthʌb.kˈɑːm slˈæʃ hˈɛksɡɹæd slˈæʃ kəkˈɔːɹoʊ fɚðə sˈɔːɹs.` | differs |
| 2.17 | `Done ✅ the pull request is ready for review.` | `dˈʌn wˈIt hˈɛvi ʧˈɛk mˈɑɹk ðə pˈʊl ɹəkwˈɛst ɪz ɹˈɛdi fɔɹ ɹəvjˈu.` | `dˈʌn wˈaɪt hˈɛvi tʃˈɛk mˈɑːɹk ðə pˈʊl ɹᵻkwˈɛst ɪz ɹˈɛdi fɔːɹ ɹᵻvjˈuː.` | differs |


### Word-level inventory of every sentence difference

Produced by aligning the two normalised phoneme streams word by word
(`difflib.SequenceMatcher`) for all 32 sentences, then classifying each aligned mismatch:
**notation** if it survives collapsing r-colouring, espeak's doubled `ɹ` and unstressed vowel quality;
**word gaps** if it survives that plus removing spaces; **substantive** otherwise. This table is the
complete inventory — there is no difference between the two frontends anywhere in the corpus that is
not listed here.

| # | misaki says | espeak says | kind |
| --- | --- | --- | --- |
| 1.1 | `ɹineImd ɹiɹaItɛmdiɛseItʃ` | `ɹɪneImd ɹɪɹaItɛmdi.ɛseItʃ` | **substantive** |
| 1.2 | *(no difference anywhere in the sentence)* | | identical |
| 1.3 | `ɪn ðə` | `ɪnðə` | word gaps |
| 1.4 | `bəkʌz` | `bɪkʌz` | notation |
| 1.4 | `ɪɡzɪsts.` | `ɛɡzɪsts.` | notation |
| 1.5 | *(nothing)* | `slæʃ` | **substantive** |
| 1.6 | `tu` | `tə` | notation |
| 1.6 | `ɹɪsɜɹtʃ` | `ɹɪsɜtʃ` | notation |
| 1.7 | `vɜɹtʃəwəl ənvaIɹənmənt lɪvz` | `vɜtʃuəl ɛnvaIɹənmənt laIvz` | **substantive** |
| 1.8 | `ɹɛdʒəstəɹd` | `ɹɛdʒɪstəɹd` | notation |
| 1.9 | *(no difference anywhere in the sentence)* | | identical |
| 1.10 | `ʌv ðə` | `ʌvðə` | word gaps |
| 1.10 | `kʌlpɹət.` | `kʌlpɹɪt.` | notation |
| 1.11 | *(no difference anywhere in the sentence)* | | identical |
| 1.12 | `ði` | `ðɪ` | notation |
| 1.12 | `tu` | `tʊ` | notation |
| 1.13 | `ɛvəɹiθɪŋ` | `ɛvɹɪθɪŋ` | **substantive** |
| 1.14 | `bəfɔɹ` | `bɪfɔɹ` | notation |
| 1.15 | `lɪvz` | `laIvz` | **substantive** |
| 2.1 | `siɛleIjudiaIɛseItʃmɪnsieItʃeIɑɹɛs` | `klɔdɪʃ ɛmaIɛn tʃɑɹz` | **substantive** |
| 2.2 | `tɜɹn` | `tɜn` | notation |
| 2.3 | `sneIkkeIs, kæməlkeIs` | `sneIk keIs, kæməl keIs` | word gaps |
| 2.4 | `θɜɹti` | `θɜti` | notation |
| 2.4 | `)pi` | `pi` | **substantive** |
| 2.4 | `kɜɹl.` | `kɜl.` | notation |
| 2.5 | `ɹəpɔɹtɪd kɜɹl` | `ɹɪpɔɹtɪd kɜl` | notation |
| 2.5 | `ɹəkwɛst` | `ɹɪkwɛst` | notation |
| 2.6 | `pɹəvaIdəɹ` | `pɹəvaIdəɹɹ` | notation |
| 2.6 | `fɔɹ hʌndɹəd` | `fɔɹhʌndɹɪd` | word gaps |
| 2.7 | `zɪɹoU θɹi zɪɹoU,` | `ziəɹoU.θɹi.ziəɹoU,` | **substantive** |
| 2.7 | `tu θɜɹtin zɪɹoU` | `tu.θɜtin.ziəɹoU` | **substantive** |
| 2.8 | `sɜɹvəɹ` | `sɜvəɹɹ` | notation |
| 2.8 | `eIti` | `eIt θaUzənd` | **substantive** |
| 2.9 | `zɪɹoU pOInt tu` | `ziəɹoU.twɛnti` | **substantive** |
| 2.10 | `ði` | `ðɪ` | notation |
| 2.10 | `tu` | `tuhʌndɹɪd` | **substantive** |
| 2.10 | `tʃɛksʌm` | `tʃɛksəm` | notation |
| 2.11 | `dʒeIɛsoUɛn` | `dʒeIsɑn` | **substantive** |
| 2.12 | `faIv hʌndɹəd` | `faIvhʌndɹɪd` | word gaps |
| 2.13 | `twɛlv θɜɹti` | `wʌn θaUzənd tuhʌndɹɪd θɜti` | **substantive** |
| 2.13 | `wʌn θaUzənd tu hʌndɹəd θɜɹti` | `wʌn,tuhʌndɹɪd θɜti` | **substantive** |
| 2.14 | `ɡɛtjuzəɹbaIɪd` | `ɡɛt juzəɹ baI aIdi` | **substantive** |
| 2.14 | `mæksɹitɹaIz əntaIəɹli.` | `ɛmeIɛks ɹitɹaIz ɛntaIəɹli.` | **substantive** |
| 2.15 | `ðə` | `ðɪ` | notation |
| 2.16 | `fɔɹ ðə` | `fəɹðə` | **substantive** |
| 2.17 | `ɹəkwɛst` | `ɹɪkwɛst` | notation |
| 2.17 | `ɹəvju.` | `ɹɪvju.` | notation |
