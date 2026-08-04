# Tolerant emphasis parsing for cmark-gfm

Date: 2026-08-04
Status: design, awaiting review
Repo: `gatherheart/cmark-gfm` (fork of `github/cmark-gfm`)

## Problem

CommonMark deliberately rejects malformed emphasis. A stray space next to a
delimiter, a delimiter run of the wrong length, or two formatting ranges that
cross each other all cause the delimiters to be emitted as literal text rather
than as formatting. This is correct per spec and is what makes cmark
predictable, but it surprises authors who type markdown the way they'd type in
a WYSIWYG editor.

Eleven inputs were collected that parse differently from what an author would
expect. They are the specification for this work; there is no external parser
being matched.

## Scope

### Cases in scope

Case 11 in the original list duplicates case 2, so there are eleven unique
inputs, not twelve. Case numbers below follow the original list.

| # | Input | cmark-gfm today | Target |
|---|---|---|---|
| 1 | `**안녕하세요 **` | `**안녕하세요 **` | `<strong>안녕하세요 </strong>` |
| 2 | `** 안녕하세요**` | `** 안녕하세요**` | `<strong> 안녕하세요</strong>` |
| 3 | `**안녕하세요! **` | `**안녕하세요! **` | `<strong>안녕하세요! </strong>` |
| 5 | `**12*34**56*` | `<strong>12*34</strong>56*` | `<strong>12<em>34</em></strong><em>56</em>` |
| 6 | `~~가나**다라~~마바**` | `<del>가나**다라</del>마바**` | `<del>가나<strong>다라</strong></del><strong>마바</strong>` |
| 7 | `**안녕 **하세요** 반가워**` | `<strong>안녕 하세요 반가워</strong>` | `<strong>안녕 </strong>하세요<strong> 반가워</strong>` |
| 8 | `***안녕하세요!***` | `<em><strong>안녕하세요!</strong></em>` | unchanged — already correct |
| 9 | `*가격은 * 입니다*` | `<em>가격은 * 입니다</em>` | unchanged — already correct |
| 10 | `**안녕하세요*` | `*<em>안녕하세요</em>` | `<strong>안녕하세요</strong>` |
| 12 | `**굵게*기울임**` | `<strong>굵게*기울임</strong>` | unchanged — confirmed as desired |

Note case 7: cmark-gfm currently *deletes* the interior `**`. The target is not a
special case — it is cases 1 and 2 applied side by side:

```
**안녕 **하세요** 반가워**

**안녕 **      case 1 verbatim (space before the closer)  → <strong>안녕 </strong>
하세요         no delimiters of its own                    → plain
** 반가워**    case 2 verbatim (space after the opener)    → <strong> 반가워</strong>
```

An earlier draft targeted `<strong>안녕 **하세요** 반가워</strong>`, keeping the
interior `**` literal. That required two extra rules (tight-first pairing and a
redundant-nesting prune) and an ungated restructure of `process_emphasis`. The
target above falls out of R1″ and R1′ with no additional rule, so all three were
dropped. See Dropped rules.

### Out of scope

**Case 4 — intraword `_`.** `안녕_하세요_반가워` would need emphasis between two
word characters. That is structurally identical to `snake_case_name`, which must
keep working. A script-aware carve-out (allow intraword `_` only when an
adjacent character is not an ASCII word character) would satisfy both, but
protecting identifiers was chosen over case 4. Case 4 keeps its current literal
output.

### Non-goals

- Matching any other implementation's behavior.
- Changing default cmark-gfm behavior. Everything is behind an opt-in flag.
- Round-trip stability under `-t commonmark` (see Accepted costs).

## Architecture

### Option gate

Add to `src/cmark-gfm.h` (bits 1-4 and 8-17 are taken; 18 is free):

```c
#define CMARK_OPT_TOLERANT_EMPHASIS (1 << 18)
```

Off by default. Exposed as `--tolerant` in `src/main.c`. Every behavior below is
conditional on this bit, so the ~650 existing spec tests are unaffected.

### Files touched

| File | Change |
|---|---|
| `src/cmark-gfm.h` | option bit, doc comment |
| `src/inlines.c` | `scan_delims`, `process_emphasis`, `S_insert_emph`, new lookahead pre-pass and snip helper |
| `src/main.c` | `--tolerant` flag; warn when combined with `-t commonmark` |
| `extensions/strikethrough.c` | R9: stop the `done:` loop destroying interior openers |
| `test/tolerant.txt` | new spec-format test file |
| `test/CMakeLists.txt` | register the new test |
| `wasm/shim.c`, `docs/` | comparison page (see Tooling) |

`~~` joins the rules below automatically for *pairing* purposes, because
`extensions/strikethrough.c:32` pushes onto the same delimiter stack as `*` and
`_`. It does however need one change of its own for R9 — see that rule.

