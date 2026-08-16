# `audition-10` — the minimum-length audition

The instrument for
[#10](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/10) ("how short is too
short to speak?"). **The findings, the listening index and the threshold sweep are in
[`docs/decisions/min-length-audition.md`](../../docs/decisions/min-length-audition.md)** — read
that; this directory is just what produced it.

**`items/` is real data, not fixtures.** Each of the sixteen `.txt` files is a verbatim assistant
message lifted out of this machine's Claude Code transcripts, sub-200 characters and therefore
never rewritten by the hook. `items.tsv` cites the session, message uuid and timestamp for every
one, and each file is byte-identical to the message it cites. Nothing here was authored to stand
in for a message; the hand-authored fixtures in this audition are the five `sNN` items, which live
in `corpus/spoken/` and are marked `hand-authored` in `corpus/manifest.tsv`.

```
items/                 16 real, raw, never-rewritten assistant messages, one per file
items.tsv              id, band (ACK / FACT), prose_len, origin, note
select-short-real.py   rebuilds items/ from a transcript extraction; selection is by uuid, in-script
run.sh                 synthesizes the audition (silent) -> ~/.local/share/kokoro/bench/audition-10/
phonemize.py           phoneme counts for a whole population, no synthesis (needs the Kokoro venv)
sweep.py               the duration law and both threshold sweep tables
```

Nothing here calls an LLM, touches a hook, or writes into `corpus/`. It reads `bench/bench` and
`bench/sanitizers.py` and modifies neither. Regeneration steps are at the bottom of the doc.
