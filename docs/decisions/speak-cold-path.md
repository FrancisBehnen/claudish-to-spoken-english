# The cold path: what shipped, what was deferred, and what it rests on

The speech integration spec ([`speech-integration-spec.md`](speech-integration-spec.md))
specifies a lazy, self-electing, per-session **resident worker**. This branch ships
everything else and **forks a fresh speaker per turn instead**. This document is the whole
of the difference, so nobody has to diff a 4,800-line spec against the code to find it.

It is deliberately short. This project's failure mode is 4,800-line documents.

## What was built

| file | what it is |
| --- | --- |
| `speak.sh` | the `Stop` hook. §10.3's ordered steps, no `set` options, `exit 0` on every path. |
| `speak-key.sh` | `speak_key()` — `sha256( trim( text ) )`, **sourced by both hooks** so the handoff key has one definition. |
| `speak-child.py` | the detached speaker: claim, bounded wait, dedup, sanitize, split, synthesise, play. |
| `speech/` | `sanitize()` and `first_sentence()` / `split_sentences()`, moved out of `bench/` to the plugin root. |
| `rewrite.sh` | +13 lines: publish the rewrite to `speak/rw.<key>` by temp-write + rename, behind `CLAUDISH_SPEAK`. |
| `hooks/hooks.json` | a `Stop` block, `"timeout": 10`, no matcher. **No `SubagentStop` block** (§7). |
| `tests/` | a `Stop` payload fixture, a hook self-test, and the key fixture table. |

The shape: the hook gates, classifies, installs a job by rename, forks a detached child and
exits 0. The child does everything that can take time. Audio starts on **sentence one**;
synthesis of sentence N+1 overlaps playback of N.

## What was deferred, and what each deferral costs

| spec clause | deferred | why | known hazard |
| --- | --- | --- | --- |
| **§10.5** resident worker | entirely — no generation election, no `kqueue` wake, no `worker.lock.<gen>` / `worker.retiring.<gen>` records, no retirement protocol, no 20-minute idle exit | residency is a latency optimisation, and it is the direct cause of four of the spec's five ship-blocking defects (§13 rows 20, 21, 24, 27). What it would buy is now measured and small — **0.79 s of a 6.54 s `Stop` fire → audio path**, flat — against an LLM rewrite that dominates it and scales with answer length. See the measurement below. | ~340 MB of model load and a Python start **per turn** instead of once per session — measured in a live session at import 0.36–0.39 s + model load 0.43–0.54 s ≈ **0.79 s** of the child's own work. On a loaded machine that is where a slow turn comes from. |
| **§10.6** anchored player-record preemption | replaced by one lock directory + one owner record | `playerdir/`, the anchored `^[0-9]+\.[0-9a-f]{8}$` record names, the `.pending` markers and the generation prefix exist to coordinate *a worker and its players across generations*. There is one process here. | pid reuse. Mitigated: the owner record carries `<pid>` **and** `<lstart>`, and both must match before anything is signalled. Residual is `ps`'s one-second `lstart` resolution — the spec has the same residual and says so. |
| **§3.5.1** bounded wait lives in the worker | lives in the **detached child** | there is no worker. It must not live in the hook: §6's non-blocking guarantee is that the hook renames and exits. | none new. The hook's measured wall cost is unchanged (0.10–0.12 s, below). |
| **§10.5 clause 1** job claimed by rename to `job.taken.<pid>` | each hook installs `speak/job.<pid>` and hands that name to the child it forks | there is no shared worker to claim a shared `job`. Still a temp-write + rename, so still atomic. | a job whose child never starts is not picked up by anyone. It is reclaimed by `rewrite.sh:117`'s sweep. Same as the spec's "worker cannot start at all" row (§10.7): **lost, silently**. |
| **§10.7** synthesis watchdog (`TERM → sleep 2 → KILL`) | `CLAUDISH_SPEAK_TIMEOUT` bounds **cumulative synthesis, checked between sentences** | there is no separate synthesis process to signal — the child *is* the synthesiser — and `Kokoro.create()` spends its time inside onnxruntime, where a Python signal handler cannot land promptly. | a single pathological `create()` can overrun the budget. Bounded in practice by the sanitizer's 510-phoneme guarantee; audio already playing is never cut by the budget. |

Nothing else in the spec was skipped. Steps 0a–0b (the `CLAUDISH_ENABLED` derivation and the
global off-file), step 6's ordering (preemption before every content-based exit), the
content-addressed handoff, the eight-class hazard gate on the raw path, the `last_assistant_message`
source, the `LOCKED ABSENT` config rows and the `bash -n` gate are all implemented as written.

## The invariant this rests on, and what its failure sounds like

**At most one consumer per session.** §3.5.1 clause 5 ("at most one wait is ever outstanding")
and §5.1's lock-free dedup against `speak/spoken` both lean on the resident worker being the sole
consumer **by election**. There is no election here — every `Stop` forks a speaker — so the
invariant had to be rebuilt, and it is the top correctness risk in this branch.

