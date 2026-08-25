# Voice and first-sentence pipelining

Work for [#9](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/9), part of the
[#1](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/1) map. Measured 2026-08-16
on **Apple M3, 16 GB**, through the settled espeak / `kokoro-onnx` path
([provisioning](../research/kokoro-onnx-provisioning.md)).

**The two halves of #9 are decided by different things and are kept apart on purpose.**

| | Half A — pipelining | Half B — voice |
| --- | --- | --- |
| Decided by | **a stopwatch** | **an ear** |
| Status here | **concluded** | **not concluded, and cannot be** |
| What this doc gives you | numbers and the argument they support | wavs, an index, and what to listen for |

**Nothing in Half B is a claim about how any voice sounds.** No audio was played while writing this.
The only voice properties recorded are durations and real-time factors, which are stopwatch readings.
Any word like "warmer", "clearer" or "more natural" would be fabricated, so none appears.

---

# Half A — pipelining: measured, and concluded

## The question, and the number that answers it

#9's rule: whole-message time-to-first-audio comfortably under 3 s → don't build pipelining; over it →
build it. [#6](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/6) measured the
whole-message side and found **all twelve real rewrites over the line**, the closest at ~3.9 s. That
settles *"whole-message synthesis is too slow"*. It does **not** settle *"pipelining fixes it"* —
that needs the TTFA of **sentence one alone**, which nobody had measured. This is that number.

**TTFA is defined exactly as [`bench/README.md`](../../bench/README.md) defines it** — the sum of the
same measured phases (`sanitize` + `Kokoro.create()` + `soundfile.write()` + player spawn), model load
excluded and reported separately. The measuring script is
[`bench/first-sentence.py`](../../bench/first-sentence.py), a **sibling** of `bench.py`: it imports
`sanitizers.py` so the rules are literally the same code #6 ran, and edits neither file.

Two conservative choices, both stated so they can be argued with:

- the `sanitize` phase runs over the **whole** message, not just the sentence handed to `create()`.
  A worker receives the whole rewrite and must clean and split it before it can know where sentence
  one ends, so it pays the full sanitize. (It costs 0.2–1.5 ms; it changes nothing.)
- `--play none` throughout, because two sibling agents were synthesizing on this machine. Player
  spawn is therefore 0.0 ms and every TTFA below is a **lower bound by the 15–20 ms** `bench.py`
  measured for a real `afplay` spawn.

## Measured, 2026-08-16 — all 12 real rewrites, `af_heart`, `candidate` sanitizer, warm

Three modes in one process, so they share machine conditions:

| mode | what is synthesized |
| --- | --- |
| **first** | sentence one only — what a sentence-granularity pipeliner plays first |
| **stream** | `Kokoro.create_stream()`'s **first yielded chunk** — what the library's own batching gives you with no splitter written at all |
| **whole** | the whole message — #6's measurement, reproduced here for pairing |

| item | chars | **first: chars** | **first: TTFA** | stream: TTFA | whole: TTFA | whole: audio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `r01` | 268 | 88 | **1.22 s** ✅ | 3.50 s ❌ | 3.58 s ❌ | 16.5 s |
| `r02` | 275 | 62 | **0.85 s** ✅ | 3.56 s ❌ | 3.53 s ❌ | 16.9 s |
| `r03` | 334 | 62 | **0.78 s** ✅ | 4.39 s ❌ | 4.37 s ❌ | 20.8 s |
| `r04` | 369 | 19 | **0.41 s** ✅ | 5.07 s ❌ | 5.17 s ❌ | 24.2 s |
| `r05` | 639 | 27 | **0.39 s** ✅ | 5.44 s ❌ | 8.07 s ❌ | 34.5 s |
| `r06` | 611 | 64 | **0.89 s** ✅ | 6.16 s ❌ | 8.34 s ❌ | 34.7 s |
| `r07` | 669 | 64 | **0.88 s** ✅ | 5.60 s ❌ | 9.94 s ❌ | 47.0 s |
| `r08` | 784 | 87 | **1.14 s** ✅ | 5.54 s ❌ | 9.74 s ❌ | 45.5 s |
| `r09` | 1176 | 65 | **0.85 s** ✅ | 5.37 s ❌ | 14.26 s ❌ | 67.7 s |
| `r10` | 1564 | 32 | **0.50 s** ✅ | 5.53 s ❌ | 21.42 s ❌ | 101.9 s |
| `r11` | 2370 | 42 | **0.54 s** ✅ | 5.47 s ❌ | 32.36 s ❌ | 153.9 s |
| `r12` | 2897 | 72 | **1.05 s** ✅ | 5.35 s ❌ | 36.40 s ❌ | 172.8 s |
| | | | **12/12 pass** | **0/12** | **0/12** | |
| | | median | **0.85 s** | 5.41 s | 9.04 s | |
| | | max | **1.22 s** | 6.16 s | 36.40 s | |

RTF across every row above: **0.208–0.277**, i.e. inside the 0.22–0.29 band #6 calls a quiet machine.

**The `first` column was then re-measured from scratch in a separate process** and came back within
0.02 s on every item (max 1.23 s, median 0.82 s, RTF 0.226–0.275). The whole-message column also
agrees with #6 independently — #6 has `r01` at ~3.9 s cold and I have it at 3.58 s warm, `r12` at
40.0 s against my 36.4 s.

The wavs are on disk if you want to hear what these actually are:
`~/.local/share/kokoro/bench/first-sentence/rNN.{first,stream,whole}.af_heart.wav`.

## The conclusion

**First-sentence TTFA clears the 3-second tolerance on every real rewrite, with a 2.4× margin at the
worst item and ~3.5× at the median. Pipelining solves the problem, and the ticket's condition for
building it is met.**

The margin is wide in a way that matters for the decision: the worst first sentence (1.22 s) is
**2.9× faster than the fastest whole message** (3.53 s) and **30× faster than the slowest**
(36.40 s). And it barely varies with message length — `r12` is 11× longer than `r01` and its first
sentence still starts in 1.05 s — because sentence one is 19–88 characters no matter how long the
message is. That is the property pipelining is buying: **TTFA stops being a function of message
length.**

Two consequences worth carrying into #11:

- **Without pipelining, 2 of the 12 real rewrites never speak at all** — if the hard 30-second ceiling
  is a ceiling on time-to-first-audio, `r11` (32.4 s) and `r12` (36.4 s) are abandoned before a word
  is said. With pipelining they start in 0.54 s and 1.05 s.
- **The production fallback stops being load-bearing for the common case.** "Speak anyway past 3 s"
  currently carries every real message; after pipelining it is a guard for the cold-start case below,
  not the normal path. That is a change in what the fallback is *for*, and it should be re-read in
  that light rather than assumed unchanged.

## The library already splits — but not finely enough. This is the useful finding

`Kokoro.create()` never synthesizes a long message in one go: it phonemises, calls `_split_phonemes`,
and loops (`kokoro_onnx/__init__.py:194-207`). Measured above, `r12` is **7 batches**, `r11` is 6,
`r10` is 4. The audio is *already* produced piecewise and then concatenated before `create()` returns.

There is also a **`create_stream()`** in the installed library (`__init__.py:211-259`) — an async
generator that yields each batch as it lands. So "emit early" needs no chunk loop written at all.

**But its granularity is the packed batch, up to 509 phonemes — and that is too coarse:** the `stream`
column above is **0/12, median 5.41 s**. A packed batch is ~25 s of speech; synthesizing it costs
~5.4 s. So:

> The zero-effort pipelining (`create_stream`, take what it gives you) **does not clear 3 s**.
> Sentence-granularity pipelining does. The worker has to choose its own boundaries.

## "A splitter is needed anyway" — confirmed, with the caveat

#9 argues pipelining's marginal cost is lower than it looks because the 510-phoneme limit forces a
splitter regardless. **Confirmed, from the sources rather than asserted:**

- [`espeak-sanitizer-rules.md` §10](../research/espeak-sanitizer-rules.md) measures the failure: a
  single run without `. , ! ? ;` that phonemises to ≥510 raises
  `IndexError: index 510 is out of bounds for axis 0 with size 510`, bisected to len 509 OK / 510
  raise. Its verdict: a sanitizer must "**guarantee** a boundary at least every ~400 characters",
  and whether that lives in the sanitizer or in the worker's pre-`create()` splitting is #11's call.
- [`bench/sanitizers.py:218-235`](../../bench/sanitizers.py) is that guarantee already implemented —
  `rule_A_guarantee_boundary` walks the text tracking the run length since the last character in
  `BOUNDARY_CHARS = ".,!?;"` and rewrites a space into a boundary when the run gets too long.

So the text-walking, boundary-tracking machinery is **required whether or not pipelining is built**,
and it already exists.

**The caveat, so this is not oversold:** rule A is a *boundary inserter over a character run*, not a
sentence splitter — it answers "where must I force a break?", while a pipeliner asks "where does the
first sentence end?". They share the scan and the character class, not the logic. What pipelining
actually adds on top of what is already needed is:

1. a first-sentence scan (a `re.finditer` over `[.!?]` — see `first_sentence()` in
   `bench/first-sentence.py`, 6 lines),
2. an **ordered playback queue** — the real cost, and the one to design carefully,
3. partial-failure handling: sentence 3 failing after sentences 1–2 have played is a state the
   whole-message path cannot reach.

Item 2 is the honest cost. Items 1 and 3 are small; the splitter is not new work.

## Will the queue starve? Arithmetic, not a measurement

RTF is **0.21** on this machine, i.e. synthesis runs ~4.8× faster than playback. So while chunk *k*
plays for `d_k` seconds, chunk *k+1* needs `0.21 × d_{k+1}` seconds to render, and the queue stays
ahead as long as `d_{k+1} < 4.8 × d_k` — no sentence may be more than ~4.8× longer than the one before
it. With `af_heart` on this corpus, first sentences run 1.4–5.4 s of audio, so there is a lot of room.

**This is arithmetic on a measured RTF, not an end-to-end measurement** — no pipeline exists to
measure. It is stated so #11 knows what to check, and the pathological shape to check is a very short
sentence one followed by a very long sentence two.

## Caveats, all of them

- **Sibling agents were synthesizing on this machine throughout the session.** That is not a
  footnote: **three full passes were discarded** for it. A first pass ran at RTF 0.32–0.51, a second
  at 0.21–0.67, and rows `r01`–`r06` of a third at 0.32–0.62. The numbers published above are from
  runs whose RTF sits at **0.208–0.277**, and every row above 0.30 was re-run until it came back in
  band. `r06` needed a third attempt on its own. (The verdict never actually changed — first-sentence
  TTFA passed 12/12 even at RTF 0.51 — but a contended number should not be published as if it were
  a clean one.)
- **One self-inflicted contention, worth recording so it is not re-derived.** The first `stream`
  implementation drove `create_stream()` and stopped after the first chunk. That leaks CPU:
  `process_batches()` keeps synthesizing the remaining batches into an unbounded queue after you stop
  reading, and `aclose()` cannot cancel the `_create_audio` already running in its executor thread.
  It polluted the following rows. The published `stream` column replicates the same first iteration
  inline instead (`phonemize` → `_split_phonemes` → `_create_audio(batch 0)` → `trim`), which is the
  identical work with no background task.
- **Cold start is now the only thing that can miss the 3 s line.** Model load is excluded (0.53–0.83 s
  here, paid once by a resident worker). But the provisioning doc measures the **first synthesis after
  a sleep/wake at ~4.9 s vs ~0.95 s warm** — larger than the entire warm first-sentence budget. So
  pipelining does not remove #11's warm-up-on-wake question; **it concentrates the whole remaining
  latency risk into it.**
- **Do not batch sentence one up to a minimum length.** Re-run with `--min-chars 80` (extend sentence
  one until it is at least 80 characters), clean at RTF 0.223–0.258: **10/12 pass, `r03` at 3.54 s and
  `r10` at 3.84 s fail**. The margin is real but it is not deep enough to absorb a "make the first
  chunk a decent size" heuristic. Speak sentence one at whatever length it is — including `r04`'s
  19-character *"Stage 1 works fine."*
- **The sanitizer is `candidate`, which #8 has not decided.** It shapes what "sentence one" *is* —
  rule B turns a heading line into its own sentence. If #8 changes rule B, these lengths change and
  the pass is worth re-taking. The command is in the script's docstring.
- **One voice.** All of Half A is `af_heart`. Half B measures `af_nicole` speaking 1.51× slower, which
  scales the worst first sentence to ~1.85 s — still inside 3 s, but that is arithmetic, and a chosen
  voice should get its own pass.
- **`--play none` means spawn is 0.0 ms**, so every TTFA is a lower bound by 15–20 ms.
- **The 30-second ceiling and message preemption were not exercised.** Neither behaviour exists to
  test, and nothing here was heard.

## Reproducing

```bash
P=~/.local/share/kokoro/venv/bin/python
$P bench/first-sentence.py --stream --whole      # the table above
$P bench/first-sentence.py --min-chars 80        # the sensitivity check
$P bench/first-sentence.py --show-text           # what "sentence one" actually is
```

Check the `rtf` column before believing any row: the script flags anything above 0.30 with
`<-- RTF HIGH, rerun` and marks a whole mode `CONTENDED, discard`.


---

# Half B — voice: the audition, not the answer

**This half is not decided and this document does not decide it.** The job here was to make the
audition cheap: enumerate what exists, shortlist defensibly, and synthesize the **same real corpus
items** across the shortlist so a listening session is `afplay` and nothing else.

#9 is explicit about why a demo sentence would be worthless: *"a voice that sounds fine reading prose
may be unbearable reading a message full of file paths."* So every item below is a **real** rewrite
(`rNN`), chosen for path and identifier density, sanitized with the same `candidate` sanitizer #6
measured through.

## What is actually in `voices-v1.0.bin`

54 voices (`bench/bench --list-voices`). The prefix is language and gender: `a` American English,
`b` British English, then `e` Spanish, `f` French, `h` Hindi, `i` Italian, `j` Japanese,
`p` Portuguese, `z` Chinese; `f`/`m` for female/male.

**English is 28 of the 54**: 11 `af_`, 9 `am_`, 4 `bf_`, 4 `bm_`. The other 26 are other languages
and are out of scope — this plugin speaks English rewrites.

## The shortlist, and the rule that produced it

The rule is upstream's own **Overall Grade**, from the model card's
[`VOICES.md`](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md), which grades "the
quality and quantity of [a voice's] associated training data, both of which impact overall inference
quality". Training-duration notation there: `HH` = 10–100 h, `H` = 1–10 h, `MM` = 10–100 min.

**Take every English voice graded B- or better. That is four, and all four are female.** No male
voice reaches B-: the best are three American `C+` voices at `H` hours (`am_fenrir`, `am_michael`,
`am_puck`), and the best British male is `bm_george`/`bm_fable` at `C`. Since "should this be a male
voice?" is a real question and the grade alone would silently answer it "no", **two of the three
joint-best male voices are included as the male-tier probe**.

| voice | accent | grade | training | why it is here |
| --- | --- | --- | --- | --- |
| `af_heart` | American F | **A** | — | the assumed default; the baseline everything else is heard against |
| `af_bella` | American F | **A-** | HH hours | the only other voice within a grade of the default |
| `af_nicole` | American F | **B-** | HH hours | the B- tier |
| `bf_emma` | British F | **B-** | HH hours | the B- tier, and the accent probe |
| `am_michael` | American M | C+ | H hours | male tier (joint best male grade) |
| `am_puck` | American M | C+ | H hours | male tier (joint best male grade) |

**Excluded, and why:** `af_aoede` / `af_kore` / `af_sarah` (C+, `H` hours) and everything below them
sit under the B- cut, and a shortlist that is not listenable in one sitting is not an audition. Two
voices are excluded for a second reason worth recording — `af_sky` and `am_santa` carry upstream's
🤏 mark, meaning **1–10 minutes** of training data.

**Adding one back is one command**, which is the point of shipping the harness rather than a verdict:

```bash
bench/bench --id r03,r04,r06,r11 --sanitizer candidate --voice af_sarah --play none \
  --out-dir ~/.local/share/kokoro/bench/audition-9
```

## The items, and what each one carries

Chosen from the 12 real rewrites by hazard density (`corpus/manifest.tsv`), shortest first so the
audition can stop early:

| item | chars | hazard classes it carries | the listening question it answers |
| --- | --- | --- | --- |
| `r04` | 369 | `ID-SNAKE`, `ID-CAMEL`, `ID-ASSIGN`, `MD-BACKTICK` | identifiers — `chunks=2`, `prose_len=298` |
| `r03` | 334 | `PATH-EXT`, `NUM-UNIT`, `SPLIT-NEWLINE` | file extensions and byte counts in prose |
| `r06` | 611 | `PATH-EXT`, `PATH-SLASH`, `PATH-HYPHEN-EXT` | full paths — `docs/agents/issue-tracker.md` |
| `r11` | 2370 | `ID-SCREAM`, `ID-ACRONYM`, `ID-VOWELLESS`, `PATH-*`, `NUM-4DIGIT`, `MD-PIPE` | everything at once, and length |

## The wavs

`~/.local/share/kokoro/bench/audition-9/` — 24 files, `<item>.candidate.<voice>.wav`. The name sorts
item-first, so one glob is one item across all six voices, in a fixed order:

```bash
A=~/.local/share/kokoro/bench/audition-9
for f in "$A"/r04.*.wav; do echo "$f"; afplay "$f"; done   # identifiers, ~2 min total
for f in "$A"/r06.*.wav; do echo "$f"; afplay "$f"; done   # paths, ~3.5 min total
```

**Listen in tiers and stop when it is decided.** Tier 1 (`r04`) is the identifier question, Tier 2
(`r06`) the path question, Tier 3 (`r03`) a shorter cross-check, Tier 4 (`r11`) the tiebreak — `r11`
is 2 to 4 minutes *per voice*, so it is worth playing only across whichever two voices survive.

## What to listen for

Not "which is nicer" — these are the specific places the measured research says a voice can fail on
programming text, so they are where a difference would actually cost something:

- **`r04`** — `snake_case` and `camelCase` runs, and `chunks=2` / `prose_len=298` read as assignments.
  espeak splits identifiers into words (`CLAUDISH_MIN_CHARS` → "claudish M-I-N chars"); the question
  is whether a given voice keeps the word gaps audible or slurs them back together.
- **`r06`, `r03`** — `docs/agents/issue-tracker.md`, `research/*`, `settings.json`, "59 bytes",
  "code 0". Whether the slashes stay separable, whether the `.md` / `.json` endings land as letters
  rather than noise, and whether a bare number in prose survives.
- **`r11`** — `CLAUDISH_ANTHROPIC_URL`, `CLAUDISH_OPENAI_URL`, `hooks/hooks.json`,
  `.claude/worktrees/agent-…`, a markdown table, and sustained attention: whether a voice that is
  fine for 20 seconds is still fine for two minutes, which is the realistic shape of a long rewrite.
- **All items** — the rate at which each voice speaks; see the durations below, which differ by a
  factor of two and are a *measured* difference you can also hear.

## The one thing that is measurable about a voice, measured

Same text, same sanitizer, same model — only the voice differs. Audio duration is therefore a pure
property of the voice's speaking rate:

| item | `af_heart` | `af_bella` | `af_nicole` | `bf_emma` | `am_michael` | `am_puck` |
| --- | --- | --- | --- | --- | --- | --- |
| `r03` | 20.80 s | 21.16 s | **32.70 s** | 19.03 s | 22.85 s | **18.07 s** |
| `r04` | 24.17 s | 24.45 s | **36.50 s** | 22.17 s | 25.69 s | **18.77 s** |
| `r06` | 34.73 s | 35.20 s | **52.86 s** | 32.73 s | 38.17 s | **28.78 s** |
| `r11` | 153.88 s | 156.31 s | **232.36 s** | 142.51 s | 168.45 s | **117.57 s** |
| vs `af_heart` | 1.00× | 1.02× | **1.51×** | 0.92× | 1.10× | **0.76×** |

Two consequences that are arithmetic, not taste:

1. **`af_nicole` takes 51 % longer to say the same words than `af_heart`; `am_puck` takes 24 % less.**
   A two-minute rewrite in `af_heart` is three minutes in `af_nicole`.
2. **Voice choice moves Half A's numbers.** Synthesis time is `RTF × audio duration` and RTF is flat
   across voices, so a slower voice raises time-to-first-audio in the same proportion. The margin
   Half A reports is wide enough to absorb 1.51×, but it is not free, and it would be the first thing
   to re-measure if a slow voice is chosen.

**That is the entire measurable difference between these six.** Everything else about them is a
listening question, and this document does not answer it. **#9 stays open for that reason.**

---

## DECISION — half B (2026-08-25)

Settled by Francis listening blind (voices presented as V1–V6), verdicts exported to
`~/.local/share/kokoro/bench/audition-verdicts.tsv`. **4/4 items judged.**

**The voice is `bf_emma`.** It won all four items — `r03`, `r04`, `r06`, `r11` — every one of them a
real rewrite dense with paths and identifiers, which is the content this feature actually has to read.

**`af_heart` is rejected.** It was the assumed default through the whole of #1, had never been heard
against real content, and was explicitly eliminated on `r03`. Also eliminated: `af_nicole` (`r03`,
`r04`), `af_bella` and `am_michael` (`r03`).

One consequence for the numbers already recorded in half A: **`bf_emma` is not the voice half A was
measured on.** Every TTFA figure above is `af_heart`. `bf_emma`'s duration ratio against `af_heart`
was not measured (only `af_nicole` +51% and `am_puck` −24% were), so the first-sentence TTFA budget
should be re-checked on `bf_emma` before the 3-second margin is treated as banked. The margin is
wide — 1.22s worst case against 3s — so this is a confirmation step, not an expected reversal.

### That re-check is done (2026-08-25, same day)

**Confirmed, no revision needed.** Measured on `bf_emma` with the same script and the same TTFA
definition, all 12 real rewrites, warm, on a quiet machine (RTF 0.21–0.29 on every `stream` and
`whole` row):

| mode | `bf_emma` | `af_heart`, as published above |
| --- | --- | --- |
| **first** | **12/12 pass** · median 0.86 s · max 1.20 s | 12/12 · median 0.85 s · max 1.22 s |
| stream | 0/12 · median 4.98 s · max 7.03 s | 0/12 · median 5.41 s · max 6.16 s |
| whole | 0/12 · median 8.09 s · max 36.83 s | 0/12 · median 9.04 s · max 36.40 s |

An `af_heart` control run taken minutes later on the same machine reproduced the published figures to
within 0.04 s per item, which is what licenses reading the two columns against each other. And the
duration ratio that was never measured now is: **`bf_emma` produces 0.927× `af_heart`'s audio** over
the 12 whole messages (683 s against 736 s), against the 0.92× the voice table above predicted from
four items.

Full per-item table, the RTF caveats and the noise on the sub-2-second items:
[`sanitizer-audition-13.md`](sanitizer-audition-13.md) §"Confirmation measurement".

Half A (build first-sentence pipelining) was settled on 2026-08-17 and is unchanged.
