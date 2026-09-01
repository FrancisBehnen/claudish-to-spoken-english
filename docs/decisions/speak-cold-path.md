# The cold path: what shipped, what was deferred, and what it rests on

The speech integration spec ([`speech-integration-spec.md`](speech-integration-spec.md))
specifies a lazy, self-electing, per-session **resident worker**. This branch ships
everything else and **forks a fresh speaker per turn instead**. This document is the whole
of the difference, so nobody has to diff a 4,800-line spec against the code to find it.

It is deliberately short. This project's failure mode is 4,800-line documents.

## What was built

| file | what it is |
| --- | --- |
| `speak.sh` | the `Stop` hook. §10.3's steps — in §10.3's order except step 6, see the change table — no `set` options, `exit 0` on every path. |
| `speak-key.sh` | `speak_key()` — `sha256( trim( text ) )`, **sourced by both hooks** so the handoff key has one definition. |
| `speak-child.py` | the detached speaker: claim, bounded wait, dedup, sanitize, split, synthesise, play. |
| `speech/` | `sanitize()` and `first_sentence()` / `split_sentences()`, moved out of `bench/` to the plugin root. |
| `rewrite.sh` | one `publish_speech()` helper, called twice: with the rewrite above `CLAUDISH_MIN_CHARS`, with the **raw** text below it. Temp-write + rename, behind `CLAUDISH_SPEAK`, guarded so it cannot touch the fail-open path. |
| `hooks/hooks.json` | a `Stop` block, `"timeout": 10`, no matcher. **No `SubagentStop` block** (§7). |
| `tests/` | a `Stop` payload fixture, a hook self-test, and the key fixture table. |

The shape: the hook gates, classifies, installs a job by rename, forks a detached child and
exits 0. The child does everything that can take time. Audio starts on **sentence one**;
synthesis of sentence N+1 overlaps playback of N.

## What was deferred, and what each deferral costs

| spec clause | deferred | why | known hazard |
| --- | --- | --- | --- |
| **§10.5** resident worker | entirely — no generation election, no `kqueue` wake, no `worker.lock.<gen>` / `worker.retiring.<gen>` records, no retirement protocol, no 20-minute idle exit | residency is a latency optimisation, and it is the direct cause of four of the spec's five ship-blocking defects (§13 rows 20, 21, 24, 27). Cold is fast enough — see the measurement below. | ~340 MB of model load and a Python start **per turn** instead of once per session. On a loaded machine that is where a slow turn comes from. |
| **§10.6** anchored player-record preemption | replaced by one lock directory + one owner record | `playerdir/`, the anchored `^[0-9]+\.[0-9a-f]{8}$` record names, the `.pending` markers and the generation prefix exist to coordinate *a worker and its players across generations*. There is one process here. | pid reuse. Mitigated: the owner record carries `<pid>` **and** `<lstart>`, and both must match before anything is signalled. Residual is `ps`'s one-second `lstart` resolution — the spec has the same residual and says so. |
| **§3.5.1** bounded wait lives in the worker | lives in the **detached child** | there is no worker. It must not live in the hook: §6's non-blocking guarantee is that the hook renames and exits. | none new. The hook's measured wall cost is unchanged (0.10–0.12 s, below). |
| **§10.5 clause 1** job claimed by rename to `job.taken.<pid>` | each hook installs `speak/job.<pid>` and hands that name to the child it forks | there is no shared worker to claim a shared `job`. Still a temp-write + rename, so still atomic. | a job whose child never starts is not picked up by anyone. It is reclaimed by `rewrite.sh:117`'s sweep. Same as the spec's "worker cannot start at all" row (§10.7): **lost, silently**. |
| **§10.7** synthesis watchdog (`TERM → sleep 2 → KILL`) | `CLAUDISH_SPEAK_TIMEOUT` bounds **cumulative synthesis, checked between sentences** | there is no separate synthesis process to signal — the child *is* the synthesiser — and `Kokoro.create()` spends its time inside onnxruntime, where a Python signal handler cannot land promptly. | a single pathological `create()` can overrun the budget. Bounded in practice by the sanitizer's 510-phoneme guarantee; audio already playing is never cut by the budget. |

Nothing else in the spec was skipped, but **two things were later changed on purpose** and are
recorded in the next section rather than here: step 6's *ordering*, and §3.3/§3.4/§3.5's length
floor together with the hazard gate that hung off it. Steps 0a–0b (the `CLAUDISH_ENABLED`
derivation and the global off-file), the content-addressed handoff, the `last_assistant_message`
source, the `LOCKED ABSENT` config rows and the `bash -n` gate are all implemented as written.

## What was changed after the spec, and on whose authority

