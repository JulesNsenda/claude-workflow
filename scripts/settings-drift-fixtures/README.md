# settings-drift fixtures and contract

This directory is the tracked single source of truth for what
`scripts/settings-drift.sh` and `scripts/settings-drift.ps1` do. The two scripts
implement it independently (there is no JSON tool common to a stock Mac, Linux
and Windows box); CI runs both over every case below and compares their output
with the expected files. Change a rule here, in both scripts, and in a fixture.

The fixtures were cut against jq 1.7.1 (escaping and number formatting are jq's).

## Contract

ASCII only in every message (a Windows PowerShell 5.1 console mangles an em
dash). Output has no indentation - the installers indent it.

**CLI.** `sh scripts/settings-drift.sh <repo> <live>`;
`scripts/settings-drift.ps1 -Repo <path> -Live <path>`. Wrong or extra arguments
print `usage: ...` on stderr and exit 2. **Exit:** 0 clean, 1 drift, 2 not
checked. Callers must ignore the code and never abort on it.

**Not-checked lines.** Exactly one is printed (exit 2), first match in this
order:

```
settings drift: not checked - jq not found                                  (sh only; probes ${CLAUDE_WORKFLOW_JQ:-jq})
settings drift: not checked - repo settings.json could not be parsed by <jq|PowerShell>
settings drift: not checked - repo settings.json has nothing to compare     (empty / non-object / only $schema)
settings drift: not checked - live settings.json not found
settings drift: not checked - live settings.json is not a regular file
settings drift: not checked - live settings.json could not be parsed by <jq|PowerShell>
settings drift: not checked - live settings.json is empty or holds more than one JSON value
settings drift: not checked - live settings.json is not a JSON object
settings drift: not checked - comparison failed                             (any unexpected failure after the checks above)
```

A tool's own error message is never printed (it can quote live content). The
two "could not be parsed" cases name the tool, so they carry `expected.jq.txt`
and `expected.ps.txt` instead of `expected.txt`.

**Walk.** `compare(repoValue, liveExists, liveValue, pathArray)` in repo document
order. The root is an object and the root key `$schema` is skipped.

- **repo object:** live present and not an object: `differs P repo object, live T`.
  Repo `{}` and live absent: `missing P {}`. Otherwise recurse per repo key; the
  live side is present iff live is an object with that exact (case-sensitive,
  ordinal) key.
- **repo array:** live present and not an array: `differs P repo array, live T`.
  Repo `[]` and live absent: `missing P []`. Otherwise, per repo element E in
  order: `missing P E` unless live is present and some live element equals E
  (deep, type- and case-exact, object key order irrelevant). No descent into
  arrays, so arrays of objects (hooks) are compared whole.
- **repo scalar** (string/number/boolean/null): live absent: `missing P V`;
  live present and unequal (type- and case-exact): `differs P repo V, live T`.

Comparison is ordinal: no culture, no case folding, no normalisation (a soft
hyphen is a character). There is deliberately no substring match: a live
`Read(.env.*)` must not satisfy the repo rule `Read(.env)`.

**Output.** `P` is the path array as compact JSON (`["permissions","deny"]`).
`V` and `E` are compact canonical JSON of the repo value: object keys sorted
(ordinal, so uppercase before lowercase), string escapes `\"` `\\` `\n` `\t`
`\r` `\b` `\f`, other control characters and DEL (0x7f) as lowercase `\u00xx`,
everything else literal. `T` is the live type: `object`, `array`, `string`,
`number`, `boolean` or `null`. A live **value** is never printed. Prefixes are
`settings drift: missing ` and `settings drift: differs `. With no drift, print
exactly `settings: no repo setting missing or different (live-only settings not
checked)`.

**Known divergences, kept out of the fixtures.** Keys differing only in case
(PowerShell rejects, jq accepts), comments and trailing commas (PowerShell 7
tolerates, jq rejects), and number formatting such as `1.0`. Key sort is ordinal UTF-16 in PowerShell
but code-point in jq; they differ only for keys mixing astral characters with
U+E000-U+FFFF (the current settings.json is ASCII). Non-ASCII repo values may be
mangled when a child `powershell.exe` is captured through the console code page
(the CI harness sets UTF-8 output encoding; the installer runs the check
in-process). One direction only: a rule the repo removes stays in a hand-merged
file.

## Layout

One directory per case:

- `repo.json` - the repo-side settings (the side that is walked).
- `live.json` - the hand-merged side. Deliberately absent in `live-absent` and
  `two-floors`, a directory in `live-is-directory`, 0 bytes in `empty-live`,
  CRLF in `crlf-live`.
- `expected.txt` - the exact stdout both implementations must print.
- `expected.jq.txt` / `expected.ps.txt` - only where the message names the tool
  (`invalid-json-live`, `invalid-json-repo`, `two-floors`).

The harness compares output modulo line endings (CR is stripped, since jq.exe on
Windows may emit CRLF). The exit code is implied by the expected output: the clean
line means 0, a `missing`/`differs` line means 1, a `not checked` line means 2.

`sentinel-never-printed` holds `SENTINEL-LIVE-7f3a` on the live side and the
harness also asserts it is absent from the output; `bigint-live` likewise checks
that a 30-digit live integer is reported as `number` only. Fixtures are
byte-exact input (see `.gitattributes`) - do not let an editor reflow them.
