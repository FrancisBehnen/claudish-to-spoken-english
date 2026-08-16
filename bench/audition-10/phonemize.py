#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# Count phonemes for a whole population, without synthesizing any of it.
#
# The audition measures that speech duration tracks PHONEMES almost exactly
# (audio_s = 0.355 + 0.05488 * phonemes, R^2 0.995 over 27 items) and tracks
# characters only loosely, because phoneme density runs 1.2-2.3 per prose
# character depending on how token-heavy the text is. So the threshold sweep is
# worth doing on real phoneme counts rather than on a character fit.
#
# This runs the same espeak G2P bench uses -- kok.tokenizer.phonemize, after the
# same sanitizer -- over every message in a population, and writes one row per
# message. It never calls create(), so it produces no audio and costs no CPU
# worth speaking of.
#
#   KOKORO_ROOT=~/.local/share/kokoro \
#     ~/.local/share/kokoro/venv/bin/python bench/audition-10/phonemize.py \
#       <extract-dir> <out.tsv> [sanitizer]
#
# No LLM, no hook.
# ---------------------------------------------------------------------------
import json
import os
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(REPO / "bench"))
import sanitizers  # noqa: E402

KROOT = pathlib.Path(os.environ.get("KOKORO_ROOT",
                                    pathlib.Path.home() / ".local/share/kokoro"))


def prose_len(text: str) -> int:
    fence = False
    keep = []
    for line in text.split("\n"):
        if line.startswith("```"):
            fence = not fence
            continue
        if not fence:
            keep.append(line)
    return len(re.sub(r"\s", "", "\n".join(keep)))


def main() -> int:
    exdir = pathlib.Path(sys.argv[1])
    out = pathlib.Path(sys.argv[2])
    san_name = sys.argv[3] if len(sys.argv) > 3 else "candidate"
    opts = sanitizers.Opts()

    def san(text):
        return sanitizers.run(san_name, text, opts)

    from kokoro_onnx import Kokoro
    kok = Kokoro(str(KROOT / "kokoro-v1.0.onnx"), str(KROOT / "voices-v1.0.bin"))

    rows = [["pop", "id", "prose_len", "phonemes"]]

    # population 1: every assistant message in the local transcripts
    for n, line in enumerate(
            (exdir / "all.jsonl").read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        d = json.loads(line)
        ph = kok.tokenizer.phonemize(san(d["txt"]), "en-us")
        rows.append(["transcript", f"{d['sess'][:8]}:{d['uuid'][:8]}",
                     str(prose_len(d["txt"])), str(len(ph))])

    # population 2: the speech corpus
    for p in sorted((REPO / "corpus" / "spoken").glob("*.txt")):
        t = p.read_text(encoding="utf-8")
        ph = kok.tokenizer.phonemize(san(t), "en-us")
        rows.append(["corpus", p.stem, str(prose_len(t)), str(len(ph))])

    # population 3: the twelve real pairs, raw assistant message vs its rewrite.
    # Same sanitizer both sides, so the difference is the LLM's and nothing else.
    for p in sorted((REPO / "corpus" / "source").glob("r*.txt")):
        for kind, d in (("source", "source"), ("rewrite", "spoken")):
            t = (REPO / "corpus" / d / p.name).read_text(encoding="utf-8")
            ph = kok.tokenizer.phonemize(san(t), "en-us")
            rows.append([kind, p.stem, str(prose_len(t)), str(len(ph))])

    out.write_text("\n".join("\t".join(r) for r in rows) + "\n", encoding="utf-8")
    print(f"wrote {len(rows) - 1} rows to {out} (sanitizer={san_name})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
