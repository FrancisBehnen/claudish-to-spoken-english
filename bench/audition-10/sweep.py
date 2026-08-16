#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# The #10 threshold sweep: what each candidate CLAUDISH_SPEAK_MIN_CHARS value
# would do, over two populations.
#
#   1. every assistant message in this machine's transcripts for this repo
#      (the frequency answer: how often speech fires, and how much of it)
#   2. the 50-item speech corpus (continuity with bench and #6)
#
# Duration is not guessed from characters. The audition measures that speech
# duration tracks PHONEMES almost exactly and characters only loosely, so this
# fits audio_s on phonemes from the 27 measured audition items and applies that
# law to per-message phoneme counts produced by phonemize.py. The fit, its R^2
# and its residuals are printed so it can be distrusted precisely.
#
#   python3 bench/audition-10/sweep.py [audition.tsv] [phon.tsv]
#
# Both default to ~/.local/share/kokoro/bench/audition-10/, where run.sh and
# phonemize.py put them.
#
# Pass --extract-dir DIR (the directory extract-real-sources.sh wrote) and it
# also prints the arrival-rate table: how far apart messages actually land, and
# therefore what share of a working session would be spoken aloud.
#
# No LLM, no synthesis, no hook. Counting only.
# ---------------------------------------------------------------------------
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
OUT = pathlib.Path.home() / ".local/share/kokoro/bench/audition-10"
THRESHOLDS = [0, 20, 40, 60, 80, 100, 120, 150, 200, 250, 300]


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


def read_tsv(path):
    rows = []
    lines = path.read_text(encoding="utf-8").splitlines()
    head = lines[0].split("\t")
    for line in lines[1:]:
        if line.strip():
            rows.append(dict(zip(head, line.split("\t"))))
    return rows


def fit(xs, ys):
    """least squares y = a + b x, plus R^2"""
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    b = (sum((x - mx) * (y - my) for x, y in zip(xs, ys))
         / sum((x - mx) ** 2 for x in xs))
    a = my - b * mx
    ss_tot = sum((y - my) ** 2 for y in ys)
    ss_res = sum((y - (a + b * x)) ** 2 for x, y in zip(xs, ys))
    return a, b, 1 - ss_res / ss_tot


def audition_texts():
    texts = {}
    for p in sorted((HERE / "items").glob("*.txt")):
        texts[p.stem] = p.read_text(encoding="utf-8")
    for i in ("r01", "r03", "r06"):
        texts[f"raw-{i}"] = (REPO / "corpus/source" / f"{i}.txt").read_text(encoding="utf-8")
        texts[f"rew-{i}"] = (REPO / "corpus/spoken" / f"{i}.txt").read_text(encoding="utf-8")
    for i in ("s09", "s15", "s21", "s32", "s33"):
        texts[i] = (REPO / "corpus/spoken" / f"{i}.txt").read_text(encoding="utf-8")
    return texts


