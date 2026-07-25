#!/usr/bin/env bash
#
# run-stats.sh — aggregate the "## Run stats" blocks out of plan files.
#
# Reads every *.md in one or more plans directories, pulls the fenced block that
# follows a "## Run stats" heading, and prints one row per run plus the headline
# ratios.
#
# scripts/run-stats.example.md is the single source of truth for the key list.
# Change the keys there first, then here and in skills/plan-gates/SKILL.md.
#
# Parsing discipline: the input is hand-edited Markdown, so values are treated
# as opaque strings and never executed — no eval, no source, no command
# substitution on parsed content. Keys outside the allowlist are ignored rather
# than assigned, control bytes are stripped before printing, and a block that
# yields no recognised key is counted as malformed and skipped rather than
# killing the run.
#
# A run is excluded from the ratios entirely unless all seven counter values
# parse as integers — "unknown" removes the run from both numerator and
# denominator, rather than quietly acting as a zero.
#
# Usage:
#   scripts/run-stats.sh [plans-dir ...]      # default: docs/plans
#   scripts/run-stats.sh ~/code/*/docs/plans  # aggregate across projects
#
# Tested against gawk only. CI exercises one awk implementation; mawk and busybox
# awk are untried, so treat portability as unverified rather than assumed.
#
# Plan files live wherever the project keeps them; this repo gitignores docs/,
# but that is a property of this repo, not of the workflow.

set -euo pipefail

