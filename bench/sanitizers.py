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

The bottom half of this file is the **#8 audition set**: a `base` reference
plus one variant per open axis of #8, so each axis can be heard as an A/B.
Those are not decisions either -- they are the alternatives, built so that a
listener can pick one. See `docs/decisions/sanitizer-audition.md`.

The last three variants (`flag-pause`, `ext-word`, `path-short-nolead`) are
**#13's follow-up set**: two rules #8's listener asked for that had never been
auditioned, and the one combination #8's decision left explicitly unmeasured.
Same rule: not decisions, just the alternatives. See
`docs/decisions/sanitizer-audition-13.md`.
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
# `\S+` runs to whitespace, so a URL ending a sentence takes the full stop
# with it -- which silently deletes a chunk boundary, the one thing rule B
# and rule A exist to create. Handed back before the substitution. (Found
# while building the #8 audition: `s26` lost a sentence boundary under
# `candidate`. The rule's own worked example keeps its full stop, so this is
# the rule doing what it was written to do.)
_URL_TRAIL = ".,;:!?)\"'"


def rule_I_urls(text: str, replacement: str) -> str:
    return _URL_RE.sub(
        lambda m: replacement + _url_trail(m.group(0)), text
    )


def _url_trail(u: str) -> str:
    return u[len(u.rstrip(_URL_TRAIL)):]


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


# ==========================================================================
# The #8 audition set: one variant per open axis
# ==========================================================================
#
# STILL NOT A DECISION. #8 is decided by ear and nothing in this file has
# been listened to. These variants exist so that each open axis of #8 can be
# HEARD as an A/B against a fixed reference, instead of argued about.
#
# `base` is that reference: rule-for-rule the same pipeline as `candidate`,
# with one named choice per open axis. Every other variant below changes
# EXACTLY ONE of those choices, so the pair (`base`, `variant`) isolates the
# axis. `none` stays the control for all of them.
#
# The open axes, and `base`'s default for each:
#
#   markdown   strip  -- rules C + D
#   urls       link   -- rule I, replace with "a link"
#   scream     lower  -- rule J, lowercase `_`-joined identifiers
#   paths      asis   -- no path rule at all: espeak says every "slash"
#   code       read   -- fenced blocks are read out; the fence is silent
#   ticks      keep   -- backticks left in place (espeak emits nothing for them)
#   boundary   "."    -- what rules B and A insert
#
# and the two axes #13 adds, both of which `base` also declines to do:
#
#   flags      keep   -- a flag name / bare identifier is left as it is
#   exts       keep   -- a file extension's `.` reaches espeak as a full stop
#
# Adding one more is still a one-function job: a new field value, a helper
# branch, and one decorated line.


@dataclass
class Axes:
    """One choice per open axis of #8 (plus #13's two). Defaults are `base`."""

    markdown: str = "strip"  # strip | swallow | strip-plus
    urls: str = "link"  # link | full | domain
    scream: str = "lower"  # lower | asis | spell | drop
    paths: str = "asis"  # asis | nolead | basename | shorten | shorten-nolead
    #                      | expand
    code: str = "read"  # read | long | count | short | silent
    ticks: str = "keep"  # keep | strip | pause
    flags: str = "keep"  # keep | pause          (#13)
    exts: str = "keep"  # keep | word            (#13)
    boundary: str = ""  # "" -> opts.boundary


# --- code blocks (settled: skipped and announced; the WORDING is open) -----

_NUMWORD = {
    1: "one", 2: "two", 3: "three", 4: "four", 5: "five", 6: "six",
    7: "seven", 8: "eight", 9: "nine", 10: "ten", 11: "eleven", 12: "twelve",
    13: "thirteen", 14: "fourteen", 15: "fifteen", 16: "sixteen",
    17: "seventeen", 18: "eighteen", 19: "nineteen", 20: "twenty",
}


def _numword(n: int) -> str:
    # Spelled out so the announcement carries no NUM-UNIT hazard of its own.
    return _NUMWORD.get(n, str(n))


_FENCE_RE = re.compile(r"(?ms)^[ \t]*```[^\n]*\n(?P<body>.*?)^[ \t]*```[ \t]*$")


