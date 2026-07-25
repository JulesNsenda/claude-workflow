# Run stats — canonical format

This file is the single source of truth for the `## Run stats` block that every
full-gear plan file ends with. Three things read this format, and none of them
enforces it on the others:

- `skills/plan-gates/SKILL.md` tells the orchestrator to write the block,
- `scripts/run-stats.sh` parses it,
- this file is what the CI smoke test feeds the parser.

So change the keys **here first**, then in the other two.

## The block

A fenced block, headed `## Run stats`, containing **flat `key: value` lines
only** — no nesting, no lists, no quoting, no anchors. The fence says `yaml`
because flat scalars are valid YAML, but the parser is not a YAML parser: a
nested map's child lines would be read as top-level keys.

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
| `gear` | `full` or `light`. |
| `effort_plan`, `effort_diff` | Effort the critics ran at in each pass. |
| `findings_*_actioned` | Findings that changed the work. |
| `findings_*_rejected` | Findings consciously rejected **with a written reason**. Not a failure — this is the critic-noise signal. |
| `findings_*_dropped` | `medium`/`low` findings dropped without individual reasons. Counted so the rejection rate can't read as a whole-panel number when it only saw the severe tail. |
| `escaped` | Defects **both critic passes missed**, caught at Gate 3, Gate 4, or by you afterwards. The most important number here. |
| `agents_spawned` | Total across both phases, including fix-loop re-runs. |
| `gates_failed_first_pass` | How many of gates 1–4 needed a fix loop. `none` if all passed first time. |
| `escalated_from` | The gear the task *started* at if it moved up (`skip`, `light`); `none` if it started where it finished. |

## Sentinels

- `none` — knowably empty.
- `unknown` — **not knowable**. Write this rather than guessing; `run-stats.sh`
  excludes `unknown` from its ratios instead of counting it as zero.

A fabricated number is worse than a missing one. A run where the critics found
nothing and a defect escaped anyway is the most valuable row in the set — record
what happened, not what should have happened.
