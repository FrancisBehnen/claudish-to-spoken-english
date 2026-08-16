#!/usr/bin/env python3
"""Bench harness for auditioning synthesized rewrites.

Throwaway by design: an instrument for deciding #8/#9/#10, not a component of
the speech feature. It never touches rewrite.sh, providers.sh or any hook, and
it never calls an LLM.

Run it through bench/bench, which finds the Kokoro venv for you.
See bench/README.md for what every number means.
"""

from __future__ import annotations

import argparse
import os
import shlex
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
sys.path.insert(0, str(HERE))

import sanitizers  # noqa: E402

KROOT = Path(os.environ.get("KOKORO_ROOT", Path.home() / ".local/share/kokoro"))
DEFAULT_OUT = KROOT / "bench"
DEFAULT_CORPUS = Path(os.environ.get("CLAUDISH_CORPUS", REPO / "corpus" / "spoken"))
DEFAULT_PLAYER = os.environ.get("CLAUDISH_PLAYER", "/usr/bin/afplay")
MAX_PHONEME_LENGTH = 510  # kokoro_onnx.config; a batch reaching this raises


# --------------------------------------------------------------------------
# results
# --------------------------------------------------------------------------


@dataclass
class Result:
    item: str
    san: str
    voice: str
    status: str = "OK"  # OK | CRASH | ERROR
    cold: bool = False
    chars_in: int = 0
    chars_out: int = 0
    words: int = 0
    phonemes: int = 0
    batches: int = 0
    max_batch: int = 0
    predicted: str = ""  # "" | "WILL RAISE"
    sanitize_ms: float = 0.0
    g2p_ms: float = 0.0
    synth_ms: float = 0.0
    write_ms: float = 0.0
    spawn_ms: float = 0.0
    ttfa_ms: float = 0.0
    wall_ms: float = 0.0
    audio_s: float = 0.0
    rtf: float = 0.0
    played: str = "none"
    wav: str = ""
    detail: str = ""

    @property
    def ttfa_s(self) -> float:
        return self.ttfa_ms / 1000.0


TSV_FIELDS = [
    "item", "san", "voice", "status", "cold", "chars_in", "chars_out", "words",
    "phonemes", "batches", "max_batch", "predicted", "sanitize_ms", "g2p_ms",
    "synth_ms", "write_ms", "spawn_ms", "ttfa_ms", "wall_ms", "audio_s", "rtf",
    "played", "wav", "detail",
]


# --------------------------------------------------------------------------
# playback -- with its own watchdog, because macOS has no timeout(1)
# --------------------------------------------------------------------------


