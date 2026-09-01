# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **A silent turn no longer cuts off the previous answer.** `speak.sh`'s
  preemption ran above every gate that can exit without speaking, so a turn
  that was never going to speak still TERMed the previous speaker's process
  group: a long answer playing, a one-line question asked, and the long answer
  cut off mid-sentence with nothing in its place. The kill now runs below the
  content gates and above the fork, so a turn that *does* speak still leaves
  exactly one speaker. `tests/speak-selftest.sh` cases 7 and 8.

### Changed
- **Speech has no length floor of its own.** Below `CLAUDISH_MIN_CHARS`
  `rewrite.sh` published nothing, so short answers were spoken from a separate
  raw path in `speak.sh` or — if they carried one of eight hazard classes —
  not at all. Now `rewrite.sh` publishes on the short path too, carrying the
  **raw** text under the same key, and `speak.sh` reads `CLAUDISH_MIN_CHARS`
  on no path: `MIN_CHARS` decides what is *rewritten*, never what is spoken.
  That drops the eight-class hazard gate, which had measured zero effect on all
  sixteen real sub-threshold items. `tests/speak-selftest.sh` case 9.

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
  (FrancisBehnen/claudish-to-spoken-english#23). This is the **cold path**: the
  spec's resident worker and its preemption protocol are deliberately not
  built — see [`docs/decisions/speak-cold-path.md`](docs/decisions/speak-cold-path.md).
- `speak-key.sh`: the one definition of the rewrite→speech handoff key,
  `sha256( trim( text ) )`, sourced by `rewrite.sh` and `speak.sh` alike so the
  publisher and the consumer cannot compute different paths and leave the
  plugin silently mute. Pinned by `tests/speak-key-cases.tsv` against an
  independent Python implementation, under both hooks' shell regimes.
- `tests/`: a `Stop` payload fixture and two scripts that exercise the speech
  hook with no Claude Code session involved.
- `claude-cli` provider: rewrites can run through the local `claude` binary in
  print mode, on your existing Claude Code subscription instead of a metered API
  key or a local model (~8–12 s per message on an M3, versus ~15–25 s for a
  local model that fits 16 GB). The message travels on stdin so long messages
  are not capped by `ARG_MAX`; recursion is guarded with `CLAUDISH_ENABLED=0` in
  the child's environment; no MCP servers are loaded; and the session is not
  persisted. New vars: `CLAUDISH_CLAUDE_BIN`, `CLAUDISH_CLAUDE_DISALLOW`
  (FrancisBehnen/claudish-to-spoken-english#12).
- `_llm_run_bounded`: a watchdog that TERMs then KILLs a child at
  `LLM_TIMEOUT` seconds. The HTTP providers get their bound from
  `curl --max-time`, but macOS ships no `timeout(1)`, so a subprocess provider
  has to bring its own — without it a wedged CLI could stall the assistant's
  answer and break the fail-open contract.
- `ratelimited` is now part of the `llm_complete` contract, so a subscription
  quota refusal gets its own once-per-session notice rather than a generic one.

### Changed
- `bench/sanitizers.py` moved to `speech/sanitizers.py`, and
  `bench/first-sentence.py`'s `_SENT_END` / `first_sentence` moved to
  `speech/split.py`. Both are now at the plugin root so the shipped `Stop` hook
  imports the same code the bench harness measures, rather than reaching into
  `bench/` by path. The registry, `run()`, and every rule are unchanged; the
  bench scripts are now callers rather than owners.

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

[0.3.0]: https://github.com/gvzdv/claudish-to-english/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/gvzdv/claudish-to-english/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/gvzdv/claudish-to-english/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/gvzdv/claudish-to-english/releases/tag/v0.1.0
