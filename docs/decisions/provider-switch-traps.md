# Switching the rewrite provider to `claude-cli`: two traps, and what checking them settled

Evidence for [#14](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/14), follow-up
to [#12](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/12), part of the
[Kokoro speech map (#1)](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/1).
Checked 2026-08-25 against the source, this machine's settings, this machine's live environment, one
two-item `capture-real-rewrites.sh` run, one one-item `time-one-rewrite.sh` run, and — for section 5 —
two logs that already existed on disk. **No hook was modified.** `rewrite.sh`, `rewrite-md.sh`,
`providers.sh` and `hooks/hooks.json` are untouched by this work.

**Two claims were carried into this document from a hand session. Both were re-checked against the
source line by line, and neither survived unchanged. Trap 1's mechanism is confirmed — twice, by
reading the source and by a live run — but its consequence ("breaks every rewrite") rests on one
step nobody has measured. Trap 2 is confirmed in its *effect* and wrong in its *mechanism*, and that
correction is section 2's whole point.**

Everything here is a file read, a `printenv`, a checksum, a word count, a subprocess that made no
network request, a timestamp read out of a log, or — for trap 1's mechanism and section 4's latency —
a run that spent real calls and whose resolved provider and model were observed. Nothing is inferred
from how the plugin "probably" behaves except where the text says so.

**#14's own call has since been made, and its provider has since been verified.** The ~1,300-word
latency measurement was authorised, refused twice by this machine's permission classifier, and then
run: **2026-08-25, 15:25 CEST, 52.50s, `rc=0`, 6,094 bytes out**. Section 4 records it. *Which
provider served it* was not established at the time, was posted publicly on #14 as an open caveat,
and is settled in section 5 — from logs, with no second call. Trap 1 being confirmed live (section 1)
settles the *provider/model resolution* and says nothing about the latency curve — the two are not
the same finding and are kept apart on purpose.

> **UPDATE, 2026-09-01 — #14 was implemented, and three of this document's open items are now
> closed.** `claude-cli` is the DEFAULT provider, the display pair went 45/60 → 120/120, and the
> `speak.sh` constant that tracks `hooks.json` moved with it. Everything above is preserved as the
> 2026-08-25 snapshot it was, **including the sentence that says no hook was modified — that was true
> when written and is no longer true of the repo.** Section 7 below records what changed, which
> unverified items it settled, and which of this document's own conclusions it overturns. Read the
> line numbers above as historical: `rewrite.sh:65` is now `:72`, `rewrite.sh:211` is now `:271`,
> `providers.sh:61` is now `:79`, `providers.sh:92` is now `:110`.

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

Two further findings sit outside the trap list, in sections 4 and 5: **the ~1,300-word latency is
52.50s**, over the 45s `CLAUDISH_TIMEOUT` default; and **the binary that served that measurement is
confirmed to be the `claude` CLI and not ollama**, from logs, after the figure was published with
that question open.

Those two are not one finding, and section 5 keeps them apart on purpose. The **provider is
observed**. The **model is not**: `haiku` is what `providers.sh:92` resolves to once
`CLAUDISH_MODEL` is unset and what `providers.sh:267` passes as `--model`, both read from the
source — **no record read here names the model that produced the text**. Wherever this document puts
`claude-cli` and `haiku` together, the first half is observed and the second is the argument the
script demonstrably builds.

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

## 4. The measurement: blocked twice, then spent — 1,328 words in 52.50s

**#14's open question is answered. The call was spent on 2026-08-25 and the number is 52.50s.**

> **This section used to be titled "prepared, authorised, and blocked before it ran", and everything
> below "The result" was written while that was true.** It stopped being true at 15:25 CEST on
> 2026-08-25. The prepared-but-unspent material is kept rather than rewritten around the answer: the
> input selection, the thresholds and the three non-comparabilities were all fixed *before* the
> number existed, which is the only reason the number can be read at face value.

### The result

| | |
| --- | --- |
| when | **2026-08-25, 15:25:22.3 → 15:26:14.8 CEST** |
| banner it printed | `provider=claude-cli model=haiku timeout=120s input=1328w/8318c` |
| TSV line it printed | `1328  8318  0  0  0  52.50  6094` |
| read as | 1,328 words / 8,318 bytes in; `rc=0`; not rate-limited; not truncated; **52.50s**; 6,094 bytes out |

Against the thresholds this section fixed in advance: **over the 45s `CLAUDISH_TIMEOUT` default, and
inside the 60s `MessageDisplay` ceiling by 7.5s.** It completed only because `time-one-rewrite.sh`
runs on a 120s budget; under the real display-hook config `_llm_run_bounded` would have killed it at
45s and the user would have seen the original message plus the setup notice.

**Which provider actually served it was not established at the time** — the banner reports the
script's own resolved variables, not what `llm_complete` dispatched on. That gap was posted publicly
as a caveat on #14 rather than glossed, and section 5 closes it.

Section 1's live run did not settle the latency and was never claimed to. It spent two calls on
corpus-sized items and settled how `PROVIDER` and `MODEL` resolve; this is a latency at ~1,300 words.
Reading a confirmed trap 1 as a confirmed latency curve is the one misreading this section exists to
prevent.

The call was authorised mid-session, and the first two attempts to make it were refused by this
machine's auto-mode permission classifier — the harness declining to let an agent spawn a nested
`claude` process, which is a guardrail against exactly the kind of quota-spending this measurement
is. It was not worked around. A later attempt in the same session was allowed and is the run above.
**A human running the same command by hand is not subject to the classifier at all.**

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

`corpus/capture-log.tsv`, the 12 real rewrites, all on `claude-cli` (confirmed in section 5) at the
`haiku` that `providers.sh:92` resolves (read from the source, not from any response):

| item | source words | output bytes | seconds |
| --- | ---: | ---: | ---: |
| `r01` | 40 | 270 | 7 |
| `r05` | **65** | 641 | 6 |
| `r08` | 136 | 788 | 9 |
| `r10` | 305 | 1576 | 10 |
| `r11` | 383 | 2387 | 13 |
| `r12` | **663** | 2933 | **13** |
| *the measurement, once spent* | **1328** | **6094** | **52.50** |

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

### What it would settle — and which branch it took

- **Comfortably under 45s** → the flat-latency extrapolation holds at 2× the largest prior
  measurement, and #14's failure is a **provider** problem, not a model-speed one.
- ✅ **Between 45s and 60s** → the curve is not flat; `claude-cli` would need `CLAUDISH_TIMEOUT`
  raised toward the ceiling, and section 2's ceiling becomes load-bearing rather than academic.
  **This is the branch that happened, at 52.50s.**
- **Over 60s, or a non-zero `rc`** → switching provider does not fix long messages, and the honest
  outcome is to let them fail open by design.

The middle branch is not a licence to raise `CLAUDISH_TIMEOUT` and move on. 52.50s clears 60s by
7.5s on a single sample, with no error bar (non-comparability 2 above), and the 60 behind it is not a
knob the user owns: it is **this plugin's own declared `MessageDisplay` timeout**
(`hooks/hooks.json:9`), so moving it means editing a plugin file inside a version-pinned cache
directory that the next update replaces — section 2. Whether the harness would honour a larger value
there is a separate question, and **unestablished** ("What was not verified", item 3). A knob whose
whole remaining range is 7.5 seconds wide is not a fix.

---

## 5. Which provider actually served the measurement — settled from logs, no second call

**Verified after the fact, from two record sets that already existed on this machine. It was the
`claude` CLI. It was not ollama. The caveat on #14 is resolved.**

Section 4's banner said `provider=claude-cli model=haiku`, but that is `time-one-rewrite.sh` reading
back its own resolved variables — the shell state, not the dispatch. The caveat posted as
[`issuecomment-5411419480`](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/14#issuecomment-5411419480)
said exactly that, and named a real reason to doubt: **52.50s for 8,205 characters is slow for
`haiku` and entirely ordinary for a local `qwen3:4b-instruct-2507-q4_K_M`**, which `ollama ps` showed
resident on the GPU right after the run. The doubt was reasonable. It was also wrong, and the same
log that refutes it also explains the residency that raised it.

### The window, fixed to the second

| | |
| --- | --- |
| the timed section began | **2026-08-25 15:25:22.3 CEST** (= `13:25:22.3Z`) |
| it ended | **2026-08-25 15:26:14.8 CEST** (= `13:26:14.849Z`, when the result landed) |
| how that is known | the transcript of the session that ran it, `~/.claude/projects/-Users-francis-behnen-Code-claudish-to-spoken-english/07b120e5-b990-47eb-aa3d-28e522236473.jsonl`: the `tool_use` at `2026-08-25T13:25:20.259Z`, and the `tool_result` at `2026-08-25T13:26:14.849Z` carrying the TSV line. Start = end − 52.50s. |

### Evidence 1 — ollama had no model loaded during that window (read from a log)

ollama here is the brew build (`~/homebrew/opt/ollama/bin/ollama serve`, running since 11:47) and its
stdout goes to **`~/homebrew/var/log/ollama.log`**. It logs every HTTP request it answers, with a
timestamp and a duration. Read, not inferred:

- The file is a single continuous append log from 2026-08-15 11:42:56 to 2026-08-25 15:55:56 — no
  rotation, no truncation — and holds 76 request lines for 2026-08-25, running from 10:42:33 to
  15:55:56. Between **15:10:02** and **15:26:44** there is **not one request of any kind**. The
  measurement window sits entirely inside that silence.
- Stronger than silence: at **15:26:44.678** the log shows `starting llama-server`, then
  `llama-server started in 4.29 seconds`. The model was loaded **cold**. It had been evicted by the
  5-minute idle timer some time after the 15:10:02 request, so **no model was resident at
  15:25:22–15:26:14** and ollama could not have produced 6,094 bytes, or anything else.
- No request on 2026-08-25 has a duration near 52.50s. The three longest are 45.29s, 45.23s and
  45.08s — all **HTTP 500**, which is the display hook's own `CLAUDISH_TIMEOUT=45` cutting ollama off.

**The residency that made the caveat suspicious comes from the same log, 29 seconds too late.** The
cold load at 15:26:44 serves a request logged at 15:27:08 whose prompt is **610 tokens** — the
`MessageDisplay` hook rewriting the assistant message that *reported* the measurement. The 1,328-word
input is roughly 2,000 tokens, and the log records **no prompt of any size** in the measurement
window — the last one before it is at 15:10:02 and the next at 15:26:44 (610 tokens). Prompts that
big do appear in the log on other days and earlier that morning, so this is an argument from the
window, not from the sizes.

### Evidence 2 — a `claude` process started one second into the call (read from disk)

The CLI creates a directory under **`~/.claude/session-env/`** named for its session id when it
starts, `-p` mode included. Birth times via `stat -f '%SB'`:

| directory | created |
| --- | --- |
| `d2186a88-f281-4acd-97d1-5d9d352e9e69` | **2026-08-25 15:25:23** |

It is the **only** one created between 15:20 and 15:30; it lands one second after `llm_complete`
began; and **no transcript exists for that session id** anywhere under `~/.claude/projects/`, which
is precisely what `-p --no-session-persistence` (`providers.sh:266-268`) leaves behind. A `claude`
process started inside the measurement and left no session file.

### The same records clear the 6–13s corpus band as well

The caveat noted that `capture-real-rewrites.sh` resolves the provider the same way, so the corpus
band inherits the doubt. It does not survive either.

- **`r01`–`r12`, captured 2026-08-15.** `~/.claude/session-env/` holds **twelve** directories created
  between **15:32:58** and **15:34:50** — one `claude` start per corpus item. Twelve starts give
  **eleven** inter-start gaps (16, 8, 12, 9, 7, 9, 10, 10, 8, 10, 13 s), so only eleven of
  `capture-log.tsv`'s twelve per-item seconds (7, 8, 13, 9, 6, 10, 10, 9, 8, 10, 13, 13) can be
  checked against a gap at all: **ten of those eleven match within a second**. The first gap is 9s
  longer than `r01`'s 7s, and **what those 9 seconds went to is not observable from these
  timestamps** — nothing in the record attributes them. `r12`'s 13s has no following start, so it is
  unchecked. On that whole day **every** `POST /api/chat` to ollama returned **HTTP 404 in under
  30 ms** — the model had not been pulled yet, and ollama served **zero** completions on 2026-08-15.
- **`r13`, `r14`, captured 2026-08-25.** Two more session-env directories at **13:45:08** and
  **13:45:17** — 9 seconds apart, matching `capture-log.tsv`'s `r13 = 9s`. ollama's log has nothing
  between 13:41:50 and 13:45:36.

### Observed, and inferred, kept apart

- **Observed.** ollama answered no request during the measurement and had no model loaded. A `claude`
  process started 1s into it and persisted no session. The fourteen corpus items carry the same
  signature. `time-one-rewrite.sh:54-55` sets `CLAUDISH_PROVIDER=claude-cli` and unsets
  `CLAUDISH_MODEL` before `providers.sh` is sourced, and the `claude-cli` branch
  (`providers.sh:240-288`) is the only branch that can be reached from that state — it makes no HTTP
  call of its own.
- **Inferred, strongly.** That the `claude` process reached **Anthropic's API** with `--model haiku`.
  No endpoint override exists on this machine: `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`,
  `ANTHROPIC_API_KEY`, `apiKeyHelper` and the Bedrock/Vertex switches are all absent from
  `~/.claude/settings.json`, `~/.claude/settings.local.json`, `~/.claude.json`, `~/.zshrc`,
  `~/.zshenv`, `~/.zprofile` and this repo's `.claude/settings.local.json`; `claude` resolves to the
  official binary at `~/.local/share/claude/versions/2.1.245`; and the only local inference server on
  the box is the ollama that the log just cleared.
- **Not observed.** **No record read here names the model that generated the text.** No network
  capture was taken, the CLI writes no per-call log, and `~/.claude/telemetry/` holds only a stale
  failed-event spool (newest entry 08:24 that day). The model name rests on the `--model haiku`
  argument that `providers.sh:267` demonstrably builds, not on a response.

### What this does to #14's conclusion

The caveat hedged that the ticket's conclusion was "unaffected either way", because if ollama had
served the call then `claude-cli` was simply never measured. **That disjunction is void: `claude-cli`
*was* measured.** Testing the position rather than repeating it, it holds — and on firmer ground than
the hedge allowed:

- **1,328 words takes 52.50s on the `claude` CLI** — the binary is observed above; the `haiku`
  behind it is the `--model` argument `providers.sh:267` builds, not a model named by any record.
  52.50s is over the 45s `CLAUDISH_TIMEOUT` default, so under the real display-hook config the
  watchdog kills that rewrite. Switching provider therefore **does not** fix long-message timeouts;
  it trades ollama's refusal for a client-side timeout, which is the harder of the two to diagnose.
- **Latency is not flat**, and that reading now stands on fourteen corpus measurements plus one long
  one that are *all* confirmed to have run on `claude-cli`, rather than on a band of unknown
  provenance.
- The one thing that would have changed had ollama served it — "then `claude-cli` was never measured
  at all, and #14's premise is untested" — is no longer available as a reading.

### The live re-run rig: armed, and deliberately not fired

A re-run was prepared before the logs settled the question, and is left armed because it would prove
the model name (the one thing above that is still inference) rather than the binary. **It has not
been run: it would spend a second subscription call, and the standing rule in this repo is that no
bench or corpus tool calls an LLM without explicit authorisation.**

- **`~/.local/share/claudish-probe-bin/claude`** — a wrapper reached only via `CLAUDISH_CLAUDE_BIN`
  (`providers.sh:68`), never on `PATH`. It logs `argv`, the `--model` flag, stdin byte count, wall
  time and the resolved real binary, then runs the real `claude`. It resolves that binary by scanning
  `PATH` and skipping any candidate whose resolved **device:inode** equals its own, so it cannot
  recurse; it forwards `TERM`/`INT` so `_llm_run_bounded`'s watchdog still lands on the CLI; and it
  `tee`s stdin so the child still sees a pipe. Self-tested with `--version` only — no LLM call.
- The input is re-extracted to a scratchpad path and verified at **1,328 words / 8,205 characters /
  8,318 bytes / 0 fences**, byte-identical to the original run's banner. **It is not committed: it is
  borrowed from an unrelated project's transcript and this repo is public.**
- `time-one-rewrite.sh`'s spend guard refuses to run while the output file exists, so firing it means
  a deliberate `rm` of that path first.

---

## What was not verified

Listed so nobody mistakes an unchecked thing for a checked one.

1. ~~**The latency of a ~1,300-word rewrite on `claude-cli`** — #14's actual question. Section 4 has
   the script, the input and the thresholds; only the call is missing.~~ **Measured on 2026-08-25:
   52.50s (section 4), on a provider confirmed in section 5.** What remains unverified is the *shape*
   of the curve between 663 and 1,328 words: two points do not distinguish a knee from a slope, and
   `n=1` at the top end has no error bar. Nobody should read 52.50s as a constant.
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

---

## 7. What #14's implementation changed, and what that settled

**Added 2026-09-01**, when #14 was implemented rather than analysed. Everything above this line is
the 2026-08-25 snapshot and is left alone; this section is the delta.

### What changed in the repo

| file | before | after |
| --- | --- | --- |
| `providers.sh:79` | `PROVIDER="${CLAUDISH_PROVIDER:-ollama}"` | `...:-claude-cli}"` |
| `providers.sh:129-135` | *(did not exist)* | `MODEL_IGNORED` — the trap-1 guard |
| `rewrite.sh:72` | `LLM_TIMEOUT="${CLAUDISH_TIMEOUT:-45}"` | `...:-120}"` |
| `rewrite.sh:271` | *"raise `CLAUDISH_TIMEOUT` or set `CLAUDISH_MODEL` to a smaller model"* | *"switch `CLAUDISH_PROVIDER`, or raise `CLAUDISH_TIMEOUT` **and** the MessageDisplay hook timeout in hooks.json, or set `CLAUDISH_MODEL` to a faster model"* |
| `hooks/hooks.json:9` | `"timeout": 60` | `"timeout": 120` |
| `speak.sh:283` | `MD_TIMEOUT=60` | `MD_TIMEOUT=120` |

**The reason the change is worth making is NOT the reason #14 gives.** #14's body argued that
`claude-cli` latency is flat and so clears the long-message timeout; section 4 above measured that
and **refuted it** (52.50 s at 1,328 words), and #14's own recommendation was *"close as refuted"*.
That refutation stands and nothing here disturbs it. The change ships on a **different and
independently reported** problem: with several concurrent Claude Code sessions, ollama serves
requests **serially** (`llama-server … -np 1`, `OLLAMA_NUM_PARALLEL` unset), so the sessions queue
behind one another — 8 × `curl_rc=28` against 10 successful rewrites in 30 minutes on four sessions.
`docs/research/ollama-concurrency.md` says why parallelising ollama is not the fix. **Concurrency is
a queueing problem, not a latency-curve problem**, and `claude-cli` fixes it by not having the queue.
The 45 → 120 timeout raise is what carries the *long-message* case, and it would have been the right
fix on ollama too; it needed the hook timeout raised with it to be anything but inert.

### Item 2 — "that `claude --model <ollama-id>` fails, and how" — SETTLED, and then guarded

Run 2026-09-01, one call, no rewrite produced:

```
$ printf 'Say OK.' | claude -p --model 'qwen3:4b-instruct-2507-q4_K_M' \
    --strict-mcp-config --no-session-persistence --output-format text
rc=1
stdout: There's an issue with the selected model (qwen3:4b-instruct-2507-q4_K_M). It may not
        exist or you may not have access to it. Run --model to pick a different model.
stderr: "qwen3:4b-instruct-2507-q4_K_M" is not a model this version of Claude Code
        recognizes, so auto-compact will keep this session within 200k tokens ...
        [claude-code:unrecognized_model] {"model":"qwen3:4b-instruct-2507-q4_K_M",...}
```

**Trap 1's consequence is confirmed: "breaks every rewrite" is exact** **[obs]**. Three details the
inference did not predict:

1. **It fails FAST and spends nothing.** No generation happens, so a machine left in this state
   burns no quota — it just never rewrites anything.
2. **The real message is on `stdout`, and the useless one is on `stderr`.** `providers.sh` prefers
   `stderr` for diagnostics on a failed run (deliberately — on a failure stdout is not a rewrite),
   so the once-per-session notice would have read *"the claude CLI failed: "qwen3:…" is not a model
   this version of Claude Code recognizes, so auto-compact will keep this session within 200k
   tokens"* — a first line about auto-compact, not about the model. Diagnosable, but badly.
3. So the notice machinery does **not** make this trap safe enough to leave armed once `claude-cli`
   is the **default**. Section 1 above judged the trap acceptable, and it was — for an **opt-in**
   provider, where the user typed the switch and could be told to unset the variable in the same
   breath. **Nobody opts into a default.**

`providers.sh:129-135` therefore ignores a `CLAUDISH_MODEL` that cannot possibly be a Claude model.
The test is narrow on purpose: `name:tag` **and** no `claude`/`anthropic`/`haiku`/`sonnet`/`opus`
anywhere in the string. A bare colon would not do — Bedrock and Vertex ids carry one
(`us.anthropic.claude-haiku-4-5-20251001-v1:0`) and `claude-cli` honours them. A colon-free string is
passed through untouched, so a typo in a real model name still fails loudly instead of being papered
over. `tests/config-test.sh` pins all four of those cases.

### Item 3 — "whether Claude Code imposes any absolute hook-timeout ceiling" — HALF SETTLED

Section 2 said this was not established and that its conclusion did not need it. **Raising
`hooks.json:9` past 60 does need it**, so it was established. Two observations on `claude` **2.1.252**:

- **The config schema does not cap it** **[obs]**. The command-hook entry types the field as
  `timeout: number().positive().optional()`, described *"Timeout in seconds for this specific
  command"*. No `.max()`.
- **The runner does not clamp it** **[obs]**. It computes `nn = e.timeout ? e.timeout*1000 : <default>`
  and passes `nn` straight into a `setTimeout` that TERMs the child. There is no `Math.min`,
  `Math.max`, floor or ceiling anywhere on that path, and no per-event branch — **one function serves
  every command-hook event**.
- **A declared 90 was honoured at runtime** **[obs]**. A command hook declaring `"timeout": 90`,
  whose script logs a heartbeat every 0.5 s for 75 s, ran to completion and exited on its own — 152
  log lines, last heartbeat at t+82.85 s wall, never TERMed.

Section 2's *"a `strings` search of the installed CLI binary (2.1.245) found no hook-timeout
ceiling — every match was bundled test-runner text"* was **right in its conclusion and stopped one
step early**: the matches for the *phrase* are test-runner text, but the relevant code carries no such
phrase. Searching for the schema field and for the runner's arithmetic finds it immediately.

**What is still [inferred], stated so nobody upgrades it by reading fast:**

- That the harness actually **kills** at the declared deadline. The code says
  `setTimeout(kill, timeout*1000)`; the probe finished early, so no kill was watched. This is the
  benign direction — if the deadline is not enforced, everything downstream is merely conservative.
- That `MessageDisplay` behaves like the probed event. The runner is event-agnostic in the source
  read above, and `hooks.json` has shipped `"timeout": 180` on `PostToolUse` against a 150 s
  `CLAUDISH_MD_TIMEOUT` since that hook existed — but the probe itself was `SessionStart`.

### Item 4 — "the exact overhead between the hook budget and the LLM call" — still unmeasured

Handled by construction instead of by measurement: `CLAUDISH_TIMEOUT`'s default and
`hooks.json:9` are now the **same number** (120), so the LLM budget can never exceed the process
budget, and the overhead comes out of the LLM call's own slack rather than out of the hook's. That is
strictly safer than the old 45-under-60 arrangement and needs no number nobody has.

### The interaction that had to be handled, and was nearly missed

`speak.sh`'s wait deadline is the spec's §3.5.1 clause 3 derivation
`min( CLAUDISH_TIMEOUT + 2, MD_TIMEOUT ) + 3`, and `MD_TIMEOUT` is a **constant in `speak.sh` that
copies `hooks.json:9`**. Raising `hooks.json` alone would have left it at 60 and put the wait's
deadline at **63 s** while the display budget ran to 120 — so every rewrite landing in between,
**including the 52.50 s one measured in section 4**, would have been put on screen and **never
spoken**, with `wait deadline passed -> silent` in the debug log and nothing at all on screen to say
why. The derivation is locked, and it was not touched: what moved is the `[repo]` value it reads, by
the clause's own definition of `MD_TIMEOUT`. `tests/config-test.sh` now asserts
`speak.sh:MD_TIMEOUT == hooks.json`'s declared MessageDisplay timeout, and a deliberate mutation back
to 60 makes it fail with the band named:

```
FAIL  speak.sh MD_TIMEOUT=60 but hooks.json declares 120 -- a rewrite landing between 63s
      and 120s would be DISPLAYED and never SPOKEN (spec 3.5.1 clause 3)
FAIL  derived wait 63s is short of the 120s display budget: rewrites in between are silent
```

### What the user must change on this machine

`~/.claude/settings.json`'s `env` block still sets `CLAUDISH_MODEL=qwen3:4b-instruct-2507-q4_K_M`,
which exists for the ollama path. The guard makes leaving it **safe** rather than **correct**:

- **Remove the `CLAUDISH_MODEL` key** (or set it to `haiku`). Then nothing is being ignored and the
  debug log stops saying so.
- **Keep it only if you also set `CLAUDISH_PROVIDER=ollama`**, in which case the pair is consistent
  and no guard fires.

Env vars are frozen at session launch (section 3), so either way it takes a new session.

