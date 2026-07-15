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
| [`CLAUDE.md`](./CLAUDE.md) | Global working preferences Claude Code loads on every session — the workflow below. |
| [`skills/`](./skills/) | On-demand [skills](https://docs.claude.com/en/docs/claude-code/skills). Ships a documented template ([`example-skill`](./skills/example-skill/SKILL.md)) plus a real [`test`](./skills/test/SKILL.md) skill that enforces the "test everything" pass. |
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

The authoritative version — including the model-tier table and the exact gates —
lives in [`CLAUDE.md`](./CLAUDE.md); this summary is deliberately loose so the
two drift as little as possible.

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
~/.claude/CLAUDE.md        ->  <repo>/CLAUDE.md
~/.claude/skills/<name>    ->  <repo>/skills/<name>   (one link per skill folder)
```

It is **safe to re-run**. Any existing *real* file at a target is moved to
`<target>.backup.<timestamp>` before the symlink is created; existing symlinks are
replaced in place.

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
> which needs neither — so skills always link cleanly, and only `CLAUDE.md`
> requires the one-time Developer Mode toggle.

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
