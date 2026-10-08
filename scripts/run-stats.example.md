# Run stats — canonical format

This file is the single source of truth for the `## Run stats` block that every
full-gear plan file ends with. Three things read this format, and none of them
enforces it on the others:

- `skills/plan-gates/SKILL.md` tells the orchestrator to write the block,
- `scripts/run-stats.sh` parses it,
- this file is what the CI smoke test feeds the parser.

So change the keys **here first**, then in the other two.

## Run stats

The heading above is the real one — this file is also the CI smoke-test
fixture, so it is parsed by `run-stats.sh` on every build and any drift between
this format and the parser fails the build rather than degrading quietly.

**One block per run.** The parser accepts `## Run stats` exactly, or that text
followed by a non-word character, so a later run on the same plan gets its own
heading, such as `## Run stats — phase 2`. A heading like `## Run statsheet`
is not a stats heading. A near miss is a level-2+ heading reading `run stats` with other casing
or level (such as `### Run stats`), outside an accepted section; it is warned
about on stderr and not parsed. Other spellings (`Run-stats`, `Runstats`) are
not detected. A
heading with no fenced block under it is listed as "never filled in"; a fence
with no recognised key is listed as malformed. That includes a placeholder
written *inside* the fence — leave the fence out until there is something to
put in it. The stats fence is `yaml`, `yml` or bare; any other fence in the
section (`bash`, `markdown`) is ordinary code and ignored. One block per
heading: a second one is warned about and not parsed. Only backtick fences are
recognised (`~~~` is not), and a fence closes only on a bare backtick line at
least as long as its opener, so a longer outer fence can quote a shorter one.
A stats fence that is never closed is discarded, not counted. A sub-heading
inside the section is fine: the section ends at the next H1 or H2. A heading
may have 0-3 leading spaces; a tab or 4 or more is a code block, so it is
neither parsed nor warned about.

A fenced block containing **flat `key: value` lines only** — no nesting, no
lists, no quoting, no anchors. The fence says `yaml` because flat scalars are
valid YAML, but the parser is not a YAML parser: a nested map's child lines
would be read as top-level keys.

The numbers below are **illustrative, not a real run** — they exist so the CI
assertions have something to compute. Don't anchor on them.

```yaml
date: 2026-07-25
slug: opus-5-adoption
gear: full
effort_plan: high
effort_diff: high
findings_plan_actioned: 4
findings_plan_rejected: 2
findings_plan_dropped: 0
findings_diff_actioned: 9
findings_diff_rejected: 3
findings_diff_dropped: 0
escaped: 1
agents_spawned: 11
gates_failed_first_pass: 2
escalated_from: none
```

## The keys

| Key | Meaning |
|---|---|
| `date`, `slug` | Match the plan filename. |
| `gear` | `full` - only full-gear runs write this block. |
| `effort_plan`, `effort_diff` | Effort the critics ran at in each pass. |
| `findings_*_actioned` | Findings that changed the work. |
| `findings_*_rejected` | Findings consciously rejected **with a written reason**. Not a failure — this is the critic-noise signal. |
| `findings_*_dropped` | `medium`/`low` findings dropped without individual reasons. Counted so the rejection rate can't read as a whole-panel number when it only saw the severe tail. |
| `escaped` | Defects **both critic passes missed**, caught at Gate 3, Gate 4, or by you afterwards. The most important number here. |
| `agents_spawned` | Total across both phases, including fix-loop re-runs. |
| `gates_failed_first_pass` | How many of gates 1–5 needed a fix loop. `none` if all passed first time. Gate 5's re-verification counts as part of Gate 5, not as a second failure of gates 3–4. |
| `escalated_from` | The gear the task *started* at if it moved up (`skip`, `light`); `none` if it started where it finished. |

## Sentinels

- `none` — knowably empty.
- `unknown` — **not knowable**. Write this rather than guessing. A run whose
  counters aren't all integers is dropped from the ratios **entirely** — both
  numerator and denominator — and reported as excluded. Leaving a counter out,
  or writing prose like `4 (approx)`, does the same thing and is reported
  separately. That is deliberate: excluding a term from a sum while keeping the
  denominator would be arithmetically identical to writing `0`, which would
  punish the honest answer and flatter the run.

A fabricated number is worse than a missing one. A run where the critics found
nothing and a defect escaped anyway is the most valuable row in the set — record
what happened, not what should have happened.
