---
name: plan-gates
description: >-
  The full plan → gate → commit procedure for full-gear work: new features,
  multi-file refactors, schema/API changes, anything security-sensitive or
  where the approach is genuinely uncertain. Use whenever a task warrants the
  "full" gear from the global gears table, or when the user says "plan this",
  "full workflow", or asks for the adversarial planning panel. Covers Phase 1
  (orient, draft, adversarial critics, plan file, approval stop) and Phase 2
  (implement on mid-tier agents, five gates — conformance, adversarial diff
  review, tests, runtime, simplify — fix loop, commit per item).
# No `effort:` pin here, deliberately — see the README's effort section. A skill
# effort field OVERRIDES the session level rather than flooring it, so pinning
# `high` would clamp a deliberate `/effort xhigh` run down for the whole
# procedure. That is the same argument this repo already rejected for a `medium`
# pin on the security gate.
---

# Skill: plan-gates

Two phases. Model names never appear here — use the tier table in the global
`CLAUDE.md` (frontier / mid / fast). The every-gear **hard rules** in the
global `CLAUDE.md` apply throughout and are authoritative; this skill adds the
full-gear procedure. Everywhere below, reviewers return **findings, not
reasoning transcripts**.

## Phase 1 — Plan (frontier)

1. **Orient before planning.** First, in the main session, recall relevant
   saved memories — subagents don't inherit them, so this one cannot be
   delegated. Then map the part of the codebase the task touches — key files,
   contracts, existing patterns — using the `Explore` subagent (pinned to the
   fast tier). Planning on a wrong mental model is the most expensive error
   there is: the whole pipeline, reviewers included, inherits it.
2. **Draft the plan** from your own analysis of the code and the request, on
   the frontier tier — do not downgrade mid-plan.
3. **Adversarial panel — at least 3 critics, in parallel** (single message,
   one `Agent` call each). Two are mandatory and predefined:
   - **`security-critic`** — always runs.
   - **`architecture-critic`** — always runs.

   Both return the schema defined in their own agent file, or "n/a — reason".
   Those files are the single source of truth for the fields; don't restate
   them here, or they go stale on the next schema change.

   Add **one or more task-fit critics** (correctness/edge-case auditor,
   simplicity critic, integration reviewer, performance, …) as
   `general-purpose` agents. Per Anthropic's delegation guidance, give each
   one a distinct objective, its **own output schema**, and clear task
   boundaries — otherwise critics duplicate work and leave gaps. That schema
   **must include `model`, `severity` and `confidence`**, so step 4's triage
   rule binds the whole panel and not just the two predefined critics. Spawn
   them **read-only** (deny `Write`, `Edit`, and the spawn tool): a review step
   must not be able to edit the code it is reviewing. Every critic gets the
   full plan **and** repo access: reviewers must read the real code, so they
   catch "the plan assumes X but the code does Y."
4. **Reconcile critiques into a final plan.** Where critics disagree, surface
   the disagreement and pick a side, briefly stating the deciding factor — do
   not paper over conflicts. Triaging low-value findings out is the session's
   job, not the critics' — but it is non-discretionary for the severe tail:
   any `critical`/`high` finding is actioned or recorded in **Agent critiques
   considered** with a written rejection reason, regardless of confidence.
   Quote the critic's own `severity`/`confidence` verbatim when you record it —
   you may **not** re-grade to duck the rule; if you disagree, keep the tag and
   record the disagreement. A finding from a built-in that emits no severity
   (`/code-review`, `/security-review`) counts as `high` until you grade it
   explicitly and record the grade. `medium`/`low` may be dropped without
   individual reasons, but **record how many** in the run-stats block
   (`findings_*_dropped`) — an unmeasured drop bucket makes the rejection-rate
   stat read as a whole-panel number when it only ever saw the severe tail.
5. **Write the plan file** to `docs/plans/YYYY-MM-DD-<slug>.md` (date from
   `currentDate`, not a guess), containing: **Goal**, **Approach**,
   **File-level changes** (a concrete checklist), **Risks & open questions**,
   **Agent critiques considered** — what each critic raised and how the plan
   addresses or consciously rejects it — and, appended at Gate 2,
   **Agent critiques considered — diff stage**: same format, separate corpus,
   sub-headed per plan-item and pass (`### <item> · pass N`) so the two stages
   and the fix-loop iterations stay countable apart. Finally **Run stats**,
   filled in at the end of Phase 2. Those sections, sized to the task — cover
   the substance, nothing beyond it, no filler or restatement. That is a
   brevity rule for prose, **not** for the per-finding rejection reasons step 4
   requires: never drop one of those to save space.
