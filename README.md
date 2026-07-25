# claude-workflow

[![CI](https://github.com/JulesNsenda/claude-workflow/actions/workflows/ci.yml/badge.svg)](https://github.com/JulesNsenda/claude-workflow/actions/workflows/ci.yml)

My global [Claude Code](https://claude.com/claude-code) configuration — a small,
curated set of working preferences and skills that I symlink into `~/.claude`.

It's public because the core of it is a **plan-then-implement workflow** and a
**model-routing convention** that I think are good defaults for agentic coding.
Copy what's useful.

## What's in here

| File | What it is |
|---|---|
| [`CLAUDE.md`](./CLAUDE.md) | Always-on rules Claude Code loads every session: the model-tier table, the three gears, and the hard rules. Deliberately small — the procedure lives in the skill below. |
| [`skills/`](./skills/) | On-demand [skills](https://docs.claude.com/en/docs/claude-code/skills). [`plan-gates`](./skills/plan-gates/SKILL.md) is the full plan → gate → commit procedure; [`test`](./skills/test/SKILL.md) enforces the "test everything" pass; [`example-skill`](./skills/example-skill/SKILL.md) is a documented template. |
| [`agents/`](./agents/) | [Subagents](https://docs.claude.com/en/docs/claude-code/sub-agents): the adversarial [`security-critic`](./agents/security-critic.md) and [`architecture-critic`](./agents/architecture-critic.md) (read-oriented tools, findings-only output), an [`implementer`](./agents/implementer.md) that builds strictly from the approved plan (no web/research tools), a [`test-runner`](./agents/test-runner.md) specialist, and an [`Explore`](./agents/explore.md) override pinned to the fast tier (if your Claude Code version doesn't let a user agent shadow the built-in name, set `CLAUDE_CODE_SUBAGENT_MODEL` instead). |
| [`settings.json`](./settings.json) | Mostly permission hygiene: blocks the **Read tool** from secret paths (`.env*`, `secrets/`, `*.pem`/`*.key`, `~/.ssh`, `~/.aws`), denies the common force-push forms, asks before **every** push, allow-lists routine git commands. Plus one advisory behavioural default — `workflowSizeGuideline: small` (needs ≥ 2.1.219; documented in the Claude Code CHANGELOG rather than the settings reference), which asks Claude to aim under 5 agents in any *dynamic workflow* it writes. That is a different mechanism from this repo's own subagents, which it does not touch — and it is advice, not a cap. If you merge this file by hand, merge the `permissions` block first and independently: it is the part that is load-bearing. |
| [`.claude-plugin/`](./.claude-plugin/plugin.json) | Plugin manifest, so the skills + agents can also be installed as a namespaced [plugin](https://docs.claude.com/en/docs/claude-code/plugins). |
| [`install.sh`](./install.sh) / [`install.ps1`](./install.ps1) | Symlink the above into `~/.claude`. Idempotent; backs up anything it would overwrite. |

## The workflow, in one screen

**Orient → Plan → Implement → Review the diff → Test → Verify at runtime →
Commit per item**, with the model tier matched to each phase and the rigor
matched to the risk.

- **Orient first.** Recall project memory and map the affected subsystem with
  cheap fast-tier agents before planning — a wrong mental model poisons
  everything downstream.
- **Adversarial planning.** Draft on the strongest model, then ≥3 parallel
  critics who read the *actual repo*, not just the plan text. **Security and
  architecture are mandatory angles on every plan**; further angles fit the
  task. Reconcile the critiques into a plan file, then **stop for approval**
  before any production code.
- **Implement on mid-tier agents, fanned out** — one per cohesive unit, strictly
  to the plan; deviations get surfaced, not improvised.
- **Gate hard after coding:** plan-conformance check, security + architecture
  review of the *diff* (bugs live in code, not plans), a dedicated test pass
  that must cover every change, and an end-to-end runtime check. Nothing is
  done until it's green, covered, and observed working.
- **Commit per plan-item**, and capture durable lessons to memory at the end.
- **Three gears — skip / light / full** — so rigor scales with risk instead of
  being bypassed.

### As a diagram

Tinted nodes mark the steps where the workflow pins a model tier — **violet =
frontier**, **blue = mid**, **green = fast**; untinted steps inherit from
context.

```mermaid
flowchart TD
    Task([Task arrives]) --> Gear{"Pick a gear —<br/>risk × blast radius"}
    Gear -->|"trivial / obvious"| Skip["Skip — just do it"]
    Gear -->|"bounded,<br/>self-contained"| Light["Light — inline plan, one reviewer,<br/>verify + test + runtime check"]
    Gear -->|"feature / refactor /<br/>security-sensitive"| Orient

    subgraph P1["Phase 1 — Plan"]
        Orient["Orient — recall memories,<br/>map the subsystem"]:::fast --> Draft["Draft the plan"]:::frontier
        Draft --> Panel["Adversarial panel — at least 3 agents<br/>reading the real repo"]
        Panel --> Sec["Security<br/>(mandatory)"]
        Panel --> Arch["Architecture<br/>(mandatory)"]
        Panel --> Fit["Task-fit angles<br/>(correctness, simplicity, …)"]
        Sec --> Reconcile["Reconcile critiques →<br/>docs/plans/YYYY-MM-DD-slug.md"]:::frontier
        Arch --> Reconcile
        Fit --> Reconcile
    end

    Reconcile --> Approve{"User approval<br/>(hard stop)"}
    Approve -->|"changes"| Draft
    Approve -->|"approved"| Impl

    subgraph P2["Phase 2 — Implement → Gate → Commit"]
        Impl["Implement — agents fanned out,<br/>one per cohesive unit"]:::mid --> G1
        G1["Gate 1 · conformance —<br/>diff vs plan, item by item"]:::frontier --> G2
        G2["Gate 2 · adversarial diff review —<br/>security + architecture + correctness"] --> G3
        G3["Gate 3 · dedicated test pass —<br/>suite green, change fully covered"]:::mid --> G4
        G4["Gate 4 · runtime verify —<br/>drive the real flow end-to-end"]
        Fix["Fix loop —<br/>re-plan, re-implement"]:::frontier
        G1 -. "fail" .-> Fix
        G2 -. "fail" .-> Fix
        G3 -. "fail" .-> Fix
        G4 -. "fail" .-> Fix
        Fix --> Impl
        G4 -->|"all green"| Commit["Commit this plan-item"]
        Commit -->|"more items"| Impl
    end

    Commit -->|"plan complete"| Capture["Capture learnings → memory"]
    Skip --> Done([Done])
    Light --> Done
    Capture --> Done

    classDef frontier fill:#e6e0f8,stroke:#7c6bd6,color:#2a2340
    classDef mid fill:#dbe9f9,stroke:#4a90d9,color:#1c3350
    classDef fast fill:#def0e5,stroke:#4caf7d,color:#1d3a2a
```

The authoritative version is split across the documented primitives:
[`CLAUDE.md`](./CLAUDE.md) holds the always-on rules (tier table, gears, hard
rules), the [`plan-gates`](./skills/plan-gates/SKILL.md) skill holds the exact
phases and gates, and the critics live in [`agents/`](./agents/). This summary
is deliberately loose so it drifts as little as possible.

## Assumptions, and the knobs behind them

**Effort is the second axis of the tier table.** Alongside the model tier, each
agent pins an [`effort`](https://platform.claude.com/docs/en/build-with-claude/effort)
level in its frontmatter: frontier agents run `high` and mid-tier agents inherit
the session default. (The fast/discovery tier's intended level is `low`, but its
current model, Haiku, doesn't take an effort level — so that tier isn't pinned
today; the intent applies if it moves to an effort-capable model.) `high` *is* the
API default, so
pinning the two critics to `high` doesn't make them think harder than a normal
session — it **holds** them at high independent of the session's effort, so a
cheap, low-effort session can't quietly downgrade a security or architecture
review. `xhigh` is reserved for the riskiest full-gear reviews. (This is Claude
Code's subagent `effort:` field — distinct from Claude Managed Agents'
`model.effort`.)

### Nesting: the agents this repo defines can't spawn

**No agent defined here is granted a spawn tool.** Every `tools:` list in
[`agents/`](./agents/) is an allowlist, and none of them includes `Agent` — so
whatever the platform default is, these agents can't nest through the harness.
(`Bash` remains a general escape hatch; a depth cap is not a sandbox, and the
`permissions.deny` rules below constrain the **Read tool**, not shell reads.)
The uncontrolled edges are the built-ins this repo doesn't define: the
`general-purpose` task-fit critics the plan-gates panel spawns, and
`/code-review` at Gate 2. Omitting `Agent` from `tools:` only works for agents
you define; for the built-ins the levers are `disallowedTools` and the guard
below.

The **platform default is contested**, so don't rely on it either way. The
v2.1.219 CHANGELOG says subagents now nest to depth 3 by default (was 1) and
that `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` disables nesting; the sub-agents
reference still says a subagent can't spawn subagents by default, with its
version note covering only v2.1.172–v2.1.216. Set the variable explicitly if
you depend on the depth:

```jsonc
{
  "permissions": { /* … keep yours … */ },
  "env": { "CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "1" }
}
```

`"1"` means one layer below the main conversation — subagents that cannot
delegate further; verify that reading against your installed version. **Merge
this into your settings, don't paste over them** — the `permissions` block has
to survive. And check `ls -l ~/.claude/settings.json` first: on a fresh install
it is a *symlink into this repo*, so editing it in place would put your personal
environment into a tracked, public file. Replace it with a real copy (`cp -L`)
before adding anything machine-specific.

### Harness assumptions — Claude Code ≥ 2.1.218

Version-specific, so stamped — everything in this subsection rots on a
platform schedule:

- **Assumes ≥ 2.1.218**, where `/code-review` — this workflow's Gate 2 — runs as a
  *background subagent*, so reviewing the diff no longer eats the orchestrator's
  context.
- Concurrent subagents are capped (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`,
  default 20), and `--max-budget-usd` halts background subagents once the
  budget is hit — worth setting for unattended runs.

## Install

```bash
git clone https://github.com/JulesNsenda/claude-workflow.git
cd claude-workflow
```

**macOS / Linux:**

```bash
./install.sh            # or: ./install.sh --dry-run  to preview
```

**Windows (PowerShell):**

```powershell
.\install.ps1           # or: .\install.ps1 -DryRun  to preview
```

Then restart Claude Code.

### What the installer does

It creates symlinks so `~/.claude` points back at this repo — edit a file here and
the change is live everywhere immediately, and `git pull` updates your config:

```
~/.claude/CLAUDE.md          ->  <repo>/CLAUDE.md
~/.claude/settings.json      ->  <repo>/settings.json    (unless a real settings.json exists)
~/.claude/agents/<name>.md   ->  <repo>/agents/<name>.md (one link per agent file)
~/.claude/skills/<name>      ->  <repo>/skills/<name>    (one link per skill folder)
```

It is **safe to re-run**. Any existing *real* file at a target is moved to
`<target>.backup.<timestamp>` before the symlink is created; existing symlinks are
replaced in place. **Exception: `settings.json` is never displaced** — an
existing real settings file holds your accumulated permission decisions and
hook wiring, so the installer skips it and tells you to merge the repo's
[`settings.json`](./settings.json) manually — and until you merge it, **none of
the repo's permission rules are active** for you.

### Uninstall

```bash
./install.sh --uninstall      # macOS / Linux
```
```powershell
.\install.ps1 -Uninstall      # Windows
```

Removes the links this repo owns and restores the newest backup of anything the
installer displaced. Links pointing anywhere else are left strictly alone. Both
modes accept the dry-run flag.

> **Windows notes:** `install.sh` deliberately **refuses to run under git-bash /
> MSYS / Cygwin** — `ln -s` there silently *copies* instead of linking, which
> would leave stale files that never receive repo updates. Use `install.ps1`.
> File symlinks need Developer Mode (*Settings → Privacy & security → For
> developers*) or an elevated shell; skill *directories* fall back to a Junction,
> which needs neither — so skills always link cleanly, and only the *file* links
> (`CLAUDE.md`, `settings.json`, `agents/*.md`) require the one-time Developer
> Mode toggle.

### Alternative: install as a plugin

The repo doubles as a Claude Code [plugin](https://docs.claude.com/en/docs/claude-code/plugins)
(`.claude-plugin/plugin.json` at the root; `skills/` and `agents/` are
auto-discovered). A plugin install gets you the skills and agents, namespaced
and conflict-free — but **not** `CLAUDE.md` or `settings.json`: plugins don't
contribute a root `CLAUDE.md` as context, and permission settings stay yours.
The symlink installer remains the full-fidelity path; the plugin is the
low-commitment one. **Pick one path, not both** — installing both registers
every skill and agent twice (once bare, once plugin-namespaced).

## Why no hooks?

Hooks are the right tool for "must happen every time, zero exceptions" — but
they need project-specific commands (there is no universal "run the suite"),
and a *global* Stop hook would fire in every project on every turn. So this
repo ships what *can* be enforced globally: `permissions.deny` rules in
[`settings.json`](./settings.json), which no allow rule can override. Be clear
about their honest limits: they block the **Read tool** from secret paths (a
shell read like `cat .env` instead falls through to a permission prompt), they
deny the *common* force-push spellings (a trailing `--force` falls through to
the push prompt — which is why **every** push asks), and none of it applies
until the settings file is actually linked or merged. Test-gating hooks stay
a per-project addition. Ask
Claude to write one where it fits: *"add a Stop hook that runs `npm test` and
blocks until green."*

## Making your own skill

Copy [`skills/example-skill`](./skills/example-skill/SKILL.md) — it documents the
`SKILL.md` format (kebab-case `name`, a `description` packed with trigger words,
then the procedure body) and how Claude decides when to load a skill.

## Local, private overrides

The bottom of [`CLAUDE.md`](./CLAUDE.md) imports `~/.claude/CLAUDE.local.md` if it
exists (and silently does nothing if it doesn't — verified against Claude Code's
memory loader). Put anything you don't want public — employer conventions,
internal tool/agent names, machine-specific paths — in that file. It lives in
`~/.claude`, never in this repo, so it's impossible to commit by accident.

## Repo hygiene

CI runs `shellcheck` on the shell scripts, PSScriptAnalyzer on the PowerShell
installer, and a **leak guard**: the build fails if any blocklisted private
string lands in the tree. The blocklist itself lives *outside* the repo (as the
`LEAK_BLOCKLIST` GitHub Actions secret — one regex per line) precisely so the
repo never has to name the things it must not contain.

## License

[MIT](./LICENSE) — take it, fork it, adapt it.
