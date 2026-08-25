# Sanitizer follow-ups: the listening script for #13

The audio [#13](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/13) was decided
from. Built 2026-08-25, on top of the set
[#8](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/8) settled the same day —
see [`sanitizer-audition.md`](sanitizer-audition.md), whose **DECISION** block and three listener
notes are what created this ticket.

**STATUS: decided. #13 is closed.** The [DECISION](#decision-2026-08-25) at the end is filled in —
all three rules adopted, on verdicts recorded 11:27–11:37 UTC on 2026-08-25 and committed as
[`audition-verdicts-13.tsv`](audition-verdicts-13.tsv).

**Everything before that DECISION is the listening script as it was written, and it stays that way on
purpose.** It decides nothing and contains no claim about how anything sounds: every "what it does" is
a text diff, a phoneme string or a duration, and every "what to listen for" is a question that had
not yet been answered when it was written. Read it as the instrument; read the DECISION for the
result.

**#8's seven axes are not reopened.** Two of its three listener notes asked for rules that had never
been auditioned, and its "still open" list named one combination it could not measure. That is all
that is here:

| # | what | pairs | minutes | why it is here |
| --- | --- | ---: | ---: | --- |
| 8 | commas around flag names and bare identifiers | 7 | ~3 | the note on `s15:scream-drop` — a generalisation of axis 1's winning `tick-pause` |
| 9 | pronounceable file extensions | 7 | ~4 | the note on `s10:path-expand` — "`hooks.json` should become 'hooks dot json'" |
| 3 | `path-shorten` combined with `path-nolead` | 6 | ~3 | #8's own "still open" list: both undefeated, never heard together |

**20 pairs, ~10 minutes of audio to play through** (34 distinct wavs, 8.1 minutes; a `base` wav is
played once per pair it appears in). This document takes them in the order #13 raises them; **the
page puts axis 3 first**, because it sorts by #8's axis numbering and axis 3 is an existing axis
rather than a new one. Same pairs either way.

The third note (`s12:path-shorten`, "if the original text is shown but B is the spoken text") needed
no audio: it is a spec statement about the display path, and it belongs in
[#11](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/11), not here.

---

## How to listen

The pairs are **section 4** of the same local page #8 was decided on. It carries #8's 67 pairs and
#9's and #10's sections too, all already judged; section 4 is the new part.

```bash
cd ~/.local/share/kokoro/bench && python3 -m http.server 8765
# then open http://localhost:8765/audition.html
```

That is the route that was **verified end to end** on 2026-08-25: page renders, every `<audio src>`
resolves 200, a verdict click persists to `localStorage` under the key `claudish-audition/v1`, and a
reload restores it. `open ~/.local/share/kokoro/bench/audition.html` also works in Safari, but
`file://` audio is blocked outright in some browsers and **`localStorage` is per origin** — if the
#8 verdicts were recorded over `file://` they will not be visible over `http://localhost:8765`, and
the progress counter will read low. The #8 verdicts are already exported to
[`audition-verdicts.tsv`](audition-verdicts.tsv), so nothing is lost either way; open it the same way
as last time if you want the counter to make sense.

Regenerate the page or any row — the wavs are not committed (22 MB for this set, no LFS here):

```bash
python3 bench/audition-page.py                                   # rebuild the page from the wavs
bench/bench --id s28 -s base,flag-pause -v bf_emma --show-text --play none
bench/bench --id s10 -s base,ext-word -v bf_emma                 # plays each in turn
bench/bench --list-sanitizers                                    # all 26 variants + rule order
```

### The voice is `bf_emma`, and that is why this is a separate section

Every wav in #8's section 1 is `af_heart`, **the voice #9 rejected**. #13's wavs are `bf_emma`, the
voice #9 chose. They live in their own directory —
`~/.local/share/kokoro/bench/audition-13/<item>.<variant>.bf_emma.wav` — and the page builds them as
their own section, because merging them into section 1 would have silently paired an `af_heart`
reference against a `bf_emma` variant and the pair would no longer have isolated the rule.

**Nothing in section 4 is comparable with a section 1 wav.** Section 4 is internally consistent:
both sides of every pair are `bf_emma`.

### The three things every pair contains

Unchanged from #8, and deliberately so:

- **`none`** — the control, the text handed to Kokoro untouched. Present in every axis below.
- **`base`** — the reference: the `candidate` pipeline with #8's original default on every open axis.
  **Not** the settled sanitizer. `base` still keeps backticks, still does nothing to paths, still
  reads code blocks out. Keeping it is what makes a #13 pair readable the same way a #8 pair was:
  one axis moved against a fixed point.
- **the variant** — `base` with exactly one axis moved.

Using `base` rather than #8's settled combination has a cost worth stating: on an item that carries
backticks, axis 8's commas are heard against a no-comma backtick background, not against
`tick-pause`. The rule steps over backticked spans (see below), so the pair is still a clean
one-axis test — but "how the two comma rules sound *together*" is not on this page.

---

## Axis 8 — commas around flag names and bare identifiers

The note, verbatim, left on `s15:scream-drop`:

> "B would be even better if it gets a comma before and after the flag name I think, like what you
> did with variables in `backticks`"

Axis 1 chose `tick-pause` and established that **the win was the commas, not the backtick removal**
(`tick-strip` is phoneme-identical to leaving the backticks in). So `flag-pause` applies the
identical treatment — the same `_set_off` helper `tick-pause` uses, extracted so the two cannot drift
— to the code tokens that carry **no** backticks.

Three shapes, and no more:

| shape | examples | note |
| --- | --- | --- |
| a flag | `-p`, `-R`, `--max-time`, `--strict-mcp-config` | the text is untouched; only commas are added |
| an assignment | `CLAUDISH_ENABLED=0`, `curl_rc=28`, `http=429` | |
| a `_`-joined identifier | `curl_rc`, `CLAUDISH_MIN_CHARS` | exactly rule J's set |

Bare acronyms (`RAM`, `SHA-256`) and camelCase are **not** in it, for the reason #1 gives for
narrowing rule J the same way: widening regresses ordinary words, and `GitHub` satisfies every
camelCase test there is. Paths and filenames are axis 3's and axis 9's business.

**Backticked spans are stepped over, not matched inside.** Under `base` (backticks kept) a
`` `--flag` `` is left alone, so this axis and axis 1 stay independent.

### What it does to the text

`s28` — the only corpus item carrying `FLAG-SHORT` and `FLAG-LONG`:

```
base        I passed --max-time 30 and -p to curl. Use -R to name the repo, add
            --strict-mcp-config so no servers load, and -q if you want it quiet.
flag-pause  I passed , --max-time, 30 and , -p, to curl. Use , -R, to name the repo, add
            , --strict-mcp-config, so no servers load, and , -q, if you want it quiet.
```

`s15` — the item the note was written on (`base` has already lowercased the identifiers, rule J):

```
base        Raise claudish_min_chars if short replies are getting spoken.
            claudish_speak_off_file points at the runtime off switch, anthropic_api_key is
            read only as a fallback, and max_retries is ignored entirely.
flag-pause  Raise , claudish_min_chars, if short replies are getting spoken.
            , claudish_speak_off_file, points at the runtime off switch, anthropic_api_key,
            is read only as a fallback, and , max_retries, is ignored entirely.
```

Two things to notice in that second diff, both deliberate and both inherited from `tick-pause`:
`anthropic_api_key` gets **no** leading comma, because the sentence already had one there and the
double is collapsed; and the comma lands after the space (`Raise , claudish...`), which is exactly
what the winning `tick-pause` output looks like — whitespace is not a phoneme.

`s17` shows the narrowing at work: `snake_case` and `min_chars` are set off, while `camelCase`,
`kebab-case`, `getUserById` and `minChars` are not.

### The finding that matters more than the wavs

**No real rewrite carries an un-backticked flag or `_`-joined identifier. Zero of twelve.**

Every code token in the 12 real rewrites is either inside backticks (`` `$CLAUDISH_OLLAMA` ``,
`` `curl -K` ``, `` `chunks=2` ``) or is camelCase / an acronym, which this rule declines. `r04`,
`r11` and `r12` carry `ID-SNAKE` / `ID-SCREAM` / `ID-ASSIGN` in `corpus/classes.tsv` — and in all
three the tokens are backticked, so `flag-pause` is a **measured no-op** on all three.

That does not make the rule pointless — the settled sanitizer keeps `tick-pause`, so on real output
those tokens already get their commas *via the backticks*. What this rule catches is the residue,
and the corpus says the residue is rare. It is decision-relevant either way, so it is stated up
front rather than discovered afterwards.

The consequence for the listening: **this axis is decided on synthetic fixtures.** `s28`, `s15`,
`s16` and `s17` are the informative pairs; the two real-corpus pairs (`r04`, and `s03` alongside it)
are byte-identical controls.

### What to listen for

- Does setting a flag off with commas make it easier to hear as a name rather than as prose?
- `s28` puts five of them in two sentences. Is that better, or is it a stutter?
- `s16`'s assignments (`claudish_enabled=0`) already read as three tokens. Do commas help there or
  fragment them further?
- `s17` is the mixed case: two tokens set off, four left alone in the same sentence. Does the
  inconsistency draw attention to itself?

| pairs | items |
| --- | --- |
| 7 (2 of them byte-identical controls) | `s28`, `s15`, `s16`, `s17`, and `s03` + `r04` as controls |

---

## Axis 9 — pronounceable file extensions

The note, verbatim, left on `s10:path-expand`:

> "`hooks.json` should become 'hooks dot json' so that 'json' is pronounced"

`path-expand` spells every extension — `.md` becomes " dot M D", and by the same rule `.json` would
become " dot J S O N". The axis-3 winner `path-shorten` does not touch extensions at all. So neither
settled variant does what the note asks.

### The rule needs no pronunciation table, and that is measured

The obvious implementation is a list of which extensions are words and which are letters. #13 says
as much ("`.sh` is probably 'S H'; `.json` probably 'jason'"). **It is not needed.** For all 23
extensions the sanitizer recognises, espeak's reading of the extension is byte-identical after a `.`
and after the word "dot", and it is already right in every case:

| written | espeak phonemes | reads as |
| --- | --- | --- |
| `foo.json` / `foo dot json` | `dʒˈeɪsˈɑːn` | "jason" |
| `foo.sh` / `foo dot sh` | `ˌɛsˈeɪtʃ` | "S-H" |
| `foo.py` / `foo dot py` | `pˈaɪ` | "pie" |
| `foo.md` / `foo dot md` | `ˌɛmdˈiː` | "M-D" |
| `foo.sql` / `foo dot sql` | `ˌɛskjˌuːˈɛl` | "sequel" |
| `foo.yaml` / `foo dot yaml` | `jˈæməl` | "yamel" |
| `foo.log`, `foo.wav`, `foo.lock` | `lˈɔɡ`, `wˈæv`, `lˈɑːk` | words |
| `foo.tsv`, `foo.csv`, `foo.html` | `tˌiːˌɛsvˈiː`, … | letters |

**Spelling them out is what breaks them.** `dot J S O N` is `dʒˈeɪ ˈɛs ˈoʊ ˈɛn`; spelled `log` is
"L-O-G", spelled `wav` is "double-U-A-V", spelled `py` is "P-Y" instead of "pie". That is precisely
the complaint the note makes about `path-expand`.

So `ext-word` does **one** thing: the `.` in `name.ext` becomes the word "dot", and the extension is
handed to espeak untouched. That removes the sentence-final mark `PATH-EXT` is about — espeak keeps
the literal `.`, which reaches the model as a full stop mid-sentence — and leaves the pronunciation
to the frontend that already gets it right.

Two stated limits. A **bare** extension (`.sh` with no name in front of it) is left alone: that is
`PATH-EXTBARE`, a documented control class where both frontends already agree, so `s09` — "It
handles .sh, .py, .md, .json and .wav files." — is a byte-identical control here rather than a test.
And espeak reads `yml` as "immel"; no variant on this page fixes that, and spelling it is the only
thing that would.

### What it does to the text

```
s10  base      The hook is registered in hooks/hooks.json, and I wrote the findings to
               docs/research/kokoro-deployment.md. …
     ext-word  The hook is registered in hooks/hooks dot json, and I wrote the findings to
               docs/research/kokoro-deployment dot md. …

s08  base      I renamed rewrite-md.sh but left README.md alone. …
     ext-word  I renamed rewrite-md dot sh but left README dot md alone. …
```

The slashes are still spoken as "slash" — that is axis 3's question, not this one.

### What to listen for

- Is "hooks dot json" better than espeak's "hooks. jason", where the `.` plants a full stop?
- `s08` has five extensions in three sentences (`.sh` ×3, `.md` ×2). Does saying "dot" five times
  get tiring faster than the mid-sentence full stops it replaces?
- `r03` and `r06` are the real-corpus check, one `.json` and one `.md`, both inside longer prose.

| pairs | items |
| --- | --- |
| 7 (2 of them byte-identical controls) | `s08`, `s10`, `s13`, `r03`, `r06`, and `s09` + `r03:none` as controls |

---

## Axis 3 — `path-shorten` and `path-nolead`, heard together

#8's DECISION chose `path-shorten` (3–0, undefeated) and recorded that `path-nolead` is *also*
undefeated (2–0) but is a different transformation that was never heard combined with it. This is
that combination, `path-short-nolead`.

**It is a smaller difference than it sounds.** `path-shorten` already drops a leading `~/`, `/` or
`./` — only `path-expand` re-attaches the lead — so the entire audible difference between the
combination and `path-shorten` alone is **the bare dot on whichever segment survives first**:

```
s12  path-shorten       … off right now because .claude/claudish-off exists …
     path-short-nolead  … off right now because claude/claudish-off exists …

s13  path-shorten       The permission lives in .claude/settings.json now, and the plugin
                        manifest is in .claude-plugin/plugin.json. …
     path-short-nolead  The permission lives in claude/settings.json now, and the plugin
                        manifest is in claude-plugin/plugin.json. …
```

Measured over the four items on this page:

| item | combination vs `path-shorten` | combination vs `path-nolead` |
| --- | --- | --- |
| `s11` | **identical** | differs |
| `s12` | **differs** — `.claude/` → `claude/` | differs |
| `s13` | **differs** — `.claude/`, `.claude-plugin/` | **identical** (both paths are only two segments deep) |
| `r06` | **identical** | differs |
| `s09` | identical (no path in the item at all) | identical |

So the axis has **two discriminating pairs** (`s12`, `s13`) and two pairs (`s11`, `r06`) that are a
re-run of `path-shorten` itself under the new voice — which is worth having, since `s11` never had a
`path-shorten` wav in #8 at all. `s13` is new to the audition entirely.

### What to listen for

- Is "claude slash settings dot json" better than "dot claude slash settings dot json"?
- `s13` is the `PATH-DOTDIR` fixture: three dotfile paths in two sentences. If the leading dot is
  noise anywhere, it is there.
- On `s11` and `r06` the two sides are `path-shorten` against `base`, which #8 already judged on
  `af_heart`. Hearing it again on `bf_emma` is a free re-confirmation, not a new question.

| pairs | items |
| --- | --- |
| 6 (1 of them a byte-identical control) | `s11`, `s12`, `s13`, `r06`, `r06:none`, and `s09` as the control |

---

## Calibration — 6 of the 20 pairs are the same wav twice

#8's session put 12 byte-identical pairs in front of the listener without saying which they were, and
**11 of 12 were correctly called "no audible difference"; 1 was not.** That measured the resolution
limit of the whole exercise at roughly **1 call in 12 is noise**, and it is why axis 2 of #8 was
recorded as *not settled* rather than as a narrow win. (Axis 2 has since been settled directly, by
ear, and its "1–1 tie" turned out to be a mis-posed axis rather than a noise-floor problem — see
["Axis 2 is settled"](#axis-2-is-settled--and-not-by-either-variant-on-either-page) below.)

This session keeps the same instrument. **6 of the 20 pairs are byte-identical wavs**, one per axis
at minimum, and the page does not say which:

| pair | axis | why it is identical |
| --- | --- | --- |
| `r04:flag-pause` | 8 | every identifier in `r04` is backticked, so the rule declines it |
| `s03:flag-pause` | 8 | same — `s03` is all backticks |
| `s28:none` | 8 | `s28` is one line of plain prose, so `base` itself is a no-op on it |
| `s09:ext-word` | 9 | bare extensions are left alone by design |
| `r03:none` | 9 | `base` changes `r03`'s text but not its phonemes |
| `s09:path-short-nolead` | 3 | `s09` contains no path |

Byte-identity was verified two ways: the phoneme strings compare equal under kokoro-onnx's own
tokenizer, and the wav files hash equal. Synthesis was also confirmed **deterministic across
processes** — the same text and voice re-synthesized in a separate run produced a byte-identical wav
— which is what makes "identical text ⇒ identical audio" safe to rely on here.

"No audible difference" is a correct answer on those six. On the other fourteen it is also a real
answer: 6 of 20 phonemise identically, so the page says so in aggregate without saying which.

---

## What this audition cannot settle

- **Anything about how any of it sounds.** Nothing here was played back while it was built.
- **How the two comma rules sound together.** `flag-pause` is `base` + commas on bare tokens;
  the settled sanitizer will also have `tick-pause`. Both use the same helper, so they cannot
  disagree about *where* a comma goes — but an item with four backticked spans and two bare flags
  was never synthesized with both rules on.
- **Whether axis 8's rule is worth its risk on real output**, beyond the 0-of-12 carrier count. The
  corpus is 12 real rewrites from one machine and one week; a different assistant style could put
  bare flags in every message.
- **The `yml` reading.** espeak says "immel" and nothing here changes it.
- **`.py` as "pie" versus "P-Y".** Measured, not auditioned: `ext-word` keeps espeak's "pie". If
  "P-Y" is wanted, that is a pronunciation table, and this rule deliberately has none.
- **Deeper leading-dot paths.** `s12` and `s13` are the only corpus items with a bare-dot directory
  segment, and in `s13` the paths are only two segments deep, so `path-nolead` and the combination
  are identical there. A `.github/workflows/ci.yml`-shaped path is not in the corpus.
- **Axis 2 of #8** (`.` versus `,` as the line-break replacement) stays inconclusive. No variant
  here touches it.
- **Rule L** stays gated behind `--respell`, unauditioned, still mis-firing on "the lives of
  others". `s12` and `s13` on this page carry `PROSE-LIVES`-adjacent prose but no variant includes
  rule L, so no wav here is affected by it.

---

## Confirmation measurement: first-sentence TTFA on `bf_emma`

Not part of the audition. #9's half-A table — the measurement that says first-sentence pipelining
clears the 3-second tolerance — was taken entirely on **`af_heart`, the voice #9 then rejected**, and
[`voice-and-pipelining.md`](voice-and-pipelining.md) closes by saying the margin "should be
re-checked on `bf_emma` before the 3-second margin is treated as banked". This is that re-check.

Same script, same definition, same corpus: `bench/first-sentence.py`, `TTFA = sanitize +
Kokoro.create() + soundfile.write() + player spawn`, all 12 real rewrites, `candidate` sanitizer,
warm, `--play none` (so spawn is 0.0 ms and every figure is a lower bound by the 15–20 ms
`bench.py` measured for a real `afplay`).

```bash
~/.local/share/kokoro/venv/bin/python bench/first-sentence.py -v bf_emma --stream --whole
```

| item | chars | first: chars | **`bf_emma` first** | `af_heart` first (#9's published) | `af_heart` first (re-run today) | `bf_emma` stream | `bf_emma` whole | whole: audio, `bf_emma` / `af_heart` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `r01` | 268 | 88 | **1.20 s** ✅ | 1.22 s | 1.24 s | 3.28 s ❌ | 3.39 s ❌ | 15.1 / 16.5 s |
| `r02` | 275 | 62 | **0.90 s** ✅ | 0.85 s | 0.83 s | 3.32 s ❌ | 3.44 s ❌ | 15.2 / 16.9 s |
| `r03` | 334 | 62 | **0.88 s** ✅ | 0.78 s | 0.79 s | 4.23 s ❌ | 4.36 s ❌ | 19.0 / 20.8 s |
| `r04` | 369 | 19 | **0.57 s** ✅ | 0.41 s | 0.40 s | 4.82 s ❌ | 4.83 s ❌ | 22.2 / 24.2 s |
| `r05` | 639 | 27 | **0.44 s** ✅ | 0.39 s | 0.39 s | 4.99 s ❌ | 6.97 s ❌ | 32.1 / 34.5 s |
| `r06` | 611 | 64 | **0.84 s** ✅ | 0.89 s | 0.78 s | 5.16 s ❌ | 6.97 s ❌ | 32.7 / 34.7 s |
| `r07` | 669 | 64 | **0.89 s** ✅ | 0.88 s | 0.88 s | 5.22 s ❌ | 9.21 s ❌ | 43.7 / 47.0 s |
| `r08` | 784 | 87 | **1.14 s** ✅ | 1.14 s | 1.14 s | 5.25 s ❌ | 9.27 s ❌ | 42.3 / 45.5 s |
| `r09` | 1176 | 65 | **0.83 s** ✅ | 0.85 s | 0.87 s | 4.98 s ❌ | 13.27 s ❌ | 62.5 / 67.7 s |
| `r10` | 1564 | 32 | **0.58 s** ✅ | 0.50 s | 0.48 s | 4.83 s ❌ | 21.36 s ❌ | 93.1 / 101.9 s |
| `r11` | 2370 | 42 | **0.81 s** ✅ | 0.54 s | 0.52 s | 7.03 s ❌ | 36.83 s ❌ | 142.5 / 153.9 s |
| `r12` | 2897 | 72 | **1.03 s** ✅ | 1.05 s | 1.03 s | 4.98 s ❌ | 35.42 s ❌ | 162.4 / 172.8 s |
| | | **pass** | **12 / 12** | 12 / 12 | 12 / 12 | 0 / 12 | 0 / 12 | |
| | | median | **0.86 s** | 0.85 s | 0.81 s | 4.98 s | 8.09 s | |
| | | max | **1.20 s** | 1.22 s | 1.24 s | 7.03 s | 36.83 s | |

RTF: `stream` 0.209–0.288 and `whole` 0.211–0.258, inside the 0.22–0.29 band #6 calls a quiet
machine. The `first` rows read 0.234–0.388 — the two above 0.30 are `r04` and `r11`, whose first
sentences are 1.6 s and 2.1 s of audio, so the fixed per-call overhead dominates. That is an
artefact of dividing by a very short duration, not contention: the `af_heart` control taken minutes
later on the same machine reproduced **#9's published figures to within 0.04 s on every item**
(0.39 / 0.81 / 1.24 against 0.39 / 0.85 / 1.22, RTF 0.224–0.277).

**Confirmed. First-sentence TTFA on `bf_emma` is 12/12 under the 3-second tolerance, median 0.86 s,
worst item 1.20 s — a 2.5× margin, and indistinguishable from `af_heart`.** Half A's conclusion
stands as written and needs no revision.

Three details worth keeping:

- **`bf_emma` is not slower.** Per item it is within ±0.1 s of the `af_heart` control on 9 of 12
  items. `r11` is the exception (0.81 s against 0.52 s) and it is noise, not the voice: across four
  runs today `r11`'s first sentence measured 0.60 s, 0.70 s, 0.77 s and 0.81 s. Sub-2-second items
  vary by ±0.2 s run to run; the long items do not.
- **#9's predicted duration ratio is confirmed.** Summed over the 12 whole messages, `bf_emma`
  produces 683 s of audio against `af_heart`'s 736 s — **0.927×**, against the 0.92× #9's
  voice table predicted from four items.
- **Pipelining is still required, by the same margin.** Whole-message TTFA fails 12/12 on `bf_emma`
  (3.39 s – 36.83 s) and `create_stream()`'s first chunk fails 12/12 (3.28 s – 7.03 s), both the
  same shape as `af_heart`'s. Without pipelining `r11` and `r12` still never speak inside a
  30-second ceiling.
- **The known trap did not fire.** `first_sentence()` runs on the sanitizer's *output*, not on the
  raw text, so `r10`'s first full stop is not the one inside `**…find.**`: its sentence one is 32
  characters and 0.58 s, not 219 characters and 3.58 s. That ordering is a property of
  `bench/first-sentence.py` as written and was verified, not assumed.

---

## Appendix: what was measured

34 wavs, 8.1 minutes of audio, 20 pairs. `bf_emma` at speed 1.0 throughout, `--play none`. One row
per wav; `phon` phonemes, `audio_s` the length of the audio. **No latency column** — every duration
here is a length of audio, which machine contention does not affect, and the latency question is the
section above, measured on its own with its own RTF check.

| axis | item | variant | chars in | chars out | phon | audio_s |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 3 paths | `r06` | `none` | 611 | 611 | 654 | 33.1 |
| 3 paths | `r06` | `base` | 611 | 608 | 645 | 32.7 |
| 3 paths | `r06` | `path-short-nolead` | 611 | 603 | 632 | 31.6 |
| 3 paths | `s09` | `base` | 48 | 47 | 69 | 3.6 |
| 3 paths | `s09` | `path-short-nolead` | 48 | 47 | 69 | 3.6 |
| 3 paths | `s11` | `base` | 144 | 143 | 199 | 11.5 |
| 3 paths | `s11` | `path-short-nolead` | 144 | 132 | 158 | 8.9 |
| 3 paths | `s12` | `base` | 189 | 188 | 257 | 14.7 |
| 3 paths | `s12` | `path-short-nolead` | 189 | 168 | 196 | 10.6 |
| 3 paths | `s13` | `base` | 145 | 144 | 175 | 10.0 |
| 3 paths | `s13` | `path-short-nolead` | 145 | 142 | 171 | 9.9 |
| 8 flags | `r04` | `base` | 369 | 368 | 440 | 22.2 |
| 8 flags | `r04` | `flag-pause` | 369 | 368 | 440 | 22.2 |
| 8 flags | `s03` | `base` | 185 | 184 | 206 | 11.2 |
| 8 flags | `s03` | `flag-pause` | 185 | 184 | 206 | 11.2 |
| 8 flags | `s15` | `base` | 203 | 202 | 228 | 12.4 |
| 8 flags | `s15` | `flag-pause` | 203 | 212 | 238 | 12.8 |
| 8 flags | `s16` | `base` | 162 | 161 | 248 | 12.7 |
| 8 flags | `s16` | `flag-pause` | 162 | 169 | 256 | 13.2 |
| 8 flags | `s17` | `base` | 144 | 143 | 172 | 9.5 |
| 8 flags | `s17` | `flag-pause` | 144 | 148 | 177 | 9.6 |
| 8 flags | `s28` | `none` | 137 | 137 | 167 | 8.7 |
| 8 flags | `s28` | `base` | 137 | 136 | 167 | 8.7 |
| 8 flags | `s28` | `flag-pause` | 137 | 151 | 182 | 9.1 |
| 9 exts | `r03` | `none` | 334 | 334 | 369 | 19.0 |
| 9 exts | `r03` | `base` | 334 | 333 | 369 | 19.0 |
| 9 exts | `r03` | `ext-word` | 334 | 337 | 375 | 19.1 |
| 9 exts | `r06` | `ext-word` | 611 | 612 | 651 | 32.9 |
| 9 exts | `s08` | `base` | 148 | 147 | 193 | 11.2 |
| 9 exts | `s08` | `ext-word` | 148 | 167 | 223 | 12.2 |
| 9 exts | `s09` | `ext-word` | 48 | 47 | 69 | 3.6 |
| 9 exts | `s10` | `base` | 172 | 171 | 225 | 12.8 |
| 9 exts | `s10` | `ext-word` | 172 | 183 | 243 | 12.9 |
| 9 exts | `s13` | `ext-word` | 145 | 152 | 187 | 10.6 |

No wav in this set crashed and none came near the 510-phoneme ceiling: the largest batch reported
anywhere is **500**, `r06` under `ext-word`.

---

## DECISION (2026-08-25)

Settled by Francis listening to section 4 blind, one sitting, 11:27–11:37 UTC on 2026-08-25 — the
same day as #8's session and on the same page. Verdicts exported to
`~/.local/share/kokoro/bench/audition-verdicts-round-2.tsv` and committed beside this document as
[`audition-verdicts-13.tsv`](audition-verdicts-13.tsv).

Read that file's other sections with the origin caveat in mind: its `sanitizer`, `voice` and `length`
blocks are the #8/#9/#10 pairs re-rendered by the page and are **almost entirely unjudged in this
export** (`progress: 20/87` in its header — and one of that 20 is the artefact named just below)
because `localStorage` is per origin and #8's sitting was recorded on the other one. Nothing is lost — those verdicts are
[`audition-verdicts.tsv`](audition-verdicts.tsv), 67/67 and 4/4 and 27/27 — and **nothing in this
DECISION is derived from any row outside `section = sanitizer-13`.**

One row in this export is an artefact and is worth naming, because it looks like evidence and is not.
`r06:none` is the only pair id that appears in both section 1 and section 4, and the page keyed its
verdict store on the pair id alone — so the single section-4 click at `11:27:54.486Z` wrote **both**
rows. The `section = sanitizer` copy of `r06:none` was never listened to in this sitting: its wavs are
`af_heart` and section 4's are `bf_emma`. That is also why the header reads `progress: 20/87` for
**19** verdicts. It agrees with #8's own `af_heart` verdict on that pair (recorded at `08:12:30.285Z`
in [`audition-verdicts.tsv`](audition-verdicts.tsv)), but that agreement is a coincidence of the copy,
not a second hearing. Nothing in the tallies below reads the duplicated row.
`bench/audition-page.py` now namespaces the store key by section, so this cannot recur.

**19 of the 20 pairs judged.** The twentieth is `s03:flag-pause`, one of the six byte-identical
controls; it was left unjudged and **no verdict has been invented for it**. The tallies below exclude
the five *judged* control pairs, which carry no signal.

**All three rules are adopted. None of them lost a single pair.**

| axis | decision | margin | what the margin is made of |
| --- | --- | --- | --- |
| 9 extensions | **`ext-word`** — the `.` in `name.ext` becomes the word "dot" | **5–0** | `r03`, `r06`, `s08`, `s10`, `s13`. **Two of the five are real rewrites**, and the rule fires on 5 of the 12 real items (`r03`, `r06`, `r10`, `r11`, `r12`) — the strongest real-output mandate on this page |
| 8 flags and bare identifiers | **`flag-pause`** — set them off with axis 1's commas | **4–0** | `s15`, `s16`, `s17`, `s28`. **All four synthetic.** The one real pair, `r04`, was a measured byte-identical no-op — the caveat below is load-bearing, not decorative |
| 3 paths | **`path-short-nolead`** — last two segments, and no leading bare dot | **4–0** | `r06`, `s11`, `s12`, `s13` — but **only `s12` separates the combination from both of its parents**. See below |

For the record, the two reference points: `base` went **1–13** and the `none` control **0–1**.
`base`'s single win is `r06:none` — sanitized beat unsanitized on a real rewrite — which re-confirms
#8's "sanitizing beats not sanitizing everywhere it was tested" on `bf_emma` rather than on the voice
#9 rejected.

### Calibration — the noise floor of *this* session

6 of the 20 pairs were the same wav against itself, blinded, and the page did not say which. Five of
the six were judged, and **all five were called "no audible difference"** — correctly. The sixth
(`s03:flag-pause`) was not judged.

**That is not evidence of a better ear than #8's.** #8 measured 11 of 12 controls correct, which set
the resolution limit at roughly **1 wrong call in 12**. Five trials cannot distinguish 0-in-5 from
1-in-12: at #8's rate, five clean controls happen about two thirds of the time. The floor for this
session is therefore **inherited, not improved** — still about 1 call in 12 is noise. Every margin
above is 4 or 5 unanimous calls in the same direction, several times that floor. **Nothing here is
decided inside the noise**, and nothing here licenses re-reading a narrow #8 margin as a win.

### Listener notes this round: none — and that was checked

The `note` column is **empty on all 20 rows of section 4**. This is stated rather than passed over
because #8's write-up was nearly closed without reading the three listener notes sitting in its
export — same file, same column — and those three notes are the whole reason #13 exists. "No notes"
here is a checked fact, not an absence of looking.

### The three questions this document said the decision had to answer

**1. Axis 8, with 0 of 12 real carriers — does it ship, or wait for a real carrier?**

**It ships. The reason it safely can is the same reason it is worth little today.** `flag-pause` is a
measured no-op on **all twelve** real rewrites — not only on the three that carry `ID-*` classes.
(Verified by running the variant and `base` over `corpus/spoken/r01`–`r12` and comparing:
byte-identical, twelve for twelve.) Adopting it cannot change a single word of today's real output,
so it carries no measurable regression risk, and its 4–0 is not the artefact of an inattentive ear —
the same sitting called five byte-identical controls correctly.

**But its value is entirely contingent on output shapes that have not yet occurred in production.**
All four discriminating pairs are synthetic fixtures (`s15`, `s16`, `s17`, `s28`). **No real message
in the corpus exercises this rule at all.** Every flag and `_`-joined identifier in the 12 real
rewrites already sits inside backticks, where the settled `tick-pause` sets it off — so on real
output those commas are already there, put there by a different rule.

This is the same class of gap as `MD-FENCE-MULTI`: a rule justified by fixtures the corpus builder
wrote, waiting for the real world to produce the shape. It is recorded as a **live caveat, not a
footnote.** If a future capture puts a bare flag in a real message, axis 8's behaviour on it is known
only from four synthetic items, and the question `s28` raises — five commas in two sentences, help or
stutter? — has been answered only on `s28`.

**2. Axis 3 — does it amend #8's settled row?**

**Yes.** `path-short-nolead` replaces `path-shorten` as the axis-3 default, and #8's DECISION table is
amended in [`sanitizer-audition.md`](sanitizer-audition.md) rather than left only here.

**The 4–0 is not four new discriminations.** Measured by running the variants over the corpus, not
inferred:

| pair | what it actually decided |
| --- | --- |
| `r06`, `s11` | `path-short-nolead` is **text-identical to `path-shorten`** on both. These two are a re-confirmation of #8's axis-3 winner on `bf_emma` — worth having, since #8 heard it on the rejected voice and `s11` never had a `path-shorten` wav at all — but they say nothing about the combination |
| `s13` | `path-short-nolead` is **text-identical to `path-nolead`** here (both paths are only two segments deep), so this is a first hearing of `path-nolead` on a `PATH-DOTDIR` item, not of the combination |
| `s12` | **the only pair on the page where the combination differs from both parents.** `.claude/claudish-off` → `claude/claudish-off` |

So the combination is adopted **undefeated, on one genuinely combinational pair.** That is a
defensible adoption — the transformation is the union of two independently undefeated rules and it
never lost — but "4–0" overstates the evidence, and anyone reopening axis 3 should know it rests on
`s12`.

**3. Axis 9's scope — what does [#11](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/11) have to write down?**

Three things, all read out of `bench/sanitizers.py` rather than assumed:

- **Order: paths first, extensions second.** `_pipeline` runs `rule_P_paths` and then
  `rule_X_extensions`, so a segment the path rule has just shortened still gets its extension spoken.
  That order is now normative, not incidental.
- **`ext-word` does *not* step over backticked spans; `flag-pause` does.** Under the settled
  sanitizer (`tick-pause` on), a `` `hooks.json` `` reaches the model as `, hooks dot json,` — axis
  1's commas and axis 9's "dot" on the same token. **That composition has never been synthesized**;
  see "Still open".
- **A bare extension is left alone.** `.sh` with no name in front of it is `PATH-EXTBARE`, where both
  frontends already agree. `s09` is a byte-identical control here by design, not by oversight.

### What `ext-word`'s win is about — and it is not pronunciation

#13 assumed a **pronunciation** problem and asked for a table of which extensions are words and which
are letters. Building the audition measured that away: for all 23 extensions the sanitizer
recognises, espeak's reading is byte-identical after a `.` and after the word "dot", and already
correct in every case. **No pronunciation table was built and none is needed.**

`ext-word` won anyway — 5–0, including two real items — and it is **not phoneme-identical** to `base`:
`r03` is 375 phonemes against 369. So the win is real, and it has to be explained by something other
than pronunciation. It is **prosody and pacing**: the rule deletes a full stop espeak was planting
mid-sentence and puts a spoken syllable in its place, which re-phrases the stream around the
filename. That is the entire mechanism.

**Anyone later reading "we added dot-word to fix pronunciation" would be wrong.** The pronunciation
was never broken. The phrasing was.

### Axis 2 is settled — and not by either variant on either page

Landed after this document's DECISION was first written, and it supersedes every "axis 2 is
deliberately undecided" line that used to be in these files, this one included.

**The rule is conditional: the line-break boundary is `,` for 3 bullets or fewer, and `.` for 4 and
up.** Settled by Francis directly, by ear. Three things travel with it and none of them is optional.

**1. The "1–1 tie" was a mis-posed axis, not a coin-flip.** Every variant on this axis applies **one
character to every line break in the item** — `san_lb_comma` in
[`bench/sanitizers.py`](../../bench/sanitizers.py) is one line,
`_pipeline(text, opts, Axes(boundary=","))`, and `Axes.boundary` is a single character. The axis as posed could not
express a conditional answer, so a conditional answer had to read as a tie. Read #8's three verdicts
against the rule instead of against each other and they do not tie — they fit:

| item | shape | #8's verdict | the rule |
| --- | --- | --- | --- |
| `r09` | real, 1176 ch, paragraph-heavy | no audible difference | neither, correctly: there is barely a bullet to break |
| `s37` | 8 bullets, 653 ch | `base` (`.`) wins | `.`, 8 ≥ 4 |
| `s38` | 3 bullets, 106 ch | `lb-comma` (`,`) wins | `,`, 3 ≤ 3 |

Three for three. That is a better account of the same data than "inconclusive" was — but it is an
account of **three** items, and the rule was not derived from them mechanically.

**2. The cutoff's POSITION is the listener's call, not an audited result.** The evidence brackets it
at 3 and at 8. **No item between 4 and 7 bullets has ever been synthesized**, in this audition or in
#8's. Where exactly the boundary sits between those two is a judgement, and it is to be held to the
same standard as `flag-pause`'s zero real carriers above: adopted, recorded, and not to be quoted as
a measurement.

**3. No registered sanitizer implements a conditional boundary.** All 26 take a fixed `boundary`
character. This is a **new capability to be built**, not a variant to be selected — so it cannot be
compared on the page as it stands, and it has to exist in code before the settled-set confirmation
listen under "Still open" can include it.

**It carries no crash-safety weight either way.** `kokoro_onnx._split_phonemes` splits on `. , ! ? ;`
— `BOUNDARY_CHARS` in [`bench/sanitizers.py`](../../bench/sanitizers.py) is that set — so `.` and `,`
are both valid batch seams and **both** avert the 510-phoneme `IndexError`. Nothing about this choice
is a safety trade; it is prosody only.

### What this changes in the settled defaults

The sanitizer #11 specifies is #8's settled set with exactly three amendments:

| | before #13 | after #13 |
| --- | --- | --- |
| axis 3 paths | `path-shorten` | **`path-short-nolead`** |
| axis 8 flags / bare identifiers | no rule | **`flag-pause`** |
| axis 9 `name.ext` | no rule | **`ext-word`** |

Axis 2's conditional boundary is a fourth amendment to the same settled set, settled the same day but
**not by anything on this page** — see the section above. It is listed separately because it is the
only one of the four that no registered sanitizer can currently produce.

### What it does *not* change

- **#8's other six axes.** Not reopened, not re-auditioned, not touched by any variant here.
- **Axis 2** (`.` versus `,` as the line-break replacement) is settled, but **not by anything on this
  page** — no variant here moves it and no wav in `audition-13/` bears on it. See ["Axis 2 is
  settled"](#axis-2-is-settled--and-not-by-either-variant-on-either-page) above.
- **No pronunciation table.** `.py` still reads "pie" (measured, never auditioned) and `yml` still
  reads "immel". Both are known and both are left alone on purpose.
- **Rule L** stays gated behind `--respell`, still mis-firing on "the lives of others".
- **Bare acronyms and camelCase** are still not set off by axis 8, for the reason #1 gives for
  narrowing rule J the same way.

### Still open after this decision

- **Axis 8 has no real carrier — and the first one has now appeared, unheard.** The caveat above, as
  an open item. It was written as "revisit when a corpus capture produces a bare flag or `_`-joined
  identifier *outside* backticks", and the corpus growing to 14 real items has produced one: on `r14`,
  `flag-pause` is **no longer a no-op**. A single `_`-joined identifier reaches it —
  `exceed_context_size_error`, which arrives from inside a fenced block body that the code-block rule
  did not remove, so `base` speaks it and `flag-pause` sets it off with commas. Two things follow, and
  neither changes a verdict above. **The 12 real rewrites this audition was decided on are still a
  measured no-op, twelve for twelve**, so nothing here rests on `r14`. And **`r14` has not been
  synthesized**, in any variant, so the rule has still never been *heard* on real output — the first
  real carrier is a text measurement, not an audition result. Whether a token inside an unremoved
  fence body is the shape this rule was meant for is axis 7's question before it is axis 8's.
- **Axis 2's conditional boundary has to be built before it can be heard.** No registered sanitizer
  takes anything but a fixed boundary character, so the settled rule — `,` at 3 bullets or fewer, `.`
  at 4 and up — does not exist in code yet. It is a prerequisite for the confirmation listen below,
  not a variant selection, and it is the one settled amendment the page cannot currently render.
- **Nothing between 4 and 7 bullets has ever been synthesized.** Axis 2's cutoff is bracketed by
  `s38` at 3 and `s37` at 8 and its exact position is a judgement, so the corpus wants an item in
  that gap before anyone treats the number 4 as measured.
- **The settled combination has never been heard.** 26 sanitizers are registered and **not one of
  them is the settled set**: every pair on both audition pages moves exactly one axis against `base`,
  which is what made them readable. `tick-pause` + `flag-pause` on one item, and `path-short-nolead`
  + `ext-word` on one path, are compositions no wav on disk contains. #11 should register the settled
  combination as a single variant — including axis 2's conditional boundary, once that exists — and
  give it one confirmation listen before it ships: not to re-decide an axis, but to catch an
  interaction.
- **`s12` carries the whole combinational case for axis 3** (above).
- **Deeper leading-dot paths.** A `.github/workflows/ci.yml`-shaped path is still not in the corpus,
  so the combination on a three-segment dotdir path is unauditioned.
- **Everything under "What this audition cannot settle"** above stands as written, except the two
  items this block answers.
