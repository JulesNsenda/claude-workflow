#!/bin/sh
#
# settings-drift.sh — report which repo settings.json entries are missing or
# different in a real (hand-merged) ~/.claude/settings.json.
#
# The installers never overwrite a real settings.json, so a setting the repo adds
# later (workflowSizeGuideline, PR #3) sat un-merged for two months with nothing
# saying so. This walks the REPO file and names every path the live file lacks.
# It is read-only and never edits either file.
#
# The contract (CLI, exit codes, the ordered "not checked" messages, walk rules,
# output formats, escaping) lives in scripts/settings-drift-fixtures/README.md,
# the single tracked source of truth. Callers such as the installers must ignore
# the exit code and never abort on it.
#
# scripts/settings-drift.ps1 implements the same contract for machines without
# jq (a stock Windows box). scripts/settings-drift-fixtures/ is that contract:
# CI runs both implementations over the same fixtures against the same
# expected-output files. Change a rule in one, change it in both.
#
# Why the walk is shaped this way: it is case- and type-exact and uses PATH
# ARRAYS, never dotted strings. There is deliberately no `contains`/`inside`:
# they substring-match strings, so a live `Read(.env.*)` would "contain" the repo
# rule `Read(.env)` and hide the very gap this exists to find.
#
# A live VALUE is never printed — only its type — so a secret sitting in a
# hand-merged file cannot leak through this report. For the same reason a jq
# error message is never printed (it quotes input), including from the final
# comparison pass, which reports "comparison failed" instead.
#
# Injection discipline: the jq program below is one static single-quoted string
# and both files reach it via --slurpfile. No data is spliced into the program
# and nothing is eval'd.
#
# Known limitation: ONE DIRECTION. A rule the repo later removes stays in a
# hand-merged file forever; this cannot see it. The convention that covers it is
# a CHANGELOG entry "Removed - delete from a hand-merged settings.json".
#
# Known parser divergence (accepted, kept out of the parity fixtures): PowerShell
# rejects keys that differ only in case, and PowerShell 7 tolerates comments and
# trailing commas; jq does the opposite. For such inputs one tool says "could not
# be parsed" and the other reports drift. Number formatting (1.0, large ints) is
# also unmatched between the two encoders — the repo settings hold no numbers.
#
# jq is looked up as ${CLAUDE_WORKFLOW_JQ:-jq}; the variable is the test seam for
# the jq-absent case (PATH games do not work on a runner that ships jq), in the
# same spirit as CLAUDE_WORKFLOW_ALLOW_MSYS in install.sh.

set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: settings-drift.sh <repo-settings> <live-settings>" >&2
  exit 2
fi

repo=$1
live=$2
jq_bin=${CLAUDE_WORKFLOW_JQ:-jq}

not_checked() {
  printf 'settings drift: not checked - %s\n' "$1"
  exit 2
}

command -v "$jq_bin" >/dev/null 2>&1 || not_checked "jq not found"

# --- repo side: parse, then require something to compare ---
# stderr is discarded everywhere below: jq's own message can quote file content.
# shellcheck disable=SC2016 # jq program, single-quoted on purpose
repo_info=$("$jq_bin" -n -r --slurpfile r "$repo" \
  'if ($r | length) == 1 and ($r[0] | type) == "object"
   then ($r[0] | del(."$schema") | length | tostring)
   else "0" end' 2>/dev/null) || not_checked "repo settings.json could not be parsed by jq"
repo_info=$(printf '%s' "$repo_info" | tr -d '\r')
[ "$repo_info" != "0" ] || not_checked "repo settings.json has nothing to compare"

# --- live side ---
[ -e "$live" ] || not_checked "live settings.json not found"
# -f, not just -e: a directory is refused here, and a FIFO would otherwise hang jq.
[ -f "$live" ] || not_checked "live settings.json is not a regular file"

# shellcheck disable=SC2016 # jq program, single-quoted on purpose
live_info=$("$jq_bin" -n -r --slurpfile l "$live" \
  '"\($l | length) \(if ($l | length) == 1 then ($l[0] | type) else "-" end)"' \
  2>/dev/null) || not_checked "live settings.json could not be parsed by jq"
live_info=$(printf '%s' "$live_info" | tr -d '\r')

# --slurpfile yields one element per JSON value: zero is empty/whitespace, two or
# more is a multi-document file. Either is refused rather than guessed at.
case $live_info in
  "1 "*) ;;
  *) not_checked "live settings.json is empty or holds more than one JSON value" ;;
esac
[ "$live_info" = "1 object" ] || not_checked "live settings.json is not a JSON object"

clean_line='settings: no repo setting missing or different (live-only settings not checked)'

# Canonical JSON = keys sorted recursively, compact. jq's tojson keeps insertion
# order, so objects are rebuilt by hand. cmp walks the repo value `.` against the
# live value $l (only meaningful when $ex, i.e. the live side exists there).
# shellcheck disable=SC2016 # the jq program is deliberately single-quoted: $vars are jq's, not the shell's
out=$("$jq_bin" -n -r --slurpfile r "$repo" --slurpfile l "$live" --arg clean "$clean_line" '
  def canon:
    if type == "object" then
      "{" + (to_entries | sort_by(.key)
             | map("\(.key | tojson):\(.value | canon)") | join(",")) + "}"
    elif type == "array" then "[" + (map(canon) | join(",")) + "]"
    else tojson end;
  def cmp($p; $ex; $l):
    if type == "object" then
      if $ex and ($l | type) != "object" then
        "settings drift: differs \($p | tojson) repo object, live \($l | type)"
      elif ($ex | not) and length == 0 then
        "settings drift: missing \($p | tojson) {}"
      else
        . as $o
        | keys_unsorted[] as $k
        | ($ex and ($l | type) == "object" and ($l | has($k))) as $h
        | $o[$k] | cmp($p + [$k]; $h; if $h then $l[$k] else null end)
      end
    elif type == "array" then
      if $ex and ($l | type) != "array" then
        "settings drift: differs \($p | tojson) repo array, live \($l | type)"
      elif ($ex | not) and length == 0 then
        "settings drift: missing \($p | tojson) []"
      else
        .[] as $e
        | select(($ex | not) or (any($l[]; . == $e) | not))
        | "settings drift: missing \($p | tojson) \($e | canon)"
      end
    elif ($ex | not) then
      "settings drift: missing \($p | tojson) \(canon)"
    elif $l != . then
      "settings drift: differs \($p | tojson) repo \(canon), live \($l | type)"
    else empty end;
  [ $r[0] | del(."$schema") | cmp([]; true; $l[0]) ]
  | if length == 0 then $clean else .[] end
' 2>/dev/null) || not_checked "comparison failed"

# jq.exe on Windows may emit CRLF; a real CR can never appear in the output
# because every value is JSON-escaped.
out=$(printf '%s\n' "$out" | tr -d '\r')
printf '%s\n' "$out"

[ "$out" != "$clean_line" ] || exit 0
exit 1
