# The settled set: the confirmation listen for #11

The listening script for **ship blocker 1** of
[#11](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/11) — §13 row 1 of
[`speech-integration-spec.md`](speech-integration-spec.md):

> **The settled sanitizer combination has never been synthesized, and now contains a rule that does
> not exist** (§4.2) — what closes it: implement conditional boundary **B′** (§4.1), register the
> combination as one variant, one confirmation listen. **Blocks shipping: yes.**

Built 2026-08-25, on top of [`sanitizer-audition.md`](sanitizer-audition.md) (#8, seven axes) and
[`sanitizer-audition-13.md`](sanitizer-audition-13.md) (#13, three rules adopted 13–0).

**STATUS: two of the three steps are done; the third is the listener's.** B′ is implemented,
the combination is registered as `settled`, 24 wavs are synthesized and 14 pairs are on the page as
**section 5**. The [DECISION](#decision) block at the end is **empty**. Nothing below claims how
anything sounds.

**Everything before the DECISION is the instrument, and it stays that way.** Every "what it does" is
a text diff, a phoneme count, a byte count or a wav duration; every "what to listen for" is a
question nobody has answered.

---

## What was built

Two sanitizers, taking the registry from 26 to **28** **[repo]**:

| name | what it is | why it exists |
| --- | --- | --- |
| `lb-auto` | **rule B′** on `base` and nothing else | so the pair (`base`, `lb-auto`) isolates the new rule the same way every other pair on the page isolates its axis |
| `settled` | **all nine axes at their decided value, composed** | so the thing that would actually ship can be heard as one thing |

`settled` is the **only entry in `bench/sanitizers.py` that is a decision** rather than an
alternative, and the file's docstring now says so. Every other variant moves exactly one axis against
`base`, which is what made its pair readable.

### `settled`, axis by axis

| axis | value | rule | the margin it was adopted on |
| --- | --- | --- | --- |
| 1 backticks | `pause` | `tick-pause` | #8, 2–0 + 1 tie **[heard]** |
| 2 line breaks | `CONDITIONAL` | **rule B′** | the listener directly, 2026-08-25 — **never heard** |
| 3 paths | `shorten-nolead` | `path-short-nolead` | #13, 4–0 **[heard]** |
| 4 markdown | `strip` | rules C + D | #8, 5–0 **[heard]** |
| 5 `SCREAMING_SNAKE` | `lower` | rule J | #8, 7–0 **[heard]** |
| 6 URLs | `domain` | `url-domain` | #8, 2–0 **[heard]** |
| 7 code blocks | `count` | `cb-count` | #8, 4–0 **[heard]** |
| 8 flags | `pause` | `flag-pause` | #13, 4–0, **all four synthetic** **[heard]** |
| 9 `name.ext` | `word` | `ext-word` | #13, 5–0 **[heard]** |

**`base` already carries axes 4 and 5 at their settled value** **[repo]**, so a (`base`, `settled`)
pair moves **seven** axes, not nine. Rule L does not ship and `settled` does not set it.

---

## Rule B′, and the one place the spec contradicts itself

§4.1 of the spec is LOCKED, and this is an implementation of it — with **one deliberate departure**,
stated here rather than buried in a commit.

### The rule as implemented

> For a run of line-break-separated items, count the **boundaries** rule B is about to plant between
> two items. Replace the line breaks with **`, `** when that count is **≤ 3** and with **`. `** when
> it is **≥ 4**. A line already ending in a `BOUNDARY_CHARS` member keeps it, unchanged from rule B.
> A text with **no** boundary between two items has no run, and takes the fixed `opts.boundary`.

`bench/sanitizers.py`: `rule_Bprime_conditional`, `count_boundaries`, `COND_CUTOFF = 4`,
`Axes.boundary = "auto"`. The counting regex is rule B's own pattern with a lookahead, so the count
and the replacement cannot drift apart **[repo]**.

### The departure: boundaries, not segments

§4.1 states the count **twice, and the two statements disagree**:

- **§4's axis table and §4.1's evidence table count bullets.** `s38` is *"106 chars, 4 lines, 3
  bullets"* and takes `,`; `s37` is *"653 chars, 9 lines, 8 bullets"* and takes `.`.
- **§4.1's clause 3 counts segments** — *"the non-empty segments a `\n+` split produces"*.

Measured **[measured-here]**: `s38` has **4** non-empty `\n+` segments (a lead-in line plus three
bullets) and **3** boundaries between two items. `s37` has **9** segments and **8** boundaries.

So under clause 3 as written, **`s38` counts 4, takes `.`, and contradicts the one verdict in the
whole audition that chose `,`** — the verdict §4.1 cites in its own support. And it is not a one-item
slip. **On all eight bullet-carrying items in `corpus/spoken/`, the non-empty segment count strictly
exceeds the bullet count** **[measured-here]** — every one of them carries at least one line that is
not a bullet — so counting segments would make the conditional rule pick `.` for every list in the
corpus and collapse back onto `base`.

Counting boundaries (`segments − 1`) reproduces **both** discriminating verdicts, is marker-free, and
is the acoustically relevant quantity: the question the listener answered was how many stops in a row
a passage plants, not how many lines it has. That is what is implemented. **§4.1 clause 3 needs the
correction; §4's table row does not.**

### What "item" means for a paragraph run — the choice, and how thin its evidence is

**Chosen: the whole message is one run, and a paragraph break is counted exactly like a list break.
There is no blank-line special case.** That is §4.1 clause 3's own instruction — *"a paragraph-only
run of two long paragraphs therefore counts 2 and takes `,`"* — and under the boundary count that
pair of paragraphs plants 1 boundary and also takes `,`: the same outcome by different arithmetic.

**Rejected: blank lines delimiting runs**, so a bullet block and the prose around it get different
characters. It needs a rule for which character goes *at* a run boundary, and **there is no verdict
anywhere that bears on that**. It also contradicts clause 3 directly.

**The evidence here is one tie.** The only paragraph-heavy item ever auditioned on this axis is
`r09`, and its verdict was *"no audible difference"* **[heard]** #8. So **nothing about the paragraph
case is heard**, in either direction, and §15 of the spec already names it as the most likely place
the rule is wrong. This choice is the cheaper of the two to reverse — one function — and it is
recorded as unheard rather than defended.

### Rule A is untouched

`rule_A_guarantee_boundary` keeps `opts.boundary` (`.`) under `settled` **[repo]**. It is a length
guard on a 400-character run, not an enumeration, so the conditional does not reach it.

### The cutoff's position is still the listener's, and this does not move it

`COND_CUTOFF = 4` is one named constant. Its **position** is where the listener put it, not where a
wav proved it: the corpus's axis-2 evidence is `s38` at 3 and `s37` at 8 (§13 row 5). This document
does not try to settle it — but it does put **one** wav at the seam, which the corpus did not have
before: see `s04` below.

---

## How to listen

Section 5 of the same local page #8 and #13 were decided on.

```bash
cd ~/.local/share/kokoro/bench && python3 -m http.server 8765
# then open http://localhost:8765/audition.html   and scroll to Section 5
```

**Verified end to end 2026-08-25** **[measured-here]**: the page renders, all 24 section-5
`<audio src>` URLs resolve 200, a verdict click persists to `localStorage` under
`claudish-audition/v1` with the key `settled-set/<item>:<variant>`, the progress line moves 0 → 1 →
0 on click and un-click, and no other section's counter changes.

> **`localStorage` is per origin.** Verdicts recorded over `file://` are invisible over
> `http://localhost:8765` and the reverse. Pick one origin and stay on it. The #8 and #13 verdicts
> are already exported to [`audition-verdicts.tsv`](audition-verdicts.tsv) and
> [`audition-verdicts-13.tsv`](audition-verdicts-13.tsv), so a low counter costs nothing.

Regenerate anything — the wavs are **not committed** (37 MB for this set):

```bash
python3 bench/audition-page.py                                       # rebuild the page
bench/bench --id s03 -s base,settled -v bf_emma --show-text --play none
bench/bench --id r13 -s base,settled -v bf_emma \
  --out-dir ~/.local/share/kokoro/bench/audition-11 --play none      # how these were made
bench/bench --list-sanitizers                                        # all 28, with rule order
```

**The voice is `bf_emma`** — #9's winner, the same voice as section 4. A section-5 wav **is**
comparable with a section-4 wav and is **not** comparable with a section-1 wav (`af_heart`, rejected).

---

## The pairs

**14 pairs, 24 distinct wavs, 14.6 minutes of playthrough** **[measured-here]**. **Zero pairs are
phoneme-identical and zero are byte-identical** **[measured-here]** — every pair here is a real
difference, unlike #13's set where 6 of 20 were the same wav twice.

`base` is the reference on every pair, as in sections 1 and 4.

### Group A — the settled set, composed (10 pairs)

The confirmation listen proper. **This is not a re-vote on any axis** — every margin in the table
above stands. It is one question: **does any pair of settled rules interact badly when they land on
the same token?**

| pair | kind | what the composition puts on one token **[measured-here]** |
| --- | --- | --- |
| `r11:settled` | **real** | **the two artifacts below** — `` `$CLAUDISH_OLLAMA` `` → `, $, claudish_ollama,` and `` `curl -K` `` → `, curl , -K,`. Neither rule produces either alone |
| `r06:settled` | **real** | `` `docs/agents/issue-tracker.md` `` → `, agents/issue-tracker dot md,` — axis 1 + axis 3 + axis 9 on one token, the composition §4.2 names |
| `r06:none` | **real** | the untouched-text control for the same item |
| `r13:settled` | **real** | `cb-count` on two fenced blocks, plus `` `settings.json` `` → `, settings dot json,`. Audio drops **78.10 s → 60.39 s** |
| `r09:settled` | **real** | `url-domain` on a GitHub URL, inside an 11-boundary bullet-and-prose message |
| `r03:settled` | **real** | `settings.json` → `settings dot json` with no backticks anywhere — axis 9 alone on a real message |
| `s03:settled` | *synthetic* | five backticked spans, one of them `` `providers.sh` `` → `, providers dot sh,` |
| `s13:settled` | *synthetic* | `.claude/settings.json` → `claude/settings dot json` — axis 3 and axis 9 on one path |
| `s28:settled` | *synthetic* | five bare flags set off — `flag-pause`'s **only** carrier anywhere |
| `s38:settled` | *synthetic* | the whole set on the one item B′ changes |

**What to listen for.** `r11` first — it is the pair the text measurement already flagged, and the
question there is narrow: does a stranded "dollar" between two commas, and a `curl` split from its
`-K`, actually sound wrong, or does it pass unnoticed? Then the rest: a comma that lands where a full
stop was doing work; a span set off twice. `, hooks dot json,` — does the "dot" survive being wrapped
in axis 1's commas, or does the token turn into three pauses in a row? On `s28`, five commas in two
sentences: help, or stutter? That question was asked of `s28` in #13 and answered on `s28` alone;
nothing has changed it.

### Group B — rule B′, isolated (2 pairs, axis 2)

| pair | what it moves **[measured-here]** |
| --- | --- |
| `s38:lb-auto` | 3 boundaries → B′ picks `,` where `base` picks `.`. **This is the only corpus item where `lb-auto` differs from `base` at all** |
| `s04:lb-comma` | 4 boundaries → B′ picks `.`, which *is* `base`, so the pair is `base` against what B′ would ship **if the cutoff were 5** |

**What `s04` answers, and what it does not.** It is the seam: a lead-in line, three bullets and a
closing sentence — 4 boundaries, 3 bullets. It is the **first wav the corpus has ever had between 3
and 8** **[measured-here]**, and it is at the very edge of the gap, not in the middle. It answers
*"at 4 boundaries, is `.` right?"* — A/B, blind. It does **not** settle §13 row 5, which stays open.

It is also where the two possible counts diverge: **4 boundaries** (implemented → `.`) versus
**3 bullets** (the listener's phrasing → `,`). If `,` wins here, the count wants to exclude a
closing line, or the cutoff wants to be 5.

### Group C — triangulating the one composition §4.2 names (2 pairs)

`s03` carries `` `providers.sh` ``: a backticked span whose contents are a `name.ext`. Axis 1 and
axis 9 have each been heard on it alone; neither has been heard on it together.

| pair | what it moves |
| --- | --- |
| `s03:tick-pause` | axis 1 alone — the commas, no "dot" |
| `s03:ext-word` | axis 9 alone — the "dot", no commas |

With `s03:settled` in group A that is a three-way triangulation on one item: if the composition
sounds wrong, these two say **which half** is carrying it.

---

## Two interactions, found by text measurement before anyone listened

**These were not predicted; they fell out of running the composed pipeline over the corpus.** Both
are on `r11`, a **real** rewrite, and neither rule produces either of them on its own
**[measured-here]**:

| | `base` | `tick-pause` alone | `flag-pause` alone | `settled` |
| --- | --- | --- | --- | --- |
| `` `$CLAUDISH_OLLAMA` `` | `` `$claudish_ollama` `` | `, $claudish_ollama,` | *unchanged* | **`, $, claudish_ollama,`** |
| `` `curl -K` `` | `` `curl -K` `` | `, curl -K,` | *unchanged* | **`, curl , -K,`** |

**The mechanism is the rule order, and it is exactly the mechanism §4.2 warned about.** Axis 1
(`tick-pause`) **removes the backtick characters** before axis 8 (`flag-pause`) runs
(`_pipeline`: `rule_T_ticks` then `rule_S_bare_spans`) **[repo]**. `rule_S_bare_spans` steps *over*
backticked spans by design — that is what kept axis 8 independent of axis 1 in #13's pairs — but
after axis 1 has run there are no backticked spans left to step over. So:

- `_BARE_SPAN_RE`'s lookbehind is `(?<![\w/=.-])`, which does **not** include `$`, so the identifier
  matches with the sigil left outside and `_set_off` plants a comma between them.
- A multi-token span like `` `curl -K` `` is set off once by axis 1 and then **again, internally**, by
  axis 8 on the `-K`.

**Scope, measured over all 54 corpus items** **[measured-here]**: the stranded-`$` shape occurs on
**`r11` only, three times**; the split-inside-a-former-span shape occurs on **`r11` only, once**.
Every other place axis 8 fires under `settled` is a token that carried no backticks in the first
place, which is the shape #13 auditioned.

**Nothing here reopens an axis and nothing here is a claim about how it sounds.** `r11:settled` is on
the page precisely so the listener can decide whether "dollar, claudish ollama" and "curl, dash K"
are defects or noise. **If they are defects, the fix is a rule-scope change** — `$` added to
`_BARE_SPAN_RE`'s lookbehind, and/or axis 8 skipping a span axis 1 has already set off — **not a
re-vote on axis 1 or axis 8.**

---

## What this listen cannot settle, and two gaps it works around rather than hides

**`flag-pause`'s set of real carriers is different inside the settled set than outside it, and this
was not expected.** #13 measured the rule a no-op on all twelve real rewrites — byte-identical,
twelve for twelve — because every flag and `_`-joined identifier in them sat inside backticks, where
axis 8 steps over them **[heard]** #13; its follow-up note then found the corpus's first real
carrier on `r14`, an `exceed_context_size_error` inside a fenced block body. **Composition inverts
both** **[measured-here]**:

| item | `flag-pause` vs `base` | axis 8 inside `settled` | why |
| --- | --- | --- | --- |
| `r14` | **changes it** | **no-op** | axis 7 (`cb-count`) replaces the fenced block, so the token is gone before axis 8 sees it |
| `r11` | **no-op** | **changes it** | axis 1 strips the backticks the rule was stepping over |

So the one real carrier #13 recorded **disappears** inside the settled set, a different one
**appears**, and the only thing axis 8 does to real text under `settled` is the artifact above. The
rule's *intended* value still rests entirely on `s28` and three other synthetic items, and §4.3's
closing condition — a real capture with a bare flag outside backticks — is unchanged. **The claim
"it ships free of regression risk because it is a measured no-op on real text" is true of
`flag-pause` on `base` and is NOT true of `flag-pause` inside `settled`.** I expected it to carry
over; it does not.

**B′ is a measured no-op on every real rewrite in the corpus.** Across all 54 corpus items,
`lb-auto` differs from `base` on **exactly one** — `s38`, synthetic **[measured-here]**. On the 14
real rewrites it is **byte-identical, fourteen for fourteen**, because each of them either plants
4 boundaries or more (so B′ picks `.`, which is `base`) or ends every line in punctuation rule B
leaves alone. **This is the same gap class as `flag-pause`'s** and it is stated as one: the
conditional boundary, as specified and as implemented, changes nothing about any real message the
corpus has captured. Its value is a claim about shapes production has not produced yet.

**The 4–7 band is still nearly empty.** `s04` puts one wav at 4. Nothing exists at 5, 6 or 7.

**No axis is being re-decided.** If a pair here sounds wrong, the finding is the **interaction**, and
the fix is a rule-order or rule-scope change, not a re-vote.

**Nothing about `MD-FENCE-MULTI` improves.** `cb-count`'s line-count wording is still justified by
fixtures the corpus builder wrote; `r13` carries one, which is a real carrier for the *class* but not
for the wording.

---

## What §4.2 of the spec will need to say

**Not applied here** — #11 owns [`speech-integration-spec.md`](speech-integration-spec.md) and a
single integration pass folds this in. Recorded so that pass has the text.

1. **§13 row 1's first two clauses are done.** B′ is implemented (`bench/sanitizers.py`,
   `rule_Bprime_conditional`, selectable as `lb-auto`); the combination is registered as `settled`;
   24 wavs exist under `~/.local/share/kokoro/bench/audition-11/` and 14 pairs are section 5 of the
   audition page. **The row stays open until the listen happens**, and the listen is the listener's.
2. **§4.1 clause 3 is wrong as written and needs replacing.** *"the non-empty segments a `\n+` split
   produces"* makes `s38` count 4 and take `.`, contradicting the `s38` verdict the same section
   cites as evidence. The implemented count is of **boundaries between two items** — `segments − 1` —
   which reproduces both discriminating verdicts. §4's axis-table row is unaffected.
3. **§4.1's "no registered sanitizer implements this" is now false** and its consequence — *"the
   settled-set confirmation listen cannot include axis 2 until rule B′ exists"* — is discharged.
4. **A new caveat, of §4.3's class, belongs next to §4.3.** B′ is a **measured no-op on all 14 real
   rewrites and on 53 of the 54 corpus items**; the only item it changes is `s38`. Its closing
   condition is the same shape as `flag-pause`'s: a real capture with a short list whose lines do not
   already end in punctuation.
5. **§13 row 5 is unchanged but slightly better funded.** One wav now exists at 4 boundaries (`s04`,
   `base` against `lb-comma`). 5, 6 and 7 are still empty.
6. **A finding §4.2 predicted and did not name: two interactions exist, and they are on a real
   item.** Axis 1 strips the backticks axis 8 relies on stepping over, so inside `settled` — and only
   inside `settled` — `` `$CLAUDISH_OLLAMA` `` becomes `, $, claudish_ollama,` and `` `curl -K` ``
   becomes `, curl , -K,`, both on `r11`, both **measured, neither heard**. §4.3's *"ships free of
   regression risk, a measured no-op on all twelve real rewrites"* is true of `flag-pause` on `base`
   and **false of `flag-pause` inside the settled set**; that sentence needs the qualifier. The
   inversion is symmetric and worth carrying: axis 7 removes `r14`'s carrier before axis 8 sees it,
   so **`r14` is a no-op inside `settled`** while `r11` is not.
7. **§15's "axis 2 … the most likely error is on paragraph runs" stands, and now names a choice**:
   one run per message, paragraph breaks counted like list breaks, no blank-line special case — the
   §4.1 clause-3 reading, adopted with its evidence (`r09`, a tie) stated as thin.

---

## Appendix: what was measured

All of it here, none of it heard. Reproduce with the commands under [How to listen](#how-to-listen).

**Registry.** 28 sanitizers **[repo]**.

**Text reach, over all 54 items of `corpus/spoken/`** **[measured-here]**:

| comparison | items changed | of which real |
| --- | ---: | ---: |
| `settled` vs `base` | 29 of 54 | 13 of 14 (`r02` is the exception) |
| `lb-auto` vs `base` | **1** of 54 (`s38`) | **0** of 14 |
| `lb-comma` vs `base` | 17 of 54 | 7 of 14 |
| `settled` vs `settled` with axis 8 off | 6 of 54 | **1** of 14 (`r11`, and only the artifact) |

**No regression in the 26 that already existed.** Ran every pre-existing variant over all 54 corpus
items under both `--boundary .` and `--boundary ,`, old file against new: **byte-identical, 26 for
26** **[measured-here]**. The only shared code that moved is rule B's pattern, hoisted to a module
constant so B′ counts exactly what B replaces.

**Crash safety.** Phonemised every item under both `base` and `settled` with kokoro-onnx's own
tokenizer and split it with `Kokoro._split_phonemes`: the worst batch under `settled` is **509**
phonemes (`r13`), and **nothing exceeds 510** **[measured-here]**. No synthesis, no model load. Both
`.` and `,` are members of `BOUNDARY_CHARS`, which is that splitter's own set, so B′ switches prosody
without ever changing whether the text chunks **[repo]**.

**Audio.** 24 wavs, 37 MB, `bf_emma`, uncommitted **[measured-here]**:

| item | `base` | `settled` | other |
| --- | ---: | ---: | --- |
| `r03` | 19.03 s | 19.11 s | |
| `r06` | 32.73 s | 32.47 s | `none` 33.09 s |
| `r09` | 62.53 s | 62.91 s | |
| `r11` | 142.51 s | 143.17 s | |
| `r13` | 78.10 s | **60.39 s** | |
| `s03` | 11.18 s | 11.84 s | `tick-pause` 11.43 s · `ext-word` 11.50 s |
| `s04` | 12.48 s | — | `lb-comma` 12.35 s |
| `s13` | 10.05 s | 10.13 s | |
| `s28` | 8.73 s | 9.09 s | |
| `s38` | 6.02 s | 5.99 s | `lb-auto` 5.99 s |

**`r13` is the only item where the settled set changes duration by more than a second**, and the
17.71 s it removes is `cb-count` skipping two fenced blocks — an axis #8 settled 4–0, not a new
effect.

**Not measured here, and not claimed:** TTFA. The `bench` runs above synthesize the **whole** message
with no first-sentence pipelining, so their TTFA column is a full-synthesis time and says nothing
about §4's 0.86 s median, which is a pipelined, warm, resident-worker number
([`voice-and-pipelining.md`](voice-and-pipelining.md)). Nothing in this document bears on §10.5.

---

## DECISION

*Empty. The confirmation listen has not happened.*

**What closes it:** play section 5 blind, record a verdict on each of the 14 pairs, export the TSV
from the page's Export panel to `docs/decisions/audition-verdicts-11.tsv`, and write the outcome
here.

**What a clean result means:** no axis reopens, §13 row 1 closes, and the sanitizer that ships is
`settled` exactly as registered.

**What a dirty result means:** the finding is an **interaction**, named by which pair carried it —
and group C exists so that a bad `s03:settled` can be attributed to axis 1 or axis 9 rather than
argued about. For `r11` the attribution is already done, in text, above.
