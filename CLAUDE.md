# Global working preferences

## Plan-then-implement workflow (non-trivial work only)

For any non-trivial task — new features, refactors touching multiple files, schema/API changes, anything where the approach is genuinely uncertain — follow this two-phase workflow:

### Model tiers (the only place model names live)

The workflow below refers to **tiers**, not model names, so it doesn't rot as the lineup changes — when it does, update this table and nothing else:

| Tier | Used for | Currently |
|---|---|---|
| **frontier** | planning, verification, orchestration — the main session | strongest available (Fable 5 / Opus) |
| **mid** | implementation, the dedicated test pass | Sonnet |
| **fast** | reading, search, discovery | Haiku |

### Phase 1: Plan (frontier tier)

1. Stay on the frontier tier for planning; do not downgrade mid-plan.
2. **Orient before planning.** Recall any relevant saved memories, then map the part of the codebase the task touches — key files, contracts, existing patterns — before drafting. Delegate this discovery to **fast-tier** `Explore`/read agents (cheap). Planning on a wrong mental model is the most expensive error there is: the whole pipeline, reviewers included, inherits it.
3. Draft an initial plan from your own analysis of the code and the request.
4. Spawn **adversarial agents in parallel** (single message, multiple `Agent` tool calls, `subagent_type: general-purpose` or a more specific type if one fits — e.g. a `security-auditor` or `code-reviewer` agent). Give every agent **the full plan _and_ access to the actual repo** — reviewers must read the real code, not just the plan text, so they catch "the plan assumes X but the code does Y." **Two critique angles are mandatory on every plan, always:**
   - **Security** — authn/authz, input validation, injection, secrets and data exposure, unsafe defaults, dependency/supply-chain risk, and anything that widens the attack surface. On a change with genuinely no security surface, the security agent should return "n/a — here's why" quickly rather than manufacture findings: mandatory to *look*, not to *find*.
   - **Architecture** — module boundaries, coupling, data flow, blast radius, scalability, fit with existing patterns, and long-term maintainability.

   Then spin up **one or more further agents** with angles that fit the task (correctness/edge-case auditor, simplicity/over-engineering critic, integration reviewer, performance, …) — **at least 3 agents total**. Each agent should:
   - Be told its role is to find flaws, missed edge cases, simpler alternatives, or hidden risks — not to rubber-stamp.
   - Be given a distinct critique angle so they don't all converge on the same objection.
5. Reconcile their critiques into a final plan. Where agents disagree, surface the disagreement and pick a side with reasoning — do not paper over conflicts.
6. Write the final plan to **`docs/plans/YYYY-MM-DD-<slug>.md`** in the active project. Use the date from the `currentDate` context, not a guess. The plan file should include:
   - **Goal** — what we're trying to achieve and why.
   - **Approach** — the chosen design at a level a reviewer can sanity-check.
   - **File-level changes** — concrete list of files to add/edit/delete.
   - **Risks & open questions** — what could go wrong, what's still unresolved.
   - **Agent critiques considered** — short summary of what each adversarial agent raised and how the plan addresses (or consciously rejects) each point.
7. Stop and wait for explicit approval before writing any production code. "Looks good", "ship it", "go ahead", or similar from the user is the green light.

### Phase 2: Implement → Verify → Fix (models switch automatically)

Once the plan is approved, I drive the whole implement→verify→fix loop and **switch models automatically per phase** — you don't run `/model`. I set the model on each agent I spawn and tell you which model ran the work. (The main orchestrator session stays on the frontier tier; the model changes happen on the spawned agents.)

1. **Drive implementation with `/goal`.** `/goal <condition>` is a built-in Claude Code command (v2.1.139+) that keeps Claude working autonomously across turns until a completion condition holds, re-checking after each turn (fast model). Use it to gate implementation on the approved plan, e.g.
   `/goal the plan in docs/plans/<file>.md is fully implemented: every file-level change made, nothing derails from the plan's approach, frontier verification passes, the security + architecture diff-review is clean, the dedicated test pass is green with the change fully covered, and the affected flow is verified working end-to-end at runtime`.
   Like `/model`, `/goal` is a command *you* type — I can't set it for you, so I'll hand you the exact `/goal …` line to paste (or you set it). On versions without `/goal`, skip it; the same loop below still runs, just without the auto-continue.
