"""Sentence splitting for the speech path.

Extracted from `bench/first-sentence.py`, which is where `_SENT_END` and
`first_sentence()` were written and where the 12/12-under-3 s measurement that
justifies first-sentence pipelining was taken. They moved here for two reasons:

  * `first-sentence.py` cannot be imported by module name -- the hyphen makes
    it un-importable without an `importlib.spec_from_file_location` dance, and
    that dance is a smell rather than a design; and
  * the rest of that file is measurement scaffolding (argparse, a `Row`
    dataclass, TSV emitters, a `create_stream` replication) that the runtime
    must not drag in.

`bench/first-sentence.py` is now the SECOND caller of this module rather than
its owner, so the bench figure and the shipped splitter cannot drift.

**The splitter must run AFTER markdown stripping** (§4). In corpus item `r10`
the first full stop sits inside `**...find.**`, so splitting raw text yields a
219-character "first sentence" (3.58 s, FAIL) where splitting sanitized text
yields 32 characters (0.50 s, PASS). Callers sanitize first; this module does
not do it for them, because `bench/first-sentence.py` needs to vary which
sanitizer runs.
"""

from __future__ import annotations

import re

# A sentence ends at . ! ? followed by whitespace or end of text. Kokoro's own
# _split_phonemes also breaks on , and ; -- those are chunk seams, not
# sentences, and a pipeliner speaks a sentence.
_SENT_END = re.compile(r"[.!?](?=\s|$)")


def first_sentence(text: str, min_chars: int = 0) -> str:
    """The first sentence, extended until it is at least min_chars long.

    min_chars exists because rule B turns a heading line into its own
    one-word 'sentence'. Speaking 'Summary.' at 0.3s would be a TTFA win that
    means nothing, so --min-chars is the sensitivity check on that.

    At runtime it is 0: §4 measured that batching sentence one up to a minimum
    length is a REGRESSION -- `--min-chars 80` drops 12/12 under the 3 s line
    to 10/12 -- so the shipped speaker never passes anything but 0.
    """
    for m in _SENT_END.finditer(text):
        if m.end() >= min_chars:
            return text[: m.end()].strip()
    return text.strip()


def split_sentences(text: str) -> list[str]:
    """Every sentence, on the same boundary rule `first_sentence` uses.

    Element 0 is exactly `first_sentence(text, 0)`; the rest continue on the
    same regex to the end of the text. This is what lets the speaker start
    audio on sentence one instead of on the whole message -- whole-message TTFA
    fails the 3 s line 12/12, sentence one passes 12/12 at a 0.86 s median.
    """
    out: list[str] = []
    start = 0
    for m in _SENT_END.finditer(text):
        seg = text[start:m.end()].strip()
        if seg:
            out.append(seg)
        start = m.end()
    tail = text[start:].strip()
    if tail:
        out.append(tail)
    return out
