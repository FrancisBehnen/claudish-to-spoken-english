# The minimum-length audition: how long a short message actually takes to say

The evidence for
[#10](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/10), part of the
[Kokoro speech map (#1)](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/1).
Assembled 2026-08-16.

**This document does not set `CLAUDISH_SPEAK_MIN_CHARS` and does not say how anything sounds.**
The ticket's question — *when you are looking away from the screen, is a two-second "Done, tests
pass" worth the interruption?* — is a judgement about your attention, and nobody but you can make
it. What is here is the two seconds made real: 27 wavs grouped so the comparison is the one the
ticket draws, every duration measured, and a sweep that says what each candidate threshold would
cost and buy. Listen, then pick the number.

Everything below is a stopwatch reading, a count, or an arithmetic consequence of one. No LLM was
called — not one rewrite was generated for this — and no hook was touched.

---

## The wrinkle, stated first

`rewrite.sh` skips any message whose prose length is under `CLAUDISH_MIN_CHARS` (default 200)
— `rewrite.sh:147`, counted after fenced code blocks are dropped and whitespace removed
(`rewrite.sh:139-141`). **Those messages never reach the LLM at all.** So speaking a sub-200
message means speaking *raw assistant output*: the sanitizer is the only thing between Claude's
markdown and the model, with no rewrite having simplified it first.

That makes this ticket the exception in the map. Every other speech ticket assumes the input is a
clean plain-English rewrite. Here it is whatever Claude typed. All sixteen short items in the
audition are therefore **real, raw, never-rewritten assistant messages**, pulled out of this
machine's own transcripts — not hand-authored fixtures and not rewrites.

### Provenance, since the distinction is the whole point

`corpus/README.md` is careful to separate real from synthetic and this has to match it. The three
kinds of text in this audition:

| files | what they are | how to check |
| --- | --- | --- |
| `bench/audition-10/items/*.txt` (16) | **real, verbatim assistant messages**, sub-200, never rewritten | each row of `items.tsv` cites `transcript <session>:<uuid> <timestamp>`; the file is byte-identical to that message |
| `corpus/source/rNN.txt` + `corpus/spoken/rNN.txt` (3 pairs) | **real** assistant message and **its real rewrite**, captured for #7 | `corpus/manifest.tsv` |
| `corpus/spoken/sNN.txt` (5) | **hand-authored** hazard fixtures, marked as such since #7 | `corpus/manifest.tsv`, `origin = hand-authored` |

Nothing in this audition was written by an agent to stand in for a message. The sixteen were
selected by hand out of 142 extracted messages — the selection is the judgement, recorded per item
in `select-short-real.py`; the text is not. Verified after the fact: **16 of 16 item files are
byte-identical to the transcript message they cite.**

```bash
# what the citation means, checked directly against the transcript on disk
grep -c "Now delegating both remaining threads in parallel." \
  ~/.claude/projects/-Users-francis-behnen-Code-claudish-to-spoken-english/1a9bf25f-*.jsonl
```

**Extraction was not blocked.** `corpus/bin/extract-real-sources.sh` reads **assistant** messages
only and ran clean over 142 of them. The classifier refusal `corpus/README.md` records was for
selecting *user prompts*, which nothing here needs. (The one refusal hit here was cosmetic:
`extract-real-sources.sh` is committed mode 644, so it must be run as `bash …`, not executed
directly.)

---

## How to listen

Wavs are in `~/.local/share/kokoro/bench/audition-10/`, named
`<item>.candidate.af_heart.wav`. Voice is `af_heart` and the sanitizer is `candidate`
(rules A–K) — both of those are other tickets' open questions (#9, #8), held fixed here so this
one has a single variable. Specifically it is `candidate` **as committed in
[f42f96d](https://github.com/FrancisBehnen/claudish-to-spoken-english/commit/f42f96d)**; #8's branch
changes rule I, so anything re-synthesized after that lands will differ slightly on URL-bearing
items.

```bash
A=~/.local/share/kokoro/bench/audition-10

afplay $A/ack01.candidate.af_heart.wav      # 20 chars: "Now the README updates."
afplay $A/fct01.candidate.af_heart.wav      # 34 chars: "Frontier is empty. Charting the map now."

# the two bands, shortest first, in one pass each
for f in ack01 ack02 ack03 ack04 ack05 ack06 ack07 ack08; do afplay $A/$f.candidate.af_heart.wav; done
for f in fct01 fct02 fct03 fct04 fct05 fct06 fct07 fct08; do afplay $A/$f.candidate.af_heart.wav; done

# five acknowledgements in a row. Back to back this is NOT what a session feels
# like -- measured on these transcripts, assistant messages arrive a median 51s
# apart -- so `sleep 51` between them is the honest version, and it takes 4 min.
for f in ack01 ack02 ack04 ack03 ack05; do afplay $A/$f.candidate.af_heart.wav; sleep 51; done

# raw assistant message, then its plain-English rewrite, back to back
afplay $A/raw-r01.candidate.af_heart.wav; afplay $A/rew-r01.candidate.af_heart.wav
```

---

## Band A — bare acknowledgement

Progress narration. What was just done, or what is about to be done; nothing you could not have
predicted from having asked for the work. **The band assignment is a hand-applied judgement**
against that criterion, recorded per item in `bench/audition-10/items.tsv`; `ack07` is the
borderline one (it carries an opinion, not a fact). The `text` column is verbatim; `[…]` marks an
elision **in this table only**, and the wav speaks the whole message. Durations are quoted to
0.1 s, as the harness's summary table reports them.

| item | prose_len | audio | text |
| --- | ---: | ---: | --- |
| `ack01` | 20 | 1.5 s | Now the README updates. |
| `ack02` | 44 | 2.8 s | Now delegating both remaining threads in parallel. |
| `ack03` | 51 | 3.4 s | Now push the map update and close the three research tickets. |
| `ack04` | 62 | 3.6 s | I'll start by reading the README and checking the current state of things. |
| `ack05` | 76 | 5.2 s | Verifying the highest-stakes claim in that report — an actual crash in the synthesis path. |
| `ack06` | 110 | 8.1 s | All clean and all merged. Removing the worktrees (branches stay intact) and stopping the scratch dir from showing up as untracked. |
| `ack07` | 147 | 10.5 s | Right call — that's implementation, and the map says implementation is the next effort, not this one. […] |
| `ack08` | 198 | 15.6 s | Delegation noted — I'll route the substantive work to subagents from here. ⏎⏎ Setting up the sleep/wake test. […] |

`ack01` is the shortest assistant message in all 142 the transcripts hold.
`ack08` at prose_len 198 is the closest real message to the 200-character gate from below.

## Band B — a short message carrying a fact

Contains a claim about the world: a measured value, a name, a state, or a negative result.

| item | prose_len | audio | text |
| --- | ---: | ---: | --- |
| `fct01` | 34 | 2.5 s | Frontier is empty. Charting the map now. |
| `fct02` | 60 | 5.4 s | Both wavs are valid 24 kHz mono audio. Writing the provisioning record. |
| `fct03` | 79 | 5.4 s | No `env` block exists in any scope, so there's nothing to collide with. […] |
| `fct04` | 83 | 7.9 s | Torch-free: `**238 MB**`, and it installed from cache in 0s. […] |
| `fct05` | 98 | 12.4 s | Service is up on `127.0.0.1:11434` and registered with launchd for login autostart. Now pulling the model (2.5 GB). |
| `fct06` | 120 | 14.8 s | Idle CPU is `**0.0%**`, and idle RSS actually *falls* to ~380–470 MB as pages get reclaimed. […] |
| `fct07` | 122 | 13.2 s | RSS `**plateaus at ~665 MB**` after rep 5 — it doesn't leak. The 934 MB earlier was the high-water mark […] |
| `fct08` | 194 | 15.9 s | Found the bug in my own check: `uv pip compile` seeds `**metadata**` (`.msgpack`/`.http`) into that cache dir […] |

**The two bands are not the same length in seconds at the same length in characters.** `ack06`
(110 chars) is 8.1 s; `fct05` (98 chars) is 12.4 s — shorter on screen, half again as long in the
ear. Why is the next section.

## Five corpus fixtures, for continuity

**Hand-authored** items from [`corpus/`](../../corpus/README.md) — four `LEN-UNDER`, one
`LEN-OVER` — included so this audition can be compared against #6's numbers and #8's rules. These
are the only authored text in the audition; everything else is a real message.

| item | prose_len | audio | what it is |
| --- | ---: | ---: | --- |
| `s09` | 39 | 4.1 s | bare extensions; a control both research docs found already correct |
| `s21` | 98 | 12.0 s | bare 4-digit numbers |
| `s15` | 176 | 13.7 s | `SCREAMING_SNAKE_CASE` env vars |
| `s32` | 199 | 13.4 s | the length probe one character *under* the 200 gate |
| `s33` | 201 | 14.0 s | the length probe one character *over* it |

`s32` and `s33` differ by one character of input and 0.6 s of audio — but on the live path they
differ by everything, because `s33` would have been rewritten first and `s32` would not.

---

## What actually determines how long a message takes to say

Not its character count. **Phonemes**, almost exactly:

```
audio_s = 0.355 + 0.05488 * phonemes      R² = 0.9950     (27 measured items)
audio_s = 1.665 + 0.06775 * prose_len     R² = 0.9432     (the same 27 items)
```

Seconds-per-phoneme is flat across the whole set — 0.047 to 0.061, no trend with length. What
varies is **phoneme density**, and it varies a lot: **1.21 to 2.26 phonemes per prose character**
across the audition, and 0.91 to 2.26 across all 142 transcript messages.

| item | prose_len | phonemes | density | audio |
| --- | ---: | ---: | ---: | ---: |
| `ack04` | 62 | 76 | 1.23 | 3.6 s |
| `fct05` | 98 | 221 | **2.26** | 12.4 s |
| `fct06` | 120 | 252 | 2.10 | 14.8 s |
| `ack06` | 110 | 138 | 1.25 | 8.1 s |
| `rew-r06` | 507 | 645 | 1.27 | 34.7 s |

The dense ones are dense for a legible reason: `127.0.0.1:11434`, `2.5 GB`, `~380–470 MB`,
`0.0%`, four-digit numbers. Ordinary narration sits near 1.25; anything carrying an address, a
version, or a measurement runs to 2.

**Consequence for this ticket, stated as arithmetic and not as advice:** a threshold in characters
does not bound the utterance in seconds. At any character threshold the shortest thing you can be
interrupted by is roughly `0.35 + 0.055 × 1.25 × T` seconds and the longest message *at that same
length* is roughly `0.35 + 0.055 × 2.26 × T` — a spread of about 1.8×. A threshold expressed in
phonemes, or in predicted seconds, would not have that slack. Whether that matters is the
judgement; that it exists is measured.

---

## The threshold sweep

For each candidate `CLAUDISH_SPEAK_MIN_CHARS`, over two populations. Durations come from each
message's **own** phoneme count (measured by running the same espeak G2P `bench` uses, through the
same `candidate` sanitizer) fed through the law above — not from a character estimate.

### Population 1 — 142 assistant messages, this machine's transcripts for this repo

Four sessions (`1a9bf25f`, `62d419ff`, `d51e4ee0`, `e13166aa`), every assistant message in each.
This is the frequency answer: how often speech fires and how much of it there is.

```
 thresh  spoken  silent    %   shortest    its    shortest   median     total
  chars                          chars   seconds  utterance  spoken    speech
      0     142       0  100%       20      1.8s      1.8s     10.5s    103.6m
     20     142       0  100%       20      1.8s      1.8s     10.5s    103.6m
     40     137       5   96%       44      3.3s      3.3s     11.0s    103.4m
     60     128      14   90%       60      5.8s      4.5s     12.9s    102.8m
     80     106      36   74%       82      6.3s      6.3s     15.8s    100.7m
    100      89      53   62%      100      7.5s      7.2s     19.9s     98.6m
    120      76      66   53%      120      8.6s      8.6s     26.2s     96.9m
    150      64      78   45%      154     14.5s     11.4s     31.6s     94.8m
    200      50      92   35%      202     14.7s     14.7s    117.0s     91.3m
    250      46      96   32%      256     18.5s     18.5s    118.5s     90.1m
    300      38     104   26%      318     27.7s     24.8s    134.3s     87.3m
```

Two things fall out of that table that are worth reading slowly.

**The threshold controls the number of interruptions, not the volume of speech.** Going from 0 to
200 silences 92 of 142 messages — 65% of them — and removes **12 minutes out of 104**. The long
messages carry nearly all the audio; the short ones are almost free in seconds and are almost all
of the count.

**`shortest chars` and `shortest utterance` are different messages** wherever they disagree (at
threshold 60, the shortest message is 5.8 s and the shortest *utterance* is 4.5 s, from a longer
but thinner message). That is the density spread again.

### How often it would happen, and how much of the time it would be talking

The transcripts carry timestamps, so the arrival rate is measurable rather than imagined.
Consecutive assistant messages arrive a **median 51 s apart** (p10 20 s, p25 32 s, p75 106 s;
137 gaps, ones over an hour dropped as session breaks). Total active time across the four
sessions is **400 minutes**.

| threshold | messages spoken | speech | share of active time |
| ---: | ---: | ---: | ---: |
| 0 | 142 | 103.6 min | **25.9 %** |
| 60 | 128 | 102.8 min | 25.7 % |
| 100 | 89 | 98.6 min | 24.7 % |
| 150 | 64 | 94.8 min | 23.7 % |
| 200 | 50 | 91.3 min | 22.8 % |
| 300 | 38 | 87.3 min | 21.8 % |

Across the whole range of plausible thresholds the machine is talking for **roughly a quarter of
the elapsed time either way**. The threshold changes how many times it starts, not how long it
goes on for. (The share is an overstatement at the long end for the reason in the caveat below:
messages over 200 characters would be rewritten first, and the rewrite is ~14 % shorter in
aggregate over the twelve pairs.)

### Population 2 — the 50-item speech corpus

```
 thresh  spoken  silent    %   shortest    its    shortest   median     total
  chars                          chars   seconds  utterance  spoken    speech
      0      50       0  100%       39      4.1s      4.1s     14.0s     23.3m
     20      50       0  100%       39      4.1s      4.1s     14.0s     23.3m
     40      49       1   98%       85      6.5s      6.5s     14.0s     23.2m
     60      49       1   98%       85      6.5s      6.5s     14.0s     23.2m
     80      49       1   98%       85      6.5s      6.5s     14.0s     23.2m
    100      47       3   94%      100     12.6s      7.5s     14.0s     22.9m
    120      43       7   86%      121     14.9s      7.5s     14.7s     22.2m
    150      27      23   54%      152     12.7s      7.5s     20.6s     18.8m
    200      20      30   40%      201     14.0s      7.5s     36.7s     17.2m
    250      14      36   28%      277     20.6s     20.6s     49.3s     15.8m
    300      13      37   26%      313     24.5s     24.5s     49.3s     15.5m
```

The corpus is not a sample of anything — 38 of its 50 items are hand-authored hazard fixtures
clustered between 100 and 200 characters — so read it as continuity with #6 and #8, not as a
frequency claim. Population 1 is the one with a population behind it.

**A caveat that cuts both ways.** In population 1, messages at or above 200 characters are counted
here as their **raw** text. On the live path those would be rewritten first, and the rewrite is not
the same length. Measured over the twelve real pairs, below ~600 raw characters the rewrite is
*longer* and above ~1600 it is much shorter (next section). So the "total speech" column
overstates the long tail and understates the short end. The counts — how many messages are spoken
— are unaffected.

---

## Raw versus rewritten, and what it costs

The audition holds three pairs, the same content twice: `raw-rNN` is the verbatim assistant
message, `rew-rNN` is the plain-English rewrite the plugin produced from it (`corpus/source/` and
`corpus/spoken/`, captured for #7). Same voice, same sanitizer, so the only difference is the LLM.

```bash
A=~/.local/share/kokoro/bench/audition-10
afplay $A/raw-r01.candidate.af_heart.wav; afplay $A/rew-r01.candidate.af_heart.wav   # 202 -> 221 chars
afplay $A/raw-r03.candidate.af_heart.wav; afplay $A/rew-r03.candidate.af_heart.wav   # 271 -> 277
afplay $A/raw-r06.candidate.af_heart.wav; afplay $A/rew-r06.candidate.af_heart.wav   # 443 -> 507
```

| pair | raw chars | rewritten | raw audio | rewritten audio | Δ |
| --- | ---: | ---: | ---: | ---: | ---: |
| `r01` | 202 | 221 | 15.2 s | 16.5 s | +1.3 s |
| `r03` | 271 | 277 | 21.4 s | 20.8 s | −0.6 s |
| `r06` | 443 | 507 | 30.9 s | 34.7 s | +3.8 s |

`raw-r01` is the closest thing this corpus has to the sub-200 case: at prose_len 202 it is two
characters over the gate, so it is the shortest real message that *did* get rewritten, and the pair
is the nearest available answer to "what would the rewrite have bought me here". In duration terms
it bought nothing: it cost 1.3 s.

Extended to all twelve pairs — phoneme counts only, no audio synthesised, so these are the law's
predictions rather than measurements:

| | raw | rewritten |
| --- | ---: | ---: |
| `r01`–`r04` (202–298 raw chars) | 75.1 s | 77.7 s |
| `r05`–`r08` (349–592) | 154.2 s | 169.8 s |
| `r09`–`r12` (1624–3249) | 656.7 s | 516.2 s |
| all twelve | 886.0 s | 763.6 s |

**The rewrite only buys brevity on long messages.** Under ~600 raw characters it adds seconds in
seven of the eight pairs (`r07` is the exception at −3.2 s); `r12` is where it pays, turning 246 s
of raw output into 183 s. Which is to say: at the
lengths this ticket is about, an LLM in the loop would not have made the utterance shorter, even
if one were in the loop — and below 200 characters, none is.

What the sanitizer alone does to raw short text, measured on the sixteen: it is nearly a no-op in
character terms (23→23, 130→130, 100→96 where `**bold**` is stripped, 115→121 where `2.5 GB` and
`127.0.0.1:11434` gain spelled-out decimals) and comes nowhere near the 510-phoneme crash line.
The largest batch across the sixteen short items is **265 phonemes** (`fct08`, prose_len 194); the
only runs that approach the line at all are the two `r06` items at 495, and both are over 440
characters. **No short item can crash the synthesiser** — the crash shape needs a ~500-character
run with no `. , ! ? ;` in it, and none of these is long enough to hold one.

---

## The wait before the speech

Time-to-first-audio, as #6 defines it: wall clock from text-in to the player process starting,
model load excluded and reported separately. Measured with `--play none`, so player spawn is
0.0 ms and each figure is a lower bound by the 15–20 ms #6 measured for a real `afplay` spawn.

**These are the numbers from a clean pass, and getting one took four attempts.** Warm RTF is flat
at 0.22–0.29 on a quiet machine; two sibling agents were synthesizing here all afternoon and the
first three passes came back at 0.32–0.92, 0.21–0.48 and 0.32–0.48, each discarded rather than
published. The pass below ran at **RTF 0.217–0.297, mean 0.237** — inside the band on every one of
its 28 rows.

| item | prose_len | phonemes | TTFA | audio | wait, as % of the speech |
| --- | ---: | ---: | ---: | ---: | ---: |
| `ack01` | 20 | 26 | **0.43 s** | 1.50 s | 29 % |
| `fct01` | 34 | 43 | 0.68 s | 2.50 s | 27 % |
| `ack02` | 44 | 54 | 0.75 s | 2.80 s | 27 % |
| `ack03` | 51 | 63 | 0.83 s | 3.40 s | 24 % |
| `fct02` | 60 | 100 | 1.32 s | 5.40 s | 24 % |
| `ack04` | 62 | 76 | 0.91 s | 3.60 s | 25 % |
| `ack05` | 76 | 95 | 1.26 s | 5.20 s | 24 % |
| `fct03` | 79 | 99 | 1.28 s | 5.40 s | 24 % |
| `fct04` | 83 | 138 | 1.86 s | 7.90 s | 24 % |
| `fct05` | 98 | 221 | 2.84 s | 12.40 s | 23 % |
| `ack06` | 110 | 138 | 1.85 s | 8.10 s | 23 % |
| `fct06` | 120 | 252 | **3.31 s** | 14.80 s | 22 % |
| `fct07` | 122 | 221 | 2.96 s | 13.20 s | 22 % |
| `ack07` | 147 | 185 | 2.42 s | 10.50 s | 23 % |
| `fct08` | 194 | 263 | 3.55 s | 15.90 s | 22 % |
| `ack08` | 198 | 264 | 3.46 s | 15.60 s | 22 % |
| `s09` / `s21` / `s15` / `s32` / `s33` | 39–201 | 69–244 | 1.04–3.14 s | 4.1–14.0 s | 22–25 % |
| `raw-r01` → `rew-r01` | 202 → 221 | 261 → 290 | 3.34 → 3.59 s | 15.2 → 16.5 s | 22 % |
| `raw-r03` → `rew-r03` | 271 → 277 | 367 → 369 | 4.63 → 4.52 s | 21.4 → 20.8 s | 22 % |
| `raw-r06` → `rew-r06` | 443 → 507 | 576 → 645 | 6.80 → 7.55 s | 30.9 → 34.7 s | 22 % |

```
27 runs: 27 OK, 0 CRASH, 0 ERROR
TTFA vs 3s tolerance:  pass 15/27 (56%)   fail 12/27
  min 0.43s   median 2.84s   p90 4.63s   max 7.55s
  RTF 0.217-0.297 throughout; model loaded once in 0.66s
```

Three things worth pulling out.

**The wait is a fixed fraction of the speech, not a constant.** 22–29 % across a 20× range of
lengths — which is the RTF, showing up as latency. So TTFA is not an independent variable to
trade against duration; a shorter utterance is a shorter wait, in the same proportion, every time.

**Short messages are the only ones that clear #9's 3-second line.** Everything at or under ~150
prose characters starts inside 3 s; everything at 194 and above misses. `fct06` is the
counter-example that proves the density point again — 120 characters, and it misses at 3.31 s,
because it is 252 phonemes. The line in seconds does not correspond to a line in characters.

**Cold costs one model load and nothing else.** A fresh process on `ack01`, no warm-up: model
load 0.66 s, first synthesis 420 ms, TTFA **0.42 s**, RTF 0.290 — statistically the same as the
0.43 s the warm run reported. So starting a worker costs about **0.7 s once**, and the ~4.9 s
first-synthesis figure in
[`kokoro-onnx-provisioning.md`](../research/kokoro-onnx-provisioning.md) is specifically the
post-sleep/wake arena page-in, which was **not** re-tested here.

**Audio duration is load-independent** — verified, not assumed. The audition was synthesized three
times at very different loads, and **all 27 items report the same duration to the millisecond** in
the clean pass (RTF 0.217–0.297) and the contended one (RTF 0.212–0.479). Durations in this
document are therefore safe even where a latency would not have been.

---

## What this does not establish

- **Nothing about how any of it sounds.** Not one claim of "clear", "useful", "annoying" or
  "noise" appears above, deliberately. That is the listening, and the listening is yours.
- **The number.** `CLAUDISH_SPEAK_MIN_CHARS` is unset by this document.
- **The band boundary is a judgement, not a measurement.** "Acknowledgement" versus "carries a
  fact" was applied by hand against a stated criterion; `ack07` and `fct01` are the two calls most
  open to disagreement.
- **The population is four sessions of one repo, all of them charting or provisioning work.** A
  session spent debugging would have a different length distribution. 142 messages is enough to
  see the shape and not enough to defend a percentile.
- **Voice and sanitizer are held fixed at `af_heart` and `candidate`**, both of which are open
  questions (#9, #8). If either changes, the durations move — the phoneme law will hold, the
  phoneme counts will not.
- **No barge-in, no queueing.** The sweep counts messages independently. What happens when a
  second message arrives while the first is still being spoken is #9's and the integration
  design's problem, and it plainly interacts with this threshold.
- **Two sibling agents were synthesizing on this machine throughout.** Three passes were discarded
  for running outside the 0.22–0.29 RTF band before a clean one was taken; the published pass ran
  at 0.217–0.297 on every row. Durations were verified identical across the clean and the
  contended passes, so only the latencies ever depended on this.
- **Post-sleep cold.** The ~4.9 s first-synthesis-after-wake figure from the provisioning doc was
  not re-tested. What was measured here is process-cold, which costs one 0.66 s model load.
- **Whether the two bands should get different thresholds.** They plainly behave differently in
  seconds, and the ticket suspects they differ in worth. Nothing here can tell you whether one
  knob or two is the right shape; a `CLAUDISH_SPEAK_MIN_CHARS` that discriminates by content would
  need a content test the bash hook does not have.

---

## Regenerating

```bash
# 1. Pull assistant messages out of the local transcripts (free, no LLM).
bash corpus/bin/extract-real-sources.sh \
  ~/.claude/projects/-Users-francis-behnen-Code-claudish-to-spoken-english /tmp/claudish-ex

# 2. Re-select the sixteen short items into bench/audition-10/items/ (free).
#    Selection is by transcript uuid, recorded in the script.
python3 bench/audition-10/select-short-real.py /tmp/claudish-ex

# 3. Synthesize the audition. Silent; wavs land in ~/.local/share/kokoro/bench/audition-10/.
bench/audition-10/run.sh

# 4. Count phonemes for both populations (free, no synthesis).
KOKORO_ROOT=~/.local/share/kokoro ~/.local/share/kokoro/venv/bin/python \
  bench/audition-10/phonemize.py /tmp/claudish-ex \
  ~/.local/share/kokoro/bench/audition-10/phon.tsv

# 5. Re-derive the duration law, both sweep tables and the arrival rate (free).
python3 bench/audition-10/sweep.py --extract-dir /tmp/claudish-ex
```

Step 1 reads only **assistant** messages; selecting user prompts out of a transcript is what this
machine's permission classifier blocks, and nothing here needs them (`corpus/README.md`, "Known
deviation from the live hook"). It was not blocked this time.

The sixteen item texts are committed under `bench/audition-10/items/` — they are real messages from
Francis' own sessions on this repo, the same provenance as `corpus/source/`. Wavs are not
committed; there is no LFS here.