It is held by two things:

1. **`speak.sh` step 6**, on every path below step 5, including the deliberately silent ones:
   read `speak/consumer/owner`, validate `<pid>` against the *current* `lstart` of that pid **and**
   against the command being one of ours, then `kill -TERM -<pid>` — the process group, so the
   player dies with the speaker.
2. **`speak-child.py`'s `claim()`**: `mkdir(2)` on `speak/consumer` is the claim — atomic, no
   symlink protocol needed. A live incumbent is TERMed, then KILLed after 1.5 s, and only then is
   its lock broken. A confirmed-dead or recycled-pid incumbent's lock is broken immediately. A
   lookup that *fails* is treated as neither: nothing is signalled and nothing is broken.

**If both miss, two speakers finish their waits and say the same turn over each other** — two
voices, seconds out of phase. That is what a broken claim sounds like, and `tests/speak-selftest.sh`
case 6 is the check.

It is not airtight, and these are the gaps:

- an incumbent that survives `SIGKILL` (uninterruptible sleep) holds the lock until the 5 s claim
  deadline, after which the newcomer **exits silently**. The turn is lost rather than doubled —
  the safe direction, and the same direction §3.2 chooses everywhere else.
- `lstart` has one-second resolution, so a pid recycled inside the same second reads as a match.
- a lock directory whose `owner` file never appears is broken after 1 s. A predecessor stalled
  for longer than that *between its `mkdir` and its `owner` write* would be double-consumed. The
  window is two syscalls wide and nothing has been seen in it.

## The measurement, with both endpoints named

Numbers with different endpoints are not comparable, and this project has been bitten by that
before — including in this very section. An earlier version of it read a **process start → wav
written** figure against `worker-residency.md`'s **hook fire → audio** median and concluded that the
cold path "clears the 3 s line". Different endpoints, invalid comparison; **the conclusion is
withdrawn**. Every row below names its endpoints, and no interval in this document is quoted without
them. Do not quote one elsewhere without them either.

| what | endpoints | value |
| --- | --- | --- |
| **this branch, offline** (`tests/speak-selftest.sh`) | `speak.sh` invoked → first `.wav` on disk | **2.08, 2.15, 2.31, 2.45, 2.46, 2.68 s** (n=6, buffered hit, `bf_emma`, `corpus/spoken/r03.txt`, page cache warm) |
| **this branch, hook wall cost** | `speak.sh` invoked → `speak.sh` returned | **0.10–0.12 s** |
| **this branch, child internals** | child `main()` entry → first `.wav` | 1.78–2.36 s: import 0.16–0.36, model load 0.33–0.53, first `create()` 1.28–1.50 |
| **this branch, mute latency** | `touch` the off-file → speaker and player both gone | **1.34–1.50 s**, with a 6 s sentence in flight |
| **this branch, live session** | `Stop` fires → **audio**, first ever measured on this branch | **6.54 s** (5-sentence answer) and **20.34 s** (23-sentence answer), n=2 |
| **the spec's cold figure** | hook fire → **audio**, no LLM anywhere in the path (`worker-residency.md`, n=7) | median **3.16 s**, range 2.66–5.50, **4 of 7 over the 3 s line** |
| **the spec's warm figure** | hook fire → audio, resident worker, no LLM in the path (n=30) | median **1.22 s**, 28/30 under 3 s |

The live rows are two turns logged on 2026-09-01 — the first numbers this branch has with the **same
endpoint pair** as the 3.16 s figure. They are read fork → audio, and the fork is the last thing the
hook does, so fork → audio and `Stop` fire → audio differ by the hook's 0.10–0.12 s wall cost and are
used interchangeably below.

**What the live turns decompose into, and what residency would actually buy.** Of turn A's 6.54 s
(`Stop` fire → audio), **4.3 s was the speaker waiting for `rewrite.sh`'s ollama call to publish**
(fork 09:11:00, publish 09:11:04) and **2.23 s was its own work** — import 0.364, model load 0.427,
first `create()` 1.440. Turn B splits ~14 s of wait against 5.26 s of its own work, on an ollama call
that ran ~20 s end to end for `rewrite_bytes=1185`. **The resident worker removes import and model
load and nothing else: 0.79 s of turn A's 6.54 s, and that term is flat.** It does **not** touch the
LLM rewrite, which is the dominant term and the only one that scales with answer length — ~4 s at
`rewrite_bytes=411`, ~20 s at 1185. So §10.5's payoff is bounded at **under a second on a
six-second path**, measured at the right endpoints rather than inferred from the deletion test, and
that is what the deferral now rests on. What the fork buys in return is unchanged: the cost is paid
**only on turns that actually speak**, by one process rather than a resident 340 MB one.

**Two turns is not a distribution.** n=2, one machine, one model, one session; these figures locate
the terms, they do not bound them. And they are not comparable to `worker-residency.md`'s 3.16 s
beyond sharing endpoints: that run had **no LLM in its path at all** — `speak.sh` did not exist yet
and the text came from the committed corpus — and its composition is not restated here. Nothing
above says this path beats or loses to that median. What today supports is the decomposition and the
bound on residency's share of it.

