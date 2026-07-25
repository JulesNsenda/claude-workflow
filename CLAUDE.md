# Global working preferences

Always-on rules only — deliberately small, because long memory files reduce
adherence. The full plan → gate → commit procedure lives in the **`plan-gates`
skill** (loaded on demand); the reviewers and specialists are **subagents** in
`~/.claude/agents/` (`security-critic`, `architecture-critic`, `implementer`,
`test-runner`, and a fast-pinned `Explore` override).

## Model tiers (canonical table)

Everything else refers to **tiers**, so the workflow doesn't rot as the lineup
changes — when it does, update this table plus the matching `model:` / `effort:`
pins in `~/.claude/agents/*.md` (family aliases, not dated IDs — they only need
touching when a tier moves to a different model family):

| Tier | Used for | Currently | Effort |
|---|---|---|---|
| **frontier** | planning, verification, orchestration — the main session | strongest available (Fable 5 / Opus) | high |
| **mid** | implementation, the dedicated test pass | Sonnet | inherit |
| **fast** | reading, search, discovery | Haiku | low\* |

(**Effort** = the `effort:` level pinned per tier — `high` *is* the default, so
it's a pin, not a ranking; `xhigh` is held for the riskiest reviews. `*`Haiku
takes no effort level, so `fast` isn't pinned — `low` is the intent if it moves to
a model that does. Rationale in the README.)

## Right-sizing: three gears

Rigor scales with risk and blast radius — a workflow too heavy for the task
gets silently bypassed, which is worse than a lighter one that gets used:

- **Skip (just do it).** One-line fixes, typos, obvious single-file edits,
  pure questions, or when the user has already given a specific approach. No
  plan file, no agents.
- **Light.** A single self-contained change with real but bounded risk. Inline
  plan, **one** reviewer (`security-critic` *or* `architecture-critic` —
  whichever angle the change touches), then verify + test + a quick runtime
  check.
- **Full.** New features, multi-file refactors, schema/API changes, anything
  security-sensitive or approach-uncertain → **invoke the `plan-gates`
  skill** and follow it end to end.

When unsure, err one gear heavier — the user can say "just do it" to drop
down. Cost context: multi-agent runs ≈ 15× the tokens of a chat exchange
(Anthropic's internal figure — directional), which is exactly why the lighter
gears exist.

## Hard rules (every gear)

- **Full-gear approval stop:** after the plan file, wait for explicit approval
  ("looks good" / "ship it" / "go ahead") before any production code.
- Nothing is "done" until it is tested, the change is covered, and the flow is
  **observed** working at runtime — never weaken or skip a test to force
  green.
- Reviewers and critics output **findings, not reasoning transcripts**.
- While a subagent is working, wait silently — no status commentary until its
  report arrives.
- If implementation deviates from the plan, surface it — don't improvise.
- Commit per plan-item, not one batch commit per plan.
- When a task ends, write durable decisions and gotchas to memory.

## Model routing (automatic — the user never runs /model)

- **Reading / discovery → `Explore` subagent** (pinned to the fast tier via
  `~/.claude/agents/explore.md`). Read directly in the main session only for
  exact text you're about to edit.
- **Planning, verifying, orchestrating → frontier** (the main session).
- **Implementing → mid-tier `implementer` agents**, fanned out per cohesive unit.
- **Testing → `test-runner` subagent or the `/test` skill** (mid tier).

Mechanics: models can only be set on spawned agents — the main session stays on
the frontier tier, and every spawned agent opens its report with a `model:`
line (`Explore` excepted: it never receives this file).

## Local, private overrides (optional)

Machine- or client-specific preferences that shouldn't live in a public repo
go in `~/.claude/CLAUDE.local.md`. The line below imports that file **if it
exists** and is a silent no-op if it doesn't — so cloning this repo needs
nothing extra. Keep anything private (employer conventions, internal
tool/agent names, per-machine paths) there, not here.

@~/.claude/CLAUDE.local.md