def rule_N_code_block(text: str, mode: str) -> str:
    """Replace a fenced block with an announcement. `read` leaves it alone.

    `silent` emits a bare `.` -- kokoro-onnx has no pause primitive other than
    punctuation, so "nothing but a pause" IS a full stop with no words.
    """
    if mode == "read":
        return text

    def repl(m: re.Match) -> str:
        n = len([ln for ln in m.group("body").splitlines() if ln.strip()])
        if mode == "silent":
            return "."
        if mode == "short":
            return "Code block."
        plural = "line" if n == 1 else "lines"
        if mode == "count":
            return f"Code block, {_numword(n)} {plural}."
        return f"Then a {_numword(n)} line code block."

    return _FENCE_RE.sub(repl, text)


# --- backticks (MD-BACKTICK: 9 of 12 real items) --------------------------

_TICK_SPAN_RE = re.compile(r"`([^`\n]+)`")

# Where a comma would be redundant: nothing precedes the span, or an opening
# bracket does; a mark the chunker already splits on follows it.
_SET_OFF_OPEN = ("", "\n", "(", "[", "{")
_SET_OFF_CLOSE = ".,;:!?)]"


def _set_off(m: re.Match, inner: str) -> str:
    """`inner`, set off with the chunker's own comma on each side that does not
    already carry punctuation.

    Extracted so axis 1 (`tick-pause`) and #13's axis 8 (`flag-pause`) apply
    the IDENTICAL treatment -- the whole premise of #13's first rule is that
    the thing axis 1 chose was the commas, so the generalisation has to be the
    same commas and not a second opinion about them.
    """
    before = m.string[m.start() - 1: m.start()] if m.start() else ""
    follows = m.string[m.end():m.end() + 1]
    head = "" if before in _SET_OFF_OPEN else ", "
    tail = "" if follows in _SET_OFF_CLOSE else ", "
    return head + inner + tail


def _tidy_commas(text: str) -> str:
    """Collapse the doubles `_set_off` can leave, and drop a line-leading one.

    Deliberately NOT a blanket ", X" -> "X" tidy: that would eat the real
    commas in "It handles .sh, .py, .md".
    """
    text = re.sub(r",[ \t]*,", ",", text)
    return re.sub(r"(?m)^[ \t]*,[ \t]*", "", text)


def _split_ticks(text: str) -> list[tuple[str, bool]]:
    """-> [(segment, is_a_backticked_span), ...], covering `text` exactly."""
    out: list[tuple[str, bool]] = []
    i = 0
    for m in _TICK_SPAN_RE.finditer(text):
        if m.start() > i:
            out.append((text[i:m.start()], False))
        out.append((m.group(0), True))
        i = m.end()
    out.append((text[i:], False))
    return out


def rule_T_ticks(text: str, mode: str) -> str:
    """espeak emits NOTHING for a backtick, so this axis is about the words
    around it. `strip` removes the character (expected: a measured no-op).
    `pause` sets the span off with the chunker's own boundary character."""
    if mode == "keep":
        return text
    if mode == "strip":
        return text.replace("`", "")
    text = _TICK_SPAN_RE.sub(lambda m: _set_off(m, m.group(1)), text)
    return _tidy_commas(text.replace("`", ""))


# --- paths (PATH-SLASH 7 real, PATH-EXT 5 real) ---------------------------

_SEG = r"\.?[\w-]+(?:\.[\w-]+)*"
_PATH_RE = re.compile(
    r"(?<![\w/~.@-])(?P<lead>~/|\.{1,2}/|/)?(?P<body>(?:" + _SEG + r"/)+" + _SEG + r")"
)
# Extensions seen in the corpus. Deliberately a list, not `\w+`: a bare
# `\w+\.\w+` would eat "docs. Read" and every ordinary sentence.
_EXTS = (
    "sh|py|md|json|jsonl|txt|log|tsv|csv|yaml|yml|toml|wav|onnx|bin|"
    "ts|js|html|xml|cfg|ini|lock|sql"
)
_BARE_EXT_RE = re.compile(r"\b([\w-]+)\.(" + _EXTS + r")\b")


def _spell_ext(seg: str) -> str:
    m = re.fullmatch(r"(.+)\.(" + _EXTS + r")", seg)
    if not m:
        return seg
    return f"{m.group(1)} dot {' '.join(m.group(2).upper())}"


