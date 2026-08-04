# Tolerant Emphasis Parsing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in `CMARK_OPT_TOLERANT_EMPHASIS` mode to cmark-gfm that parses ten collected malformed-emphasis inputs the way an author would expect, without changing any default behavior.

**Architecture:** Every change is a local, flag-gated adjustment to `scan_delims` and the existing single-pass closer walk in `process_emphasis`. No restructure of that function is required. A `test/strict-oracle.sh` fixture of 14 outputs across 6 corpora and 5 writers guards strict behavior after every task.

**Tech Stack:** C99, CMake, Python 3 test harness (`test/spec_tests.py`), Emscripten for the comparison page.

## Global Constraints

- Option bit is exactly `CMARK_OPT_TOLERANT_EMPHASIS (1 << 18)`. Bits 1-4 and 8-17 are taken; do not reuse.
- Default behavior must not change. With the flag off, every existing test must produce byte-identical output.
- Never run `git add -A` or `git add .`; add named files only.
- Do not push. Commits stay local on branch `tolerant-emphasis`.
- Build directory is `build/`; configure with `cmake -S . -B build -DCMARK_TESTS=ON`.
- Full existing suite gate: `ctest --test-dir build --output-on-failure`.
- Case numbering follows the spec (`docs/superpowers/specs/2026-08-04-cmark-gfm-tolerant-emphasis-design.md`). Case 4 and case 11 are deliberately absent — 4 is out of scope, 11 duplicates 2.
- Rule identifiers R1″, R1′, R3, R4, R6, R8, R9, R10 are stable and must appear in test names. R2, R2ᴛ, R5 and R7 were dropped during design and must not be reintroduced; see the spec's Dropped rules section.
- R10 is conditional: implement it only if a test fails without it (see its task).

---

### Task 1: Option bit and `--tolerant` flag

**Files:**
- Modify: `src/cmark-gfm.h:769` (after `CMARK_OPT_FULL_INFO_STRING`)
- Modify: `src/main.c:53` (usage text), `src/main.c:186` (flag parsing)

**Interfaces:**
- Consumes: nothing.
- Produces: `CMARK_OPT_TOLERANT_EMPHASIS` macro, used by every later task. `--tolerant` CLI flag setting it.

- [ ] **Step 1: Add the option macro**

In `src/cmark-gfm.h`, after the `CMARK_OPT_FULL_INFO_STRING` block:

```c
/** Parse emphasis tolerantly: accept delimiter runs that strict CommonMark
 * rejects, and permit crossing emphasis ranges. See
 * docs/superpowers/specs/2026-08-04-cmark-gfm-tolerant-emphasis-design.md
 */
#define CMARK_OPT_TOLERANT_EMPHASIS (1 << 18)
```

- [ ] **Step 2: Add the CLI flag**

In `src/main.c`, in the `else if` chain near line 186:

```c
    } else if (strcmp(argv[i], "--tolerant") == 0) {
      options |= CMARK_OPT_TOLERANT_EMPHASIS;
```

And in `print_usage` near line 53:

```c
  printf("  --tolerant        Parse emphasis tolerantly (non-CommonMark)\n");
```

- [ ] **Step 3: Build and verify the flag is accepted and inert**

```bash
cmake -S . -B build -DCMARK_TESTS=ON >/dev/null && cmake --build build -j8 2>&1 | tail -3
printf '**a **\n' | ./build/src/cmark-gfm --tolerant
```

Expected: `<p>**a **</p>` — the flag parses but changes nothing yet.

- [ ] **Step 4: Verify no regression**

```bash
ctest --test-dir build --output-on-failure 2>&1 | tail -5
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/cmark-gfm.h src/main.c
git commit -m "Add CMARK_OPT_TOLERANT_EMPHASIS option bit and --tolerant flag"
```

---

### Task 2: Test harness and the ten failing cases

**Files:**
- Create: `test/tolerant.txt`
- Modify: `test/spec_tests.py:22` (add `--tolerant` argument), `test/spec_tests.py:147` (pass it through)
- Modify: `test/cmark.py:61`, `test/cmark.py:74-84` (accept and apply options)
- Modify: `test/CMakeLists.txt` (register two new tests)

**Interfaces:**
- Consumes: `CMARK_OPT_TOLERANT_EMPHASIS` from Task 1.
- Produces: `ctest -R tolerant` target. Every later task verifies against it.

- [ ] **Step 1: Write the test file with all ten cases**

Create `test/tolerant.txt`. The fence is exactly 32 backticks, matching `spec.txt`.

````
# Tolerant emphasis

Cases collected from author expectation. Case numbers match the design spec.
Cases 4 and 11 are absent by design: 4 is out of scope, 11 duplicates 2.

## Loose closing delimiter (R1", R1')

```````````````````````````````` example
**안녕하세요 **
.
<p><strong>안녕하세요 </strong></p>
````````````````````````````````

## Loose opening delimiter (R1", R1')

```````````````````````````````` example
** 안녕하세요**
.
<p><strong> 안녕하세요</strong></p>
````````````````````````````````

## Loose closer after punctuation (R1", R1')

```````````````````````````````` example
**안녕하세요! **
.
<p><strong>안녕하세요! </strong></p>
````````````````````````````````

