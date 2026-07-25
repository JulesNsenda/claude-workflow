# Changelog

Notable changes to this repo, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This is a configuration repo rather than a library, so "breaking" is read
against the **installed surface**, not an API: **major** is anything that
changes where the installer writes, or removes or renames an agent, skill, or
hard rule that existing setups already depend on; **minor** adds an agent,
skill, script, or rule; **patch** is fixes and wording. The version here is the
same one declared in
[`.claude-plugin/plugin.json`](./.claude-plugin/plugin.json) — the git tag and
the plugin manifest are kept in step, since a plugin install reads the manifest
and a clone reads the tag.

## [Unreleased]

### Added

- [`scripts/version-check.sh`](./scripts/version-check.sh) and a `version-guard`
  CI job: the git tag and the `version` field in
  [`.claude-plugin/plugin.json`](./.claude-plugin/plugin.json) have to agree, and
  now something checks it rather than it being a convention. CI gained a `v*`
  tag trigger so the check fires on the tag itself; the job's fixtures run on
  every push regardless, so the script can't sit unexercised between releases.
  Detective rather than preventive by design — see
  [Releases](./README.md#releases) for the ordering that makes that safe.

## [1.0.0] - 2026-07-25

First tagged release. Everything below already existed on `main`; this entry
describes the surface as a whole rather than a delta, because there was no
earlier release to upgrade from.

### Added

- **`CLAUDE.md`** — the always-on rules loaded every session, deliberately kept
  small because long memory files reduce adherence: the canonical **model-tier
  table** (frontier / mid / fast, with effort as a second axis), the **three
  gears** that scale rigor to blast radius (skip / light / full), the hard rules
  every gear obeys, the automatic model-routing convention, and a silent import
  of `~/.claude/CLAUDE.local.md` for private overrides.
- **Skills** (`skills/`) — [`plan-gates`](./skills/plan-gates/SKILL.md), the
  full plan → gate → commit procedure with an adversarial planning panel, an
  approval stop, and four gates per implemented item;
  [`test`](./skills/test/SKILL.md), the dedicated testing pass;
  [`example-skill`](./skills/example-skill/SKILL.md), a documented template for
  writing your own.
- **Subagents** (`agents/`) — the adversarial
  [`security-critic`](./agents/security-critic.md) and
  [`architecture-critic`](./agents/architecture-critic.md), which review both
  the plan and the diff and emit findings rather than reasoning transcripts; an
  [`implementer`](./agents/implementer.md) with no web or research tools, so it
  builds strictly from the approved plan; a
  [`test-runner`](./agents/test-runner.md) specialist; and an
  [`Explore`](./agents/explore.md) override pinned to the fast tier, which keeps
  discovery cheap on a frontier session.
- **`settings.json`** — permission hygiene: the Read tool is denied on secret
  paths, the common force-push forms are denied, every push asks, and routine
  git commands are allow-listed. Plus the advisory `workflowSizeGuideline`.
- **Installers** — [`install.sh`](./install.sh) and
  [`install.ps1`](./install.ps1) symlink the tracked config into `~/.claude`.
  Both are idempotent, back up anything they would overwrite, and support a
  dry-run.
- **Plugin manifest** ([`.claude-plugin/plugin.json`](./.claude-plugin/plugin.json))
  — the same skills and agents installable as a namespaced plugin, as a
  lower-commitment alternative to the symlink path.
- **Scripts** (`scripts/`) — [`leak-check.sh`](./scripts/leak-check.sh), which
  greps the tracked tree against a blocklist that lives outside the repo;
  [`run-stats.sh`](./scripts/run-stats.sh), which aggregates per-run critic
  yield out of local plan files so the workflow can be measured rather than
  assumed; and [`ref-check.sh`](./scripts/ref-check.sh), which fails the build
  when the docs and the agent/skill tree stop naming each other correctly.
- **CI** — `shellcheck`, PSScriptAnalyzer, and a guard per script. Each checker
  carries deliberately broken fixtures and asserts the *message* produced rather
  than the exit status alone, because a checker that quietly matches nothing
  exits 0 forever and reads as green.

Landed as pull requests [#1], [#2], [#3], and [#4].

[1.0.0]: https://github.com/JulesNsenda/claude-workflow/releases/tag/v1.0.0
[#1]: https://github.com/JulesNsenda/claude-workflow/pull/1
[#2]: https://github.com/JulesNsenda/claude-workflow/pull/2
[#3]: https://github.com/JulesNsenda/claude-workflow/pull/3
[#4]: https://github.com/JulesNsenda/claude-workflow/pull/4
