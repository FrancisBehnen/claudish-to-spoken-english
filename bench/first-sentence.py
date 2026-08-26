#!/usr/bin/env python3
"""First-sentence TTFA: what pipelining would actually deliver.

#6 measured time-to-first-audio for the WHOLE message and found every real
rewrite over the 3-second line. That settles "whole-message synthesis is too
slow"; it does not settle "pipelining fixes it". The number that does is the
TTFA of *sentence one alone*, which is what a pipelined worker would play
first. This script measures it, paired against the whole-message figure in the
same process so both share the same machine conditions.

TTFA is defined exactly as bench/bench.py defines it -- the sum of the same
measured phases, no constant added:

    TTFA = sanitize + Kokoro.create() + soundfile.write() + player spawn

Two deliberate choices, both conservative:

  * the sanitize phase runs over the WHOLE message, not just the sentence it
    then hands to create(). A real worker receives the whole rewrite and has to
    clean and split it before it can know where sentence one ends, so charging
    it the full sanitize is what production would pay.
  * with --play none the spawn phase is 0.0 ms, so the figure is a lower bound
    by the 15-20 ms bench/bench.py measured for a real afplay spawn.

Model load is excluded for the same reason bench/bench.py excludes it: a
resident worker pays it once at startup, not per utterance. It is reported in
the header.

This is a sibling of bench.py, not a modification of it: bench.py is untouched
and the sanitizer registry is imported, so the rules are literally the same
code #6 ran. The registry now lives at `speech/sanitizers.py` and this file's
splitter now lives at `speech/split.py` -- both moved to the plugin root so the
shipped Stop hook imports the same code this script measures. Nothing about
either changed in the move.

Three modes, selectable together so they share a process:

  first   sentence one only -- what a sentence-granularity pipeliner plays
  stream  Kokoro.create_stream()'s FIRST yielded chunk -- what the library's
          own batching delivers with no splitter written at all
  whole   the whole message -- #6's measurement, reproduced for pairing

Run it in the Kokoro venv:

    ~/.local/share/kokoro/venv/bin/python bench/first-sentence.py --whole --stream
    ~/.local/share/kokoro/venv/bin/python bench/first-sentence.py --min-chars 80
"""

from __future__ import annotations

import argparse
import os
import statistics
import sys
import time
from dataclasses import dataclass
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
sys.path.insert(0, str(REPO))

# Both moved to the plugin root under speech/ so the shipped Stop hook can
# import them without reaching into bench/, and because this file's own name
# has a hyphen in it and cannot be imported by module name at all. THIS FILE IS
# NOW THE SECOND CALLER OF BOTH, not their owner: `_SENT_END` and
# `first_sentence` are the same code, in one place, so the figure this script
# measures and the splitter that ships cannot drift.
from speech import sanitizers  # noqa: E402
from speech.split import _SENT_END, first_sentence  # noqa: E402,F401

KROOT = Path(os.environ.get("KOKORO_ROOT", Path.home() / ".local/share/kokoro"))
DEFAULT_OUT = KROOT / "bench" / "first-sentence"
DEFAULT_CORPUS = Path(os.environ.get("CLAUDISH_CORPUS", REPO / "corpus" / "spoken"))


@dataclass
class Row:
    item: str
    mode: str  # "first" | "whole"
    cold: bool = False
    chars_full: int = 0
    chars_spoken: int = 0
    phonemes: int = 0
    batches: int = 0
    max_batch: int = 0
    sanitize_ms: float = 0.0
    synth_ms: float = 0.0
    write_ms: float = 0.0
    ttfa_ms: float = 0.0
    audio_s: float = 0.0
    rtf: float = 0.0
    wav: str = ""
    status: str = "OK"
    detail: str = ""

    @property
    def ttfa_s(self) -> float:
        return self.ttfa_ms / 1000.0


TSV_FIELDS = [
    "item", "mode", "cold", "chars_full", "chars_spoken", "phonemes", "batches",
    "max_batch", "sanitize_ms", "synth_ms", "write_ms", "ttfa_ms", "audio_s",
    "rtf", "status", "wav", "detail",
]