## Crossing bold and italic (R3, R4, R6, R8, R9)

```````````````````````````````` example
**12*34**56*
.
<p><strong>12<em>34</em></strong><em>56</em></p>
````````````````````````````````

## Crossing strikethrough and bold (R4, R8, R9) strikethrough

```````````````````````````````` example
~~가나**다라~~마바**
.
<p><del>가나<strong>다라</strong></del><strong>마바</strong></p>
````````````````````````````````

## Two loose pairs on one line: case 1 plus case 2 (R1", R1')

```````````````````````````````` example
**안녕 **하세요** 반가워**
.
<p><strong>안녕 </strong>하세요<strong> 반가워</strong></p>
````````````````````````````````

## Bold and italic together (unchanged)

```````````````````````````````` example
***안녕하세요!***
.
<p><em><strong>안녕하세요!</strong></em></p>
````````````````````````````````

## Literal asterisk inside italic (unchanged)

```````````````````````````````` example
*가격은 * 입니다*
.
<p><em>가격은 * 입니다</em></p>
````````````````````````````````

## Truncated closing delimiter (R4, R6)

```````````````````````````````` example
**안녕하세요*
.
<p><strong>안녕하세요</strong></p>
````````````````````````````````

## Lone interior asterisk stays literal (R4, R6)

```````````````````````````````` example
**굵게*기울임**
.
<p><strong>굵게*기울임</strong></p>
````````````````````````````````

## Regression: adjacent ranges must stay separate (R4)

```````````````````````````````` example
**a** and **b**
.
<p><strong>a</strong> and <strong>b</strong></p>
````````````````````````````````

## Regression: identifiers are untouched (case 4 out of scope)

```````````````````````````````` example
snake_case_name
.
<p>snake_case_name</p>
````````````````````````````````

```````````````````````````````` example
__init__
.
<p><strong>init</strong></p>
````````````````````````````````

```````````````````````````````` example
MAX_BUFFER_SIZE
.
<p>MAX_BUFFER_SIZE</p>
````````````````````````````````

## Regression: literal asterisks (R1" length gate)

```````````````````````````````` example
2 * 3 * 4 = 24
.
<p>2 * 3 * 4 = 24</p>
````````````````````````````````

```````````````````````````````` example
a * b, c * d
.
<p>a * b, c * d</p>
````````````````````````````````

## Regression: loose on both edges is rejected (R1')

```````````````````````````````` example
2 ** 3 ** 4
.
<p>2 ** 3 ** 4</p>
````````````````````````````````
````

Note `__init__` expects `<strong>init</strong>` — that is cmark-gfm's *current*
behavior (leading and trailing `__` are not intraword), and it must not change.
Confirm it before writing the file:

```bash
printf '__init__\n' | ./build/src/cmark-gfm
```

If the output differs, use the actual output as the expected value — this case
exists to pin current behavior, not to change it.

- [ ] **Step 2: Add option plumbing to `test/cmark.py`**

Change the `CMark.__init__` signature and both converters. Replace lines 74-84:

```python
    def __init__(self, prog=None, library_dir=None, extensions=None, options=0):
        self.prog = prog
        self.extensions = []
        self.options = options
        if extensions:
            self.extensions = extensions.split()
        if prog:
            prog += ' --unsafe'
            if options & (1 << 18):
                prog += ' --tolerant'
            extsfun = lambda exts: ''.join([' -e ' + e for e in exts])
            self.to_html = lambda x, exts=[]: pipe_through_prog(prog + extsfun(exts + self.extensions), x)
            self.to_commonmark = lambda x, exts=[]: pipe_through_prog(prog + ' -t commonmark' + extsfun(exts + self.extensions), x)
```

Then thread `options` into the library path. Change line 61 from the hardcoded
constant to include the caller's options, and pass them to the parser too:

```python
    result = render_html(document, (1 << 17) | options, syntax_extensions).decode('utf-8')
```

`to_html` and `parse` both need an `options` parameter to carry it; give each a
default of `0` so existing callers are unaffected.

- [ ] **Step 3: Add `--tolerant` to `test/spec_tests.py`**

After the `--extensions` argument near line 22:

```python
    parser.add_argument('--tolerant', dest='tolerant', action='store_true',
            default=False, help='enable CMARK_OPT_TOLERANT_EMPHASIS')
```

And at line 147, pass it:

```python
        converter = CMark(prog=args.program, library_dir=args.library_dir,
                          extensions=args.extensions,
                          options=(1 << 18) if args.tolerant else 0).to_html
```

- [ ] **Step 4: Register the tests**

In `test/CMakeLists.txt`, inside the `if (CMARK_SHARED)` block and again beside
`spectest_executable`:

```cmake
    add_test(tolerant_library
      ${PYTHON_EXECUTABLE} "${CMAKE_CURRENT_SOURCE_DIR}/spec_tests.py" "--no-normalize"
      "--spec" "${CMAKE_CURRENT_SOURCE_DIR}/tolerant.txt" "--tolerant"
      "--extensions" "strikethrough"
      "--library-dir" "${CMAKE_CURRENT_BINARY_DIR}/../src"
      )
```