def rule_P_paths(text: str, mode: str) -> str:
    """`asis` is no rule at all. The others reshape a multi-segment path."""
    if mode == "asis":
        return text

    def repl(m: re.Match) -> str:
        segs = m.group("body").split("/")
        if mode == "nolead":  # drop `~/`, `/`, `./` and a leading bare dot
            segs[0] = segs[0].lstrip(".") or segs[0]
            return "/".join(segs)
        if mode == "basename":
            return segs[-1]
        if mode == "shorten":
            return "/".join(segs[-2:])
        if mode == "shorten-nolead":
            # #13: #8 left `path-shorten` and `path-nolead` both undefeated and
            # never heard together. Note that `shorten` ALREADY drops `~/`, `/`
            # and `./` -- only `expand` re-attaches the lead -- so the whole
            # audible difference between this and `shorten` is the bare dot on
            # whichever segment survives first: `.claude/settings.json`.
            segs = segs[-2:]
            segs[0] = segs[0].lstrip(".") or segs[0]
            return "/".join(segs)
        lead = m.group("lead") or ""  # expand: keep every segment
        return lead + " slash ".join(_spell_ext(s) for s in segs)

    out = _PATH_RE.sub(repl, text)
    if mode == "expand":  # bare `name.ext` in prose carries PATH-EXT too
        out = _BARE_EXT_RE.sub(lambda m: _spell_ext(m.group(0)), out)
    return out


# --- flag names and bare identifiers (axis 8, from #13) --------------------
#
# The #8 listener's note on `s15:scream-drop`: "B would be even better if it
# gets a comma before and after the flag name I think, like what you did with
# variables in `backticks`". Axis 1 chose `tick-pause` and established that the
# win was the COMMAS, not the backtick removal -- so this is that treatment,
# applied to the code tokens that carry no backticks.
#
# Three shapes, and no more:
#
#   flags        `-p`, `-R`, `--max-time`, `--strict-mcp-config`
#   assignments  `CLAUDISH_ENABLED=0`, `curl_rc=28`, `http=429`
#   `_`-joined   `curl_rc`, `CLAUDISH_MIN_CHARS`  -- exactly rule J's set
#
# Bare acronyms (`RAM`, `SHA-256`) and camelCase are deliberately NOT in it,
# for the reason #1 records for narrowing rule J the same way: any widening
# regresses ordinary words. (`GitHub` satisfies every camelCase test there is.)
# Paths and filenames are axis 3's business, and a `name.ext` is axis 9's, so
# the trailing lookahead hands those back.
#
# Two boundary bugs, found in review of #13 and fixed here. Both are about an
# `=`, and both are TEXT-IDENTICAL FIXES on the whole corpus -- all 54 items of
# `corpus/spoken/`, `flag-pause` against `base` unchanged on every one, so
# #13's 4-0 still describes the rule below:
#
#   `--flag=value`  the flag arm won the alternation and stopped at `--flag`,
#                   orphaning the value: ", --flag, =value". A flag now takes
#                   its `=value` with it, so the whole token is set off once.
#   `name=value.`   `[\w.:/-]+` is greedy and `.` is in it, so a sentence-final
#                   full stop was eaten INTO the span and the closing comma was
#                   then suppressed against it. A value must now end on a
#                   non-dot character, which leaves the `.` outside where
#                   `_set_off` reads it as the boundary it is.
#
# Still true and deliberate: an `=value` that ends in a known extension
# (`out_file=notes.md`) is set off WHOLE and axis 9 does not see inside it.
# Splitting there would hand axis 9 a bare `.md`, which it leaves alone by
# design, so the split would buy nothing.
_BARE_SPAN_RE = re.compile(
    r"(?<![\w/=.-])(?:"
    r"--?[A-Za-z][\w-]*(?:=[\w.:/-]*[\w:/-])?"  # a flag, with its value
    r"|[A-Za-z_][\w-]*=[\w.:/-]*[\w:/-]"        # a bare assignment
    r"|[A-Za-z]\w*(?:_\w+)+"                    # a `_`-joined identifier
    r")(?![\w/=])(?!\.(?:" + _EXTS + r")\b)"
)