def spawn_player(player: str, wav: Path) -> tuple[subprocess.Popen | None, float, str]:
    argv = shlex.split(player) + [str(wav)]
    t0 = time.perf_counter()
    try:
        p = subprocess.Popen(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError as e:
        return None, (time.perf_counter() - t0) * 1000, f"player failed: {e}"
    return p, (time.perf_counter() - t0) * 1000, ""


def reap_player(p: subprocess.Popen, budget_s: float) -> str:
    """Wait for the player, then TERM, then KILL. The _llm_run_bounded shape."""
    try:
        p.wait(timeout=budget_s)
        return ""
    except subprocess.TimeoutExpired:
        pass
    p.terminate()
    try:
        p.wait(timeout=2.0)
        return f"player exceeded {budget_s:.0f}s budget, terminated"
    except subprocess.TimeoutExpired:
        p.kill()
        p.wait(timeout=2.0)
        return f"player exceeded {budget_s:.0f}s budget, killed"


def stop_player(p: subprocess.Popen) -> None:
    if p.poll() is None:
        p.terminate()
        try:
            p.wait(timeout=2.0)
        except subprocess.TimeoutExpired:
            p.kill()


# --------------------------------------------------------------------------
# one run
# --------------------------------------------------------------------------


def bench_one(kok, sf, text: str, item: str, san_name: str, args, opts,
              cold: bool) -> Result:
    r = Result(item=item, san=san_name, voice=args.voice, cold=cold)
    r.chars_in = len(text)

    # ---- t0: the text is handed to the harness ---------------------------
    t0 = time.perf_counter()

    t = time.perf_counter()
    clean = sanitizers.run(san_name, text, opts)
    r.sanitize_ms = (time.perf_counter() - t) * 1000
    r.chars_out = len(clean)
    r.words = len(clean.split())

    # ---- preflight: what create() is about to do, before it does it ------
    # EXCLUDED from ttfa_ms by construction: it duplicates work create() does
    # internally, so charging it to time-to-first-audio would slander the run.
    # `wall_ms` includes it, so nothing is hidden. --no-preflight removes it.
    if not args.no_preflight:
        t = time.perf_counter()
        try:
            ph = kok.tokenizer.phonemize(clean, args.lang)
            batches = kok._split_phonemes(ph)
            r.phonemes = len(ph)
            r.batches = len(batches)
            r.max_batch = max((len(b) for b in batches), default=0)
            if r.max_batch >= MAX_PHONEME_LENGTH:
                r.predicted = "WILL RAISE"
        except Exception as e:  # noqa: BLE001 -- diagnostics must never abort
            r.detail = f"preflight failed: {type(e).__name__}: {e}"
        r.g2p_ms = (time.perf_counter() - t) * 1000
    preflight_ms = r.g2p_ms

    # ---- synthesize ------------------------------------------------------
    t = time.perf_counter()
    try:
        samples, sr = kok.create(clean, voice=args.voice, speed=args.speed,
                                 lang=args.lang)
    except Exception as e:  # noqa: BLE001 -- s35/s37 are expected to land here
        r.synth_ms = (time.perf_counter() - t) * 1000
        r.wall_ms = (time.perf_counter() - t0) * 1000
        r.ttfa_ms = r.wall_ms - preflight_ms
        r.status = "CRASH" if isinstance(e, IndexError) else "ERROR"
        r.detail = f"{type(e).__name__}: {e}"
        return r
    r.synth_ms = (time.perf_counter() - t) * 1000
    r.audio_s = len(samples) / sr
    r.rtf = (r.synth_ms / 1000) / r.audio_s if r.audio_s else 0.0

    # ---- write the wav ---------------------------------------------------
    wav = Path(args.out_dir) / f"{item}.{san_name}.{args.voice}.wav"
    t = time.perf_counter()
    sf.write(str(wav), samples, sr)
    r.write_ms = (time.perf_counter() - t) * 1000
    r.wav = str(wav)

    # ---- play ------------------------------------------------------------
    proc = None
    if args.play != "none":
        proc, r.spawn_ms, err = spawn_player(args.player, wav)
        if err:
            r.detail = err
            r.played = "failed"
        else:
            r.played = args.play

    r.ttfa_ms = r.sanitize_ms + r.synth_ms + r.write_ms + r.spawn_ms
    r.wall_ms = (time.perf_counter() - t0) * 1000

    if proc is not None:
        if args.play == "spawn":
            stop_player(proc)
        else:
            msg = reap_player(proc, r.audio_s * 2 + 10)
            if msg:
                r.detail = (r.detail + "; " + msg).lstrip("; ")

    if not args.keep_wav:
        wav.unlink(missing_ok=True)
        r.wav = "(deleted)"
    return r


# --------------------------------------------------------------------------
# reporting
# --------------------------------------------------------------------------


def print_detail(r: Result, tol: float, clean_preview: str | None = None) -> None:
    verdict = "PASS" if r.ttfa_s <= tol else "FAIL"
    print(f"\n  {r.item}  [{r.san}]  voice={r.voice}"
          f"{'  (COLD first synthesis)' if r.cold else ''}")
    print(f"    status        {r.status}"
          + (f"  -- {r.detail}" if r.detail else ""))
    print(f"    chars         {r.chars_in} in -> {r.chars_out} out"
          f"  ({r.words} words)")
    print(f"    phonemes      {r.phonemes} in {r.batches} batches,"
          f" largest {r.max_batch}"
          + (f"   <-- {r.predicted} (limit {MAX_PHONEME_LENGTH})"
             if r.predicted else ""))
    print(f"    sanitize      {r.sanitize_ms:8.1f} ms")
    if r.g2p_ms:
        print(f"    preflight g2p {r.g2p_ms:8.1f} ms   (diagnostic, not in TTFA)")
    print(f"    synthesis     {r.synth_ms:8.1f} ms")
    if r.status == "OK":
        print(f"    write wav     {r.write_ms:8.1f} ms")
        print(f"    player spawn  {r.spawn_ms:8.1f} ms   ({r.played})")
        print(f"    TIME TO FIRST AUDIO  {r.ttfa_s:6.2f} s"
              f"   {verdict} vs {tol:.1f}s tolerance")
        print(f"    audio         {r.audio_s:8.2f} s   (RTF {r.rtf:.3f})")
    print(f"    wall          {r.wall_ms / 1000:8.2f} s   (incl. preflight)")
    if r.wav and r.wav != "(deleted)":
        print(f"    wav           {r.wav}")


def print_summary(results: list[Result], tol: float, sort: str) -> None:
    rows = list(results)
    if sort == "ttfa":
        rows.sort(key=lambda r: -r.ttfa_ms)
    elif sort == "chars":
        rows.sort(key=lambda r: -r.chars_in)

    hdr = (f"{'item':<5} {'sanitizer':<11} {'st':<5} {'c':<1} "
           f"{'chars':>5} {'phon':>5} {'bat':>4} {'maxb':>5} "
           f"{'san_ms':>7} {'synth_s':>8} {'TTFA_s':>7} {'<=' + f'{tol:g}s':>6} "
           f"{'audio_s':>8} {'rtf':>6}")
    print("\n" + hdr)
    print("-" * len(hdr))
    for r in rows:
        ok = r.status == "OK"
        verdict = ("PASS" if r.ttfa_s <= tol else "FAIL") if ok else "-"
        print(f"{r.item:<5} {r.san:<11} {r.status:<5} {'C' if r.cold else ' ':<1} "
              f"{r.chars_in:>5} {r.phonemes:>5} {r.batches:>4} {r.max_batch:>5} "
              f"{r.sanitize_ms:>7.1f} {r.synth_ms / 1000:>8.2f} "
              f"{r.ttfa_s:>7.2f} {verdict:>6} "
              f"{r.audio_s:>8.2f} {r.rtf:>6.3f}")

    ok = [r for r in results if r.status == "OK"]
    bad = [r for r in results if r.status != "OK"]
    print("-" * len(hdr))
    print(f"{len(results)} runs: {len(ok)} OK, "
          f"{sum(1 for r in bad if r.status == 'CRASH')} CRASH, "
          f"{sum(1 for r in bad if r.status == 'ERROR')} ERROR")
    if bad:
        for r in bad:
            print(f"  {r.status:<5} {r.item:<5} [{r.san}]  {r.detail}")
    if ok:
        ttfas = sorted(r.ttfa_s for r in ok)
        n = len(ttfas)
        passed = sum(1 for v in ttfas if v <= tol)
        print(f"\nTTFA vs {tol:g}s tolerance (the #9 number):")
        print(f"  pass {passed}/{n}  ({100 * passed / n:.0f}%)   "
              f"fail {n - passed}/{n}")
        print(f"  min {ttfas[0]:.2f}s   median {ttfas[n // 2]:.2f}s   "
              f"p90 {ttfas[min(n - 1, int(n * 0.9))]:.2f}s   max {ttfas[-1]:.2f}s")
        worst = sorted(ok, key=lambda r: -r.ttfa_ms)[:8]
        print("  slowest:")
        for r in worst:
            print(f"    {r.item:<5} [{r.san:<11}] {r.ttfa_s:6.2f}s  "
                  f"{r.chars_in:>5} chars, {r.audio_s:6.2f}s audio"
                  f"{'   (cold)' if r.cold else ''}"
                  f"{'   OVER' if r.ttfa_s > tol else ''}")
        cold = [r for r in ok if r.cold]
        if cold:
            warm = [r for r in ok if not r.cold]
            print(f"\n  cold first synthesis: {cold[0].item} at "
                  f"{cold[0].ttfa_s:.2f}s TTFA "
                  f"({cold[0].synth_ms / 1000:.2f}s synth). "
                  f"{len(warm)} warm runs follow.")


def write_tsv(path: Path, results: list[Result]) -> None:
    lines = ["\t".join(TSV_FIELDS)]
    for r in results:
        lines.append("\t".join(
            f"{getattr(r, f):.1f}" if isinstance(getattr(r, f), float)
            else str(getattr(r, f)) for f in TSV_FIELDS))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"\nwrote {path}")


