# Run stats — canonical format

This file is the single source of truth for the `## Run stats` block that every
full-gear plan file ends with (light-gear runs write a shorter one, see below).
Four things read this format, and none of them enforces it on the others:

- `skills/plan-gates/SKILL.md` tells the orchestrator to write the full block,
- the root `CLAUDE.md` tells it to write the light one,
- `scripts/run-stats.sh` parses it,
- this file is what the CI smoke test feeds the parser.

So change the keys **here first**, then in `run-stats.sh` and `plan-gates`; the
root `CLAUDE.md` only points here.

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
gates_failed: 2,4
escalated_from: none
```

## The keys

| Key | Meaning | Filled at |
|---|---|---|
| `date`, `slug` | Match the plan filename. | plan written |
| `gear` | `full` or `light`. Anything else is listed by file:line and the run is left out of the ratios. | plan written (full) / close (light) |
| `effort_plan` | Effort the critics ran at in the plan pass. Re-count if the plan is revised and re-reviewed before approval. | plan written |
| `effort_diff` | Effort the critics ran at in the diff pass. `mixed` if a later pass ran at a different effort. | each Gate 2 triage |
| `findings_plan_actioned` | Findings that changed the work. Re-count the `findings_plan_*` keys if the plan is revised and re-reviewed before approval. | plan written |
| `findings_diff_actioned` | Findings that changed the work. Running totals across passes, counting each distinct finding once: one raised again in a later pass is not re-added. | each Gate 2 triage |
| `findings_plan_rejected` | Findings consciously rejected **with a written reason**. Not a failure — this is the critic-noise signal. | plan written |
| `findings_diff_rejected` | As `findings_plan_rejected`, for the diff pass. Running totals, as for `findings_diff_actioned`. | each Gate 2 triage |
| `findings_plan_dropped` | `medium`/`low` findings dropped without individual reasons. Counted so the rejection rate can't read as a whole-panel number when it only saw the severe tail. | plan written |
| `findings_diff_dropped` | As `findings_plan_dropped`, for the diff pass. Running totals, as for `findings_diff_actioned`. | each Gate 2 triage |
| `escaped` | Defects **both critic passes missed**, caught at Gate 3, Gate 4, or by you afterwards. The most important number here. In a light run: defects the one reviewer missed, caught by the test or the runtime check before the run was done. | close |
| `agents_spawned` | Total across both phases, including fix-loop re-runs. Seeded with the Phase 1 count, then a running total; at close, add agents spent on work that never reached a commit. | plan written, then each plan-item commit, and at close |
| `gates_failed` | Which of gates 1–5 needed a fix loop: `none`, `pending`, `unknown`, or a list such as `2,4`. It is a list of gate numbers, not a count — `2` means gate 2 looped. Spaces around commas are ignored, brackets are dropped, order is normalised and duplicates collapsed, so `[4, 2]` reads as `2,4`. Each gate is listed once however many loops it took. Gate 5's re-verification counts as Gate 5, not as a second failure of gates 3–4. It is a dimension, not a ratio counter: apart from `pending`, it never excludes a run from the ratios. A value that is none of those is reported on its own line. Seeded `none`; on the first fix loop *replace* `none` with that gate, on later loops append (`none,2` is not a valid value). | each fix loop |
| `gates_failed_first_pass` | **Legacy only.** The older count of gates that needed a fix loop. Old blocks keep parsing and show as `n=2` in the GATES column; new blocks don't write it. | never — omit |
| `escalated_from` | The gear the task *started* at if it moved up (`skip`, `light`); `none` if it started where it finished. | plan written |

**Light gear.** A light run writes one short block when it closes, appended to
`docs/plans/light-runs.md` under its own heading (`## Run stats — <date> <slug>`),
only if `git check-ignore -q docs/plans/light-runs.md` exits 0 (ignored). On
anything else (1, or 128 outside a repo) ask the user once per project and
remember the answer in project memory. Add a
prose line `Commit: <subject>` under the block, so a later bug can be traced to
it. These eight lines are the whole record; the plan-stage keys are not written.
`findings_diff_*` count the one reviewer's findings, at whatever stage it ran.
The parser counts a light run as complete when its diff counters and `escaped`
are integers, and reports the light runs on a line of their own, apart from the
full-gear ratios. This fence sits outside the stats section, so the parser never
reads it as a run; CI extracts it from here (keep it the first `yaml` fence after this
paragraph).

```yaml
date: 2026-10-09
slug: example-light
gear: light
findings_diff_actioned: 1
findings_diff_rejected: 0
findings_diff_dropped: 0
escaped: 1
escalated_from: none
```

**Seeding (full gear).** Write the block when the plan is written, with every key present
except the legacy one: keys whose *Filled at* starts with "plan written" get
their values, `gates_failed` starts at `none`, and every other key is `pending`.
Derive the seed from this table, not by copying the illustrative block above —
that one is a closed example CI parses.

`escaped` stays `pending` until close, so an abandoned run can never enter the
ratios with a structural zero. When Gate 3 or Gate 4 catches a defect both
critic passes missed, note it in the plan (diff-stage critiques); at close,
`escaped` is the count of those notes.

## Sentinels

- `none` — knowably empty.
- `pending` — **not reached yet**. Any key holding it keeps the run out of the
  ratios (both numerator and denominator) and lists it as still pending,
  unfinished or abandoned. Closing a run resolves every `pending` to a real
  value or `unknown`.
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
