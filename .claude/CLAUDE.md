# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is — and the one rule that matters most

`claude-workflow` is a **configuration repo, not an application**: the tracked
files *are* the deliverable. `install.sh` / `install.ps1` symlink them into
`~/.claude`, so on an installed machine an edit here changes the live Claude Code
config immediately — there is no build step between the two.

**The repo-root `CLAUDE.md` is the shipped product**, symlinked to
`~/.claude/CLAUDE.md` and therefore loaded as global memory in *every* project on
the machine. It is deliberately short (its own opening paragraph says why: long
memory files reduce adherence). Guidance about *developing this repo* does not
belong there — it belongs in this file. Treat the same way: `settings.json`,
`agents/*.md`, `skills/*/SKILL.md`.

## Commands

There is **no test framework and no build**. CI (`.github/workflows/ci.yml`) is
six jobs, each an inline shell block. Everything below runs from the repo root.

```bash
# Lint — exactly the five files CI checks
shellcheck install.sh scripts/leak-check.sh scripts/run-stats.sh scripts/ref-check.sh scripts/version-check.sh

# Docs <-> agents/skills cross-references (CI invokes it as `sh`, not bash — POSIX is a real constraint)
sh scripts/ref-check.sh

# Release tag vs plugin manifest; the tag argument is bare (v1.0.0), never refs/tags/v1.0.0
sh scripts/version-check.sh v1.0.0

# Plan-file stats parser, against the tracked fixture CI uses
mkdir -p /tmp/plans-fixture && cp scripts/run-stats.example.md /tmp/plans-fixture/
bash scripts/run-stats.sh /tmp/plans-fixture

# Leak guard (blocklist lives outside the repo: $LEAK_BLOCKLIST_FILE, else ~/.claude/leak-blocklist.txt)
bash scripts/leak-check.sh

# Installer, always preview first
./install.sh --dry-run          # macOS/Linux
```

```powershell
.\install.ps1 -DryRun           # Windows
Invoke-ScriptAnalyzer -Path ./install.ps1 -Severity Error, Warning   # what CI's PSScriptAnalyzer job runs
```

**Running "a single test."** The self-tests are fixture blocks inside
`ci.yml`, not files — to reproduce one, copy that step's `build_good` /
`expect_fail` block into a shell and run it. Fixture trees are not git repos,
so `ref-check.sh` needs `REF_CHECK_ALLOW_UNTRACKED=1`:

```bash
REF_CHECK_ALLOW_UNTRACKED=1 sh scripts/ref-check.sh /tmp/ref-fixture
```

**Windows:** `install.sh` refuses to run under Git Bash / MSYS / Cygwin on
purpose — `ln -s` silently deep-copies there. Use `install.ps1`. File symlinks
need Developer Mode; skill *directories* fall back to a Junction and don't.

## Architecture: how the pieces refer to each other

Four layers, each with a single source of truth. Most mistakes here are
*duplication* — restating something a lower layer already owns, so the two drift.

- **`CLAUDE.md` (root)** — always-on rules: the model-tier table, the three
  gears, the hard rules. **Model names appear only in that table.** Everything
  else says "frontier / mid / fast", so the workflow survives a model lineup
  change.
- **`skills/*/SKILL.md`** — on-demand procedure. `plan-gates` holds the full
  plan → gate → commit sequence; `test` holds the testing pass; `example-skill`
  is the copy-me template. `plan-gates` deliberately does **not** restate the
  critics' output schemas — the agent files own those.
- **`agents/*.md`** — the subagents, each with a `tools:` allowlist, a `model:`
  pin, and its own findings schema. No agent is granted a spawn tool; that
  omission is the nesting control.
- **`scripts/`** — the CI checks plus `run-stats.sh`. **Not symlinked by the
  installer**, so anything that needs them (e.g. the `plan-gates` run-stats step) must point
  at the clone, not `~/.claude`.

Two cross-layer rules worth knowing before editing:

- `scripts/run-stats.example.md` is the **single source of truth for the
  run-stats key list**. Change it first, then `run-stats.sh`, then the
  `plan-gates` skill. CI parses that example as its fixture, so a key rename
  that misses the parser fails the build.
- Both installers **discover `agents/*.md` and `skills/*/` dynamically** — adding
  one needs no installer edit. It does need a documentation mention (below).

## Invariants CI enforces — the ones easy to break by editing prose

`scripts/ref-check.sh` reads the repo-root `CLAUDE.md`, `skills/**/SKILL.md`,
and `README.md`. **This file is not in its corpus**, so backticks here are free.
In those three, they are not:

1. **Frontmatter `name` must match** its filename (`agents/`) or its directory
   name (`skills/`), case-insensitively. A repo house rule, not a harness
   requirement — `agents/explore.md` declares `name: Explore` to shadow the
   built-in, which is why the comparison is case-insensitive.
2. **Forward check.** In root `CLAUDE.md` and `skills/**/SKILL.md`, a backticked
   token must resolve to an agent/skill name if it *contains a hyphen*, or if a
   role word (`agent(s)`, `subagent(s)`, `critic(s)`, `skill(s)`, `override`)
   follows it. Exempt: `general-purpose`, `code-review`, `security-review`,
   `verify`, `run`, `my-skill`. **Backtick script names with the `.sh` extension** — the
   token pattern has no dot, so `ref-check.sh` is not a token while a bare
   `ref-check` is a hyphenated one that would fail to resolve.
3. **Reverse check.** Every agent and skill must appear as a backticked token at
   least once *outside its own defining file*, across root `CLAUDE.md` +
   `skills/**/SKILL.md` + `README.md`. Trimming a mention out of the root
   `CLAUDE.md` can break this even though nothing was renamed.
4. **README relative links must exist**; absolute targets and any `..` component
   are rejected outright.

Every check also **fails loudly on an empty result** (zero inventory, zero
tokens, zero classified tokens, zero README links) rather than reporting a
false clean pass.

**The CI house rule:** assertions grep for the *specific failure message*, never
just a non-zero exit. Asserting exit status alone was measured here to let three
of four checks be deleted with the build still green. So a new check ships with
one deliberately broken fixture per failure mode, each asserting its own message
— and the fixture is verified by mutation (delete the guard; the real script must
fail where the mutant reports clean).

## Line endings

`.gitattributes` pins `*.sh` to LF (a CRLF shebang breaks on Linux) and `*.ps1`
to CRLF. Markdown follows `text=auto`, so it checks out **CRLF on Windows and LF
on CI**. Consequence worth internalising: a locally clean `ref-check.sh` run is
**not** proof of a clean CI run — gawk under Git Bash strips a trailing CR from
`$0` on its own, mawk on Linux does not. A CR only bites between a backtick span
and the role word that follows it, which is exactly where the CI fixture puts it.

## Releases

Two things carry the version a consumer reads: the **git tag** and the
`version` field in `.claude-plugin/plugin.json`. `version-check.sh` asserts they
agree and CI runs it on tag pushes (the workflow triggers on `*`, not `v*`, so a
non-`v` tag fails loudly instead of running no CI at all).

Order — the check is detective, not preventive: **push the tag → wait for CI
green → `gh release create`.** A tag nothing has consumed is cheap to delete and
re-cut.

`CHANGELOG.md` is a third carrier and is **not** guarded — a tag with no matching
changelog heading still passes. That leg is a human check. For this repo semver
reads against the *installed surface*: **major** moves where the installer writes
or removes/renames an agent, skill, or hard rule; **minor** adds one; **patch** is
fixes and wording.

## Conventions when editing

- **Comments and prose explain *why*, and record what was measured or declined.**
  The density in `ci.yml` and the scripts is deliberate — match it rather than
  trimming it. A rejected alternative is documented as rejected, not deleted.
- `/docs/` and `/.claude/` are gitignored: plan files record which findings were
  consciously rejected and stay local.
- `~/.claude/CLAUDE.local.md` holds anything machine- or client-specific. It never
  lives in this repo.