def rule_S_bare_spans(text: str, mode: str) -> str:
    """Set a flag name or a bare identifier off with axis 1's commas.

    Backticked spans are stepped OVER rather than matched inside, so this axis
    and axis 1 stay independent: under `base` (ticks kept) a `` `--flag` `` is
    left alone here, and the pair (`base`, `flag-pause`) still moves exactly
    one axis even on an item that is full of backticks.
    """
    if mode == "keep":
        return text
    out = [seg if is_tick
           else _BARE_SPAN_RE.sub(lambda m: _set_off(m, m.group(0)), seg)
           for seg, is_tick in _split_ticks(text)]
    return _tidy_commas("".join(out))


# --- pronounceable file extensions (axis 9, from #13) ---------------------
#
# The #8 listener's note on `s10:path-expand`: "`hooks.json` should become
# 'hooks dot json' so that 'json' is pronounced". `path-expand` spells EVERY
# extension -- `.md` becomes " dot M D" -- and the axis-3 winner `path-shorten`
# does not touch extensions at all, so neither settled variant covers this.
#
# The obvious implementation is a table saying which extensions are words and
# which are letters. It is NOT NEEDED, and this is measured, not assumed. For
# all 23 extensions `_EXTS` lists, espeak's reading of the extension is
# BYTE-IDENTICAL after a `.` and after the word "dot":
#
#   foo.json  -> 'fˈuː.dʒˈeɪsˈɑːn'      foo dot json -> ... dˈɑːt dʒˈeɪsˈɑːn'
#   foo.sh    -> 'fˈuː.ˌɛsˈeɪtʃ'        foo dot sh   -> ... dˈɑːt ˌɛsˈeɪtʃ'
#
# and it is already right in every case: `json` "jason", `sh` "S-H", `py`
# "pie", `md` "M-D", `sql` "sequel", `yaml` "yamel", `log` "log", `wav` "wav".
# Spelling them out is what breaks them -- `log` becomes "L-O-G", `wav`
# "double-U-A-V", `py` "P-Y" -- which is exactly the note's complaint about
# `path-expand`.
#
# So the rule does ONE thing: the `.` becomes the word "dot". That removes the
# sentence-final mark PATH-EXT is about and leaves the pronunciation to the
# frontend that already gets it right. One known limit, unfixed by anything
# here: espeak reads `yml` as "immel".
def rule_X_extensions(text: str, mode: str) -> str:
    """`name.ext` -> `name dot ext`: the dot said, the `.` gone, the extension
    handed to espeak untouched.

    A BARE extension (`.sh` with no name in front of it, as in s09) is left
    alone: `PATH-EXTBARE` is a documented control class -- both frontends
    already agree on it -- and the hazard this rule exists for is the `.`
    INSIDE `name.ext` landing as a sentence-final mark.
    """
    if mode == "keep":
        return text
    return _BARE_EXT_RE.sub(lambda m: f"{m.group(1)} dot {m.group(2)}", text)


# --- SCREAMING_SNAKE_CASE (rule J is the `lower` arm) ---------------------


def rule_J_scream(text: str, mode: str) -> str:
    """Narrowed to `_`-joined tokens exactly as rule J is, because #1 records
    that widening it regresses `SHA-256` to "shah" and `RAM` to "ram"."""
    if mode == "asis":
        return text

    def repl(m: re.Match) -> str:
        tok = m.group(0)
        if tok == tok.lower():
            return tok
        if mode == "lower":
            return tok.lower()
        if mode == "spell":  # letters as separate tokens, `_` -> a comma
            return ", ".join(" ".join(seg.upper()) for seg in tok.split("_"))
        return ""  # drop

    # No tidy-up beyond the double space the deletion leaves, which the
    # pipeline collapses anyway: a "drop the space before punctuation" pass
    # also fires on ordinary text like "It handles .sh, .py, .md".
    return _SNAKE_RE.sub(repl, text)


# --- URLs (rule I is the `link` arm) --------------------------------------


def rule_I_domain(text: str) -> str:
    def repl(m: re.Match) -> str:
        raw = m.group(0)
        u = re.sub(r"(?i)^https?://", "", raw)
        u = re.sub(r"(?i)^www\.", "", u)
        host = u.split("/")[0].split(":")[0].rstrip(_URL_TRAIL)
        # Same trailing-punctuation hand-back as rule I: a URL that closes a
        # sentence or a markdown link must not take the mark with it.
        return host.replace(".", " dot ") + _url_trail(raw)

    return _URL_RE.sub(repl, text)