# --------------------------------------------------------------------------
# input selection
# --------------------------------------------------------------------------


def resolve_inputs(args) -> list[tuple[str, str]]:
    """-> [(item_id, text)]"""
    out: list[tuple[str, str]] = []
    corpus = Path(args.corpus_dir)

    ids: list[str] = []
    for spec in args.id:
        ids.extend(x for x in spec.split(",") if x)
    if args.all:
        ids = sorted(p.stem for p in corpus.glob("*.txt"))
    elif args.kind:
        pre = "r" if args.kind == "real" else "s"
        ids = sorted(p.stem for p in corpus.glob(f"{pre}*.txt"))

    for i in ids:
        p = corpus / f"{i}.txt"
        if not p.exists():
            raise SystemExit(f"bench: no corpus item {i} at {p}")
        out.append((i, p.read_text(encoding="utf-8")))

    for f in args.files:
        p = Path(f)
        if not p.exists():
            raise SystemExit(f"bench: no such file {p}")
        out.append((p.stem[:16], p.read_text(encoding="utf-8")))

    if args.text:
        out.append(("stdin", args.text))

    return out


# --------------------------------------------------------------------------


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        prog="bench",
        description="Audition synthesized rewrites and time them.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""examples:
  bench/bench --id r09                       one corpus item, sanitized, played
  bench/bench --id r02 --sanitizer none,candidate   A/B the same item
  bench/bench --all --play none --tsv /tmp/run.tsv  the whole corpus, silent
  bench/bench notes.txt --voice af_bella     an arbitrary text file
