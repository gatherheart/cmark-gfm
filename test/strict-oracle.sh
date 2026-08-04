#!/bin/sh
# Capture or verify strict (flag-off) output across every corpus and writer.
#
# Usage: sh test/strict-oracle.sh save   (once, before any rule lands)
#        sh test/strict-oracle.sh check  (after every change)
#
# Two changes in the tolerant-emphasis plan are not flag-gated: extracting
# S_find_opener, and adding the snip branch at the S_insert_emph call site.
# This fixture catches either immediately, across more writers than an HTML
# diff would see.
set -eu

CMARK=${CMARK:-./build/src/cmark-gfm}
DIR=${ORACLE_DIR:-/tmp/strict-oracle}
MODE=${1:?usage: strict-oracle.sh save|check}

case "$MODE" in
  save|check) ;;
  *) echo "usage: strict-oracle.sh save|check" >&2; exit 2 ;;
esac

[ -x "$CMARK" ] || { echo "no binary at $CMARK; build first" >&2; exit 2; }
mkdir -p "$DIR"

n=0
failed=0
while IFS='|' read -r corpus flags; do
  [ -n "$corpus" ] || continue
  n=$((n + 1))
  out="$DIR/$n.out"
  # shellcheck disable=SC2086
  $CMARK $flags < "$corpus" > "$out.new" 2>&1 || true
  if [ "$MODE" = save ]; then
    mv "$out.new" "$out"
  elif [ ! -f "$out" ]; then
    echo "ORACLE MISSING: $out (run 'save' first)" >&2
    failed=$((failed + 1))
  elif ! diff -q "$out" "$out.new" >/dev/null 2>&1; then
    echo "ORACLE DIFF: $corpus [$flags]" >&2
    diff "$out" "$out.new" | head -20 >&2
    failed=$((failed + 1))
  else
    rm -f "$out.new"
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

if [ "$failed" -gt 0 ]; then
  echo "strict oracle $MODE: $failed of $n outputs DIFFER" >&2
  exit 1
fi
echo "strict oracle $MODE: $n outputs"
