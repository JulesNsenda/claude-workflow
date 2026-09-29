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

- **Settings drift check.** A hand-merged `~/.claude/settings.json` is never
  overwritten, so a setting the repo adds later (`workflowSizeGuideline`) sat
  un-merged for two months with nothing saying so.
  [`settings-drift.sh`](./scripts/settings-drift.sh) (needs `jq`) and
  `scripts/settings-drift.ps1` (no dependencies) list every repo setting
  missing from, or different in, the live file; both installers run it from the
  "real settings.json exists" and "symlink to elsewhere" branches and print the
  command to re-run after a `git pull`. Comparison is case- and type-exact, arrays are checked per
  element, a value from the live file is never printed, and it is one-direction
  only (a setting the repo removes is not reported). Both scripts run the same
  fixtures in `scripts/settings-drift-fixtures/` in CI.
- **CI `settings-drift` jobs**, the first CI that runs the installers: the
  fixtures under Windows PowerShell 5.1 and PowerShell 7 as well as `sh`, plus
  `install.sh --dry-run` and `install.ps1 -DryRun` against a scratch home to
  check the report appears, the run finishes, and nothing is written, plus the
  `settings.json` symlink cases (own
  absolute and relative, foreign, dangling, and uninstall restoring a
  dangling backup).

### Changed

- The run-stats `gear` key in `scripts/run-stats.example.md` now reads `full`
  only, matching the README: only full-gear runs write the block.

### Fixed

- `--dry-run` / `-DryRun` created `~/.claude/skills` and `~/.claude/agents`
  before checking the flag; a dry run now writes nothing.
- A `settings.json` symlink pointing outside the repo (e.g. into a dotfiles
  repo) was silently re-pointed at this repo with no backup. It is now left
  alone and gets the drift report, like a real file. "Points at this repo" is
  decided by file identity (`-ef` / resolved path), so a relative link to the
  repo's own `settings.json` is still recognised; uninstall's ownership prefix
  now ends in a path separator, so a sibling clone such as
  `claude-workflow-fork` is not claimed.
- A **dangling** `settings.json` symlink (for instance from a moved clone) was
  never repaired. It is now backed up as `settings.json.backup.<timestamp>`
  (the link itself, so a target that is only unmounted stays restorable) and
  re-linked to this repo.
- `install.ps1` left the drift script's exit code in `$LASTEXITCODE`, which
  could surface as the installer's own exit code; it is reset. The re-run hint
  now uses `sh` / the current PowerShell host with
  `-ExecutionPolicy Bypass`, and quotes its paths.
- `install.ps1` treated a **hard-linked** real file as a stale link — Windows
  PowerShell reports any file with more than one name as `LinkType HardLink` —
  so a hard-linked `CLAUDE.md` or agent file was deleted without a backup. Only
  symbolic links and junctions count as links now; a hard-linked file is backed
  up like any real file, and a hard-linked `settings.json` is never displaced.

## [1.2.0] - 2026-09-29

Minor: one new step in `plan-gates` Phase 2 — the installed surface —
nothing removed or renamed.

### Added

