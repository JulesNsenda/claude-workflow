#!/usr/bin/env bash
#
# leak-check.sh — fail if any TRACKED file matches a blocked pattern.
#
# The blocklist lives OUTSIDE this repo on purpose: it names exactly the things
# that must never appear here, so committing it would be the leak. One extended
# regex per line, matched case-insensitively.
#
# Usage:
#   scripts/leak-check.sh [blocklist-file]
#   # default: $LEAK_BLOCKLIST_FILE, else ~/.claude/leak-blocklist.txt
#
# Output discipline: on a hit, print FILE NAMES ONLY — never the matched
# content and never the patterns (CI logs are public).

set -euo pipefail

list="${1:-${LEAK_BLOCKLIST_FILE:-$HOME/.claude/leak-blocklist.txt}}"

if [[ ! -f "$list" ]]; then
  echo "leak-check: no blocklist at $list — skipping (create it: one regex per line)." >&2
  exit 0
fi

if files=$(git grep -lIiE -f "$list" 2>/dev/null); then
  echo "leak-check: BLOCKED content found in:" >&2
  echo "$files" >&2
  echo "leak-check: (matches not shown on purpose — run 'git grep -iE -f <blocklist>' locally to see them)" >&2
  exit 1
fi

echo "leak-check: clean"
