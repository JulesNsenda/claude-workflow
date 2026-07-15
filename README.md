# claude-workflow

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

**Plan → Implement → Verify → Fix**, with the model tier matched to each phase.

1. **Plan on the strongest model (Opus/Fable).** Draft a plan, then spawn **≥3
   adversarial reviewer agents in parallel**, each with a *distinct* critique
   angle (correctness/edge-cases, over-engineering, integration blast-radius) and
   told to find flaws, not rubber-stamp. Reconcile their critiques into a plan
   file at `docs/plans/YYYY-MM-DD-<slug>.md`, then **stop for approval** before
   writing production code.
2. **Implement on Sonnet, fanned out.** One agent per file / cohesive unit, in
   parallel. Implement strictly to the plan — deviations get surfaced, not
   silently accepted.
3. **Verify on Opus.** Walk the diff against the plan item-by-item; report
   pass/fail per item.
4. **Fix loop.** Any issue → re-plan (Opus) → re-implement (Sonnet) → re-verify,
   until clean.

**Model routing (every task):** reading/searching → Haiku · planning/verifying/
orchestrating → Opus · implementing → Sonnet. The orchestrating session stays on
Opus and spawns cheaper agents for the cheap phases.

**When to skip the ritual:** one-line fixes, obvious single-file edits, pure
questions, or when you've already been given a specific approach.

The full, authoritative version lives in [`CLAUDE.md`](./CLAUDE.md).

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

> **Windows symlink note:** file symlinks need Developer Mode (*Settings → Privacy
> & security → For developers*) or an elevated shell. Skill *directories* fall back
> to a Junction, which needs neither — so skills always link cleanly, and only
> `CLAUDE.md` requires the one-time Developer Mode toggle.

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

## License

[MIT](./LICENSE) — take it, fork it, adapt it.