```cmake
  add_test(tolerant_executable
    ${PYTHON_EXECUTABLE} "${CMAKE_CURRENT_SOURCE_DIR}/spec_tests.py" "--no-normalize"
    "--spec" "${CMAKE_CURRENT_SOURCE_DIR}/tolerant.txt" "--tolerant"
    "--extensions" "strikethrough"
    "--program" "${CMAKE_CURRENT_BINARY_DIR}/../src/cmark-gfm"
    )
```

- [ ] **Step 5: Build the strict-output oracle**

Two changes in this plan are not flag-gated: extracting `S_find_opener` (Task 4)
and adding the snip branch (Task 7). Capture every corpus in the repo, through
every writer, so either can be caught immediately.

Create `test/strict-oracle.sh`:

```sh
#!/bin/sh
# Capture or verify strict (flag-off) output across every corpus and writer.
# Usage: sh test/strict-oracle.sh save   (once, before any rule lands)
#        sh test/strict-oracle.sh check  (after every change)
set -eu
CMARK=./build/src/cmark-gfm
DIR=/tmp/strict-oracle
MODE=$1
mkdir -p "$DIR"
n=0
while IFS='|' read -r corpus flags; do
  [ -n "$corpus" ] || continue
  n=$((n + 1))
  out="$DIR/$n.out"
  # shellcheck disable=SC2086
  $CMARK $flags < "$corpus" > "$out.new" 2>&1 || true
  if [ "$MODE" = save ]; then
    mv "$out.new" "$out"
  else
    diff -q "$out" "$out.new" >/dev/null \
      || { echo "ORACLE DIFF: $corpus [$flags]"; exit 1; }
  fi
done <<'EOF'
test/spec.txt|
test/spec.txt|--sourcepos
test/spec.txt|--smart
test/spec.txt|-t commonmark
test/spec.txt|-t xml
test/spec.txt|-t latex
test/spec.txt|-t man
test/regression.txt|
test/regression.txt|-t commonmark
test/smart_punct.txt|--smart
test/extensions.txt|-e strikethrough -e table -e autolink -e tasklist
test/extensions.txt|-e strikethrough -e table -t commonmark
test/extensions-full-info-string.txt|--full-info-string
test/extensions-table-prefer-style-attributes.txt|-e table --table-prefer-style-attributes
EOF
echo "strict oracle $MODE: $n outputs"
```

Then capture the baseline:

```bash
chmod +x test/strict-oracle.sh
sh test/strict-oracle.sh save
```

Expected: `strict oracle save: 14 outputs`. Commit the script in this task so
every later task can re-run it.

Fourteen outputs across six corpora and five writers is meaningfully stronger than
one HTML diff — it catches sourcepos drift, `-t commonmark` drift, and extension
interactions, none of which a plain HTML comparison would see.

- [ ] **Step 6: Run and record the baseline**

```bash
cmake -S . -B build -DCMARK_TESTS=ON >/dev/null && cmake --build build -j8 >/dev/null
ctest --test-dir build -R tolerant --output-on-failure 2>&1 | tail -40
```

Expected: the seven regression cases and cases 8, 9, 12 PASS; cases 1, 2, 3, 5,
6, 7, 10 FAIL. Write the exact pass/fail list into the commit message — it is the
baseline every later task is measured against.

- [ ] **Step 7: Verify existing suites still pass**

```bash
ctest --test-dir build --output-on-failure 2>&1 | tail -8
```

Expected: everything except the two `tolerant_*` tests passes.

- [ ] **Step 8: Commit**

```bash
git add test/tolerant.txt test/spec_tests.py test/cmark.py test/CMakeLists.txt test/strict-oracle.sh
git commit -m "Add failing test suite for tolerant emphasis

Baseline: cases 8, 9, 12 and all regression guards pass; cases 1, 2, 3, 5,
6, 7, 10 fail."
```

---

### Task 3: R1″ and R1′ — whitespace tolerance

Targets cases 1, 2, 3.

**Files:**
- Modify: `src/inlines.c:415` (`scan_delims`), and its two call sites
- Modify: `src/cmark-gfm-extension_api.h:113` (`delimiter` struct)

**Interfaces:**
- Consumes: the existing closer walk in `process_emphasis` (`src/inlines.c:672`).
- Produces: `delimiter.loose_open`, `delimiter.loose_close` (both `int`), read by Task 7.

- [ ] **Step 1: Add the loose-edge fields**

In `src/cmark-gfm-extension_api.h`, extend the struct. Append at the end so the
ABI offset of existing fields is unchanged:

```c
typedef struct delimiter {
  struct delimiter *previous;
  struct delimiter *next;
  cmark_node *inl_text;
  bufsize_t position;
  bufsize_t length;
  unsigned char delim_char;
  int can_open;
  int can_close;
  int loose_open;   /* inner edge as an opener is whitespace */
  int loose_close;  /* inner edge as a closer is whitespace */
} delimiter;
```

- [ ] **Step 2: Relax flanking in `scan_delims`, length-gated**

`scan_delims` needs the option and two out-parameters. Add them to its signature
and update both call sites. After the existing `left_flanking` / `right_flanking`
assignments:

