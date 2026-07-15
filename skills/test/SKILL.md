---
name: test
description: >-
  Run the full test suite AND expand coverage for the current change — the
  dedicated testing pass. Its ONLY job is tests. Use after implementing or
  verifying a change, and whenever the user says "test", "run tests", "cover
  this", "write tests", or "make sure it's tested". Enforces: nothing is done
  until the suite is green and every change is covered (with a regression test
  per bug fixed).
---

# Skill: test

The testing specialist. Tests are the *only* thing this pass touches — no
refactors, no feature work, no scope creep. Goal: **everything the change
introduced or altered is exercised, and the whole suite is green.**

## 1. Find the runner (don't assume)

Detect how this project runs tests before running anything:

- **JS/TS** → `package.json` `scripts` (`test`, `test:unit`, `test:ci`); jest /
  vitest / mocha / node:test config.
- **Python** → `pytest` (`pyproject.toml` / `pytest.ini` / `tox.ini`), or
  `unittest`.
- **Go** → `go test ./...`. **Rust** → `cargo test`. **Java** → `mvn test` /
  `gradle test`. **Ruby** → `rspec` / `rake test`.
- Fallback: a `Makefile` / `justfile` `test` target, or CI config
  (`.github/workflows/*`) — mirror what CI runs.

If you genuinely can't determine it, ask — don't silently skip testing.

## 2. Run the full existing suite first

Establish the baseline. Capture failures verbatim. A pre-existing failure is
reported, not hidden — but don't let it mask regressions from the change.

## 3. Map the change surface

From `git diff` (vs the base branch or the pre-change state), list every new or
modified: function/method, conditional branch, error path, boundary, and public
interface. That list is your coverage target — not the whole codebase, but *all*
of the change.

## 4. Cover every item on that list

For each change-surface item, ensure a test exists for:

- the happy path,
- edge cases (empty/nil, boundaries, large inputs, concurrency if relevant),
- error handling (the failure actually surfaces the way it should),
- **a regression test for any bug this change fixed** — it must fail on the old
  code and pass on the new.

Match the project's existing test style, helpers, and file layout. Reuse
fixtures/factories rather than inventing parallel ones.

## 5. Re-run until green, then report coverage of the change

Iterate: run → fix the test or surface a real defect → run. When green, report:

- suite result (counts, duration),
- **what the change's coverage actually is** — which change-surface items are
  covered, and any left uncovered *with the reason* (e.g. "requires a live
  network host"). Report the change's coverage, not just the global percentage.

## Non-negotiables

- **Never** weaken, `skip`, or delete a test to force green. If a test fails,
  either the code is wrong (fix it / flag it) or the test is wrong (fix the
  test with justification) — never make it disappear.
- **Never** assert on wrong-but-current behavior just to lock in a passing run.
- An untestable path is a **finding to resolve**, not a step to skip — say so
  explicitly rather than quietly leaving it uncovered.
