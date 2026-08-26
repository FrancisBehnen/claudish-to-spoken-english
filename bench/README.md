# Bench harness: listen to synthesized rewrites, and time them

The instrument the listening tickets share. Built for
[#6](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/6), part of the
[Kokoro speech map (#1)](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/1).
Assembled 2026-08-16.

**Throwaway by design.** This is an asset for *deciding* #8 (sanitizer rules), #9 (voice and the
first-sentence-pipelining call), #10, and #13 (#8's three follow-up rules) — not a component of the
speech feature. It touches no hook, imports nothing from `rewrite.sh` / `rewrite-md.sh` /
`providers.sh`, and never calls an LLM. Delete the directory when the decisions are made and nothing
breaks.

**Nothing in here is a claim about how anything sounds.** Every number below is a stopwatch reading
or a count. The `candidate` sanitizer is a candidate.

```bash
bench/bench --id r09                                  # one item, sanitized, played
bench/bench --id r12 --sanitizer none,candidate       # A/B the same item, back to back
bench/bench --all --play none --tsv /tmp/run.tsv      # the whole corpus, silent, summary table
bench/bench --id s37 --sanitizer none --play none     # a documented crash, survived and reported
bench/bench notes.txt --voice af_bella                # any text file
```

---

## Layout

```
bench/
  bench              launcher: finds the Kokoro venv, execs bench.py in it
  bench.py           the harness: timing, synthesis, playback, reporting
  first-sentence.py  a sibling: TTFA for sentence one alone, for #9
  audition-page.py   builds the local listening page for #8, #9, #10 and #13
  README.md          this file
```

`sanitizers.py` and the sentence splitter no longer live here. They moved to `speech/` at the
plugin root so the shipped `Stop` hook can import them without reaching into a bench directory,
and because `first-sentence.py`'s hyphen makes it un-importable by module name. **This harness is
now the second caller of both, not their owner** — which is the point: the figure measured here
and the code that ships are literally the same code.

`first-sentence.py` imports `speech/sanitizers.py` and `speech/split.py` and edits neither. It answers the question `bench.py`
raises but cannot answer — what a *pipelined* worker's TTFA would be — by synthesizing only sentence
one and timing it with the same four-phase definition. Run it in the venv directly
(`~/.local/share/kokoro/venv/bin/python bench/first-sentence.py --stream --whole`); results in
[`docs/decisions/voice-and-pipelining.md`](../docs/decisions/voice-and-pipelining.md).

`audition-page.py` builds five sections: #8's sanitizer pairs, #9's voice items, #10's length items,
and — added for #13 — a second pair section over `audition-13/`, which is a separate directory
precisely because it is a separate *voice* (`bf_emma`, which #9 chose, against #8's rejected
`af_heart`). Merging them would have paired one voice's reference against another voice's variant.
Section 5, added for #11, is a third pair section over `audition-11/`: same voice as section 4, but
its `settled` pairs move **seven** axes at once rather than one, so it is filed apart from a section
whose whole readability comes from moving one.

`audition-page.py` also imports `speech/sanitizers.py` and edits nothing. It synthesizes nothing either —
it globs the wavs `bench.py` already wrote and builds one self-contained HTML page for listening to
them and recording a verdict per pair:

```bash
python3 bench/audition-page.py                       # re-execs itself into the venv
open ~/.local/share/kokoro/bench/audition.html
```

The page is written **beside** `audition-8/`, `audition-9/`, `audition-10/` and `audition-13/` so
every `<audio src>` is a relative sibling and it works from a `file://` URL with no server; if a
browser refuses, the page carries the `python3 -m http.server` fallback (which is the route verified
for #13, and the one to prefer — `localStorage` is per origin, so switching between `file://` and
`http://localhost` hides earlier verdicts). Everything on it is derived — the pairs from the
wavs on disk, the pronounced text from running the real sanitizer over the real corpus file, the
durations from the wav headers, each variant's description from the registry — so a variant
synthesized later shows up on a re-run with no edit here. Verdicts live in `localStorage` and export
as TSV or Markdown from a textarea. **It is not committed** (~200 KB, and it is a throwaway
instrument for one listening session); the generator is.

Requires the Kokoro install that
[`docs/research/kokoro-onnx-provisioning.md`](../docs/research/kokoro-onnx-provisioning.md)
provisions at `~/.local/share/kokoro/` (Python 3.11.8, `kokoro-onnx`, no torch). Nothing new is
installed. `KOKORO_ROOT` overrides the location.

Synthesis is `Kokoro.create(text, voice=…)` — **espeak, kokoro-onnx's own default G2P**, which is
what #1 settled on. `is_phonemes=True` is never passed and misaki is never imported.

Wavs go to `~/.local/share/kokoro/bench/` (`--out-dir`), never into the repo — there is no LFS here
and a wav is ~2.5 MB. `--no-keep-wav` deletes each one after playing.

---

## Time-to-first-audio: the definition

TTFA is the number [#9](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/9) is
waiting on. It compares against the settled **3-second tolerance** to decide whether first-sentence
pipelining has to be built. So it is defined tightly, and it is **measured, never modelled**:

> **TTFA = wall clock from the moment the text is handed to the harness to the moment the player
> process actually starts.**

Concretely, four measured phases, each timed with `time.perf_counter()` around the real call:

| phase | what it is |
| --- | --- |
| `sanitize` | the selected sanitizer function running on the raw text |
| `synthesis` | `Kokoro.create()` — the whole utterance, every batch |
| `write wav` | `soundfile.write()` to disk |
| `player spawn` | `subprocess.Popen()` of the player returning |

`TTFA = sanitize + synthesis + write + spawn`. Nothing is estimated and no constant is added.

Three things that definition deliberately does **not** include, each for a stated reason:

- **Model load.** `Kokoro(...)` runs once per process and is reported once in the run header. A
  resident worker pays it once at startup, not per utterance, so charging it to every TTFA would be
  a lie in the other direction. It is ~0.6–1.5 s here.
- **The preflight phoneme count** (see below). It duplicates work `create()` does internally and
  exists only so the harness can tell you *why* something crashed. It is timed separately as
  `preflight g2p` and excluded by construction. `wall` — also reported — includes it, so nothing is
  hidden, and `--no-preflight` makes `wall == TTFA`.
- **Listening to the audio.** `wall` stops when the player starts, not when it stops. A 40-second
  utterance still reports a ~9 s wall.

**With `--play none`, `player spawn` is 0.0 ms and TTFA is a lower bound** by exactly that much. If
you want the whole corpus measured *including* a real player spawn but without sitting through it:

```bash
bench/bench --all --play spawn --player "/usr/bin/afplay -v 0"
```

`--play spawn` starts the real player, records the real spawn, and stops it immediately; `-v 0` makes
that silent. Measured spawn on this machine is ~2–20 ms, so it moves nothing — but it is measured
rather than assumed.

The summary table carries a `<=3s` column: `PASS` / `FAIL` against `--tolerance` (default 3.0). Under
the table is the distribution — pass rate, min / median / p90 / max — and the eight slowest runs,
because the long items are what decide the question. `--sort ttfa` puts the worst first.

## Cold vs warm

Model load is expensive and so is the first synthesis after it (and after a sleep/wake — ~4.9 s vs
~0.95 s, measured in the provisioning doc). The harness **loads the model once and reuses it** for
every item in a run, and marks the first synthesis of the process `COLD` (a `C` in the summary
table's `c` column, and a line under the distribution). Without that flag a corpus run would slander
every item that happened to be first.

`--warmup` does a throwaway synthesis before the run instead, so no measured item is cold.

## The preflight, and the 510-phoneme crash

Before synthesizing, the harness runs the diagnostic from
[`espeak-sanitizer-rules.md`](../docs/research/espeak-sanitizer-rules.md) §"Reproducing":

```py
ph = kok.tokenizer.phonemize(text, "en-us")
print(len(ph), [len(b) for b in kok._split_phonemes(ph)])   # any batch >= 510 will raise
```

so every row reports `phon` (total phonemes), `bat` (batches) and `maxb` (largest batch), and any run
whose largest batch reaches 510 is flagged `WILL RAISE` **before** it is attempted.

**`maxb` = 509 is the ceiling, not a near miss.** `_split_phonemes` flushes the current batch when
`len(current) + len(part) + 1 >= 510`, so a *packed* batch can never exceed 509 however long the text
is. The only way `maxb` goes above 509 is a single punctuation-free part that is already too big on
its own — which is exactly the crash. Measured: `r07` reports `maxb` 509 under `candidate`, and it
stays 509 at `--max-run 300` and `--max-run 200`, because rule A is not what produced it.

`Kokoro.create()` chunks only on `. , ! ? ;`. A batch reaching 510 phonemes raises
`IndexError: index 510 is out of bounds for axis 0 with size 510` — an off-by-one in `_create_audio`,
not a documented `ValueError`. `\n` is not in `DEFAULT_VOCAB` and is silently deleted, so it is
neither a boundary nor a pause.

**Corpus items `s35` and `s37` are documented to raise.** The harness catches it, records a `CRASH`
row with the exception, and **continues** — one crash never aborts a corpus run. `CRASH` does not make
the harness exit non-zero; only an `ERROR` (the harness itself misbehaving) does.

That crash-vs-survive column per sanitizer is itself an output: it is how #8 can judge whether a
candidate's chunk-boundary rule actually works.

## Playback

Default player is `/usr/bin/afplay`, overridable with `--player` or `$CLAUDISH_PLAYER` (the plugin's
own idiom). Kokoro's wav plays through it directly; no `sox`, no `ffmpeg`.

`--play full` waits for playback to finish, **with its own watchdog** — there is no `timeout(1)` on
macOS, so the harness gives the player `audio_duration * 2 + 10` seconds, then `terminate()`, then
`kill()`. That is the `_llm_run_bounded` shape from `providers.sh`, copied rather than reinvented.

| `--play` | behaviour | when |
| --- | --- | --- |
| `full` | spawn, hear it out, reap with a watchdog | auditioning; the default for a single run |
| `spawn` | spawn, measure, stop immediately | measuring TTFA in bulk |
| `none` | no player at all (`--no-play`) | bulk verification; the default for many runs |

---

## Sanitizers

A sanitizer is a function `(text, opts) -> text` in `speech/sanitizers.py`, registered with a decorator.
**Adding one more is writing one function** — no other file changes:

```py
@sanitizer("mine", "what it does in one line")
def san_mine(text, opts):
    return text.replace("...", "...")
```

`--sanitizer` takes a comma-separated list, and every input is run through every one of them in
order. That is also the **A/B mechanism** — `--sanitizer none,candidate --id r12` synthesizes the
same item twice, back to back, plays both, and puts them on adjacent rows of the summary table.

`bench/bench --list-sanitizers` prints them with their rule order.

| name | what |
| --- | --- |
| `none` | passthrough. The control — a corpus that only ever runs through a sanitizer can confirm one but never refute it. |
| `candidate` | rules **A–K** from the research doc's candidate list. |
| `crashguard` | rules **B + A** only: the two that decide whether `create()` raises, and nothing else. Isolates the crash question from the prosody question. |
| `base` + 19 axis variants | added for [#8](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/8). `base` is `candidate` with one *named* default per open axis; each variant moves **exactly one** axis (`tick-*`, `lb-*`, `path-*`, `md-*`, `scream-*`, `url-*`, `cb-*`). See [`docs/decisions/sanitizer-audition.md`](../docs/decisions/sanitizer-audition.md). |
| `lb-auto` + `settled` | added for [#11](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/11). `lb-auto` is the conditional boundary **rule B′** on `base` and nothing else; `settled` is **the set that would ship** — all nine axes at their decided value, composed. `settled` is the one entry in this registry that *is* a decision rather than an alternative. See [`docs/decisions/settled-set-audition.md`](../docs/decisions/settled-set-audition.md). |
| 3 follow-up variants | added for [#13](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/13): `flag-pause` and `ext-word` are two rules #8's listener asked for and nobody had heard; `path-short-nolead` is the one combination #8's decision left unmeasured. Same `base` reference, still one axis at a time. **All three were auditioned on `bf_emma` and all three are adopted** — `ext-word` 5–0, `flag-pause` 4–0, `path-short-nolead` 4–0, none of them beaten; `path-short-nolead` replaces `path-shorten` on axis 3. See [`docs/decisions/sanitizer-audition-13.md`](../docs/decisions/sanitizer-audition-13.md). |

**28 sanitizers are registered**; `bench/bench --list-sanitizers` is the authoritative list.

**Two of the 28 were added for #11, and they close the gap the paragraph below used to describe.**
Rule B′ — the conditional boundary, `,` on a short run and `.` on a long one — is implemented and
selectable as `lb-auto`; the composition that would actually ship is registered as `settled` and is
synthesized in `audition-11/`. **It has now been heard.** The confirmation listen ran 2026-08-25,
blind, on `bf_emma`: `settled` was preferred on **all nine** pairs it appeared in, and B′ won in
isolation on `s38`. Two gaps stayed open — the `COND_CUTOFF` position, which one wav at 4 boundaries
contradicts, and a slash-terminated path that no axis-3 rule sets off. See
[`docs/decisions/settled-set-audition.md`](../docs/decisions/settled-set-audition.md), whose DECISION
block is the record.

**The other 26 are still one-axis-at-a-time variants and none of them is the settled set.** That is
deliberate and stays: each moves exactly one axis against `base`, which is what made its pair
readable.

### `candidate` is a candidate, not a decision

It implements the rows of
[`espeak-sanitizer-rules.md`](../docs/research/espeak-sanitizer-rules.md)
§"Candidate rule list, in priority order" — a list the document itself calls *"input to #8's
decision, explicitly NOT the decision"*, ranked by **measured phoneme damage**, not by how anything
sounds. Nobody has listened to any of it. **The rules are #8's call; this is the thing #8 listens
through.**

Applied in this order (execution order, not the doc's priority lettering — the constraints are noted):

| | rule | note |
| --- | --- | --- |
| H | strip emoji | first, before anything else can match inside one |
| I | URLs → `a link` | before E/F, so no version/decimal rule chews a URL |
| C | strip `*` | |
| D | strip `#` heading markers | line-anchored, so it must precede B |
| B | line breaks → `. ` | B destroys the line anchors D needs |
| G | strip thousands separators | before K and F |
| K | currency: unit after the number | `$4.50` → `4 dollars 50` |
| E | version dots → spaces | **must precede F**, or `v0.3.0` → `v0 3 point 0` |
| F | decimal dot → ` point ` | |
| J | lowercase `_`-joined identifiers | narrowed to `_`-joined, per #1 — widening it regresses `SHA-256` |
| L | respell mis-POS'd words | **only with `--respell`**, see below |
| A | guarantee a chunk boundary | last: arithmetic on the text that will actually be phonemised |

`--max-run` (default 400 input chars) is rule A's budget and `--boundary` (`.` or `,`) is what B and A
insert. Both are knobs precisely because the doc lists their right values under "Could not establish".

**Rule L is gated behind `--respell` and it is not safe.** `lives` → `livz` is verified to work when
applied, but the trigger condition is explicitly unestablished. The implementation uses the
preceding-word test the doc sketches (pronoun / auxiliary / modal → leave alone), which fits all seven
probes in the doc and *still* mis-fires on `the lives of others` — the one case espeak currently gets
right. It is here so the regression can be heard, not because it is ready.

**Rule M** ("never emit `[text](/phonemes/)`") is a prohibition, not a transformation. There is no
code for it and there is no code that emits that syntax.

### Known limits of this implementation

- Rule H's emoji ranges are a guess at the class. The doc measured five emoji; ZWJ sequences, skin
  tones and regional-indicator flags were never tested.
- Rule I's bare-host branch requires both a short TLD list and a trailing path. An earlier version
  made the path optional and swallowed `rewrite.sh`.
- Rule A counts **input characters**, which the corpus README flags as a character count standing in
  for a phoneme count. It can under-protect on path- and identifier-heavy text. `maxb` in the table
  is the ground truth; if it reaches 510, lower `--max-run`.
- Rule A cannot help a >`--max-run` run with no whitespace in it at all; it needs somewhere to put
  the boundary.

---

## Input selection

| flag | |
| --- | --- |
| `FILE…` | any text files, positional |
| `--id r09` / `--id r01,s37` | corpus items by id, repeatable |
| `--all` | all 54 items of `corpus/spoken/` |
| `--kind real` / `--kind synthetic` | the 14 `rNN` or the 40 `sNN` |
| `--text "…"` | a literal string |
| `--corpus-dir` / `$CLAUDISH_CORPUS` | a different corpus |

The corpus is [`corpus/`](../corpus/README.md) — 14 real rewrites and 40 synthetic hazard
fixtures. The two newest real items have no wavs on disk: every wav this directory’s pages play
was synthesized when the corpus held 12.
One `.txt` per utterance, no front matter; the harness reads `spoken/*.txt` and nothing else.

## Everything else

| flag | default | |
| --- | --- | --- |
| `--voice` / `--list-voices` | `af_heart` | the harness default, and the voice **#9 rejected**: it chose `bf_emma`, which is what #13's wavs are and what `-v bf_emma` selects |
| `--speed` | `1.0` | |
| `--lang` | `en-us` | |
| `--tolerance` | `3.0` | the TTFA pass/fail line |
| `--sort` | `id` | or `ttfa` / `chars` |
| `--tsv PATH` | | full per-run table, one row per run, for later analysis |
| `--show-text` | | print the sanitized text before speaking it |
| `--quiet` | | summary table only |
| `--out-dir` | `~/.local/share/kokoro/bench` | |
| `--no-keep-wav` | keeps them | |

## Reading the summary table

```
item  sanitizer   st    c chars  phon  bat  maxb  san_ms  synth_s  TTFA_s   <=3s  audio_s    rtf
s35   none        CRASH C  1281  1344    2  1344     0.0     0.14    0.14      -     0.00  0.000
s35   candidate   OK       1281  1347    3   506     1.1    17.36   17.38   FAIL    73.64  0.236
```

`st` status · `c` cold · `chars` input characters · `phon` phonemes · `bat` batches ·
`maxb` largest batch (≥510 raises) · `san_ms` sanitize · `synth_s` `create()` ·
`TTFA_s` time-to-first-audio · `<=3s` the #9 verdict · `audio_s` output duration ·
`rtf` synthesis ÷ audio.

---

## What it measured on 2026-08-16

**Stopwatch readings and counts, on this machine, with this candidate. Not verdicts.** Nothing was
judged by ear, and the sanitizer these were taken through is a candidate, not #8's answer. Re-run
before quoting; the harness exists so the numbers can be regenerated, not archived.

```bash
bench/bench --all --sanitizer candidate --play none --quiet --sort ttfa --tsv /tmp/run.tsv
```

```
50 runs: 50 OK, 0 CRASH, 0 ERROR
TTFA vs 3s tolerance:  pass 13/50 (26%)   fail 37/50
  min 1.07s   median 3.49s   p90 16.84s   max 40.03s
  slowest:  r12 40.03s (2897 ch, 172.8s audio) · r11 35.67s · r10 23.59s
            s34 16.98s · s35 16.84s · r09 15.78s · r07 11.37s · r08 10.67s
  cold first synthesis: r01 at 3.93s TTFA; 49 warm runs follow
  RTF 0.23-0.29 throughout, model loaded once in 0.6-1.5s
```

Every one of the twelve **real** rewrites (`r01`-`r12`) is over the 3-second line, `r01` and `r02` —
the shortest of them, 275 chars — by the smallest margin at ~3.9s. Player spawn, measured on the real
path, is **15-20 ms**, so `--play none` costs the TTFA figure nothing that matters.

The crash-vs-survive signal, which is the part #8 can act on:

| item | `none` | `candidate` |
| --- | --- | --- |
| `s35` | **CRASH** — 1344 phonemes, largest batch 1344 | OK — 1347 phonemes, 3 batches, largest **506**, 73.6s audio |
| `s37` | **CRASH** — 653 phonemes, largest batch 653 | OK — 662 phonemes, 2 batches, largest **439**, 38.3s audio |

Both crashes are `IndexError: index 510 is out of bounds for axis 0 with size 510`, both were
predicted by the preflight before `create()` was called, and neither aborted the run.

On a clean-prose item the candidate is a measured no-op: `s09` gives 69 phonemes and 4.14s of audio
through `none` and through `candidate` alike.

One discarded run is worth recording so nobody re-derives it: an earlier full-corpus pass taken while
something else was loading the CPU reported RTF up to 1.54 and a 68.5s max TTFA. **The harness has no
CPU isolation** — check the `rtf` column, which is flat at ~0.23 on a quiet machine, before believing
a slow row.
