#!/bin/sh
#
# ref-check.sh — verify agent/skill cross-references between the docs and the
# repo actually resolve, in both directions.
#
# Four checks, all built from ONE inventory: parse `^name:` out of the
# frontmatter of every agents/*.md and skills/*/SKILL.md — the same dynamic
# discovery install.sh already uses (see its "agents:" / "skills:" INSTALL
# loops — not the uninstall unlink loops above them — in install.sh) — so no
# layout knowledge is hardcoded twice. Cite by anchor text, not line number:
# this script's whole job is catching cross-reference rot, so a stale line
# number here would be exactly that.
#
#   1. Frontmatter sanity — every agents/*.md and skills/*/SKILL.md has a
#      non-empty `name:`, matching its filename (agents) / directory name
#      (skills) CASE-INSENSITIVELY. This is a repo HOUSE RULE, not a harness
#      requirement — the sub-agents docs say "the filename doesn't have to
#      match". Case-insensitivity exists because agents/explore.md
#      deliberately declares `name: Explore` to shadow the built-in Explore.
#   2. Forward — every name-shaped token referenced in CLAUDE.md and
#      skills/**/SKILL.md must resolve to an inventory name.
#   3. Reverse — every inventory name must be referenced at least once, as a
#      backticked token OUTSIDE its own defining file, across CLAUDE.md +
#      skills/**/SKILL.md + README.md. This is the durable rename-catcher: it
#      depends on no prose wording, so it survives the cosmetic reflows that
#      defeat check 2. It is also a deliberate HOUSE RULE, not an accident:
#      no agent or skill may exist without being backticked somewhere else in
#      the docs, so a next contributor hitting this should add a mention, not
#      treat it as a checker bug. A name's own SKILL.md/agent file doesn't
#      count as that mention — every inventory item must be found by someone
#      else.
#   4. README link targets — every relative link target in README.md
#      (`](target)`, `](target "title")`, `](target#anchor)`) must exist on
#      disk. Absolute targets and any target containing a `..` path component
#      are rejected outright, distinctly from "does not exist".
#
# Check 2's matching rule (the part worth getting wrong quietly):
#   - strip \r; drop fenced code blocks (``` or ~~~, optionally indented);
#     flatten newlines to spaces
#   - extract backtick spans; a token is a span matching
#     ^/?([A-Za-z][A-Za-z0-9-]*)$ — take group 1, so the optional leading `/`
#     recovers `/test` and `/example-skill`
#   - Rule A: token contains a hyphen -> check it
#   - Rule B: the span is followed by \s*[*_]*\s* then a role word
#     (agent(s)/subagent(s)/critic(s)/skill(s)/override) -> check it. The gap
#     is \s*, NOT adjacency — literal adjacency matches nothing in this corpus.
#   - resolve against the inventory, case-insensitively — never a filesystem
#     probe, which is case-blind on NTFS and case-sensitive on CI runners
#   - exemptions (built-ins / template placeholders, no file by design):
#     general-purpose, code-review, security-review, verify, my-skill
#
# Never fails open: asserts the inventory is non-empty, that at least one
# backtick token was extracted from the forward corpus, that at least one of
# those survived Rule A/B selection, and that at least one relative README
# link target was found — all before it may print the clean line. A broken
# discovery/extraction/classification pass reads as a failure, not a silent
# pass. An unclosed fenced code block (``` or ~~~ left open at end of file)
# also fails loudly instead of silently swallowing the rest of the file.
#
# Root resolution — NOT pinned to "the repo": cd's to the resolved root
# (default: `git rev-parse --show-toplevel` from the CALLER's cwd, i.e.
# whatever repo you happen to be standing in — NOT this script's own
# location) and, when that root is a git repo, enumerates the corpus via
# `git ls-files`, so it can only ever read TRACKED files from that repo. An
# explicit `root` argument that is NOT itself a git repo (a fixture tree for
# testing) falls back to a plain glob that reads whatever is on disk —
# tracked or not, including anything untracked and private. That fallback
# refuses to run unless REF_CHECK_ALLOW_UNTRACKED=1 is set, so a stray
# `ref-check.sh ~/.claude` cannot silently enumerate and print names read out
# of untracked, possibly employer/client-specific files.
#
# Output discipline: on failure, names the offending reference, its source
# file, and a `grep -rn '<name>'` hint — never file content (CI logs are
# public), matching leak-check.sh's convention. Every interpolated value is
# printed with `printf '%s'`, never `echo`, and a name that fails shape
# validation is never echoed at all (only its source file is).
#
# Usage:
#   scripts/ref-check.sh [root]
#   # default root: git rev-parse --show-toplevel (from the caller's cwd)
#   # REF_CHECK_ALLOW_UNTRACKED=1 required when root is not a git repo