6. **Stop for approval.** No production code until the user says "looks
   good" / "ship it" / "go ahead" or similar.

## Phase 2 — Implement → Gate → Commit

Models switch automatically per phase: the main session stays frontier
(orchestrator/verifier); implementation and testing run on spawned agents.

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
   plans — plus a correctness pass via the built-in `/code-review` skill,
   naming the level explicitly and never invoking it bare (the README's
   harness-assumptions section carries the version-stamped reason). The
   built-in `/security-review` also fits security-sensitive diffs.
   Weight this gate
   at least as heavily as the plan review; it's where most real defects are
   caught. Triage per Phase 1 step 4, recording into **Agent critiques
   considered — diff stage**. Each critic's `model:` line is self-reported, not
   attestation: cross-check it against that agent's frontmatter pin, and if a
   review came back on a fallback model, re-run `/model` and re-run the critic
   before the gate can pass.
5. **Gate 3 · Dedicated test pass — always.** Hand off to the `test-runner`
   subagent (or the `/test` skill): run the full suite, cover every
   change-surface item, regression test per bug fixed, report the change's
   actual coverage. An untested or untestable path is a finding to resolve,
   not a step to skip.
6. **Gate 4 · Runtime verification.** A green suite is not a working feature.
   Exercise the affected flow end-to-end the way a user would and observe
   actual behavior. A project `verify` skill, where the repo has one, is the
   first choice; otherwise the built-in `/run` skill launches and drives the
   app.
7. **Gate 5 · Simplify — readability is part of done.** The code works; this
   gate is where it becomes code someone else can own. The bar: a competent
   junior developer should be able to read the change and say what it does
   without the plan file open. Run the built-in `/simplify` over the change —
   it applies reuse, simplification, efficiency and altitude cleanups and
   deliberately does not hunt for bugs — then read the result yourself against
   the same bar. Anything beyond a light cleanup goes to a mid-tier
   `implementer` with the specific cleanups named: this is implementation, so
   it runs on the implementation tier.

   What this gate looks for:
   - names that say what a thing *is*, not how it came to be;
   - no cleverness that needs a comment to be legible — while keeping the
     comments that record *why*, which are the opposite of clutter;
   - no speculative generality: an abstraction earns its place at the second
     caller, not the first;
   - control flow shaped like the problem the plan describes.

   Two hard limits. **Simplifying must not change behaviour** — a cleanup that
   alters what the code does stops being this gate's business and goes back to
   the plan. And it must not **weaken a test** to stay green; that is an
   every-gear hard rule, and this is the gate most likely to tempt it.
8. **Re-verify after simplifying — always.** A cleanup is a code change, so
   the evidence gathered before it no longer describes what is in the tree:
   re-run **Gate 3** (the dedicated test pass) and **Gate 4** (runtime
   verification) on the simplified code, and treat a regression here exactly
   like any other gate failure. Gates 1 and 2 re-open only if the cleanup moved
   code between files, changed a signature, or touched something a critic
   called out — a rename or a collapsed conditional doesn't need the panel
   again. Judge it, and record which you re-ran.
9. **Fix loop.** Any gate failure: re-plan the fix (frontier), re-implement
   (mid tier), re-run the affected gates. Repeat until clean.
10. **Commit per plan-item** as it clears all five gates — tick its checkbox in
   the same commit. Don't batch the whole plan into one commit; per-item
   commits bound derailment and make reverts cheap.
11. **Fill in `## Run stats`** after the last plan-item commit, as its own
   `chore(plan): record run stats` commit. The format and key list live in
   `scripts/run-stats.example.md` in the claude-workflow repo — read that file
   rather than reconstructing the keys from memory (the installer symlinks
   `skills/` and `agents/` but not `scripts/`, so open it from the clone).
   **Record what happened, not what should have happened.** A run where the
   critics found nothing and a defect escaped anyway is the most valuable row
   in the set — never round it toward looking good, and write `unknown` for
   anything you don't actually know rather than guessing. `unknown` drops the
   run from the ratios rather than counting as zero, so honesty costs nothing.
12. **Capture what you learned.** Write durable decisions and gotchas to
    memory; keep the plan file updated if scope legitimately changed so it
    stays a faithful record. Keep an entry to three things — the decision,
    the why, and the trap it avoids; the README covers the shape. What has
    proved worth keeping: architectural decisions and the
    alternatives rejected, non-obvious constraints discovered in the
    codebase, gotchas that cost real time, and conventions inferred from the
    code. What stays out of an entry: what was implemented (the plan file and
    git history already hold that), routine progress, or anything
    reconstructible from the diff.
