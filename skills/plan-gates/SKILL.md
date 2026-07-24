---
name: plan-gates
description: >-
  The full plan → gate → commit procedure for full-gear work: new features,
  multi-file refactors, schema/API changes, anything security-sensitive or
  where the approach is genuinely uncertain. Use whenever a task warrants the
  "full" gear from the global gears table, or when the user says "plan this",
  "full workflow", or asks for the adversarial planning panel. Covers Phase 1
  (orient, draft, adversarial critics, plan file, approval stop) and Phase 2
  (implement on mid-tier agents, four gates, fix loop, commit per item).
---

# Skill: plan-gates

Two phases. Model names never appear here — use the tier table in the global
`CLAUDE.md` (frontier / mid / fast). The every-gear **hard rules** in the
global `CLAUDE.md` apply throughout and are authoritative; this skill adds the
full-gear procedure. Everywhere below, reviewers return **findings, not
reasoning transcripts**.

## Phase 1 — Plan (frontier)

1. **Orient before planning.** Recall relevant saved memories, then map the
   part of the codebase the task touches — key files, contracts, existing
   patterns — using the `Explore` subagent (pinned to the fast tier). Planning
   on a wrong mental model is the most expensive error there is: the whole
   pipeline, reviewers included, inherits it.
2. **Draft the plan** from your own analysis of the code and the request, on
   the frontier tier — do not downgrade mid-plan.
3. **Adversarial panel — at least 3 critics, in parallel** (single message,
   one `Agent` call each). Two are mandatory and predefined:
   - **`security-critic`** — always runs; returns severity/where/risk/fix
     findings, or "n/a — reason" when there's genuinely no security surface.
   - **`architecture-critic`** — always runs; returns concern/where/blast
     radius/alternative findings.

   Add **one or more task-fit critics** (correctness/edge-case auditor,
   simplicity critic, integration reviewer, performance, …) as
   `general-purpose` agents. Per Anthropic's delegation guidance, give each
   one a distinct objective, its **own output schema**, and clear task
   boundaries — otherwise critics duplicate work and leave gaps. Every critic
   gets the full plan **and** repo access: reviewers must read the real code,
   so they catch "the plan assumes X but the code does Y."
4. **Reconcile critiques into a final plan.** Where critics disagree, surface
   the disagreement and pick a side, briefly stating the deciding factor — do
   not paper over conflicts.
5. **Write the plan file** to `docs/plans/YYYY-MM-DD-<slug>.md` (date from
   `currentDate`, not a guess), containing: **Goal**, **Approach**,
   **File-level changes** (a concrete checklist), **Risks & open questions**,
   and **Agent critiques considered** — what each critic raised and how the
   plan addresses or consciously rejects it.
6. **Stop for approval.** No production code until the user says "looks
   good" / "ship it" / "go ahead" or similar.

## Phase 2 — Implement → Gate → Commit

Models switch automatically per phase: the main session stays frontier
(orchestrator/verifier); implementation and testing run on spawned agents, and
each report says which model ran the work.

1. **Optionally drive with `/goal`** (built-in, v2.1.139+; the user types it —
   hand them the line to paste). Its evaluator is a fast model that doesn't
   run commands itself, so **never use one giant condition**. Use narrow,
   sequential goals with the proof baked in, advancing as each is met, e.g.:
   - `/goal every file-level change in docs/plans/<file>.md is implemented and git diff confirms it`
   - `/goal the security-critic and architecture-critic reviews of the diff report no unresolved findings`
   - `/goal the test suite passes (<test command>) and every change-surface item is covered`
   - `/goal the affected flow works end-to-end at runtime, observed — not inferred`
   Without `/goal`, the same loop runs, just without auto-continue.
2. **Implement on mid-tier `implementer` agents, fanned out.** One `implementer`
   `Agent` call per file or cohesive unit, in parallel where independent. Each
   gets the plan-file path and its slice. Strictly to the plan: if output deviates
   (extra scope, different approach, unlisted files), surface it — don't silently
   accept.
3. **Gate 1 · Conformance (frontier — the main session).** Walk the diff
   against the plan file item by item: every change made? matches the
   approach? anything derailed? Pass/fail per item.
4. **Gate 2 · Adversarial diff review.** Re-run **`security-critic`** and
   **`architecture-critic`** on the actual diff — bugs live in code, not
   plans — plus a correctness pass via the built-in `/code-review` skill
   (the built-in `/security-review` also fits security-sensitive diffs).
   Weight this gate
   at least as heavily as the plan review; it's where most real defects are
   caught.
5. **Gate 3 · Dedicated test pass — always.** Hand off to the `test-runner`
   subagent (or the `/test` skill): run the full suite, cover every
   change-surface item, regression test per bug fixed, report the change's
   actual coverage. An untested or untestable path is a finding to resolve,
   not a step to skip.
6. **Gate 4 · Runtime verification.** A green suite is not a working feature.
   Exercise the affected flow end-to-end the way a user would (the built-in
   `/verify` skill fits here) and observe actual behavior.
7. **Fix loop.** Any gate failure: re-plan the fix (frontier), re-implement
   (mid tier), re-run the affected gates. Repeat until clean.
8. **Commit per plan-item** as it clears all four gates — tick its checkbox in
   the same commit. Don't batch the whole plan into one commit; per-item
   commits bound derailment and make reverts cheap.
9. **Capture what you learned.** Write durable decisions and gotchas to
   memory; keep the plan file updated if scope legitimately changed so it
   stays a faithful record.
