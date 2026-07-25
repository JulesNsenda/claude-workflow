#!/bin/sh
#
# version-check.sh — assert a release tag and the plugin manifest agree.
#
# Two things carry this repo's version: the git tag (what a clone pins with
# `git checkout v1.0.0`) and the `version` field in .claude-plugin/plugin.json
# (what a plugin install reads). Nothing forced them to agree, so a release
# could ship with the two naming different versions and nothing would say so.
# This is that check.
#
# It is DETECTIVE, not preventive: it runs on the tag push, so a mismatch is
# caught after the tag exists but before `gh release create` — recovery is
# `git push --delete origin <tag>`, fix, re-tag. The failure actually being
# guarded against is a mismatch shipping SILENTLY, and the ordering that makes
# that safe is: push tag -> CI green -> create the release.
#
# Usage:
#   scripts/version-check.sh <tag> [manifest]
#   # manifest defaults to .claude-plugin/plugin.json, relative to CWD
#
# Pass the BARE tag name. In GitHub Actions that is `${{ github.ref_name }}`
# (or $GITHUB_REF_NAME), NOT `${{ github.ref }}` — the latter is
# `refs/tags/v1.0.0` and would never match. Passing a full ref is a wiring
# mistake with its own error message rather than a confusing shape failure,
# because a fixture that only ever passes bare tags cannot catch it.
#
# Exit 0 and print one clean line on agreement; exit 1 naming both values
# otherwise. Every failure prints a distinct message: asserting the exit
# status alone lets checks be deleted with the build still green (measured in
# this repo — see the ref-check CI job).

set -eu

usage() {
  echo "version-check: usage: version-check.sh <tag> [manifest]" >&2
  exit 2
}

[ "$#" -ge 1 ] || usage
[ "$#" -le 2 ] || usage

tag=$1
manifest=${2:-.claude-plugin/plugin.json}

# Accepts v<major>.<minor>.<patch> with optional semver prerelease and build
# metadata, so a `v1.1.0-rc.1` tag is a first-class case rather than a loud
# failure at the worst possible moment.
semver_body='[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?'

# --- the wiring mistake, named explicitly ---
case $tag in
  refs/*)
    # shellcheck disable=SC2016 # literal backticks and $VAR in the message text, not expansions
    printf 'version-check: tag `%s` looks like a full git ref — pass the BARE tag name (github.ref_name / $GITHUB_REF_NAME), not github.ref\n' "$tag" >&2
    exit 1
    ;;
esac

if ! printf '%s' "$tag" | grep -qE "^v${semver_body}$"; then
  # shellcheck disable=SC2016 # literal backticks and $VAR in the message text, not expansions
  printf 'version-check: tag `%s` has an invalid shape (expected v<major>.<minor>.<patch> with optional -prerelease/+build)\n' "$tag" >&2
  exit 1
fi

if [ ! -f "$manifest" ]; then
  # shellcheck disable=SC2016 # literal backticks and $VAR in the message text, not expansions
  printf 'version-check: manifest `%s` not found (run from the repo root, or pass its path)\n' "$manifest" >&2
  exit 1
fi

# Fail-loud floor. A checker that extracts nothing exits 0 forever and reads as
# green, so zero keys and several keys are both refusals rather than a guess.
#
# Count OCCURRENCES (`grep -o`), not matching lines (`grep -c`). This is not a
# nicety — with `grep -c` the whole guard inverts on a single-line manifest:
# `{"name":"x","version":"1.2.3","dep":{"version":"9.9.9"}}` is one line, so the
# count is 1, the ambiguity refusal never fires, and the greedy `.*` in the sed
# below takes the LAST match. Measured: `v9.9.9` passed clean while the
# top-level version a plugin install actually reads was 1.2.3, and the correct
# `v1.2.3` was rejected. Any reflow (`jq -c`, a formatter) or a nested block
# that carries its own version reaches that state.
#
# Do NOT "fix" this by anchoring the key to the start of a line instead: that
# quietly converts refuse-on-ambiguity into read-whichever-is-top-level, which
# is a guess.
key_count=$(grep -oE '"version"[[:space:]]*:' "$manifest" | wc -l | tr -d ' ')
[ -n "$key_count" ] || key_count=0

if [ "$key_count" -eq 0 ]; then
  # shellcheck disable=SC2016 # literal backticks and $VAR in the message text, not expansions
  printf 'version-check: manifest `%s` has no "version" key; refusing to report a false clean pass — extraction is broken\n' "$manifest" >&2
  exit 1
fi

if [ "$key_count" -gt 1 ]; then
  # shellcheck disable=SC2016 # literal backticks and $VAR in the message text, not expansions
  printf 'version-check: manifest `%s` has %s "version" keys — ambiguous, refusing to guess which one the tag should match\n' "$manifest" "$key_count" >&2
  exit 1
fi

manifest_version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest")

if [ -z "$manifest_version" ]; then
  # shellcheck disable=SC2016 # literal backticks and $VAR in the message text, not expansions
  printf 'version-check: found a "version" key in `%s` but could not extract its value; refusing to report a false clean pass — extraction is broken\n' "$manifest" >&2
  exit 1
fi

# Validated before it is echoed anywhere below, so a junk manifest value is
# rejected on shape rather than quoted back as if it were a version.
#
# The line count is not redundant with the shape check that follows it: `grep`
# matches line by line, so a MULTI-line value satisfies `^...$` as soon as any
# one of its lines does.
#
# Be precise about its status: this is UNREACHABLE while the key-count floor
# above stands, because `sed -n ...p` emits one line per matching input line and
# two matches now refuse before reaching here. It is verified by mutation, not
# by fixture — no fixture can reach it. If you ever weaken the floor above, this
# is what catches the fallout; that is the only reason it is here.
if [ "$(printf '%s' "$manifest_version" | wc -l | tr -d ' ')" -ne 0 ]; then
  # shellcheck disable=SC2016 # literal backticks and $VAR in the message text, not expansions
  printf 'version-check: manifest `%s` yielded a multi-line version value — refusing to use it\n' "$manifest" >&2
  exit 1
fi

if ! printf '%s' "$manifest_version" | grep -qE "^${semver_body}$"; then
  # shellcheck disable=SC2016 # literal backticks and $VAR in the message text, not expansions
  printf 'version-check: manifest `%s` version has an invalid shape (expected <major>.<minor>.<patch> with optional -prerelease/+build) — refusing to use it\n' "$manifest" >&2
  exit 1
fi

if [ "$tag" != "v${manifest_version}" ]; then
  # shellcheck disable=SC2016 # literal backticks and $VAR in the message text, not expansions
  printf 'version-check: tag `%s` does not match `%s` version `%s` — expected tag `v%s`. Bump the manifest and the tag together.\n' \
    "$tag" "$manifest" "$manifest_version" "$manifest_version" >&2
  exit 1
fi

# shellcheck disable=SC2016 # literal backticks and $VAR in the message text, not expansions
printf 'version-check: clean — tag `%s` matches `%s` version `%s`\n' "$tag" "$manifest" "$manifest_version"
