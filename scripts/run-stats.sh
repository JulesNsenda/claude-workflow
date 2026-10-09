#!/usr/bin/env bash
#
# run-stats.sh — aggregate the "## Run stats" blocks out of plan files.
#
# Reads every *.md in one or more plans directories, pulls the fenced block under
# each "## Run stats" heading, and prints one row per run plus the headline
# ratios. scripts/run-stats.example.md is the single source of truth for the
# format: the key list, and the heading and fence rules. Change the keys there
# first, then here and in skills/plan-gates/SKILL.md.
#
# Parsing discipline: the input is hand-edited Markdown, so values are treated
# as opaque strings and never executed — no eval, no source, no command
# substitution on parsed content. Keys outside the allowlist are ignored rather
# than assigned, control bytes (C0, DEL, UTF-8 C1) are replaced with ? in every
# printed value and filename, and a block that yields no recognised key is
# skipped rather than killing the run. Skipped sections are listed by file:line,
# not just counted: silent survivorship bias was the thing this was written to
# stop.
#
# Output besides the table and ratios:
#   stdout  "never filled in" (a heading with no fence), "malformed" (a fence
#           with no recognised key), "still pending" (a run with `pending` in
#           any key), a gates_failed value that is not a list of gates,
#           duplicate blocks (identical values), and (date, slug) pairs shared
#           across files with different values.
#   stderr  a near-miss heading that was not parsed; an unclosed fence (its
#           partial block is discarded, never counted); a second block under
#           one heading (not parsed).
#
# gear is full or light (a block with no gear key is read as full, as before; any
# other value is listed by file:line and the run is left out of every ratio). The
# headline (plan / diff / escaped partition, rejection rate) is computed over full
# runs only, so the light gear's thinner records can never dilute it. Light runs
# get a line of their own right under "escaped both passes", printed only when a
# complete light run exists (or k > 0): escaped / (diff actioned + escaped), plus how many
# full runs were escalated from light (light runs that went badly were escalated
# and recorded as full, so the light rate is biased low - the k flags that). With
# no full-gear run at all the headline, rejection and "dropped" lines are omitted
# ("No full-gear run" replaces them), so the last line is then the light line or
# a diagnostic; the "last line is dropped" drift invariant holds for any corpus
# with a complete full run and no diagnostics, which the canonical example is.
# k counts every full run escalated from light, complete or not, and the light
# line prints for k > 0 even with no complete light run ("n/a (0 runs; ...)").
#
# A full run is excluded from the ratios entirely unless all seven counter values
# parse as integers — "unknown" removes the run from both numerator and
# denominator, rather than quietly acting as a zero. "pending" ("not reached
# yet", a seeded block that was never closed) does the same whichever key holds
# it, but is reported apart and by file, so an in-flight or abandoned run is told
# from one whose counters were never knowable. A light run writes no plan-stage
# keys, so only its three diff counters and escaped must be integers.
#
# gates_failed is a dimension, not a ratio counter: apart from a pending value (see
# above) it never keeps a run out.
# Its normalised list fills the GATES column and feeds the fix-loop tally printed
# under the table. A legacy gates_failed_first_pass count renders as n=2, so it
# cannot be read as "gate 2".
#
# Usage:
#   scripts/run-stats.sh [plans-dir ...]      # default: docs/plans
#   scripts/run-stats.sh ~/code/*/docs/plans  # aggregate across projects
#
# CI logs which awk ran. Only that implementation is exercised, so mawk and
# busybox awk portability is unverified rather than assumed.
#
# Plan files live wherever the project keeps them; this repo gitignores docs/,
# but that is a property of this repo, not of the workflow.

set -euo pipefail

