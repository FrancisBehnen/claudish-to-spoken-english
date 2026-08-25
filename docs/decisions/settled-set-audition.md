# The settled set: the confirmation listen for #11

The listening script for **ship blocker 1** of
[#11](https://github.com/FrancisBehnen/claudish-to-spoken-english/issues/11) — §13 row 1 of
[`speech-integration-spec.md`](speech-integration-spec.md):

> **The settled sanitizer combination has never been synthesized, and now contains a rule that does
> not exist** (§4.2) — what closes it: implement conditional boundary **B′** (§4.1), register the
> combination as one variant, one confirmation listen. **Blocks shipping: yes.**

Built 2026-08-25, on top of [`sanitizer-audition.md`](sanitizer-audition.md) (#8, seven axes) and
[`sanitizer-audition-13.md`](sanitizer-audition-13.md) (#13, three rules adopted 13–0).

**STATUS: all three steps are done. The listen happened 2026-08-25, blind, `bf_emma`** — 14 pairs
scored: thirteen in one sitting and `r11` in a single-pair re-listen afterwards. The committed export
[`audition-verdicts-11.tsv`](audition-verdicts-11.tsv) holds **all 14 of section 5's pairs scored**,
and is the one artifact for the round. **`settled` won every pair it was in, 9–0.**
Read the [DECISION](#decision) for the outcome, including **two named open gaps and one open item**:
the B′ cutoff, which the listen contradicted; a slash-terminated path, which the listen discovered;
and B′'s count, which knowingly disagrees with locked spec text that #11 has to amend.

**Everything before the DECISION is still the instrument.** Every "what it does" outside the DECISION
is a text diff, a phoneme count, a byte count or a wav duration, and every "what to listen for" is
the question as it was asked — not its answer. The two exceptions are labelled: the axis-2 row of the
table below now carries its heard margin like every other row, and the sections the DECISION
supersedes say so inline and point at it.

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
| 2 line breaks | `CONDITIONAL` | **rule B′** | #11, 1–0 on `s38`, B′ as shipped **[heard]** — but see the cutoff gap in the [DECISION](#decision) |
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
`Axes.boundary = "auto"`. **`count_boundaries` iterates rule B's own compiled pattern,
`_B_BREAK_RE`, and subtracts only the one intentional exclusion — a match reaching the end of the
text** — so a change to what rule B treats as a break flows into the count instead of having to be
mirrored **[repo]**.

> **Corrected 2026-08-25, from review on [PR #24](https://github.com/FrancisBehnen/claudish-to-spoken-english/pull/24).**
> This sentence previously claimed the count "is rule B's own pattern with a lookahead, so the count
> and the replacement cannot drift apart". That was **false**: it was a second, independently typed
> pattern, and it did already disagree with rule B. On the text `"a\n \n b"` rule B plants one
> boundary and the old count returned **0** **[measured-here]**. The count now reads `_B_BREAK_RE`
> itself, which makes the no-drift claim structural rather than asserted. **The fix is a no-op on
> the corpus** — all 28 sanitizers byte-identical over all 54 items under both `--boundary .` and
> `--boundary ,`, and no item's boundary count changed **[measured-here]** — so every measurement and
> every wav in this document still stands.

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

#### Say it without the euphemism: the code is currently OUT OF CONTRACT

"Departure" is too soft for what this is, so state it flatly. **§4.1 is LOCKED, clause 3 is part of
it, and `count_boundaries` does not implement clause 3.** The spec's own words are *"the items of a
run are the non-empty segments a `\n+` split produces"* with *"`. ` if the count is `≥ 4`"*
(`speech-integration-spec.md` §4.1, the rule block and qualification 3) **[repo]**. On `s38` that is
4 items and demands `.`; `settled` emits `,` **[measured-here]**. **That is a live violation of a
locked clause, on a real registered sanitizer, and it is not resolved by this document.**

It is nonetheless the right code, and the reason is that **clause 3 contradicts the other two
statements of the same rule in the same section**. §4.1 has three: the rule block (*"count the items
the run holds"*, ≤3 → `,`), qualification 1 (*"`s38` at 3 bullets picks `,`"* — cited as the verdict
the cutoff rests on), and qualification 3 (items = segments). **Under qualification 3, `s38` counts 4
and takes `.` — the opposite of what qualification 1 says the listener chose.** Clause 3 is the odd
one out, and as of this listen it is also the one the listener has overruled by ear: `s38:lb-auto`
won blind **[heard]**.

**Clause 3 is wrong at both ends, not merely mis-cutoffed** **[measured-here]**:

| what clause 3 says, read literally | scope in `corpus/spoken/` | what the implementation does |
| --- | --- | --- |
| a list's segments include its lead-in line, so **every list counts ≥ 4 and takes `.`** | **8 of 8** bullet-carrying items — segments strictly exceed bullets on every one | boundaries, so `s38` takes `,`; B′ can actually fire on a short list |
| a one-line message is **1 item, so ≤ 3, so `,`** — it would end on a comma | **31 of 54** items are single-segment | no boundary between two items means no run, so the fixed `opts.boundary` (`.`) applies — the `s35` branch |

So on lists clause 3 makes B′ pick `.` for **every list in the corpus**, collapsing it onto `base` and
buying nothing — B′ would never once fire the `,` it exists to produce. **That is the collapse claim,
and it is about lists specifically**; across all 54 items clause 3 does *not* simply reduce to `base`,
because at the other end it would put a comma at the end of 31 one-line messages, which is a second
and arguably worse defect. **A correct amendment has to fix both**, which is why the proposed
replacement text in [what §4.2 will need to say](#what-42-of-the-spec-will-need-to-say) carries a
no-run sentence as well as the boundaries change.

**Whose job this is.** #11 owns `speech-integration-spec.md` and this document must not edit it, so
**the divergence stays open until #11 accepts the clause 3 amendment.** Until then the honest state is:
*the implementation knowingly contradicts a locked clause, the listen is the evidence that the
implementation is the side that is right, and the clause is the thing that has to move.* Recorded
here rather than silently carried.

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

> **Superseded by the [DECISION](#decision).** `s04` was heard, and it went **against** the value in
> the file. The cutoff is still not settled, but it is no longer merely unaudited — it is now
> contradicted at 4 by the only wav that has ever tested it.

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
> [`audition-verdicts-13.tsv`](audition-verdicts-13.tsv), and #11's to
> [`audition-verdicts-11.tsv`](audition-verdicts-11.tsv), so a low counter costs nothing.

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

> **`,` won.** That conditional is discharged in the [DECISION](#decision), which is where the
> consequence is written down.

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

1. **§13 row 1 closes.** All three clauses are done: B′ is implemented (`bench/sanitizers.py`,
   `rule_Bprime_conditional`, selectable as `lb-auto`); the combination is registered as `settled`;
   24 wavs exist under `~/.local/share/kokoro/bench/audition-11/`; and **the confirmation listen
   happened 2026-08-25, blind, `bf_emma`, with `settled` preferred on all nine pairs it was in**
   **[heard]** ([`audition-verdicts-11.tsv`](audition-verdicts-11.tsv)). The row closes on the
   composition. It does **not** close §13 row 5, and it does not close the two gaps the
   [DECISION](#decision) names.
2. **§4.1 clause 3 must be amended, and this is the one item here that is a REQUIRED CONTRACT CHANGE
   rather than a note.** *"the non-empty segments a `\n+` split produces"* makes `s38` count 4 and
   take `.`, contradicting the `s38` verdict the same section cites as evidence. The implemented count
   is of **boundaries between two items** — `segments − 1`.

   **Until #11 accepts this amendment, the implementation is out of contract with locked text.** The
   divergence is live, not theoretical: `settled` emits `,` on `s38` where clause 3 demands `.`
   **[measured-here]**. **The code is not being changed to match**, and the reason is on the record —
   clause 3 contradicts §4.1's own rule block and its own qualification 1, and the listener has now
   overruled it by ear. The full statement of the violation, its scope at both ends of the clause, and
   why the code is the side that is right is under [out of
   contract](#say-it-without-the-euphemism-the-code-is-currently-out-of-contract). **The amendment is
   the fix; a code change would be the bug.**

   **What the listen settles, exactly.** Across all 54 corpus items, **`s38` is the only one where the
   two readings produce a different character at all** **[measured-here]** — everywhere else both land
   on the same side of the cutoff, `s04` (4 boundaries / 5 segments → `.` either way) and `s37`
   (8 / 9 → `.` either way) included. So `s38` is the whole discriminator, and **`s38` was played
   blind and went to the boundaries implementation**: B′'s `,` beat `base`'s `.` **[heard]**, where
   the segment count would have produced `base`'s `.`. That is the reading confirmed by ear, on the
   one pair that can confirm it. `s04` bears on the **cutoff**, not on this choice, and it is recorded
   under item 5. §4's axis-table row is unaffected. **Proposed replacement for clause 3:**

   > Count the **boundaries** a run plants between two items — equivalently, the non-empty segments a
   > `\n+` split produces, **minus one**. A break at the very end of the text separates the last item
   > from nothing and is not counted. Replace the line breaks with `, ` below the cutoff and `. ` at
   > or above it. A text with no boundary between two items has no run and takes the fixed boundary.
   > A paragraph break is counted exactly like a list break; two long paragraphs therefore count 1.

   The worked example in clause 3 — *"a paragraph-only run of two long paragraphs therefore counts 2
   and takes `,`"* — needs its number changed from 2 to **1**. The outcome (`,`) is unchanged.

   **The no-run sentence in that replacement is load-bearing and is not cosmetic.** Clause 3 read
   literally makes a one-line message **1 item**, therefore `≤ 3`, therefore `,` — so it would end
   **31 of the 54 corpus items** on a comma **[measured-here]**. The implementation instead treats "no
   boundary between two items" as "no run" and applies the fixed `opts.boundary`. An amendment that
   only swaps *segments* for *boundaries* and stops there would leave that end broken, because 0
   boundaries is also `≤ 3`. Both halves have to land together.
3. **§4.1's "no registered sanitizer implements this" is now false** and its consequence — *"the
   settled-set confirmation listen cannot include axis 2 until rule B′ exists"* — is discharged.
   Axis 2's **"never heard"** caveat comes off: B′ as shipped was played in isolation against `base`
   on `s38` and won **[heard]**.
4. **A new caveat, of §4.3's class, belongs next to §4.3.** B′ is a **measured no-op on all 14 real
   rewrites and on 53 of the 54 corpus items**; the only item it changes is `s38`. Its closing
   condition is the same shape as `flag-pause`'s: a real capture with a short list whose lines do not
   already end in punctuation. **The listen does not discharge this** — the one item that carries the
   rule is synthetic, so what was confirmed is the rule's direction, not its reach.
5. **§13 row 5 stays open and now has evidence pointing away from the shipped constant.** One wav
   exists at 4 boundaries (`s04`, `base` against `lb-comma`) and **`,` won it, blind** **[heard]** —
   against `COND_CUTOFF = 4`, which picks `.` there. 5, 6 and 7 are still empty. See the
   [DECISION](#decision)'s cutoff gap for why the constant was not simply moved.
6. **A finding §4.2 predicted and did not name: two interactions exist, they are on a real item, and
   they have now been heard and tolerated.** Axis 1 strips the backticks axis 8 relies on stepping
   over, so inside `settled` — and only inside `settled` — `` `$CLAUDISH_OLLAMA` `` becomes
   `, $, claudish_ollama,` and `` `curl -K` `` becomes `, curl , -K,`, both on `r11`
   **[measured-here]**. **`r11:settled` was then played blind and `settled` won** **[heard]**: the
   artifacts did not cost the pair. That is *tolerated*, not *absent* — one listener, one item, and
   the shapes remain in the output. §4.3's *"ships free of regression risk, a measured no-op on all
   twelve real rewrites"* is true of `flag-pause` on `base` and **still false of `flag-pause` inside
   the settled set**; that sentence needs the qualifier regardless of `r11`'s verdict, because the
   other half of the inversion was never played: axis 7 removes `r14`'s carrier before axis 8 sees
   it, so **`r14` is a no-op inside `settled`** while `r11` is not.
7. **§15's "axis 2 … the most likely error is on paragraph runs" stands, and now names a choice**:
   one run per message, paragraph breaks counted like list breaks, no blank-line special case — the
   §4.1 clause-3 reading, adopted with its evidence (`r09`, a tie) stated as thin. **The listen does
   not improve this**: no paragraph-heavy item was played on axis 2.
8. **§4.3 needs a new open condition that no section currently carries: a slash-terminated path.**
   Found by ear on `r06` during this listen **[heard]**, not by any measurement here. Axis 3 ships as
   `path-short-nolead` and **no path rule looks at a trailing `/`** **[repo]**. Details, mechanism and
   a candidate rule are in the [DECISION](#decision); nothing is implemented.

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

**Re-run after BOTH PR-review fixes to rule B** — the `count_boundaries` rewrite (see [the rule as
implemented](#the-rule-as-implemented)) and the blank-line fix to `_B_BREAK_RE` below. Same
comparison, widened to **all 28** including `lb-auto` and `settled`, both boundary settings, measured
against the pre-review commit: **byte-identical, 28 for 28 over 54 items**, and **no item's boundary
count changed** — `s38` 3, `s04` 4, `s37` 8 before and after **[measured-here]**. Checked directly
rather than by inference: the **24 distinct wavs behind the 14 scored pairs** are byte-identical for
byte-identical input, so **no wav was re-synthesized and every duration in the table below is still
the duration of the file that was heard** **[measured-here]**. Live re-synthesis of `s38` under
`base`, `lb-auto` and `settled`: **3 OK, 0 CRASH, 0 ERROR**, one batch of 112 phonemes each, same
durations as the heard files **[measured-here]**.

**The second fix was a real bug, and it is worth stating rather than folding into a regression line.**
`_B_BREAK_RE` was `(\S)[ \t]*\n+[ \t]*`, and `\n+` **stops at the first line that is blank only to
the eye**. A "blank" line holding a single space or tab therefore split the run, and rule B left a
**raw newline in its own output**: `"a\n \n b"` sanitized to `"a. \n b"` **[measured-here]** — the
`SPLIT-NEWLINE` hazard rule B exists to remove, produced by rule B. It is now
`(\S)[ \t]*(?:\n[ \t]*)+`, which takes a whole run of breaks however they are padded; the leading-break
strip got the same spelling. **Scope, and this is the reason the listen is untouched: no item in
`corpus/spoken/` contains a whitespace-only line, so the bug could not fire on anything auditioned,
and no sanitized output of any of the 28 variants over any of the 54 items contains a newline either
before or after the fix** **[measured-here]**. It was latent, not harmless — real assistant text is
not guaranteed to be tidy — and it is the same input that exposed the `count_boundaries` drift, which
is how it was found.

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

**The listen happened. `settled` ships.** Section 5 was played blind on **2026-08-25**, voice
`bf_emma`, **all 14 pairs scored** — thirteen between **15:18 and 15:54 UTC** and `r11` in a
single-pair re-listen afterwards. The export is committed at
[`audition-verdicts-11.tsv`](audition-verdicts-11.tsv) **[repo]**; it is that file, not this prose,
that is the record.

**`settled` won every pair it was in: 9–0** **[heard]**.

| pair | verdict | preferred |
| --- | --- | --- |
| `r03:settled` | B is better | **`settled`** |
| `r06:settled` | B is better | **`settled`** |
| `r09:settled` | A is better | **`settled`** |
| `r11:settled` | B is better | **`settled`** |
| `r13:settled` | A is better | **`settled`** |
| `s03:settled` | A is better | **`settled`** |
| `s13:settled` | B is better | **`settled`** |
| `s28:settled` | B is better | **`settled`** |
| `s38:settled` | B is better | **`settled`** |

Nine for nine, five of them **real** rewrites, and the composition was never once beaten by `base`.
Sides alternated across the nine — `settled` was A on three and B on six **[repo]** — so the sweep is
not a side bias.

**The sanity pair passed.** `r06:none`, `base` against untouched text: **`base` preferred**
**[heard]**. Sanitizing beats raw. The instrument was measuring something.

### What this closes

1. **No axis reopens.** Every margin in [the axis-by-axis table](#settled-axis-by-axis) stands, and
   nothing here is a re-vote. That was the precondition for a clean result and it held.
2. **§13 row 1 closes.** B′ exists, the combination is registered, the confirmation listen happened.
   All three clauses discharged.
3. **The sanitizer that ships is `settled` exactly as registered** — the nine axis values in that
   table, composed in `_pipeline`'s order, no edits. **Two qualifiers, neither of them a change to the
   composition:** the *cutoff constant inside* B′ is now contradicted by the only wav that has ever
   tested it (gap 1), and B′'s **count** contradicts §4.1 clause 3's locked wording, deliberately and
   with the listen as the reason (the [open item](#open-item-settled-ships-out-of-contract-with-41-clause-3-on-purpose)).
4. **Axis 2's "never heard" caveat comes off.** B′ as shipped was heard in isolation against `base` on
   `s38` and won **[heard]**. Axis 2 is no longer the one axis adopted without a wav behind it.
5. **The boundaries reading of §4.1 clause 3 is confirmed by ear**, on the single corpus item that can
   confirm it. `s38` is the only one of 54 where the segment count and the boundary count produce
   different characters **[measured-here]**, and it went to boundaries. The proposed replacement text
   is item 2 of [what §4.2 will need to say](#what-42-of-the-spec-will-need-to-say).
6. **Group C's triangulation came back consistent, not diagnostic.** `s03:tick-pause` → **`tick-pause`
   preferred**; `s03:ext-word` → **`ext-word` preferred** **[heard]**. Both halves of the composition
   §4.2 names win alone on `s03`, and the whole thing wins on `s03` too. There was no bad pair to
   attribute, so the triangulation was never needed — it is recorded as a negative result, which is
   the outcome it was built to be able to have.
7. **`r11`'s measured interaction was heard and did not cost the pair.** `r11` is the item carrying
   the axis-1 × axis-8 artifacts — `` `$CLAUDISH_OLLAMA` `` → `, $, claudish_ollama,` and
   `` `curl -K` `` → `, curl , -K,`, produced by neither rule alone. Blind, **`settled` still beat
   `base` on `r11`** **[heard]**. **State that at its real strength:** the artifacts were not audible
   enough to lose a pair, on one item, to one listener. That is **tolerated, not harmless**. The
   shapes are still in the output, they are still the mechanism §4.2 warned about, and §4.3's
   *"ships free of regression risk, a measured no-op on all twelve real rewrites"* is **still false as
   written** — because its other half, the `r14` no-op where axis 7 eats the carrier before axis 8
   sees it, was never played in this listen at all. The fix, if it is ever wanted, remains a
   rule-scope change, not a re-vote.

### Open gap 1 — the cutoff is contradicted at 4, and was not moved

**`s04:lb-comma` → `lb-comma` preferred, blind** **[heard]**. This is the one result of the round that
goes against the file.

`s04` is the seam and the corpus's only wav between 3 and 8 boundaries. It has **4** boundaries, so
B′ as shipped picks `.` — which on this item is byte-identical to `base` **[measured-here]**. The pair
was therefore `base`/`settled`'s character against the comma, and **the comma won**. The document
wrote the conditional down in advance: *"If `,` wins here, the count wants to exclude a closing line,
or the cutoff wants to be 5."*

**`COND_CUTOFF` is left at 4** — deliberately, and this is the decision, not an omission:

- **One wav cannot pick between the two repairs.** `s04` is *"a lead-in line, three bullets and a
  closing sentence"*: 4 boundaries, 3 bullets. A cutoff of 5 explains the verdict. So does a count
  that excludes a trailing non-list line, which would make `s04` count 3. **Both predict `,` here**,
  and they diverge on shapes the corpus does not contain. Moving the constant would silently pick one.
- **It is one wav at the very edge of a gap that is still empty at 5, 6 and 7.** §13 row 5 asked for
  the band to be filled; it now has one point, at one end.
- **Changing it would invalidate the sweep above.** `lb-comma` differs from `base` on 17 of 54 items
  **[measured-here]**, so a cutoff of 5 changes what `settled` does to items in group A that were
  just heard as `settled`. That is a new set, not an amendment to this one.

**So: §13 row 5 stays open, and it is no longer merely unaudited — it is contradicted at 4.** The next
listen on this axis wants wavs at 5, 6 and 7, and an `s04` variant with the closing line removed to
separate the two repairs. The constant is one named line in `bench/sanitizers.py`, and the comment
there now carries the verdict against it **[repo]**.

### Open gap 2 — a slash-terminated path has no pause, found by ear in a shipped axis

**This is the round's genuinely new finding, and it came from the listener, not from a measurement.**
Recorded verbatim, on the `r06:none` pair:

> I think a pause is needed after the path if a `path/` ends with a slash. Now it sounds like
> `research/branches`

**What is in the text.** `r06` says *"save their work to local `` `research/*` `` branches"*. Under
`base`, axis 4's markdown strip removes the `*` and leaves `` `research/` ``; the slash is silent, so
"research" runs straight into "branches" and the ear reconstructs a two-segment path,
`research/branches` — a path that is not in the message **[measured-here]**.

**Which rule owns it: axis 3, `path-short-nolead`, and it does not fire at all.** `_PATH_RE` requires
`(?:SEG/)+SEG`, so a slash-*terminated* path is never matched as one unit **[repo]**:

| input | `settled` output | why |
| --- | --- | --- |
| `research/` | `research/` | no match — nothing follows the final `/` |
| `~/research/` | `~/research/` | same |
| `docs/decisions/notes/` | `decisions/notes/` | matches `docs/decisions/notes`, the trailing `/` sits outside the match and survives |

**There is no trailing-slash handling anywhere in `bench/sanitizers.py`** — no `endswith("/")`, no
`rstrip("/")`, nothing **[repo]**. So this is a real gap in an axis that ships, at `4–0` **[heard]**,
and the gap was invisible to every measurement in this document.

**Why it did not sink `r06:settled`, and why that is not a defence.** On `r06` the token is
*backticked*, so axis 1 (`tick-pause`) sets it off and the settled output is `, research/, branches` —
there *is* a pause, supplied by a different axis, by luck **[measured-here]**. A slash-terminated path
**outside** backticks gets nothing: `settled` leaves *"Saved to research/ branches"* exactly as it is
**[measured-here]**. The defect is latent in the shipped set and `r06` happens not to expose it.

**Candidate rule, a sketch and nothing more.** After rule P, append a `BOUNDARY_CHARS` member — `,`,
for the same reason axis 1 and axis 8 use one — to a path token that ends in `/`, so the following
word cannot fuse onto it. Two things would have to be settled first: `_PATH_RE` has to be widened to
*see* a slash-terminated path before any of this can reach `research/` or `~/research/`; and the comma
must not double up where axis 1 has already set the span off, which is `_tidy_commas`' job.

**Not implemented, and no wav was synthesized for it.** Whether it gets a round-4 listen is the
listener's call and is **open**. Nothing about it is heard except the one report above — which is a
listener's diagnosis of a cause, not an A/B verdict, and it is labelled that way on purpose.

### Open item — `settled` ships out of contract with §4.1 clause 3, on purpose

**This is not a gap in the evidence; it is an unresolved disagreement between the code and locked
text, and it does not close with this listen.** §4.1 clause 3 counts *segments*; `count_boundaries`
counts *boundaries*. On `s38` clause 3 demands `.` and `settled` emits `,` **[measured-here]** — the
one item the whole axis turns on.

**The listen is what makes the code the right side of that disagreement.** `s38:lb-auto` won blind
**[heard]**, and `s38` is the only corpus item where the two readings differ at all
**[measured-here]**. Clause 3 also contradicts §4.1's own rule block and its own qualification 1, and
read literally it is wrong at both ends — `.` for every list in the corpus, and a trailing `,` on 31
one-line messages. Full statement under [out of
contract](#say-it-without-the-euphemism-the-code-is-currently-out-of-contract).

**So `count_boundaries` was deliberately NOT changed to match the locked clause.** Bending the code to
a clause the listener has overruled would be backwards, and it would undo the sweep above. **The fix
is the clause 3 amendment, which #11 owns** — proposed text in [item
2](#what-42-of-the-spec-will-need-to-say). **Until #11 accepts it, this document's claim is only that
the divergence is deliberate, measured, named and evidenced — not that it is resolved.**

### What was not established

- **Nothing about the paragraph case on axis 2.** No paragraph-heavy item was played on this axis;
  `r09`'s tie from #8 is still the only evidence and §15 still names it the likeliest error.
- **Nothing about `flag-pause`'s reach on real text.** Its intended value still rests on `s28` and
  three other synthetic items; §4.3's closing condition is unchanged.
- **Nothing about B′'s reach on real text.** It is still a measured no-op on all 14 real rewrites; the
  one item that carries it is synthetic. What was confirmed is direction, not reach.
- **Nothing about `MD-FENCE-MULTI`,** and nothing about TTFA or §10.5.
- **The 4–7 band is still nearly empty:** one point, at 4, and it went against the file.

### A note on the timestamps

The `judged_at` column is the page's serialization stamp, not an independent record of when a pair was
heard. For `r11` it reads `16:40:08.540Z` against an export stamp of `16:40:08.541Z` — 1 ms apart,
where round 3's last verdict and its export were 8.7 s apart **[repo]**. Treat the column as ordering,
not as timing. The `r11` verdict itself is the listener's, reported directly, and its sides were
confirmed against the served page's own `"base_side": "a"` for `r11:settled` under the same
`2026-08-25 14:42 UTC` page generation that round 3 was scored on — so no pair was re-rendered or
reshuffled between the two listens **[repo]**.
