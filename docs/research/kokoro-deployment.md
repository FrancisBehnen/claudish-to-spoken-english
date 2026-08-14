# Kokoro deployment landscape: FastAPI server vs CLI

Research for [#2](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/2), part of the
[#1](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/1) map.
Investigated 2026-08-14. Every claim below is followed by the primary source it came from.
Where a fact could not be established from a primary source it is listed under
[Could not establish](#could-not-establish) rather than guessed at.

---

## Recommendation

**Pin Python 3.12.** Not 3.13, not the local 3.14.6. See
[Python version](#1-python-version-the-hard-constraint-is-kokoro-not-torch) — 3.12 is the only
version that satisfies every candidate package simultaneously.

**Provision `remsky/Kokoro-FastAPI` first, run it with `DEVICE_TYPE=cpu`, and measure.**
It is the only option that is actively maintained (pushed 2026-08-14), it is genuinely
OpenAI-compatible on `POST /v1/audio/speech`, it returns `wav` directly, and — decisively for a
bash hook — **it does its own chunking**, so `rewrite.sh` never has to implement the 510-token
split. Its own `.python-version` is `3.12`.

**Set `DEVICE_TYPE=cpu` explicitly, do not let it auto-select MPS.** The server's device
auto-detection prefers MPS on a Mac
([`config.py` `get_device()`](https://github.com/remsky/Kokoro-FastAPI/blob/master/api/src/core/config.py)),
and the single macOS memory report that exists is an MPS report of **1.8 GB after the first
sentence, growing steadily**
([remsky/Kokoro-FastAPI#262](https://github.com/remsky/Kokoro-FastAPI/issues/262)). The same
thread has a Mac Mini M4 user reporting the growth disappears on the CPU backend
([comment, 2025-04-14](https://github.com/remsky/Kokoro-FastAPI/issues/262#issuecomment-2800399787)).
For rewrites that are a few sentences long, MPS buys little and costs the memory budget.

**Predicted branch: honestly uncertain, leaning server-if-CPU-backend.** The one macOS number on
record (1.8 GB) sits *above* the 1.5 GB gate, but it was measured on MPS, on master as of
2025-03-27, and before the voice-tensor leak fix that landed 2026-05-09
([#453](https://github.com/remsky/Kokoro-FastAPI/issues/453) →
[#459](https://github.com/remsky/Kokoro-FastAPI/issues/459)). A separate report in the same thread
puts steady-state CPU usage at "about 1.5–3 of 4 GB"
([comment, 2025-06-15](https://github.com/remsky/Kokoro-FastAPI/issues/262#issuecomment-2973634866)),
which straddles the gate. This genuinely has to be measured; the numbers do not settle it.

**If it fails the gate, the CLI fallback should be `nazdridoy/kokoro-tts`, not `python -m kokoro`.**
`kokoro-tts` runs on ONNX Runtime and its entire dependency closure is
`espeakng-loader`, `numpy`, `onnxruntime`, `phonemizer-fork` (plus its own epub/pdf readers) —
**no torch, no transformers, no spaCy**
([kokoro-onnx PyPI metadata](https://pypi.org/pypi/kokoro-onnx/json)). The pip `kokoro` CLI
imports torch, transformers and spaCy on every invocation, which is the wrong shape for a
per-message process.

**espeak-ng does not need to be installed.** See [espeak-ng](#3-espeak-ng-not-a-hard-requirement).
It arrives as a pip wheel with the shared library bundled. This corrects the assumption in the map.

---

## 1. Python version: the hard constraint is `kokoro`, not torch

The ticket guessed torch would be the blocker on Python 3.14. **It is not.**

torch 2.13.0 (current) ships macOS arm64 wheels for cp310 through cp314, including a free-threaded
cp314t build ([PyPI JSON API for `torch`](https://pypi.org/pypi/torch/json)):

```
torch-2.13.0-cp310-cp310-macosx_14_0_arm64.whl
torch-2.13.0-cp311-cp311-macosx_14_0_arm64.whl
torch-2.13.0-cp312-cp312-macosx_14_0_arm64.whl
torch-2.13.0-cp313-cp313-macosx_14_0_arm64.whl
torch-2.13.0-cp314-cp314-macosx_14_0_arm64.whl
torch-2.13.0-cp314-cp314t-macosx_14_0_arm64.whl
```

The blocker is the Kokoro packages' own metadata. Collected from the PyPI JSON API:

| Package | Latest | `requires_python` | Source |
|---|---|---|---|
| `kokoro` | 0.9.4 (2025-04-05) | **`>=3.10,<3.13`** | [pypi.org/pypi/kokoro/json](https://pypi.org/pypi/kokoro/json) |
| `misaki` | 0.9.4 | **`>=3.8,<3.13`** | [pypi.org/pypi/misaki/json](https://pypi.org/pypi/misaki/json) |
| `kokoro-tts` | 2.3.1 (2026-04-08) | **`>=3.11,<3.13`** | [pypi.org/pypi/kokoro-tts/json](https://pypi.org/pypi/kokoro-tts/json) |
| `kokoro-onnx` | 0.5.0 (2026-01-30) | `>=3.10,<3.14` | [pypi.org/pypi/kokoro-onnx/json](https://pypi.org/pypi/kokoro-onnx/json) |
| `kokoro-onnx` | 0.3.9 (pinned by `kokoro-tts`) | **`>=3.9,<3.13`** | [pypi.org/pypi/kokoro-onnx/0.3.9/json](https://pypi.org/pypi/kokoro-onnx/0.3.9/json) |
| `onnxruntime` | 1.28.0 | `>=3.11` (arm64 wheels cp311–cp314) | [pypi.org/pypi/onnxruntime/json](https://pypi.org/pypi/onnxruntime/json) |
| `spacy` | 3.8.15 | `>=3.9,<3.15`, but arm64 wheels only cp310–cp313 | [pypi.org/pypi/spacy/json](https://pypi.org/pypi/spacy/json) |

**The intersection is Python 3.11–3.12, and 3.12 is the upper bound.** Two independent
corroborations that 3.12 is the intended target:

- `remsky/Kokoro-FastAPI` ships
  [`.python-version` = `3.12`](https://github.com/remsky/Kokoro-FastAPI/blob/master/.python-version)
  (its `pyproject.toml` says `requires-python = ">=3.10"`, but it pins `kokoro==0.9.4`, which caps
  the environment at <3.13 regardless).
- `nazdridoy/kokoro-tts` ships
  [`.python-version` = `3.12`](https://github.com/nazdridoy/kokoro-tts/blob/main/.python-version)
  and its README states the prerequisite as
  *"Python 3.11-3.12 (Python 3.13+ is not currently supported)"*
  ([README](https://github.com/nazdridoy/kokoro-tts/blob/main/README.md)).

So: **`uv venv --python 3.12`**.

### A trap worth knowing about

The `kokoro` git `main` branch has drifted past its last release. `pyproject.toml` on `main` says
`requires-python = ">=3.10, <3.14"` while still carrying `version = "0.9.4"`
([pyproject.toml](https://github.com/hexgrad/kokoro/blob/main/pyproject.toml)) — but the wheel
actually published to PyPI as 0.9.4 declares `<3.13`. Installing from PyPI enforces `<3.13`;
only a `pip install git+https://github.com/hexgrad/kokoro` would relax it, onto unreleased code.
Do not read the GitHub `pyproject.toml` as the effective constraint.

---

## 2. The four options

| | What it is | Deps | Python | Maintained |
|---|---|---|---|---|
| **`kokoro` (pip)** | Reference inference library `KPipeline`/`KModel`, plus a bundled CLI at `python -m kokoro` | torch, transformers, `misaki[en]` (→ spaCy), huggingface-hub, numpy, loguru | `>=3.10,<3.13` | **Stale.** Last commit [2025-08-06](https://api.github.com/repos/hexgrad/kokoro), last release 2025-04-05, 200 open issues |
| **`remsky/Kokoro-FastAPI`** | Dockerised/uv-runnable FastAPI server wrapping `kokoro` | all of the above + fastapi/uvicorn, av, soundfile, `espeakng-loader==0.2.4` | `.python-version` 3.12 | **Active.** Pushed [2026-08-14](https://api.github.com/repos/remsky/Kokoro-FastAPI), 5.3k stars, Apache-2.0, v0.8.0-rc2 |
| **`kokoro-onnx`** | Independent ONNX Runtime reimplementation (MIT; model still Apache-2.0) | `espeakng-loader`, `numpy`, `onnxruntime`, `phonemizer-fork` — **no torch** | `>=3.10,<3.14` | Active, pushed [2026-07-05](https://api.github.com/repos/thewh1teagle/kokoro-onnx) |
| **`nazdridoy/kokoro-tts`** | CLI on top of `kokoro-onnx==0.3.9`; epub/pdf/stdin input, `--stream` playback via `sounddevice` | above + beautifulsoup4, ebooklib, pymupdf, sounddevice, soundfile | `>=3.11,<3.13` | Moderately active, pushed [2026-04-08](https://api.github.com/repos/nazdridoy/kokoro-tts) |

Note the `kokoro`-vs-`kokoro-onnx` split matters more than it first looks: they are separate
codebases with separate phonemisation. `kokoro` uses `misaki` (dictionary-first, spaCy-backed,
espeak only as fallback); `kokoro-onnx` phonemises entirely through espeak via `phonemizer-fork`
([`kokoro_onnx/__init__.py`](https://github.com/thewh1teagle/kokoro-onnx/blob/main/src/kokoro_onnx/__init__.py)).
kokoro-onnx's own README notes *"It's recommend to use misaki g2p package from v1.0"*, i.e. its
default G2P is the weaker of the two.

`kokoro-tts` defaults to looking for `kokoro-v1.0.onnx` and `voices-v1.0.bin` **in the current
working directory**, but `--model <path>` and `--voices <path>` accept absolute paths
([`kokoro_tts/__init__.py`](https://github.com/nazdridoy/kokoro-tts/blob/main/kokoro_tts/__init__.py),
lines 168–169, 1297–1362) — so a hook can point at a fixed location rather than depending on CWD.

---

## 3. espeak-ng: **not** a hard requirement

This is the finding that most changes the provisioning plan.

### For English, espeak is only an out-of-dictionary fallback

`KPipeline.__init__` constructs the espeak fallback inside a `try`/`except` and continues without
it ([`kokoro/pipeline.py`](https://github.com/hexgrad/kokoro/blob/main/kokoro/pipeline.py)):

```python
if lang_code in 'ab':
    try:
        fallback = espeak.EspeakFallback(british=lang_code=='b')
    except Exception as e:
        logger.warning("EspeakFallback not Enabled: OOD words will be skipped")
        logger.warning({str(e)})
        fallback = None
    self.g2p = en.G2P(trf=trf, british=lang_code=='b', fallback=fallback, unk='')
```

So for `lang_code='a'`/`'b'` (American/British English) the pipeline runs without espeak; words
outside misaki's dictionary are **silently skipped**, not errored on. The upstream README calls it
exactly that: *"Install espeak, used for English OOD fallback and some non-English languages"*
([hexgrad/kokoro README](https://github.com/hexgrad/kokoro/blob/main/README.md)), and
`hexgrad/Kokoro-82M`'s VOICES.md lists "espeak-ng `en-us` fallback" under American English
([VOICES.md](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md)).

For Spanish/French/Hindi/Italian/Portuguese (`e`,`f`,`h`,`i`,`p`) espeak is *not* a fallback — those
lang codes construct `EspeakG2P` unconditionally, so it is required. Irrelevant here; this plugin
speaks English.

### And it does not need Homebrew anyway — it arrives as a pip wheel

`misaki[en]` depends on **`espeakng-loader`**
([misaki PyPI metadata](https://pypi.org/pypi/misaki/json)), and `misaki/espeak.py` wires
`phonemizer` to the bundled library at import time
([misaki/espeak.py](https://github.com/hexgrad/misaki/blob/main/misaki/espeak.py)):

```python
EspeakWrapper.set_library(espeakng_loader.get_library_path())
EspeakWrapper.set_data_path(espeakng_loader.get_data_path())
```

I downloaded and inspected the wheel to confirm it really carries the binary. The
`espeakng_loader-0.2.4-py3-none-macosx_11_0_arm64.whl` (9.9 MB, 371 entries) contains:

```
espeakng_loader/libespeak-ng.1.52.0.dylib
espeakng_loader/libespeak-ng.1.dylib
espeakng_loader/libespeak-ng.dylib
espeakng_loader/espeak-ng-data/en_dict
espeakng_loader/espeak-ng-data/…      (100+ language dictionaries)
```

([wheel listing from `https://files.pythonhosted.org/.../espeakng_loader-0.2.4-py3-none-macosx_11_0_arm64.whl`,
indexed at [pypi.org/pypi/espeakng-loader/json](https://pypi.org/pypi/espeakng-loader/json)])

`kokoro-onnx` depends on `espeakng-loader>=0.2.4` too, and `Kokoro-FastAPI` lists
`espeakng-loader==0.2.4` as a direct dependency
([Kokoro-FastAPI pyproject.toml](https://github.com/remsky/Kokoro-FastAPI/blob/master/pyproject.toml)).
**Every path gets espeak-ng from pip.**

Caveat worth carrying forward: Kokoro-FastAPI's README still tells uv users to *"Install espeak-ng
in your system if you want it available as a fallback for unknown words/sounds. The upstream
libraries may attempt to handle this, but results have varied."*
([README](https://github.com/remsky/Kokoro-FastAPI/blob/master/README.md)) — an explicit
maintainer hedge that the bundled loader is not always reliable.

### If it turns out to be needed on macOS

`brew install espeak-ng` — Homebrew has espeak-ng 1.52.0 with prebuilt bottles for
`arm64_tahoe`, `arm64_sequoia`, `arm64_sonoma`, `arm64_ventura`
([formulae.brew.sh API](https://formulae.brew.sh/api/formula/espeak-ng.json)). Same 1.52.0 the
wheel bundles, so no version skew.

---

## 4. HTTP API shape of the server

Routes come from `api/src/routers/openai_compatible.py`, mounted with
`app.include_router(openai_router, prefix="/v1")`
([main.py:141](https://github.com/remsky/Kokoro-FastAPI/blob/master/api/src/main.py)).

**Yes, it is genuinely OpenAI-compatible.**

| Method | Path | |
|---|---|---|
| POST | `/v1/audio/speech` | The OpenAI speech endpoint |
| GET | `/v1/audio/voices` | List voices |
| POST | `/v1/audio/voices/combine` | Blend voices |
| GET | `/v1/models`, `/v1/models/{model}` | Model listing |
| GET | `/v1/download/{filename}` | Retrieve a completed generation |
| GET | `/health` | Liveness — **useful for the hook's "is the server up?" probe** |
| POST | `/dev/captioned_speech`, `/dev/dialogue`, `/dev/ssml` | Non-stable helpers |

The README's own example drives it with the stock `openai` Python client against
`base_url="http://localhost:8880/v1"`, `api_key="not-needed"`. Default bind is `0.0.0.0:8880`
([config.py](https://github.com/remsky/Kokoro-FastAPI/blob/master/api/src/core/config.py)).

### Request body (`OpenAISpeechRequest`)

From [`api/src/structures/schemas.py`](https://github.com/remsky/Kokoro-FastAPI/blob/master/api/src/structures/schemas.py):

| Field | Default | |
|---|---|---|
| `model` | `"kokoro"` | also accepts `tts-1`, `tts-1-hd`; an unknown model is a **400** |
| `input` | required | the text |
| `voice` | `"af_heart"` | single or combined (`"af_sky+af_bella"`) |
| `response_format` | `"mp3"` | `mp3 \| opus \| aac \| flac \| wav \| pcm` |
| `speed` | `1.0` | clamped to `0.25`–`4.0` (`RATE_MIN`/`RATE_MAX`) |
| `stream` | **`true`** | note the default |
| `lang_code` | `null` | otherwise inferred from the voice name's first letter |
| `volume_multiplier` | `1.0` | |
| `normalization_options` | on | number/URL/email expansion before phonemising |
| `download_format`, `return_download_link`, `return_timing`, `allow_voice_tags`, `voice_aliases` | | extensions beyond OpenAI |

### Audio formats and streaming

Six formats, with these response content types
([openai_compatible.py:324](https://github.com/remsky/Kokoro-FastAPI/blob/master/api/src/routers/openai_compatible.py)):

```
mp3 → audio/mpeg   opus → audio/opus   aac → audio/aac
flac → audio/flac  wav  → audio/wav    pcm → audio/pcm
```

`pcm` is documented as *"raw 16-bit samples without headers"*. Sample rate is 24000 Hz
(`StreamingAudioWriter(request.response_format, sample_rate=24000)`).

**Streaming is supported and is the default** (`stream: true`). Chunks are emitted per sentence
group. For this plugin, `"response_format": "wav", "stream": false` and a single `curl` into a
temp file feeding `afplay` is the simplest shape — `afplay` plays wav natively, so no `sox`/`ffmpeg`
is needed. `wav` also avoids the *"MediaSource.addSourceBuffer: Type not supported"* mp3 complaint
seen on Apple Silicon in [#270](https://github.com/remsky/Kokoro-FastAPI/issues/270) (that was the
web UI, not the API, but mp3 on this platform has history).

---

## 5. Context limit: **510 confirmed** — and it is phoneme characters, not text tokens

The half-remembered number is right, and it is now verified three ways.

**Where it comes from.** `KModel.context_length` is the ALBERT encoder's
`max_position_embeddings`, and `hexgrad/Kokoro-82M`'s `config.json` sets that to **512**
([config.json](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/config.json), `plbert.max_position_embeddings`).
Two positions go to the BOS/EOS pads, leaving **510**
([kokoro/model.py](https://github.com/hexgrad/kokoro/blob/main/kokoro/model.py)):

```python
self.context_length = self.bert.config.max_position_embeddings   # 512
...
assert len(input_ids)+2 <= self.context_length, (len(input_ids)+2, self.context_length)
```

**Independent confirmation #2:** `kokoro-onnx` hardcodes
`MAX_PHONEME_LENGTH = 510`
([src/kokoro_onnx/config.py](https://github.com/thewh1teagle/kokoro-onnx/blob/main/src/kokoro_onnx/config.py)).

**Independent confirmation #3:** Kokoro-FastAPI's configuration guide documents
`ABSOLUTE_MAX_TOKENS | 450 | Hard ceiling per chunk, model limit is 510`
([docs/configuration.md](https://github.com/remsky/Kokoro-FastAPI/blob/master/docs/configuration.md)).

**It counts phonemes, not input characters.** The check is `len(ps) > 510` on the phoneme string,
so the amount of English text that fits varies with the text. Do not budget by character count.

### What happens when text exceeds it

Not one behaviour — four, depending on the path:

| Path | Behaviour |
|---|---|
| `KPipeline.__call__` with English (`lang_code` `a`/`b`) | **Auto-chunks.** `en_tokenize()` splits at 510 phonemes using a punctuation "waterfall" — first `!.?…`, then `:;`, then `,—` — preferring the latest sentence-ish boundary that fits ([pipeline.py](https://github.com/hexgrad/kokoro/blob/main/kokoro/pipeline.py)) |
| …and a single chunk still exceeds 510 | Logs `"Unexpected len(ps) == N > 510"` and **silently truncates** `ps = ps[:510]` |
| `KPipeline` with non-English lang codes | Chunks at ~400 *characters* on `[.!?]+`, then truncates phonemes at 510 |
| `generate_from_tokens()` with a raw phoneme string | **Raises** `ValueError: Phoneme string too long: N > 510` |
| `kokoro-onnx` | `_split_phonemes()` batches at 510 splitting on `[.,!?;]`; an over-long batch is warned about and truncated |
| **Kokoro-FastAPI** | Never gets near it. `smart_split()` targets 175–250 tokens and hard-caps at 450 (`TARGET_MIN_TOKENS`/`TARGET_MAX_TOKENS`/`ABSOLUTE_MAX_TOKENS` in [config.py](https://github.com/remsky/Kokoro-FastAPI/blob/master/api/src/core/config.py)) |

The failure mode to fear is the **silent truncation**, not the exception — a long rewrite would just
stop mid-sentence with only a log line. That is a strong argument for the server, which chunks for
you well below the ceiling.

### Quality guidance on length (also from the model card)

> "Most voices perform best on a 'goldilocks range' of 100-200 tokens out of ~500 possible."
> — **Weakness** on utterances under 10–20 tokens; **rushing** on utterances over 400 tokens.
>
> — [VOICES.md](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md)

Relevant to the map's open "chunking strategy" question: chunk toward 100–200 tokens for quality,
not toward 510 for efficiency. And very short rewrites (a one-line answer) will sound *worse*, not
better — the model card explicitly suggests bundling short utterances together.

---

## 6. Voices and the `lang_code` / prefix scheme

**54 voice packs** in `hexgrad/Kokoro-82M`, each ~523 KB
([HF model API, `siblings` with `blobs=true`](https://huggingface.co/api/models/hexgrad/Kokoro-82M?blobs=true)).

The prefix is two characters: **language code + gender**.

`lang_code` values, from `KPipeline.LANG_CODES`
([pipeline.py](https://github.com/hexgrad/kokoro/blob/main/kokoro/pipeline.py)):

| Code | Language | G2P route | Alias |
|---|---|---|---|
| `a` | American English | `misaki[en]` | `en-us` |
| `b` | British English | `misaki[en]` | `en-gb` |
| `e` | Spanish | espeak-ng | `es` |
| `f` | French (fr-fr) | espeak-ng | `fr-fr` |
| `h` | Hindi | espeak-ng | `hi` |
| `i` | Italian | espeak-ng | `it` |
| `p` | Brazilian Portuguese | espeak-ng | `pt-br` |
| `j` | Japanese | `misaki[ja]` | `ja` |
| `z` | Mandarin Chinese | `misaki[zh]` | `zh` |

Second character: `f` = female, `m` = male. So `af_heart` = American English, female, "heart".

English voices (the relevant ones), with the model card's overall grades
([VOICES.md](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md)):

- **American female (11):** `af_heart` **A**, `af_bella` **A-** 🔥, `af_nicole` B- 🎧,
  `af_aoede`/`af_kore`/`af_sarah` C+, `af_alloy`/`af_nova` C, `af_sky` C-,
  `af_jessica`/`af_river` D
- **American male (9):** `am_fenrir`/`am_michael`/`am_puck` C+,
  `am_echo`/`am_eric`/`am_liam`/`am_onyx` D, `am_adam` F+, `am_santa` D-
- **British female (4):** `bf_emma` B-, `bf_isabella` C, `bf_alice`/`bf_lily` D
- **British male (4):** `bm_fable`/`bm_george` C, `bm_lewis` D+, `bm_daniel` D

`af_heart` is both the graded best and the default in `kokoro`'s CLI, in `kokoro-onnx`'s examples,
and in Kokoro-FastAPI (`DEFAULT_VOICE=af_heart`). **Sensible default for `CLAUDISH_VOICE`.**

**Voice blending is supported everywhere**, with different syntaxes — worth knowing so the config
surface doesn't accidentally lock into one:

- `kokoro`: comma-delimited, averaged — `voice='af_bella,af_jessica'` (`KPipeline.load_voice`)
- Kokoro-FastAPI: `+`-delimited with optional weights — `"af_bella(2)+af_sky"`
- `kokoro-tts`: colon-weighted — `--voice "af_sarah:60,am_adam:40"`

A language-mismatched voice does not error; it logs
`"Language mismatch, loading X voice into Y pipeline"` and proceeds.

Note Kokoro-FastAPI ships voices the HF repo does not (e.g. `af_jadzia` in
`api/src/voices/v1_0/`), so its `/v1/audio/voices` list is a superset. Enumerate at runtime rather
than hardcoding.

---

## 7. Download sizes and cache locations

### The torch path (`kokoro` pip / Kokoro-FastAPI)

| Artefact | Size | Where |
|---|---|---|
| `kokoro-v1_0.pth` | **327,212,226 B (~312 MiB)** | HF cache, or repo dir for Kokoro-FastAPI |
| `config.json` | 2,351 B | alongside |
| Each voice `.pt` | ~523 KB | lazily, one per voice used |
| `en_core_web_sm-3.8.0` (spaCy) | **12,806,118 B (~12.2 MiB)** | site-packages |

Model and voice sizes from the
[HF model API](https://huggingface.co/api/models/hexgrad/Kokoro-82M?blobs=true); spaCy wheel size
from the `Content-Length` of
[its GitHub release asset](https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl).

**Weight cache location** — `KModel` calls `hf_hub_download(repo_id='hexgrad/Kokoro-82M', ...)`
([model.py](https://github.com/hexgrad/kokoro/blob/main/kokoro/model.py)). Per the huggingface_hub
docs, *"The default `<CACHE_DIR>` is `~/.cache/huggingface/hub`… customizable with the `cache_dir`
argument on all methods, or by specifying either `HF_HOME` or `HF_HUB_CACHE`"*
([Understand caching](https://huggingface.co/docs/huggingface_hub/guides/manage-cache)). So:

```
~/.cache/huggingface/hub/models--hexgrad--Kokoro-82M/
```

**Kokoro-FastAPI does not use the HF cache for weights.** Its
[`docker/scripts/download_model.py`](https://github.com/remsky/Kokoro-FastAPI/blob/master/docker/scripts/download_model.py)
`urlretrieve`s `kokoro-v1_0.pth` + `config.json` from its *own* GitHub release
(`.../releases/download/v0.1.4/`) into `--output api/src/models/v1_0`, verifying a pinned SHA-256.
`start-gpu_mac.sh` invokes exactly that
([start-gpu_mac.sh](https://github.com/remsky/Kokoro-FastAPI/blob/master/start-gpu_mac.sh)), so on
the uv path the weights live **inside the repo clone**, not in `~/.cache`. Voice `.pt` files are
committed to the repo under `api/src/voices/v1_0/`. Overridable via `MODEL_DIR` / `VOICES_DIR`.

Also note: the spaCy model is fetched at *first run*, not install time —
`misaki/en.py` does `if not spacy.util.is_package(name): spacy.cli.download(name)`
([misaki/en.py:525](https://github.com/hexgrad/misaki/blob/main/misaki/en.py)). **That shells out to
pip**, and `pip` is not present in a `uv venv` by default. `kokoro/__main__.py`'s own docstring
warns about it:

> ```
> Common issues:
> pip not installed: `uv pip install pip`
> (Temporary workaround while https://github.com/explosion/spaCy/issues/13747 is not fixed)
> ```
> — [kokoro/__main__.py](https://github.com/hexgrad/kokoro/blob/main/kokoro/__main__.py)

So on a uv venv: **`uv pip install pip` before the first generation**, or pre-install
`en_core_web_sm` from its wheel URL as Kokoro-FastAPI does in its `pyproject.toml`.
(The `misaki` git `main` adds `pip>=25.0.1` as a dependency to fix this, but the published 0.9.4
wheel does not carry it — another main-vs-release drift.)

### The ONNX path (`kokoro-onnx` / `kokoro-tts`)

Assets from the
[`model-files-v1.0` release](https://api.github.com/repos/thewh1teagle/kokoro-onnx/releases/tags/model-files-v1.0):

| File | Size | |
|---|---|---|
| `kokoro-v1.0.onnx` | 325,532,387 B (~310 MiB) | full precision |
| `kokoro-v1.0.fp16.onnx` | 177,464,787 B (~169 MiB) | |
| `kokoro-v1.0.int8.onnx` | 92,361,271 B (~88 MiB) | quantised |
| `voices-v1.0.bin` | 28,214,398 B (~27 MiB) | **all voices in one file** |

kokoro-onnx's README advertises *"Lightweight: ~300MB (quantized: ~80MB)"* and *"Fast performance
near real-time on macOS M1"* ([README](https://github.com/thewh1teagle/kokoro-onnx/blob/main/README.md)).

**There is no cache** on this path: files are downloaded manually and located by path. Put them
somewhere stable (e.g. `~/.local/share/kokoro/`) and pass `--model` / `--voices`.

---

## 8. Memory footprint

**This is the weakest part of the evidence base, and the part the decision rule depends on. Read
the documented/reported split carefully.**

### Documented — but not applicable

Kokoro-FastAPI's README has a memory table, and it is **CUDA VRAM on Windows 11 + WSL2 with an
NVIDIA 4060Ti**, not macOS resident memory
([README, Performance & Benchmarks](https://github.com/remsky/Kokoro-FastAPI/blob/master/README.md)):

| Workload | Loaded | Floor | Reclaimed | Reload |
|---|---|---|---|---|
| Short (6s audio) | 3.11 GB | 2.37 GB | 758 MiB | +4.9s |
| Long-form (7.5m) | 3.98 GB | 2.37 GB | 1,656 MiB | +5.1s |

"Floor is host + CUDA context." **Do not carry these numbers to a Mac** — most of the floor is the
CUDA context, which does not exist here. There is no equivalent macOS table anywhere in the repo,
and the Kubernetes/Helm deployment doc specifies no memory requests or limits either
([docs/deployment/kubernetes.md](https://github.com/remsky/Kokoro-FastAPI/blob/master/docs/deployment/kubernetes.md)).

### Reported by users — the only macOS numbers that exist

All from [remsky/Kokoro-FastAPI#262, "Memory leak and Performance issue"](https://github.com/remsky/Kokoro-FastAPI/issues/262)
(**still open**, created 2025-03-27). These are user reports, not maintainer measurements:

- **Original report — macOS, `start-gpu_mac.sh` (MPS), master as of 2025-03-27:**
  *"The memory usage is 1.8GB after generating the first sentence. But as more sentences are
  generated, the memory usage keeps growing steadily."*
- Reproduced on Linux CPU in Docker and on Ubuntu by two other users; **not** reproduced on
  Windows 11 + RTX 4090.
- **Mac Mini M4, 2026-04-14:** *"In my Mac Mini M4 device, the issue only occurs when I use torch
  MPS backend. If I use CPU backend, then the issue does not occur again."* — the basis for the
  `DEVICE_TYPE=cpu` recommendation.
- **2025-06-15, CPU version:** *"Kokoro uses about 1,5-3 of 4 GB"* under a `docker --memory=4g` cap,
  stable for weeks; unconstrained it *"could easily swallow 20-30 GB of RAM over time."*
- Traced upstream to the `kokoro` library itself by a contributor, filed as
  [hexgrad/kokoro#152 "Memory leak"](https://github.com/hexgrad/kokoro/issues/152) — **still open**,
  and `hexgrad/kokoro` has not been pushed to since 2025-08-06.

### A separate, *fixed* leak

[#453 "Memory leak: per-request voice tensor reload causes unbounded RSS growth"](https://github.com/remsky/Kokoro-FastAPI/issues/453)
is a different bug — the voice tensor was serialised to a new temp file on every request, ~20–30 MB
of transient allocations each time, into `tempfile.gettempdir()` where the app's own cleanup never
looked. The reporter measured *"~500MB baseline"* RSS for the CPU container, climbing to **7.6 GB
over 2.5 days at 50–100 requests/day** and triggering the OOM killer. Fixed by
[#459](https://github.com/remsky/Kokoro-FastAPI/issues/459), closed **2026-05-09**, so it *is* in
v0.8.0-rc2.

That `~500MB baseline` is the closest thing to an idle-RSS figure on record — but it is Linux,
Docker, CPU, and from a bug report rather than a benchmark.

### What this means for the ≤1.5 GB gate

- The **only** macOS number is 1.8 GB, on MPS, pre-fix. Above the gate.
- The CPU backend is reported to avoid the growth, and one report puts it at 1.5–3 GB steady-state
  under load; another puts baseline at ~500 MB.
- The `#453` fix (May 2026) postdates every one of those reports, so all of them understate the
  current build's behaviour by an unknown amount.
- The upstream `kokoro` leak (`hexgrad/kokoro#152`) is **still open** and the library is dormant, so
  whatever remains of it is still present.

**There is no substitute for measuring.** Suggested protocol for the measurement ticket: start with
`DEVICE_TYPE=cpu`, record RSS at idle-after-boot, after one generation, and after ~50 generations —
the reports say the interesting number is the third one, not the first. `/debug/system` exposes
process memory but is off unless `ENABLE_DEBUG_ENDPOINTS=true`
([docs/configuration.md](https://github.com/remsky/Kokoro-FastAPI/blob/master/docs/configuration.md));
plain `ps`/Activity Monitor is fine.

---

## 9. Other things worth carrying into the design

- **`POST /dev/unload`** frees the model and reloads lazily on the next request
  (`ALLOW_DEV_UNLOAD=true` to enable). A pressure valve if idle RSS is the only thing failing the
  gate — at a documented +~5 s reload cost (CUDA figure).
- **Apple Silicon has a history of friction** with this server:
  [#270 "Multiple issues on Mac Apple Silicon"](https://github.com/remsky/Kokoro-FastAPI/issues/270)
  (open, 2025-03-31 — `start-gpu.sh` resolves to CUDA wheels and fails; mp3 unsupported in the web
  UI) and [#277 "start-gpu_mac.sh not running on mac gpu"](https://github.com/remsky/Kokoro-FastAPI/issues/277)
  (open, 2025-04-05). Both predate the current MPS support
  ([#233 "Added support for MPS on Apple silicon"](https://github.com/remsky/Kokoro-FastAPI/issues/233), closed)
  and `start-gpu_mac.sh`, but they say provisioning is unlikely to be frictionless.
- **`PYTORCH_ENABLE_MPS_FALLBACK=1` is mandatory for MPS**, not optional. `KPipeline` refuses MPS
  without it (`RuntimeError("MPS requested but fallback not enabled")`) and won't auto-select MPS
  unless it's set ([pipeline.py](https://github.com/hexgrad/kokoro/blob/main/kokoro/pipeline.py));
  the upstream README documents it as the Apple Silicon GPU incantation. Moot if we run on CPU.
- **The server ships a kill switch we want.** `ENABLE_VOICE_TAGS=false` stops `[voice:...]` in the
  input from switching speakers — described in the config docs as being *"for deployments proxying
  untrusted text"*. Assistant rewrites are effectively untrusted text; `allow_voice_tags` also
  defaults to `false` per-request, so this is belt-and-braces.
- **`ADVANCED_TEXT_NORMALIZATION`** (default on, English only) expands numbers, URLs and emails
  before phonemising. Likely a quality win for developer-flavoured rewrites full of paths and
  version numbers — but it is the server's, not the library's. The CLI path has no equivalent.
- **Licensing:** model weights Apache-2.0, `kokoro` Apache-2.0, Kokoro-FastAPI Apache-2.0,
  `kokoro-onnx` MIT. Nothing blocking.

---

## Could not establish

Stated plainly, because a downstream ticket will install software based on this.

1. **Idle resident memory of Kokoro-FastAPI on macOS with `DEVICE_TYPE=cpu` on the current build.**
   No such figure exists in any primary source. The 1.8 GB number is MPS, is a user report, and
   predates the May 2026 leak fix by over a year. **This is exactly the number the decision rule
   needs, and it must be measured.**
2. **Idle CPU usage of the server.** Not documented anywhere; no user report found either.
3. **Sleep/wake survival on macOS.** Nothing in any repo, doc, or issue addresses it.
4. **Cold-start latency of the CLI paths.** I found no primary measurement of how long
   `python -m kokoro` or `kokoro-tts` takes from process start to first audio byte. The reasoning
   that ONNX starts faster than torch+transformers+spaCy is *inference from the dependency lists*,
   not a measured fact. For a per-message hook this is a first-order concern and should be timed
   alongside the memory measurement.
5. **Whether the `#459` voice-tensor fix materially changes the macOS picture.** The fix is real and
   merged; its effect on the numbers above is unmeasured.
6. **Whether the bundled `espeakng-loader` fallback actually works on macOS arm64 in practice.** The
   wheel demonstrably contains `libespeak-ng.1.52.0.dylib` and the dictionaries, and the loading code
   is straightforward — but Kokoro-FastAPI's maintainer hedges that "results have varied", and I
   could not find a primary source that settles it for Apple Silicon specifically. Since it is only
   an OOD fallback for English, a failure here degrades quality (skipped words) rather than breaking
   generation — but it should be spot-checked with a deliberately out-of-dictionary word.
7. **Real-time factor on this machine.** The 35x–100x realtime figure in the README is a CUDA
   4060Ti number. kokoro-onnx claims "near real-time on macOS M1" with no methodology. Neither
   transfers.
