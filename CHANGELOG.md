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

## [1.5.0] - 2026-10-09

Minor: two new `plan-gates` rules (project-aware critics, plan sizing); nothing
removed or renamed. ([#19])

### Changed

- **`plan-gates` prefers project-aware critics.** If a project-specific review
  agent is available it becomes a task-fit critic at the plan and the diff
  review (as-is only if read-only and severity-tagged); convention sources are
  named by path in every critic's brief, since subagents can't invoke skills.
  Rejection ran highest where critics didn't know the house conventions
  (observed, uncontrolled).
- **`plan-gates` sizes the plan.** A plan-item is defined as one independently
  committable unit. More than one independent concern means proposing a split
  (or a separate light-gear change); a third fix loop on one item, or agents
  spent at about twice the plan's own budget, stops the run to offer a re-plan
  or a split. Large runs are where review stops converging.

## [1.4.0] - 2026-10-09

Minor: a new run-stats sentinel and key, and a changed `plan-gates` procedure
(the stats block is seeded at plan time and kept as a running ledger); nothing
removed — `gates_failed_first_pass` still parses. ([#17])

### Added

- **`pending` sentinel for run stats.** An abandoned or in-flight run used to
  look finished, with structural zeros feeding the ratios. A key holding
  `pending` ("not reached yet", distinct from `unknown`, "not knowable") now
  keeps the run out of the ratios and lists it as still pending by `file:line`.
- **`gates_failed` list key.** Records *which* gates needed a fix loop (`none`,
  `pending`, `unknown`, or a list such as `2,4`), and the aggregator tallies it
  per gate, so the stats say where the loops happen rather than only how many.
- **A *Filled at* column** in `scripts/run-stats.example.md`, naming the
  checkpoint at which each key is written.
- **CI check that tracked Markdown is valid UTF-8**, with a broken fixture that
  asserts its own failure message. A Windows tool once wrote cp1252 dashes into
  the run-stats format doc, which render as garbage on GitHub; CI stayed green
  because nothing parses prose.

### Changed

- **`plan-gates` seeds Run stats at plan time and keeps it as a running
  ledger.** Writing the block only at the end meant an interrupted run left no
  trace. The block is now seeded when the plan file is written, updated at each
  checkpoint, and closed observably before the change summary, which now
  carries one composed Run stats line. `escaped` stays `pending` until close so
  an abandoned run cannot enter the ratios with a structural zero.

### Deprecated

- **`gates_failed_first_pass` is legacy-only.** Old blocks still parse (shown
  as `n=2` in the GATES column); new blocks write `gates_failed` instead.

## [1.3.1] - 2026-10-08

Patch: fixes to the run-stats aggregator, which is not part of the installed
surface. No agent, skill, rule or installer change. ([#15])

### Fixed

- **Unfinished runs were hidden.** A `## Run stats` heading followed by prose
  instead of a fenced block was folded into an anonymous "malformed" count, so
  runs that never reported were invisible. Such sections are now listed by
  `file:line` as "never filled in". A fence with no recognised key is listed
  separately as malformed.
- **Suffixed headings were dropped silently.** `## Run stats — <label>` (one
  block per run, so a later run on the same plan gets its own heading) is now
  parsed. Near-miss headings (another level or casing) get a warning on stderr.
- **An unclosed fence could swallow the rest of a file** and feed partial
  counters into the ratios. Fences now follow CommonMark: the length is
  tracked, and a block only closes on a bare closer. Only a `yaml` or bare
  fence under the heading counts as the stats block. An unclosed block is
  discarded and reported at its opening line.
- **The same directory passed twice** (for example `plans` and `plans/`)
  double-counted every run. Directories are now deduped on their canonical
  path. A path shaped like `name=value` is no longer read as an awk variable
  assignment.
- **Control-byte sanitising now covers filenames as well as values**, plus
  UTF-8 C1 and bidi controls. One sanitiser is shared by every printed line.

### Changed

- **Duplicate reporting:**
  - A duplicate is now a block with identical values, in any file. The message
    now reads `duplicate block(s) (identical values)`.
  - A (date, slug) pair that appears in more than one file with different values
    gets its own warning, since it is either a stale copy or a name collision.
  - Several blocks in one file are no longer reported as duplicates.
- **The CI smoke test:**
  - It now carries one fixture per parser failure path, each asserting its own
    message.
  - The canonical-format check fails if the example produces any warning or
    diagnostic line, whatever its wording.
  - It records which awk the runner used.

## [1.3.0] - 2026-09-30

Minor: two new scripts (the settings drift check) that both installers now
call, and installer fixes that narrow what they overwrite; nothing removed or
renamed. ([#13])

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

[Unreleased]: https://github.com/JulesNsenda/claude-workflow/compare/v1.5.0...HEAD
[1.5.0]: https://github.com/JulesNsenda/claude-workflow/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/JulesNsenda/claude-workflow/compare/v1.3.1...v1.4.0
[1.3.1]: https://github.com/JulesNsenda/claude-workflow/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/JulesNsenda/claude-workflow/compare/v1.2.0...v1.3.0
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
[#13]: https://github.com/JulesNsenda/claude-workflow/pull/13
[#15]: https://github.com/JulesNsenda/claude-workflow/pull/15
[#17]: https://github.com/JulesNsenda/claude-workflow/pull/17
[#19]: https://github.com/JulesNsenda/claude-workflow/pull/19