```c
  *loose_open = cmark_utf8proc_is_space(after_char);
  *loose_close = cmark_utf8proc_is_space(before_char);

  if (subj->parser_options & CMARK_OPT_TOLERANT_EMPHASIS) {
    /* R1": tolerance only for runs of length >= 2, which is what keeps
     * "2 * 3 * 4" literal. */
    if (numdelims >= 2) {
      left_flanking = left_flanking || (numdelims > 0 && *loose_open);
      right_flanking = right_flanking || (numdelims > 0 && *loose_close);
    }
  }
```

If `subject` has no options field, read it from `parser->options` — check how
`subj` reaches the parser and use whichever is available; `process_emphasis`
already receives `cmark_parser *parser`.

- [ ] **Step 3: Enforce R1′ at the pairing site**

In the closer walk in `process_emphasis`, immediately after a candidate opener is found and before
recording the pair:

```c
      if ((parser->options & CMARK_OPT_TOLERANT_EMPHASIS) &&
          opener->loose_open && closer->loose_close) {
        /* R1': never pair two loose inner edges. Rejects "2 ** 3 ** 4". */
        opener_found = false;
      }
```

- [ ] **Step 4: Run the tolerant tests**

```bash
cmake --build build -j8 >/dev/null
ctest --test-dir build -R tolerant --output-on-failure 2>&1 | tail -30
```

Expected: cases 1, 2, 3 now PASS. `2 ** 3 ** 4` and `2 * 3 * 4` still PASS. Case
7 may still fail — Task 7 handles it.

- [ ] **Step 5: Verify strict is untouched**

```bash
sh test/strict-oracle.sh check
ctest --test-dir build --output-on-failure 2>&1 | tail -8
```

Expected: `IDENTICAL`, and no new failures.

- [ ] **Step 6: Commit**

```bash
git add src/inlines.c src/cmark-gfm-extension_api.h
git commit -m "Add R1\" and R1' whitespace tolerance

R1\" relaxes flanking for runs of length >= 2 only, keeping single-asterisk
prose literal. R1' rejects pairs whose inner edges are both whitespace.
Fixes cases 1, 2, 3."
```

---

### Task 4: R3 — drop the rule of three

**Files:**
- Modify: `src/inlines.c:694-712` (extract the opener search, then gate it)

**Interfaces:**
- Consumes: the opener search inlined at `src/inlines.c:694-712`.
- Produces: `static delimiter *S_find_opener(subject *, delimiter *, bufsize_t, bufsize_t[3][128], bool tolerant);` used by Task 5.

- [ ] **Step 1: Extract the opener search**

The search is currently inlined in the closer walk at `src/inlines.c:694-712`.
Lift it verbatim — no condition changes in this step — so the next step has one
place to gate:

```c
static delimiter *S_find_opener(subject *subj, delimiter *closer,
                                bufsize_t stack_bottom,
                                bufsize_t openers_bottom[3][128],
                                bool tolerant) {
  delimiter *opener = closer->previous;
  while (opener != NULL && opener->position >= stack_bottom &&
         opener->position >= openers_bottom[closer->length % 3][closer->delim_char]) {
    if (opener->can_open && opener->delim_char == closer->delim_char) {
      if (!(closer->can_open || opener->can_close) ||
          closer->length % 3 == 0 ||
          (opener->length + closer->length) % 3 != 0) {
        return opener;
      }
    }
    opener = opener->previous;
  }
  return NULL;
}
```

Replace the inlined loop with a call, then confirm the extraction alone changed
nothing:

```bash
cmake --build build -j8 >/dev/null && sh test/strict-oracle.sh check
```

Expected: `strict oracle check: 14 outputs` with no `ORACLE DIFF` line. This
extraction is the only part of the task that is not flag-gated, so verify it
before touching any condition.

- [ ] **Step 2: Gate the `% 3` conditions**

```c
    if (opener->can_open && opener->delim_char == closer->delim_char) {
      if (tolerant) {
        return opener;
      }
      if (!(closer->can_open || opener->can_close) ||
          closer->length % 3 == 0 ||
          (opener->length + closer->length) % 3 != 0) {
        return opener;
      }
    }
```

`tolerant` is a `bool` parameter of `S_find_opener`, passed from the closer
walk as `(parser->options & CMARK_OPT_TOLERANT_EMPHASIS) != 0`.

- [ ] **Step 3: Run the tolerant tests**

```bash
cmake --build build -j8 >/dev/null && ctest --test-dir build -R tolerant --output-on-failure 2>&1 | tail -30
```

Expected: cases 1, 2, 3 still pass. Case 12 may now FAIL — it depends on R4/R6
from Task 5 to be restored. Record which cases changed.

- [ ] **Step 4: Verify strict is untouched**

```bash
sh test/strict-oracle.sh check
```

- [ ] **Step 5: Commit**

```bash
git add src/inlines.c
git commit -m "Add R3: drop the rule of three under tolerance

Case 12 regresses until R4/R6 land in the next task."
```

---

### Task 5: Lookahead, R4 and R6 — length-aware pairing

Targets cases 10 and 12.

**Files:**
- Modify: `src/inlines.c` (`S_find_opener` from Task 4, and the closer walk)