Three more things the live run settled:

- **The handoff key matches on real payload text.** `speak.sh` hashed `91ce22f1…` from
  `last_assistant_message`, `rewrite.sh` published `rw.91ce22f1…`, and the child logged
  `src=rw.91ce22f1`. `tests/speak-key-test.sh` only ever proved the two *implementations* agree on a
  fixture; this is the first evidence that the payload text `speak.sh` hashes is the text
  `rewrite.sh` saw.
- **Audio outruns the turn.** A five-sentence answer began playing 6.5 s after the turn ended and ran
  **36.02 s** — about **115 words per minute** against ~250 for silent reading, so listening takes
  roughly twice as long as reading. In normal use the previous turn is **still speaking** when the
  next one arrives. That is what makes step 6's preemption and the mute path load-bearing rather than
  polish; turn B was in fact muted mid-play.
- **The spool self-cleaned.** `speak/` was gone afterwards, including an orphaned publish from a
  pre-restart turn that no `Stop` hook ever consumed. No leaked wavs, no stale consumer claim.

## Manual test

```sh
# The hook, in isolation, without Claude Code. Real audio:
tests/speak-selftest.sh
# ...or silently, with a fake player:
tests/speak-selftest.sh -q
# ...or on your own text:
tests/speak-selftest.sh /path/to/some-rewrite.txt
```

Six cases: speech off leaves zero side effects; a buffered hit speaks and reports
hook-invocation-to-wav; a rewrite published 3 s *after* the hook is still heard (the bounded
wait); `touch`ing the off-file kills audio already sounding; a publish that never comes is silent
at the deadline; and a second turn during the first leaves exactly one speaker.

```sh
# The handoff key, cross-checked against python hashlib under BOTH shell regimes:
tests/speak-key-test.sh

# The raw hook against the committed fixture:
CLAUDISH_SPEAK=1 CLAUDISH_DEBUG=1 ./speak.sh < tests/stop-payload.json
tail "${TMPDIR:-/tmp}/claudish-to-english/debug.log"
```

## Running this branch in a live Claude Code session

The plugin is installed at user scope as `claudish-to-english@claudish-tts`, **pinned to commit
`446eefc`**, and the pin is what `${CLAUDE_PLUGIN_ROOT}` resolves to:
`~/.claude/plugins/cache/claudish-tts/claudish-to-english/0.3.0/`. `/plugin marketplace update`
would only re-pull `main`, so until this branch merges the way to run it is to point that one
path at a checkout of the branch. **Nothing here needs a network fetch beyond one `git fetch` of
a branch that is already pushed.**

```sh
# 1. Get the branch onto disk, without taking the branch away from any worktree.
cd ~/Code/claudish-to-spoken-english
git fetch origin task/speak-hook-cold-path
git worktree add /tmp/claudish-speech origin/task/speak-hook-cold-path   # detached HEAD

# 2. Point the plugin cache at it, keeping the pinned copy next to it.
CACHE="$HOME/.claude/plugins/cache/claudish-tts/claudish-to-english/0.3.0"
mv "$CACHE" "$CACHE.446eefc.bak"
ln -s /tmp/claudish-speech "$CACHE"

# 3. Turn speech on. In ~/.claude/settings.json, beside the existing
#    "CLAUDISH_MODEL": "qwen3:4b-instruct-2507-q4_K_M":
#      "CLAUDISH_SPEAK": "1"

# 4. Restart Claude Code. Hooks are read at session launch and CLAUDISH_* is
#    frozen there, so an already-running session will not pick either up.
```

Then ask it something that produces more than ~200 characters of prose. The answer appears, and it
is spoken once the rewrite's own LLM call has published — measured `Stop` fire → audio at 6.5 s for a
five-sentence answer and 20.3 s for a twenty-three-sentence one, so expect the wait to grow with the
answer. Expect the previous turn to still be talking when the next one lands. `touch
~/.claude/claudish-speak-off` silences it without stopping the on-screen rewrite.

To undo:

```sh
CACHE="$HOME/.claude/plugins/cache/claudish-tts/claudish-to-english/0.3.0"
rm "$CACHE" && mv "$CACHE.446eefc.bak" "$CACHE"
git -C ~/Code/claudish-to-spoken-english worktree remove /tmp/claudish-speech
```

Once this merges to `main` the permanent route is the normal one:
`/plugin marketplace update claudish-tts` then `/plugin update claudish-to-english@claudish-tts`.

If something is wrong, `CLAUDISH_DEBUG=1` and `tail -f
"${TMPDIR:-/tmp}/claudish-to-english/debug.log"` show every decision both hooks take. There is
deliberately no on-screen notice: a `Stop` hook cannot write to the screen.

To hear it for real in Claude Code, see also the **Speech** section of `README.md`.
