# Kokoro provisioned locally: the ONNX path, measured

Provisioning and measurement for [#5](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/5),
part of the [#1](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/1) map.
Measured 2026-08-15 on **Apple M3, 16 GB**, macOS Darwin 25.6.0.

Every number below was produced on this machine by the harnesses quoted at the end. Nothing here is
an estimate, and the things that were **not** measured are listed under
[Not measured](#not-measured) rather than glossed.

---

## Scope: this is the ONNX branch only

[#2](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/2) recommended provisioning
`remsky/Kokoro-FastAPI` **first** and letting the ≤1.5 GB gate decide between it and the CLI
fallback. That is deliberately **not** what happened here: the torch stack was declined for bandwidth
reasons (metered connection), so the ONNX branch was provisioned and measured instead.

**Consequence: the gate as written is still undecided.** These numbers say nothing about the
FastAPI/torch server's footprint. What they do establish is that the memory objection which motivated
the gate does not bite on the ONNX path — and, unexpectedly, that a **third option** beats both
branches of the original either/or. See [The option the gate didn't have](#the-option-the-gate-didnt-have).

---

## Headline numbers

| | espeak G2P (kokoro-onnx default) | misaki G2P (what [#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3) analysed) |
|---|---|---|
| Cold start, process launch → wav on disk | **5.11 s** | **6.76 s** |
| ├ import `kokoro_onnx` | 0.39 s | 0.29 s |
| ├ load misaki + spaCy | — | 2.25 s |
| ├ load ONNX model | 0.87 s | 1.16 s |
| ├ G2P | 0.000 s | 0.011 s |
| └ first synthesis (12.6 s of audio) | 3.85 s | 3.04 s |
| Warm synthesis, same 12.7 s text | 3.01 s | 2.86 s |
| Warm synthesis, one sentence (4–6 s audio) | 0.95–1.38 s | 0.89–1.29 s |
| Realtime factor, warm | **0.24×** | **0.22×** |
| Resident RSS, steady state under load | **~665 MB** | **~780 MB** |
| Resident RSS, idle after one synthesis | **~380–470 MB** | not sampled |
| Idle CPU | **0.0 %** | not sampled |

Synthesis is comfortably faster than realtime — roughly 4× — so playback can begin long before
generation finishes, and a sentence costs about a second.

## Memory: it plateaus, it does not leak

This is the number the gate turns on, and it needed two different measurements to get right.

`resource.getrusage(...).ru_maxrss` is a **high-water mark that can never fall**, and it reported
934 MB after three synthesis reps — which looks like a leak and would have been reported as one.
Sampling **actual** resident size with `ps` over 20 reps shows what is really happening:

```
after load              518.8 MB
rep   1   2.193s   rss   555.3 MB
rep   4   1.077s   rss   557.3 MB
rep   5   1.362s   rss   663.0 MB   <- onnxruntime arena settles here
rep  10   1.010s   rss   665.9 MB
rep  15   1.068s   rss   665.5 MB
rep  20   0.993s   rss   664.7 MB
```

It **plateaus at ~665 MB by rep 5 and stays flat for the remaining 15** (±2 MB, and trending very
slightly *down*). With misaki the same shape holds at ~780 MB. The growth from 555 → 665 MB is
onnxruntime's allocation arena reaching steady state, not an accumulating leak.

Idling is cheaper still. A warm worker left alone for 30 s:

```
t+  0s   cpu 310.2%   rss  523.2 MB     <- synthesis still finishing, 3+ cores
t+  5s   cpu   0.0%   rss  473.2 MB
t+ 15s   cpu   0.0%   rss  466.1 MB
t+ 30s   cpu   0.0%   rss  379.6 MB     <- OS reclaiming/compressing pages
```

**Idle CPU is a genuine 0.0 %** — there is no background thread, no polling loop. Idle RSS *falls*
to ~380 MB as macOS reclaims pages the arena is no longer touching.

Against the gate's ≤1.5 GB idle-RSS rule, the ONNX path passes on **either** reading of "idle"
(380 MB idle, 665 MB under load) with more than 2× headroom, and passes the ~0 % idle-CPU rule
outright.

## The option the gate didn't have

The gate framed a binary: resident **HTTP server** (fast, heavy) versus per-message **CLI** (light,
slow). The measurements expose a third shape that dominates both:

> **A resident `kokoro-onnx` worker driven by misaki G2P.**
> Torch-free, ~380–470 MB idle, 0.0 % idle CPU, ~1 s per sentence, and it keeps #3's phonemisation.

- Versus the **CLI**: a per-message process pays the full 5.1 s (espeak) or 6.8 s (misaki) cold start
  *every single message*, of which 2.25 s is spaCy loading and ~1 s is the ONNX model — pure waste
  repeated per message. A resident worker pays it once.
- Versus the **FastAPI server**: no torch, no transformers, no HTTP layer, and a fraction of the
  install. The one macOS memory report that motivated the gate's caution (1.8 GB and growing, on MPS)
  has no analogue here.

The cost is that "resident" needs an owner — something must start it lazily, keep it warm, and decide
when it dies. That is design work for [#11](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/11),
not a measurement.

## The coupling nobody flagged: kokoro-onnx does not use misaki by default

`kokoro-onnx` phonemises through **espeak via `phonemizer-fork`**. It is a separate codebase from
`hexgrad/kokoro` with separate phonemisation — [#2](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/2)
noted this, but the consequence deserves stating plainly:

> **[#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3)'s entire sanitizer
> analysis was performed against `misaki`. On kokoro-onnx's default path, none of it applies.**

Everything #3 established — the `SCREAMING_SNAKE_CASE` behaviour, the 4-digit-year rule, the
`[text](/phonemes/)` override hook, which markdown characters are voiced — is a property of misaki's
frontend, not of the model. So the sanitizer decision in
[#8](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/8) is only well-founded if
misaki is actually in the pipeline.

**Verified fix:** it can be. `Kokoro.create()` accepts `is_phonemes=True`, so misaki's output can be
fed straight in, bypassing kokoro-onnx's own G2P entirely:

```python
from misaki import en, espeak
g2p = en.G2P(trf=False, british=False,
             fallback=espeak.EspeakFallback(british=False), unk="")
phonemes, _ = g2p(text)
samples, sr = kokoro.create(phonemes, voice="af_heart", lang="en-us", is_phonemes=True)
```

Configured exactly as `kokoro/pipeline.py:123` does it, so the phonemes match what #3 measured. The
measured cost of choosing misaki over the default: **+2.25 s cold load, +115 MB steady RSS, and
0.011 s per call** — the G2P itself is free; only the spaCy load is not. Audio duration differs
slightly between the two (3.90 s vs 4.18 s for the same sentence), confirming the phoneme streams
genuinely differ.

**Recommendation: pass misaki phonemes explicitly.** The alternative is redoing #3 against
`phonemizer-fork`, and #3 was the more expensive ticket.

## `misaki[en]` pulls torch — do not install the extra

The whole appeal of the ONNX path is a dependency closure with no torch in it. Installing the
documented way destroys that:

```
uv pip install kokoro-onnx "misaki[en]" soundfile     # -> torch==2.13.0, venv 777 MB
```

The chain, read out of the installed metadata:

```
misaki[en]  ->  spacy-curated-transformers 0.3.1  ->  torch>=1.12.0
```

`misaki` 0.9.4's released `en.py` **never imports** `spacy-curated-transformers` (the
`FallbackNetwork` class that would use it exists only on git `main` — #3 established this). So torch
arrives purely through dependency *metadata* for code that is not in the release. Installing misaki's
real runtime needs directly, and omitting that one package, works and is torch-free:

```
uv pip install kokoro-onnx misaki espeakng-loader num2words phonemizer-fork spacy soundfile
```

**238 MB instead of 777 MB, and `torch: no`.** The G2P path was then exercised end-to-end — 12
synthesis reps through misaki — so this is verified working, not merely importable.

## espeak-ng: the research was right

Confirmed on this machine: **no** `espeak-ng` binary on `PATH`, **no** Homebrew formula installed,
and synthesis works anyway. The library and its dictionaries arrive entirely inside the
`espeakng-loader` wheel:

```
library : .../site-packages/espeakng_loader/libespeak-ng.dylib   (504,168 B)
data    : .../site-packages/espeakng_loader/espeak-ng-data       (121 entries)
```

No Homebrew install is required — which matters here, because this machine's brew uses a custom
prefix and builds from source.

---

## Install, verbatim

Python **3.11.8**, already present at `/Library/Frameworks/...`, so **no Python download was needed**.
#2 recommended pinning 3.12, but that pin was driven by the torch path (`kokoro` needs
`>=3.10,<3.13`; Kokoro-FastAPI's own `.python-version` is 3.12). For the ONNX packages alone —
`kokoro-onnx` (`>=3.10,<3.14`) and `kokoro-tts` (`>=3.11,<3.13`) — **3.11 satisfies everything**.
Local `python3` is 3.14.7 and is too new for both.

```bash
KROOT="$HOME/.local/share/kokoro"
mkdir -p "$KROOT"

uv venv --python /Library/Frameworks/Python.framework/Versions/3.11/bin/python3.11 "$KROOT/venv"

# NOT misaki[en] -- see the torch section above.
uv pip install --python "$KROOT/venv/bin/python" \
  kokoro-onnx misaki espeakng-loader num2words phonemizer-fork spacy soundfile

uv pip install --python "$KROOT/venv/bin/python" \
  "https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl"

B=https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0
curl -fL -o "$KROOT/kokoro-v1.0.onnx" "$B/kokoro-v1.0.onnx"
curl -fL -o "$KROOT/voices-v1.0.bin"  "$B/voices-v1.0.bin"
```

### Locations and sizes

| Path | Size | |
|---|---|---|
| `~/.local/share/kokoro/` | **619 MB** | everything, one directory, no hidden cache |
| `~/.local/share/kokoro/venv/` | 270 MB | incl. spaCy + `en_core_web_sm`, no torch |
| `~/.local/share/kokoro/kokoro-v1.0.onnx` | 325,532,387 B | full precision |
| `~/.local/share/kokoro/voices-v1.0.bin` | 28,214,398 B | all voices in one file |

Both downloads match [#2](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/2)'s
recorded byte counts **exactly**. SHA-256:

```
7d5df8ecf7d4b1878015a32686053fd0eebe2bc377234608764cc0ef3636a6c5  kokoro-v1.0.onnx
bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d  voices-v1.0.bin
```

There is **no model cache** on this path — nothing in `~/.cache/huggingface`, nothing hidden. Files
are located by explicit path, so the whole install is one deletable directory.

### First audio

Two real files, 24 kHz mono 16-bit, ~12.7 s each, same text through each frontend — the first
material for [#6](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/6) and
[#9](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/9):

```bash
afplay ~/.local/share/kokoro/bench-espeak.wav    # kokoro-onnx default G2P
afplay ~/.local/share/kokoro/bench-misaki.wav    # misaki G2P
```

`afplay` is present at `/usr/bin/afplay`, and `wav` plays through it directly — no `sox`, no
`ffmpeg`, as the map assumed.

---

## Sleep/wake: survives, with one slow utterance on the way back

Measured 2026-08-15 by leaving a resident worker running across two real sleep cycles, synthesizing
every 20 s and appending an fsync'd line per beat to `~/.local/share/kokoro/sleepwake.log`. Sleep
boundaries come from `pmset -g log`, not from guesswork:

| | |
|---|---|
| 14:01:07 → 14:01:19 | `Entering Sleep state due to 'Software Sleep'` → `Wake from Deep Idle` — **12 s** |
| 14:01:25 → 14:01:48 | `Entering Sleep state due to 'Clamshell Sleep'` → `DarkWake to FullWake` — **~23 s** |

The heartbeat log across that window:

```
beat  5  14:00:50  gap= 21.4s  synth=1.003s  rss= 428.1 MB
beat  6  14:01:21  gap= 31.1s  synth=4.899s  rss= 320.7 MB   <- first synth after wake
beat  7  14:02:02  gap= 41.6s  synth=2.090s  rss= 394.9 MB
beat  8  14:02:25  gap= 22.1s  synth=0.921s  rss= 410.6 MB   <- fully recovered
...
beat 19  14:06:17  gap= 21.1s  synth=0.988s  rss= 414.6 MB
```

**It survives.** No wedge, no raised exception, no lost state — 26 beats total, and it kept
synthesizing correct audio for four minutes after the second wake.

**It does not leak across sleep.** Steady state was 424–428 MB before, 411–415 MB after. Slightly
*lower*, not higher.

**But the first synthesis after a wake costs ~4.9 s** — 5× the normal ~0.95 s — with a second beat at
2.09 s before it settles. That is the ONNX arena being paged back in. Design consequence: either the
worker does a throwaway warm-up synthesis when it notices a long gap, or the **first** thing spoken
after you open the lid arrives several seconds late. Since speech is detached and off the
`MessageDisplay` critical path, the latter is tolerable — but it should be a decision, not a surprise.

A related freebie, from `ps` sampling between beats: an **idle** worker's resident set falls much
further than the earlier 380 MB figure suggested — as low as **~28 MB** while sitting between
heartbeats, because macOS compresses and reclaims the arena aggressively. The RSS numbers above are
all measured immediately *after* a synthesis, which is the honest high reading.

### Still untested: hibernation, which is a different mechanism

Both sleeps above were `Deep Idle` — suspend-to-RAM, nothing written to disk. This machine is
configured `standby 1` / `hibernatemode 3`, so a **longer** sleep writes memory to disk and restores
it, which is a materially bigger perturbation of a ~400 MB resident set than what was tested here.
Worth an opportunistic lid-closed-overnight check; not worth blocking on, since the failure mode it
would reveal is a slow or failed first utterance on a detached path, not a stalled hook.

## Not measured

- **The FastAPI/torch server's footprint.** Declined — and now declined *on evidence* rather than
  merely on bandwidth. See [Why the server branch was closed](#why-the-server-branch-was-closed).
- **Any judgement about how it SOUNDS.** Two wavs exist and are playable; nobody has listened yet.
  Voice choice, prosody, and whether misaki's phonemes actually sound better than espeak's are
  [#9](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/9)'s business.
- **The 510-phoneme context limit.** Not exercised — the test texts are far short of it. Note that
  #2's "the server does its own chunking" advantage **does not transfer** to this path: on
  `kokoro-onnx`, chunking is the caller's problem.
- **`nazdridoy/kokoro-tts` itself.** The CLI wrapper was never installed; `kokoro-onnx` was driven
  directly, which is what a resident worker would do and avoids the wrapper's epub/pdf/sounddevice
  dependencies.
- **Idle RSS and idle CPU for the misaki variant** specifically. Only the espeak worker was idled.
  Expect ~+115 MB by analogy with the loaded figures, but that is inference, not measurement.

## Why the server branch was closed

The gate in [#5](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/5) was designed to
choose between a resident **HTTP server** and a per-message **CLI** by measuring the server. That
measurement was never taken, and it is now being **declined on evidence** rather than left dangling.

**What it would have cost.** Resolved 2026-08-15 with `uv pip compile` against Python 3.11, then
priced from PyPI metadata by picking the one wheel a cp311/macOS-arm64 install would fetch, and
skipping wheels already unpacked in the local `uv` cache:

| | Wheels | Weights | Repo clone | **Total** |
|---|---|---|---|---|
| `remsky/Kokoro-FastAPI`, as it pins itself | 181.2 MiB | 312.1 MiB | 73.3 MiB | **≈ 566 MiB** |
| `kokoro` pip only, torch unpinned (screening) | 19.1 MiB | 312.1 MiB | — | **≈ 332 MiB** |

Two details worth keeping:

- **Kokoro-FastAPI pins `torch==2.8.0`** (`cpu` extra), while `kokoro` itself leaves torch
  **unpinned**. A torch 2.13.0 wheel is already in this machine's `uv` cache, so it helps the
  screening route and does nothing at all for the real server.
- Kokoro-FastAPI also pins `misaki[en,ja,ko,zh]`, dragging in ~31 MiB of Japanese/Korean/Chinese G2P
  (`jieba`, `pypinyin-dict`, `nltk`, `pyopenjtalk`) that an English-only rewrite will never call.

**Why it is not worth spending.** The gate existed to answer one question — *is a resident TTS process
affordable on 16 GB?* — and the ONNX measurements answer it with room to spare: ~665 MB under
sustained load, ~380 MB shortly after idling, as low as ~28 MB when genuinely idle, 0.0 % idle CPU, no
leak, and it survives sleep. A torch server would have to win on some *other* axis to justify 566 MiB
of bandwidth plus torch's permanent ~500 MB on disk and a much larger resident set. Its one concrete
advantage over this path is server-side chunking against the 510-phoneme limit — real, but a bounded
amount of code written once, against a limit whose behaviour
[#3](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/3) already documented.

If the number is ever wanted rather than the argument, the 332 MiB screening route is the way to buy
it: the torch path's footprint is dominated by torch plus the 312 MiB model, and FastAPI/uvicorn add
tens of MB — so a resident `KModel` measuring above ~1.5 GB would rule the server out without ever
installing it.

## Reproducing

The three harnesses used, in the session scratchpad (not committed — they are throwaway):

| Harness | What it answers |
|---|---|
| `bench.py --g2p misaki\|espeak` | cold-start breakdown, warm latency, `ru_maxrss` |
| `rss.py <reps> <g2p>` | **actual** RSS per rep via `ps` — the leak question |
| `idle.py` | idle %CPU and RSS decay of a warm resident worker |

The distinction between `bench.py` and `rss.py` is the methodological point worth keeping: had only
`ru_maxrss` been reported, this document would have claimed a leak that does not exist.