**Interfaces:**
- Consumes: `S_find_opener` from Task 4.
- Produces: `static void S_mark_later_equal_closers(subject *subj, bufsize_t stack_bottom);` which sets `delimiter.has_later_equal` — add that `int` field to the struct alongside the Task 3 fields.

- [ ] **Step 1: Add the field and the lookahead pre-pass**

```c
static void S_mark_later_equal_closers(subject *subj, bufsize_t stack_bottom) {
  delimiter *d, *later;
  for (d = subj->last_delim; d != NULL && d->position >= stack_bottom; d = d->previous) {
    d->has_later_equal = 0;
    for (later = d->next; later != NULL; later = later->next) {
      if (later->can_close && later->delim_char == d->delim_char &&
          later->length == d->length) {
        d->has_later_equal = 1;
        break;
      }
    }
  }
}
```

The inner loop makes this O(n²) worst case. That is acceptable only because
`MAX_EMPH_PAIRS` and the R10 bound cap n; if the pathological test in Task 9
fails, replace this with a single reverse sweep keyed on `(delim_char, length)`.

Call it at the top of `process_emphasis`, before the closer walk, only when tolerant.

- [ ] **Step 2: Two-sub-pass opener search**

Replace the single backward walk in `S_find_opener` with a length-preferring one:

```c
static delimiter *S_find_opener(subject *subj, delimiter *closer,
                                bufsize_t stack_bottom,
                                bufsize_t openers_bottom[3][128],
                                bool tolerant) {
  delimiter *opener;
  int pass;
  int passes = tolerant ? 2 : 1;

  for (pass = 0; pass < passes; pass++) {
    opener = closer->previous;
    while (opener != NULL && opener->position >= stack_bottom &&
           opener->position >= openers_bottom[closer->length % 3][closer->delim_char]) {
      if (opener->can_open && opener->delim_char == closer->delim_char) {
        if (!tolerant) {
          if (!(closer->can_open || opener->can_close) ||
              closer->length % 3 == 0 ||
              (opener->length + closer->length) % 3 != 0) {
            return opener;
          }
        } else if (pass == 0) {
          /* R4: prefer an opener of equal run length. */
          if (opener->length == closer->length)
            return opener;
        } else {
          /* R6: unequal fallback, but skip openers reserved for their own
           * equal-length closer. Keeps case 12's ** waiting for its partner. */
          if (!opener->has_later_equal)
            return opener;
        }
      }
      opener = opener->previous;
    }
  }
  return NULL;
}
```

- [ ] **Step 3: Node type follows the opener on unequal pairs**

In `S_insert_emph`, line 766 currently reads:

```c
  use_delims = (closer_num_chars >= 2 && opener_num_chars >= 2) ? 2 : 1;
```

Under tolerance, when the two runs differ in length, the type follows the opener
and both runs are consumed entirely:

```c
  if (tolerant && opener_num_chars != closer_num_chars) {
    use_delims = opener_num_chars >= 2 ? 2 : 1;
  } else {
    use_delims = (closer_num_chars >= 2 && opener_num_chars >= 2) ? 2 : 1;
  }
```

Then force both runs to zero remaining characters in that branch, so no leftover
literal `*` is emitted. This is what turns case 10 into `<strong>안녕하세요</strong>`
rather than `*<em>안녕하세요</em>`.

- [ ] **Step 4: Run the tolerant tests**

```bash
cmake --build build -j8 >/dev/null && ctest --test-dir build -R tolerant --output-on-failure 2>&1 | tail -30
```

Expected: cases 10 and 12 PASS. Cases 1, 2, 3 still pass.

- [ ] **Step 5: Verify strict is untouched**

```bash
sh test/strict-oracle.sh check
ctest --test-dir build --output-on-failure 2>&1 | tail -8
```

- [ ] **Step 6: Commit**

```bash
git add src/inlines.c src/cmark-gfm-extension_api.h
git commit -m "Add R4 and R6: length-preferring pairing with guarded fallback

Fixes cases 10 and 12."
```

---

### Task 6: R9 — keep interior openers alive, in both removal loops

Prerequisite for cases 5 and 6. On its own it changes no expected output.

**Files:**
- Modify: `src/inlines.c` (`S_insert_emph`, the interior free loop)
- Modify: `extensions/strikethrough.c:70-77` (the `done:` loop)

**Interfaces:**
- Consumes: `CMARK_OPT_TOLERANT_EMPHASIS`.
- Produces: no new symbols. Enables Task 7.

- [ ] **Step 1: Spare viable openers in `S_insert_emph`**

The interior free loop (upstream `src/inlines.c:778-784`) becomes:

```c
  delim = closer->previous;
  while (delim != NULL && delim != opener) {
    tmp_delim = delim->previous;
    if (!(tolerant && delim->can_open))
      remove_delimiter(subj, delim);
    delim = tmp_delim;
  }
```

- [ ] **Step 2: Spare viable openers in the strikethrough extension**

`extensions/strikethrough.c` has its own loop that destroys everything between
its opener and closer. Case 6 fails without this change: the interior `**` opener
is deleted when `~~` resolves, so the trailing `**` has no partner.

