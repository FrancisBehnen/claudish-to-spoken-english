# claudish-to-english

<p align="center">
  <img
    src="https://github.com/gvzdv/claudish-to-english/releases/download/assets/comparison.png"
    width="820"
    alt="Side-by-side comparison: a dense, jargon-heavy Claude message labeled 'Claudish' on the left, and its plain-English rewrite on the right">
</p>

A Claude Code plugin that shows a **plain-English rewrite** of each assistant
message, produced by **your own Claude Code subscription via the local `claude`
CLI** (default), a **local LLM via ollama**, the **Anthropic API**, or any
**OpenAI-compatible API**. It is **display-only**:
Claude's own reasoning and the saved transcript keep the original text — only
what you read on screen changes.

An optional second hook rewrites **Markdown files** into plain English when they
are written or edited (opt-in, off by default).

> Status: working prototype. Every hook fails **open** — if anything goes wrong
> (provider down, timeout, missing key or dependency), you simply see Claude's
> original text. The plugin can never swallow or corrupt an answer.


---

## Requirements (read this first)

**On the default `claude-cli` provider you need almost none of the below** —
`jq`, and the `claude` binary you already have. The ollama sections here are for
`CLAUDISH_PROVIDER=ollama`, which shells out to a **local** model and does not
work until those pieces are in place. (With `CLAUDISH_PROVIDER=anthropic` or
`openai` you need only `jq`, `curl`, and an API key — see
[Providers](#providers).)

<a id="macos-setup"></a>
<details>
<summary><strong>macOS setup</strong></summary>

| Requirement | Why | Install |
|---|---|---|
| **ollama**, running | Does the rewriting, locally | `brew install ollama` then `ollama serve` |
| A pulled model | The actual rewriter | `ollama pull gemma4:26b-mlx` (~17 GB; choose the model that fits into your memory) |
| `jq` | Parses hook JSON | ships with macOS 15+; else `brew install jq` |
| `curl` | Talks to ollama | ships with macOS |

Warm the model once after `ollama serve` (the first call is a slow cold load):

```bash
ollama run gemma4:26b-mlx "hi"
```

**If the local model isn't ready, the plugin does nothing to your text** —
Claude's output shows normally, unchanged. That is by design, not a bug. It skips
(fails open) when ollama is down, the request times out, or the model isn't
pulled. The first time that happens in a session it tells you why: the display
hook appends a one-line notice on screen, and the Markdown hook shows a
`systemMessage`. So a silent skip is never a mystery (once per session; set
`CLAUDISH_NOTICE=0` to silence it).

**Pick a model you actually have.** The default is `gemma4:26b-mlx`, an
Apple-silicon (MLX) build — the right choice on a Mac, but **macOS-only**. On
Windows it doesn't run, so you must switch to a regular tag (see
[Windows setup](#windows-setup)). Pull it (as above), or pull a smaller/faster
model and point the plugin at it by setting `CLAUDISH_MODEL` to that model's
exact ollama tag in your `env` (see
[Configuring the plugin](#configuring-the-plugin)). If `CLAUDISH_MODEL` names a
model you have not pulled, every rewrite is skipped — with the one-time notice
above.

</details>

<a id="windows-setup"></a>
<details>
<summary><strong>Windows setup</strong></summary>

The hooks are bash scripts; on Windows, Claude Code runs them through **Git
Bash** (Git for Windows).

| Requirement | Why | Install |
|---|---|---|
| **Ollama**, running | Does the rewriting, locally | `winget install Ollama.Ollama`, then launch the Ollama app; it serves on `localhost:11434` |
| A pulled model | The actual rewriter | `ollama pull gemma4:26b` (choose a model that fits into your memory) |
| `jq` | Parses hook JSON | `winget install jqlang.jq` |
| `curl` | Talks to ollama | ships with Windows 10+ |
| Git Bash | Runs the hook scripts | Claude Code users usually already have it; else `winget install Git.Git` |

Restart your terminal after installing so `jq`, `ollama`, and Git Bash are on
PATH (check `jq --version` and `ollama --version`).

> **The default model is macOS-only — Windows users must override it.** The
> plugin's default, `gemma4:26b-mlx`, is an Apple-silicon (MLX) build that doesn't
> run on Windows, so leaving it unset means every rewrite is silently skipped.
> Always set `CLAUDISH_MODEL` to a regular (non-MLX) tag on Windows. The table
> above uses `gemma4:26b` as an example; choose another if it fits your machine
> better.

Warm the model once after launching Ollama (the first call is a slow cold load):

```powershell
ollama run gemma4:26b "hi"
```

Then set `CLAUDISH_MODEL` in the `env` block of your `settings.json` (see
[Configuring the plugin](#configuring-the-plugin) — that method is identical on
Windows), or for a one-off session from PowerShell:

```powershell
$env:CLAUDISH_MODEL = "gemma4:26b"; claude
```

Windows equivalents of the mid-session kill switch
([Toggling mid-session](#toggling-mid-session)):

```powershell
New-Item -ItemType File $HOME\.claude\claudish-off   # pause rewrites
Remove-Item $HOME\.claude\claudish-off               # resume
```

(In Git Bash the `touch`/`rm` commands from that section work as-is.)

Notes:
- Write `CLAUDISH_MD_DIR` with forward slashes
(`C:/dev/docs/plain`) so the bash-side path checks match
- The `CLAUDISH_DEBUG=1` log lands under Git Bash's temp directory
(`$TMPDIR/claudish-to-english/`, typically
`C:\Users\<you>\AppData\Local\Temp\claudish-to-english\`).

</details>

---

## Install

Directly from this repository (also serves its own marketplace):

```shell
/plugin marketplace add FrancisBehnen/claudish-to-spoken-english
/plugin install claudish-to-english@claudish-tts
```

After review by the Anthropic team, the plugin will be available to install from the community marketplace:

```shell
/plugin marketplace add anthropics/claude-plugins-community
/plugin install claudish-to-english@claude-community
```

If the install summary says `Run /reload-plugins to activate.`, run that command.

**Try before installing** (loads it for one session, no install):

```bash
claude --plugin-dir /path/to/claudish-to-english
```

Run `/reload-plugins` after edits; if it doesn't load, check the `/plugin`
**Errors** tab.

---

## Configuring the plugin

All behavior is controlled by `CLAUDISH_*` environment variables (full list in
[Configuration](#configuration-env-vars) below). When you install from a
marketplace, set them in Claude Code's **`env` block in `settings.json`** — do
**not** edit the plugin's own `hooks/hooks.json`, which lives in the read-only
plugin cache (`~/.claude/plugins/cache/…`) and is overwritten on every update.

For a personal, all-projects setup, use `~/.claude/settings.json`:

```json
{
  "env": {
    "CLAUDISH_MODEL": "gemma4:26b-mlx",
    "CLAUDISH_MODE": "append"
  }
}
```

The hooks are subprocesses Claude Code spawns, so they inherit these. A few
things to know:

- **Restart Claude Code after editing `env`.** The value is captured at launch,
  so a running session keeps the old one.
- **`env` does not merge across scopes.** The highest-precedence settings file
  that defines `env` supplies the *entire* block — it isn't combined with lower
  scopes. Precedence: managed → local → project → user. Keep all your
  `CLAUDISH_*` vars in whichever file wins.
- **Scopes:** `~/.claude/settings.json` (all your projects) ·
  `.claude/settings.json` (shared with a repo, checked in) ·
  `.claude/settings.local.json` (just you, just this repo).

Quick one-off without editing a file — hooks inherit the launching shell:

```bash
CLAUDISH_MODEL=llama3.2:3b claude
```

To confirm the hook is firing, set `CLAUDISH_DEBUG=1` and watch
`"$TMPDIR"/claudish-to-english/debug.log`.

---

## Customizing the rewrite prompt

Each hook ships with a default system prompt that asks the model for plain
English while preserving facts, code, and structure. You can **replace** either
prompt with your own to add specific rules or use wording that works
better with your model. To do so, point the hook at a file that holds
the prompt:

| Hook | Prompt file |
|---|---|
| Display (`rewrite.sh`) | `CLAUDISH_PROMPT_FILE` |
| Markdown (`rewrite-md.sh`) | `CLAUDISH_MD_PROMPT_FILE` |

The file's contents **replace** the built-in prompt, so
include every instruction you want the model to follow — otherwise the defaults
(keep facts, leave code blocks alone, output only the rewrite) are gone. Keeping
the prompt in a file avoids escaping a long, multi-line prompt inside a JSON
string. If the variable is unset, or the file is empty or unreadable, the hook
falls back to its built-in default, so a bad path never stops rewrites.

```json
{
  "env": {
    "CLAUDISH_PROMPT_FILE": "/ABS/PATH/prompts/plain.txt",
    "CLAUDISH_MD_PROMPT_FILE": "/ABS/PATH/prompts/md-plain.txt"
  }
}
```

The display hook still appends the **original user question** to your prompt, as
context to keep the rewrite on-topic (see
[How the display hook works](#how-the-display-hook-works)). Your prompt
replaces only the base instruction.

---

## How the display hook works

Claude Code fires the `MessageDisplay` event **once per streamed chunk**, not
once per message. Each fire is a separate process carrying `message_id`,
`index`, a `final` flag, and this chunk's `delta` (a text fragment, not the
whole message). So the hook **buffers every delta** to a temp file (keyed by
`message_id`) and only calls the model on the **final** chunk, once the whole
message is known:

```
chunk 0 (final:false) ─┐
chunk 1 (final:false) ─┤ append each delta to $TMPDIR/claudish-to-english/<session>/<message>/<index>.part
chunk 2 (final:false) ─┘  → emit nothing (append) or "" (replace)
chunk 3 (final:true)  ──► reconstruct full message → call the provider once → show the rewrite
                          → delete the buffer
```

On that final chunk it also reads the **original user question** from the
transcript and passes it to the model as **context only** — to keep the rewrite
on-topic. The model is told never to answer or repeat the question; it only
rewrites the assistant's message.

### Display modes

| `CLAUDISH_MODE` | On screen | Notes |
|---|---|---|
| `append` (default) | Original streams normally, then a `💬 In plain English:` block is appended. | Safest. No streaming loss; if the LLM fails you just don't get the extra block. |
| `replace` | Only the simplified version (original chunks suppressed while streaming). | Experimental. Appears all at once after LLM latency; on failure it re-shows the full original. |

---

## Markdown file rewrite (optional second hook)

A `PostToolUse` hook (`rewrite-md.sh`) rewrites Markdown **files** into plain
English when they are written or edited. Unlike the display hook, this changes
bytes on disk.

**Opt-in by directory.** It does nothing unless `CLAUDISH_MD_DIR` is set, and it
only touches `*.md` files whose resolved path is inside that directory. Every
other `README`, `CLAUDE.md`, or doc you edit is left alone.

| `CLAUDISH_MD_MODE` | Result | Notes |
|---|---|---|
| `sibling` (default) | Writes `NAME.plain.md` next to `NAME.md`. | Non-destructive; the original is never touched. |
| `overwrite` | Replaces `NAME.md` in place. | Adds a `<!-- claudish-to-english:rewritten -->` marker so a re-write is skipped (idempotent). A weak model can degrade real docs — use with care. |

In both modes: YAML frontmatter is split off and re-attached **verbatim**, fenced
code is left to the model instruction, short files are skipped, and the write is
atomic. Fail-open here means the file is left **exactly as the agent wrote it**.

**Large files are slow.** `gemma4:26b-mlx` (the default) rewrites at roughly 60
tokens/s, so a long plan or spec can take 30–120s. This hook allows up to
`CLAUDISH_MD_TIMEOUT` (150s) inside a 180s `PostToolUse` hook budget; if a rewrite
still times out you get the one-time notice above — raise those limits, or set
`CLAUDISH_MODEL` to a smaller model.

Enable it for one directory, in sibling mode (the safe default), the same way
as every other setting — the `env` block of your `settings.json`:

```json
{
  "env": {
    "CLAUDISH_MD_DIR": "/ABS/PATH/docs/plain",
    "CLAUDISH_MD_MODE": "sibling"
  }
}
```

In `overwrite` mode the marker comment is written **after** any YAML
frontmatter, so the frontmatter stays on line 1 where parsers expect it.

---

## Providers

Rewrites go through one of four providers, selected with `CLAUDISH_PROVIDER`
(both hooks share the setting). **The default is `claude-cli`**, which runs each
rewrite on your own Claude Code subscription. That is a change from upstream,
where the default was local ollama — see
[Why `claude-cli` is the default, and what it costs](#why-claude-cli-is-the-default-and-what-it-costs)
before you leave it alone.

| Provider | Endpoint | Key | Default model |
|---|---|---|---|
| `ollama` | `CLAUDISH_OLLAMA` (`http://localhost:11434`) | none | `gemma4:26b-mlx` |
| `anthropic` | `CLAUDISH_ANTHROPIC_URL` (`https://api.anthropic.com`) + `/v1/messages` | `CLAUDISH_ANTHROPIC_KEY` or `ANTHROPIC_API_KEY` | `claude-haiku-4-5` |
| `openai` | `CLAUDISH_OPENAI_URL` + `/chat/completions` | `CLAUDISH_OPENAI_KEY` or `OPENAI_API_KEY` | `gpt-5.6-luna` |
| `claude-cli` **(default)** | the local `claude` binary (`CLAUDISH_CLAUDE_BIN`), no network call of our own | none — your existing Claude Code login | `haiku` |

> [!CAUTION]
> The cloud providers pick their key up from the **ambient environment**
> (`OPENAI_API_KEY` / `ANTHROPIC_API_KEY`), and `CLAUDISH_OPENAI_URL` defaults
> to api.openai.com. Anything that puts those variables into the environment
> Claude Code launches with — an `export` in your shell profile, a tool like
> direnv loading a project's `.env` into your shell, or the `env` block of a
> settings file — makes them visible to this plugin. In such an environment,
> setting the single variable `CLAUDISH_PROVIDER=openai` starts sending every
> assistant message (and, with the Markdown hook, file contents) to OpenAI's
> cloud. Likewise, `CLAUDISH_PROVIDER=anthropic` will quietly spend the same
> `ANTHROPIC_API_KEY` (and share its rate limits) that other tools on your
> machine may rely on. Selecting a cloud provider IS the consent switch — set
> it only when you mean it, and use the `CLAUDISH_*_KEY` variables when you
> want the plugin on a dedicated key.

```bash
# ollama — local, nothing leaves your machine, no quota spent
export CLAUDISH_PROVIDER=ollama
export CLAUDISH_MODEL=gemma4:26b-mlx        # the default; any pulled tag works

# Anthropic — Claude Haiku
export CLAUDISH_PROVIDER=anthropic
export ANTHROPIC_API_KEY=sk-ant-...
export CLAUDISH_MODEL=claude-haiku-4-5      # the default; override to taste

# OpenAI — GPT-5.6 Luna
export CLAUDISH_PROVIDER=openai
export OPENAI_API_KEY=sk-...
export CLAUDISH_MODEL=gpt-5.6-luna          # the default; override to taste

# Any OpenAI-compatible server (LM Studio, llama.cpp server, vLLM, OpenRouter).
# A key is only required for api.openai.com — local servers work keyless.
export CLAUDISH_PROVIDER=openai
export CLAUDISH_OPENAI_URL=http://localhost:1234/v1
export CLAUDISH_MODEL=qwen3-30b

# Your own Claude Code subscription, via the local CLI — no API key at all.
# THE DEFAULT. Costs subscription quota instead of money; see the caution below.
export CLAUDISH_PROVIDER=claude-cli
export CLAUDISH_MODEL=haiku                 # the default; an alias or full id
```

Notes:

- `CLAUDISH_MODEL` overrides any provider's default model. It is **not**
  namespaced per provider, so a value left over from ollama (`gemma4:26b-mlx`)
  travels to whichever provider you switch to. Unset it when you switch.
  **One narrow exception, because the default provider moved under people's
  feet:** on `claude-cli`, a `CLAUDISH_MODEL` that is an unmistakably foreign
  `name:tag` — a colon, and no `claude`/`anthropic`/`haiku`/`sonnet`/`opus`
  anywhere in it — is ignored and `haiku` is used instead. Without that, an
  ollama tag sitting in a settings `env` block would reach the CLI as `--model`
  verbatim and fail **every** rewrite (measured: `claude -p --model
  qwen3:4b-instruct-2507-q4_K_M` exits 1 with *"is not a model this version of
  Claude Code recognizes"*). Bedrock and Vertex ids carry a colon too
  (`us.anthropic.claude-haiku-4-5-20251001-v1:0`) and are **not** touched, and
  neither is any colon-free name — so a typo in a real model name still fails
  loudly rather than being quietly papered over. `CLAUDISH_DEBUG=1` logs it
  whenever it fires.
- Requests to api.openai.com send `reasoning_effort: "none"` (GPT-5.6-class
  models otherwise spend reasoning tokens on a plain rewrite). Custom
  OpenAI-compatible URLs get no such field, since some local servers reject
  unknown fields. Force one with `CLAUDISH_OPENAI_EFFORT`, or set it
  **explicitly empty** (`CLAUDISH_OPENAI_EFFORT=`) to omit the field even for
  api.openai.com — needed for models that reject `reasoning_effort` entirely.
- The anthropic provider caps completions at `CLAUDISH_MAX_TOKENS` (default
  4096, since the Messages API requires an explicit cap).
- A rewrite that hits an output-token cap is **discarded**, not shown — on all
  the HTTP providers (ollama's `done_reason: "length"` included): a half-finished
  rewrite on screen is confusing, and in the Markdown hook's `overwrite` mode
  it would replace your real document. You get the original text plus the
  once-per-session notice suggesting a higher cap.
- Every provider failure stays fail-open: missing key, bad key, unreachable
  endpoint, or timeout just leaves the original text (plus the once-per-session
  notice, unless `CLAUDISH_NOTICE=0`).

> **Privacy:** every provider except `ollama` — **including the default** —
> sends each assistant message (and, for the Markdown hook, file contents) to an
> external API. `CLAUDISH_PROVIDER=ollama` is the only setting under which
> nothing leaves your machine. Read [Privacy / egress](#privacy--egress).

### Why `claude-cli` is the default, and what it costs

> [!IMPORTANT]
> **The default provider spends your Claude subscription quota — every turn, in
> every session.** `claude-cli` rewrites draw on the same 5-hour and 7-day
> windows as your real Claude Code work. There is no separate budget and no
> separate bill. If you run several sessions at once, every one of them is
> spending that quota on the display layer, and the way you find out is your
> *real* work being refused.
>
> This is a deliberate trade, not an oversight. It is here because the
> alternative was worse **for the concurrent case**: a local ollama serves
> requests one at a time (`llama-server … -np 1`, `OLLAMA_NUM_PARALLEL` unset),
> so four concurrent sessions queue behind each other and time out. Measured on
> four sessions: **8 timeouts (`curl_rc=28`) against 10 successful rewrites in
> 30 minutes.** `docs/research/ollama-concurrency.md` explains why turning
> ollama parallel is not the fix. `claude-cli` has no such queue.
>
> **If that trade is wrong for you, it is one line to undo**, and nothing else
> in the plugin changes:
>
> ```bash
> export CLAUDISH_PROVIDER=ollama      # back to local, no quota, nothing leaves the machine
> ```
>
> That path needs the ollama pieces in [Requirements](#requirements-read-this-first),
> and it is **serial** — which is the problem this default exists to avoid, so
> expect timeouts again if you run sessions in parallel.
>
> Other ways to spend less of it, in rising order of bluntness:
>
> | Lever | Effect |
> |---|---|
> | `CLAUDISH_MIN_CHARS=600` (default `200`) | only long messages are rewritten; short ones are already plain |
> | `CLAUDISH_PROVIDER=anthropic` + `CLAUDISH_ANTHROPIC_KEY` | costs money on a key you choose instead of subscription quota |
> | `CLAUDISH_PROVIDER=ollama` | no quota, no money, no egress — but serial, so it times out under concurrency |
> | `touch ~/.claude/claudish-off` | pauses rewrites **immediately**, in sessions already running ([Toggling mid-session](#toggling-mid-session)) |
> | `CLAUDISH_ENABLED=0` | off from the next session start |
>
> A quota refusal is detected and gets its own once-per-session on-screen
> notice, so the display layer tells you when it has run you dry rather than
> silently going quiet.

### The `claude-cli` provider

`CLAUDISH_PROVIDER=claude-cli` (the default) runs each rewrite through the `claude` binary in
print mode, on the Claude Code login you already have. No API key, no local
model, no 17 GB of RAM. Measured on an M3 for a ~100-word message: **8–12 s**,
against ~2–4 s for the raw Haiku API and ~15–25 s for a local model small
enough to co-exist with everything else.

It is the only provider that is a subprocess rather than an HTTP call, which
changes a few things:

- **It spends subscription quota, not money** — the tradeoff and the levers are
  spelled out in
  [Why `claude-cli` is the default](#why-claude-cli-is-the-default-and-what-it-costs)
  above. It matters more than it used to, because this is now the default rather
  than an opt-in.
- **The message travels on stdin, not argv**, so long messages are not capped by
  `ARG_MAX`.
- **Recursion is guarded with `CLAUDISH_ENABLED=0` in the child's environment.**
  This hook is normally installed globally, so the child session loads it too;
  both hooks read that variable and bail before doing anything. (`--bare` would
  be the obvious way to skip hooks, but it reads auth *only* from
  `ANTHROPIC_API_KEY`/`apiKeyHelper` — never OAuth or the keychain — which would
  defeat the point of this provider.)
- **No MCP servers are loaded** (`--strict-mcp-config` with no config), and the
  session is not persisted.
- **The timeout is enforced by a watchdog**, not by curl: macOS ships no
  `timeout(1)`, so the provider TERMs and then KILLs the child at
  `CLAUDISH_TIMEOUT` seconds. A wedged CLI can therefore never stall the
  assistant's answer.
- **Tool use is not blocked by default.** `--disallowed-tools` validates every
  name against the CLI's tool registry and exits on the first one it doesn't
  recognize, so a hard-coded list here breaks loudly on any tool rename (it did:
  `MultiEdit` is not a known tool on CLI 2.1.233). Containment is the watchdog
  plus a prompt that asks only for the rewrite. Tighten it yourself with
  `CLAUDISH_CLAUDE_DISALLOW="Bash Read Edit"` if you want.

> **Privacy:** this provider sends your messages to Anthropic, the same as the
> `anthropic` provider — just billed to your subscription instead of a key.

---

## Configuration (env vars)

| Var | Default | Meaning |
|---|---|---|
| `CLAUDISH_ENABLED` | `1` | Master switch. `0` = pass everything through. Read once at session start. |
| `CLAUDISH_OFF_FILE` | `~/.claude/claudish-off` | Runtime kill switch. While this file exists, rewrites pause — re-checked every message, so unlike env vars it works mid-session. See [Toggling mid-session](#toggling-mid-session). |
| `CLAUDISH_MODE` | `append` | `append` or `replace` (display hook). |
| `CLAUDISH_PROMPT_FILE` | *(unset)* | Path to a file whose contents replace the display hook's system prompt (whole prompt, not merged). Empty/unreadable falls back to the built-in default. See [Customizing the rewrite prompt](#customizing-the-rewrite-prompt). |
| `CLAUDISH_PROVIDER` | `claude-cli` | `ollama`, `anthropic`, `openai`, or `claude-cli` — which LLM serves rewrites (both hooks). **The default spends subscription quota**; see [Why `claude-cli` is the default](#why-claude-cli-is-the-default-and-what-it-costs). |
| `CLAUDISH_MODEL` | *(per provider)* | Model name; overrides the provider default (see [Providers](#providers)). The ollama default `gemma4:26b-mlx` is MLX (Apple-silicon only; Windows users must override). On `claude-cli` a foreign `name:tag` is ignored rather than obeyed — see the note under [Providers](#providers). |
| `CLAUDISH_OLLAMA` | `http://localhost:11434` | ollama base URL. |
| `CLAUDISH_ANTHROPIC_KEY` | *(unset)* | Anthropic API key; falls back to `ANTHROPIC_API_KEY`. |
| `CLAUDISH_OPENAI_KEY` | *(unset)* | OpenAI(-compatible) API key; falls back to `OPENAI_API_KEY`. Only required for api.openai.com. |
| `CLAUDISH_OPENAI_URL` | `https://api.openai.com/v1` | Base URL for any OpenAI-compatible endpoint (LM Studio, llama.cpp server, vLLM, OpenRouter, ...). Trailing slashes are ignored. |
| `CLAUDISH_ANTHROPIC_URL` | `https://api.anthropic.com` | Base URL for the anthropic provider — override for proxies/gateways that speak the Messages API. |
| `CLAUDISH_OPENAI_EFFORT` | `none` on api.openai.com, else *(unset)* | `reasoning_effort` sent with openai-provider requests. Set explicitly empty to omit the field. |
| `CLAUDISH_MAX_TOKENS` | `4096` | Completion cap for the anthropic provider. Rewrites that hit the cap are discarded (fail-open), with a notice to raise it. |
| `CLAUDISH_CLAUDE_BIN` | `claude` | Path to the `claude` binary used by the `claude-cli` provider. |
| `CLAUDISH_CLAUDE_DISALLOW` | *(empty)* | Space-separated tool names to deny in the `claude-cli` child session. Empty by default — an unrecognized name makes the CLI exit, killing every rewrite. |
| `CLAUDISH_MIN_CHARS` | `200` | Skip messages/files whose prose (code stripped) is shorter than this. |
| `CLAUDISH_STUB` | `0` | `1` = deterministic stub instead of the model (for testing display mechanics). |
| `CLAUDISH_TIMEOUT` | `120` | LLM client timeout for the **display** hook (seconds). Keep it at or below that hook's own `timeout` in `hooks/hooks.json` (120s) — that one bounds the whole hook process, so it is the real ceiling and raising this one alone does nothing. |
| `CLAUDISH_MD_TIMEOUT` | `150` | LLM client timeout for the **Markdown file** hook (seconds). Higher on purpose — a large model rewriting a long doc is slow. Keep it below the `PostToolUse` hook `timeout` (180s). |
| `CLAUDISH_DEBUG` | `0` | `1` = write a debug log to `$TMPDIR/claudish-to-english/`. |
| `CLAUDISH_NOTICE` | `1` | `1` = show a one-time, once-per-session notice when a rewrite is skipped because the provider is unreachable, the call timed out, a key is missing, or the model isn't available (display hook appends it on screen; Markdown hook uses a `systemMessage`). `0` = stay fully silent (pure fail-open). |
| `CLAUDISH_MD_DIR` | *(unset)* | **Markdown hook opt-in.** Only `*.md` under this directory is rewritten. Unset = the Markdown hook does nothing. |
| `CLAUDISH_MD_MODE` | `sibling` | `sibling` (`NAME.plain.md`) or `overwrite` (in place). |
| `CLAUDISH_MD_SUFFIX` | `plain` | Sibling infix: `NAME.<suffix>.md`. |
| `CLAUDISH_MD_PROMPT_FILE` | *(unset)* | Path to a file whose contents replace the Markdown hook's system prompt (whole prompt, not merged). Empty/unreadable falls back to the built-in default. |

In `hooks/hooks.json` the display hook (`MessageDisplay`) has a **120s**
`timeout` and the Markdown hook (`PostToolUse`) has a 180s `timeout` — the file
hook is higher because a large model rewriting a long document can take a couple
of minutes. `CLAUDISH_TIMEOUT` and `CLAUDISH_MD_TIMEOUT` keep the LLM call itself
bounded at or below those ceilings, so it fails open cleanly instead of being
killed mid-write.

**These are two numbers and you must move both.** The hook's own `timeout`
bounds the *process* that makes the LLM call, so a hook the harness stops
displays nothing at all — raising `CLAUDISH_TIMEOUT` past it buys you nothing.
The display pair was 45/60 until they were raised together to 120/120.

A declared hook `timeout` above 60 **is** honoured: a hook declaring `90` was
observed running to completion after 75s of work, and the CLI's own hook config
schema types `timeout` as a plain positive number of seconds with no maximum
(checked on 2.1.252). The 60 that used to be here was this plugin's own chosen
value, never a harness limit — the `PostToolUse` entry four lines below has been
180 all along.

**Quick kill switch:** set `CLAUDISH_ENABLED=0` or disable the plugin (both apply
only from the next session start), or `touch ~/.claude/claudish-off` to pause a
session that's already running — see [Toggling mid-session](#toggling-mid-session)
below.

### Toggling mid-session

`CLAUDISH_ENABLED` and the other env vars are read once, when a session launches,
so they can't pause rewrites in a session that's already running. For that, both
hooks also check a **flag file** on every invocation — each fire is a fresh
process, so the check is always live:

```bash
touch ~/.claude/claudish-off   # pause rewrites, effective on the next message
rm    ~/.claude/claudish-off   # resume
```

You create and remove this file yourself; nothing creates it on install, and its
absence is the normal "on" state. While it exists, `ENABLED` is forced to `0` and
the fail-open path leaves Claude's original text untouched. Point a hotkey at a
two-line toggle script to flip rewrites from the keyboard across all running
sessions at once. Override the path with `CLAUDISH_OFF_FILE`.

### Reasoning models

The ollama request sends `"think": false`, and openai-provider requests to
api.openai.com send `reasoning_effort: "none"`. Models with a hidden reasoning
phase otherwise spend most of their time generating reasoning tokens you never
see — much slower for identical output quality on this simple task. Keep it off.

---

## Speech (optional third hook) — hear the rewrite spoken aloud

**Off by default.** With `CLAUDISH_SPEAK=1` the plugin speaks each turn's final message through
[Kokoro](https://github.com/thewh1teagle/kokoro-onnx), a local neural TTS — the plain-English
rewrite where there is one, and the message itself where it was too short to be rewritten.
**Speech has no length floor of its own**; `CLAUDISH_MIN_CHARS` decides what gets *rewritten*,
never what gets spoken. Nothing is sent anywhere; synthesis runs on your machine.

```bash
export CLAUDISH_SPEAK=1        # in your shell profile, or "env" in ~/.claude/settings.json
```

That is the whole enable. The plugin ships a `Stop` hook that fires on every turn for every
user; when `CLAUDISH_SPEAK` is not `1` it exits before it reads stdin, before it needs `jq`,
and before it parses anything. The residual cost of having speech installed but off is **one
bash process per turn**. Small, new, not zero.

### Requirements

- **macOS.** `afplay` is the only verified player. The player is configurable and other
  platforms are not promised.
- **A Kokoro venv at `$KOKORO_ROOT`** (default `~/.local/share/kokoro`) containing
  `kokoro-v1.0.onnx`, `voices-v1.0.bin`, and `venv/bin/python` with `kokoro_onnx`,
  `onnxruntime` and `soundfile` installed. See
  [`docs/research/kokoro-onnx-provisioning.md`](docs/research/kokoro-onnx-provisioning.md).
- **`espeak-ng` is not a prerequisite.** `libespeak-ng.dylib` ships inside the
  `espeakng-loader` wheel.
- `jq`, as for the rewrite hook.

If any of that is missing, speech is silent — there is no on-screen notice, because a `Stop`
hook has no way to write to the screen. `CLAUDISH_DEBUG=1` and
`$TMPDIR/claudish-to-english/debug.log` are the only diagnostic.

### Configuration

| variable | default | note |
| --- | --- | --- |
| `CLAUDISH_SPEAK` | **`0`** | off by default. The only variable in this plugin whose default is "feature off". |
| `CLAUDISH_SPEAK_OFF_FILE` | `~/.claude/claudish-speak-off` | runtime mute, **separate from `claudish-off`**. Checked fresh every invocation, and again before every sentence. |
| `CLAUDISH_VOICE` | `bf_emma` | chosen blind against real content; `af_heart`, `af_nicole`, `af_bella` and `am_michael` were all rejected. |
| `CLAUDISH_PLAYER` | `afplay` | `wav` plays directly; no `sox`/`ffmpeg` needed. |
| `CLAUDISH_SPEAK_TIMEOUT` | `30` | bounds **synthesis**, not the hook. |
| `KOKORO_ROOT` | `~/.local/share/kokoro` | the same name the bench harness uses; there is no second one. |
| `CLAUDISH_DEBUG` | `0` | reuses the rewrite hook's flag and its log file. There is no separate speech debug flag. |
| `CLAUDISH_SPEAK_MIN_CHARS` | — | **deliberately does not exist**, and neither does any other floor on speech. `CLAUDISH_MIN_CHARS` decides whether a message is *rewritten*; below it the raw message is published and spoken, because it was skipped precisely for being plain already. A knob nobody has justified does not ship. |
| `CLAUDISH_TTS_URL` | — | **deliberately does not exist.** The HTTP-server branch was measured and declined; there is no endpoint to point at. Synthesis is in-process. |

The wait for the rewrite has **no knob of its own**, on purpose: it is derived as
`min(CLAUDISH_TIMEOUT + 2, MD_TIMEOUT) + 3` seconds — **123 s at the defaults** — from the
same variable the rewrite's own LLM call uses and from `MD_TIMEOUT`, the display hook's
declared `timeout` in `hooks/hooks.json` (**120**). Raising `CLAUDISH_TIMEOUT` above **118**
does not extend it, because at that point the display hook's own budget binds first and a
rewrite that overruns it publishes nothing at all. (Moving *that* timeout means editing
`hooks/hooks.json` in the plugin.)

**`MD_TIMEOUT` in `speak.sh` is a copy of that hooks.json number, and the two must stay
equal.** Leave the copy behind when hooks.json moves and you get the plugin's nastiest
possible bug: a rewrite that lands after the stale wait but inside the real display budget is
put **on screen and never spoken**, with no error anywhere — the speaker has already logged
`wait deadline passed -> silent` and exited. When the display pair went 45/60 → 120/120, a
stale `MD_TIMEOUT=60` would have capped speech at 63 s while the screen got 120 s.
`tests/config-test.sh` asserts the two are equal, so they can no longer drift in silence.

### Mute vs disable

```bash
touch ~/.claude/claudish-speak-off   # stop speaking, keep rewriting on screen
rm    ~/.claude/claudish-speak-off   # resume

touch ~/.claude/claudish-off         # stop BOTH: no speech and no rewrite
```

`claudish-speak-off` takes effect **mid-utterance** — the speaker re-checks both files before
every sentence and while a sentence is playing, so audio that is already sounding stops within
about a fifth of a second.

### The speech arrives after the rewrite, and that is not a bug

The `Stop` event fires *concurrently with* the last chunk of the assistant's message — measured
a median 6.7 ms **before** it — and the text that gets spoken is the rewrite, which takes an LLM
call. So the answer appears on screen and is spoken a few seconds later. If the rewrite never
arrives, speech gives up silently at the derived deadline above.

Two consequences worth knowing:

- **What gets spoken is the published text, which is usually the rewrite.** A message too
  short to be rewritten at all (below `CLAUDISH_MIN_CHARS`) is published raw and spoken
  anyway: **speech has no length floor of its own**, because such a message was skipped
  precisely for being plain already. Either way the text goes through the sanitizer before
  it is spoken, so markdown syntax is never read out verbatim — but the sanitizer is lossy
  by design: `speak.sh:131` is heard as "speak dot sh:131", `/Users/f/Code/foo/bar.py` as
  "foo/bar dot py", a GitHub URL as "github dot com", and a fenced block as "Code block, two
  lines." **No gate silences a short message for carrying a path, a URL or a code fence.** An
  earlier design had one; it was deleted on 2026-09-01 because of the sixteen real
  sub-threshold messages that had been measured, **zero** carried such a construct — the gate
  silenced nothing anyone has observed. `docs/decisions/speak-cold-path.md` records the
  deletion and its cost.
- **Subagents never speak.** The `Stop` event does not fire for them, and the plugin ships no
  `SubagentStop` hook. A turn that ends while a background task is still running stays silent
  too.

### Trying it without Claude Code

```sh
tests/speak-selftest.sh        # ten cases, 33 assertions, real audio (~4 min)
tests/speak-selftest.sh -q     # same ten cases and assertions, silent
tests/speak-key-test.sh        # pin the rewrite→speech handoff key (16 cases)
tests/config-test.sh           # the two timeouts and the derived deadline (11)
```

[`docs/decisions/speak-cold-path.md`](docs/decisions/speak-cold-path.md) is what was built,
what was deliberately deferred, and the measured latency.

---

## Privacy / egress

**The default provider sends content off your machine.** `claude-cli` reaches
Anthropic through the local `claude` binary rather than `curl`, but every
rewritten assistant message (and, with the Markdown hook enabled, file contents)
still leaves your machine — the same destination as the `anthropic` provider;
what differs is who pays, not where it goes. `openai` sends it to OpenAI, or to
whatever `CLAUDISH_OPENAI_URL` points at.

**`CLAUDISH_PROVIDER=ollama` is the only setting under which nothing leaves your
machine.** There the rewriter runs entirely locally, so no conversation content
is transmitted at all. Pointing `CLAUDISH_OLLAMA` at a remote/hosted endpoint
gives that up again.

Note that the default is the *same* destination your Claude Code session is
already talking to, which is why it was chosen as a default at all — it adds no
new party to the conversation. It does add *volume*: the display layer now sends
every assistant message back for a second pass. If that is not acceptable, set
`CLAUDISH_PROVIDER=ollama`.

---

## Layout

```
claudish-to-english/
├── .claude-plugin/
│   ├── plugin.json         # plugin manifest
│   └── marketplace.json    # so the repo can be added as a marketplace directly
├── hooks/
│   └── hooks.json          # MessageDisplay -> rewrite.sh ; Stop -> speak.sh ; PostToolUse -> rewrite-md.sh
├── rewrite.sh              # display-rewrite hook
├── rewrite-md.sh           # markdown-file rewrite hook (opt-in)
├── providers.sh            # provider layer (ollama/anthropic/openai/claude-cli), sourced by both hooks
├── speak.sh                # speech hook (opt-in, off by default)
├── speak-key.sh            # the rewrite->speech handoff key, sourced by rewrite.sh AND speak.sh
├── speak-child.py          # the detached speaker: waits, sanitizes, splits, synthesises, plays
├── speech/                 # sanitizer + sentence splitter, shared with the bench harness
├── tests/                  # payload fixture + standalone hook tests
├── CHANGELOG.md            # notable changes per version (Keep a Changelog)
├── LICENSE
└── README.md
```

## License

MIT — see [LICENSE](./LICENSE).