def first_stream_chunk(kok, clean: str, args):
    """What Kokoro.create_stream() yields FIRST, and nothing after it.

    kokoro-onnx already ships batched streaming: create_stream() phonemises,
    splits with the same _split_phonemes create() uses, synthesizes each batch,
    and yields it. So a pipelined worker needs no chunk loop of its own -- but
    the granularity is the PACKED BATCH (up to 509 phonemes), not the sentence,
    which is exactly what this measures.

    Done by replicating create_stream's first iteration inline rather than by
    driving the coroutine, and that is not fussiness: create_stream's
    process_batches() task keeps synthesizing the REMAINING batches into an
    unbounded queue after you stop reading, and aclose() cannot cancel the
    _create_audio call already running in its executor thread. Driving it and
    breaking leaves CPU burning into the next measurement -- a first pass done
    that way self-contended and had to be discarded. The measured work here is
    identical: phonemize -> _split_phonemes -> _create_audio(batch 0) -> trim.
    """
    from kokoro_onnx.trim import trim as trim_audio

    voice = kok.get_voice_style(args.voice)
    phonemes = kok.tokenizer.phonemize(clean, args.lang)
    batches = kok._split_phonemes(phonemes)
    # _split_phonemes emits a spurious empty leading batch when the first part
    # is already oversized (the crash shape); skip it rather than time silence.
    first = next((b for b in batches if b.strip()), "")
    samples, sr = kok._create_audio(first, voice, args.speed)
    samples, _ = trim_audio(samples)
    return samples, sr