- **Change summary** step in [`plan-gates`](./skills/plan-gates/SKILL.md)
  Phase 2 (new step 11): after the last plan-item commit, a short
  plain-language `## Summary` in the plan file (what changed and why per
  item, how to check it, scope cut, risks and follow-ups), reused as the PR
  description. Rejected critic findings stay local; the outward text carries
  at most a count. Where the plan file is tracked it is committed together
  with the run stats, now as `chore(plan): record summary and run stats`.
  The global `CLAUDE.md` cadence rule's "outcome first when you finish" now
  says what that outcome contains, so every gear ends the same way. The
  README diagram follows. ([#9], [#11])

### Fixed

- `.claude/CLAUDE.md` pointed at "`plan-gates` step 9" for run stats, which
  had since moved; it now names the step rather than a number.

## [1.1.0] - 2026-09-29

Minor: one new gate in `plan-gates` — the installed surface — plus one new
release script (scripts aren't installed); nothing removed or renamed. The rest is fixes and a re-check of every version-stamped
harness assumption against Claude Code 2.1.284.

### Added

- **Gate 5 · Simplify, then re-verify** in
  [`plan-gates`](./skills/plan-gates/SKILL.md) Phase 2. The bar: a competent
  junior can say what the change does without the plan file open. Drives the
  built-in `/simplify`, escalates anything past a light cleanup to a mid-tier
  `implementer`, and may neither change behaviour nor weaken a test. Gates 3
  and 4 always re-run on the simplified code. The README diagram and the
  `gates_failed_first_pass` description in
  [`run-stats.example.md`](./scripts/run-stats.example.md) follow (1–4 → 1–5);
  no run-stats key was added or renamed. ([#8])
- A tracked repo-development guide at `.claude/CLAUDE.md`, so guidance about
  *developing* this repo stays out of the shipped global `CLAUDE.md`. ([#8])
- [`scripts/version-check.sh`](./scripts/version-check.sh) and a `version-guard`
  CI job: the git tag and the `version` field in
  [`.claude-plugin/plugin.json`](./.claude-plugin/plugin.json) have to agree, and
  now something checks it rather than it being a convention. CI gained a tag
  trigger so the check fires on the tag itself; the job's fixtures run on every
  push regardless, so the script can't sit unexercised between releases.
  Detective rather than preventive by design — see
  [Releases](./README.md#releases) for the ordering that makes that safe, and
  for the one carrier (this file) that is deliberately still unguarded.
  ([#6])

### Changed

- **Model lineup moved to Fable 5.1 / Opus 5.5 / Sonnet 5.5.** Only the tier
  table's "Currently" column and the README model section change: agents pin
  family aliases, so no `model:` line moved. The copied account-type table for
  the `default` model setting was removed rather than updated, since it went
  stale with this lineup; the README now points at the model-config docs
  instead.
- **README harness assumptions re-checked against 2.1.284.** The nesting
  default is no longer contested (docs and CHANGELOG agree on depth 3), but it
  is now served remotely, so setting `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`
  explicitly is stronger advice than before. Ultracode is recorded as its own
  `/effort` toggle, with why `plan-gates` stays on plain `Agent` fan-out. A
  new paragraph covers `AGENTS.md` and the project-instructions setting, whose
  `managed-only` mode silently stops the global `CLAUDE.md` loading.
- The effort claim is scoped to the Agent tool (skills *do* carry an effort
  field; `plan-gates` declines to pin it, since it overrides rather than
  floors). ([#8])

### Fixed

- **Gate 4 pointed at a built-in `/verify` that 2.1.284 doesn't ship.** It
  now names a project `verify` skill first and the built-in `/run` otherwise.
  [`ref-check.sh`](./scripts/ref-check.sh) exempts `run` as a built-in;
  mutation-verified.
- **Gate 2 names `/code-review`'s effort level** instead of calling it bare,
  which reused whatever level was typed last and decided whether the review
  ran in the orchestrator's context. ([#8])
- **[`test-runner`](./agents/test-runner.md) was told to follow a project
  `test` skill it has no `Skill` tool to load.** The body is now stated as
  authoritative. ([#8])
- **`version-check.sh` counted matching lines, not occurrences**, so a
  single-line manifest with a nested `"version"` passed a *wrong* tag clean
  and rejected the right one. The same change moved CI's tag trigger from
  `v*` to `*`, so a non-`v` tag now fails loudly instead of running no CI.
  ([#7])

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

[Unreleased]: https://github.com/JulesNsenda/claude-workflow/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/JulesNsenda/claude-workflow/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/JulesNsenda/claude-workflow/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/JulesNsenda/claude-workflow/releases/tag/v1.0.0
[#1]: https://github.com/JulesNsenda/claude-workflow/pull/1
[#2]: https://github.com/JulesNsenda/claude-workflow/pull/2
[#3]: https://github.com/JulesNsenda/claude-workflow/pull/3
[#4]: https://github.com/JulesNsenda/claude-workflow/pull/4
[#6]: https://github.com/JulesNsenda/claude-workflow/pull/6
[#7]: https://github.com/JulesNsenda/claude-workflow/pull/7
[#8]: https://github.com/JulesNsenda/claude-workflow/pull/8
[#9]: https://github.com/JulesNsenda/claude-workflow/issues/9
[#11]: https://github.com/JulesNsenda/claude-workflow/pull/11