set -eu

root="${1:-}"
if [ -z "$root" ]; then
  if ! root=$(git rev-parse --show-toplevel 2>/dev/null); then
    echo "ref-check: no root given and not inside a git repo" >&2
    exit 1
  fi
fi

if [ ! -d "$root" ]; then
  # shellcheck disable=SC2016 # literal backtick pair, not command substitution
  printf 'ref-check: root `%s` is not a directory\n' "$root" >&2
  exit 1
fi

cd "$root" || exit 1

use_git=0
if [ -e .git ]; then
  use_git=1
fi

if [ "$use_git" -eq 0 ] && [ "${REF_CHECK_ALLOW_UNTRACKED:-}" != "1" ]; then
  # shellcheck disable=SC2016 # literal backtick pair, not command substitution
  printf 'ref-check: `%s` is not a git repository — refusing to enumerate untracked files.\n' "$root" >&2
  printf 'ref-check:   set REF_CHECK_ALLOW_UNTRACKED=1 to opt in (e.g. for a test fixture tree).\n' >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Signal handlers just exit (with the conventional 128+signum code); that
# exit *also* fires the EXIT trap above, so cleanup still runs. A trap that
# only did `rm -rf "$tmp"` on INT/TERM/HUP would clean up and then keep
# running with a deleted tmpdir instead of actually stopping.
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# --- the extractor: strip fenced code blocks, flatten to one line, pull out
# backtick spans, and tag each one "checked" (Rule A or B applies) or not. ---
cat > "$tmp/extract.awk" <<'AWK_EOF'
BEGIN {
  role = "(agents|agent|subagents|subagent|critics|critic|skills|skill|override)"
  buf = ""
  infence = 0
}
# A fence closes only with the marker that opened it — otherwise a ~~~ inside a
# ``` block would close it early and the rest of the block gets tokenized.
/^[ \t]*(```|~~~)/ {
  marker = ($0 ~ /^[ \t]*```/) ? "`" : "~"
  if (!infence) { infence = 1; fencemarker = marker }
  else if (marker == fencemarker) { infence = 0 }
  next
}
!infence { buf = buf $0 " " }
END {
  if (infence) {
    print "ref-check: unclosed fenced code block (``` or ~~~) in " src > "/dev/stderr"
    exit 1
  }
  s = buf
  while (match(s, /`\/?[A-Za-z][A-Za-z0-9-]*`/)) {
    mstart = RSTART
    mlen = RLENGTH
    span = substr(s, mstart, mlen)
    rest = substr(s, mstart + mlen)
    token = span
    gsub(/`/, "", token)
    if (substr(token, 1, 1) == "/") token = substr(token, 2)
    hasHyphen = (token ~ /-/) ? 1 : 0
    ruleB = 0
    if (match(rest, "^[ \t]*[*_]*[ \t]*" role)) {
      after = substr(rest, RLENGTH + 1, 1)
      if (after !~ /[A-Za-z0-9_]/) ruleB = 1
    }
    checked = (hasHyphen || ruleB) ? 1 : 0
    printf "%s\t%s\t%d\n", token, src, checked
    s = substr(s, mstart + mlen)
  }
}
AWK_EOF

frontmatter_name() {
  # strip a leading UTF-8 BOM (0xEF 0xBB 0xBF) in the C locale, byte-wise, so
  # it can't defeat the NR==1 frontmatter guard below; then strip \r. Built via
  # printf rather than a \xHH sed escape — that's a GNU extension, and this is
  # the byte-exact POSIX way to embed the 3 raw BOM bytes in the script.
  LC_ALL=C sed "1s/^$(printf '\357\273\277')//" < "$1" | tr -d '\r' | awk '
    BEGIN { dq = "\042"; sq = "\047" }
    NR == 1 && $0 !~ /^---[[:space:]]*$/ { exit }
    NR == 1 { infm = 1; next }
    infm && /^---[[:space:]]*$/ { exit }
    infm && /^name:[[:space:]]*/ {
      line = $0
      sub(/^name:[[:space:]]*/, "", line)
      sub(/[[:space:]]+$/, "", line)
      first = substr(line, 1, 1)
      last = substr(line, length(line), 1)
      if (length(line) >= 2 && first == last && (first == dq || first == sq)) {
        line = substr(line, 2, length(line) - 2)
      }
      print line
      exit
    }
  '
}

extract_tokens() {
  tr -d '\r' < "$1" | awk -v src="$1" -f "$tmp/extract.awk"
}

# --- enumerate the corpus: tracked files only, via git ls-files, unless
# root isn't a git repo (a fixture tree), in which case fall back to a plain
# glob. `:(glob)` makes git's `*` stop at `/`, same as the shell glob below —
# plain git pathspec `*` crosses directories and would silently pick up
# nested files (agents/sub/nested.md) the fallback and install.sh cannot see.
: > "$tmp/agent_files.txt"
: > "$tmp/skill_files.txt"

if [ "$use_git" -eq 1 ]; then
  git ls-files -- ':(glob)agents/*.md' > "$tmp/agent_files.txt"
  git ls-files -- ':(glob)skills/*/SKILL.md' > "$tmp/skill_files.txt"
else
  for f in agents/*.md; do
    [ -e "$f" ] && printf '%s\n' "$f" >> "$tmp/agent_files.txt"
  done
  for f in skills/*/SKILL.md; do
    [ -e "$f" ] && printf '%s\n' "$f" >> "$tmp/skill_files.txt"
  done
fi

# --- build the inventory (check 1) ---
: > "$tmp/inventory.tsv"
check1_fail=0

while IFS= read -r f; do
  [ -n "$f" ] || continue
  base=$(basename "$f" .md)
  name=$(frontmatter_name "$f")
  if [ -z "$name" ]; then
    printf 'ref-check: %s has no (or empty) frontmatter "name:"\n' "$f" >&2
    check1_fail=1
    continue
  fi
  if ! printf '%s' "$name" | grep -qE '^[A-Za-z][A-Za-z0-9-]*$'; then
    printf 'ref-check: %s frontmatter name has an invalid shape (expected ^[A-Za-z][A-Za-z0-9-]*$) — refusing to use it\n' "$f" >&2
    check1_fail=1
    continue
  fi
  name_lc=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
  base_lc=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')
  if [ "$name_lc" != "$base_lc" ]; then
    # shellcheck disable=SC2016 # literal backtick pair, not command substitution
    printf 'ref-check: %s frontmatter name `%s` does not match filename `%s` (case-insensitive) — repo house rule, see header\n' "$f" "$name" "$base" >&2
    check1_fail=1
    continue
  fi
  printf '%s\t%s\n' "$name" "$f" >> "$tmp/inventory.tsv"
done < "$tmp/agent_files.txt"

while IFS= read -r f; do
  [ -n "$f" ] || continue
  dir=$(dirname "$f")
  base=$(basename "$dir")
  name=$(frontmatter_name "$f")
  if [ -z "$name" ]; then
    printf 'ref-check: %s has no (or empty) frontmatter "name:"\n' "$f" >&2
    check1_fail=1
    continue
  fi
  if ! printf '%s' "$name" | grep -qE '^[A-Za-z][A-Za-z0-9-]*$'; then
    printf 'ref-check: %s frontmatter name has an invalid shape (expected ^[A-Za-z][A-Za-z0-9-]*$) — refusing to use it\n' "$f" >&2
    check1_fail=1
    continue
  fi
  name_lc=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
  base_lc=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')
  if [ "$name_lc" != "$base_lc" ]; then
    # shellcheck disable=SC2016 # literal backtick pair, not command substitution
    printf 'ref-check: %s frontmatter name `%s` does not match directory name `%s` (case-insensitive) — repo house rule, see header\n' "$f" "$name" "$base" >&2
    check1_fail=1
    continue
  fi
  printf '%s\t%s\n' "$name" "$f" >> "$tmp/inventory.tsv"
done < "$tmp/skill_files.txt"

awk -F'\t' '{print tolower($1)}' "$tmp/inventory.tsv" | sort -u > "$tmp/inventory_names_lc.txt"

cat > "$tmp/exemptions.txt" <<'EOF'
general-purpose
code-review
security-review
verify
my-skill
EOF

# --- collect every backtick token from the forward+reverse corpus in one
# pass: CLAUDE.md and skills/**/SKILL.md are both forward- and
# reverse-eligible; README.md is reverse-only. ---
: > "$tmp/tokens_all.tsv"

if [ -f CLAUDE.md ]; then
  extract_tokens CLAUDE.md >> "$tmp/tokens_all.tsv"
fi

while IFS= read -r f; do
  [ -n "$f" ] || continue
  extract_tokens "$f" >> "$tmp/tokens_all.tsv"
done < "$tmp/skill_files.txt"

if [ -f README.md ]; then
  extract_tokens README.md >> "$tmp/tokens_all.tsv"
fi

forward_total=$(awk -F'\t' '$2 != "README.md"' "$tmp/tokens_all.tsv" | wc -l | tr -d ' ')

# --- check 2: forward — every checked token must resolve to the inventory
# or be an exemption. ---
check2_fail=0
awk -F'\t' '$3 == 1 && $2 != "README.md"' "$tmp/tokens_all.tsv" > "$tmp/forward_checked.tsv"

# shellcheck disable=SC2034 # checked: already filtered to checked==1 by the awk above
while IFS="$(printf '\t')" read -r token src checked; do
  [ -n "$token" ] || continue
  # defence in depth: re-validate the token shape before using it anywhere,
  # even though the extractor's own regex already anchors it this way.
  if ! printf '%s' "$token" | grep -qE '^[A-Za-z][A-Za-z0-9-]*$'; then
    continue
  fi
  token_lc=$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')
  if grep -qxF -- "$token_lc" "$tmp/exemptions.txt"; then
    continue
  fi
  if grep -qxF -- "$token_lc" "$tmp/inventory_names_lc.txt"; then
    continue
  fi
  # shellcheck disable=SC2016 # literal backtick pair, not command substitution
  printf 'ref-check: unresolved reference `%s` in %s — no agent/skill named `%s` in the inventory\n' "$token" "$src" "$token" >&2
  printf 'ref-check:   hint: grep -rn '\''%s'\'' .\n' "$token" >&2
  check2_fail=1
done < "$tmp/forward_checked.tsv"

# --- check 3: reverse — every inventory name must show up as a backtick
# token somewhere in the forward+reverse corpus (any token, not just the
# Rule-A/B "checked" subset — this is the rename-catcher, not the
# resolution check), EXCLUDING tokens sourced from that name's own defining
# file — otherwise a skill's own body can be its only "reference", which
# falsifies the whole point of the check. ---
check3_fail=0

while IFS="$(printf '\t')" read -r name src; do
  [ -n "$name" ] || continue
  name_lc=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
  awk -F'\t' -v skip="$src" '$2 != skip { print tolower($1) }' "$tmp/tokens_all.tsv" | sort -u > "$tmp/referenced_excl_self.txt"
  if ! grep -qxF -- "$name_lc" "$tmp/referenced_excl_self.txt"; then
    # shellcheck disable=SC2016 # literal backtick pair, not command substitution
    printf 'ref-check: inventory name `%s` is never referenced as a backticked token outside its own defining file (%s) in CLAUDE.md, skills/**/SKILL.md, or README.md\n' "$name" "$src" >&2
    printf 'ref-check:   hint: grep -rn '\''%s'\'' .\n' "$name" >&2
    check3_fail=1
  fi
done < "$tmp/inventory.tsv"

# --- check 4: README relative link targets must exist on disk. Matches
# `](target)` (with or without a leading "./"), an optional space + quoted
# "title", and/or a trailing #anchor; discards http(s)/mailto/in-page-anchor
# targets; rejects absolute targets and any target containing a `..` path
# component outright, with a distinct message — either escapes the repo root
# or (via MSYS `/c/...` path translation on Windows) resolves to something
# wildly outside it. ---
check4_fail=0
: > "$tmp/readme_links.txt"
if [ -f README.md ]; then
  grep -oE '\]\([^)]+\)' README.md | sed -E 's/^\]\(//; s/\)$//' > "$tmp/readme_link_targets_raw.txt"
  while IFS= read -r raw; do
    [ -n "$raw" ] || continue
    case "$raw" in
      http*|'#'*|mailto:*) continue ;;
    esac
    # strip an optional trailing space-quoted "title", then an optional
    # trailing #anchor (in that order, so a title containing '#' is safe)
    target=$(printf '%s' "$raw" | sed -E 's/[[:space:]]+"[^"]*"[[:space:]]*$//')
    target=$(printf '%s' "$target" | sed -E 's/#[^#]*$//')
    [ -n "$target" ] || continue
    printf '%s\n' "$target" >> "$tmp/readme_links.txt"
  done < "$tmp/readme_link_targets_raw.txt"

  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    case "$rel" in
      /*)
        # shellcheck disable=SC2016 # literal backtick pair, not command substitution
        printf 'ref-check: README.md link target `%s` is absolute — link targets must be repo-relative\n' "$rel" >&2
        check4_fail=1
        continue
        ;;
    esac
    case "/$rel/" in
      */../*)
        # shellcheck disable=SC2016 # literal backtick pairs, not command substitution
        printf 'ref-check: README.md link target `%s` contains a `..` path component — link targets must stay inside the repo\n' "$rel" >&2
        check4_fail=1
        continue
        ;;
    esac
    if [ ! -e "$rel" ]; then
      # shellcheck disable=SC2016 # literal backtick pair, not command substitution
      printf 'ref-check: README.md links to `%s`, which does not exist\n' "$rel" >&2
      check4_fail=1
    fi
  done < "$tmp/readme_links.txt"
else
  echo "ref-check: README.md not found at repo root" >&2
  check4_fail=1
fi

fail=0
if [ "$check1_fail" -eq 1 ]; then fail=1; fi
if [ "$check2_fail" -eq 1 ]; then fail=1; fi
if [ "$check3_fail" -eq 1 ]; then fail=1; fi
if [ "$check4_fail" -eq 1 ]; then fail=1; fi

# Fail loudly rather than open: a checker that matches nothing exits 0
# forever and reads as green.
if [ ! -s "$tmp/inventory.tsv" ]; then
  echo "ref-check: inventory is empty — no agents/*.md or skills/*/SKILL.md were discovered; refusing to report a false clean pass" >&2
  fail=1
fi
if [ "$forward_total" -eq 0 ]; then
  echo "ref-check: zero backtick tokens extracted from CLAUDE.md/skills/**/SKILL.md; refusing to report a false clean pass — extraction is broken" >&2
  fail=1
fi
if [ ! -s "$tmp/forward_checked.tsv" ]; then
  echo "ref-check: zero Rule-A/B-selected tokens in the forward corpus; refusing to report a false clean pass — the classifier is broken" >&2
  fail=1
fi
if [ ! -s "$tmp/readme_links.txt" ]; then
  echo "ref-check: zero relative link targets found in README.md; refusing to report a false clean pass — link extraction is broken" >&2
  fail=1
fi

if [ "$fail" -eq 1 ]; then
  exit 1
fi

echo "ref-check: clean"