def arrival_rate(exdir, rows, dur):
    """Median gap between assistant messages, and the speech duty cycle."""
    import datetime
    import json
    import statistics

    ph = {r["id"]: (int(r["prose_len"]), int(r["phonemes"]))
          for r in rows if r["pop"] == "transcript"}
    msgs = [json.loads(x) for x in
            (exdir / "all.jsonl").read_text(encoding="utf-8").splitlines() if x.strip()]
    bysess = {}
    for d in msgs:
        bysess.setdefault(d["sess"][:8], []).append(d)

    gaps, active = [], 0.0
    for ds in bysess.values():
        ds.sort(key=lambda d: d["ts"])
        ts = [datetime.datetime.fromisoformat(d["ts"].replace("Z", "+00:00")) for d in ds]
        g = [(ts[i + 1] - ts[i]).total_seconds() for i in range(len(ts) - 1)]
        g = [x for x in g if x < 3600]  # anything longer is a session break
        gaps += g
        active += sum(g)
    gaps.sort()
    print(f"arrival rate: {len(gaps)} gaps, median {statistics.median(gaps):.0f}s "
          f"(p10 {gaps[len(gaps) // 10]:.0f}s, p25 {gaps[len(gaps) // 4]:.0f}s, "
          f"p75 {gaps[3 * len(gaps) // 4]:.0f}s); "
          f"active session time {active / 60:.0f} min")
    print(f"  {'thresh':>6} {'spoken':>7} {'speech':>10} {'share of active':>16}")
    for t in THRESHOLDS:
        tot = sum(dur(p) for pl, p in ph.values() if pl >= t)
        n = sum(1 for pl, _ in ph.values() if pl >= t)
        print(f"  {t:>6} {n:>7} {tot / 60:>9.1f}m {100 * tot / active:>15.1f}%")
    print()


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    exdir = None
    for i, a in enumerate(sys.argv):
        if a == "--extract-dir":
            exdir = pathlib.Path(sys.argv[i + 1])
            args = [x for x in args if x != sys.argv[i + 1]]
    audtsv = pathlib.Path(args[0]) if len(args) > 0 else OUT / "audition.tsv"
    phontsv = pathlib.Path(args[1]) if len(args) > 1 else OUT / "phon.tsv"

    # ---- the duration law, measured ---------------------------------------
    texts = audition_texts()
    meas = []  # (item, prose_len, phonemes, audio_s)
    for r in read_tsv(audtsv):
        if r["status"] != "OK" or r["item"] not in texts:
            continue
        meas.append((r["item"], prose_len(texts[r["item"]]),
                     int(r["phonemes"]), float(r["audio_s"])))

    a, b, r2 = fit([m[2] for m in meas], [m[3] for m in meas])
    ca, cb, cr2 = fit([m[1] for m in meas], [m[3] for m in meas])
    dens = sorted(m[2] / m[1] for m in meas)
    print(f"duration law, from {len(meas)} measured audition items:")
    print(f"  on phonemes:   audio_s = {a:.3f} + {b:.5f} * phonemes   R^2 = {r2:.4f}")
    print(f"  on characters: audio_s = {ca:.3f} + {cb:.5f} * prose_len  R^2 = {cr2:.4f}")
    print(f"  phoneme density over those items: {dens[0]:.2f}-{dens[-1]:.2f} "
          f"per prose char (median {dens[len(dens) // 2]:.2f})")
    worst = sorted(meas, key=lambda m: -abs(m[3] - (a + b * m[2])))[:3]
    print("  largest residuals on the phoneme law: " + ", ".join(
        f"{m[0]} {m[3]:.2f}s vs {a + b * m[2]:.2f}s" for m in worst))
    print()

    def dur(ph):
        return a + b * ph

    rows = read_tsv(phontsv)
    pops = {
        "transcript": "population 1: assistant messages in this machine's "
                      "transcripts for this repo",
        "corpus": "population 2: the 50-item speech corpus",
    }
    measured_audio = {m[0]: m[3] for m in meas}
    for pop, title in pops.items():
        sel = [(int(r["prose_len"]), int(r["phonemes"]), r["id"])
               for r in rows if r["pop"] == pop]
        dsel = sorted(ph / pl for pl, ph, _ in sel if pl)
        print(f"{title}  ({len(sel)} items)")
        print(f"  phoneme density across the population: {dsel[0]:.2f}-"
              f"{dsel[-1]:.2f} per prose char (median {dsel[len(dsel) // 2]:.2f})")
        sweep(sel, dur, measured_audio)
        print()

    if exdir is not None:
        arrival_rate(exdir, rows, dur)
    return 0


def sweep(items, dur, measured_audio):
    total = len(items)
    hdr = ("thresh", "spoken", "silent", "%", "shortest", "its", "shortest",
           "median", "total")
    hdr2 = ("chars", "", "", "", "chars", "seconds", "utterance", "spoken", "speech")
    print("  " + " ".join(f"{h:>9}" for h in hdr))
    print("  " + " ".join(f"{h:>9}" for h in hdr2))
    for t in THRESHOLDS:
        spoken = [i for i in items if i[0] >= t]
        if not spoken:
            print(f"  {t:>9} {0:>9} {total:>9}" + "         -" * 6)
            continue
        secs = sorted((measured_audio.get(i[2], dur(i[1])), i[0]) for i in spoken)
        by_chars = sorted(spoken)
        short_chars = by_chars[0]
        short_secs = measured_audio.get(short_chars[2], dur(short_chars[1]))
        med = secs[len(secs) // 2][0]
        tot = sum(s for s, _ in secs)
        print(f"  {t:>9} {len(spoken):>9} {total - len(spoken):>9} "
              f"{100 * len(spoken) // total:>8}% {short_chars[0]:>9} "
              f"{short_secs:>8.1f}s {secs[0][0]:>8.1f}s {med:>8.1f}s "
              f"{tot / 60:>8.1f}m")
    print("  'shortest chars' is the shortest message that would be spoken; 'its "
          "seconds' is how long")
    print("  that one takes. 'shortest utterance' is the shortest SPEECH at that "
          "threshold, which is a")
    print("  different message whenever a longer message is denser.")


if __name__ == "__main__":
    raise SystemExit(main())