```c
done:
  delim = closer;
  while (delim != NULL && delim != opener) {
    tmp_delim = delim->previous;
    if (!((parser->options & CMARK_OPT_TOLERANT_EMPHASIS) && delim->can_open))
      cmark_inline_parser_remove_delimiter(inline_parser, delim);
    delim = tmp_delim;
  }
```

`parser` is already a parameter of `insert`.

- [ ] **Step 3: Verify no behavior change yet**

```bash
cmake --build build -j8 >/dev/null
ctest --test-dir build --output-on-failure 2>&1 | tail -8
sh test/strict-oracle.sh check
```

Expected: same pass/fail set as Task 7. Surviving delimiters have nothing to pair
with until R8 lands, so cases 5 and 6 still fail.

- [ ] **Step 4: Commit**

```bash
git add src/inlines.c extensions/strikethrough.c
git commit -m "Add R9: keep interior openers alive under tolerance

There are two delimiter removal loops, not one; the strikethrough
extension has its own, and case 6 needs both patched."
```

---

### Task 7: R8 — crossing ranges and snipping

Targets cases 5 and 6.

**Files:**
- Modify: `src/inlines.c` (the closer walk's `S_insert_emph` call site, new `S_insert_emph_split`)

**Interfaces:**
- Consumes: `S_insert_emph` (`src/inlines.c:755`).
- Produces: `static cmark_node *S_insert_emph_split(subject *subj, delimiter *opener, delimiter *closer, int use_delims);`

- [ ] **Step 1: Detect the crossing case in apply**

Before calling `S_insert_emph`, compare tree depths:

```c
static int S_depth(cmark_node *n) {
  int d = 0;
  while (n->parent) { d++; n = n->parent; }
  return d;
}
```

If `S_depth(opener->inl_text) != S_depth(closer->inl_text)`, or their parents
differ, the ranges cross and `S_insert_emph` cannot be used — it walks siblings
from opener to closer and would corrupt the tree.

- [ ] **Step 2: Implement the split**

Walk up from the opener's parent to the common ancestor of both, emitting one node
per level:

- at the opener's level: wrap everything from the node after the opener to the end
  of that parent;
- at the common ancestor: wrap everything from the start of the level to the node
  before the closer.

Each fragment gets its own `start_column` / `end_column` from the nodes it
actually wraps, not the original pair's span — the spec requires each fragment
report a real range.

Verify against both targets:

```bash
printf '**12*34**56*\n' | ./build/src/cmark-gfm --tolerant
printf '~~가나**다라~~마바**\n' | ./build/src/cmark-gfm --tolerant -e strikethrough
```

Expected:

```
<p><strong>12<em>34</em></strong><em>56</em></p>
<p><del>가나<strong>다라</strong></del><strong>마바</strong></p>
```

- [ ] **Step 3: Run the full tolerant suite**

```bash
ctest --test-dir build -R tolerant --output-on-failure 2>&1 | tail -30
```

Expected: all ten cases and every regression PASS. This is the first point where
the suite is green.

- [ ] **Step 4: Run under sanitizers**

```bash
cmake -S . -B build-asan -DCMARK_TESTS=ON -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_C_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer" >/dev/null
cmake --build build-asan -j8 >/dev/null
ctest --test-dir build-asan --output-on-failure 2>&1 | tail -8
```

Expected: no ASan or UBSan reports. Snipping allocates nodes and re-parents
children, so this step is mandatory, not optional.

- [ ] **Step 5: Verify strict is untouched**

```bash
sh test/strict-oracle.sh check
```

- [ ] **Step 6: Commit**

```bash
git add src/inlines.c
git commit -m "Add R8: snip crossing emphasis ranges

One delimiter pair may now produce several nodes. Fixes cases 5 and 6."
```

---

### Task 8: R10 — memoize only permanent failures

**Files:**
- Modify: `src/inlines.c` (the closer walk's `if (!opener_found)` block)

**Interfaces:**
- Consumes: `S_find_opener` from Task 4.
- Produces: no new symbols.

- [ ] **Step 1: Classify the failure**

A failure is *permanent* only when no opener of that delimiter character exists
before the closer at all. Anything else — rejected by R1′, R4, R6, or R7 — is
*conditional* and must not raise the floor.

```c
static bool S_any_opener_before(delimiter *closer, bufsize_t stack_bottom) {
  delimiter *d = closer->previous;
  while (d != NULL && d->position >= stack_bottom) {
    if (d->can_open && d->delim_char == closer->delim_char)
      return true;
    d = d->previous;
  }
  return false;
}
```

At the existing `if (!opener_found)` block:

```c
      if (!opener_found) {
        bool permanent = !tolerant || !S_any_opener_before(old_closer, stack_bottom);
        if (permanent) {
          openers_bottom[old_closer->length % 3][old_closer->delim_char] =
              old_closer->position;
          if (!old_closer->can_open)
            remove_delimiter(subj, old_closer);
        }
      }
```

- [ ] **Step 2: Verify case 7 does not depend on ordering luck**

```bash
cmake --build build -j8 >/dev/null
printf '**안녕 **하세요** 반가워**\n' | ./build/src/cmark-gfm --tolerant
```

Expected: `<p><strong>안녕 **하세요** 반가워</strong></p>`. Without R10, pruning
run2↔run3 puts run1 out of run4's reach.

- [ ] **Step 3: Run everything**

```bash
ctest --test-dir build --output-on-failure 2>&1 | tail -8
sh test/strict-oracle.sh check
```

Expected: all green, strict identical.

- [ ] **Step 4: Commit**

```bash
git add src/inlines.c
git commit -m "Add R10: memoize only permanent opener-search failures

A rejection by R1', R4, R6 or R7 is conditional and must not stop later
closers reaching earlier openers."
```

---

### Task 9: Pathological input bound

R10 and the Task 5 lookahead both risk quadratic behavior. This task proves they
do not.

**Files:**
- Modify: `test/pathological_tests.py`

**Interfaces:**
- Consumes: the finished parser.
- Produces: a timed test in the existing pathological suite.

- [ ] **Step 1: Add the cases**

`test/pathological_tests.py` already has a timeout mechanism; follow its existing
entry format and add:

```python
    ("many unmatched closers", ("a* " * 10000, re.compile(r'a\*'))),
    ("many unmatched openers", ("*a " * 10000, re.compile(r'\*a'))),
    ("alternating tight runs", ("*a*b" * 10000, re.compile(r'<em>a</em>'))),
```

- [ ] **Step 2: Run with the flag off**

```bash
cmake --build build -j8 >/dev/null
ctest --test-dir build -R pathological --output-on-failure 2>&1 | tail -10
```

Expected: PASS within the suite's existing timeout.

- [ ] **Step 3: Run with the flag on and time it**

```bash
python3 -c "print('a* ' * 10000)" > /tmp/patho.md
time ./build/src/cmark-gfm --tolerant /tmp/patho.md > /dev/null
time ./build/src/cmark-gfm /tmp/patho.md > /dev/null
```

Expected: tolerant is within roughly 2× of strict. If it is dramatically slower,
replace the Task 5 lookahead's inner loop with a single reverse sweep keyed on
`(delim_char, length)` and re-measure before committing.

- [ ] **Step 4: Commit**

```bash
git add test/pathological_tests.py
git commit -m "Add pathological input tests for the R10 search bound"
```

---

### Task 10: WASM build and comparison page

**Files:**
- Create: `wasm/shim.c`, `wasm/build.sh`, `docs/index.html`
- Modify: `.gitignore` (ignore `wasm/build/`)

**Interfaces:**
- Consumes: the finished library and `CMARK_OPT_TOLERANT_EMPHASIS`.
- Produces: `docs/cmark-gfm.js`, `docs/cmark-gfm.wasm`, and a static page.

- [ ] **Step 1: Write the shim**

`wasm/shim.c` exposes one render entry point. Keeping extension registration in C
avoids reimplementing cmark-gfm's multi-step setup in JavaScript.

```c
#include <stdlib.h>
#include <string.h>
#include "cmark-gfm.h"
#include "cmark-gfm-core-extensions.h"

static const char *EXTS[] = {"strikethrough", "table", "autolink", "tasklist"};

/* fmt: 0 = html, 1 = xml. Caller frees the result with free(). */
char *tolerant_render(const char *md, int options, int fmt) {
  cmark_parser *parser;
  cmark_node *doc;
  char *out;
  size_t i;

  cmark_gfm_core_extensions_ensure_registered();
  parser = cmark_parser_new(options);
  for (i = 0; i < sizeof(EXTS) / sizeof(EXTS[0]); i++) {
    cmark_syntax_extension *e = cmark_find_syntax_extension(EXTS[i]);
    if (e)
      cmark_parser_attach_syntax_extension(parser, e);
  }
  cmark_parser_feed(parser, md, strlen(md));
  doc = cmark_parser_finish(parser);
  out = (fmt == 1) ? cmark_render_xml(doc, options)
                   : cmark_render_html(doc, options,
                       cmark_parser_get_syntax_extensions(parser));
  cmark_node_free(doc);
  cmark_parser_free(parser);
  return out;
}
```

- [ ] **Step 2: Write the build script**

`wasm/build.sh`:

```bash
#!/bin/sh
set -e
emcmake cmake -S . -B wasm/build -DCMARK_TESTS=OFF -DCMARK_SHARED=OFF \
  -DCMARK_STATIC=ON -DCMAKE_BUILD_TYPE=Release
emmake cmake --build wasm/build -j8
emcc wasm/shim.c \
  wasm/build/src/libcmark-gfm.a wasm/build/extensions/libcmark-gfm-extensions.a \
  -I src -I extensions -I wasm/build/src \
  -O2 -sMODULARIZE -sEXPORT_NAME=CmarkGfm -sALLOW_MEMORY_GROWTH \
  -sEXPORTED_FUNCTIONS='["_tolerant_render","_free","_malloc"]' \
  -sEXPORTED_RUNTIME_METHODS='["cwrap","UTF8ToString","stringToNewUTF8"]' \
  -o docs/cmark-gfm.js
```

Requires `emsdk` активated in the shell. Verify with `emcc --version` first.

- [ ] **Step 3: Write the page**

`docs/index.html`: a textarea, buttons preloading each of the ten cases, and two
result columns. Both columns call the same export; the only difference is the
options bitmask.

```js
const OPT_UNSAFE = 1 << 17, OPT_TOLERANT = 1 << 18;
CmarkGfm().then(m => {
  const render = m.cwrap('tolerant_render', 'number', ['string','number','number']);
  const run = (md, opts, fmt) => {
    const p = render(md, opts, fmt);
    const s = m.UTF8ToString(p);
    m._free(p);
    return s;
  };
  window.update = () => {
    const md = document.querySelector('#input').value;
    for (const [id, opts] of [['strict', OPT_UNSAFE],
                              ['tolerant', OPT_UNSAFE | OPT_TOLERANT]]) {
      document.querySelector(`#${id}-src`).textContent  = run(md, opts, 0);
      document.querySelector(`#${id}-out`).innerHTML    = run(md, opts, 0);
      document.querySelector(`#${id}-ast`).textContent  = run(md, opts, 1);
    }
  };
});
```

- [ ] **Step 4: Build and check locally**

```bash
sh wasm/build.sh && python3 -m http.server -d docs 8000
```

Open `http://localhost:8000`, load case 5, and confirm the tolerant column shows
`<strong>12<em>34</em></strong><em>56</em>` while the strict column shows
`<strong>12*34</strong>56*`.

