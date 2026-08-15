# The sanitizer rule inventory, re-derived against espeak

Preparatory evidence for [#8](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/8)
(the sanitizer decision). **#8 is not resolved by this document** — it remains blocked by
[#6](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/6) and
[#7](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/7), and every question in it
that turns on how something *sounds* is still open.
Measured 2026-08-15 on the venv described in
[`kokoro-onnx-provisioning.md`](kokoro-onnx-provisioning.md).

**Nothing in this document is a claim about how anything sounds.** Every claim is a phoneme string, a
character count, or an exception. The frontend decision this document is downstream of was made by a
**human ear**, on identifiers, and is attributed that way throughout.

---

## Why this exists

[#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3)'s sanitizer analysis
([`kokoro-text-handling.md`](kokoro-text-handling.md)) derived six must-strip rules and a
ten-item leave-alone list — **entirely against misaki**.
[`kokoro-programming-text-audio.md`](kokoro-programming-text-audio.md) then showed at least two of
those rules behave differently or invert under espeak.

**The frontend is now settled: espeak — `kokoro-onnx`'s own default — plus a sanitizer.** The
pipeline calls `kokoro.create(text, voice=..., lang="en-us")` directly and does **not** pass
`is_phonemes=True`. misaki and spaCy are not in the runtime path at all.

So the rule list has to be re-derived. This document does that, rule by rule, empirically.

## Method

espeak phonemes were reproduced **exactly** as the real synthesis path produces them, from
`kokoro_onnx/tokenizer.py:67-78` — including the `DEFAULT_VOCAB` filter, which silently drops any
character not in the model vocabulary:

```py
import espeakng_loader, phonemizer
from phonemizer.backend.espeak.wrapper import EspeakWrapper
from kokoro_onnx.config import DEFAULT_VOCAB

EspeakWrapper.set_data_path(espeakng_loader.get_data_path())
EspeakWrapper.set_library(espeakng_loader.get_library_path())

raw = phonemizer.phonemize(text.strip(), "en-us", preserve_punctuation=True, with_stress=True)
filtered = "".join(filter(lambda p: p in DEFAULT_VOCAB, raw)).strip()
```

Where a claim is about chunking, exceptions, or the 510 limit, the **real model** was loaded
(`~/.local/share/kokoro/kokoro-v1.0.onnx`, `voices-v1.0.bin`) and `Kokoro.create()` was actually
called. Audio was written but **not listened to**.

Every probe below was run through the venv interpreter
`~/.local/share/kokoro/venv/bin/python`. No packages were installed; the venv was used as found.

### The vocab filter, enumerated

`DEFAULT_VOCAB` has **114 entries**. Its complete non-alphabetic membership is:

```
' !"(),.:;?̃—“”…→↓↗↘'
```

Established by iterating `kokoro_onnx.config.DEFAULT_VOCAB`. Consequences, each checked against a
test string:

| Character | In vocab | Consequence |
| --- | --- | --- |
| `. , ! ? ; : " ( )` | yes | reach the model as punctuation |
| `— … “ ”` | yes | reach the model as prosody |
| **`\n` `\r` `\t`** | **no** | **silently deleted — see rule 11** |
| `[` `]` | no | deleted; the only other characters any probe lost |
| `'` `-` `_` `~` `/` `\` `\|` `*` `#` `$` `%` `&` `@` `+` `=` `<` `>` `{` `}` and the backtick | no | never emitted by espeak in the first place — it either voices them as words or ignores them — so the filter is not what removes them |

Across every probe in this document, the **only** characters the filter removed were `\n`, `\r` and
`[`/`]`. That reproduces
[`kokoro-programming-text-audio.md`](kokoro-programming-text-audio.md)'s "zero characters removed"
finding for prose, and extends it: the filter *does* bite, but only on whitespace and brackets.

---

## Part 1 — #3's six must-strip rules, re-judged

| # | #3's rule (derived vs misaki) | espeak verdict |
| --- | --- | --- |
| 1 | Strip `*` / `**` | **still needed** (and now deterministic) |
| 2 | Strip `#` heading markers | **still needed** |
| 3 | Replace or drop URLs | **still needed** |
| 4 | Insert a comma into bare 4-digit numbers | **inverted — actively harmful** |
| 5 | Split `SCREAMING_SNAKE_CASE` on `_` and lowercase | **split: unnecessary (no-op). lowercase: still needed, narrowed** |
| 6 | Strip emoji | **still needed** |

### 1. `*` and `**` — still needed, and the non-determinism is gone

| Input | espeak phonemes | misaki, per #3 |
| --- | --- | --- |
| `I made the **bold** change.` | `aɪ mˌeɪd ðɪ ˈæstɚɹˌɪskɐstɚɹˌɪsk bˈoʊld ˈæstɚɹˌɪskɐstɚɹˌɪsk tʃˈeɪndʒ.` | voiced |
| `the *starred* one` | `ðɪ ˈæstɚɹˌɪsk stˈɑːɹd ˈæstɚɹˌɪsk wˌʌn` | voiced |
| `**Done.** I fixed it.` | `ˈæstɚɹˌɪskɐstɚɹˌɪsk dˈʌn.ˈæstɚɹˌɪskɐstɚɹˌɪsk aɪ fˈɪkst ɪt.` | **silent** |
| `* first bullet` | `ˈæstɚɹˌɪsk fˈɜːst bˈʊlɪt` | — |

**espeak voices every asterisk, in every position tried.** The `**Done.**` case is the interesting
one: misaki was *silent* there because spaCy happened to tag the asterisks as punctuation. espeak has
no tagger, so the outcome is stable — which makes the rule easier to justify, not less necessary.
Note also that a `*` **bullet marker** is voiced while a `-` bullet marker is silent (rule 7), so
list markers are not uniformly safe.

Bash or Python: **bash** — `s/\*\+//g`.

### 2. `#` heading markers — still needed

| Input | espeak phonemes |
| --- | --- |
| `# Heading here` | `hˈæʃ hˈɛdɪŋ hˈɪɹ` |
| `## Heading two` | `hˈæʃhæʃ hˈɛdɪŋ tˈuː` |
| `### Summary` | `hˈæʃhɐʃhˌæʃ sˈʌmɚɹi` |

Identical in shape to misaki, including espeak's `$max3` cap at three repetitions. Unchanged.
Note `##` gives **two** "hash" under espeak where #3 observed one under misaki (spaCy had blanked the
first as a currency tag) — another case where removing spaCy removed the luck.

Bash or Python: **bash** — anchored `sed` on `^ *#\{1,6\} \+`.

### 3. URLs — still needed

| Input | espeak phonemes |
| --- | --- |
| `https://github.com/hexgrad/kokoro` | `ˌeɪtʃtˌiːtˈiːpˌiːˈɛs:slˈæʃslæʃ ɡˈɪthʌb.kˈɑːm slˈæʃ hˈɛksɡɹæd slˈæʃ kəkˈɔːɹoʊ` |
| `https://example.com/a/b?x=1&y=2` | `…bˈiː?ˈɛks ˈiːkwəlz wˈʌn ænd wˈaɪ ˈiːkwəlz tˈuː` |
| `github.com/hexgrad/kokoro` (schemeless) | `ɡˈɪthʌb.kˈɑːm slˈæʃ hˈɛksɡɹæd slˈæʃ kəkˈɔːɹoʊ` |
| `See https://…/kokoro for details.` → `See a link for details.` | `sˈiː ɐ lˈɪŋk fɔːɹ diːtˈeɪlz.` |

Read out in full, character class by character class, with `:` and `.` landing as punctuation —
byte-for-byte the same failure #3 described. Replacing the URL with a spoken phrase produces clean
phonemes (last row). Schemeless URLs behave the same way, so a `https?://`-only regex under-matches.

Bash or Python: **bash**, but note the schemeless case needs a second pattern.

### 4. Bare 4-digit numbers — INVERTED, and #3's fix is actively harmful

This is the sharpest reversal in the set. **espeak has no year rule, and inserting a thousands
separator destroys the reading.**

| Input | espeak phonemes | Reads as | misaki, per #3 |
| --- | --- | --- | --- |
| `8080` | `ˈeɪt θˈaʊzənd ˈeɪɾi` | "eight thousand eighty" | "eighty eighty" ✗ |
| `1234` | `wˈʌn θˈaʊzənd tˈuːhˈʌndɹɪd θˈɜːɾi fˈɔːɹ` | correct | "twelve thirty four" ✗ |
| `16000` | `sˈɪkstiːn θˈaʊzənd` | correct | — |
| `1234567` | `wˈʌn mˈɪliən tˈuːhˈʌndɹɪd θˈɜːɾi fˈɔːɹ θˈaʊzənd fˈaɪvhˈʌndɹɪd sˈɪksti sˈɛvən` | correct | — |
| `1,234` | `wˈʌn,tˈuːhˈʌndɹɪd θˈɜːɾi fˈɔːɹ` | "one **[comma]** two hundred thirty four" — **"thousand" gone** | correct |
| `16,000` | `sˈɪkstiːn,zˈiəɹoʊzˈiəɹoʊ zˈiəɹoʊ` | "sixteen **[comma]** zero zero zero" | correct |
| `1,234,567` | `wˈʌn,tˈuːhˈʌndɹɪd θˈɜːɾi fˈɔːɹ,fˈaɪvhˈʌndɹɪd sˈɪksti sˈɛvən` | "thousand"/"million" both gone | correct |
| `$1,000` | `dˈɑːlɚ wˈʌn,zˈiəɹoʊzˈiəɹoʊ zˈiəɹoʊ` | broken | — |

`16,000` is worse than `1,234`: espeak drops the magnitude word *and* reads the remaining three
digits individually.

**Years need no rewrite.** `2026` → `tˈuː θˈaʊzənd twˈɛnti sˈɪks` ("two thousand twenty six");
`1999` → `nˈaɪntiːnhˈʌndɹɪd nˈaɪnti nˈaɪn` ("nineteen hundred ninety nine"). Both defensible readings
with no intervention.

**So the espeak rule is the exact opposite of #3's: strip thousands separators, do not insert them.**

Bash or Python: **bash**, but only with GNU-ish care — the correct transform needs a lookahead
(`(?<=\d),(?=\d{3})` applied repeatedly for `1,234,567`). BSD `sed` has no lookahead; the loop form
`:a;s/\([0-9]\),\([0-9]\{3\}\)/\1\2/;ta` works. **Python is cleaner here.**

### 5. `SCREAMING_SNAKE_CASE` — splitting on `_` is a no-op; lowercasing is the rule that works

**Splitting on `_` changes nothing at all.** Every identifier tested produced **byte-identical**
phonemes with `_` and with a space:

| Input | phonemes with `_` | phonemes with space | identical? |
| --- | --- | --- | --- |
| `CLAUDISH_MIN_CHARS` | `klˈɔːdɪʃ mˈɪn tʃˈɑːɹz` | `klˈɔːdɪʃ mˈɪn tʃˈɑːɹz` | yes |
| `MAX_RETRIES` | `mˈæks ɹˈiːtɹaɪz` | `mˈæks ɹˈiːtɹaɪz` | yes |
| `HTTP_429` | `ˌeɪtʃtˌiːtˌiːpˈiː fˈɔːɹhˈʌndɹɪd twˈɛnti nˈaɪn` | same | yes |
| `CLAUDISH_OFF_FILE` | `klˈɔːdɪʃ ˈɔf fˈaɪl` | same | yes |
| `CLAUDISH_TTS_URL` | `klˈɔːdɪʃ tˌiːtˌiːˈɛs jˌuːˌɑːɹɹˈɛl` | same | yes |
| `snake_case` | `snˈeɪk kˈeɪs` | same | yes |
| `camelCase` | `kˈæməl kˈeɪs` | same (`camel Case`) | yes |
| `getUserById` | `ɡɛt jˈuːzɚ baɪ aɪdˈiː` | same | yes |

Also checked in carrier sentences (`The default for X is ten.`) — still identical. **Verdict for the
split: unnecessary. It is a no-op, not a harm.**

**But case matters, and that is where the remaining defect is.** espeak spells out short all-caps
segments *in sentence context* and speaks them as words when lowercase:

| In a sentence | UPPERCASE | lowercase |
| --- | --- | --- |
| `…for CLAUDISH_MIN_CHARS is ten.` | `klˈɔːdɪʃ ˌɛmˌaɪˈɛn tʃˈɑːɹz` — "claudish **M-I-N** chars" | `klˈɔːdɪʃ mˈɪn tʃˈɑːɹz` — "claudish min chars" |
| `…for MAX_RETRIES is ten.` | `ˌɛmˌeɪˈɛks ɹˈiːtɹaɪz` — "**M-A-X** retries" | `mˈæks ɹˈiːtɹaɪz` — "max retries" |
| `Set CLAUDISH_OFF_FILE …` | `klˈɔːdɪʃ ˌoʊˌɛfˈɛf fˈaɪl` — "claudish **O-F-F** file" | `klˈɔːdɪʃ ˈɔf fˈaɪl` — "claudish off file" |

Note the same identifier **in isolation** gives `mˈɪn` (the word). So espeak's spell-out is
context-dependent — a caution, not a rule, exactly as
[`kokoro-programming-text-audio.md`](kokoro-programming-text-audio.md) warned.

**Lowercasing does not damage genuine acronyms**, because espeak spells unpronounceable letter runs
regardless of case. Verified identical upper/lower: `JSON`→`dʒˈeɪsˈɑːn`, `API`→`ˌeɪpˌiːˈaɪ`,
`HTTP`→`ˌeɪtʃtˌiːtˌiːpˈiː`, `URL`→`jˌuːˌɑːɹɹˈɛl`, `TTS`→`tˌiːtˌiːˈɛs`, `SQL`→`ˌɛskjˌuːˈɛl`,
`CPU`→`sˌiːpˌiːjˈuː`, `ID`→`aɪdˈiː`, `GB`→`dʒˌiːbˈiː`, `NPM`→`ˌɛnpˌiːˈɛm`.

**Two regressions found, and they are why the rule must be narrowed:**

- `RAM` → `ˌɑːɹɹˌeɪˈɛm` (R-A-M) becomes `ram` → `ɹˈæm` (the animal).
- `SHA-256` → `ˌɛsˌeɪtʃˈeɪ tˈuːhˈʌndɹɪd…` (S-H-A) becomes `sha-256` → `ʃˈɑː …` ("shah").

Restricting the lowercase to **all-caps segments inside a `_`-joined identifier** removes both
regressions while keeping the win. Verified: `MAX_RETRIES is 3 and HTTP_429 is retried.` →
`mˈæks ɹˈiːtɹaɪz … ˌeɪtʃtˌiːtˌiːpˈiː fˈɔːɹhˈʌndɹɪd twˈɛnti nˈaɪn`, and
`We use SHA-256 and it has 16 GB of RAM.` unchanged.

Bash or Python: the narrowed rule needs "match an identifier token, then lowercase **that match**".
That is a callback substitution. `awk` can do it (`tolower()` per field), `sed` cannot portably.
**Wants Python, or awk.**

### 6. Emoji — still needed

| Input | espeak phonemes |
| --- | --- |
| `✅` | `wˈaɪt hˈɛvi tʃˈɛk mˈɑːɹk` |
| `🎉 Shipped!` | `pˈɑːɹɾi pˈɑːpɚ ʃˈɪpt!` |
| `⚠️ Careful.` | `wˈɔːɹnɪŋ kˈɛɹfəl.` |
| `🚀` | `ɹˈɑːkɪt` |
| `😀` | `ɡɹˈɪnɪŋ fˈeɪs` |

Read by Unicode name, exactly as #3 found. The `⚠️` case confirms the variation selector U+FE0F is
handled without residue. Unchanged.

Bash or Python: **Python.** Ranged Unicode character classes in `sed`/`tr` are not portable across
BSD and GNU, and emoji are multi-codepoint (ZWJ sequences, variation selectors). Python's `re` with
explicit codepoint ranges is the honest way to do it.

---

## Part 2 — #3's leave-alone list, re-judged

| # | #3's item | espeak verdict |
| --- | --- | --- |
| 7 | `_italics_`, `-` bullets, `>` blockquotes, `\|` pipes, `--flags` | **confirmed — leave alone** |
| 8 | Backticks (deferred to an ear test) | **settled without an ear test — leave alone** |
| 9 | Currency, `%`, thousands commas, ordinals, `& @ +` | **splits: `%`/ordinals/`&@+` fine; currency and commas are broken** |
| 10 | Terminal punctuation is load-bearing | **still needed — and stronger than #3 said** |
| 11 | Preserve `\n` | **inverted — `\n` is deleted and carries nothing** |
| 12 | `[text](/phonemes/)` override | **does not exist; actively harmful if emitted** |
| 13 | Runtime lexicon injection | **does not exist on this path** |
| 14 | Guard the silent-espeak-failure mode | **no longer silent — the guard is already in kokoro-onnx** |

### 7. Underscores, hyphens, bullets, blockquotes, pipes, flags — confirmed harmless

| Input | espeak phonemes | Note |
| --- | --- | --- |
| `an _italic_ word` | `ɐn ɪtˈælɪk wˈɜːd` | clean |
| `- first bullet` | `fˈɜːst bˈʊlɪt` | marker silent |
| `> quoted line` | `kwˈoʊɾᵻd lˈaɪn` | silent |
| `a \| b` | `ɐ bˈiː` | silent |
| `the --dry-run flag` | `ðə dɹˈaɪɹˈʌn flˈæɡ` | clean |
| `I passed -p to curl.` | `aɪ pˈæst pˈiː tə kˈɜːl.` | clean |
| `I passed --max-time 30 and -p to curl.` | `aɪ pˈæst mˈækstˈaɪm θˈɜːɾi ænd pˈiː tə kˈɜːl.` | clean |
| `1. First step` | `wˈʌn. fˈɜːst stˈɛp` | same as misaki |
| `The <div> tag.` | `ðə dˈɪv tˈæɡ.` | angle brackets silent |

**This also closes a defect
[`kokoro-programming-text-audio.md`](kokoro-programming-text-audio.md) §7.1 raised.** misaki injected
a literal `)` before a single-letter flag (`… ænd )pˈi tə kˈɜɹl.`), because spaCy tagged `-p` as
`-RRB-`. **espeak does not** — `-p` is clean in both sentences tried. That candidate rule is
**unnecessary on this frontend.**

### 8. Backticks — settled, no ear test needed

| Input | espeak phonemes |
| --- | --- |
| `` `rewrite.sh` `` | `ɹᵻɹˈaɪt.ˌɛsˈeɪtʃ` |
| ` ```a fence``` ` | `ɐ fˈɛns` |

**espeak emits nothing at all for a backtick.** misaki turned it into a curly quote `“ ”`, which is
in the vocab and reached the model as a prosodic mark — which is why #3 deferred the decision to an
ear test. On this frontend there is nothing to hear. **#3's ear-test question 1 about backticks is
moot; leave them alone.**

(`—` and `…` *are* in the vocab and do survive as prosody. `:` survives too — `Done: finally.` →
`dˈʌn: fˈaɪnəli.` — but see rule 10 for why `:` is not a chunk boundary here.)

### 9. Numbers and symbols — split verdict

**Confirmed fine, leave alone:**

| Input | espeak phonemes |
| --- | --- |
| `50%` | `fˈɪfti pɚsˈɛnt` |
| `1st` / `2nd` / `3rd` | `fˈɜːst` / `sˈɛkənd` / `θˈɜːd` |
| `a & b` / `a @ b` / `a + b` | `ˈeɪɐnd bˈiː` / `ɐ æt bˈiː` / `ɐ plˈʌs bˈiː` |
| `3:45` | `θɹˈiː:fˈɔːɹɾi fˈaɪv` |

**Broken, needs a rule — currency:**

| Input | espeak phonemes | Reads as |
| --- | --- | --- |
| `It costs $4.50.` | `ɪt kˈɔsts dˈɑːlɚ fˈɔːɹ.fˈɪfti.` | "costs **dollar** four **[full stop]** fifty" |
| `It costs $20.` | `ɪt kˈɔsts dˈɑːlɚ twˈɛnti.` | "costs **dollar** twenty" |
| `It costs $1,000.` | `ɪt kˈɔsts dˈɑːlɚ wˈʌn,zˈiəɹoʊzˈiəɹoʊ zˈiəɹoʊ.` | fully broken |

espeak reads `$` as a **pre-posed singular "dollar"** and does not say "point" or "cents". misaki
handled all of this correctly (`fˈɔɹ dˈɑləɹz ænd fˈɪfti sˈɛnts`). **#3's item 9 is inverted for
currency.** Verified fix — move the unit after the number and pluralise:

| Rewrite | espeak phonemes |
| --- | --- |
| `It costs 4 dollars 50.` | `ɪt kˈɔsts fˈɔːɹ dˈɑːlɚz fˈɪfti.` |
| `It costs 1000 dollars.` | `ɪt kˈɔsts wˈʌn θˈaʊzənd dˈɑːlɚz.` |
| `It costs 20 dollars.` | `ɪt kˈɔsts twˈɛnti dˈɑːlɚz.` |

**Broken, needs a rule — thousands commas:** see rule 4. #3 listed "commas-in-thousands" under
*leave alone*; on espeak they are one of the worst inputs in the set.

Bash or Python: currency is a plain `sed` substitution. **bash.**

### 10. Terminal punctuation — still needed, and it is now crash-preventing

#3 called terminal punctuation load-bearing for chunk-seam placement. On `kokoro-onnx` it is stronger
than that: **without it, `create()` raises.**

`Kokoro.create()` chunks by itself, via `_split_phonemes` (`kokoro_onnx/__init__.py:136-168`), which
splits the **phoneme string** on `re.split(r"([.,!?;])", phonemes)`. Note what that means:

- the split set is **`. , ! ? ;` only**. `:`, `—` and `…` are in the vocab and reach the model, but
  are **not** chunk boundaries. (misaki's `waterfall_last` did use `:;` and `,—`.)
- the docstring says it splits by spaces; **it does not**. A punctuation-free run is never split.

Measured with the real model:

| Input | phonemes | batches | `create()` |
| --- | --- | --- | --- |
| 2040 chars, one sentence per clause | 2087 | 5 — sizes 434/434/434/434/347 | **OK**, 109.4 s audio in 25.0 s wall |
| 1280 chars, commas only | 1519 | 4 — 493/493/493/37 | **OK**, 82.0 s audio in 19.2 s wall |
| 630 chars, **no punctuation at all** | 819 | 2 — sizes **0/819** | **`IndexError: index 510 is out of bounds for axis 0 with size 510`** |
| 1260 chars, no punctuation | 1639 | 2 — 0/1639 | same `IndexError` |

The mechanism, read out of the source and then confirmed by bisecting the exact boundary:

- `_create_audio` (`__init__.py:97-101`) logs `"Phonemes are too long, truncating to 510 phonemes"`
  and truncates the string to 510 characters. So `Tokenizer.tokenize`'s documented
  `ValueError("text is too long…")` is **dead code on this path** — it can never fire.
- Then `voice = voice[len(tokens)]` (`__init__.py:108`). The voice style array is shape
  **`(510, 1, 256)`** (verified by printing `get_voice_style("af_heart").shape`), so
  `len(tokens) == 510` is one past the end.

Bisected boundary, calling `_create_audio` directly with truncated phoneme strings:

```
len=508: OK, 26.60s audio
len=509: OK, 27.35s audio
len=510: IndexError: index 510 is out of bounds for axis 0 with size 510
len=511: IndexError: index 510 is out of bounds for axis 0 with size 510
```

**So: 509 phonemes is the last safe batch. Any single run without `. , ! ? ;` that phonemises to
≥510 characters raises.** English prose measured at ~1.02 phonemes per input character
(84 chars → 85 phonemes, 420 → 429), so the danger threshold is a punctuation-free stretch of
roughly **500 input characters**.

Two smaller observations from the same runs:

- `_split_phonemes` emits a **spurious empty leading batch** when the very first part already exceeds
  the budget (`sizes=[0, 819]`), because it appends `current_batch` before it has ever been filled.
  Harmless in itself — `_create_audio("")` returns 11 400 samples (0.475 s) rather than raising — but
  it means batch counts are off by one in that case.
- Not "truncated", not "errors" in the documented way: it is an **off-by-one IndexError inside
  `kokoro-onnx`**, which no ticket predicted.

**Verdict: terminal punctuation is not merely nice for seams, it is the only thing standing between a
long rewrite and an exception. It must be preserved, and a sanitizer should additionally *guarantee*
a boundary at least every ~400 characters.** Whether the guarantee lives in the sanitizer or in the
worker's own pre-`create()` splitting is
[#11](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/11)'s call, not this
document's.

### 11. `\n` — INVERTED: it is deleted and carries nothing

#3's design consequence 11 was "preserve `\n`, it is the free way to force a generation boundary."
That is a property of `KPipeline`, which splits on `r'\n+'` before phonemising. **`kokoro-onnx` has no
such split**, and `\n` is **not in `DEFAULT_VOCAB`**, so it is silently dropped by the tokenizer
filter.

| Input | espeak raw | after vocab filter |
| --- | --- | --- |
| `First line.\nSecond line.` | `fˈɜːst lˈaɪn. \nsˈɛkənd lˈaɪn. ` | `fˈɜːst lˈaɪn. sˈɛkənd lˈaɪn.` |
| `First para.\n\nSecond para.` | `fˈɜːst pˈæɹə. \nsˈɛkənd pˈæɹə. ` | `fˈɜːst pˈæɹə. sˈɛkənd pˈæɹə.` |
| `First line\nSecond line` (no punctuation) | `fˈɜːst lˈaɪn \nsˈɛkənd lˈaɪn ` | `fˈɜːst lˈaɪn sˈɛkənd lˈaɪn` |
| `- a\n- b\n- c` bullet list | — | `ɹˈæn ðə tˈɛsts fˈɪkst ðə hˈʊk pˈʊʃt ðə bɹˈæntʃ` |

Note `\n\n` collapses to a *single* `\n` in espeak's output and then to nothing. Words do not glue
together — espeak inserts a space at the line break — but there is **no pause and no boundary**.

Verified fix: turn each line break into terminal punctuation.

| Rewrite of `- ran the tests\n- fixed the hook\n- pushed the branch` | phonemes |
| --- | --- |
| as-is | `ɹˈæn ðə tˈɛsts fˈɪkst ðə hˈʊk pˈʊʃt ðə bɹˈæntʃ` |
| `\n` → `. ` | `ɹˈæn ðə tˈɛsts. fˈɪkst ðə hˈʊk. pˈʊʃt ðə bɹˈæntʃ` |
| `\n` → `, ` | `ɹˈæn ðə tˈɛsts, fˈɪkst ðə hˈʊk, pˈʊʃt ðə bɹˈæntʃ` |

Both give a chunk boundary; which one to use is a listening call for #8.

`\r` and `\t` are also not in the vocab. `\t` is emitted by espeak as a space (harmless); `\r`
survives espeak as a literal `\r` and is then dropped.

Bash or Python: **bash** — `tr`/`sed` on line breaks is trivial. Deciding *where* a synthetic
boundary must go to stay under 500 characters is arithmetic on a running count, which **wants
Python.**

### 12. `[text](/phonemes/)` — does not exist, and emitting it is one of the worst inputs measured

Confirmed empirically, not just from the absence of misaki:

| Input | phonemes after vocab filter |
| --- | --- |
| `[Kokoro](/kˈOkəɹO/) is nice.` | `kəkˈɔːɹoʊ(slˈæʃ kˈeɪ stɹˈɛs ˈoʊ kˈeɪ ʃwˈɑː tˈɜːndˈɑːɹ ˈoʊ slˈæʃ) ɪz nˈaɪs.` |
| `The file [lives](/lˈɪvz/) in docs.` | `ðə fˈaɪl lˈaɪvz(slˈæʃ ˌɛlstɹˌɛssmˈɔːlkˌæpˌaɪvˌiːzˈiː slˈæʃ) ɪn dˈɑːks.` |

**The phoneme string is read aloud, character name by character name** — "slash K-A-Y stress O K-A-Y
schwa turned-R O slash" — and the intended word is *not* corrected (`lives` is still `lˈaɪvz`). The
`[`/`]` are dropped by the vocab filter but the `(`/`)` survive as punctuation. This is the single
most damaging input tried in this document. **#3's design consequence 12 — "the escape hatch that
survives an HTTP transport" — must be marked dead for the chosen frontend, and any code that emits
that syntax must be removed.**

### 13. Runtime lexicon injection — does not exist on this path

`Lexicon.golds` is a misaki object. There is no `Lexicon` in `kokoro_onnx`; the whole G2P is one
`phonemizer.phonemize()` call. Nothing to inject into.

### 14. The silent-espeak-failure guard — already handled, and no longer silent

#3 warned that misaki's `EspeakFallback` fails silently and then deletes words, and that an install
must assert it. On the `kokoro-onnx` path, `Tokenizer.__init__` (`tokenizer.py:30-51`) explicitly
`ctypes.cdll.LoadLibrary`s the espeak library, falls back to a system-wide lookup, and **raises
`RuntimeError` with a diagnostic message** if neither works. The failure mode is loud. **No sanitizer
rule needed; keep the smoke test anyway.**

---

## Part 3 — espeak-only hazards and their fixes

### A. Version strings plant a full stop between every component

| Input | espeak phonemes | Reads as |
| --- | --- | --- |
| `v0.3.0` | `vˈiː zˈiəɹoʊ.θɹˈiː.zˈiəɹoʊ` | "v zero**.**three**.**zero" |
| `torch 2.13.0` | `tˈɔːɹtʃ tˈuː.θˈɜːtiːn.zˈiəɹoʊ` | "torch two**.**thirteen**.**zero" |
| `Python 3.11.8` | `pˈaɪθən θɹˈiː.ɪlˈɛvən.ˈeɪt` | "Python three**.**eleven**.**eight" |

Those `.` marks are in the vocab **and** are `_split_phonemes` boundaries, so on a long message a
510-phoneme seam can land inside a version number.

**Minimal fix: replace the dots of a multi-dot numeric run with spaces.** Verified:

| Rewrite | espeak phonemes |
| --- | --- |
| `It shipped as v0 3 0 with torch 2 13 0.` | `ɪt ʃˈɪpt æz vˈiː zˈiəɹoʊ θɹˈiː zˈiəɹoʊ wɪð tˈɔːɹtʃ tˈuː θˈɜːtiːn zˈiəɹoʊ.` |
| `Python 3 11 8 on macOS.` | `pˈaɪθən θɹˈiː ɪlˈɛvən ˈeɪt ˌɔn mˈæk ˌoʊˈɛs.` |

This matches misaki's reading exactly (`vˈi zˈɪɹO θɹˈi zˈɪɹO`) and removes both stray full stops.
Rejected alternative: `v0-3-0` → `vˈiː zˈiəɹoʊ dˈæʃ θɹˈiː dˈæʃ zˈiəɹoʊ` — espeak **voices** the
hyphen as "dash". Do not use hyphens.

### B. Decimals lose the word "point"

| Input | espeak phonemes | Reads as |
| --- | --- | --- |
| `0.24` | `zˈiəɹoʊ.twˈɛnti fˈɔːɹ` | "zero**[.]**twenty four" |
| `0.75` | `zˈiəɹoʊ.sˈɛvənti fˈaɪv` | "zero**[.]**seventy five" |
| `1.5` | `wˈʌn.fˈaɪv` | "one**[.]**five" |
| `0.24x` | `zˈiəɹoʊ.twˈɛnti fˈɔːɹ ˈɛks` | "zero**[.]**twenty four ex" |

**Minimal fix: replace a `.` between two digits with the literal word ` point `.** Verified:

| Rewrite | espeak phonemes |
| --- | --- |
| `It runs at 0 point 24x realtime.` | `ɪt ɹˈʌnz æt zˈiəɹoʊ pˈɔɪnt twˈɛnti fˈɔːɹ ˈɛks ɹˈiːəltaɪm.` |
| `It took 0 point 2 4 seconds.` | `zˈiəɹoʊ pˈɔɪnt tˈuː fˈɔːɹ` — digit-by-digit if the digits are also separated |
| `1,234,567 rows in 1 point 5 seconds.` (with commas stripped) | `wˈʌn mˈɪliən … ɹˈoʊz ɪn wˈʌn pˈɔɪnt fˈaɪv sˈɛkəndz.` |

**A and B conflict and must be ordered.** `\d+(\.\d+){2,}` (version) must be rewritten to spaces
**before** the single-dot decimal rule runs, or `v0.3.0` becomes `v0 3 point 0` — observed while
building the prototype.

Bash or Python: the ordering is fine in `sed`, but "replace *all* dots inside a matched multi-dot
run" is a nested substitution. **Wants Python** (or two `sed` passes with a loop).

### C. The `lives` defect, and what pronunciation-correction mechanisms actually exist

**The defect, and its shape.** espeak's POS disambiguation is a shallow preceding-word rule. `lives`
gets the **verb** reading after a pronoun and the **noun** reading after a noun phrase:

| Input | espeak phonemes | Correct? |
| --- | --- | --- |
| `It lives there.` | `ɪt lˈɪvz ðˈɛɹ.` | yes |
| `He lives here.` | `hiː lˈɪvz hˈɪɹ.` | yes |
| `This lives here.` / `That lives here.` | `lˈɪvz` | yes |
| `The file lives in docs.` | `ðə fˈaɪl **lˈaɪvz** ɪn dˈɑːks.` | **no** |
| `The config lives here.` | `lˈaɪvz` | **no** |
| `The hook lives in rewrite.sh.` | `lˈaɪvz` | **no** |
| `Everything lives here.` | `lˈaɪvz` | **no** |
| `The virtual environment lives in the venv directory.` | `lˈaɪvz` | **no** |
| `the lives of others` (genuine noun) | `lˈaɪvz` | yes |

Seven sentences, and the split is clean: **pronoun subject → correct; anything else → wrong.** That
is why `kokoro-programming-text-audio.md` saw it on two unrelated sentences.

**What mechanisms exist. Answer: none that is practical, and two that are actively harmful.**

| Mechanism | Result | Evidence |
| --- | --- | --- |
| misaki `[text](/phonemes/)` | **harmful** — phoneme string read aloud | rule 12 above |
| espeak's own `[[phonemes]]` escape | **harmful** — letters spelled out | `The file [[lIvz]] in docs.` → `ðə fˈaɪl ˈɛl ˈɪvz ɪn dˈɑːks.` ("E-L I-V-Z"); `[[h@l'oU]]` → `ˈeɪtʃ æt ˈɛlˈoʊ jˈuː`. The escape is honoured by espeak's *synthesiser*, not by `espeak_TextToPhonemes`, which is what `phonemizer` calls. |
| SSML `<phoneme ph="…">` | **harmful** — tag read aloud | → `fˈoʊniːm pˌiːˈeɪtʃ ˈiːkwəlz"ˈɛl ˈɪvz"lˈaɪvz slˈæʃ fˈoʊniːm`. Same for `<say-as>`. `phonemizer` does not enable SSML. |
| espeak-ng **user dictionary** (`en_extra` / recompiled `en_dict`) | **not available without a download** | see below |
| `kokoro-onnx` API | **nothing exposed** | `Tokenizer.phonemize` takes only `text`, `lang`, `norm`. `EspeakConfig` exposes `data_path` and `lib_path` — a *whole data directory*, not a per-word override. |

On the user dictionary specifically, three facts, each checked:

1. `PHONEMIZER_ESPEAK_DATA_PATH` / `EspeakWrapper.set_data_path()` / `EspeakConfig.data_path` do let
   you point espeak at a **different data directory** — so a modified `en_dict` *would* be picked up.
   (`phonemizer/backend/espeak/wrapper.py:119-230`; `kokoro_onnx/tokenizer.py:20-23`.)
2. `espeak_ng_CompileDictionary` **is** exported by the bundled dylib — `nm -gU
   libespeak-ng.dylib` shows `_espeak_ng_CompileDictionary` and `_espeak_CompileDictionary`. So no
   `espeak-ng` binary is needed to compile one; ctypes suffices.
3. **But the dictionary *sources* are not shipped.** `espeakng_loader/espeak-ng-data/` contains only
   compiled `*_dict` blobs — `find` for `*_list`, `*_rules`, `dictsource`, `en_extra` returns
   nothing. Calling `espeak_ng_CompileDictionary` against a writable copy of the data directory
   returns **rc = 2** (no source files). Compiling a custom dictionary therefore requires downloading
   espeak-ng's `dictsource/en_list` and `en_rules`, which is an install and was **not** done
   (metered connection).

**So the practical mechanism is a text-level respelling, and it works.** Verified:

| Rewrite | espeak phonemes |
| --- | --- |
| `The file livz in docs.` | `ðə fˈaɪl **lˈɪvz** ɪn dˈɑːks.` ✅ |
| `The file livves in docs.` | `ðə fˈaɪl lˈɪvz ɪn dˈɑːks.` ✅ |
| `The file liv'z in docs.` | `ðə fˈaɪl lˈɪvz ɪn dˈɑːks.` ✅ |
| `The file lihvz in docs.` | `ðə fˈaɪl lˈɪhvz ɪn dˈɑːks.` ✗ (spurious `h`) |
| `The file, it lives in docs.` | `ðə fˈaɪl, ɪt lˈɪvz ɪn dˈɑːks.` ✅ (rephrase) |
| `The file is in docs.` | `ðə fˈaɪl ɪz ɪn dˈɑːks.` ✅ (avoid the word) |

`livz` is the minimal respelling. A respelling table is a plain word-substitution map — the same
shape as a lexicon, just applied to graphemes instead of phonemes.

**Other mispronounced ordinary words found.** A handful of probes, not a dictionary audit:

| Input | espeak phonemes | Should be | Verdict |
| --- | --- | --- | --- |
| `The tests use live data.` | `ðə tˈɛsts **jˈuːs** lˈaɪv dˈeɪɾə.` | `jˈuːz` | **wrong** — noun reading of the verb |
| `Use it now.` | `**jˈuːs** ɪt nˈaʊ.` | `jˈuːz` | **wrong** |
| `We use it.` / `They use jq.` / `I use it daily.` | `jˈuːz` | | right (pronoun subject) |
| `It uses jq.` | `jˈuːzᵻz` | | right |
| `Close the file.` | `**klˈoʊs** ðə fˈaɪl.` | `klˈoʊz` | **wrong** — adjective reading of the imperative |
| `Please close it.` | `**klˈoʊs** ɪt.` | `klˈoʊz` | **wrong** |
| `It will close soon.` | `klˈoʊz sˈuːn` | | right (after a modal) |
| `I read the file yesterday.` | `aɪ **ɹˈiːd** ðə fˈaɪl` | `ɹˈɛd` | **wrong** — past tense |
| `I read it earlier.` | `**ɹˈiːd**` | `ɹˈɛd` | **wrong** |
| `I have read it.` / `It was read.` | `ɹˈɛd` | | right (after an auxiliary) |
| `Present the results.` | `**pɹˈɛzənt** ðə ɹɪzˈʌlts.` | `pɹɪzˈɛnt` | **wrong** — imperative |
| `I will present them.` | `pɹɪzˈɛnt` | | right |
| `It is a duplicate.` | `dˈuːplᵻkˌeɪt` | `dˈuːplɪkət` | wrong (noun/verb stress) |
| `record`, `object`, `project`, `separate`, `estimate`, `content`, `minute`, `wound`, `refuse`, `route`, `bases` | correct in both readings tried | | fine |

**The pattern is the finding: espeak mis-reads a POS-ambiguous word whenever the disambiguating cue
is anything other than an immediately preceding pronoun, auxiliary, or modal.** `use`, `close` and
`read` are all high-frequency in a coding assistant's prose, so this is not an edge case. It is also
exactly the thing #3 noted misaki's spaCy tagger buys — a real cost of the frontend the ear chose.

Bash or Python: a respelling map is a `sed` script or an `awk` associative array — **bash is fine**.
But the misreadings are **context-dependent**, so an unconditional `lives`→`livz` would also change
`the lives of others` (which is currently *correct*). Getting that right needs a preceding-word
condition. **Wants Python.**

### D. Angle-bracketed tags leak their contents

`The <div> tag.` → `ðə dˈɪv tˈæɡ.` — the brackets are silent but the tag name is spoken. Not a
problem for markdown, but worth knowing if HTML ever reaches the sanitizer.

---

## Candidate rule list, in priority order

**This is input to #8's decision, explicitly NOT the decision.** #8 is blocked by
[#6](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/6) and
[#7](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/7), and every ranking below
is by *measured phoneme damage*, not by how anything sounds. Placement (bash hook vs Python worker)
is [#11](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/11)'s decision; the last
column is evidence for it, not a choice.

Order matters where noted — E must run before F.

| # | Rule | Transformation | Worked example | bash or Python? |
| --- | --- | --- | --- | --- |
| **A** | **Guarantee a chunk boundary** | ensure no run without `. , ! ? ;` exceeds ~400 input chars; insert `.` or `,` | 630 chars of unpunctuated text → `IndexError` → with boundaries, synthesises | **Python** (running count) |
| **B** | **Line breaks → terminal punctuation** | `\n+` → `. ` (or `, `) | `- ran the tests\n- fixed the hook` → `ran the tests. fixed the hook` → `ɹˈæn ðə tˈɛsts. fˈɪkst ðə hˈʊk` | bash |
| **C** | **Strip `*`** | `s/\*\+//g` | `the **bold** change` → `ðɪ bˈoʊld tʃˈeɪndʒ` (was `ˈæstɚɹˌɪskɐstɚɹˌɪsk bˈoʊld …`) | bash |
| **D** | **Strip `#` heading markers** | anchored `s/^ \{0,3\}#\{1,6\} \+//` | `# Summary` → `sˈʌmɚɹi` (was `hˈæʃ sˈʌmɚɹi`) | bash |
| **E** | **Version strings: dots → spaces** | in `\d+(\.\d+){2,}`, every `.` → ` ` | `v0.3.0` → `v0 3 0` → `vˈiː zˈiəɹoʊ θɹˈiː zˈiəɹoʊ` (was `…zˈiəɹoʊ.θɹˈiː.zˈiəɹoʊ`) | Python |
| **F** | **Decimals: dot → " point "** | `(?<=\d)\.(?=\d)` → ` point ` | `0.24x` → `0 point 24x` → `zˈiəɹoʊ pˈɔɪnt twˈɛnti fˈɔːɹ ˈɛks` | bash |
| **G** | **Strip thousands separators** | `(?<=\d),(?=\d{3})` → `` (repeat) | `16,000` → `16000` → `sˈɪkstiːn θˈaʊzənd` (was `sˈɪkstiːn,zˈiəɹoʊzˈiəɹoʊ zˈiəɹoʊ`) | Python (or looped sed) |
| **H** | **Strip emoji** | drop emoji + variation selectors | `change ✅` → `tʃˈeɪndʒ` (was `tʃˈeɪndʒ wˈaɪt hˈɛvi tʃˈɛk mˈɑːɹk`) | Python |
| **I** | **Replace URLs** | `https?://\S+` **and** bare `host.tld/path` → `a link` | `See https://github.com/hexgrad/kokoro for details.` → `sˈiː ɐ lˈɪŋk fɔːɹ diːtˈeɪlz.` | bash |
| **J** | **Lowercase `_`-joined identifiers** | lowercase the whole matched `\w+(_\w+)+` token | `MAX_RETRIES is 3` → `max_retries is 3` → `mˈæks ɹˈiːtɹaɪz ɪz θɹˈiː` (was `ˌɛmˌeɪˈɛks ɹˈiːtɹaɪz`) | Python/awk |
| **K** | **Currency: unit after the number** | `\$(\d+)\.(\d\d)` → `\1 dollars \2`; `\$(\d+)` → `\1 dollars` | `It costs $4.50.` → `It costs 4 dollars 50.` → `ɪt kˈɔsts fˈɔːɹ dˈɑːlɚz fˈɪfti` (was `dˈɑːlɚ fˈɔːɹ.fˈɪfti`) | bash |
| **L** | **Respell mis-POS'd words** | conditional map: `lives`→`livz`, `use`→`youze`?, `close`→?, `read`→`red`?, when not preceded by a pronoun/auxiliary/modal | `The file lives in docs.` → `The file livz in docs.` → `ðə fˈaɪl lˈɪvz ɪn dˈɑːks.` | Python (needs the condition) |
| **M** | **Never emit `[text](/phonemes/)`** | a prohibition, not a transformation | `[lives](/lˈɪvz/)` → `lˈaɪvz(slˈæʃ ˌɛlstɹˌɛss… slˈæʃ)` | n/a |

**Explicitly dropped from #3's list**, because they are no-ops or harms on this frontend:

- split `SCREAMING_SNAKE_CASE` on `_` — **no-op**, verified byte-identical on 8 identifiers.
- insert a comma into bare 4-digit numbers — **harmful**; rule G is its inverse.
- strip backticks — **no-op**, espeak emits nothing for them.
- strip `_` / `-` / `>` / `|` / `--flags` — **no-op**, all already silent.
- rewrite a bare `-p` flag (the misaki `)` injection) — **no-op**, espeak is clean.
- preserve `\n` as a boundary — **inverted**; rule B replaces it.
- runtime lexicon injection, `[text](/phonemes/)` — **do not exist** on this path.

**Left open for #8, because they are listening calls this document cannot make:** whether paths
(`~/.local/share/kokoro/venv` → "tilde slash dot local slash share slash kokoro slash venv") and
leading slashes should be spoken at all, whether `. ` or `, ` is the right line-break replacement,
how a skipped code block is announced, and whether the sanitizer wins against a parallel LLM call at
all.

---

## Could not establish

- **Anything about how any of this sounds.** No audio was auditioned. Two wav files were written
  during the long-input test and immediately discarded. Every "better"/"worse" word above is about
  phoneme count, word identity, or an exception.
- **Whether rule L can be made safe.** `lives`→`livz` is verified to work *when applied*, but the
  correct trigger condition is not established — an unconditional substitution would also change
  `the lives of others`, which espeak currently gets **right**. The preceding-word rule
  (pronoun/auxiliary/modal → leave alone) fits all 7 `lives` probes, 5 `use` probes, 4 `close` probes
  and 4 `read` probes, but 20 sentences is not a specification. **espeak's `en_list`/`en_rules` were
  not read**, so no rule is derived from source. And the respellings for `use`, `close` and `read`
  were **not found** — only the defects were.
- **How many other ordinary English words espeak mis-reads.** The probe set was ~55 sentences chosen
  to cover POS-ambiguous words a coding assistant uses. It is not an audit and no coverage claim is
  made.
- **Whether a custom espeak dictionary is viable.** The mechanism exists (`data_path` override +
  `espeak_ng_CompileDictionary` in the bundled dylib) but the sources do not ship and were not
  downloaded. `rc = 2` from a compile attempt is the whole evidence. Nothing is known about how large
  `en_list`/`en_rules` are, how long a compile takes, or whether a worker could do it at startup.
- **Whether the emoji character class in rule H is complete.** Five emoji were tested. ZWJ family
  sequences, skin-tone modifiers and regional-indicator flags were not.
- **Where the ~400-character boundary for rule A should actually sit.** ~1.02 phonemes per character
  was measured on plain prose only. Path- and identifier-heavy text phonemises longer per character
  (a URL is ~2.5×), so the safe margin for real rewrite output is unmeasured.
- **`create_stream()`.** Only `create()` was exercised. `create_stream` calls the same
  `_split_phonemes` and `_create_audio`, so the `IndexError` should reproduce, but that was not
  tested.
- **British English.** `en-us` throughout.
- **Whether the `IndexError` is fixed upstream.** The installed `kokoro-onnx` was read as found; no
  issue tracker was checked.

## Reproducing

One throwaway harness in the session scratchpad (not committed) plus the snippet in
[Method](#method). The single piece worth keeping verbatim is the vocab-filtered phonemiser, because
comparing unfiltered espeak output to what the model receives is what makes a `\n` finding invisible:

```py
raw = phonemizer.phonemize(text.strip(), "en-us", preserve_punctuation=True, with_stress=True)
filtered = "".join(filter(lambda p: p in DEFAULT_VOCAB, raw)).strip()
dropped  = sorted(set(raw) - set(filtered) - {" "})   # <- this is where \n showed up
```

For the chunking and 510 findings, load the real model and inspect the batching before synthesising:

```py
kok = Kokoro(f"{K}/kokoro-v1.0.onnx", f"{K}/voices-v1.0.bin")
ph  = kok.tokenizer.phonemize(text, "en-us")
print(len(ph), [len(b) for b in kok._split_phonemes(ph)])   # any batch >= 510 will raise
```
