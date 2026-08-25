# Handoff timing probe

The probe behind [`handoff-match-rate.md`](../handoff-match-rate.md) §3.2 and §4. It answers two
separate questions with one capture:

1. **Does `Stop.last_assistant_message` equal `rewrite.sh`'s delta concatenation?** (`match.sh` —
   compared after the turn settles, so the answer is independent of any race.)
2. **Does `Stop` wait for the `MessageDisplay` hook?** (`collect.sh`, `latency.sh` — the ordering.)

Committed so both results are re-measurable by someone who was not there. The original captures for
the first 35-turn run were destroyed; the 32 turns in `runs.tsv` were measured with *this* kit and
are the reproducible ones.

This kit was then run once more, end to end from an empty directory — `setup.sh`, a fresh session,
two driven turns, `collect.sh` — to confirm the committed copy works as published rather than only in
the tree it was developed in. Those two turns reproduced the finding independently: dispatch gaps
+6.6 ms and +211.7 ms, `Stop` starting 3.9–4.1 s before the display hook returned, the
slow-published buffer stale both times, and `match.sh` returning `exact` both times. They are not in
`runs.tsv`, which is the measurement proper.

## Run it

```bash
export PROBE_DIR=/tmp/handoff-probe
./setup.sh                     # makes the dirs + the THROWAWAY settings file
                               # and prints the launch command and checksums
```

`setup.sh` prints the `claude --settings …` line to launch the probe session. Then per turn:

```bash
PROBE_DIR=/tmp/handoff-probe ./run.sh mytag 4 "Write six paragraphs about lighthouses."
PROBE_DIR=/tmp/handoff-probe ./collect.sh      # the ordering table
PROBE_DIR=/tmp/handoff-probe ./latency.sh      # the in-hook budget
```

`run.sh` drives the session through Herdr. Swap that one line for any driver; nothing else depends
on it.

Set the hold to `0` for the control regime and `4` for the slow-display-hook regime. The control is
not optional — it is what proves the dispatch gap does not depend on the hook's duration, and
therefore that `Stop` is not waiting.

## Reading the output

`collect.sh` columns:

| column | meaning |
| --- | --- |
| `dispatch_gap_ms` | `Stop` entry − final-chunk `MessageDisplay` entry. Positive = display hook started first. |
| `stop_start_minus_md_return_ms` | Negative = `Stop` started **before** the display hook returned, i.e. concurrent. |
| `read_vs_immediate_publish_ms` | Negative = `Stop` read the buffer **before** the display hook could publish, even publishing at once. |
| `buf_immediate` / `buf_slow` | `STALE` = the buffer held a **previous** turn's text at `Stop`'s read. |

## Five traps this kit exists to avoid

1. **`~/.claude/settings.json` is never written.** The hooks live in a throwaway file passed to one
   session with `--settings`. `setup.sh` prints its sha256 so you can diff before and after.
2. **`zsh -f` does not autoload `zsh/datetime`**, so a bare `$EPOCHREALTIME` expands to the empty
   string and a probe built on it measures nothing. `zmodload zsh/datetime` first. `analyze.sh`
   cross-checks the zsh clock against the mtime clock and says so when the value is missing.
3. **`cp` without `-p` rewrites mtimes**, which silently flattens every interval to zero. The
   timestamps here *are* mtimes, so `collect.sh` parses `analysis.txt` (written from the live
   directory) rather than trusting copied files.
4. **A hook that never ran is indistinguishable from one that measured zero.** Every hook drops
   marker files on entry, so absence is visible: `collect.sh` prints `INCOMPLETE` rather than a row
   of zeroes. Three turns during this measurement did fail to fire — the prompt was typed but not
   submitted — and were dropped, not scored.
5. **Snapshot inside the bracket.** `stop.sh` copies both buffers between `tread0`/`tread1` and
   hashes the copies. Hashing the live files after the bracket reads a *later* state than the one
   timed, which makes a stale read look fresh.

Also: this plugin installs a **user-scope** `MessageDisplay` hook (`rewrite.sh`). Left enabled it
fires inside the probe session, calls an LLM, and pollutes every interval. `CLAUDISH_ENABLED=0`.
