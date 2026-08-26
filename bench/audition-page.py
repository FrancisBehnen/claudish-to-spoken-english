#!/usr/bin/env python3
"""Build the local listening page for the #8, #9 and #10 auditions.

    python3 bench/audition-page.py
    open ~/.local/share/kokoro/bench/audition.html

The page is written NEXT TO the wav directories on purpose:

    ~/.local/share/kokoro/bench/audition.html
    ~/.local/share/kokoro/bench/audition-8/<item>.<variant>.af_heart.wav
    ~/.local/share/kokoro/bench/audition-9/<item>.candidate.<voice>.wav
    ~/.local/share/kokoro/bench/audition-10/<item>.candidate.af_heart.wav
    ~/.local/share/kokoro/bench/audition-11/<item>.<variant>.bf_emma.wav

so every `<audio src>` is a relative sibling and the page works from a
`file://` URL with no server. The wavs are ~195 MB and are not committed; this
generator is, the page it writes is not.

NOTHING IN HERE IS A DECISION, and nothing in here or in the page it writes is
a claim about how anything sounds. The page collects Francis' verdicts; it
pre-fills none of them and it grades none of them.

Everything on the page is DERIVED:

  * the pairs come from globbing the wavs that exist on disk, so a variant
    synthesized after this was written appears without an edit here;
  * the pronounced text comes from importing `bench/sanitizers.py` and running
    the real sanitizer over the real corpus file, never from transcribing a
    document -- the page therefore cannot drift from what was synthesized;
  * durations come from the wav headers, character counts from the text,
    hazard classes and `prose_len` from `corpus/manifest.tsv`, bands from
    `bench/audition-10/items.tsv`, and each variant's one-line description
    from the sanitizer registry itself.

Phoneme-identity between the two sides of a pair is computed with
kokoro-onnx's own tokenizer when it is importable (this script re-execs itself
under the Kokoro venv to get it); it is recorded in the exported data and is
deliberately NOT shown on the page while the pair is blinded, so that an "I
heard a difference" on a phoneme-identical pair stays visible afterwards.

No LLM call, no synthesis, no playback, no network.
"""

from __future__ import annotations

import argparse
import csv
import difflib
import hashlib
import html
import json
import os
import re
import sys
import wave
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
sys.path.insert(0, str(REPO))

# See bench/bench.py: sanitizers.py now lives at speech/sanitizers.py, on the
# plugin's runtime path. Registry and `run()` are unchanged.
from speech import sanitizers  # noqa: E402


# --------------------------------------------------------------------------
# the Kokoro venv, for the phoneme-identity flag only
# --------------------------------------------------------------------------


def phonemizer(kokoro_root: Path):
    """-> callable(text) -> phoneme string, or None.

    Re-execs once under the Kokoro venv if the tokenizer is not importable
    here. The tokenizer is espeak G2P only: it loads no model and synthesizes
    nothing.
    """
    try:
        from kokoro_onnx.tokenizer import Tokenizer  # type: ignore
    except Exception:
        py = kokoro_root / "venv" / "bin" / "python"
        if os.environ.get("_AUDITION_PAGE_REEXEC") or not py.is_file():
            return None
        os.environ["_AUDITION_PAGE_REEXEC"] = "1"
        os.execv(str(py), [str(py), str(Path(__file__).resolve()), *sys.argv[1:]])
    tok = Tokenizer()
    cache: dict[str, str] = {}

    def run(text: str) -> str | None:
        if text not in cache:
            try:
                cache[text] = tok.phonemize(text, "en-us")
            except Exception:
                return None
        return cache[text]

    return run


# --------------------------------------------------------------------------
# reading what is on disk
# --------------------------------------------------------------------------

WAV_RE = re.compile(r"^(?P<item>[^.]+)\.(?P<variant>[^.]+)\.(?P<voice>[^.]+)\.wav$")


