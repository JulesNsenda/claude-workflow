# Global working preferences

## Plan-then-implement workflow (non-trivial work only)

For any non-trivial task — new features, refactors touching multiple files, schema/API changes, anything where the approach is genuinely uncertain — follow this two-phase workflow:

### Phase 1: Plan (uses the strongest model)

1. Stay on Opus for planning. If the session is already on Opus, use it directly; do not downgrade mid-plan. If better than Opus exists, use it (eg: claude-fable-5)
2. Draft an initial plan from your own analysis of the code and the request.
3. Spawn **at least 3 adversarial agents in parallel** (single message, multiple `Agent` tool calls, `subagent_type: general-purpose` or a more specific type if one fits — e.g. a dedicated `code-reviewer` agent). Each agent should:
   - Receive the full plan and the relevant context.
   - Be told its role is to find flaws, missed edge cases, simpler alternatives, or hidden risks — not to rubber-stamp.
   - Be given a distinct critique angle so they don't all converge on the same objection. Examples: (a) correctness/edge-case auditor, (b) simplicity/over-engineering critic, (c) integration/blast-radius reviewer. Pick angles that fit the task.
4. Reconcile their critiques into a final plan. Where agents disagree, surface the disagreement and pick a side with reasoning — do not paper over conflicts.
5. Write the final plan to **`docs/plans/YYYY-MM-DD-<slug>.md`** in the active project. Use the date from the `currentDate` context, not a guess. The plan file should include:
   - **Goal** — what we're trying to achieve and why.
   - **Approach** — the chosen design at a level a reviewer can sanity-check.
   - **File-level changes** — concrete list of files to add/edit/delete.
   - **Risks & open questions** — what could go wrong, what's still unresolved.
   - **Agent critiques considered** — short summary of what each adversarial agent raised and how the plan addresses (or consciously rejects) each point.
6. Stop and wait for explicit approval before writing any production code. "Looks good", "ship it", "go ahead", or similar from the user is the green light.

### Phase 2: Implement → Verify → Fix (models switch automatically)

Once the plan is approved, I drive the whole implement→verify→fix loop and **switch models automatically per phase** — you don't run `/model`. I set the model on each agent I spawn and tell you which model ran the work. (The main orchestrator session stays on Opus; the model changes happen on the spawned agents.)

1. **Drive implementation with `/goal`.** `/goal <condition>` is a built-in Claude Code command (v2.1.139+) that keeps Claude working autonomously across turns until a completion condition holds, re-checking after each turn (fast model). Use it to gate implementation on the approved plan, e.g.
   `/goal the plan in docs/plans/<file>.md is fully implemented: every file-level change made, nothing derails from the plan's approach, and Opus verification passes`.
   Like `/model`, `/goal` is a command *you* type — I can't set it for you, so I'll hand you the exact `/goal …` line to paste (or you set it). On versions without `/goal`, skip it; the same loop below still runs, just without the auto-continue.
2. **Implement with Sonnet, fanned out.** Do the actual code changes on **Sonnet** agents (`Agent` tool, `model: sonnet`). If the plan touches more than one file — or has independent units of work — spawn **multiple Sonnet agents in parallel** (single message, one `Agent` call per file or cohesive unit) instead of serially. Each agent gets the plan-file path and its slice of the work.
3. **Implement strictly to the plan; watch for derailment.** If an agent's output deviates (extra scope, a different approach, files not listed in the plan), surface it — don't silently accept or improvise. Stop and flag it.
4. **Verify with the highest Opus.** After implementation, verify on the strongest **Opus** (main session is already Opus; for isolated checking spawn an `Agent` with `model: opus`). Walk the diff against the plan file item-by-item: every file-level change made? matches the approach? anything derailed? Report pass/fail per plan item. This is the substantive gate — `/goal`'s own per-turn check uses a fast model and only decides whether to keep going.
5. **Fix loop — re-plan, then Sonnet again.** If verification finds any issue, plan the fix (Opus), then re-implement on **Sonnet** (step 2). Repeat verify→fix until clean — which is also when the `/goal` condition is satisfied.
6. Keep the plan file updated if scope legitimately changes, so it stays a faithful record.

### Automatic model routing (applies to every task)

I switch models automatically and tell you each time — you never need to run `/model` yourself:
- **Reading / researching files → Haiku.** Delegate file reads and "where is X / what does Y do" searches to agents on **Haiku** (`Agent` with `model: haiku`, or the `Explore` agent with `model: haiku`) to save tokens and keep the main context clean. Read directly in the main session only when I need exact text to edit right now.
- **Planning, verifying, orchestrating → Opus.** The main session stays on Opus.
- **Implementing → Sonnet**, per Phase 2.

Mechanics/limitation: I can only set the model on agents I spawn — there is no tool to switch the main session's own model. So "automatic switching" means the main session stays Opus (planner/verifier/orchestrator) while each cheaper phase runs in a Haiku or Sonnet agent I spawn, and I announce which model ran each piece.

### When to skip this workflow

Skip the plan-then-implement ritual for:
- One-line fixes, typo corrections, formatting tweaks.
- Single-file edits with an obvious shape (rename a variable, fix a clear bug, add a missing import).
- Pure questions ("how does X work?", "where is Y defined?").
- Tasks the user has already given a specific approach for.

When in doubt about whether a task is "non-trivial", err on the side of planning — the user can always say "just do it" to skip.

## Local, private overrides (optional)

Machine- or client-specific preferences that shouldn't live in a public repo go in `~/.claude/CLAUDE.local.md`. The line below imports that file into global memory **if it exists**, and is a silent no-op if it doesn't — so cloning this repo needs nothing extra. Keep anything private (employer conventions, internal tool/agent names, per-machine paths) there, not here.

@~/.claude/CLAUDE.local.md