def synth_one(kok, sf, raw: str, item: str, mode: str, args, opts,
              cold: bool) -> Row:
    r = Row(item=item, mode=mode, cold=cold, chars_full=len(raw))

    t0 = time.perf_counter()

    t = time.perf_counter()
    clean = sanitizers.run(args.sanitizer, raw, opts)
    if mode == "first":
        clean = first_sentence(clean, args.min_chars)
    r.sanitize_ms = (time.perf_counter() - t) * 1000
    r.chars_spoken = len(clean)

    # diagnostic only, excluded from TTFA exactly as bench.py excludes it
    try:
        ph = kok.tokenizer.phonemize(clean, args.lang)
        batches = kok._split_phonemes(ph)
        r.phonemes = len(ph)
        r.batches = len(batches)
        r.max_batch = max((len(b) for b in batches), default=0)
    except Exception as e:  # noqa: BLE001
        r.detail = f"preflight failed: {type(e).__name__}: {e}"
    pre_end = time.perf_counter()

    t = time.perf_counter()
    try:
        if mode == "stream":
            samples, sr = first_stream_chunk(kok, clean, args)
        else:
            samples, sr = kok.create(clean, voice=args.voice, speed=args.speed,
                                     lang=args.lang)
    except Exception as e:  # noqa: BLE001
        r.synth_ms = (time.perf_counter() - t) * 1000
        r.status = "CRASH" if isinstance(e, IndexError) else "ERROR"
        r.detail = f"{type(e).__name__}: {e}"
        return r
    r.synth_ms = (time.perf_counter() - t) * 1000
    r.audio_s = len(samples) / sr
    r.rtf = (r.synth_ms / 1000) / r.audio_s if r.audio_s else 0.0

    wav = Path(args.out_dir) / f"{item}.{mode}.{args.voice}.wav"
    t = time.perf_counter()
    sf.write(str(wav), samples, sr)
    r.write_ms = (time.perf_counter() - t) * 1000
    r.wav = str(wav)

    # spawn phase is 0.0: this script never plays anything (siblings running).
    r.ttfa_ms = r.sanitize_ms + r.synth_ms + r.write_ms
    _ = t0, pre_end
    return r


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        prog="first-sentence",
        description="TTFA for sentence one alone, paired against the whole message.")
    ap.add_argument("--ids", default="",
                    help="comma-separated corpus ids (default: all 12 real)")
    ap.add_argument("--corpus-dir", default=str(DEFAULT_CORPUS))
    ap.add_argument("--sanitizer", default="candidate")
    ap.add_argument("--max-run", type=int, default=400)
    ap.add_argument("--boundary", default=".", choices=[".", ","])
    ap.add_argument("--min-chars", type=int, default=0,
                    help="extend sentence one until it is this long "
                         "(sensitivity check on degenerate one-word firsts)")
    ap.add_argument("--whole", action="store_true",
                    help="also synthesize the whole message, paired")
    ap.add_argument("--stream", action="store_true",
                    help="also measure Kokoro.create_stream()'s FIRST chunk "
                         "(the library's own batch granularity)")
    ap.add_argument("-v", "--voice", default="af_heart")
    ap.add_argument("--speed", type=float, default=1.0)
    ap.add_argument("--lang", default="en-us")
    ap.add_argument("--tolerance", type=float, default=3.0)
    ap.add_argument("--out-dir", default=str(DEFAULT_OUT))
    ap.add_argument("--tsv")
    ap.add_argument("--show-text", action="store_true")
    ap.add_argument("--no-warmup", action="store_true",
                    help="do NOT do a throwaway synthesis first (then item 1 is cold)")
    args = ap.parse_args(argv)

    corpus = Path(args.corpus_dir)
    ids = [x for x in args.ids.split(",") if x] or sorted(
        p.stem for p in corpus.glob("r*.txt"))
    texts = []
    for i in ids:
        p = corpus / f"{i}.txt"
        if not p.exists():
            raise SystemExit(f"first-sentence: no corpus item {i} at {p}")
        texts.append((i, p.read_text(encoding="utf-8")))

    Path(args.out_dir).mkdir(parents=True, exist_ok=True)
    opts = sanitizers.Opts(max_run=args.max_run, boundary=args.boundary)

    model = KROOT / "kokoro-v1.0.onnx"
    voices = KROOT / "voices-v1.0.bin"
    t = time.perf_counter()
    from kokoro_onnx import Kokoro
    import soundfile as sf
    kok = Kokoro(str(model), str(voices))
    print(f"model loaded in {time.perf_counter() - t:.2f}s "
          f"(once; excluded from TTFA, as in bench.py)")
    print(f"voice={args.voice} sanitizer={args.sanitizer} "
          f"min_chars={args.min_chars} items={len(texts)} "
          f"stream={args.stream} whole={args.whole} play=none")

    cold = True
    if not args.no_warmup:
        t = time.perf_counter()
        kok.create("Warming up.", voice=args.voice, lang=args.lang)
        print(f"warm-up synthesis {time.perf_counter() - t:.2f}s "
              "(so no measured row is cold)")
        cold = False

    rows: list[Row] = []
    for item, raw in texts:
        modes = (["first"] + (["stream"] if args.stream else [])
                 + (["whole"] if args.whole else []))
        for mode in modes:
            r = synth_one(kok, sf, raw, item, mode, args, opts, cold)
            cold = False
            rows.append(r)
            if args.show_text and mode == "first":
                clean = first_sentence(
                    sanitizers.run(args.sanitizer, raw, opts), args.min_chars)
                print(f"\n--- {item} sentence one ({len(clean)} ch) ---")
                print(clean)

    hdr = (f"{'item':<5} {'mode':<6} {'c':<1} {'full':>5} {'said':>5} "
           f"{'phon':>5} {'bat':>4} {'maxb':>5} {'san_ms':>7} {'synth_s':>8} "
           f"{'TTFA_s':>7} {'<=' + f'{args.tolerance:g}s':>6} "
           f"{'audio_s':>8} {'rtf':>6}")
    print("\n" + hdr)
    print("-" * len(hdr))
    for r in rows:
        ok = r.status == "OK"
        verdict = ("PASS" if r.ttfa_s <= args.tolerance else "FAIL") if ok else "-"
        flag = "  <-- RTF HIGH, rerun" if ok and r.rtf > 0.30 else ""
        print(f"{r.item:<5} {r.mode:<6} {'C' if r.cold else ' ':<1} "
              f"{r.chars_full:>5} {r.chars_spoken:>5} {r.phonemes:>5} "
              f"{r.batches:>4} {r.max_batch:>5} {r.sanitize_ms:>7.1f} "
              f"{r.synth_ms / 1000:>8.2f} {r.ttfa_s:>7.2f} {verdict:>6} "
              f"{r.audio_s:>8.2f} {r.rtf:>6.3f}{flag}")
    print("-" * len(hdr))

    for mode in ("first", "stream", "whole"):
        sel = [r for r in rows if r.mode == mode and r.status == "OK"]
        if not sel:
            continue
        v = sorted(r.ttfa_s for r in sel)
        n = len(v)
        passed = sum(1 for x in v if x <= args.tolerance)
        rtfs = [r.rtf for r in sel]
        print(f"\n{mode}: {passed}/{n} pass the {args.tolerance:g}s line   "
              f"min {v[0]:.2f}s  median {statistics.median(v):.2f}s  "
              f"max {v[-1]:.2f}s")
        print(f"       RTF {min(rtfs):.3f}-{max(rtfs):.3f}"
              + ("   <-- CONTENDED, discard" if max(rtfs) > 0.30 else ""))

    if args.tsv:
        lines = ["\t".join(TSV_FIELDS)]
        for r in rows:
            lines.append("\t".join(
                f"{getattr(r, f):.1f}" if isinstance(getattr(r, f), float)
                else str(getattr(r, f)) for f in TSV_FIELDS))
        Path(args.tsv).write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(f"\nwrote {args.tsv}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
