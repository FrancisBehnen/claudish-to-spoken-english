# Does a local ollama serve two completions in parallel?

Research for [#4](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/4), part of [#1](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/1).
Investigated 2026-08-14 against ollama's source, docs, and release notes; llama.cpp's server and
benchmark docs; and the Anthropic/OpenAI platform docs. No third-party blog benchmarks were used.

---

## Verdict

**The parallel-LLM option collapses for this plugin as configured, and survives only in a
reconfigured form that is worse than it sounds.**

Three gates sit between "fire two requests at once" and "they genuinely run concurrently". The
plugin currently fails all three:

1. **Default is serial.** Since ollama v0.10.0 (2025-07-18) `OLLAMA_NUM_PARALLEL` defaults to `1`.
   Ollama holds a `semaphore.NewWeighted(numParallel)` in its own Go layer, so with the default the
   second request blocks in ollama *before it ever reaches the model*. This is fixable with an env
   var.
2. **The plugin's default model cannot do it at any setting.** `providers.sh` defaults to
   `gemma4:26b-mlx`. MLX models take ollama's MLX runner, which is a **single goroutine consuming an
   unbuffered channel, one request at a time**. `OLLAMA_NUM_PARALLEL` is not passed to that path and
   is not read by it. This is *not* fixable by configuration — only by switching the rewrite model
   to a GGUF build.
3. **Even on GGUF with 2 slots, the display rewrite gets slower.** Batched decoding is a
   *throughput* optimisation, not a *latency* one. On llama.cpp's own published sample numbers, two
   concurrent 128-token generations finish in 5.23 s versus 3.19 s for one alone — the user-visible
   rewrite takes ~64% longer so that the two together finish ~18% sooner than back-to-back. On a
   second published config the batch of two was a *net loss* against running them sequentially.

The minimum configuration under which "concurrent" is even literally true:
`OLLAMA_NUM_PARALLEL=2` **and** a GGUF (non-MLX) rewrite model. The cost is a doubled KV-cache
allocation and a materially slower on-screen rewrite. Given that the on-screen rewrite sits on the
`MessageDisplay` critical path and speech does not, **paying latency on the visible path to save
latency on the detached path is the wrong trade** — which points back at the deterministic
sanitizer, or at generating the speech variant *after* `emit`.

For the `anthropic` and `openai` providers pointed at a hosted endpoint, concurrency **is** real and
free of local contention — the question genuinely has a different answer there. The cost moves to
the bill.

---

## 1. ollama's request concurrency: defaults and what the knobs do

### The current defaults

From `envconfig/config.go` ([source](https://github.com/ollama/ollama/blob/main/envconfig/config.go)):

```go
// NumParallel sets the number of parallel model requests.
NumParallel = Uint("OLLAMA_NUM_PARALLEL", 1)
// MaxRunners sets the maximum number of loaded models.
MaxRunners = Uint("OLLAMA_MAX_LOADED_MODELS", 0)
// MaxQueue sets the maximum number of queued requests.
MaxQueue = Uint("OLLAMA_MAX_QUEUE", 512)
```

The FAQ ([docs/faq.mdx](https://github.com/ollama/ollama/blob/main/docs/faq.mdx), "How does Ollama
handle concurrent requests?") states them in prose:

> - `OLLAMA_MAX_LOADED_MODELS` - The maximum number of models that can be loaded concurrently
>   provided they fit in available memory. The default is 3 \* the number of GPUs or 3 for CPU
>   inference.
> - `OLLAMA_NUM_PARALLEL` - The maximum number of parallel requests each model will process at the
>   same time, default 1. Required RAM will scale by `OLLAMA_NUM_PARALLEL` \* `OLLAMA_CONTEXT_LENGTH`.
> - `OLLAMA_MAX_QUEUE` - The maximum number of requests Ollama will queue when busy before rejecting
>   additional requests. The default is 512

So the two knobs answer different questions and neither is a substitute for the other:

- **`OLLAMA_NUM_PARALLEL`** — how many requests **one loaded model** serves simultaneously. This is
  the knob that governs the ticket's question. Default `1`.
- **`OLLAMA_MAX_LOADED_MODELS`** — how many **distinct models** are resident at once (the sched.go
  default constant is `defaultModelsPerGPU = 3`,
  [sched.go:86](https://github.com/ollama/ollama/blob/main/server/sched.go)). It buys you nothing for
  two requests against the *same* model. It only helps if the speech rewrite uses a *different*
  model — which then costs a second full set of weights in memory.
- **`OLLAMA_MAX_QUEUE`** (512) — the depth of the waiting line. Its existence is itself the answer:
  ollama's contract for an over-subscribed model is *queue*, not *reject* and not *parallelise*. A
  second request against a `NUM_PARALLEL=1` model waits; it does not fail.

### The "auto" behaviour is gone — pinned down

`OLLAMA_NUM_PARALLEL` did historically auto-select. The change is precisely dated.

**PR [ollama/ollama#11330](https://github.com/ollama/ollama/pull/11330), "Reduce default parallelism
to 1"**, merged 2025-07-08, author's own description:

> The current scheduler algorithm of picking the paralellism based on available VRAM complicates the
> upcoming dynamic layer memory allocation algorithm. This changes the default to 1, with the intent
> going forward that **parallelism is explicit and will no longer be dynamically determinied**.
> Removal of the dynamic logic will come in a follow up.
>
> This behavior change should be release noted.

The diff changed three things at once — the env default `0`→`1`, the scheduler constant
`defaultParallel` `2`→`1`, and the FAQ line, which went from:

> The default will auto-select either 4 or 1 based on available memory.

to:

> The default is 1, and will handle 1 request per model at a time.

It shipped in **v0.10.0**, 2025-07-18, and was release-noted as promised
([release notes](https://github.com/ollama/ollama/releases/tag/v0.10.0)):

> - Parallel request processing now defaults to 1. For more details, see the FAQ

For context on where the feature came from, concurrency was introduced in **v0.2.0**, 2024-07-02
([release notes](https://github.com/ollama/ollama/releases/tag/v0.2.0)):

> Ollama can now serve multiple requests at the same time, using only a little bit of additional
> memory for each request.

**Bottom line: any guidance written before mid-2025 that says ollama parallelises by default is
stale.** As of current releases you get one request at a time per model unless you say otherwise.

### Where the serialization is actually enforced (GGUF path)

Two independent chokepoints, both in ollama's Go code, before llama.cpp is even involved.

**(a) Ollama's own admission semaphore.** `llm/llama_server.go`
([source](https://github.com/ollama/ollama/blob/main/llm/llama_server.go)) constructs the server with

```go
sem: semaphore.NewWeighted(int64(numParallel)),
```

and every completion, embedding, and rerank call acquires it first:

```go
if err := s.sem.Acquire(ctx, 1); err != nil { ... }
defer s.sem.Release(1)
```

With `numParallel == 1` there is exactly one permit. The display rewrite holds it; the speech
rewrite blocks on `Acquire` until the display rewrite's `defer` releases it. Not "shares the GPU
badly" — *blocked, in Go, having sent nothing*.

**(b) The runner is launched with matching slots.** The same file builds the llama-server argv:

```go
"-c", strconv.Itoa(launch.opts.NumCtx * launch.numParallel),
"-np", strconv.Itoa(launch.numParallel),
```

`-np` is llama.cpp's slot count
([llama.cpp server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)):
`-np, --parallel N` — "number of server slots". So even if you bypassed ollama's semaphore, the
downstream server has one slot.

The scheduler reads the env var once per load,
[sched.go:497](https://github.com/ollama/ollama/blob/main/server/sched.go):

```go
numParallel := max(int(envconfig.NumParallel()), 1)
```

and then forces it back to `1` in two cases: embedding-only models, and an architecture blocklist —
`mllama`, `qwen3vl`, `qwen3vlmoe`, `qwen35`, `qwen35moe`, `qwen3next`, `lfm2`, `lfm2moe`,
`nemotron_h`, `nemotron_h_moe`, `nemotron_h_omni` — with the comment "Some architectures are not safe
with num_parallel > 1", citing [issue #4165](https://github.com/ollama/ollama/issues/4165) (a
user-reported correctness bug, now encoded as shipped behaviour). Gemma is not on that list, so a
GGUF gemma build would honour `-np 2`. **A model on that list silently ignores your
`OLLAMA_NUM_PARALLEL` — it logs a warning and runs serially.** Worth knowing before picking a rewrite
model.

### The MLX path ignores all of it — and this is the plugin's default

`providers.sh` defaults the ollama provider to `gemma4:26b-mlx`:

```sh
*)         MODEL="${CLAUDISH_MODEL:-gemma4:26b-mlx}" ;;
```

Ollama routes MLX models to a separate runner. `Model.IsMLX()` is simply the model format
([server/images.go:85](https://github.com/ollama/ollama/blob/main/server/images.go)):

```go
func (m *Model) IsMLX() bool {
	return m.Config.ModelFormat == "safetensors"
}
```

and the scheduler branches on it
([sched.go:525, 588](https://github.com/ollama/ollama/blob/main/server/sched.go)) — the MLX client is
constructed as `mlxrunner.NewClient(modelName, req.opts.NumCtx)`, with **`numParallel` not passed at
all**.

The MLX runner itself is unambiguous
([x/mlxrunner/runner.go:221-257](https://github.com/ollama/ollama/blob/main/x/mlxrunner/runner.go)):

```go
func (r *Runner) Run(host, port string, mux http.Handler) error {
	g, ctx := errgroup.WithContext(context.Background())

	g.Go(func() error {
		for {
			select {
			case <-ctx.Done():
				return nil
			case request := <-r.Requests:
				err := r.runRequest(request)
				...
				close(request.Responses)
			}
		}
	})
	...
}
```

One goroutine. A blocking, synchronous `runRequest` per iteration. The next request is not even
*read* off the channel until the previous one's response channel is closed. And the channel is
unbuffered ([x/mlxrunner/server.go:62](https://github.com/ollama/ollama/blob/main/x/mlxrunner/server.go)):

```go
runner := Runner{
	Requests:  make(chan Request),
	mlxThread: worker,
}
```

so the HTTP handler blocks on `case runner.Requests <- request:` until the runner is free. There are
no slots, no continuous batching, and no `numParallel` anywhere in the package. `runRequest`
additionally funnels work through a single `mlxthread.Thread` (`r.mlxThread.Do(...)`), because MLX
requires its operations on one thread.

**Consequence: with the plugin's default model, `OLLAMA_NUM_PARALLEL=2` changes nothing. Two
simultaneous requests are strictly sequential, plus HTTP overhead.** This is the single most
important finding in this document, and it is not something the ollama FAQ tells you — the FAQ's
concurrency section describes the GGUF/llama.cpp path only.

---

## 2. Does concurrency win wall-clock time on one Apple Silicon machine?

Assume gate 2 is cleared (a GGUF rewrite model) and gate 1 is cleared (`OLLAMA_NUM_PARALLEL=2`).
Does `-np 2` actually buy time?

**The mechanism is real but it optimises the wrong quantity.** llama.cpp's server enables continuous
batching by default (`-cb, --cont-batching ... (default: enabled)`,
[server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)), so two
active slots have their decode steps merged into one batched forward pass rather than time-sliced.
That amortises the weight reads across both sequences — which is why the aggregate token rate rises.
It does **not** make either individual response arrive sooner than it would alone.

llama.cpp ships a benchmark specifically for this,
[`llama-batched-bench`](https://github.com/ggml-org/llama.cpp/blob/master/tools/batched-bench/README.md),
whose README defines `B` = number of batches (concurrent sequences), `T_TG` = time to generate all
batches, `S_TG` = text generation speed, `T` = total time. Its published sample results, first two
rows of the 128-prompt/128-generate block:

| PP | TG | B | N_KV | T_PP s | S_PP t/s | T_TG s | S_TG t/s | T s | S t/s |
|---|---|---|---|---|---|---|---|---|---|
| 128 | 128 | 1 | 256 | 0.108 | 1186.64 | 3.079 | 41.57 | 3.187 | 80.32 |
| 128 | 128 | 2 | 512 | 0.198 | 1295.19 | 5.029 | 50.90 | 5.227 | 97.95 |

Read that carefully, because it is exactly the throughput/latency distinction the ticket asks for:

- **Throughput went up.** `S_TG` 41.57 → 50.90 tok/s (×1.22). Two sequences' worth of tokens came out
  in 1.63× the time, not 2×. Batching is doing real work.
- **Latency went down — for the pair, not for either request.** Two requests back-to-back:
  2 × 3.187 = **6.37 s**. The same two batched: **5.23 s**. An **~18% wall-clock saving** on the pair.
- **The individual request got 64% slower.** A single 128-token generation that took **3.19 s** alone
  takes **5.23 s** when a sibling shares the batch.

That third line is the one that matters here. The display rewrite is on the `MessageDisplay`
critical path — it is what the user waits for. Attaching a speech call to it does not hide the speech
call's cost behind the display call; it *smears the speech call's cost onto the display call*. You'd
trade ~18% off a total the user never perceives for ~64% onto the number they do.

**Concurrency is not even reliably a net win.** The same README's JSONL example, from a different
configuration (`n_kv_max` 2048, `flash_attn` 0, 8 threads), shows batching losing outright:

```
{... "pp": 128, "tg": 128, "pl": 1, ... "t": 3.737494, "speed": 68.495094}
{... "pp": 128, "tg": 128, "pl": 2, ... "t": 11.528713, "speed": 44.410854}
```

Sequential: 2 × 3.737 = **7.47 s**. Batched: **11.53 s** — batching is **54% slower** than just doing
them one after the other. Whether `-np 2` helps or hurts is configuration-dependent, and the losing
case is not exotic.

Note also that the win, where there is one, comes from decode. **Prefill does not benefit**: `S_PP`
in the table is essentially flat (1186 → 1295 tok/s) while `T_PP` nearly doubles (0.108 → 0.198 s),
because prompt processing is compute-bound and two prompts genuinely compete. Both rewrite calls here
carry a full assistant message as input, so a meaningful share of the work is prefill — the half that
batching does *not* help.

> **Source caveat, stated plainly.** Both tables above are llama.cpp's own published sample output in
> its own repository — primary source, but the hardware is unspecified and is not stated to be Apple
> Silicon. I found **no primary-source batched-decode benchmark on Apple Silicon** from ollama or
> llama.cpp. The mechanism (continuous batching amortising weight reads) is documented; the *ratio*
> on this specific M-series machine is not, and the two published configs above disagree about the
> sign. **This is measurable locally in a few minutes** and should be measured before anyone leans on
> it — see "Not established" below.

One structural point that needs no benchmark: **one machine, one GPU.** Apple Silicon has a single
unified-memory GPU; ollama's Metal support is one device
([docs/gpu.mdx](https://github.com/ollama/ollama/blob/main/docs/gpu.mdx): "Ollama supports GPU
acceleration on Apple devices via the Metal API"). There is no second accelerator for the speech call
to run on. Whatever the two requests do, they divide one pool of compute and one pool of bandwidth —
and on the target machine they will be dividing it with a resident Kokoro server too.

---

## 3. The memory cost of parallel slots

`OLLAMA_NUM_PARALLEL=2` is not free, and ollama quantifies it exactly.

**Weights are not duplicated.** Both slots live in one runner process sharing one copy of the model —
hence v0.2.0's "using only a little bit of additional memory for each request".

**KV cache is duplicated, linearly.** The FAQ:

> Parallel request processing for a given model results in increasing the context size by the number
> of parallel requests. For example, a **2K context with 4 parallel requests will result in an 8K
> context and additional memory allocation**.
>
> `OLLAMA_NUM_PARALLEL` — ... **Required RAM will scale by `OLLAMA_NUM_PARALLEL` \*
> `OLLAMA_CONTEXT_LENGTH`.**

That is not a rule of thumb; it is literally the argv ollama builds
([llm/llama_server.go](https://github.com/ollama/ollama/blob/main/llm/llama_server.go)):

```go
"-c", strconv.Itoa(launch.opts.NumCtx * launch.numParallel),
```

and the scheduler's memory prediction agrees
([sched.go:793](https://github.com/ollama/ollama/blob/main/server/sched.go)):

```go
func effectiveLlamaServerContext(numCtx int, f *ggml.GGML, numParallel int) int {
	return effectiveModelContext(numCtx, f) * max(numParallel, 1)
}
```

**So `OLLAMA_NUM_PARALLEL=2` exactly doubles the KV-cache allocation.** In absolute terms that
depends on the default context ollama picks, which is now VRAM-tiered
([docs/context-length.mdx](https://github.com/ollama/ollama/blob/main/docs/context-length.mdx)):

> Ollama defaults to the following context lengths based on VRAM:
> - < 24 GiB VRAM: 4k context
> - 24-48 GiB VRAM: 32k context
> - \>= 48 GiB VRAM: 256k context

So the doubling is 4k→8k, 32k→64k, or 256k→512k of KV depending on the machine's tier. On a large
Mac the 32k or 256k tier makes "double the KV" a genuinely large number — and on Apple Silicon
"VRAM" *is* system RAM, so it comes straight out of the same pool as a resident Kokoro server, the
editor, and everything else. Relevant to [#1](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/1)'s
footprint budget: the parallel slot and Kokoro are competing for the same bytes, not for different
ones.

Two documented mitigations, if this path were ever taken:

- **Pin the context down.** `OLLAMA_CONTEXT_LENGTH=<small>` — a rewrite prompt is one assistant
  message, nowhere near 32k. Halving the context offsets the doubling from the extra slot exactly.
- **Quantise the KV cache.** `OLLAMA_KV_CACHE_TYPE=q8_0` — per the FAQ, "uses approximately 1/2 the
  memory of `f16` with a very small loss in precision, this usually has no noticeable impact on the
  model's quality (recommended if not using f16)". Default is `f16`. Requires Flash Attention, which
  ollama enables automatically where supported. `q4_0` is ~1/4 the memory with "a small-medium loss in
  precision".

One more consequence, easy to miss: **the KV allocation is fixed at model-load time, for the whole
session.** You pay the doubled cache continuously for as long as the model is resident, not only
during the two-request moment. For a plugin that fires a handful of short rewrites per conversation,
that is a permanent memory tax on an occasional overlap.

Finally, note what raising the setting does *not* do: `-kvu/--kv-unified` ("use single unified KV
buffer shared across all sequences") is documented as "default: enabled **if number of slots is
auto**". Ollama always passes an explicit `-np`, so slots are never auto and the unified-buffer
optimisation does not apply. The per-slot allocation is the real one.

---

## 4. Is the answer different for the `anthropic` and `openai` providers?

**Yes — and this is the one configuration where the parallel design genuinely works.**

Both cloud providers publish **rate limits, not concurrency limits.** Nothing in either doc caps
simultaneous in-flight requests; two `curl`s fired at once are two independent HTTPS connections
served by independently scaled infrastructure. There is no shared local GPU, no KV cache on your
machine, no semaphore.

**Anthropic** ([rate limits](https://platform.claude.com/docs/en/api/rate-limits)):

> The rate limits for the Messages API are measured in requests per minute (RPM), input tokens per
> minute (ITPM), and output tokens per minute (OTPM) for each model class.

Limits are enforced by token bucket ("your capacity is continuously replenished up to your maximum
limit"). At the Start tier, Claude Haiku 4.5 — the plugin's default anthropic model — is 1,000 RPM /
2,000,000 ITPM / 400,000 OTPM. Two simultaneous requests is a burst of two against a budget of a
thousand a minute: irrelevant. The one caveat worth carrying forward is documented:

> You might hit rate limits over shorter time intervals. For instance, a rate of 60 requests per
> minute (RPM) might be enforced as 1 request per second. Short bursts of requests can exceed the
> limit and trigger rate limit errors.

At 1,000 RPM a burst of two is far inside any sub-minute bucketing. It would matter only for a much
chattier caller. `providers.sh` already handles a 429 gracefully — `llm_notice_why` maps HTTP 429 to
"HTTP 429 from the endpoint — it may be down, overloaded, or rate-limiting", and the fail-open
contract holds.

**OpenAI** ([rate limits](https://developers.openai.com/api/docs/guides/rate-limits)): limits are
"RPM (requests per minute), RPD (requests per day), TPM (tokens per minute), TPD (tokens per day),
IPM (images per minute)", defined at organization and project level. The published documentation
contains **no per-account concurrency cap**.

**But `openai` in this plugin is not necessarily remote.** `providers.sh` documents the provider as
"any OpenAI-compatible `/chat/completions` endpoint (OpenAI, LM Studio, llama.cpp server, vLLM,
OpenRouter, ...)" and only requires a key for `api.openai.com`. If `CLAUDISH_OPENAI_URL` points at a
local llama.cpp server or LM Studio, **the whole of sections 1–3 applies again**, just with that
server's own slot setting instead of ollama's. For a bare `llama-server`, `-np` defaults to `-1`
(auto) rather than 1, and `--kv-unified` is then enabled by default — different defaults, same
physics: one machine, one GPU, KV cache per sequence. vLLM is a genuinely different animal
(purpose-built continuous batching) but is not a realistic single-Mac target.

So the correct framing is not "ollama vs cloud" but **"is the endpoint on this machine?"** If yes,
concurrency splits a fixed pie. If no, concurrency is free in time and costs money instead.

---

## 5. Token cost of the second call

The speech call roughly doubles per-message token consumption: the same assistant message goes in
twice as input, and two rewrites come out. Roughly 2× input and 2× output per displayed message.

**Local model (ollama, or `openai` pointed at localhost): $0, but not free.** No metering, no
account, no bill. The cost is denominated in the scarce resources of §2 and §3 — GPU time and unified
memory — and it is charged on a machine that will also be running a Kokoro TTS server. "Free but
slow" understates it slightly: it is free, and it *competes with the display rewrite for the same
compute*, which is exactly why §2's latency result matters more than its throughput result. A second
local call is not additive spend; it is a claim on the one resource the fail-open contract is
protecting.

**Hosted model: metered, and doubling is doubling.** At current list prices
([Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing)) the plugin's default
`claude-haiku-4-5` is **$1/MTok input, $5/MTok output**. The rewrite prompt plus one assistant message
is small — call it ~1k in / ~500 out per message, so ~$0.0035 per rewritten message — and adding a
speech call makes it ~$0.007. Small per message; it scales with every assistant turn of every session
all day, and it is a straight 2× on whatever the current bill is.

Two points worth making explicit for [#1](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/1):

- **This spend is separate from Claude Code's own.** The plugin's `CLAUDISH_ANTHROPIC_KEY` /
  `ANTHROPIC_API_KEY` is a metered API key, billed per token, independent of whatever plan drives the
  Claude Code session itself. A user on a subscription who sets a hosted provider for the rewrite is
  opting into a *new* meter, and the speech call doubles it.
- **Doubling the tokens does not double the value.** The two rewrites differ only in shape: one is
  read, one is heard. The design fork this research feeds — deterministic sanitizer versus second LLM
  call — is exactly the question of whether that shape difference is worth 2× tokens plus §2's
  latency. The token argument alone does not settle it; combined with §2 (the visible path gets
  slower) and §1 gate 2 (the default model cannot parallelise at all), it leans hard toward the
  sanitizer.

There is a cheap middle option the evidence supports: **prompt for both variants in one completion**
(one call, one prefill, structured output with a display section and a speech section). That pays
input tokens once instead of twice, needs no concurrency at all, and sidesteps every gate in §1. It
costs extra output tokens and some prompt complexity. Worth putting on the table in the sanitizer
decision as a third option rather than a binary.

---

## Not established

Named plainly, since these are the gaps a future session should close rather than assume:

1. **No primary-source batched-decode benchmark on Apple Silicon.** §2's ratios come from llama.cpp's
   own published sample tables on unspecified hardware, and the repo's two published configurations
   disagree about whether batching beats sequential at all. The mechanism is documented; the local
   number is not. **This is directly measurable** on the target Mac: run `llama-batched-bench` with
   `-npl 1,2`, or simply fire two `curl`s at ollama with `OLLAMA_NUM_PARALLEL=2` and a GGUF model and
   time them against two sequential ones. Anything that depends on the size of the win should wait for
   that measurement.
2. **No byte figure for the KV-cache doubling on `gemma4:26b`.** The *ratio* is exact and documented
   (`-c NumCtx × numParallel`), but the absolute megabytes depend on the model's layer count, KV-head
   count, and head dimension, which I did not confirm from a primary source. Moot for the default
   model anyway, since MLX never reaches this path. `ollama ps` reports the allocated context and
   size per loaded model and would settle it empirically.
3. **Which VRAM tier this Mac lands in.** The 4k/32k/256k default-context tiers key off how ollama
   reports available VRAM on Apple Silicon unified memory; I did not verify what figure it reports
   here. This determines whether "double the KV" is a small or a large number. `ollama ps` on the
   target machine answers it.
4. **Whether MLX parallelism is on ollama's roadmap.** The MLX runner lives under `x/` (an explicitly
   experimental tree) and has a `batch/` subpackage, so batched MLX inference may be in progress. I
   found no release note, issue, or doc committing to parallel request handling there. Treat MLX =
   serial as true-as-of-now, not permanent — but do not design against a future that isn't announced.

---

## Sources

All primary: ollama's source, docs, and release notes; llama.cpp's source docs; the Anthropic and
OpenAI platform docs.

**ollama**
- FAQ, "How does Ollama handle concurrent requests?" / KV cache quantization — https://github.com/ollama/ollama/blob/main/docs/faq.mdx
- `envconfig/config.go` (env defaults) — https://github.com/ollama/ollama/blob/main/envconfig/config.go
- `server/sched.go` (numParallel resolution, architecture blocklist, MLX branch, context prediction) — https://github.com/ollama/ollama/blob/main/server/sched.go
- `llm/llama_server.go` (admission semaphore, `-c` / `-np` argv) — https://github.com/ollama/ollama/blob/main/llm/llama_server.go
- `x/mlxrunner/runner.go` (single-goroutine request loop) — https://github.com/ollama/ollama/blob/main/x/mlxrunner/runner.go
- `x/mlxrunner/server.go` (unbuffered request channel) — https://github.com/ollama/ollama/blob/main/x/mlxrunner/server.go
- `server/images.go` (`IsMLX`) — https://github.com/ollama/ollama/blob/main/server/images.go
- Context length defaults — https://github.com/ollama/ollama/blob/main/docs/context-length.mdx
- GPU / Metal support — https://github.com/ollama/ollama/blob/main/docs/gpu.mdx
- PR #11330, "Reduce default parallelism to 1" — https://github.com/ollama/ollama/pull/11330
- Issue #4165 (architectures unsafe with num_parallel > 1; user report) — https://github.com/ollama/ollama/issues/4165
- Release v0.10.0 (default parallelism 1) — https://github.com/ollama/ollama/releases/tag/v0.10.0
- Release v0.2.0 (concurrency introduced) — https://github.com/ollama/ollama/releases/tag/v0.2.0

**llama.cpp**
- server README (`-np`, `-cb`, `--kv-unified`, slots) — https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
- batched-bench README (sample throughput/latency tables) — https://github.com/ggml-org/llama.cpp/blob/master/tools/batched-bench/README.md

**Hosted providers**
- Anthropic rate limits — https://platform.claude.com/docs/en/api/rate-limits
- Anthropic pricing — https://platform.claude.com/docs/en/about-claude/pricing
- OpenAI rate limits — https://developers.openai.com/api/docs/guides/rate-limits