- [ ] **Step 5: Commit**

```bash
git add wasm/shim.c wasm/build.sh docs/index.html docs/cmark-gfm.js docs/cmark-gfm.wasm .gitignore
git commit -m "Add WASM build and strict/tolerant comparison page

One build serves both columns by toggling the option bit at runtime."
```

- [ ] **Step 6: Enable GitHub Pages**

This is a repo settings change the repository owner must make: Settings → Pages →
Source → `master` branch, `/docs` folder. The page is then at
`https://gatherheart.github.io/cmark-gfm/`.

---

### Task 11: Document the accepted costs

**Files:**
- Modify: `src/main.c` (warn on `--tolerant -t commonmark`)
- Modify: `README.md`

**Interfaces:**
- Consumes: everything.
- Produces: user-facing documentation.

- [ ] **Step 1: Measure the round-trip behavior**

The spec records this as predicted, not measured. Measure it now:

```bash
ctest --test-dir build -R roundtrip --output-on-failure 2>&1 | tail -5
printf '**12*34**56*\n' | ./build/src/cmark-gfm --tolerant -t commonmark
printf '**12*34**56*\n' | ./build/src/cmark-gfm --tolerant -t commonmark | ./build/src/cmark-gfm --tolerant
```

Record the actual output. If the second and third commands disagree — that is,
re-parsing the rewritten markdown does not reproduce
`<strong>12<em>34</em></strong><em>56</em>` — the prediction holds. Update the
spec's "Accepted costs" section with the measured result either way.