""")
    ap.add_argument("files", nargs="*", help="text files to speak")
    ap.add_argument("--id", action="append", default=[],
                    help="corpus item id(s), e.g. r09 or r01,s37")
    ap.add_argument("--all", action="store_true", help="every corpus item")
    ap.add_argument("--kind", choices=["real", "synthetic"],
                    help="every real (rNN) or synthetic (sNN) item")
    ap.add_argument("--text", help="literal text instead of a file")
    ap.add_argument("--corpus-dir", default=str(DEFAULT_CORPUS))

    ap.add_argument("-s", "--sanitizer", default="candidate",
                    help="comma-separated sanitizer names; each input is run "
                         "through each, in order (this is the A/B mechanism)")
    ap.add_argument("--list-sanitizers", action="store_true")
    ap.add_argument("--max-run", type=int, default=400,
                    help="rule A: input chars allowed between chunk boundaries")
    ap.add_argument("--boundary", default=".", choices=[".", ","],
                    help="rule A/B: the punctuation inserted")
    ap.add_argument("--respell", action="store_true",
                    help="enable rule L (lives->livz); trigger NOT established")

    ap.add_argument("-v", "--voice", default="af_heart")
    ap.add_argument("--list-voices", action="store_true")
    ap.add_argument("--speed", type=float, default=1.0)
    ap.add_argument("--lang", default="en-us")

    ap.add_argument("--play", choices=["full", "spawn", "none"], default=None,
                    help="full: hear it out. spawn: start the player, measure "
                         "the spawn, stop it. none: no player at all. "
                         "default full for one run, none for many")
    ap.add_argument("--no-play", action="store_true", help="alias for --play none")
    ap.add_argument("--player", default=DEFAULT_PLAYER,
                    help=f"player command (default {DEFAULT_PLAYER}, "
                         "$CLAUDISH_PLAYER honoured)")

    ap.add_argument("--tolerance", type=float, default=3.0,
                    help="TTFA pass/fail threshold in seconds (default 3.0)")
    ap.add_argument("--warmup", action="store_true",
                    help="throwaway synthesis first, so no item is cold")
    ap.add_argument("--no-preflight", action="store_true",
                    help="skip the phoneme/batch diagnostic")
    ap.add_argument("--sort", choices=["id", "ttfa", "chars"], default="id")
    ap.add_argument("--out-dir", default=str(DEFAULT_OUT))
    ap.add_argument("--keep-wav", action=argparse.BooleanOptionalAction, default=True)
    ap.add_argument("--tsv", help="write the full per-run table here")
    ap.add_argument("--show-text", action="store_true",
                    help="print the sanitized text before speaking it")
    ap.add_argument("--quiet", action="store_true", help="summary table only")

    args = ap.parse_args(argv)

    if args.list_sanitizers:
        for name, s in sorted(sanitizers.REGISTRY.items()):
            print(f"{name:<12} {s.doc}")
            if s.rules:
                for line in s.rules.splitlines():
                    print(f"             {line}")
        return 0

    inputs = resolve_inputs(args)
    sans = [x for x in args.sanitizer.split(",") if x]
    for s in sans:
        sanitizers.get(s)
    if not inputs and not args.list_voices:
        ap.error("nothing to speak: pass a file, --id, --all, --kind or --text")

    n_runs = len(inputs) * len(sans)
    if args.no_play:
        args.play = "none"
    if args.play is None:
        args.play = "full" if n_runs == 1 else "none"

    Path(args.out_dir).mkdir(parents=True, exist_ok=True)
    opts = sanitizers.Opts(max_run=args.max_run, boundary=args.boundary,
                           respell=args.respell)

    # ---- load the model ONCE ---------------------------------------------
    model = KROOT / "kokoro-v1.0.onnx"
    voices = KROOT / "voices-v1.0.bin"
    for p in (model, voices):
        if not p.exists():
            raise SystemExit(f"bench: missing {p} -- see "
                             "docs/research/kokoro-onnx-provisioning.md")
    t = time.perf_counter()
    from kokoro_onnx import Kokoro
    import soundfile as sf
    kok = Kokoro(str(model), str(voices))
    load_s = time.perf_counter() - t

    if args.list_voices:
        print(" ".join(sorted(kok.voices)))
        return 0
    if args.voice not in kok.voices:
        raise SystemExit(f"bench: unknown voice {args.voice!r}; "
                         f"try --list-voices")

    if not args.quiet:
        print(f"bench: model loaded in {load_s:.2f}s "
              f"(once, reused for all {n_runs} runs)")
        print(f"bench: voice={args.voice} speed={args.speed} lang={args.lang} "
              f"play={args.play} player={args.player!r}")
        print(f"bench: sanitizers={','.join(sans)}  "
              f"max_run={args.max_run} boundary={args.boundary!r} "
              f"respell={args.respell}")
        print(f"bench: tolerance={args.tolerance}s  out_dir={args.out_dir}")

    warm = False
    if args.warmup:
        t = time.perf_counter()
        kok.create("Warming up.", voice=args.voice, lang=args.lang)
        warm = True
        if not args.quiet:
            print(f"bench: warm-up synthesis {time.perf_counter() - t:.2f}s "
                  "(so no measured item is cold)")

    results: list[Result] = []
    for item, text in inputs:
        for san in sans:
            cold = not warm and not results
            r = bench_one(kok, sf, text, item, san, args, opts, cold)
            if warm is False:
                warm = True  # only the very first synthesis is cold
            results.append(r)
            if args.show_text:
                print(f"\n--- {item} [{san}] sanitized ---")
                print(sanitizers.run(san, text, opts))
                print("--- end ---")
            if not args.quiet:
                print_detail(r, args.tolerance)

    if len(results) > 1 or args.quiet:
        print_summary(results, args.tolerance, args.sort)
    if args.tsv:
        write_tsv(Path(args.tsv), results)

    # A CRASH is data -- s35 and s37 are documented to raise -- so it does not
    # make the harness fail. An ERROR is the harness itself misbehaving.
    return 1 if any(r.status == "ERROR" for r in results) else 0


if __name__ == "__main__":
    sys.exit(main())
