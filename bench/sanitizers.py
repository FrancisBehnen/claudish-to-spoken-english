"""Pluggable sanitizers for the bench harness.

A sanitizer is a function ``(text: str, opts: Opts) -> str``. Register one by
decorating it with ``@sanitizer("name", "one-line description")``; it is then
selectable as ``--sanitizer name`` with no other edit anywhere.

NOTHING IN HERE IS A DECISION. The `candidate` sanitizer is rules A-K of
`docs/research/espeak-sanitizer-rules.md` §"Candidate rule list, in priority
order", assembled verbatim from *measured phoneme damage*. That document is
explicit that the list is input to #8, not #8's answer. Nobody has listened to
any of it. Rule L (the `lives` -> `livz` respelling) is gated behind
``--respell`` because the doc says its trigger condition is not established.
Rule M is a prohibition, not a transformation, so there is no code for it.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

# --------------------------------------------------------------------------
# registry
# --------------------------------------------------------------------------

REGISTRY: dict[str, "Sanitizer"] = {}


@dataclass
class Opts:
    """Knobs the harness exposes on the command line."""

    max_run: int = 400  # rule A: input chars between chunk boundaries
    boundary: str = "."  # rule A/B: the punctuation inserted ('.' or ',')
    respell: bool = False  # rule L, off by default
    url_replacement: str = "a link"


@dataclass
class Sanitizer:
    name: str
    doc: str
    fn: object
    rules: str = ""


def sanitizer(name: str, doc: str, rules: str = ""):
    def deco(fn):
        REGISTRY[name] = Sanitizer(name=name, doc=doc, fn=fn, rules=rules)
        return fn

    return deco


def get(name: str) -> Sanitizer:
    try:
        return REGISTRY[name]
    except KeyError:
        raise SystemExit(
            f"bench: unknown sanitizer {name!r}; known: {', '.join(sorted(REGISTRY))}"
        )


def run(name: str, text: str, opts: Opts) -> str:
    return get(name).fn(text, opts)


# --------------------------------------------------------------------------
# none -- the control
# --------------------------------------------------------------------------


@sanitizer("none", "passthrough control: hands the text to Kokoro untouched")
def san_none(text: str, opts: Opts) -> str:
    return text


# --------------------------------------------------------------------------
# individual rules (A-L), each named for its row in the research doc
# --------------------------------------------------------------------------

BOUNDARY_CHARS = ".,!?;"  # exactly what kokoro_onnx._split_phonemes splits on

# Rule H. Ranges chosen to cover the emoji planes plus Misc Symbols and
# Dingbats. The doc is explicit that only five emoji were ever measured, so
# this is a guess at the class, not a verified character set.
_EMOJI_RANGES = (
    (0x1F000, 0x1FAFF),  # emoji planes, incl. regional indicators
    (0x2600, 0x26FF),  # misc symbols  (warning sign, etc.)
    (0x2700, 0x27BF),  # dingbats      (white heavy check mark U+2705)
    (0x2B00, 0x2BFF),  # misc symbols and arrows
    (0xFE00, 0xFE0F),  # variation selectors
    (0x200D, 0x200D),  # zero-width joiner
)


def _is_emoji(ch: str) -> bool:
    o = ord(ch)
    return any(lo <= o <= hi for lo, hi in _EMOJI_RANGES)


def rule_H_strip_emoji(text: str) -> str:
    return "".join(ch for ch in text if not _is_emoji(ch))


# Rule I. Schemed URLs, `www.` hosts, and bare `host.tld/path`. The bare form
# requires BOTH a short TLD list and a trailing path, which is what keeps
# `rewrite.sh`, `providers.sh` and `libfoo.so` out of it -- an early version
# that made the path optional swallowed `rewrite.sh`.
_TLD = r"(?:com|org|net|io|dev|ai|edu|gov)"
_URL_RE = re.compile(
    r"""(?xi)
    (?: https?://\S+
      | www\.\S+
      | \b[\w-]+(?:\.[\w-]+)*\.""" + _TLD + r"""/\S*
    )"""
)


def rule_I_urls(text: str, replacement: str) -> str:
    return _URL_RE.sub(replacement, text)


# Rule C.
def rule_C_strip_asterisks(text: str) -> str:
    return re.sub(r"\*+", "", text)


# Rule D. Anchored, so a `#123` issue reference mid-line survives.
def rule_D_strip_heading_marks(text: str) -> str:
    return re.sub(r"(?m)^[ \t]{0,3}#{1,6}[ \t]+", "", text)


# Rule B. Runs AFTER D, which needs the line anchors D matches on.
def rule_B_newlines_to_punct(text: str, boundary: str) -> str:
    def repl(m: re.Match) -> str:
        prev = m.group(1)
        # Don't double up if the line already ends in something the chunker
        # splits on. ':' and '-' are in the vocab but are NOT boundaries, so
        # they still need one appended.
        if prev in BOUNDARY_CHARS:
            return prev + " "
        return prev + boundary + " "

    text = re.sub(r"(\S)[ \t]*\n+[ \t]*", repl, text)
    return re.sub(r"^[ \t]*\n+[ \t]*", "", text)


# Rule G. Looped, because `1,234,567` needs three passes.
_THOUSANDS_RE = re.compile(r"(?<=\d),(?=\d{3}\b)")


def rule_G_strip_thousands(text: str) -> str:
    while True:
        new = _THOUSANDS_RE.sub("", text)
        if new == text:
            return text
        text = new


# Rule K. After G, so `$1,234.50` has already lost its comma.
def rule_K_currency(text: str) -> str:
    text = re.sub(r"\$(\d+)\.(\d{2})\b", r"\1 dollars \2", text)
    text = re.sub(r"\$(\d+)", r"\1 dollars", text)
    return text


# Rule E. MUST run before F, or `v0.3.0` becomes `v0 3 point 0`.
_VERSION_RE = re.compile(r"\d+(?:\.\d+){2,}")


def rule_E_version_dots(text: str) -> str:
    return _VERSION_RE.sub(lambda m: m.group(0).replace(".", " "), text)


# Rule F.
def rule_F_decimal_point(text: str) -> str:
    return re.sub(r"(?<=\d)\.(?=\d)", " point ", text)


# Rule J. Narrowed to `_`-joined tokens that actually contain an uppercase
# letter; the map records that widening it regresses `SHA-256` and `RAM`.
_SNAKE_RE = re.compile(r"\b\w+(?:_\w+)+\b")


def rule_J_lower_snake(text: str) -> str:
    return _SNAKE_RE.sub(
        lambda m: m.group(0).lower() if m.group(0) != m.group(0).lower() else m.group(0),
        text,
    )


# Rule L -- GATED. `lives` -> `livz` is verified to work when applied, but the
# trigger condition is explicitly listed under "Could not establish". The
# preceding-word test below fits all 7 probes in the doc and nothing more.
_LIVES_SAFE_PREV = {
    "it", "he", "she", "they", "we", "i", "you", "this", "that", "who",
    "which", "there", "and", "still",
}


def rule_L_respell(text: str) -> str:
    def repl(m: re.Match) -> str:
        prev = (m.group(1) or "").lower()
        word = m.group(2)
        if prev in _LIVES_SAFE_PREV:
            return m.group(0)
        return m.group(0)[: m.start(2) - m.start(0)] + (
            "Livz" if word[0].isupper() else "livz"
        )

    return re.sub(r"(?i)(?:(\w+)\s+)?\b(lives)\b", repl, text)


# Rule A. Runs LAST: it is arithmetic on the text that will actually be
# phonemised. The budget is input characters, which the doc flags as a
# character count standing in for a phoneme count -- it can under-protect on
# path- and identifier-heavy text.
def rule_A_guarantee_boundary(text: str, max_run: int, boundary: str) -> str:
    out: list[str] = []
    run_len = 0
    last_space = -1  # index into `out` of the most recent space in this run
    for ch in text:
        out.append(ch)
        if ch in BOUNDARY_CHARS:
            run_len = 0
            last_space = -1
            continue
        if ch.isspace():
            last_space = len(out) - 1
        run_len += 1
        if run_len >= max_run and last_space >= 0:
            out[last_space] = boundary + " "
            run_len = len(out) - 1 - last_space
            last_space = -1
    return "".join(out)


# --------------------------------------------------------------------------
# the reference candidate
# --------------------------------------------------------------------------

_CANDIDATE_RULES = """A-K from docs/research/espeak-sanitizer-rules.md, applied in this order:
  H  strip emoji                     (early, before anything matches on them)
  I  URLs -> "a link"                (before E/F, so a URL's dots survive nothing)
  C  strip *
  D  strip # heading markers         (line-anchored, so before B)
  B  line breaks -> terminal punct   (kills the newline, which the vocab drops)
  G  strip thousands separators      (before K and F)
  K  currency: unit after the number
  E  version dots -> spaces          (MUST precede F)
  F  decimal dot -> " point "
  J  lowercase _-joined identifiers
  L  respell mis-POS'd words         (only with --respell)
  A  guarantee a chunk boundary      (last: arithmetic on the final text)"""


@sanitizer(
    "candidate",
    "reference candidate: rules A-K, assembled from measured phoneme damage",
    _CANDIDATE_RULES,
)
def san_candidate(text: str, opts: Opts) -> str:
    text = rule_H_strip_emoji(text)
    text = rule_I_urls(text, opts.url_replacement)
    text = rule_C_strip_asterisks(text)
    text = rule_D_strip_heading_marks(text)
    text = rule_B_newlines_to_punct(text, opts.boundary)
    text = rule_G_strip_thousands(text)
    text = rule_K_currency(text)
    text = rule_E_version_dots(text)
    text = rule_F_decimal_point(text)
    text = rule_J_lower_snake(text)
    if opts.respell:
        text = rule_L_respell(text)
    text = rule_A_guarantee_boundary(text, opts.max_run, opts.boundary)
    return re.sub(r"[ \t]{2,}", " ", text).strip()


# --------------------------------------------------------------------------
# a third, to show what adding one costs: rule A alone
# --------------------------------------------------------------------------


@sanitizer(
    "crashguard",
    "rules B + A only: the two that decide whether create() raises, nothing else",
    "B (line breaks -> terminal punctuation), then A (boundary every --max-run chars)",
)
def san_crashguard(text: str, opts: Opts) -> str:
    text = rule_B_newlines_to_punct(text, opts.boundary)
    text = rule_A_guarantee_boundary(text, opts.max_run, opts.boundary)
    return text.strip()
