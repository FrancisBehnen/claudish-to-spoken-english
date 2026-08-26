#!/usr/bin/env python3
"""The independent half of the handoff-key check.

`speak-key.sh` computes the key in shell. This computes it in Python, with
Python's own sha256 and Python's own strip, and the two are compared row by row
by `tests/speak-key-test.sh`. Neither is allowed to define the answer alone.

  speak-key-gen.py --emit  <cases.tsv> <outdir>  write one .txt per case,
                                                 print "name<TAB>key" per line
  speak-key-gen.py --regen <cases.tsv>           recompute the key column

Only ASCII whitespace is used in the fixtures on purpose: `str.strip()` also
strips non-breaking space and other Unicode whitespace, and POSIX
`[[:space:]]` in a shell does not, so a fixture that exercised that difference
would be pinning down a disagreement rather than an agreement.
"""
import hashlib
import pathlib
import sys


def unescape(s: str) -> str:
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            nxt = s[i + 1]
            if nxt == "n":
                out.append("\n"); i += 2; continue
            if nxt == "t":
                out.append("\t"); i += 2; continue
            if nxt == "\\":
                out.append("\\"); i += 2; continue
        out.append(c)
        i += 1
    return "".join(out)


def key(text: str) -> str:
    return hashlib.sha256(text.strip().encode("utf-8")).hexdigest()


def rows(path: pathlib.Path):
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        yield parts[0], parts[1], parts[2]


def main(argv):
    mode = argv[1]
    cases = pathlib.Path(argv[2])
    if mode == "--regen":
        out = []
        for line in cases.read_text(encoding="utf-8").splitlines():
            if not line.strip() or line.startswith("#"):
                out.append(line)
                continue
            parts = line.split("\t")
            if len(parts) < 3:
                out.append(line)
                continue
            parts[2] = key(unescape(parts[1]))
            out.append("\t".join(parts[:3]))
        cases.write_text("\n".join(out) + "\n", encoding="utf-8")
        return 0
    if mode == "--emit":
        outdir = pathlib.Path(argv[3])
        outdir.mkdir(parents=True, exist_ok=True)
        for name, esc, expected in sorted(rows(cases)):
            text = unescape(esc)
            (outdir / (name + ".txt")).write_text(text, encoding="utf-8")
            computed = key(text)
            if computed != expected:
                print("%s: table says %s, python says %s"
                      % (name, expected, computed), file=sys.stderr)
                return 1
            print("%s\t%s" % (name, expected))
        return 0
    print("unknown mode %r" % mode, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