# --- markdown beyond C and D ----------------------------------------------


def rule_MD_extra(text: str) -> str:
    """Subtractive only. Every character removed here is measured SILENT
    already (MD-UNDERSCORE / MD-BULLET / MD-BLOCKQUOTE / MD-PIPE controls),
    so the listening question is whether removing them changes anything."""
    text = re.sub(r"(?m)^[ \t]*>[ \t]?", "", text)  # blockquote markers
    text = re.sub(r"(?m)^[ \t]*[-+][ \t]+", "", text)  # `-` bullets
    text = re.sub(r"(?m)^[ \t]*\d+\.[ \t]+", "", text)  # ordered markers
    text = text.replace("|", " ")  # table pipes
    # `_italic_` only -- a blanket `_` strip would silently defeat the
    # SCREAMING_SNAKE axis by dissolving every `_`-joined identifier.
    return re.sub(r"(?<![\w])_([^_\n]+)_(?![\w])", r"\1", text)


# --- the parameterised pipeline -------------------------------------------


def _pipeline(text: str, opts: Opts, ax: Axes) -> str:
    b = ax.boundary or opts.boundary
    text = rule_H_strip_emoji(text)
    text = rule_N_code_block(text, ax.code)  # before D: kills `#` inside code
    if ax.urls == "link":
        text = rule_I_urls(text, opts.url_replacement)
    elif ax.urls == "domain":
        text = rule_I_domain(text)
    if ax.markdown in ("strip", "strip-plus"):
        text = rule_C_strip_asterisks(text)
        text = rule_D_strip_heading_marks(text)
    if ax.markdown == "strip-plus":
        text = rule_MD_extra(text)
    text = rule_T_ticks(text, ax.ticks)
    text = rule_S_bare_spans(text, ax.flags)  # #13: axis 1's commas, no ticks
    text = rule_B_newlines_to_punct(text, b)
    text = rule_P_paths(text, ax.paths)
    text = rule_X_extensions(text, ax.exts)  # #13: after P, so a surviving
    #                                          segment's extension still speaks
    text = rule_G_strip_thousands(text)
    text = rule_K_currency(text)
    text = rule_E_version_dots(text)
    text = rule_F_decimal_point(text)
    text = rule_J_scream(text, ax.scream)
    if opts.respell:
        text = rule_L_respell(text)
    text = rule_A_guarantee_boundary(text, opts.max_run, b)
    return re.sub(r"[ \t]{2,}", " ", text).strip()


_BASE_RULES = """the #8 reference point: candidate's rules, one choice per open axis
  markdown strip   C + D
  urls     link    I
  scream   lower   J
  paths    asis    no path rule
  code     read    fenced blocks read out
  ticks    keep    backticks left in place
  flags    keep    flag names and bare identifiers left as they are   (#13)
  exts     keep    a file extension's '.' reaches espeak              (#13)
  boundary '.'     what B and A insert"""


@sanitizer("base", "reference: candidate's rules, the default on every open axis", _BASE_RULES)
def san_base(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes())


# --- axis 1: backtick prosody (MD-BACKTICK, 9 of 12 real items) -----------


@sanitizer("tick-strip", "base, but the backtick characters are removed")
def san_tick_strip(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(ticks="strip"))


@sanitizer("tick-pause", "base, but each `span` is set off with commas")
def san_tick_pause(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(ticks="pause"))


# --- axis 2: the line-break replacement (rule B) --------------------------
#
# SETTLED 2026-08-25, by ear, and NOT by either variant below: the boundary is
# `,` for 3 bullets or fewer and `.` for 4 and up. Both of these apply ONE
# character to every line break in the item, which is why #8's three pairs read
# as a 1-1 tie -- the axis as posed could not express the answer. The three
# verdicts fit the conditional rule exactly: `r09` (paragraph-heavy) no audible
# difference, `s37` (8 bullets) `.`, `s38` (3 bullets) `,`.
#
# NO SANITIZER HERE IMPLEMENTS IT. All 26 take a fixed `boundary`, so the
# settled rule is a new capability to be BUILT, not a variant to be selected,
# and the cutoff's exact position is the listener's call rather than an audited
# result -- nothing between 4 and 7 bullets has ever been synthesized. Neither
# choice carries crash-safety weight: `BOUNDARY_CHARS` above is the set
# `_split_phonemes` itself splits on, so `.` and `,` are both valid batch seams
# and both avert the 510-phoneme IndexError.


