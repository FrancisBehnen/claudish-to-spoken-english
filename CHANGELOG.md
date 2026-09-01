# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-09-01

The release that speaks. With `CLAUDISH_SPEAK=1` your assistant's replies are
read aloud — the same plain-English rewrite you already see on screen, spoken
through a local Kokoro voice while you keep working. Speech is **off by
default**; nothing about the display hook changes until you turn it on.

Two things in here are not speech and are worth knowing before you update.
The rewrite provider now defaults to **`claude-cli`**, which means the text of
your assistant's messages is sent to Anthropic's API on your own subscription —
**conversation content leaves your machine**, and it draws on the same 5-hour
and 7-day quota windows as your real work. `ollama` remains the only
**zero-egress** provider: set `CLAUDISH_PROVIDER=ollama` and nothing leaves the
machine. And the display timeout moved from 45 s to **120 s**, so a slow rewrite
now has two minutes to arrive instead of giving up.

### Added
- **Speech, off by default.** With `CLAUDISH_SPEAK=1` the plugin speaks each
  turn's plain-English rewrite aloud through a local Kokoro voice (`bf_emma`).
  A new `Stop` hook, `speak.sh`, gates, classifies, drops a job and forks a
  detached speaker in ~0.11 s; the speaker waits for the rewrite to be
  published, sanitizes it with the settled rule set, splits it into sentences
  and plays sentence one while sentence two is still being synthesised.
  Measured hook-invocation-to-wav: 2.08–2.68 s. `touch
  ~/.claude/claudish-speak-off` mutes it mid-utterance;
  `~/.claude/claudish-off` still stops both speech and rewriting. New vars:
  `CLAUDISH_SPEAK`, `CLAUDISH_SPEAK_OFF_FILE`, `CLAUDISH_VOICE`,
  `CLAUDISH_PLAYER`, `CLAUDISH_SPEAK_TIMEOUT`, `KOKORO_ROOT`
  (FrancisBehnen/claudish-to-spoken-english#23).

  This is the **cold path**, and the omission is deliberate: the spec's
  **LOCKED §10.5 resident worker is not built** — no generation election, no
  `kqueue` wake, no `worker.lock.<gen>` / `worker.retiring.<gen>` records, no
  retirement protocol, no idle exit. Every turn pays ~0.79 s of Python import
  and model load instead of paying it once per session, which is the whole of
  what residency would have bought against an LLM rewrite that dominates the
  path; in exchange, four of the spec's five ship-blocking defects cannot
  occur. The reasoning and the measurements are in
  [`docs/decisions/speak-cold-path.md`](docs/decisions/speak-cold-path.md).
- `speak-key.sh`: the one definition of the rewrite→speech handoff key,
  `sha256( trim( text ) )`, sourced by `rewrite.sh` and `speak.sh` alike so the
  publisher and the consumer cannot compute different paths and leave the
  plugin silently mute. Pinned by `tests/speak-key-cases.tsv` against an
  independent Python implementation, under both hooks' shell regimes.
- `tests/`: a `Stop` payload fixture and two scripts that exercise the speech
  hook with no Claude Code session involved.
- **`tests/config-test.sh`** — 11 free assertions (no model call, no audio, no
  tokens) over the config facts no runtime test reaches: the provider default,
  the `CLAUDISH_MODEL` guard, and the coupling between `CLAUDISH_TIMEOUT`,
  `hooks.json`'s MessageDisplay timeout and `speak.sh`'s `MD_TIMEOUT`.
- `claude-cli` provider: rewrites can run through the local `claude` binary in
  print mode, on your existing Claude Code subscription instead of a metered API
  key or a local model (~8–12 s per message on an M3, versus ~15–25 s for a
  local model that fits 16 GB). The message travels on stdin so long messages
  are not capped by `ARG_MAX`; recursion is guarded with `CLAUDISH_ENABLED=0` in
  the child's environment; no MCP servers are loaded; and the session is not
  persisted. New vars: `CLAUDISH_CLAUDE_BIN`, `CLAUDISH_CLAUDE_DISALLOW`
  (FrancisBehnen/claudish-to-spoken-english#12).
- **A stale `CLAUDISH_MODEL` no longer breaks every rewrite on the new
  default.** `CLAUDISH_MODEL` is not namespaced per provider, so an ollama tag
  left in a settings `env` block reached the CLI as `--model` verbatim and
  failed every rewrite (measured: exit 1, *"is not a model this version of
  Claude Code recognizes"*, no quota spent). On `claude-cli` an unmistakably
  foreign `name:tag` — a colon and no `claude`/`anthropic`/`haiku`/`sonnet`/
  `opus` — is now ignored in favour of `haiku`, logged under `CLAUDISH_DEBUG=1`.
  Bedrock/Vertex ids (which also carry a colon) and colon-free names are
  untouched, so a typo in a real model name still fails loudly.
- `_llm_run_bounded`: a watchdog that TERMs then KILLs a child at
  `LLM_TIMEOUT` seconds. The HTTP providers get their bound from
  `curl --max-time`, but macOS ships no `timeout(1)`, so a subprocess provider
  has to bring its own — without it a wedged CLI could stall the assistant's
  answer and break the fail-open contract.
- `ratelimited` is now part of the `llm_complete` contract, so a subscription
  quota refusal gets its own once-per-session notice rather than a generic one.

### Changed
- **`claude-cli` is now the default provider, and it spends subscription
  quota.** Rewrites run on your own Claude Code login instead of a local
  ollama. This is a real tradeoff and the README states it plainly under
  [Why `claude-cli` is the default](README.md#why-claude-cli-is-the-default-and-what-it-costs):
  every turn in every session now draws on the same 5-hour and 7-day windows as
  your real work, **and the message text is sent off your machine** to
  Anthropic's API. `ollama` is the only provider with no egress at all. Undo it
  with `CLAUDISH_PROVIDER=ollama`; pause everything with `touch
  ~/.claude/claudish-off`.

  The reason is **concurrency, not speed.** A local ollama serves completions
  serially (`llama-server … -np 1`, `OLLAMA_NUM_PARALLEL` unset), so concurrent
  Claude Code sessions queue behind one another and blow the display hook's
  budget — 8 timeouts against 10 successful rewrites in 30 minutes across four
  sessions. `docs/research/ollama-concurrency.md` explains why turning ollama
  parallel is not the fix. (#14's own premise — that `claude-cli` latency is
  flat in message size — was measured and **refuted** at 52.50 s for 1,328
  words; that is not why this changed.)
- **The display timeouts went 45/60 → 120/120 seconds.** `CLAUDISH_TIMEOUT`'s
  default *and* the `MessageDisplay` hook's own `timeout` in `hooks/hooks.json`,
  which are two numbers that only work when moved together: the hook timeout
  bounds the process that makes the LLM call, so raising `CLAUDISH_TIMEOUT`
  alone was inert. A declared hook timeout above 60 is honoured — measured, and
  the CLI's hook-config schema puts no maximum on the field.
- **`speak.sh`'s `MD_TIMEOUT` tracked that raise, so long rewrites are still
  spoken.** The speech wait is the spec's derivation
  `min(CLAUDISH_TIMEOUT + 2, MD_TIMEOUT) + 3`, and `MD_TIMEOUT` is a copy of the
  hooks.json number. Left at 60 it would have capped speech at **63 s** while
  the screen got 120 s — every rewrite in between displayed and never spoken,
  with no error anywhere. The derivation itself is untouched; only the value it
  reads moved. `tests/config-test.sh` now asserts the two stay equal.
- **The display hook's timeout notice names the hooks.json ceiling and the
  provider switch**, instead of advising a `CLAUDISH_TIMEOUT` raise that does
  nothing on its own. The Markdown hook's notice already got this right.
- **Speech has no length floor of its own.** Below `CLAUDISH_MIN_CHARS`
  `rewrite.sh` published nothing, so short answers were spoken from a separate
  raw path in `speak.sh` or — if they carried one of eight hazard classes —
  not at all. Now `rewrite.sh` publishes on the short path too, carrying the
  **raw** text under the same key, and `speak.sh` reads `CLAUDISH_MIN_CHARS`
  on no path: `MIN_CHARS` decides what is *rewritten*, never what is spoken.
  That drops the eight-class hazard gate, which had measured zero effect on all
  sixteen real sub-threshold items. `tests/speak-selftest.sh` case 9.
- `bench/sanitizers.py` moved to `speech/sanitizers.py`, and
  `bench/first-sentence.py`'s `_SENT_END` / `first_sentence` moved to
  `speech/split.py`. Both are now at the plugin root so the shipped `Stop` hook
  imports the same code the bench harness measures, rather than reaching into
  `bench/` by path. The registry, `run()`, and every rule are unchanged; the
  bench scripts are now callers rather than owners.

### Fixed
- **A silent turn no longer cuts off the previous answer.** `speak.sh`'s
  preemption ran above every gate that can exit without speaking, so a turn
  that was never going to speak still TERMed the previous speaker's process
  group: a long answer playing, a one-line question asked, and the long answer
  cut off mid-sentence with nothing in its place. The kill now runs below the
  content gates and above the fork, so a turn that *does* speak still leaves
  exactly one speaker. `tests/speak-selftest.sh` cases 7 and 8.

## [0.3.0] - 2026-08-13

### Added
- Customizable rewrite prompts. Point the display hook at a prompt file with
  `CLAUDISH_PROMPT_FILE`, or the Markdown hook with `CLAUDISH_MD_PROMPT_FILE`;
  the file's contents replace the built-in prompt wholesale. An unset, empty, or
  unreadable file falls back to the built-in default, so a bad path never stops
  rewrites. Defaults are unchanged.

## [0.2.0] - 2026-08-13

### Added
- Provider layer (`providers.sh`): rewrites can run against local **ollama**
  (default, unchanged), the **Anthropic** Messages API, or any
  **OpenAI-compatible** endpoint, selected with `CLAUDISH_PROVIDER` (#10).
- Runtime kill-switch flag file (`~/.claude/claudish-off`, overridable with
  `CLAUDISH_OFF_FILE`) to pause and resume rewrites mid-session, since env vars
  are frozen at launch (#4).
- Windows setup documentation and model-default guidance (#7).
- Comparison screenshot at the top of the README.

### Fixed
- Markdown `overwrite` mode: the idempotency marker is written after any YAML
  frontmatter, so the frontmatter stays on line 1 where parsers expect it.
  Leftover display-hook temp files are also cleaned up (#1).
- Quote `CLAUDE_PLUGIN_ROOT` in the hook commands so plugin paths containing
  spaces resolve correctly (#6).

## [0.1.1] - 2026-08-10

### Added
- One-time, per-session notice explaining why a rewrite was skipped when the
  provider is unreachable, the call times out, or the model isn't available
  (`CLAUDISH_NOTICE`, default on).

### Changed
- Default model set to `gemma4:26b-mlx` (Apple-silicon MLX build).
- Separate per-hook timeouts: `CLAUDISH_TIMEOUT` (display) and
  `CLAUDISH_MD_TIMEOUT` (Markdown file).
- Added the "Configuring the plugin" section to the README.

## [0.1.0] - 2026-08-10

### Added
- Initial release. A `MessageDisplay` hook (`rewrite.sh`) that rewrites each
  assistant message into plain English with a local ollama model — `append`
  and `replace` display modes, a prose-length gate, and a fail-open contract
  that always leaves Claude's original text on screen if anything goes wrong.
- Optional `PostToolUse` Markdown-file rewrite hook (`rewrite-md.sh`), opt-in by
  directory (`CLAUDISH_MD_DIR`), with `sibling` and `overwrite` modes.

[0.4.0]: https://github.com/FrancisBehnen/claudish-to-spoken-english/releases/tag/claudish-to-english--v0.4.0
[0.3.0]: https://github.com/gvzdv/claudish-to-english/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/gvzdv/claudish-to-english/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/gvzdv/claudish-to-english/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/gvzdv/claudish-to-english/releases/tag/v0.1.0