2. **Implement on the mid tier, fanned out.** Do the actual code changes on **mid-tier** agents (`Agent` tool, `model:` set from the tier table). If the plan touches more than one file — or has independent units of work — spawn **multiple mid-tier agents in parallel** (single message, one `Agent` call per file or cohesive unit) instead of serially. Each agent gets the plan-file path and its slice of the work.
3. **Implement strictly to the plan; watch for derailment.** If an agent's output deviates (extra scope, a different approach, files not listed in the plan), surface it — don't silently accept or improvise. Stop and flag it.
4. **Verify on the frontier tier.** After implementation, verify on the **frontier** model (the main session already is; for isolated checking spawn a frontier `Agent`). Walk the diff against the plan file item-by-item: every file-level change made? matches the approach? anything derailed? Report pass/fail per plan item. This is the conformance gate — `/goal`'s own per-turn check uses a fast model and only decides whether to keep going.
5. **Adversarially review the _diff_ — not just the plan.** Verification (step 4) only checks that the code matches the plan; bugs and security holes live in the code itself. Re-run the **security + architecture** lenses on the actual diff (the `/security-review` and `/code-review` skills are built for this), plus a correctness pass. A flawless plan can still ship an injection or a coupling you didn't foresee — this is where most real defects are caught, so weight it at least as heavily as the plan review.
6. **Test with a dedicated testing specialist — always.** Once verification and diff-review pass, hand off to a test-focused agent (`Agent` with `subagent_type: test-runner`, or a `/test` skill) whose *only* job is tests — nothing else. It must: run the full existing suite; **add or expand tests to cover every change** — new code paths, edge cases, error handling, and a regression test for any bug fixed; and report what the change's coverage actually is, not just pass/fail. Nothing is "done" until it is tested and green. Treat an untested or untestable path as a finding to resolve, not a step to skip.
7. **Verify at runtime — drive the real thing.** A green suite is not a working feature: tests can pass while the endpoint 404s, the CLI flag doesn't parse, or the page renders blank. Exercise the affected flow end-to-end the way a user would (run the app, hit the endpoint, click through the change) and observe actual behavior. A `/verify`-style skill fits here when the project has one.
8. **Fix loop — re-plan, then re-implement.** If verification, diff-review, testing, or the runtime check surfaces any issue (failing test, uncovered path, regression, vulnerability, broken flow, derailment), plan the fix (frontier), re-implement on the **mid tier** (step 2), then re-run the affected gates. Repeat until the diff matches the plan, review is clean, the suite is green, the change is fully covered, and the flow works — which is also when the `/goal` condition is satisfied.
9. **Commit per plan-item.** As each plan-item clears verify + diff-review + test + runtime check, commit it (tick its checkbox in the same commit) before moving to the next — don't batch the whole plan into one commit. Under `/goal`'s cross-turn autonomy this bounds derailment and makes any revert cheap.
10. **Capture what you learned.** When the task is done, write durable decisions, gotchas, and non-obvious context to memory, and keep the plan file updated if scope legitimately changed so it stays a faithful record. That's how the next task starts smarter instead of re-deriving the same context.

### Automatic model routing (applies to every task)

I switch models automatically and tell you each time — you never need to run `/model` yourself:
- **Reading / researching files → fast tier.** Delegate file reads and "where is X / what does Y do" searches to fast-tier agents (`Agent` or `Explore` with the fast-tier model) to save tokens and keep the main context clean. Read directly in the main session only when I need exact text to edit right now.
- **Planning, verifying, orchestrating → frontier.** The main session stays on the frontier tier.
- **Implementing → mid tier**, per Phase 2.
- **Testing → a dedicated test specialist** (`test-runner` agent or `/test` skill), typically mid-tier — kept separate from implementation so tests get their own focused pass, per Phase 2 step 6.

Mechanics/limitation: I can only set the model on agents I spawn — there is no tool to switch the main session's own model. So "automatic switching" means the main session stays on the frontier tier (planner/verifier/orchestrator) while each cheaper phase runs in a fast- or mid-tier agent I spawn, and I announce which model ran each piece.

### Right-sizing: match the ritual to the risk

Rigor should scale with risk and blast radius, not run at full tilt for everything — a workflow too heavy for the task gets silently bypassed, which is worse than a lighter one that actually gets used. Pick a gear:

- **Skip (just do it).** One-line fixes, typos, formatting, obvious single-file edits (rename a variable, fix a clear bug, add a missing import), pure questions ("how does X work?"), or when the user has already given a specific approach. No plan file, no agents.
- **Light.** A single, self-contained change with real but bounded risk (a few files, one cohesive unit). Draft the plan inline (no `docs/plans` file), run **one** reviewer on whichever angle the change actually touches (security *or* architecture), implement, then verify + test + a quick runtime check of the affected flow. Skip the full agent panel.
- **Full.** New features, multi-file refactors, schema/API changes, anything security-sensitive, or where the approach is genuinely uncertain — the complete Phase 1 + Phase 2 above.

When unsure which gear, err one gear heavier — the user can always say "just do it" to drop down.

## Local, private overrides (optional)

Machine- or client-specific preferences that shouldn't live in a public repo go in `~/.claude/CLAUDE.local.md`. The line below imports that file into global memory **if it exists**, and is a silent no-op if it doesn't — so cloning this repo needs nothing extra. Keep anything private (employer conventions, internal tool/agent names, per-machine paths) there, not here.

@~/.claude/CLAUDE.local.md