@sanitizer("lb-period", "base with '.' as the line-break replacement (same as base)")
def san_lb_period(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(boundary="."))


@sanitizer("lb-comma", "base with ',' as the line-break replacement")
def san_lb_comma(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(boundary=","))


# --- axis 3: paths (PATH-SLASH 7 real, PATH-EXT 5 real) -------------------


@sanitizer("path-nolead", "base, but a leading '~/', '/', './' or '.' is dropped")
def san_path_nolead(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(paths="nolead"))


@sanitizer("path-basename", "base, but a path is reduced to its last segment")
def san_path_basename(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(paths="basename"))


@sanitizer("path-shorten", "base, but a path is reduced to its last two segments")
def san_path_shorten(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(paths="shorten"))


@sanitizer("path-expand", "base, but separators become ' slash ' and '.md' becomes ' dot M D'")
def san_path_expand(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(paths="expand"))


# --- axis 4: markdown, swallowed or stripped (MD-ASTERISK, 6 real) --------


@sanitizer("md-swallow", "base minus C and D: '*' and '#' reach espeak")
def san_md_swallow(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(markdown="swallow"))


@sanitizer("md-strip-plus", "base plus the already-silent markdown: bullets, '>', '|', '_italic_'")
def san_md_strip_plus(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(markdown="strip-plus"))


# --- axis 5: SCREAMING_SNAKE_CASE (ID-SCREAM) -----------------------------


@sanitizer("scream-asis", "base minus J: SCREAMING_SNAKE_CASE reaches espeak uppercase")
def san_scream_asis(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(scream="asis"))


@sanitizer("scream-spell", "base, but the identifier is spelled letter by letter")
def san_scream_spell(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(scream="spell"))


@sanitizer("scream-drop", "base, but the identifier is deleted from the sentence")
def san_scream_drop(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(scream="drop"))


# --- axis 6: URLs ---------------------------------------------------------


@sanitizer("url-full", "base minus I: the URL is read out in full")
def san_url_full(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(urls="full"))


@sanitizer("url-domain", "base, but a URL becomes its host: 'github dot com'")
def san_url_domain(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(urls="domain"))


# --- axis 7: how a skipped code block is announced ------------------------


@sanitizer("cb-long", "code block -> 'Then an N line code block.'")
def san_cb_long(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(code="long"))


@sanitizer("cb-count", "code block -> 'Code block, N lines.'")
def san_cb_count(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(code="count"))


@sanitizer("cb-short", "code block -> 'Code block.'")
def san_cb_short(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(code="short"))


@sanitizer("cb-silent", "code block -> a bare '.', i.e. nothing but a pause")
def san_cb_silent(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(code="silent"))


# ==========================================================================
# The #13 follow-up set: two rules #8's notes asked for, and one combination
# #8's decision left unmeasured
# ==========================================================================
#
# STILL NOT A DECISION, and #8's seven axes are NOT reopened. Each of these
# moves exactly one axis off the same `base` reference #8 used, so the pairs
# read the same way #8's did. See `docs/decisions/sanitizer-audition-13.md`.


# --- axis 8: commas around flag names and bare identifiers ----------------


@sanitizer("flag-pause",
           "base, but a flag name or bare identifier is set off with commas")
def san_flag_pause(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(flags="pause"))


# --- axis 9: pronounceable file extensions --------------------------------


@sanitizer("ext-word",
           "base, but 'hooks.json' becomes 'hooks dot json': the dot is said")
def san_ext_word(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(exts="word"))


# --- axis 3, continued: path-shorten and path-nolead, heard together ------
#
# NOT a tenth axis. It is a third candidate on #8's existing axis 3, which is
# how the audition page files it and how both decision documents record it --
# and it is now that axis's winner, replacing `path-shorten`.


@sanitizer("path-short-nolead",
           "base, but a path is its last two segments AND loses a leading dot")
def san_path_short_nolead(text: str, opts: Opts) -> str:
    return _pipeline(text, opts, Axes(paths="shorten-nolead"))
