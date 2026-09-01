"""The speech-content modules, at the plugin root and on the runtime path.

This package holds the two things the speech path needs to turn a rewrite into
sentences that Kokoro can say -- a sanitizer and a sentence splitter -- and it
is the OWNER of both. `bench/` imports from here; nothing here imports from
`bench/`.

The runtime interface is three functions and NO knobs:

    sanitize(text)                  -> the settled set, composed
    first_sentence(text, min_chars) -> sentence one
    split_sentences(text)           -> every sentence, same boundary rule

`sanitize()` takes no options on purpose. `sanitizers.Opts` exists because the
bench harness sweeps `--max-run` and `--boundary` across 28 registered
variants; the shipped speaker has exactly one setting, the one that was heard.
The 28-entry registry stays in `sanitizers.py` as the bench-facing surface and
`sanitizers.run("settled", text, opts)` is still callable exactly as it was, so
the 67 blind verdict pairs behind `settled` stay attached to the code that
ships.

Order is normative: SANITIZE FIRST, SPLIT SECOND (§4, corpus item `r10`).
"""

from __future__ import annotations

from . import sanitizers
from .split import _SENT_END, first_sentence, split_sentences

__all__ = ["sanitize", "first_sentence", "split_sentences", "sanitizers",
           "_SENT_END"]


def sanitize(text: str) -> str:
    """The settled sanitizer set (§4.2), composed, with no knobs.

    All nine axes at the value #8, #13 and the listener's 2026-08-25 axis-2
    call chose -- and it was heard as a whole, blind, on `bf_emma`, preferred
    on all nine pairs it appeared in. `sanitizers.py`'s own docstring is the
    record; this is just the one call the runtime is allowed to make.
    """
    return sanitizers.REGISTRY["settled"].fn(text, sanitizers.Opts())