if [[ $# -eq 0 ]]; then
  set -- docs/plans
fi

files=()
for dir in "$@"; do
  if [[ ! -d "$dir" ]]; then
    echo "run-stats: no such directory: $dir" >&2
    exit 1
  fi
  shopt -s nullglob
  for f in "$dir"/*.md; do
    [[ -f "$f" && -r "$f" ]] && files+=("$f")
  done
  shopt -u nullglob
done

if [[ ${#files[@]} -eq 0 ]]; then
  echo "run-stats: no plan files in $* — nothing to aggregate."
  exit 0
fi

awk -v nfiles="${#files[@]}" '
function reset() { split("", cur); nkeys = 0 }

function finish(   i, k, v, complete) {
  if (!started) { reset(); return }
  started = 0
  if (nkeys == 0) { malformed++; reset(); return }

  n++
  for (i = 1; i <= na; i++) row[n, ak[i]] = (ak[i] in cur) ? cur[ak[i]] : "?"

  k = row[n, "date"] SUBSEP row[n, "slug"]
  if (k in seen) dupes++
  seen[k] = 1

  complete = 1
  for (i = 1; i <= nn; i++) {
    v = (numf[i] in cur) ? cur[numf[i]] : ""
    if (v ~ /^[0-9]+$/) continue
    complete = 0
    if (v == "unknown" || v == "") unkvals++
    else suspect++
  }

  if (complete) {
    usable++
    for (i = 1; i <= nn; i++) sum[numf[i]] += cur[numf[i]]
  } else {
    incomplete++
  }
  reset()
}

function pct(a, b) { return (b > 0) ? sprintf("%5.1f%%", 100 * a / b) : "    n/a" }

function diagnostics() {
  if (incomplete) printf "\n%d run(s) excluded from the ratios (incomplete counters).\n", incomplete
  if (unkvals)    printf "%d counter(s) recorded as unknown or missing.\n", unkvals
  if (suspect)    printf "%d counter(s) were neither an integer nor \"unknown\" and could not be used.\n", suspect
  if (malformed || badlines) printf "skipped: %d malformed block(s), %d unparsable line(s).\n", malformed + 0, badlines + 0
  if (dupes)      printf "%d duplicate (date, slug) row(s) — check for copied plan files.\n", dupes
}

function cell(i, stage) {
  return row[i, "findings_" stage "_actioned"] "/" row[i, "findings_" stage "_rejected"] "/" row[i, "findings_" stage "_dropped"]
}

BEGIN {
  nn = split("findings_plan_actioned findings_plan_rejected findings_plan_dropped " \
             "findings_diff_actioned findings_diff_rejected findings_diff_dropped " \
             "escaped", numf, " ")
  na = split("date slug gear effort_plan effort_diff " \
             "findings_plan_actioned findings_plan_rejected findings_plan_dropped " \
             "findings_diff_actioned findings_diff_rejected findings_diff_dropped " \
             "escaped agents_spawned gates_failed_first_pass escalated_from", ak, " ")
  for (i = 1; i <= na; i++) allowed[ak[i]] = 1
}

{ sub(/\r$/, "") }

FNR == 1 { finish(); instats = 0; fence = 0; collecting = 0 }

/^[ \t]*```/ {
  if (fence) {
    fence = 0
    if (collecting) { collecting = 0; finish(); instats = 0 }
  } else {
    fence = 1
    if (instats) collecting = 1
  }
  next
}

!fence && /^##[ \t]*Run stats[ \t]*$/ { finish(); instats = 1; started = 1; reset(); next }

!fence && instats && /^#/ { finish(); instats = 0 }

collecting {
  line = $0
  gsub(/^[ \t]+|[ \t]+$/, "", line)
  if (line == "" || line ~ /^#/) next
  p = index(line, ":")
  if (p == 0) { badlines++; next }
  key = substr(line, 1, p - 1)
  val = substr(line, p + 1)
  gsub(/^[ \t]+|[ \t]+$/, "", key)
  gsub(/^[ \t]+|[ \t]+$/, "", val)
  gsub(/[\001-\037\177]/, "?", val)
  if (key !~ /^[a-z_]+$/ || !(key in allowed) || val == "") { badlines++; next }
  cur[key] = val
  nkeys++
  next
}

END {
  finish()

  printf "%d block(s) from %d file(s) scanned.\n\n", n, nfiles
  if (n == 0) {
    print "run-stats: no run-stats blocks found."
    if (malformed || badlines) printf "(%d malformed, %d unparsable line(s))\n", malformed + 0, badlines + 0
    exit 0
  }

  printf "%-11s %-24s %-5s %-9s %-10s %-10s %4s %6s %5s %-8s\n", \
         "DATE", "SLUG", "GEAR", "EFFORT", "PLAN a/r/d", "DIFF a/r/d", "ESC", "AGENTS", "GATES", "FROM"
  for (i = 1; i <= n; i++)
    printf "%-11s %-24s %-5s %-9s %-10s %-10s %4s %6s %5s %-8s\n", \
      substr(row[i, "date"], 1, 11), substr(row[i, "slug"], 1, 24), substr(row[i, "gear"], 1, 5), \
      substr(row[i, "effort_plan"] "/" row[i, "effort_diff"], 1, 9), \
      substr(cell(i, "plan"), 1, 10), substr(cell(i, "diff"), 1, 10), \
      substr(row[i, "escaped"], 1, 4), substr(row[i, "agents_spawned"], 1, 6), \
      substr(row[i, "gates_failed_first_pass"], 1, 5), substr(row[i, "escalated_from"], 1, 8)

  if (usable == 0) {
    print "\nNo run had a complete set of counters — no ratios computed."
    diagnostics()
    exit 0
  }

  real  = sum["findings_plan_actioned"] + sum["findings_diff_actioned"] + sum["escaped"]
  found = sum["findings_plan_actioned"] + sum["findings_plan_rejected"] + sum["findings_plan_dropped"] \
        + sum["findings_diff_actioned"] + sum["findings_diff_rejected"] + sum["findings_diff_dropped"]
  rej   = sum["findings_plan_rejected"] + sum["findings_diff_rejected"]
  drop  = sum["findings_plan_dropped"] + sum["findings_diff_dropped"]

  printf "\nRatios over %d complete run(s).\n", usable
  printf "Actioned findings + escapes: %d   (these three partition it, so they sum to 100%%)\n", real
  printf "  caught at plan stage   %s  (%d/%d)\n", pct(sum["findings_plan_actioned"], real), sum["findings_plan_actioned"], real
  printf "  caught at diff stage   %s  (%d/%d)\n", pct(sum["findings_diff_actioned"], real), sum["findings_diff_actioned"], real
  printf "  escaped both passes    %s  (%d/%d)   <- the number that matters\n", pct(sum["escaped"], real), sum["escaped"], real
  printf "Critic findings raised: %d\n", found
  printf "  critic rejection rate  %s  (%d/%d)\n", pct(rej, found), rej, found
  printf "  %d dropped without individual reasons — excluded from the defect count by assumption\n", drop

  diagnostics()
}
' "${files[@]}"
