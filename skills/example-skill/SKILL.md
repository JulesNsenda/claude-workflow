---
name: example-skill
description: >-
  A copy-me template showing the SKILL.md format. Replace this description with a
  one-to-three sentence summary of WHAT the skill does and, critically, WHEN to
  use it — Claude reads only the name + description to decide whether to load a
  skill, so pack the trigger words here (e.g. "Use when the user says 'deploy',
  'ship it', or asks to release a build"). This example skill does nothing; it
  exists to be duplicated.
---

# Skill: example-skill

> Delete this file's real content and write your own. This is a template.

A **skill** is a reusable, on-demand instruction set that Claude Code loads only
when it's relevant. It lives in its own directory under `~/.claude/skills/` (user
/ global scope) or `<project>/.claude/skills/` (project scope), as a folder with a
`SKILL.md` inside:

```
skills/
└── example-skill/
    └── SKILL.md        # <- this file (required)
    └── ...             # optional: helper scripts, reference/*.md, templates, etc.
```

## The two things that matter most

1. **`name`** (frontmatter) — kebab-case, must match the directory name. This is
   what the user types after a slash: `/example-skill`.
2. **`description`** (frontmatter) — the single most important line. Claude decides
   whether to pull this skill into context based on the `name` + `description`
   ALONE, before reading the body. So the description must state **what it does**
   and **when to trigger** it, including the words a user would actually say.

Good description shape:

> `Do X for Y. Use when the user says "<trigger word>", "<trigger word>", or is
> working on <situation>. Covers <the specific cases>.`

## Writing the body

The body (everything below the frontmatter) is the actual instruction set Claude
follows once the skill loads. Write it as procedure, not prose:

- Lead with any **must-read-first** warnings or preconditions.
- Give **numbered, ordered steps** when order matters.
- Prefer concrete commands, file paths, and checks over vague guidance.
- If steps are interdependent, say so — tell Claude to read the whole thing first.
- Keep it self-contained: a skill shouldn't assume context that isn't in the
  conversation or the repo.

## How to make your own

1. Copy this folder: `cp -r skills/example-skill skills/my-skill`
   (Windows: `Copy-Item -Recurse skills\example-skill skills\my-skill`).
2. Rename the `name` in the frontmatter to `my-skill` (match the folder).
3. Rewrite the `description` with real trigger words.
4. Replace this body with your procedure.
5. Re-run `install.sh` / `install.ps1` to symlink it into `~/.claude/skills/`.
6. Restart Claude Code and try `/my-skill`.
