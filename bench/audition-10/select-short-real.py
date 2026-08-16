#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# Build the #10 audition's short-message items from this machine's transcripts.
#
# rewrite.sh never rewrites a message whose prose_len is under CLAUDISH_MIN_CHARS
# (default 200), so a sub-200 message reaches a speech path as RAW assistant
# output. This script selects sixteen such messages out of the local Claude Code
# transcripts and writes them to items/ as one .txt per utterance -- the same
# shape corpus/spoken/ uses, so bench can take them as positional files.
#
# It re-uses corpus/bin/extract-real-sources.sh for the extraction itself
# (assistant messages only; that script's header records why user prompts are
# not touched). Selection is BY HAND: the SELECTION table below is the record of
# which sixteen and why, keyed on the transcript uuid so it is reproducible.
#
# No LLM is called. Nothing here is rewritten; that is the point.
#
#   python3 bench/audition-10/select-short-real.py <extract-dir>
#
# where <extract-dir> holds the all.jsonl that extract-real-sources.sh wrote.
# ---------------------------------------------------------------------------
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent

# band: ACK  = progress narration / acknowledgement. What I did, what I am about
#              to do. Nothing you could not have predicted from having asked.
#       FACT = carries a claim about the world: a measured value, a name, a
#              state, or a negative result.
# The band is a hand-applied judgement on that criterion; borderline calls are
# noted in the `note` column of items.tsv.
SELECTION = [
    # id       uuid prefix   band    note
    ("ack01", "23022989", "ACK", "the shortest real assistant message in 142"),
    ("ack02", "3a8b308d", "ACK", "delegation narration"),
    ("ack03", "c511686d", "ACK", "next-steps narration, three clauses"),
    ("ack04", "13cc9548", "ACK", "opening narration of a session"),
    ("ack05", "17379864", "ACK", "narration naming what it is about to verify"),
    ("ack06", "14a3a222", "ACK", "housekeeping narration with a parenthetical"),
    ("ack07", "7f1e3e51", "ACK", "agreeing with a scope call; a judgement, no new fact"),
    ("ack08", "e3259eeb", "ACK", "two paragraphs, prose_len 198 - the closest real item under the gate"),
    ("fct01", "e96be3b1", "FACT", "'frontier is empty' is a state claim; shortest fact-carrying item found"),
    ("fct02", "5f9b1c3a", "FACT", "24 kHz, mono - NUM-UNIT at minimum length"),
    ("fct03", "5247c0f2", "FACT", "a negative result, with a backticked identifier"),
    ("fct04", "b91c2dce", "FACT", "**238 MB** - bold markers and a unit"),
    ("fct05", "1ba394c8", "FACT", "a host:port and a size in GB"),
    ("fct06", "0b550b26", "FACT", "**0.0%**, *falls*, an en-dashed range, tilde-approximations"),
    ("fct07", "17eff123", "FACT", "two measured numbers and a correction of an earlier one"),
    ("fct08", "e9ee4f7a", "FACT", "prose_len 194, paths and extensions, just under the gate"),
]


def prose_len(text: str) -> int:
    """Exactly rewrite.sh:139-141: drop fenced code blocks, count non-space."""
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
    exdir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/claudish-ex")
    src = exdir / "all.jsonl"
    if not src.exists():
        raise SystemExit(
            f"no {src}; run corpus/bin/extract-real-sources.sh first "
            "(see docs/decisions/min-length-audition.md)")

    by_uuid = {}
    for line in src.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        d = json.loads(line)
        by_uuid[d["uuid"][:8]] = d

    items = HERE / "items"
    items.mkdir(exist_ok=True)
    rows = ["\t".join(("id", "band", "prose_len", "bytes", "lines", "origin", "note"))]
    for ident, uid, band, note in SELECTION:
        d = by_uuid.get(uid)
        if d is None:
            print(f"MISSING {ident} ({uid}) -- not in this extraction", file=sys.stderr)
            continue
        txt = d["txt"]
        (items / f"{ident}.txt").write_text(txt, encoding="utf-8")
        origin = f"transcript {d['sess'][:8]}:{uid} {d['ts']}"
        rows.append("\t".join((
            ident, band, str(prose_len(txt)), str(len(txt.encode())),
            str(txt.count("\n")), origin, note)))
    (HERE / "items.tsv").write_text("\n".join(rows) + "\n", encoding="utf-8")
    print(f"wrote {len(rows) - 1} items to {items} and {HERE / 'items.tsv'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
