# Switching the rewrite provider to `claude-cli`: two traps, and what checking them settled

Evidence for [#14](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/14), follow-up
to [#12](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/12), part of the
[Kokoro speech map (#1)](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/1).
Checked 2026-08-25 against the source, this machine's settings, this machine's live environment, and
one two-item `capture-real-rewrites.sh` run. **No hook was modified.** `rewrite.sh`, `rewrite-md.sh`,
`providers.sh` and `hooks/hooks.json` are untouched by this work.

**Two claims were carried into this document from a hand session. Both were re-checked against the
source line by line, and neither survived unchanged. Trap 1's mechanism is confirmed — twice, by
reading the source and by a live run — but its consequence ("breaks every rewrite") rests on one
step nobody has measured. Trap 2 is confirmed in its *effect* and wrong in its *mechanism*, and that
correction is section 2's whole point.**

Everything here is a file read, a `printenv`, a checksum, a word count, a subprocess that made no
network request, or — for trap 1's mechanism only — a two-item `capture-real-rewrites.sh` run whose
resolved provider and model were observed. Nothing is inferred from how the plugin "probably" behaves
except where the text says so.

**#14's own call was still never made.** The ~1,300-word latency measurement was authorised and then
blocked by this machine's permission classifier; section 4 records the instrument, the input, and
what is still unknown. Trap 1 being confirmed live (section 1) settles the *provider/model
resolution* and says nothing about the latency curve — the two are not the same finding and are kept
apart on purpose.

## The source these line numbers refer to

The running plugin is the marketplace cache copy, **not** this checkout:

```
~/.claude/plugins/cache/claudish-tts/claudish-to-english/0.3.0/
```

The three files that matter are **byte-identical** to this checkout at `9355f45`, so every
`file:line` below is true of the code that actually fires on every message:

| file | sha256 (first 12) |
| --- | --- |
| `rewrite.sh` | `d84a85152674` |
| `providers.sh` | `753136e33f31` |
| `hooks/hooks.json` | `e4d9114b2dd9` |

---

## Verdict

| | trap | status |
| --- | --- | --- |
| **1** | `CLAUDISH_MODEL` travels with you across the provider switch, and the ollama model id reaches the Claude CLI verbatim | **pass-through confirmed in the source and observed live; that the CLI *rejects* the id, and so that every rewrite breaks, remains inference** |
| **2** | the timeout notice advises raising a knob that cannot usefully move | **effect confirmed; mechanism misdescribed** |
| **3** | neither variable can be changed mid-session | found while verifying the other two |

Trap 1's row is deliberately split in two. The mechanism — a set `CLAUDISH_MODEL` overriding
`providers.sh:92`'s `claude-cli` default and being handed to the CLI as `--model` at
`providers.sh:267` — is established twice over, by reading the source and by a live run that
confirms the resolution it predicts. What the CLI *does* with an ollama model id is a second claim,
and nobody has spent a call to see it. The trap is worth defusing on the first half alone; the
second half stays labelled all the way down (section 1's "Not verified" note, and item 2 of
"What was not verified").

---

## 1. The model variable travels with you — pass-through confirmed, the CLI's reaction still inferred

**`CLAUDISH_PROVIDER=claude-cli` alone is not the switch. It is half of it, and the other half is
mandatory, not advisable.**

### The chain, end to end

| step | location | what it does |
| --- | --- | --- |
| the value | `~/.claude/settings.json` → `env` | `CLAUDISH_MODEL = qwen3:4b-instruct-2507-q4_K_M` — **the only key in that block** |
| the provider | `providers.sh:61` | `PROVIDER="${CLAUDISH_PROVIDER:-ollama}"` |
| the model | `providers.sh:92` | `claude-cli) MODEL="${CLAUDISH_MODEL:-haiku}" ;;` |
| the call | `providers.sh:267` | `-p --model "$MODEL" --system-prompt "$_sys"` |

`providers.sh:92` is the line the hand session named, and it is that line, unmoved. The
`${CLAUDISH_MODEL:-haiku}` default only applies when the variable is **unset or empty**; a set value
wins for *every* provider branch (`providers.sh:88-93`). Nothing between line 92 and line 267
validates the string, maps it, or falls back — so the child process is spawned as

```
claude -p --model qwen3:4b-instruct-2507-q4_K_M --system-prompt ... --strict-mcp-config ...
```

### The state of this machine, checked rather than assumed

- `~/.claude/settings.json` `env` block: exactly one key, `CLAUDISH_MODEL`. **`CLAUDISH_PROVIDER` is
  not set there.**
- `printenv` in a live session: `CLAUDISH_MODEL=qwen3:4b-instruct-2507-q4_K_M` is present, and no
  other `CLAUDISH_*` variable is.
- No `CLAUDISH_*` in `~/.zshrc`, `~/.zshenv`, `~/.zprofile`, or `~/.claude/settings.local.json`.

So the trap is live: set `CLAUDISH_PROVIDER=claude-cli` and change nothing else, and the ollama model
id goes to the Claude CLI on every message.

### The mechanism, observed rather than only read (2026-08-25)

The source above predicts a specific resolution. A `corpus/bin/capture-real-rewrites.sh` run on
2026-08-25 produced exactly it, with the ollama id still live in the environment:

| | |
| --- | --- |
| environment during the run | `CLAUDISH_MODEL=qwen3:4b-instruct-2507-q4_K_M`, from the `env` block of `~/.claude/settings.json`, **unchanged** |
| what the script does about it | `export CLAUDISH_PROVIDER=claude-cli` then `unset CLAUDISH_MODEL`, both **before** `providers.sh` is sourced (`capture-real-rewrites.sh:39-40`, `:50`) |
| the banner it printed (`capture-real-rewrites.sh:59-60`) | `provider=claude-cli model=haiku` |
| the calls | two items, both **`rc=0`**, at **9s** and **8s** |

That is trap 1's fix demonstrated end to end rather than argued: the source-time `unset` is
sufficient, `providers.sh:92`'s `haiku` default takes over even with a machine-wide `CLAUDISH_MODEL`
set, and a real rewrite completes on that resolution — which means the whole `claude-cli` branch
(`providers.sh:240-288`, including `_llm_run_bounded` and the output capture) works when the model id
is right. Reading `providers.sh:92` and `:267` gives the same answer; this run is that answer
observed.

**Two things this run does not establish, stated here so the confirmation is not over-read:**

1. **Nothing about the latency curve.** Both items were corpus sources, and the corpus tops out at
   663 words (`corpus/source/r12.txt`); 9s and 8s land inside the 6–13s band `capture-log.tsv`
   already records. #14's question is what happens at ~1,300 words, and section 4 is still where
   that stands — unanswered. Confirming trap 1 and confirming flat latency are separate findings.
2. **Nothing about what the CLI does with the qwen id.** The run's whole design is that the id never
   reaches the child process. Observing the *fix* work cannot observe the *failure* it prevents.

### What the user would see

The failure is loud in the log and quiet on screen. `rewrite.sh`'s fail-open contract holds
(`rewrite.sh:22-24`, and the empty-rewrite branch at `rewrite.sh:199-232`): the original assistant
text stays on screen untouched, so **nothing is lost** — the rewrite simply never appears. Once per
session, `providers.sh:363-378`'s `claude-cli` branch appends one notice line. A non-zero CLI exit
with a message on stderr lands on `providers.sh:373-374`:

```
the claude CLI failed: <first non-empty line of stderr>
```

**Not verified, and marked as such:** that the `claude` CLI rejects an unknown `--model` id with a
non-zero exit and a message. Confirming it costs one CLI invocation and it was not spent on a
negative result. The pass-through at `providers.sh:267` is verified; the child's reaction to it is
inference. `corpus/bin/capture-real-rewrites.sh` (header, "Two traps this script exists to defuse")
records the same expectation, and unsets the variable for exactly this reason — which is the closest
thing to prior art the repo has.

### The switch, done correctly

Three shapes, in descending order of how well they survive switching back:

1. **Delete `CLAUDISH_MODEL` from the `env` block and let each provider pick its own default.**
   `providers.sh:88-93` already carries a sane default per provider — `haiku` for `claude-cli`,
   `gemma4:26b-mlx` for ollama. The variable exists to *override* those, and on this machine it is
   overriding the ollama one only because that machine-specific choice was written into a
   provider-agnostic variable. Setting `CLAUDISH_PROVIDER=claude-cli` then needs no second edit.
   The cost: switching back to ollama needs the qwen id put back, because
   `gemma4:26b-mlx` is not what is pulled here.
2. **Set both, together, and treat them as one setting.** `CLAUDISH_PROVIDER=claude-cli` **and**
   `CLAUDISH_MODEL=haiku`. Correct, and reversible in one place, but it silently breaks the ollama
   path the moment the provider is flipped back without also flipping the model.
3. **Per-session override, for a trial rather than a change of default.** Launch one session with
   both variables set in its environment and leave `settings.json` alone. This is what a measurement
   should use, and what `corpus/bin/capture-real-rewrites.sh` does: `export
   CLAUDISH_PROVIDER=claude-cli` then `unset CLAUDISH_MODEL`. It is also the shape that the
   2026-08-25 run above exercised, so this option is the one with observational backing.

**A `CLAUDISH_MODEL` set to the empty string also works** — `${CLAUDISH_MODEL:-haiku}` uses `:-`,
not `-`, so an empty value takes the default. That is a fact about the code, not a recommendation:
an empty string reads like a mistake, so prefer removing the key.

---

## 2. The timeout hint points at a knob that cannot usefully move — effect confirmed, mechanism corrected

### What the code says

| location | text |
| --- | --- |
| `rewrite.sh:65` | `LLM_TIMEOUT="${CLAUDISH_TIMEOUT:-45}"` |
| `rewrite.sh:211` | `TIMEOUT_HINT="raise CLAUDISH_TIMEOUT or set CLAUDISH_MODEL to a smaller model"` |
| `providers.sh:342, 357, 372` | `"the rewrite timed out after ${LLM_TIMEOUT}s — ${TIMEOUT_HINT:-raise the timeout}"` |
| `providers.sh:386` | the ollama variant, which also suggests a smaller model |
| `hooks/hooks.json:9` | `"timeout": 60` on the **`MessageDisplay`** hook — the one `rewrite.sh` serves |
| `hooks/hooks.json:21` | `"timeout": 180` on the **`PostToolUse`** hook — the one `rewrite-md.sh` serves |

The advice is therefore ineffective as a *sole* action: `CLAUDISH_TIMEOUT` bounds the LLM call, the
hook's own `timeout` bounds the process that makes it, and the second is 60. Raising
`CLAUDISH_TIMEOUT` from 45 to, say, 120 does not buy 120 seconds — the hook is killed at 60, and the
clean fail-open at `rewrite.sh:200` is replaced by a kill mid-flight. The usable ceiling is 60 minus
whatever the hook spends outside the LLM call (buffering, `jq`, transcript read), so the *effect* the
hand session described is real. **The hint is bad advice.**

### The mechanism is not what it was described as

The claim carried in was *"Claude Code caps hooks at 60s"*. **That is not what this 60 is.**

- The 60 is **this plugin's own declared value**, in this plugin's own `hooks/hooks.json`. It is a
  number the repo chose.
- **The same file declares 180 four lines later.** If the harness enforced a hard 60s ceiling on
  hooks, the `PostToolUse` entry could not be 180 — and `CLAUDISH_MD_TIMEOUT`'s 150s default
  (`rewrite-md.sh:67`) would have been dead on arrival since the day it was written. It was not.
- **Whether Claude Code enforces any absolute per-hook ceiling, and whether `MessageDisplay` is
  treated differently from `PostToolUse`, is NOT established here.** A `strings` search of the
  installed CLI binary (2.1.245) found no hook-timeout ceiling — every match was bundled test-runner
  text or self-hosted-runner code, unrelated. Establishing it would need either the published hook
  documentation or a deliberate experiment, and **neither is needed for the conclusion**: 60 is the
  live value either way.

So the correct statement of the trap is:

> `rewrite.sh:211` tells the user to raise `CLAUDISH_TIMEOUT` without mentioning that the plugin's
> own `MessageDisplay` hook timeout of 60s (`hooks/hooks.json:9`) is the real ceiling, and that
> moving it means editing a plugin file.

### It was not merely inferred — the repo already documents it

The 60s ceiling is written down in two places in the repo's own README, and both say the right thing:

- `README.md:457` — *"`CLAUDISH_TIMEOUT` | `45` | LLM client timeout for the **display** hook
  (seconds). Keep it below that hook's `timeout` (60s)."*
- `README.md:466-469` — the paragraph naming both hook timeouts, 60 and 180, and why the file hook is
  higher.

So the ceiling is documented; only **the notice** omits it. Which makes the actual defect an
asymmetry rather than a missing insight:

| hook | its hint | names the hooks.json ceiling? |
| --- | --- | --- |
| Markdown file (`rewrite-md.sh:197`) | *"raise `CLAUDISH_MD_TIMEOUT` (and the PostToolUse hook timeout in hooks.json), or set `CLAUDISH_MODEL` to a smaller model"* | **yes** |
| display (`rewrite.sh:211`) | *"raise `CLAUDISH_TIMEOUT` or set `CLAUDISH_MODEL` to a smaller model"* | **no** |

The file hook's hint already got this right. The display hook's did not, and it is the one users hit,
because it fires on every message.

### How far the fix a user can perform actually reaches

Raising the ceiling means editing `hooks/hooks.json` — a **plugin** file, not a user setting. For a
marketplace install that file is at
`~/.claude/plugins/cache/claudish-tts/claudish-to-english/0.3.0/hooks/hooks.json`, inside a
version-pinned cache directory that a plugin update replaces. So a hand edit there is real but
temporary, and it silently reverts on the next update. That is a further reason the hint should point
at **switching provider** — an env change the user owns — rather than at a timeout at all.

---

## 3. Neither variable can be changed mid-session

Found while verifying the above, and worth recording because it shapes how any switch is tested.

`CLAUDISH_*` variables come from the `env` block of `settings.json` (or the launching shell) and are
**frozen at session launch**. `rewrite.sh:58-60` says so in as many words, and it is why the plugin
carries a flag-file kill switch at all: `CLAUDISH_OFF_FILE` is checked fresh on every invocation
(`rewrite.sh:61`) precisely because the env cannot be.

Consequences:

- Editing `settings.json` mid-session changes nothing until the next session starts.
- `touch ~/.claude/claudish-off` **pauses** rewrites live, but cannot **reconfigure** them.
- A provider trial therefore means either a new session, or calling the provider layer directly out
  of band — which is what `corpus/bin/` does, and what section 4's script does.

---

## 4. The measurement: prepared, authorised, and blocked before it ran

**#14's open question is still open. The instrument exists; the call was not spent.**

Section 1's live run does not change that. It spent two calls on corpus-sized items and settled how
`PROVIDER` and `MODEL` resolve; the question here is a latency at ~1,300 words, which no run on this
machine has reached. Reading a confirmed trap 1 as a confirmed latency curve is the one misreading
this section exists to prevent.

The one call was authorised mid-session. `corpus/bin/time-one-rewrite.sh` was written for it, the
input was selected, and the path *up to the subprocess* was dry-run — and then the invocation was
refused by this machine's auto-mode permission classifier, on both attempts. The refusal is the
harness declining to
let an agent spawn a nested `claude` process, which is a guardrail against exactly the kind of
quota-spending this measurement is, so it was not worked around. **A human running the same command
by hand is not subject to it.**

### The command that is ready to run

```bash
bash corpus/bin/time-one-rewrite.sh <input.txt> <output.txt>
```

Its guard refuses to run at all when the output file already exists, and it **creates that file
before the call rather than after it** (`time-one-rewrite.sh`, just above the timed section). So a
second run is refused whichever way the first one ended — success, non-zero `rc`, empty rewrite, or a
watchdog kill. An earlier revision of this script only wrote the file on success, which left the
failure case — the one a human retries by reflex — unguarded; a retried latency measurement measures
the retry. Spending a second call is now a deliberate `rm` of the output file, and the script says so
on stderr when no rewrite lands.

### What was verified without spending the call

A dry run with `CLAUDISH_CLAUDE_BIN` pointed at a non-existent path exercises everything up to the
subprocess and stops there — no API request, no quota:

```
provider=claude-cli model=haiku timeout=120s input=1328w/8318c
1328	8318	127	0	0	0.04	0
```

Two things fall out of that line:

- **`model=haiku`, with `CLAUDISH_MODEL=qwen3:4b-instruct-2507-q4_K_M` live in the environment.**
  The source-time `unset CLAUDISH_MODEL` is sufficient and `providers.sh:92`'s default takes over —
  the same resolution the real run in section 1 later produced against a real call.
- **`rc=127`** is `providers.sh`'s "binary not on PATH" code. **It is set by the guard at
  `providers.sh:241-243`, which returns *before* the temp files are made and before
  `_llm_run_bounded` is called at all** — so this dry run says nothing about the bounded runner, the
  subprocess, or the output capture. What it does exercise is everything on either side of them:
  source-time provider/model resolution, the input measurement, the sub-second timer, the TSV line,
  and the `curl_rc = 127` notice branch at `providers.sh:365-366`.

**An earlier revision of this section claimed the 127 came "through the real `_llm_run_bounded`
path". It does not, and the correction matters:** a dry run whose whole point is to spend nothing
cannot validate the machinery that spends. `_llm_run_bounded` (`providers.sh:146-172`) is instead
covered by the real two-item run in section 1, which reached it with a working model id and returned
`rc=0` twice.

### The input that was selected, and why

| | |
| --- | --- |
| provenance | a real assistant message from this machine's transcripts, `subagents/agent-af1f27c6a64bc31d1`, uuid `b14a64f6-a2ca-40fb-9202-c231e43791cf`, 2026-08-04T02:16:53Z |
| size | **1,328 words**, 8,318 bytes |
| prose share | **100%** — zero fenced blocks, so `prose_len` = 6,855 |
| how found | `corpus/bin/extract-real-sources.sh` over `~/.claude/projects`, then ranked by word count |
| not generated | no model was asked to write it; it is a verbatim transcript message |

**It is not from this repo's own sessions, and that is not a free choice.** The longest real
assistant message in every claudish transcript on this machine — 410 messages across the project
directory and its scratchpad — is **770 words**. Nothing in this repo's own history reaches the
failing band at all, so a ~1,300-word real message has to come from another project. This one is an
engineering report (git commits, measurements, file paths); the alternative closest to 1,300 was a
1,299-word top-level message that is **52% fenced code**, which measures the wrong thing: the prompt
tells the model to leave fences unchanged, so half of that message would be copied, not rewritten.
The all-prose message is the harder and more honest test.

### What the number would have to beat, and what would not be comparable

`corpus/capture-log.tsv`, the 12 real rewrites, all on `claude-cli`/`haiku`:

| item | source words | output bytes | seconds |
| --- | ---: | ---: | ---: |
| `r01` | 40 | 270 | 7 |
| `r05` | **65** | 641 | 6 |
| `r08` | 136 | 788 | 9 |
| `r10` | 305 | 1576 | 10 |
| `r11` | 383 | 2387 | 13 |
| `r12` | **663** | 2933 | **13** |
| *the pending measurement* | **1328** | ? | **?** |

> **A correction to #14's copy of this table:** it lists `r05` at 96 source words. `corpus/source/r05.txt`
> is **65** words by both `wc -w` and Python's `split()`. Every other row in that table matches the
> files exactly. The slip does not change the shape of the curve.

The threshold that matters is **45s** (`CLAUDISH_TIMEOUT`'s default), and the hard wall behind it is
**60s** (section 2). `r12` at 663 words took 13s; the pending item is 2.0× that input.

Three things that would **not** be comparable, stated in advance so the number is not over-read:

1. **The ollama figure it is being set against is not a measurement in this table.** #14's
   ~1,200–1,400 word failure threshold is a *reported* observation on
   `qwen3:4b-instruct-2507-q4_K_M`, not a logged latency. This would be a claude-cli number next to
   an ollama anecdote: different provider, network round-trip versus local inference, and a hosted
   model versus a 4B local one.
2. **The 12 corpus rows were captured in one warm run** on 2026-08-15; a single call today carries
   whatever CLI start-up, auth and server-side conditions apply at that moment. `n=1` has no error
   bar.
3. **`LLM_TIMEOUT=120` is not the hook's budget.** The script uses 120 so that a slow result is a
   *number* rather than the word "timeout". Read the result against 45, not against 120.

### What it would settle

- **Comfortably under 45s** → the flat-latency extrapolation holds at 2× the largest prior
  measurement, and #14's failure is a **provider** problem, not a model-speed one.
- **Between 45s and 60s** → the curve is not flat; `claude-cli` would need `CLAUDISH_TIMEOUT` raised
  toward the ceiling, and section 2's ceiling becomes load-bearing rather than academic.
- **Over 60s, or a non-zero `rc`** → switching provider does not fix long messages, and the honest
  outcome is to let them fail open by design.

---

## What was not verified

Listed so nobody mistakes an unchecked thing for a checked one.

1. **The latency of a ~1,300-word rewrite on `claude-cli`** — #14's actual question. Section 4 has
   the script, the input and the thresholds; only the call is missing. The 2026-08-25 run in
   section 1 spent two calls but on corpus-sized items (≤663 words), so it moved this not at all.
2. **That `claude --model <ollama-id>` fails, and how.** Section 1's pass-through is verified twice
   over — in the source and in a live resolution — but the CLI's reaction to a bad id is still
   inference plus `capture-real-rewrites.sh`'s prior expectation. The live run cannot help here by
   construction: it works precisely because it unsets the variable, so the bad id never reaches the
   child.
3. **Whether Claude Code imposes any absolute hook-timeout ceiling**, and whether it differs by event
   type. Section 2 does not need it.
4. **The exact overhead between the 60s hook budget and the LLM call**, i.e. what `CLAUDISH_TIMEOUT`
   could safely be raised to if the ceiling *were* moved. Nobody has measured the hook's non-LLM
   time.
5. **The ollama failure itself.** The ~1,200–1,400 word threshold in #14 is #14's reported figure and
   was not reproduced here — reproducing it would mean deliberately timing out a local model, which
   costs a minute of GPU and proves a number already reported by the person who hit it.