def read_tsv(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open(newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def wav_seconds(path: Path) -> float | None:
    try:
        with wave.open(str(path), "rb") as w:
            return w.getnframes() / float(w.getframerate())
    except Exception:
        return None


@lru_cache(maxsize=None)
def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def scan(dirpath: Path) -> list[dict]:
    """-> [{item, variant, voice, wav (name), path}] for every wav in dirpath."""
    out = []
    if not dirpath.is_dir():
        return out
    for p in sorted(dirpath.glob("*.wav")):
        m = WAV_RE.match(p.name)
        if not m:
            continue
        out.append({"item": m["item"], "variant": m["variant"],
                    "voice": m["voice"], "wav": p.name, "path": p})
    return out


# --------------------------------------------------------------------------
# where an item's text comes from
# --------------------------------------------------------------------------


def text_sources(repo: Path):
    """-> callable(item_id) -> (text, provenance) or (None, why-not).

    The resolution order mirrors how the wavs were actually made:
    `corpus/spoken/` is the bench default; `bench/audition-10/items/` is #10's
    own short-message set; `raw-rNN` / `rew-rNN` are #10's raw-vs-rewritten
    pairs, staged by `bench/audition-10/run.sh` from `corpus/source/` and
    `corpus/spoken/`.
    """
    def resolve(item: str) -> tuple[str | None, str]:
        cands: list[tuple[Path, str]] = [
            (repo / "corpus" / "spoken" / f"{item}.txt", f"corpus/spoken/{item}.txt"),
            (repo / "bench" / "audition-10" / "items" / f"{item}.txt",
             f"bench/audition-10/items/{item}.txt"),
        ]
        m = re.fullmatch(r"(raw|rew)-(.+)", item)
        if m:
            sub = "source" if m[1] == "raw" else "spoken"
            cands.insert(0, (repo / "corpus" / sub / f"{m[2]}.txt",
                            f"corpus/{sub}/{m[2]}.txt"))
        for path, label in cands:
            if path.is_file():
                return path.read_text(encoding="utf-8"), label
        return None, "no corpus text found for " + item

    return resolve


# --------------------------------------------------------------------------
# the #8 axes
# --------------------------------------------------------------------------
#
# Frequency order, as `docs/decisions/sanitizer-audition.md` has it: backticks
# first, code blocks last. This table is the ONLY hand-written mapping in the
# file -- it says which registered sanitizer belongs to which axis and which
# corpus hazard classes the axis is about. Both are structure, not judgement.
# A variant that is not listed here still reaches the page, in a trailing
# group of its own, so registering a new sanitizer never silently drops it.

AXES = [
    # #11's ship blocker 1. NOT an axis: it is every axis at once, which is
    # exactly why it needs its own group -- `n` is 0 and the page prints the
    # title without an "Axis N" prefix, because calling the composition an
    # axis would misdescribe what the pair moves.
    {"key": "settled", "n": 0, "title": "The settled set, composed",
     "variants": ["settled"], "classes": []},
    {"key": "ticks", "n": 1, "title": "Backtick prosody",
     "variants": ["tick-strip", "tick-pause"],
     "classes": ["MD-BACKTICK"]},
    {"key": "linebreak", "n": 2, "title": "The line-break replacement, and the crash",
     "variants": ["lb-period", "lb-comma", "lb-auto"],
     "classes": ["SPLIT-NEWLINE", "CHUNK-510-PUNCT"]},
    {"key": "paths", "n": 3, "title": "Paths",
     "variants": ["path-nolead", "path-basename", "path-shorten", "path-expand",
                  "path-short-nolead"],
     "classes": ["PATH-SLASH", "PATH-EXT"]},
    {"key": "markdown", "n": 4, "title": "Markdown: swallowed or stripped",
     "variants": ["md-swallow", "md-strip-plus"],
     "classes": ["MD-ASTERISK", "MD-HASH"]},
    {"key": "scream", "n": 5, "title": "SCREAMING_SNAKE_CASE",
     "variants": ["scream-asis", "scream-spell", "scream-drop"],
     "classes": ["ID-SCREAM"]},
    {"key": "urls", "n": 6, "title": "URLs",
     "variants": ["url-full", "url-domain"],
     "classes": ["URL"]},
    {"key": "code", "n": 7, "title": "How a skipped code block is announced",
     "variants": ["cb-long", "cb-count", "cb-short", "cb-silent"],
     "classes": ["MD-FENCE"]},
    # #13's two never-auditioned rules. Numbered on from #8's seven because
    # they are additions to that set, not a re-run of it.
    {"key": "flags", "n": 8, "title": "Commas around flag names and bare identifiers",
     "variants": ["flag-pause"],
     "classes": ["FLAG-SHORT", "FLAG-LONG", "ID-SCREAM", "ID-SNAKE", "ID-ASSIGN"]},
    {"key": "exts", "n": 9, "title": "Pronounceable file extensions",
     "variants": ["ext-word"],
     "classes": ["PATH-EXT", "PATH-HYPHEN-EXT", "PATH-EXTBARE"]},
    {"key": "other", "n": 10, "title": "Other registered variants",
     "variants": [], "classes": []},
]
AXIS_OF = {v: ax["key"] for ax in AXES for v in ax["variants"]}
AXIS_ORDER = {ax["key"]: i for i, ax in enumerate(AXES)}

# The two sides of every #8 pair. `base` is the reference; `none` is the
# untouched-text control, which belongs to no single axis and is filed under
# the first axis its item appears in.
REFERENCE = "base"
CONTROL = "none"


def registry_rank(name: str) -> int:
    """Variants in the order `sanitizers.py` registers them, which is the order
    the audition document lists them in. Anything unregistered sorts last."""
    order = list(sanitizers.REGISTRY)
    return order.index(name) if name in order else len(order)


def item_sort_key(item: str):
    """Real rewrites (`rNN`) before synthetic fixtures (`sNN`), numeric."""
    m = re.fullmatch(r"([a-z-]*)(\d*)", item)
    prefix, num = (m[1], m[2]) if m else (item, "")
    rank = {"r": 0, "s": 1}.get(prefix, 2)
    return (rank, prefix, int(num) if num else 0, item)


# --------------------------------------------------------------------------
# diffing, for "what the rule changed", made visible
# --------------------------------------------------------------------------

TOKEN_RE = re.compile(r"\S+|\s+")


# An equal run this short between two changes is coincidence, not context: a
# 12-line code block replaced by "Code block, twelve lines." shares its braces
# and newlines with the replacement, and reporting those as kept turns the
# whole block into shrapnel. Folded into the change instead.
MERGE_UNDER = 10


def diff_tokens(before: str, after: str) -> list[list]:
    """-> [[op, text], ...] with op in '=' (kept), '+' (added), '-' (removed).

    Word-level `difflib`, which is the standard library doing the work, plus
    one coalescing pass. This is not a diff engine; it is a legibility aid
    over the sanitizer's own output -- removed text before added text, so a
    replaced span reads as one before and one after rather than alternating.
    """
    a = TOKEN_RE.findall(before)
    b = TOKEN_RE.findall(after)
    segs = [(tag == "equal", "".join(a[i1:i2]), "".join(b[j1:j2]))
            for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(
                None, a, b, autojunk=False).get_opcodes()]

    fold = {i for i in range(1, len(segs) - 1)
            if segs[i][0] and not segs[i - 1][0] and not segs[i + 1][0]
            and len(segs[i][1].strip()) < MERGE_UNDER}

    out: list[list] = []
    i, n = 0, len(segs)
    while i < n:
        if segs[i][0] and i not in fold:
            out.append(["=", segs[i][1]])
            i += 1
            continue
        gone, came = [], []
        while i < n and (not segs[i][0] or i in fold):
            gone.append(segs[i][1])
            came.append(segs[i][2])
            i += 1
        for op, text in (("-", "".join(gone)), ("+", "".join(came))):
            if text:
                out.append([op, text])
    return out


def coin(key: str) -> int:
    """A stable, arbitrary bit per pair: which side is A.

    Seeded off the pair id rather than a clock, so the assignment survives a
    regeneration and the verdicts stay interpretable. It is recorded in the
    export either way.
    """
    return hashlib.sha256(("audition-page/ab/" + key).encode()).digest()[0] & 1


# --------------------------------------------------------------------------
# building the three sections
# --------------------------------------------------------------------------


def variant_doc(name: str) -> str:
    s = sanitizers.REGISTRY.get(name)
    return s.doc if s else ""


def build_section1(wavs, resolve, manifest, phon, skipped) -> dict:
    by_item: dict[str, dict[str, dict]] = {}
    for w in wavs:
        by_item.setdefault(w["item"], {})[w["variant"]] = w

    pairs: list[dict] = []
    for item, variants in by_item.items():
        if REFERENCE not in variants:
            skipped.append(f"{item}: no {REFERENCE} wav, so there is nothing to "
                           f"pair {', '.join(sorted(variants))} against")
            continue
        text, prov = resolve(item)
        if text is None:
            skipped.append(f"{item}: {prov} ({len(variants)} wavs)")
            continue

        row = manifest.get(item, {})
        others = sorted((v for v in variants if v != REFERENCE),
                        key=lambda v: (0 if v == CONTROL else 1,
                                       AXIS_ORDER.get(AXIS_OF.get(v, "other"), 99),
                                       registry_rank(v)))
        # `none` is the control for whichever axis this item first appears in.
        first_axis = next((AXIS_OF.get(v, "other") for v in others
                           if v != CONTROL), "other")
        clean: dict[str, str] = {}
        for v in [REFERENCE, *others]:
            clean[v] = sanitizers.run(v, text, sanitizers.Opts())

        for v in others:
            axis = first_axis if v == CONTROL else AXIS_OF.get(v, "other")
            pid = f"{item}:{v}"
            ref_is_a = coin(pid) == 0
            sides = {}
            for side, name in (("a", REFERENCE if ref_is_a else v),
                               ("b", v if ref_is_a else REFERENCE)):
                w = variants[name]
                sides[side] = {
                    "variant": name,
                    "wav": f"{w['path'].parent.name}/{w['wav']}",
                    "seconds": wav_seconds(w["path"]),
                    "chars": len(clean[name]),
                    "diff": diff_tokens(text, clean[name]),
                }
            pa, pb = (phon(clean[sides["a"]["variant"]]) if phon else None,
                      phon(clean[sides["b"]["variant"]]) if phon else None)
            pairs.append({
                "id": pid, "item": item, "axis": axis,
                "variant": v, "reference": REFERENCE,
                "base_side": "a" if ref_is_a else "b",
                "kind": row.get("kind", ""),
                "prose_len": row.get("prose_len", ""),
                "hazards": [c for c in (row.get("hazard_classes") or "").split(",") if c],
                "provenance": prov,
                "original": text,
                "chars_in": len(text),
                "a": sides["a"], "b": sides["b"],
                "text_identical": clean[sides["a"]["variant"]] == clean[sides["b"]["variant"]],
                "phonemes_identical": (None if (pa is None or pb is None) else pa == pb),
                "phonemes_a": (len(pa) if pa is not None else None),
                "phonemes_b": (len(pb) if pb is not None else None),
                "wav_identical": sha(variants[sides["a"]["variant"]]["path"])
                == sha(variants[sides["b"]["variant"]]["path"]),
            })

    axes = []
    real_items = {i for i, r in manifest.items() if r.get("kind") == "real"}
    for ax in AXES:
        mine = [p for p in pairs if p["axis"] == ax["key"]]
        if not mine:
            continue
        mine.sort(key=lambda p: (item_sort_key(p["item"]),
                                 0 if p["variant"] == CONTROL else 1,
                                 registry_rank(p["variant"])))
        carried = sorted(
            i for i in real_items
            if set(ax["classes"]) & set(
                (manifest[i].get("hazard_classes") or "").split(","))
        )
        seen = sorted({v for p in mine for v in (p["a"]["variant"], p["b"]["variant"])},
                      key=lambda v: (v != CONTROL, v != REFERENCE, registry_rank(v)))
        axes.append({
            "key": ax["key"], "n": ax["n"], "title": ax["title"],
            "classes": ax["classes"],
            "real_carriers": carried, "real_total": len(real_items),
            "legend": [{"variant": v, "doc": variant_doc(v)} for v in seen],
            "pairs": mine,
            "seconds": sum((p[s]["seconds"] or 0) for p in mine for s in "ab"),
        })
    return {
        "axes": axes,
        "pairs": sum(len(a["pairs"]) for a in axes),
        # Aggregate only. WHICH pairs these are is in the export, never on the
        # page while blinded -- but the count is what makes "no audible
        # difference" visibly a real answer rather than a way out.
        "identical_phonemes": sum(1 for p in pairs if p["phonemes_identical"]),
        "identical_wavs": sum(1 for p in pairs if p["wav_identical"]),
    }


def build_section2(wavs, resolve, manifest, skipped) -> dict:
    by_item: dict[str, list[dict]] = {}
    for w in wavs:
        by_item.setdefault(w["item"], []).append(w)

    items = []
    for item in sorted(by_item, key=item_sort_key):
        text, prov = resolve(item)
        if text is None:
            skipped.append(f"{item}: {prov} ({len(by_item[item])} voice wavs)")
            continue
        row = manifest.get(item, {})
        sans = {w["variant"] for w in by_item[item]}
        san = sorted(sans)[0]
        clean = sanitizers.run(san, text, sanitizers.Opts())
        voices = sorted(by_item[item], key=lambda w: w["voice"])
        # A stable, arbitrary presentation order per item, so the blind labels
        # V1..VN are not the alphabetical order the wav names sort in.
        order = sorted(range(len(voices)),
                       key=lambda i: hashlib.sha256(
                           f"audition-page/voice/{item}/{voices[i]['voice']}".encode()
                       ).hexdigest())
        items.append({
            "id": item, "sanitizer": san, "provenance": prov,
            "kind": row.get("kind", ""), "prose_len": row.get("prose_len", ""),
            "hazards": [c for c in (row.get("hazard_classes") or "").split(",") if c],
            "chars_in": len(text),
            "diff": diff_tokens(text, clean),
            "voices": [{
                "voice": voices[i]["voice"],
                "wav": f"{voices[i]['path'].parent.name}/{voices[i]['wav']}",
                "seconds": wav_seconds(voices[i]["path"]),
            } for i in order],
            "seconds": sum((wav_seconds(w["path"]) or 0) for w in voices),
        })
    return {"items": items, "count": len(items)}


LEN_GROUPS = [
    ("ACK", "Band A — bare acknowledgement"),
    ("FCT", "Band B — a short message carrying a fact"),
    ("CORPUS", "Corpus fixtures, for continuity"),
    ("PAIR", "A raw assistant message and its rewrite"),
]


def build_section3(wavs, resolve, manifest, items_tsv, skipped) -> dict:
    bands = {r["id"]: r for r in items_tsv}
    groups: dict[str, list[dict]] = {k: [] for k, _ in LEN_GROUPS}
    for w in wavs:
        item = w["item"]
        text, prov = resolve(item)
        if text is None:
            skipped.append(f"{item}: {prov}")
            continue
        row = manifest.get(item, {})
        band = bands.get(item, {})
        if band.get("band") in groups:
            key = band["band"]
        elif re.match(r"^(raw|rew)-", item):
            key = "PAIR"
        else:
            key = "CORPUS"
        clean = sanitizers.run(w["variant"], text, sanitizers.Opts())
        groups[key].append({
            "id": item, "sanitizer": w["variant"], "provenance": prov,
            "wav": f"{w['path'].parent.name}/{w['wav']}",
            "seconds": wav_seconds(w["path"]),
            "chars_in": len(text), "chars_out": len(clean),
            "prose_len": band.get("prose_len") or row.get("prose_len", ""),
            "note": band.get("note", ""), "origin": band.get("origin", ""),
            "hazards": [c for c in (row.get("hazard_classes") or "").split(",") if c],
            "diff": diff_tokens(text, clean),
        })

    out = []
    for key, title in LEN_GROUPS:
        rows = groups[key]
        if not rows:
            continue
        rows.sort(key=lambda r: (r["seconds"] or 0, r["id"]))
        out.append({"key": key, "title": title, "items": rows,
                    "seconds": sum((r["seconds"] or 0) for r in rows)})
    return {"groups": out, "count": sum(len(g["items"]) for g in out)}


# --------------------------------------------------------------------------
# the page
# --------------------------------------------------------------------------

CSS = """
*,*::before,*::after{box-sizing:border-box}
:root{
  color-scheme:light dark;
  --bg:#f7f7f5; --panel:#fff; --sunk:#f0f0ec; --text:#1a1a17; --dim:#61615a;
  --line:#dad9d1; --line2:#eceae2; --accent:#2b56c6; --accent-bg:#e6ebfa;
  --ins-bg:#d7f0dd; --ins-fg:#0d4a22; --del-bg:#fadcdc; --del-fg:#7c1a1a;
  --btn:#eceae4; --btn-h:#e0ded6; --done:#1a6b3c; --done-bg:#e2f2e7;
  --warn:#8a5200; --mono:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){
  --bg:#16171a; --panel:#1e2024; --sunk:#181a1d; --text:#e8e8e4; --dim:#9d9d95;
  --line:#34373d; --line2:#282b30; --accent:#8fb0ff; --accent-bg:#1f2740;
  --ins-bg:#1d3c27; --ins-fg:#8fe0a8; --del-bg:#40201f; --del-fg:#f0a3a0;
  --btn:#2a2d33; --btn-h:#353941; --done:#7fd6a0; --done-bg:#1c2f23;
  --warn:#e0b06a;
}}
:root[data-theme="dark"]{
  --bg:#16171a; --panel:#1e2024; --sunk:#181a1d; --text:#e8e8e4; --dim:#9d9d95;
  --line:#34373d; --line2:#282b30; --accent:#8fb0ff; --accent-bg:#1f2740;
  --ins-bg:#1d3c27; --ins-fg:#8fe0a8; --del-bg:#40201f; --del-fg:#f0a3a0;
  --btn:#2a2d33; --btn-h:#353941; --done:#7fd6a0; --done-bg:#1c2f23;
  --warn:#e0b06a;
}
html{background:var(--bg)}
body{margin:0;background:var(--bg);color:var(--text);
  font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif}
main{max-width:1180px;margin:0 auto;padding:0 18px 140px}
h1{font-size:20px;margin:0}
h2{font-size:18px;margin:38px 0 6px;padding-top:10px;border-top:2px solid var(--line)}
h3{font-size:15px;margin:26px 0 8px;letter-spacing:.01em}
p{margin:6px 0}
a{color:var(--accent)}
code,.mono{font-family:var(--mono);font-size:.92em}
.dim{color:var(--dim)}
.small{font-size:12.5px}
/* ---- top bar ---- */
header{position:sticky;top:0;z-index:20;background:var(--panel);
  border-bottom:1px solid var(--line);padding:9px 18px}
.bar{max-width:1180px;margin:0 auto;display:flex;flex-wrap:wrap;gap:10px 16px;align-items:center}
.bar .grow{flex:1 1 auto}
.prog{font-variant-numeric:tabular-nums;font-size:13px;color:var(--dim)}
.prog b{color:var(--text)}
button{font:inherit;color:var(--text);background:var(--btn);border:1px solid var(--line);
  border-radius:7px;padding:5px 10px;cursor:pointer}
button:hover{background:var(--btn-h)}
button:focus-visible{outline:2px solid var(--accent);outline-offset:1px}
.toggle[aria-pressed="true"]{background:var(--accent-bg);border-color:var(--accent);
  color:var(--text);font-weight:600}
/* ---- cards ---- */
.card{background:var(--panel);border:1px solid var(--line);border-left:4px solid var(--line);
  border-radius:10px;padding:12px 14px;margin:12px 0;scroll-margin-top:104px}
.card.cur{border-left-color:var(--accent);box-shadow:0 0 0 1px var(--accent) inset}
.card.done{border-left-color:var(--done)}
.hd{display:flex;flex-wrap:wrap;gap:6px 12px;align-items:baseline;margin-bottom:8px}
.id{font-family:var(--mono);font-weight:700;font-size:15px}
.tag{font-size:11.5px;color:var(--dim);border:1px solid var(--line);border-radius:20px;
  padding:1px 8px;white-space:nowrap}
.tag.big{font-variant-numeric:tabular-nums;color:var(--text);border-color:var(--accent);
  background:var(--accent-bg);font-weight:600;font-size:12.5px}
.badge{margin-left:auto;font-size:12px;color:var(--done);font-weight:600}
/* ---- text blocks ---- */
.txt{font-family:var(--mono);font-size:12.6px;line-height:1.6;white-space:pre-wrap;
  word-break:break-word;background:var(--sunk);border:1px solid var(--line2);
  border-radius:7px;padding:8px 10px;margin:4px 0;max-height:8.4em;overflow:hidden;
  position:relative}
.txt.open{max-height:none}
.txt.clip::after{content:"";position:absolute;left:0;right:0;bottom:0;height:2.2em;
  background:linear-gradient(to bottom,transparent,var(--sunk))}
.lbl{font-size:11.5px;letter-spacing:.04em;color:var(--dim);margin-top:10px}
.more{font-size:12px;padding:2px 8px;margin-top:2px}
ins{background:var(--ins-bg);color:var(--ins-fg);text-decoration:none;border-radius:3px;
  padding:0 1px}
del{background:var(--del-bg);color:var(--del-fg);border-radius:3px;padding:0 1px}
.cols{display:grid;grid-template-columns:1fr 1fr;gap:12px}
@media (max-width:820px){.cols{grid-template-columns:1fr}}
.side{border:1px solid var(--line2);border-radius:8px;padding:8px 10px;min-width:0}
.side h4{margin:0 0 4px;font-size:13px;display:flex;gap:8px;align-items:baseline}
.side h4 .who{font-family:var(--mono);color:var(--dim);font-weight:600}
.play{font-weight:600}
.play.on{background:var(--accent-bg);border-color:var(--accent)}
.kbd{font-family:var(--mono);font-size:11px;color:var(--dim);border:1px solid var(--line);
  border-radius:4px;padding:0 4px;margin-left:4px}
/* ---- verdicts ---- */
.verdict{display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin-top:10px;
  padding-top:9px;border-top:1px dashed var(--line)}
.v[aria-pressed="true"]{background:var(--done-bg);border-color:var(--done);font-weight:600}
.note{flex:1 1 220px;min-width:160px;font:inherit;font-size:13px;color:var(--text);
  background:var(--sunk);border:1px solid var(--line);border-radius:7px;padding:5px 8px}
.reveal{margin-top:8px;font-size:12.5px;color:var(--dim)}
.reveal .mono{color:var(--text);font-weight:600}
.voices{display:flex;flex-wrap:wrap;gap:8px;margin:8px 0 2px}
.vc{border:1px solid var(--line2);border-radius:8px;padding:7px 9px;min-width:132px}
.vc.win{border-color:var(--done);background:var(--done-bg)}
.vc.out{opacity:.55}
.vc .row{display:flex;gap:8px;align-items:center;font-size:12px;margin-top:5px}
label{cursor:pointer}
/* ---- export ---- */
#export textarea{width:100%;height:290px;font-family:var(--mono);font-size:11.5px;
  color:var(--text);background:var(--sunk);border:1px solid var(--line);border-radius:8px;
  padding:9px;white-space:pre}
.note-box{border:1px solid var(--line);border-left:4px solid var(--warn);border-radius:8px;
  background:var(--panel);padding:10px 13px;margin:12px 0}
"""

JS = r"""
'use strict';
const D = JSON.parse(document.getElementById('data').textContent);
const KEY = 'claudish-audition/v1';
const el = (t, cls, txt) => { const n = document.createElement(t);
  if (cls) n.className = cls; if (txt != null) n.textContent = txt; return n; };
const secs = s => (s == null ? '—' : s.toFixed(1) + 's');
const mins = s => (s < 90 ? Math.round(s) + 's' : Math.round(s / 60) + ' min');

/* A pair id is `item:variant`, which is only unique WITHIN one A/B section: a
   second section over a second wav directory can carry the same pair against a
   different voice. `r06:none` did, in #13's sitting -- so one click on the
   bf_emma card also marked the af_heart card judged, revealed its labels,
   counted twice in the progress line and exported twice, which is why that
   export reads 20/87 for 19 verdicts. The store key is namespaced by section
   from here on, with the export's own section name, and so is the DOM id. */
const SEC1 = 'sanitizer', SEC4 = 'sanitizer-13', SEC5 = 'settled-set';
const pairKey = (section, id) => section + '/' + id;

let S = { blinded: true, theme: 'auto', pairs: {}, voices: {}, len: {} };
try { const raw = localStorage.getItem(KEY); if (raw) Object.assign(S, JSON.parse(raw)); }
catch (e) { /* a corrupt or unavailable store must not stop the page */ }
/* Verdicts saved under the old bare key belong to section 1: it was the only
   A/B section that existed when they were recorded. */
if (!S.keyed_by_section) {
  const moved = {};
  for (const k in S.pairs) moved[k.indexOf('/') < 0 ? pairKey(SEC1, k) : k] = S.pairs[k];
  S.pairs = moved;
  S.keyed_by_section = true;
}
/* The A/B pair sections, in page order, paired with the section name the export
   writes. One list so the renderer, the counter and the exporter cannot drift. */
const AB_SECTIONS = [[SEC1, D.s1]]
  .concat(D.s4 && D.s4.pairs ? [[SEC4, D.s4]] : [])
  .concat(D.s5 && D.s5.pairs ? [[SEC5, D.s5]] : []);
const save = () => { try { localStorage.setItem(KEY, JSON.stringify(S)); }
  catch (e) { flash('could not save to localStorage: ' + e.message); } };

/* ---------------------------------------------------------------- audio */
let cur = null, curBtn = null;
function play(src, btn) {
  stop();
  const a = new Audio(src);
  cur = a; curBtn = btn; btn.classList.add('on');
  a.addEventListener('ended', () => { btn.classList.remove('on'); if (cur === a) cur = null; });
  a.addEventListener('error', () => { btn.classList.remove('on');
    flash('could not load ' + src + ' — if this is a file:// URL your browser may be '
      + 'blocking it; see "If nothing plays" at the top of the page.'); });
  a.play().catch(err => { btn.classList.remove('on');
    flash('playback refused: ' + err.message); });
}
function stop() { if (cur) { cur.pause(); cur = null; } if (curBtn) { curBtn.classList.remove('on'); curBtn = null; } }
let flashT = null;
function flash(msg) {
  const n = document.getElementById('flash');
  n.textContent = msg; n.hidden = false;
  clearTimeout(flashT); flashT = setTimeout(() => { n.hidden = true; }, 9000);
}

/* ------------------------------------------------------------- text blocks */
function textBlock(label, tokens_or_string) {
  const wrap = el('div');
  if (label) wrap.appendChild(el('div', 'lbl', label));
  const box = el('div', 'txt');
  if (typeof tokens_or_string === 'string') {
    box.textContent = tokens_or_string;
  } else {
    for (const [op, t] of tokens_or_string) {
      if (op === '=') box.appendChild(document.createTextNode(t));
      else box.appendChild(el(op === '+' ? 'ins' : 'del', null, t));
    }
  }
  wrap.appendChild(box);
  const more = el('button', 'more', 'show all');
  more.addEventListener('click', () => {
    box.classList.toggle('open');
    more.textContent = box.classList.contains('open') ? 'collapse' : 'show all';
  });
  requestAnimationFrame(() => {
    if (box.scrollHeight - box.clientHeight > 4) { box.classList.add('clip'); wrap.appendChild(more); }
  });
  return wrap;
}
const tag = (t, big) => el('span', big ? 'tag big' : 'tag', t);

/* ------------------------------------------------------------ verdict rows */
function verdictRow(store, id, options, onChange) {
  const row = el('div', 'verdict');
  const rec = () => (store[id] = store[id] || {});
  const btns = [];
  options.forEach(([val, text, key]) => {
    const b = el('button', 'v');
    b.appendChild(document.createTextNode(text));
    if (key) b.appendChild(el('span', 'kbd', key));
    b.dataset.val = val;
    b.addEventListener('click', () => setChoice(val));
    btns.push(b); row.appendChild(b);
  });
  const note = el('input', 'note');
  note.type = 'text'; note.placeholder = 'note (optional)';
  note.value = (store[id] && store[id].note) || '';
  note.addEventListener('input', () => { rec().note = note.value; save(); });
  row.appendChild(note);

  function setChoice(val) {
    const r = rec();
    r.choice = (r.choice === val) ? '' : val;
    if (r.choice) { r.blinded = S.blinded; r.at = new Date().toISOString(); }
    save(); paint(); onChange && onChange(r);
  }
  function paint() {
    const c = (store[id] && store[id].choice) || '';
    btns.forEach(b => b.setAttribute('aria-pressed', String(b.dataset.val === c)));
  }
  paint();
  return { row, setChoice, paint, focusNote: () => note.focus() };
}

/* -------------------------------------------------------------- section 1 */
const cards = [];   /* every card, in page order, for keyboard navigation */

/* Sections 1 and 4 are the same thing over two wav directories, so they are
   one function. Adding a third A/B section is one more call. `section` is the
   export's own section name, and it namespaces both the verdict key and the
   DOM id -- pair ids repeat across sections. */
function pairSection(section, heading, data, intro) {
  const sec = el('section');
  sec.appendChild(el('h2', null, heading));
  sec.appendChild(el('p', 'small dim', intro));
  data.axes.forEach(ax => {
    sec.appendChild(el('h3', null, (ax.n ? 'Axis ' + ax.n + ' — ' : '') + ax.title));
    const meta = el('p', 'small dim');
    const bits = [ax.pairs.length + ' pairs', mins(ax.seconds) + ' of audio'];
    if (ax.classes.length) {
      bits.push(ax.classes.join(', ') + ': ' + ax.real_carriers.length + ' of '
        + ax.real_total + ' real rewrites (' + (ax.real_carriers.join(' ') || 'none') + ')');
    }
    meta.textContent = bits.join(' · ');
    sec.appendChild(meta);
    const leg = el('p', 'small dim');
    ax.legend.forEach((l, i) => {
      if (i) leg.appendChild(document.createTextNode(' · '));
      leg.appendChild(el('span', 'mono', l.variant));
      leg.appendChild(document.createTextNode(' ' + l.doc));
    });
    sec.appendChild(leg);
    ax.pairs.forEach(p => {
      const c = pairCard(section, p); sec.appendChild(c); cards.push(c);
    });
  });
  return sec;
}

function pairCard(section, p) {
  const key = pairKey(section, p.id);
  const card = el('div', 'card');
  card.id = 'p-' + (section + '-' + p.id).replace(/[:/]/g, '-');
  const hd = el('div', 'hd');
  hd.appendChild(el('span', 'id', p.item));
  if (p.kind) hd.appendChild(tag(p.kind));
  hd.appendChild(tag(p.chars_in + ' chars'));
  if (p.prose_len) hd.appendChild(tag('prose_len ' + p.prose_len));
  p.hazards.forEach(h => hd.appendChild(tag(h)));
  const badge = el('span', 'badge');
  hd.appendChild(badge);
  card.appendChild(hd);

  card.appendChild(textBlock('original text · ' + p.provenance, p.original));

  const cols = el('div', 'cols');
  const revealBits = [];
  for (const side of ['a', 'b']) {
    const s = p[side];
    const box = el('div', 'side');
    const h = el('h4');
    h.appendChild(document.createTextNode(side.toUpperCase()));
    const who = el('span', 'who');
    revealBits.push([who, s.variant]);
    h.appendChild(who);
    box.appendChild(h);
    const b = el('button', 'play');
    b.appendChild(document.createTextNode('play ' + side.toUpperCase() + ' · ' + secs(s.seconds)));
    b.appendChild(el('span', 'kbd', side));
    b.addEventListener('click', () => play(s.wav, b));
    box.appendChild(b);
    box.dataset.side = side;
    box.appendChild(textBlock('pronounced · ' + s.chars + ' chars', s.diff));
    cols.appendChild(box);
    card._plays = card._plays || {};
    card._plays[side] = b;
  }
  card.appendChild(cols);

  const rv = el('div', 'reveal');
  card.appendChild(rv);

  const v = verdictRow(S.pairs, key, [
    ['a', 'A is better', '1'], ['b', 'B is better', '2'],
    ['same', 'no audible difference', '3'], ['unsure', 'unsure', '4'],
  ], () => { paintReveal(); progress(); });
  card.appendChild(v.row);

  function paintReveal() {
    const r = S.pairs[key] || {};
    const shown = !S.blinded || !!r.choice;
    revealBits.forEach(([n, name]) => { n.textContent = shown ? name : ''; });
    rv.textContent = '';
    if (shown) {
      rv.appendChild(document.createTextNode('A = '));
      rv.appendChild(el('span', 'mono', p.a.variant));
      rv.appendChild(document.createTextNode(' · B = '));
      rv.appendChild(el('span', 'mono', p.b.variant));
      rv.appendChild(document.createTextNode(
        ' · reference is ' + p.base_side.toUpperCase()
        + (r.choice ? (r.blinded ? ' · judged blind' : ' · judged unblinded') : '')));
    } else {
      rv.textContent = 'labels hidden until a verdict is recorded';
    }
    card.classList.toggle('done', !!r.choice);
    badge.textContent = r.choice ? 'judged' : '';
  }
  paintReveal();
  card._paint = paintReveal;
  card._verdict = v;
  card._kind = 'pair';
  return card;
}

/* -------------------------------------------------------------- section 2 */
function voiceCard(it) {
  const card = el('div', 'card');
  card.id = 'v-' + it.id;
  const hd = el('div', 'hd');
  hd.appendChild(el('span', 'id', it.id));
  if (it.kind) hd.appendChild(tag(it.kind));
  hd.appendChild(tag(it.chars_in + ' chars'));
  hd.appendChild(tag(it.voices.length + ' voices'));
  hd.appendChild(tag(mins(it.seconds) + ' to hear all'));
  const badge = el('span', 'badge'); hd.appendChild(badge);
  card.appendChild(hd);
  /* the item text once, as the sanitizer leaves it, with its own changes marked */
  card.appendChild(textBlock(
    'pronounced · sanitizer ' + it.sanitizer + ' · ' + it.provenance, it.diff));

  const wrap = el('div', 'voices');
  const rec = () => (S.voices[it.id] = S.voices[it.id] || { out: [] });
  const cells = [];
  it.voices.forEach((v, i) => {
    const c = el('div', 'vc');
    const b = el('button', 'play');
    b.appendChild(document.createTextNode('V' + (i + 1) + ' · ' + secs(v.seconds)));
    if (i < 9) b.appendChild(el('span', 'kbd', String(i + 1)));
    b.addEventListener('click', () => play(v.wav, b));
    c.appendChild(b);
    const nm = el('div', 'small mono'); c.appendChild(nm);
    const r1 = el('div', 'row');
    const win = el('input'); win.type = 'radio'; win.name = 'win-' + it.id;
    const l1 = el('label'); l1.appendChild(win); l1.appendChild(document.createTextNode(' winner'));
    win.addEventListener('change', () => { const r = rec();
      r.winner = v.voice; r.blinded = S.blinded; r.at = new Date().toISOString();
      save(); paint(); progress(); });
    r1.appendChild(l1);
    const out = el('input'); out.type = 'checkbox';
    const l2 = el('label'); l2.appendChild(out); l2.appendChild(document.createTextNode(' eliminate'));
    out.addEventListener('change', () => { const r = rec();
      r.out = (r.out || []).filter(x => x !== v.voice);
      if (out.checked) r.out.push(v.voice);
      r.at = new Date().toISOString(); save(); paint(); });
    r1.appendChild(l2);
    c.appendChild(r1);
    wrap.appendChild(c);
    cells.push({ c, nm, win, out, v, b });
    card._plays = card._plays || {};
    card._plays[String(i + 1)] = b;
  });
  card.appendChild(wrap);
  const nrow = el('div', 'verdict');
  const note = el('input', 'note'); note.type = 'text';
  note.placeholder = 'ranking or note (optional)';
  note.value = (S.voices[it.id] && S.voices[it.id].note) || '';
  note.addEventListener('input', () => { rec().note = note.value; save(); });
  nrow.appendChild(note);
  card.appendChild(nrow);

  function paint() {
    const r = S.voices[it.id] || {};
    const shown = !S.blinded || !!r.winner;
    cells.forEach(x => {
      x.nm.textContent = shown ? x.v.voice : '';
      x.win.checked = r.winner === x.v.voice;
      x.out.checked = (r.out || []).includes(x.v.voice);
      x.c.classList.toggle('win', x.win.checked);
      x.c.classList.toggle('out', x.out.checked);
    });
    card.classList.toggle('done', !!r.winner);
    badge.textContent = r.winner ? 'winner picked' : '';
  }
  paint();
  card._paint = paint;
  card._focusNote = () => note.focus();
  card._kind = 'voice';
  return card;
}

/* -------------------------------------------------------------- section 3 */
function lenCard(it) {
  const card = el('div', 'card');
  card.id = 'l-' + it.id;
  const hd = el('div', 'hd');
  hd.appendChild(el('span', 'id', it.id));
  hd.appendChild(tag(it.chars_in + ' chars', true));
  hd.appendChild(tag(secs(it.seconds) + ' of audio', true));
  if (it.prose_len) hd.appendChild(tag('prose_len ' + it.prose_len));
  it.hazards.forEach(h => hd.appendChild(tag(h)));
  const badge = el('span', 'badge'); hd.appendChild(badge);
  card.appendChild(hd);
  if (it.note) card.appendChild(el('p', 'small dim', it.note));
  const b = el('button', 'play');
  b.appendChild(document.createTextNode('play · ' + secs(it.seconds)));
  b.appendChild(el('span', 'kbd', 'a'));
  b.addEventListener('click', () => play(it.wav, b));
  card.appendChild(b);
  card._plays = { a: b };
  card.appendChild(textBlock(
    'pronounced · sanitizer ' + it.sanitizer + ' · ' + it.provenance, it.diff));
  const v = verdictRow(S.len, it.id, [
    ['worth', 'worth speaking', '1'], ['not', 'not worth speaking', '2'],
    ['unsure', 'unsure', '3'],
  ], () => { const r = S.len[it.id] || {};
    card.classList.toggle('done', !!r.choice);
    badge.textContent = r.choice ? 'judged' : ''; progress(); });
  card.appendChild(v.row);
  const r0 = S.len[it.id] || {};
  card.classList.toggle('done', !!r0.choice);
  badge.textContent = r0.choice ? 'judged' : '';
  card._verdict = v;
  card._kind = 'len';
  return card;
}

/* ---------------------------------------------------------------- render */
function render() {
  const main = document.getElementById('body');
  main.textContent = ''; cards.length = 0;

  /* section 1, and section 4 — the same machinery over a different wav dir */
  main.appendChild(pairSection(SEC1, 'Section 1 — #8 sanitizer axes', D.s1,
    D.s1.pairs + ' pairs over ' + D.s1.axes.length + ' axes, in the audition '
    + 'document’s frequency order: the axis that shows up most often in the '
    + '12 real rewrites comes first. Each pair moves exactly one axis against the '
    + 'same reference. Green is text the sanitizer added, red is text it removed. '
    + 'Voice: af_heart, which #9 has since rejected.'));

  /* section 2 */
  const s2 = el('section');
  s2.appendChild(el('h2', null, 'Section 2 — #9 voice'));
  s2.appendChild(el('p', 'small dim',
    D.s2.count + ' items, six voices each. Pick a winner per item and tick the '
    + 'ones you are eliminating. Duration is the only measured difference between '
    + 'these wavs: same text, same sanitizer, same model, only the voice differs.'));
  D.s2.items.forEach(it => { const c = voiceCard(it); s2.appendChild(c); cards.push(c); });
  main.appendChild(s2);

  /* section 3 */
  const s3 = el('section');
  s3.appendChild(el('h2', null, 'Section 3 — #10 minimum length'));
  s3.appendChild(el('p', 'small dim',
    D.s3.count + ' single items, no comparison. The question is whether a message '
    + 'this short is worth speaking at all, so the character count and the length '
    + 'of audio are on every row. Shortest first.'));
  D.s3.groups.forEach(g => {
    s3.appendChild(el('h3', null, g.title));
    s3.appendChild(el('p', 'small dim',
      g.items.length + ' items · ' + mins(g.seconds) + ' of audio'));
    g.items.forEach(it => { const c = lenCard(it); s3.appendChild(c); cards.push(c); });
  });
  main.appendChild(s3);

  /* section 4 */
  if (D.s4 && D.s4.pairs) {
    main.appendChild(pairSection(SEC4, 'Section 4 — #13 sanitizer follow-ups', D.s4,
      D.s4.pairs + ' pairs over ' + D.s4.axes.length + ' axes: the two rules the '
      + '#8 notes asked for and had never been auditioned, plus the one path '
      + 'combination #8 left unmeasured. Same reference (base), same one-axis-'
      + 'at-a-time rule as section 1 — but the voice is bf_emma, the voice #9 '
      + 'settled on, so these are NOT comparable with a section 1 wav.'));
  }

  /* section 5 */
  if (D.s5 && D.s5.pairs) {
    main.appendChild(pairSection(SEC5, 'Section 5 — #11 the settled set', D.s5,
      D.s5.pairs + ' pairs. This is the confirmation listen #11 §4.2 asks for: '
      + 'the settled combination has never been synthesized, and until now it '
      + 'contained a rule (the conditional boundary B′) that did not exist in '
      + 'code. Every earlier pair moved ONE axis; here `settled` moves seven at '
      + 'once, so the question is not which axis wins — those margins stand — '
      + 'but whether any two of them interact badly. Voice: bf_emma, same as '
      + 'section 4, so a section 5 wav IS comparable with a section 4 wav and is '
      + 'NOT comparable with a section 1 wav.'));
  }

  main.appendChild(exportPanel());
  progress();
  setCur(0, false);
}

/* -------------------------------------------------------------- progress */
function counts() {
  /* Sections 1 and 4 are both A/B pairs and share one counter and one export
     block; the `section` column tells them apart -- and so must the store key,
     or a pair id that appears in both sections counts twice here. */
  const axes1 = AB_SECTIONS.flatMap(([sec, d]) => d.axes.map(a => [sec, a]));
  const p = axes1.reduce((n, [, a]) => n + a.pairs.length, 0);
  const pj = axes1.reduce((n, [sec, a]) => n + a.pairs.filter(
    x => (S.pairs[pairKey(sec, x.id)] || {}).choice).length, 0);
  const vj = D.s2.items.filter(x => (S.voices[x.id] || {}).winner).length;
  const lj = D.s3.groups.reduce((n, g) => n + g.items.filter(
    x => (S.len[x.id] || {}).choice).length, 0);
  return { p, pj, v: D.s2.count, vj, l: D.s3.count, lj };
}
function progress() {
  const c = counts();
  const n = document.getElementById('prog');
  n.textContent = '';
  const put = (a, b, what) => {
    const s = el('span'); s.appendChild(el('b', null, a + ' of ' + b));
    s.appendChild(document.createTextNode(' ' + what));
    n.appendChild(s); n.appendChild(document.createTextNode('  ·  '));
  };
  put(c.pj, c.p, 'pairs judged');
  put(c.vj, c.v, 'voice items');
  put(c.lj, c.l, 'length items');
  n.appendChild(document.createTextNode(
    (c.pj + c.vj + c.lj) + ' of ' + (c.p + c.v + c.l) + ' total'));
  if (document.getElementById('out')) writeExport();
}

/* ---------------------------------------------------------------- export */
const CHOICE1 = { a: 'A is better', b: 'B is better',
  same: 'no audible difference', unsure: 'unsure' };
const CHOICE3 = { worth: 'worth speaking', not: 'not worth speaking', unsure: 'unsure' };
function rows1() {
  const out = [];
  const src = AB_SECTIONS.flatMap(([sec, d]) => d.axes.map(a => [sec, a]));
  src.forEach(([section, ax]) => ax.pairs.forEach(p => {
    const r = S.pairs[pairKey(section, p.id)] || {};
    out.push([section, 'axis' + ax.n + '-' + ax.key, p.item, p.kind, p.chars_in,
      p.id, p.a.variant, p.b.variant, p.base_side,
      r.choice ? (r.blinded ? 'blind' : 'unblinded') : '',
      r.choice ? CHOICE1[r.choice] : '',
      r.choice === 'a' ? p.a.variant : r.choice === 'b' ? p.b.variant : '',
      p.text_identical, p.phonemes_identical === null ? 'unknown' : p.phonemes_identical,
      p.wav_identical, (p.phonemes_a == null ? '' : p.phonemes_a + '/' + p.phonemes_b),
      (r.note || '').replace(/\t/g, ' '), r.at || '']);
  }));
  return out;
}
function rows2() {
  return D.s2.items.map(it => { const r = S.voices[it.id] || {};
    return ['voice', it.id, it.chars_in,
      r.winner ? (r.blinded ? 'blind' : 'unblinded') : '', r.winner || '',
      (r.out || []).join(' '), (r.note || '').replace(/\t/g, ' '), r.at || ''];
  });
}
function rows3() {
  const out = [];
  D.s3.groups.forEach(g => g.items.forEach(it => { const r = S.len[it.id] || {};
    out.push(['length', g.key, it.id, it.chars_in,
      it.seconds == null ? '' : it.seconds.toFixed(2),
      r.choice ? CHOICE3[r.choice] : '', (r.note || '').replace(/\t/g, ' '), r.at || '']);
  }));
  return out;
}
const H1 = ['section', 'axis', 'item', 'kind', 'chars_in', 'pair', 'side_a', 'side_b',
  'reference_side', 'blinding', 'verdict', 'preferred_variant', 'text_identical',
  'phonemes_identical', 'wav_identical', 'phonemes_a_b', 'note', 'judged_at'];
const H2 = ['section', 'item', 'chars_in', 'blinding', 'winner_voice',
  'eliminated_voices', 'note', 'judged_at'];
const H3 = ['section', 'group', 'item', 'chars_in', 'audio_s', 'verdict', 'note',
  'judged_at'];

function buildExport(fmt) {
  const c = counts();
  const head = ['# claudish audition verdicts',
    '# page generated ' + D.generated,
    '# exported ' + new Date().toISOString(),
    '# blinding is currently ' + (S.blinded ? 'ON' : 'OFF')
      + '; the per-row blinding column is the state when THAT verdict was recorded',
    '# progress: ' + c.pj + '/' + c.p + ' pairs, ' + c.vj + '/' + c.v
      + ' voice items, ' + c.lj + '/' + c.l + ' length items',
    '# text_identical / phonemes_identical / wav_identical were measured at generation'
      + ' time and are NOT shown on the page while a pair is blinded', ''];
  const blocks = [[H1, rows1()], [H2, rows2()], [H3, rows3()]];
  if (fmt === 'md') {
    const md = blocks.map(([h, rs]) => {
      const esc = v => String(v).replace(/\|/g, '\\|');
      return ['| ' + h.join(' | ') + ' |',
        '| ' + h.map(() => '---').join(' | ') + ' |',
        ...rs.map(r => '| ' + r.map(esc).join(' | ') + ' |')].join('\n');
    });
    return head.join('\n') + '\n' + md.join('\n\n');
  }
  return head.join('\n') + '\n'
    + blocks.map(([h, rs]) => [h.join('\t'), ...rs.map(r => r.join('\t'))].join('\n'))
        .join('\n\n');
}
let fmt = 'tsv';
function writeExport() { document.getElementById('out').value = buildExport(fmt); }

function exportPanel() {
  const s = el('section'); s.id = 'export';
  s.appendChild(el('h2', null, 'Export'));
  s.appendChild(el('p', 'small dim',
    'Every verdict is already saved in this browser’s localStorage, so a reload '
    + 'or a second sitting restores it. This box is the copy-out route that does not '
    + 'depend on a download working: select it and copy, or use the button. The A/B '
    + 'assignment and the blinding state travel with each row.'));
  const bar = el('div', 'verdict');
  const t = el('textarea'); t.id = 'out'; t.readOnly = true; t.spellcheck = false;
  const mk = (label, fn) => { const b = el('button', null, label);
    b.addEventListener('click', fn); bar.appendChild(b); return b; };
  const bt = mk('TSV', () => { fmt = 'tsv'; writeExport(); pf(); });
  const bm = mk('Markdown', () => { fmt = 'md'; writeExport(); pf(); });
  bt.className = 'toggle'; bm.className = 'toggle';
  const pf = () => { bt.setAttribute('aria-pressed', String(fmt === 'tsv'));
    bm.setAttribute('aria-pressed', String(fmt === 'md')); };
  pf();
  mk('copy to clipboard', async () => {
    t.select();
    try {
      if (navigator.clipboard && window.isSecureContext) await navigator.clipboard.writeText(t.value);
      else if (!document.execCommand('copy')) throw new Error('execCommand refused');
      flash('copied ' + t.value.length + ' characters');
    } catch (e) { flash('clipboard blocked (' + e.message + ') — the text is selected, press Cmd-C'); }
  });
  mk('download (bonus)', () => {
    try {
      const a = document.createElement('a');
      a.href = URL.createObjectURL(new Blob([t.value], { type: 'text/plain' }));
      a.download = 'audition-verdicts.' + (fmt === 'md' ? 'md' : 'tsv');
      a.click(); URL.revokeObjectURL(a.href);
    } catch (e) { flash('download blocked — copy from the box instead'); }
  });
  mk('clear every verdict', () => {
    if (!confirm('Delete every verdict and note recorded on this page?')) return;
    S.pairs = {}; S.voices = {}; S.len = {}; save(); render();
  });
  s.appendChild(bar);
  s.appendChild(t);
  return s;
}

/* -------------------------------------------------------------- keyboard */
let curIdx = 0;
function setCur(i, scroll) {
  if (!cards.length) return;
  curIdx = Math.max(0, Math.min(cards.length - 1, i));
  cards.forEach((c, j) => c.classList.toggle('cur', j === curIdx));
  if (scroll) cards[curIdx].scrollIntoView({ block: 'center', behavior: 'smooth' });
}
document.addEventListener('click', e => {
  const c = e.target.closest && e.target.closest('.card');
  if (c) { const i = cards.indexOf(c); if (i >= 0) setCur(i, false); }
});
document.addEventListener('keydown', e => {
  const t = e.target;
  if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA')) {
    if (e.key === 'Escape') t.blur();
    return;
  }
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  const card = cards[curIdx];
  const k = e.key;
  if (k === 'n' || k === 'j' || k === 'ArrowDown') { setCur(curIdx + 1, true); e.preventDefault(); return; }
  if (k === 'p' || k === 'k' || k === 'ArrowUp') { setCur(curIdx - 1, true); e.preventDefault(); return; }
  if (k === 's' || k === 'Escape') { stop(); return; }
  if (!card) return;
  if (card._plays && card._plays[k]) { card._plays[k].click(); e.preventDefault(); return; }
  if (k === 'Enter') { (card._focusNote || (card._verdict && card._verdict.focusNote) || (() => {}))(); e.preventDefault(); return; }
  if (k === 'r') { S.blinded = !S.blinded; save(); paintAll(); return; }
  if (card._kind === 'pair' && '1234'.includes(k)) {
    card._verdict.setChoice(['a', 'b', 'same', 'unsure'][+k - 1]); e.preventDefault(); return;
  }
  if (card._kind === 'len' && '123'.includes(k)) {
    card._verdict.setChoice(['worth', 'not', 'unsure'][+k - 1]); e.preventDefault();
  }
});

function paintAll() {
  cards.forEach(c => c._paint && c._paint());
  const b = document.getElementById('blind');
  b.setAttribute('aria-pressed', String(S.blinded));
  b.firstChild.textContent = S.blinded ? 'blinded' : 'labels visible';
  progress();
}

/* ----------------------------------------------------------------- boot */
document.getElementById('blind').addEventListener('click', () => {
  S.blinded = !S.blinded; save(); paintAll();
});
const themes = ['auto', 'light', 'dark'];
function paintTheme() {
  const r = document.documentElement;
  if (S.theme === 'auto') r.removeAttribute('data-theme');
  else r.setAttribute('data-theme', S.theme);
  document.getElementById('theme').textContent = 'theme: ' + S.theme;
}
document.getElementById('theme').addEventListener('click', () => {
  S.theme = themes[(themes.indexOf(S.theme) + 1) % 3]; save(); paintTheme();
});
document.getElementById('stop').addEventListener('click', stop);
paintTheme();
render();
paintAll();
"""


def build_html(data: dict, skipped: list[str]) -> str:
    blob = json.dumps(data, ensure_ascii=False).replace("<", "\\u003c")
    e = html.escape
    total_s = (sum(a["seconds"] for a in data["s1"]["axes"])
               + sum(i["seconds"] for i in data["s2"]["items"])
               + sum(g["seconds"] for g in data["s3"]["groups"])
               + sum(a["seconds"] for a in data.get("s4", {}).get("axes", []))
               + sum(a["seconds"] for a in data.get("s5", {}).get("axes", [])))
    # Sections 1, 4 and 5 are all A/B pairs; the blinding note is about all of
    # them.
    others = [data.get(k, {}) for k in ("s4", "s5")]
    ab_pairs = data["s1"]["pairs"] + sum(d.get("pairs", 0) for d in others)
    ab_ident_ph = (data["s1"]["identical_phonemes"]
                   + sum(d.get("identical_phonemes", 0) for d in others))
    ab_ident_wav = (data["s1"]["identical_wavs"]
                    + sum(d.get("identical_wavs", 0) for d in others))
    skip = ""
    if skipped:
        skip = ("<div class=\"note-box\"><b>Not on this page</b><ul class=\"small\">"
                + "".join(f"<li>{e(s)}</li>" for s in skipped)
                + "</ul><p class=\"small dim\">A wav whose corpus text this generator "
                  "could not find is left off rather than shown with guessed text. "
                  "Re-run the generator once the text lands.</p></div>")
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Audition bench</title>
<style>{CSS}</style>
</head>
<body>
<header><div class="bar">
  <h1>Audition bench</h1>
  <button id="blind" class="toggle" aria-pressed="true"><span>blinded</span>
    <span class="kbd">r</span></button>
  <button id="stop">stop audio<span class="kbd">s</span></button>
  <button id="theme">theme: auto</button>
  <span class="grow"></span>
  <span id="prog" class="prog"></span>
</div>
<div class="bar"><div id="flash" class="small" hidden
  style="color:var(--warn)"></div></div>
</header>
<main>
<p class="small dim">Generated {e(data['generated'])} by
<span class="mono">bench/audition-page.py</span> from the wavs in
<span class="mono">{e(data['root'])}</span> —
{data['wavs']} wavs, {mins_py(total_s)} of audio.
The text under every play button is the real output of
<span class="mono">bench/sanitizers.py</span> over the real corpus file, so it is
what was actually handed to Kokoro. Nothing here says how any of it sounds and
no verdict is pre-filled.</p>

<div class="note-box">
<p><b>Keyboard.</b> <span class="kbd">a</span> / <span class="kbd">b</span> play a
side (<span class="kbd">1</span>–<span class="kbd">6</span> play a voice in section 2,
<span class="kbd">a</span> plays in section 3) ·
<span class="kbd">1</span> <span class="kbd">2</span> <span class="kbd">3</span>
<span class="kbd">4</span> record a verdict on the current card ·
<span class="kbd">n</span>/<span class="kbd">p</span> next / previous card ·
<span class="kbd">Enter</span> jump to the note field ·
<span class="kbd">s</span> stop audio · <span class="kbd">r</span> toggle blinding.
Click a card to make it current. Nothing autoplays.</p>
<p class="small"><b>Blinding.</b> Which side is A and which is B is fixed but
arbitrary, seeded off the pair id so it survives a regeneration. Variant names stay
hidden until a verdict is recorded, or until you switch blinding off.
<b>{ab_ident_ph} of the
{ab_pairs} pairs phonemise to identical strings on both sides</b>, and
{ab_ident_wav} of those are byte-identical wavs, so
<b>&ldquo;no audible difference&rdquo; is a correct answer, not a cop-out.</b>
Which pairs those are is in the export, not on the page, so an &ldquo;I heard a
difference&rdquo; on one of them stays visible afterwards.</p>
<p class="small"><b>If nothing plays.</b> Opened as a
<span class="mono">file://</span> URL this needs the browser to load a sibling wav
directly; Safari does, and Chrome does for a file it was opened from. If a play
button flashes a load error, serve the directory instead:</p>
<p class="mono small">cd {e(data['root'])} &amp;&amp; python3 -m http.server 8765<br>
then open http://localhost:8765/audition.html</p>
</div>
{skip}
<div id="body"></div>
</main>
<script id="data" type="application/json">{blob}</script>
<script>{JS}</script>
</body>
</html>
"""


def mins_py(s: float) -> str:
    return f"{round(s)}s" if s < 90 else f"{round(s / 60)} min"


# --------------------------------------------------------------------------


def main(argv=None) -> int:
    root_default = Path(os.environ.get("KOKORO_ROOT",
                                       Path.home() / ".local/share/kokoro")) / "bench"
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--bench-dir", default=str(root_default),
                    help="where audition-8/9/10 live (default: %(default)s)")
    ap.add_argument("--out", default=None,
                    help="output html (default: <bench-dir>/audition.html)")
    ap.add_argument("--repo", default=str(REPO))
    args = ap.parse_args(argv)

    bench_dir = Path(args.bench_dir).expanduser()
    repo = Path(args.repo).expanduser()
    out = Path(args.out).expanduser() if args.out else bench_dir / "audition.html"

    manifest = {r["id"]: r for r in read_tsv(repo / "corpus" / "manifest.tsv")}
    items_tsv = read_tsv(repo / "bench" / "audition-10" / "items.tsv")
    resolve = text_sources(repo)
    phon = phonemizer(bench_dir.parent)

    w8 = scan(bench_dir / "audition-8")
    w9 = scan(bench_dir / "audition-9")
    w10 = scan(bench_dir / "audition-10")
    # #13's follow-up set. A SEPARATE directory and a separate section, not
    # more wavs in audition-8, because it is a different voice: #9 settled on
    # `bf_emma` and rejected `af_heart`, which every audition-8 wav is in.
    # Merging the two would silently pair an af_heart reference against a
    # bf_emma variant -- the pair would no longer isolate the rule.
    w13 = scan(bench_dir / "audition-13")
    # #11's settled-set confirmation listen. Also its own directory: it is
    # bf_emma like audition-13, but its reference `base` wavs are per-item and
    # its pairs move seven axes at once rather than one, so folding it into
    # section 4 would break that section's "one axis moved" reading.
    w11 = scan(bench_dir / "audition-11")
    if not (w8 or w9 or w10 or w13 or w11):
        raise SystemExit(f"audition-page: no wavs under {bench_dir}")

    skipped: list[str] = []
    s1 = build_section1(w8, resolve, manifest, phon, skipped)
    s2 = build_section2(w9, resolve, manifest, skipped)
    s3 = build_section3(w10, resolve, manifest, items_tsv, skipped)
    s4 = build_section1(w13, resolve, manifest, phon, skipped)
    s5 = build_section1(w11, resolve, manifest, phon, skipped)

    data = {
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
        "root": str(bench_dir),
        "wavs": len(w8) + len(w9) + len(w10) + len(w13) + len(w11),
        "phonemes_available": phon is not None,
        "s1": s1, "s2": s2, "s3": s3, "s4": s4, "s5": s5,
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(build_html(data, skipped), encoding="utf-8")

    print(f"wrote {out}  ({out.stat().st_size / 1024:.0f} KB)")
    print(f"  section 1  {s1['pairs']} pairs over {len(s1['axes'])} axes"
          f"   ({len(w8)} wavs)")
    print(f"             {s1['identical_phonemes']} pairs phoneme-identical, "
          f"{s1['identical_wavs']} byte-identical wavs")
    print(f"  section 2  {s2['count']} items x 6 voices        ({len(w9)} wavs)")
    print(f"  section 3  {s3['count']} single items            ({len(w10)} wavs)")
    print(f"  section 4  {s4['pairs']} pairs over {len(s4['axes'])} axes"
          f"   ({len(w13)} wavs)")
    print(f"             {s4['identical_phonemes']} pairs phoneme-identical, "
          f"{s4['identical_wavs']} byte-identical wavs")
    print(f"  section 5  {s5['pairs']} pairs over {len(s5['axes'])} groups"
          f"   ({len(w11)} wavs)")
    print(f"             {s5['identical_phonemes']} pairs phoneme-identical, "
          f"{s5['identical_wavs']} byte-identical wavs")
    print("  phoneme identity: "
          + ("kokoro-onnx tokenizer" if phon else "UNAVAILABLE (text comparison only)"))
    for s in skipped:
        print(f"  skipped: {s}")
    print(f"\nopen it:  open {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