## Rules

All rule numbers are stable identifiers used by the tests. Each is implemented as
a separate predicate (`S_tolerant_*`) rather than inlined, so any one can be
reverted independently.

### Dropped rules

Numbering is non-contiguous. Four rules were dropped during design and their
numbers are not reused, so that discussion and test names stay aligned.

- **R2 — intraword `_`.** Dropped with case 4; see Out of scope.
- **R5 — opener-first lookahead.** Proposed as "a run that can both open and
  close becomes an opener if an equal-length closer appears later." Wrong: under
  tolerance all four runs of `**a** and **b**` can both open and close, so R5
  disqualified the first three as closers and produced
  `**a** and <strong>b</strong>`. R4 + R6 + R9 produce case 5 without it.
- **R2ᴛ — tight-first pairing.** A two-pass closer walk, pass A accepting only
  pairs with two tight inner edges. Existed solely to make case 7 pair its
  outermost delimiters.
- **R7 — no redundant same-type nesting.** Discard a pair that would nest a node
  inside the same node type, emitting its delimiters as literal text. Existed
  solely to make case 7's interior `**` literal.

R2ᴛ and R7 were dropped together when case 7's target changed to
`<strong>안녕 </strong>하세요<strong> 반가워</strong>`, which R1″ and R1′ already
produce. Their removal also removes the design's largest risk: R7 could accept a
pair in pass A that only pass B revealed as redundant, by which time
`S_insert_emph` had freed the delimiter text and nothing was left to literalize.
The counterexample was `**a **b** c **`. Repairing that needed
`process_emphasis` split into plan, prune, and apply phases — a restructure that
could not be flag-gated, because it changes the one function every existing spec
test exercises. None of that is needed now. Every remaining rule is flag-gated
and local.

### Delimiter vocabulary

A **run** is a maximal sequence of one delimiter character. `**` is a run of
length 2.

A run's **inner edges** are the characters facing the content it would wrap:

- As an opener, the inner edge is the character immediately *after* the run.
- As a closer, the inner edge is the character immediately *before* the run.

A run is **loose-open** if its opener inner edge is whitespace, and
**loose-close** if its closer inner edge is whitespace.

### R1″ — length-gated whitespace tolerance

In `scan_delims`, relax flanking only for runs of length ≥ 2:

```
left_flanking  ||= (length >= 2 && is_space(after_char))
right_flanking ||= (length >= 2 && is_space(before_char))
```

Serves cases 1, 2, 3. The length gate is what keeps `2 * 3 * 4` literal:
single-character runs get no tolerance at all.

### R1′ — never pair two loose edges

At pairing time, reject a pair when the opener is loose-open *and* the closer is
loose-close.

```
**안녕하세요 **    opener tight, closer loose  → 1 loose → allow
** 안녕하세요**    opener loose, closer tight  → 1 loose → allow
2 ** 3 ** 4      opener loose, closer loose  → 2 loose → reject
```

R1″ alone would let `2 ** 3 ** 4` through; R1′ catches it. Both are needed.

### R3 — drop the rule of three

Remove the `% 3` conditions in the opener search. They exist to prevent
intraword emphasis in `*foo**bar**baz*`-shaped input; under tolerance the
equal-length preference (R4) subsumes their role. Required for case 5.

### R4 — equal-length preference

When searching backwards for an opener, try two sub-passes:

1. openers whose run length **equals** the closer's;
2. only if none matched, unequal lengths, subject to R6.

This is a backward-only search and needs no lookahead. It is what makes case 5
pair `**`↔`**` and `*`↔`*` rather than crossing lengths.

### R6 — guarded length fallback

In R4's second sub-pass, skip any candidate opener that has a later
equal-length closer — it is reserved for its own partner.

When an unequal pair is accepted, the node type follows the **opener's** length
(≥ 2 → strong, 1 → em) and both runs are consumed entirely.

```
case 10  **안녕하세요*    ** has no later len-2 closer → fallback allowed → <strong>
case 12  **굵게*기울임**   ** has a later len-2 closer → fallback blocked → * stays literal
```

R6 needs the lookahead table below.

### Lookahead pre-pass

One reverse sweep over the delimiter list before pairing:

```
has_later_equal_closer[i] = ∃ j > i : delim_char[j] == delim_char[i]
                                   && length[j] == length[i]
                                   && can_close[j]
```

O(n), keyed on (char, length). Consumed only by R6.

### R8 — crossing ranges and snipping

Two ranges **cross** when one starts inside the other and ends outside it. A
tree cannot express this, so the inner range is cut at the boundary and reopened
on the far side. One delimiter pair then produces more than one node.

When an accepted opener and closer sit at different tree depths, walk up from the
opener to their common ancestor and emit one node per level:

- inside the opener's parent: from the opener to the end of that parent;
- at each intermediate level: the whole level;
- at the common ancestor: from the start to the closer.

```
case 5   **12*34**56*
         strong pairs first (12*34), leaving the * opener inside it
         the trailing * closer sits in the paragraph → different depth → snip
         → <strong>12<em>34</em></strong><em>56</em>

case 6   ~~가나**다라~~마바**
         del pairs first (가나**다라), leaving the ** opener inside it
         the trailing ** closer sits in the paragraph → snip
         → <del>가나<strong>다라</strong></del><strong>마바</strong>
```

Snipping must happen in core `process_emphasis` **before** dispatching to an
extension's `inline_from_delim_func`. `extensions/strikethrough.c:57-66` walks
siblings from opener to closer and would corrupt the tree if handed a crossing
pair. In case 6 the `~~` pair itself does not cross — only the `**` pair does —
so strikethrough's callback still sees siblings.

### R9 — keep interior openers alive

`S_insert_emph` currently frees every delimiter between opener and closer
(`src/inlines.c:778-784` in upstream cmark; equivalent in cmark-gfm). Stop
freeing those that can still open and have not been consumed.

Without this, case 5's interior `*` is destroyed when the `**` pair resolves, and
the later `*` closer has nothing to pair with.

**There are two such removal loops, not one.** Extensions have their own, and
`extensions/strikethrough.c:70-77` removes every delimiter between its opener
and closer:

```c
done:
  delim = closer;
  while (delim != NULL && delim != opener) {
    tmp_delim = delim->previous;
    cmark_inline_parser_remove_delimiter(inline_parser, delim);
    delim = tmp_delim;
  }
```

Case 6 fails without patching this too:

```
~~가나**다라~~마바**
T1     S1     T2     S2

T2 pairs with T1 → <del> wraps 가나, **, 다라
strikethrough's done: loop then destroys S1
S2 finds no ** opener → <del>가나**다라</del>마바**   ← today's broken output
```

So R9 applies to both loops. An earlier draft of this spec claimed `~~` needed
no extension changes; that was wrong, and case 6 is the counterexample.

### R10 — memoize only permanent failures

When a closer finds no opener, cmark records a floor
(`openers_bottom[length % 3][delim_char]`, `src/inlines.c:678`) and forbids later
closers from searching before that position. It also removes the failed
delimiter outright. Both discard information after a failure.

The floor is not only a correctness device — it bounds the backward search. Input
like `a* a* a* …` repeated 10,000 times would otherwise cost O(n²). So it cannot
simply be deleted.

Distinguish two failure kinds:

| Kind | Condition | True for later closers? | Memoize |
|---|---|---|---|
| permanent | no opener of this character exists before the closer at all | yes | yes |
| conditional | openers exist; this closer was rejected by R1′, R4, or R6 | no | no |

Memoize only permanent failures. This satisfies the requirement that one failure
must not block others, while keeping the O(n) bound on the common junk-input
path.

**R10 may not be needed.** Its original justification was R7, which is now
dropped: rejecting case 7's interior pair made that closer fail, and the
unconditional floor then put the outermost opener out of reach. Without R7, the
remaining conditional failures come from R1′, R4, and R6, and case 5 — the only
in-scope case with a conditional failure — appears to survive the existing floor
anyway, because cmark-gfm buckets it by `length % 3` and case 5's failing closer
has length 1 while its later closer has length 2, so they land in different
buckets.

That is a trace, not a measurement. Implement R10 **last**, and only if a test
demonstrates a case failing without it. If all cases pass with the floor intact,
drop R10 and record that in this section.

## Trace verification

Each case was hand-traced against the rules above. Marked traces are reasoning,
not measurement — they must be confirmed by the tests in `test/tolerant.txt`.

| # | Resolving rules |
|---|---|
| 1 | R1″, R1′ |
| 2 | R1″, R1′ |
| 3 | R1″, R1′ |
| 5 | R3, R4, R6, R8, R9 |
| 6 | R4, R8, R9 |
| 7 | R1″, R1′ — the same rules as cases 1 and 2, applied twice on one line |
| 8 | R4 (unchanged behavior) |
| 9 | R1″ length gate keeps the middle `*` inert |
| 10 | R4, R6 |
| 12 | R4, R6 |

Case 7 needs no rule of its own. Its two pairs are case 1 (`**안녕 **`, tight
opener and loose closer) and case 2 (`** 반가워**`, loose opener and tight
closer) on the same line, with `하세요` between them carrying no delimiters.

Regression traces that must also hold:

| Input | Expected | Guarded by |
|---|---|---|
| `**a** and **b**` | two separate `<strong>` | all four inner edges tight; R4 pairs nearest equal-length |
| `snake_case_name` | literal | case 4 out of scope; `_` untouched |
| `__init__` | literal | same |
| `MAX_BUFFER_SIZE` | literal | same |
| `2 * 3 * 4` | literal | R1″ length gate |
| `2 ** 3 ** 4` | literal | R1′ both-edges-loose |
| `a * b, c * d` | literal | R1″ length gate |

## Accepted costs

**Source positions (`--sourcepos`, XML output only).** A snipped pair produces
two nodes from one delimiter pair, so it reports two source ranges instead of
one. Each fragment is given the range it actually covers; they are not both
stamped with the original pair's span, which would overlap and be false. HTML
output is unaffected — cmark-gfm emits sourcepos on blocks, not inlines. Tools
using sourcepos for click-to-source mapping need to expect two elements where the
author typed one pair.

**Markdown output (`-t commonmark`).** The writer emits one delimiter pair per
node, so a snipped tree is written as two pairs; re-parsing two pairs yields two
independent ranges. The information that they were one pair has nowhere to live
in markdown syntax and is destroyed at write time, in strict or tolerant mode
alike. Four candidate strings were tested and none reproduce the crossing tree:

```
**12*34***56*     → <strong>12<em>34</em></strong>56*      56 plain
**12*34****56*    → **12<em>34</em>**<em>56</em>            bold lost
**12*34** *56*    → <strong>12*34</strong> <em>56</em>      34 not italic
```

Consequence: using `--tolerant -t commonmark` as a formatter can silently change
a document's rendering. `--tolerant` with `-t commonmark` is therefore declared
unsupported, and `main.c` warns. `-t html`, `-t xml`, `-t latex`, and `-t man`
are one-way and unaffected. The existing round-trip tests
(`test/roundtrip_tests.py`, four targets in `test/CMakeLists.txt:45-94`) do not
enable the flag and keep passing.

This limitation is predicted from the writer's structure, not measured — tolerant
mode does not exist yet. Verification step: after implementation, run
`roundtrip_tests.py` with the flag enabled and record the actual result. If it
contradicts this prediction, relax the warning.

## Testing

`test/tolerant.txt` in cmark's existing spec-test format, run by
`test/spec_tests.py` with `--tolerant`. Contents:

1. All ten in-scope cases with their target output.
2. Case 4 and the regression table above, pinning what tolerance must *not*
   change.
3. Per-rule unit cases, so a failure names the rule rather than only the case.
4. Pathological input for R10's O(n) bound (`a* ` ×10,000) with a time assertion.

The existing suites must pass untouched with the flag off. `make test` gates
both.

## Tooling

A comparison page, deployable to GitHub Pages at
`gatherheart.github.io/cmark-gfm`.

Because the change is behind an option bit, **one** WASM build serves both
columns by toggling the flag at runtime — no second binary.

- `wasm/shim.c` — one entry point taking markdown plus an options bitmask and
  returning HTML; a second export calling `cmark_render_xml` for the AST view.
  Keeps cmark-gfm's multi-step extension registration out of JavaScript.
- Built with `emcc -sMODULARIZE -sEXPORTED_FUNCTIONS=…`, driven via `cwrap`.
- `docs/` — static page: input box, the eleven cases as one-click presets, and
  strict/tolerant columns showing HTML source, rendered output, and AST.
- Served from `docs/` on `master`. Pages must be enabled in repo settings
  manually.
- The same files work from a local server during development, so there is no
  separate local-only code path.

New dependency: `emsdk`.

## Risks

| | Risk | Mitigation |
|---|---|---|
| R8 changes `process_emphasis` control flow | Snipping needs a different call than `S_insert_emph` when opener and closer sit at different depths | The branch is flag-gated and the existing single-pass walk is otherwise untouched. Verified by `test/strict-oracle.sh`: 14 outputs across 6 corpora and 5 writers must stay byte-identical. |
| R8 memory ownership | Snipping allocates N nodes per pair; error paths must not leak | Reuse `S_insert_emph`'s existing splice pattern; run under the existing fuzz targets and ASan. |
| R10 bound | Misclassifying a conditional failure as permanent reintroduces blocking; the reverse reintroduces O(n²) | Pathological-input test with a time assertion. |
| Rule interaction | Ten interacting rules; hand-traces are not proof | Per-rule tests plus the regression table; the WASM page for exploratory checking. |

## Open items

1. Confirm the trace table by test, especially cases 5, 6, and 7.
2. Measure tolerant round-trip behavior (see Accepted costs).
3. Decide whether `--tolerant` should imply `-e strikethrough`. Current
   decision: no, keep them orthogonal.
4. Whether tolerance should apply inside link text, image alt text, and
   headings. Current decision: yes — same inline parser, no carve-out.
