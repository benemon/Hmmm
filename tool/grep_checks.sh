#!/bin/sh
# Static gate: fails on the cheap, greppable regressions the house review caught.
set -u
cd "$(dirname "$0")/.."
fail=0

check() {
  out=$(eval "$2")
  if [ -n "$out" ]; then
    printf 'FAIL: %s\n%s\n' "$1" "$out"
    fail=1
  fi
}

check "em-dash in tracked markdown" \
  "git ls-files '*.md' | xargs grep -n '—' || true"
check "attribution markers in brand assets" \
  "git ls-files brand assets | xargs grep -lai 'c2pa\|anthropic\|claude' || true"
check "narration comments" \
  "grep -rnE '//[[:space:]]*(First|Then|Now|Next)[ ,]' lib test || true"
check "reviewer-directed comments" \
  "grep -rniE 'properly|correctly handles|this ensures|note that we' lib test || true"
check "AI attribution in tracked files" \
  "git ls-files | grep -v '^CLAUDE.md$' | xargs grep -lw 'Claude\|Anthropic' || true"

exit $fail