| spec clause | change | why | what it costs |
| --- | --- | --- | --- |
| **§10.3 step 6** preemption runs above every content-based exit | it now runs **below** the content gates (step 8's background task, step 9's absent message) and above the fork | the spec's reasoning — *a deliberately silent turn must still cut the previous turn's audio* — was observed wrong in a live log. A long answer was playing, the user asked a one-line question, the reply never reached synthesis, and the previous answer was cut off mid-sentence **with nothing in its place**. Two turns in one log would have done it (`prose_len` 53 and 54). Silence where speech was is a lost utterance, not a barge-in. | a turn that is silent by design no longer stops the previous one — which is the point. Everything still below the kill is *failure* rather than designed silence (unreadable `speak-key.sh`, unwritable job, missing venv), and those still preempt, because that turn was going to speak. `tests/speak-selftest.sh` cases 7 and 8 are the check. |
| **§3.3**, **§3.4**, and three of **§3.5**'s four rows — the sub-threshold raw path, its eight-class hazard gate, and "below `MIN_CHARS` the wait must never run" | **removed.** Speech has no length floor of its own. `rewrite.sh` publishes on its short path too, carrying the **raw** text under the same key, and `speak.sh` reads `CLAUDISH_MIN_CHARS` on no path at all | **the user's decision, 2026-09-01**: the rewrite already decides what is worth rewriting, so a second floor underneath it only starved short answers. §3.3's premise 2 — *"below the threshold there is no rewrite to hand over"* — is what the floor rested on, and it is now false. | **§3.4 is LOCKED and this drops it.** Short text carrying a disqualifying class (a path, a URL, a fence) is now spoken, sanitized — so a path loses its leading segments and a fence becomes *"Code block, N lines."* What makes that tolerable is §3.4's own measurement, and it measures a **no-op** rather than a benefit: of #10's sixteen real sub-threshold items, **zero** carried a disqualifying class. It also widens nothing about §3.2's repeated-text collision that was not already there, but it does make it easier to reach — two identical short answers (*"Yes."*) hash to one key. |

## The invariant this rests on, and what its failure sounds like

**At most one consumer per session.** §3.5.1 clause 5 ("at most one wait is ever outstanding")
and §5.1's lock-free dedup against `speak/spoken` both lean on the resident worker being the sole
consumer **by election**. There is no election here — every `Stop` forks a speaker — so the
invariant had to be rebuilt, and it is the top correctness risk in this branch.

It is held by two things:

1. **`speak.sh` step 6**, on every path that goes on to fork a speaker — **not** on the
   deliberately silent ones any more, see the change table above: read `speak/consumer/owner`,
   validate `<pid>` against the *current* `lstart` of that pid **and** against the command being
   one of ours, then `kill -TERM -<pid>` — the process group, so the player dies with the speaker.
2. **`speak-child.py`'s `claim()`**: `mkdir(2)` on `speak/consumer` is the claim — atomic, no
   symlink protocol needed. A live incumbent is TERMed, then KILLed after 1.5 s, and only then is
   its lock broken. A confirmed-dead or recycled-pid incumbent's lock is broken immediately. A
   lookup that *fails* is treated as neither: nothing is signalled and nothing is broken.

**If both miss, two speakers finish their waits and say the same turn over each other** — two
voices, seconds out of phase. That is what a broken claim sounds like, and `tests/speak-selftest.sh`
cases 6 and 8 are the check — 6 counts the speakers, 8 names them, because "one speaker" is also
what a newcomer that never started looks like.

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
before. So:

| what | endpoints | value |
| --- | --- | --- |
| **this branch, measured here** | `speak.sh` invoked → first `.wav` on disk | **2.08, 2.15, 2.31, 2.45, 2.46, 2.68 s** (n=6, buffered hit, `bf_emma`, `corpus/spoken/r03.txt`, page cache warm) |
| **this branch, hook wall cost** | `speak.sh` invoked → `speak.sh` returned | **0.10–0.12 s** |
| **this branch, child internals** | child `main()` entry → first `.wav` | 1.78–2.36 s: import 0.16–0.36, model load 0.33–0.53, first `create()` 1.28–1.50 |
| **this branch, mute latency** | `touch` the off-file → speaker and player both gone | **1.34–1.50 s**, with a 6 s sentence in flight |
| **the spec's cold figure** | hook fire → **audio** (`worker-residency.md`, n=7) | median **3.16 s**, range 2.66–5.50, **4 of 7 over the 3 s line** |
| **the spec's warm figure** | hook fire → audio, resident worker (n=30) | median **1.22 s**, 28/30 under 3 s |

**Read the first row against the fourth carefully.** They are close but they are *not* the same
quantity: this branch's number ends at the wav existing, the spec's ends at audio — the player
spawn (15–20 ms, per `bench/bench.py`) and afplay's own start sit between them. So the honest
statement is that the cold path here lands **just under** the spec's cold median, on a machine
with the model warm in the page cache and without three other Claude Code sessions running.
It does **not** refute the spec's 4-of-7 finding: the same measurement under the same load would
likely straddle the line the same way. The 3 s line is a target and it is porous in both
directions — the spec's *warm* path missed it twice in thirty, both times on a loaded machine.

What this branch buys against residency is that the cold cost is paid **only on turns that
actually speak**, and it is bounded by one process rather than a resident 340 MB one.

## Manual test

```sh
# The hook, in isolation, without Claude Code. Real audio:
tests/speak-selftest.sh
# ...or silently, with a fake player:
tests/speak-selftest.sh -q
# ...or on your own text:
tests/speak-selftest.sh /path/to/some-rewrite.txt
```

Nine cases: speech off leaves zero side effects; a buffered hit speaks and reports
hook-invocation-to-wav; a rewrite published 3 s *after* the hook is still heard (the bounded
wait); `touch`ing the off-file kills audio already sounding; a publish that never comes is silent
at the deadline; a second turn during the first leaves exactly one speaker; a turn that exits at a
content gate leaves the live speaker **alone**; a turn that speaks preempts it and the survivor is
the **new** speaker; and a message well under `CLAUDISH_MIN_CHARS` is published by `rewrite.sh` and
spoken — the case that used to be silent. `-q` swaps the real player for a fake one: synthesis
still runs for real, only playback is faked.

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

Then ask it anything. Above ~200 characters of prose the answer appears and, a few seconds later —
after the rewrite's own LLM call — the *rewrite* is spoken. Below it there is no rewrite and no
floor either: the raw answer is spoken, and it starts sooner because nothing waited on an LLM.
`touch ~/.claude/claudish-speak-off` silences both without stopping the on-screen rewrite.

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
