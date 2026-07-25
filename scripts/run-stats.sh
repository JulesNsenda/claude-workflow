#!/usr/bin/env bash
#
# run-stats.sh — aggregate the "## Run stats" blocks out of plan files.
#
# Reads every *.md in a plans directory, pulls the fenced block that follows a
# "## Run stats" heading, and prints one row per run plus three ratios:
# plan-stage catch rate, critic rejection rate, and escape rate.
#
# scripts/run-stats.example.md is the single source of truth for the key list.
# Change the keys there first, then here and in skills/plan-gates/SKILL.md.
#
# Parsing discipline: the input is hand-edited Markdown, so values are treated
# as opaque strings and never executed — no eval, no source, no command
# substitution on parsed content. Keys outside the allowlist are ignored rather
# than assigned, and a block that yields no recognised key is counted as
# malformed and skipped rather than killing the run.
#
# "unknown" is excluded from the sums instead of counting as zero, so a run that
# honestly didn't know a number can't drag a ratio toward looking good.
#
# Usage:
#   scripts/run-stats.sh [plans-dir]     # default: docs/plans
#
# Note: docs/ is gitignored, so this data is local to your machine.

set -euo pipefail

dir="${1:-docs/plans}"

if [[ ! -d "$dir" ]]; then
  echo "run-stats: no such directory: $dir" >&2
  exit 1
fi

shopt -s nullglob
files=("$dir"/*.md)
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  echo "run-stats: no plan files in $dir — nothing to aggregate."
  exit 0
fi

awk '
function reset(   i) { split("", cur); nkeys = 0 }

function finish(   i) {
  if (!started) { reset(); return }
  started = 0
  if (nkeys == 0) { malformed++; reset(); return }

  n++
  for (i = 1; i <= na; i++) row[n, ak[i]] = (ak[i] in cur) ? cur[ak[i]] : "?"

  for (i = 1; i <= nn; i++) {
    v = (numf[i] in cur) ? cur[numf[i]] : ""
    if (v ~ /^[0-9]+$/) sum[numf[i]] += v
    else if (v == "unknown") unk[numf[i]]++
  }
  reset()
}

function pct(a, b) { return (b > 0) ? sprintf("%5.1f%%", 100 * a / b) : "    n/a" }

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

FNR == 1 { finish(); instats = 0; infence = 0 }

instats && !infence && /^## / { finish(); instats = 0 }

/^##[ \t]*Run stats[ \t]*$/ { finish(); instats = 1; started = 1; reset(); next }

instats && /^[ \t]*```/ {
  if (!infence) { infence = 1; next }
  infence = 0; finish(); instats = 0; next
}

instats && infence {
  line = $0
  gsub(/^[ \t]+|[ \t]+$/, "", line)
  if (line == "" || line ~ /^#/) next
  p = index(line, ":")
  if (p == 0) { badlines++; next }
  key = substr(line, 1, p - 1)
  val = substr(line, p + 1)
  gsub(/^[ \t]+|[ \t]+$/, "", key)
  gsub(/^[ \t]+|[ \t]+$/, "", val)
  if (key !~ /^[a-z_]+$/ || !(key in allowed) || val == "") { badlines++; next }
  cur[key] = val
  nkeys++
  next
}

END {
  finish()

  if (n == 0) {
    print "run-stats: no run-stats blocks found (" malformed + 0 " malformed, " badlines + 0 " unparsable lines)."
    exit 0
  }

  printf "%-11s %-26s %-5s %-11s %-11s %5s %7s %6s\n", \
         "DATE", "SLUG", "GEAR", "PLAN a/r/d", "DIFF a/r/d", "ESC", "AGENTS", "GATES"
  for (i = 1; i <= n; i++)
    printf "%-11s %-26s %-5s %-11s %-11s %5s %7s %6s\n", \
      row[i, "date"], substr(row[i, "slug"], 1, 26), row[i, "gear"], \
      cell(i, "plan"), cell(i, "diff"), row[i, "escaped"], \
      row[i, "agents_spawned"], row[i, "gates_failed_first_pass"]

  real  = sum["findings_plan_actioned"] + sum["findings_diff_actioned"] + sum["escaped"]
  found = sum["findings_plan_actioned"] + sum["findings_plan_rejected"] + sum["findings_plan_dropped"] \
        + sum["findings_diff_actioned"] + sum["findings_diff_rejected"] + sum["findings_diff_dropped"]
  rej   = sum["findings_plan_rejected"] + sum["findings_diff_rejected"]

  printf "\n%d run(s).\n", n
  printf "Real defects (plan actioned + diff actioned + escaped): %d\n", real
  printf "  plan-stage catch rate  %s  (%d/%d)\n", pct(sum["findings_plan_actioned"], real), sum["findings_plan_actioned"], real
  printf "  escape rate            %s  (%d/%d)   <- the number that matters\n", pct(sum["escaped"], real), sum["escaped"], real
  printf "Critic findings (actioned + rejected + dropped): %d\n", found
  printf "  critic rejection rate  %s  (%d/%d)\n", pct(rej, found), rej, found

  if (malformed || badlines) printf "\nskipped: %d malformed block(s), %d unparsable line(s).\n", malformed + 0, badlines + 0
  u = 0
  for (i = 1; i <= nn; i++) u += unk[numf[i]] + 0
  if (u) printf "%d value(s) recorded as unknown and excluded from the ratios.\n", u
}

function cell(i, stage) {
  return row[i, "findings_" stage "_actioned"] "/" row[i, "findings_" stage "_rejected"] "/" row[i, "findings_" stage "_dropped"]
}
' "${files[@]}"