if [[ $# -eq 0 ]]; then
  set -- docs/plans
fi

# One sanitiser for everything printed, defined once and used both by the main
# awk program and by safe() below. C0, DEL, UTF-8-encoded C1 (which a terminal can
# act on) and the bidi controls (LRM/RLM/ALM, U+202A-202E, U+2066-2069, which can
# reorder what a reader sees) all become "?". Filenames go through it too - they
# are attacker-shaped text just like values. The C1 claim is scoped to
# UTF-8-encoded C1: a lone 8-bit C1 byte is out of scope, because 0x80-0x9F are
# also UTF-8 continuation bytes and stripping them would mangle valid text.
clean_awk='function clean(s) {
  gsub(/[\001-\037\177]/, "?", s)
  gsub(/\302[\200-\237]/, "?", s)
  gsub(/\342\200[\216\217\252-\256]/, "?", s)
  gsub(/\342\201[\246-\251]/, "?", s)
  gsub(/\330\234/, "?", s)
  return s
}'

# Directory names are user input and end up in messages. Passed via the
# environment, not -v, because -v would interpret backslash escapes.
safe() { S=$1 LC_ALL=C awk "$clean_awk
BEGIN { printf \"%s\", clean(ENVIRON[\"S\"]) }"; }

files=()
seen_dirs=()
for dir in "$@"; do
  if [[ ! -d "$dir" ]]; then
    echo "run-stats: no such directory: $(safe "$dir")" >&2
    exit 1
  fi
  # Dedupe directories (by canonical path), so the same directory given twice,
  # or spelled two ways, is not counted twice. A seen-list, not an associative
  # array: macOS bash is 3.2. Files keep the spelling the user typed, so
  # listings print what they wrote.
  # CDPATH= so cd cannot print or resolve elsewhere; a directory named - is
  # read as a path, not "previous directory"; the trailing . survives $(...)
  # stripping a name that ends in a newline.
  cdir=$dir; [[ $cdir == - ]] && cdir=./-
  canon=$(CDPATH='' cd -P -- "$cdir" 2>/dev/null && pwd -P && printf .) || { echo "run-stats: cannot enter directory: $(safe "$dir")" >&2; exit 1; }
  canon=${canon%.}
  for d in ${seen_dirs[@]+"${seen_dirs[@]}"}; do
    [[ $d == "$canon" ]] && continue 2
  done
  seen_dirs+=("$canon")
  shopt -s nullglob
  for f in "$dir"/*.md; do
    [[ -f "$f" && -r "$f" ]] || continue
    # A path shaped like x=y would be taken by awk as a variable assignment,
    # not a file. Only those get "./": prefixing everything breaks C:/ paths
    # under Git Bash, where awk cannot open ./C:/....
    if [[ $f =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then f="./$f"; fi
    files+=("$f")
  done
  shopt -u nullglob
done

if [[ ${#files[@]} -eq 0 ]]; then
  echo "run-stats: no plan files in $(safe "$*") — nothing to aggregate."
  exit 0
fi

# The awk program lives in a variable, not inline, so that clean_awk can be
# prepended to it here and reused by safe() above: one sanitiser, two callers.
IFS= read -r -d '' prog <<'AWK' || true
function reset() { split("", cur); nkeys = 0 }

# The printable file:line of the block being finished (see the note on finish()).
function where() { return clean(bfile) ":" bline }

# Normalise a gates_failed value: "none", "pending" and "unknown" pass through; a
# list of gates 1-5 has its brackets and spaces dropped, its duplicates collapsed
# and its order fixed ("[4, 2,4]" -> "2,4"). Anything else - a gate outside 1-5,
# an empty element, "none" mixed into a list - returns "": malformed.
function gnorm(v,   t, parts, np, j, s, out, g) {
  if (v == "none" || v == "pending" || v == "unknown") return v
  t = v
  gsub(/\[/, "", t); gsub(/\]/, "", t); gsub(/[ \t]/, "", t)
  np = split(t, parts, ",")
  for (j = 1; j <= np; j++) {
    if (parts[j] !~ /^[1-5]$/) return ""
    s[parts[j]] = 1
  }
  out = ""
  for (g = 1; g <= 5; g++) if (g in s) out = out (out == "" ? "" : ",") g
  return out
}

# Heading level of the current line: the number of leading #s after 0-3 spaces,
# 0 if none. Sets htext to what follows them. No space is required after the #s,
# so "##Run stats" is a level-2 heading, as it always was. A run of #s is one
# level however long, so "###" is level 3, never level 1 or 2 (also, "#1 note"
# is level 1: a known quirk, left as it was).
function hlevel(   h) {
  htext = ""
  if (!match($0, /^ ? ? ?#+/)) return 0
  h = substr($0, 1, RLENGTH); htext = substr($0, RLENGTH + 1)
  gsub(/ /, "", h)
  return length(h)
}

# Line-by-line states (fence / instats / collecting / blockdone):
#   outside              0 / 0 / 0 / -   nothing of interest
#   section              0 / 1 / 0 / 0   after an accepted heading, no block yet
#   section-after-block  0 / 1 / 0 / 1   the block closed; another is warned about
#   stats-fence          1 / 1 / 1 / -   collecting key: value lines
#   other-fence          1 / any / 0 / - ordinary code; everything inside is text
# Only a stats fence ends in a row. Everything else is classified, not dropped.

# An unclosed fence swallowed whatever followed it. The closing fence is the only
# evidence a block is complete, so its partial block is thrown away (nkeys = 0)
# and the section is listed as malformed - including when the unclosed fence was
# ordinary code inside a stats section. One function for every evidence path: a
# stats heading or an info-string fence inside the stats fence, a file boundary,
# EOF. finish() is idempotent through started, so calling it here is safe.
function abandon() {
  print "run-stats: unclosed fence: " clean(ffile) ":" fline > "/dev/stderr"
  nkeys = 0; fence = 0; collecting = 0; hadstatsfence = 1
  finish(); instats = 0
}

# End of a file (and of the input): whatever is still open is settled here.
function flush_file() {
  if (fence) abandon()
  finish()
}

# Reports come from bfile/bline, captured at the heading. An EOF section is
# finished while the first line of the next file is current, so FILENAME would
# name the wrong file.
function finish(   i, k, v, vk, complete, haspend, g, gclass) {
  if (!started) { reset(); return }
  started = 0
  if (nkeys == 0) {
    if (hadstatsfence) { malformed++; mlist[malformed] = where() }
    else          { unfilled++;  ulist[unfilled]  = where() }
    reset(); return
  }

  n++
  for (i = 1; i <= na; i++) row[n, ak[i]] = (ak[i] in cur) ? cur[ak[i]] : "?"

  # "pending" in ANY key means the block was never closed, and its running totals
  # may be partial, so the run stays out of the ratios and is listed by file. That
  # is separate from unknown and suspect, which say a counter cannot be used and
  # are counted for the seven counters only (a light run's four, a bad-gear run's
  # none - it has no partition to be scored in).
  gclass = ("gear" in cur) ? cur["gear"] : "full"
  if (gclass == "pending") gclass = "full"
  else if (gclass != "full" && gclass != "light") { gclass = "bad"; gearbad++; gblist[gearbad] = where() }

  haspend = 0
  for (i = 1; i <= na; i++) if ((ak[i] in cur) && cur[ak[i]] == "pending") haspend = 1
  if (haspend) { pending++; plist[pending] = where() }
  complete = (gclass != "bad" && !haspend)
  if (gclass != "bad") {
    for (i = 1; i <= na; i++) {
      v = (ak[i] in cur) ? cur[ak[i]] : ""
      if (v != "pending" && isnum[ak[i]] && (gclass != "light" || lightnum[ak[i]]) && v !~ /^[0-9]+$/) {
        complete = 0
        if (v == "unknown" || v == "") unkvals++
        else suspect++
      }
    }
  }
  if (gclass == "full") {
    nfull++
    if (cur["escalated_from"] == "light") kesc++
  }

  # The GATES cell. gates_failed wins over the legacy count; a malformed value is
  # shown as written and listed. Only a list or "none" joins the tally (none is a
  # run with zero loops); unknown, and any pending run, say nothing about where
  # loops were. A legacy count is shown as n=<value> so it cannot read as a gate
  # list, and is counted apart as not tallied. The normalised value replaces the
  # raw one in row[], so the duplicate check below sees "2,4" and "[4, 2]" as one.
  gd[n] = "?"
  if ("gates_failed" in cur) {
    g = gnorm(cur["gates_failed"])
    gd[n] = (g == "") ? cur["gates_failed"] : g
    if (g == "") { gbad++; glist[gbad] = where() }
    else {
      row[n, "gates_failed"] = g
      if (g != "unknown" && !haspend) {
        gruns++
        for (k = 1; k <= 5; k++) if (index("," g ",", "," k ",")) gtally[k]++
      }
    }
  } else if ("gates_failed_first_pass" in cur) {
    v = cur["gates_failed_first_pass"]
    gd[n] = (v == "none" || v == "unknown" || v == "pending") ? v : "n=" v
    legacy++
  }

  # One rule: a block whose every allowlisted value matches an earlier one is a
  # duplicate, in the same file (a paste) or another (a copied plan). Sharing only
  # a date and slug is not: unrelated plans can share a name across projects.
  vk = ""
  for (i = 1; i <= na; i++) vk = vk SUBSEP row[n, ak[i]]
  # Otherwise, worth saying: the same (date, slug) in more than one file with
  # different values is a stale copy or a name collision. Cross-file only (in one
  # file it is a legitimate run per heading), counted once per pair: pairfile
  # holds the first file, and "" once the pair has warned.
  k = row[n, "date"] SUBSEP row[n, "slug"]
  if (vk in seenv) dupes++
  else if (!(k in pairfile)) pairfile[k] = bfile
  else if (pairfile[k] != "" && pairfile[k] != bfile) { pairs++; pairfile[k] = "" }
  seenv[vk] = 1

  if (complete && gclass == "light") {
    lusable++
    ldiff += cur["findings_diff_actioned"]; lesc += cur["escaped"]
  } else if (complete) {
    usable++
    for (i = 1; i <= nn; i++) sum[numf[i]] += cur[numf[i]]
  } else if (gclass != "bad") {
    incomplete++
  }
  reset()
}

function pct(a, b) { return (b > 0) ? sprintf("%5.1f%%", 100 * a / b) : "    n/a" }

# k > 0 alone still prints, so the selection-bias count cannot vanish with the
# light runs it flags. Unpadded: it is a sentence, not a column.
function lightline(   d) {
  if (!lusable && !kesc) return
  d = ldiff + lesc
  printf "light gear: escaped review %s (%d runs; %d full runs escalated from light)\n", \
    (d > 0) ? sprintf("%.1f%%", 100 * lesc / d) : "n/a", lusable, kesc + 0
}

# title is the text after the count; each entry prints as an indented file:line.
function listing(title, arr, count,   i) {
  if (!count) return
  printf "\n%d %s\n", count, title
  for (i = 1; i <= count; i++) printf "  %s\n", arr[i]
}

function diagnostics() {
  if (incomplete) printf "\n%d run(s) excluded from the ratios (incomplete counters).\n", incomplete
  if (unkvals)    printf "%d counter(s) recorded as unknown or missing.\n", unkvals
  if (suspect)    printf "%d counter(s) were neither an integer nor \"unknown\" and could not be used.\n", suspect
  # The CI drift regex matches this line by its "skipped:" prefix; keep it as is.
  if (malformed || badlines) printf "skipped: %d malformed block(s), %d unparsable line(s).\n", malformed + 0, badlines + 0
  if (dupes)      printf "%d duplicate block(s) (identical values) — check for copied plan files.\n", dupes
  if (pairs)      printf "%d (date, slug) pair(s) appear in more than one file with different values — a stale copy or a name collision.\n", pairs
  listing("stats section(s) never filled in:", ulist, unfilled)
  listing("run(s) still pending (unfinished or abandoned):", plist, pending)
  listing("malformed block(s) (fence with no recognised key):", mlist, malformed)
  listing("gates_failed value(s) not none, pending, unknown or a list of gates 1–5:", glist, gbad)
  listing("gear value(s) not full or light (run left out of the ratios):", gblist, gearbad)
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
             "escaped agents_spawned gates_failed gates_failed_first_pass escalated_from", ak, " ")
  for (i = 1; i <= na; i++) allowed[ak[i]] = 1
  for (i = 1; i <= nn; i++) isnum[numf[i]] = 1
  nl = split("findings_diff_actioned findings_diff_rejected findings_diff_dropped escaped", lk, " ")
  for (i = 1; i <= nl; i++) lightnum[lk[i]] = 1
}

{ sub(/\r$/, "") }

{ hl = hlevel() }

FNR == 1 { flush_file(); instats = 0 }

/^[ \t]*```/ {
  match($0, /```+/); run = RLENGTH
  rest = substr($0, RSTART + RLENGTH); gsub(/^[ \t]+|[ \t]+$/, "", rest)
  # An info-string fence at least as long as the opener, seen while collecting,
  # means the stats fence never closed. Fall-through, deliberately: after
  # abandon() fence is 0, so this same line is handled below as a fresh opener
  # (an ordinary fence, since the section is over). Shorter, or inside any other
  # fence, an info-string line is just content.
  if (fence && collecting && rest != "" && run >= flen) abandon()
  if (fence) {
    # Closes only on a bare backtick line at least as long as the opener; any
    # other backtick line inside a fence is content.
    if (rest == "" && run >= flen) {
      fence = 0
      if (collecting) {
        collecting = 0
        # A keyless fence (a placeholder) must not take the heading's slot: leave
        # started set, so a real block under the same heading still counts and a
        # section with only placeholders is listed as malformed at its end.
        if (nkeys > 0) { blockdone = 1; finish() }
      }
    }
    next
  }
  fence = 1; flen = run; ffile = FILENAME; fline = FNR
  if (instats) {
    split(tolower(rest), w, /[ \t]+/)
    if (w[1] == "" || w[1] == "yaml" || w[1] == "yml") {
      if (blockdone) print "run-stats: second block under one heading (use \"## Run stats — <label>\"): " clean(FILENAME) ":" FNR > "/dev/stderr"
      else { collecting = 1; hadstatsfence = 1 }
    }
  }
  next
}

# An accepted stats heading: level 2, then exactly "Run stats", which must end the
# heading or be followed by a non-word byte, so a suffixed heading parses and
# "## Run statsheet" does not. 0-3 leading spaces are a heading; a tab or 4+ are a
# code block. Not inside a fence - there it is quoted text - except the stats
# fence itself: an accepted heading seen while collecting is the only evidence
# that counts that it was never closed (a generic "## ..." line is a valid YAML
# comment). abandon() settles that, then the heading starts the new section.
(!fence || collecting) && hl == 2 && htext ~ /^[ \t]*Run stats([^A-Za-z0-9_]|$)/ {
  if (collecting) abandon()
  finish(); instats = 1; started = 1; hadstatsfence = 0; blockdone = 0; bfile = FILENAME; bline = FNR; reset(); next
}

# Near miss: a level 2+ heading (0-3 leading spaces, any case) that says "run
# stats" but was not accepted above. Level 1 is exempt - the title of the example
# file is "# Run stats". So is a level 3+ heading inside an accepted section: it
# is a sub-heading there. tolower is ASCII-only under LC_ALL=C.
!fence && hl >= 2 && !(instats && hl >= 3) && tolower(htext) ~ /^[ \t]*run[ \t]+stats([^A-Za-z0-9_]|$)/ {
  print "run-stats: heading not parsed (expected \"## Run stats\"): " clean(FILENAME) ":" FNR > "/dev/stderr"
}

# A section ends only at an H1 or H2, so a "### Phase 1" sub-heading inside it
# does not cut the block off.
!fence && instats && (hl == 1 || hl == 2) { finish(); instats = 0 }

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
  val = clean(val)
  if (key !~ /^[a-z_]+$/ || !(key in allowed) || val == "") { badlines++; next }
  cur[key] = val
  nkeys++
  next
}

END {
  flush_file()

  printf "%d block(s) from %d file(s) scanned.\n\n", n, nfiles
  if (n == 0) {
    print "run-stats: no run-stats blocks found."
    diagnostics()
    exit 0
  }

  printf "%-11s %-24s %-5s %-9s %-10s %-10s %4s %6s %-9s %-8s\n", \
         "DATE", "SLUG", "GEAR", "EFFORT", "PLAN a/r/d", "DIFF a/r/d", "ESC", "AGENTS", "GATES", "FROM"
  for (i = 1; i <= n; i++)
    printf "%-11s %-24s %-5s %-9s %-10s %-10s %4s %6s %-9s %-8s\n", \
      substr(row[i, "date"], 1, 11), substr(row[i, "slug"], 1, 24), substr(row[i, "gear"], 1, 5), \
      substr(row[i, "effort_plan"] "/" row[i, "effort_diff"], 1, 9), \
      substr(cell(i, "plan"), 1, 10), substr(cell(i, "diff"), 1, 10), \
      substr(row[i, "escaped"], 1, 4), substr(row[i, "agents_spawned"], 1, 6), \
      substr(gd[i], 1, 9), substr(row[i, "escalated_from"], 1, 8)

  # A summary of every parsed row, not a diagnostic, so it sits under the table
  # and before the ratios: the canonical example must still end on the "dropped"
  # line. Printed whenever a row carries a parsed gates_failed or a legacy count (so
  # also when no run is usable). A legacy-only corpus gets zeros plus the "not
  # tallied" suffix, which says why they are zeros rather than reading as "no loops".
  if (gruns || legacy) {
    printf "\nruns with a fix loop, by gate (%d runs with gates_failed): G1 %d · G2 %d · G3 %d · G4 %d · G5 %d", \
      gruns, gtally[1], gtally[2], gtally[3], gtally[4], gtally[5]
    if (legacy) printf " — %d legacy rows not tallied", legacy
    printf "\n"
  }

  if (usable == 0) {
    if (nfull == 0) print "\nNo full-gear run — headline ratios omitted."
    else            print "\nNo full-gear run had a complete set of counters — no headline ratios computed."
    lightline()
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
  lightline()
  printf "Critic findings raised: %d\n", found
  printf "  critic rejection rate  %s  (%d/%d)\n", pct(rej, found), rej, found
  printf "  %d dropped without individual reasons — excluded from the defect count by assumption\n", drop

  diagnostics()
}
AWK

# LC_ALL=C so "byte-level" means the same thing in gawk and mawk: the heading
# boundary and the control-byte classes are byte classes, not locale ones.
# Trade-off, accepted: substr and printf widths then count bytes, so a non-ASCII
# slug can be cut mid-character in the table. clean() needs the byte classes.
LC_ALL=C awk -v nfiles="${#files[@]}" "$clean_awk
$prog" "${files[@]}"