- [ ] **Step 2: Warn on the unsupported combination**

In `src/main.c`, after argument parsing completes:

```c
  if ((options & CMARK_OPT_TOLERANT_EMPHASIS) && writer == commonmark) {
    fprintf(stderr, "cmark-gfm: warning: --tolerant with -t commonmark is "
                    "unsupported; crossing emphasis cannot be written back to "
                    "markdown and rendering may change\n");
  }
```

Match the actual writer-selection variable name used in `main.c`.

- [ ] **Step 3: Document in README**

Add a short section covering: what `--tolerant` does, that it is not CommonMark,
the list of ten cases with input and output, that case 4 is deliberately excluded
to protect `snake_case`, and the two accepted costs (sourcepos reports one range
per fragment; `-t commonmark` unsupported).

- [ ] **Step 4: Commit**

```bash
git add src/main.c README.md docs/superpowers/specs/2026-08-04-cmark-gfm-tolerant-emphasis-design.md
git commit -m "Document tolerant mode and warn on unsupported writer combination"
```

---

## Self-review notes

**Spec coverage.** Every rule in the spec maps to a task: R1″/R1′ → 3, R3 → 4,
R4/R6 + lookahead → 5, R9 → 6, R8 → 7, R10 → 8 (conditional). Accepted costs → 11.
Tooling → 10. Nothing in the spec is unmapped; R2, R2ᴛ, R5 and R7 are dropped and
have no task by design.

**Known gap.** Task 7 Step 2 describes the snip algorithm in prose rather than
complete C, because the node re-parenting depends on the tree shape the earlier
rules produce and cannot be written blind. Its verification commands and expected
output are exact, so the step is still testable; the implementer should expect
~60 lines of re-parenting and lean on the ASan run that follows.

**Ordering constraints that must not be reordered.**
Task 4 (R3) temporarily regresses case 12, which Task 5 restores — do not stop
between them. Task 6 (R9) before Task 7 (R8): delimiters kept alive by R9 are
useless until snipping can consume them. Task 8 (R10) last, and only if a test
demands it — its original justification was R7, which no longer exists.

**Not flag-gated.** Only two changes touch strict behavior: the `S_find_opener`
extraction (Task 4 Step 1) and the snip branch (Task 7). Both are guarded by
`test/strict-oracle.sh`, which every task re-runs.

**Unverified traces.** Cases 5, 6 and 7 are hand-traced, not measured. Case 6's
trace already found a real spec error — the second delimiter removal loop in
`extensions/strikethrough.c`. Expect at least one more surprise in Tasks 5 and 7;
the per-task test gates exist to catch it.
