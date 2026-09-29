# settings-drift.ps1 - report which repo settings.json entries are missing or
# different in a real (hand-merged) ~/.claude/settings.json.
#
# The installers never overwrite a real settings.json, so a setting the repo adds
# later (workflowSizeGuideline, PR #3) sat un-merged for two months with nothing
# saying so. This walks the REPO file and names every path the live file lacks.
# It is read-only and never edits either file.
#
# Usage:
#   powershell -NoProfile -File scripts\settings-drift.ps1 -Repo <path> -Live <path>
#
# The contract (CLI, exit codes, the ordered "not checked" messages, walk rules,
# output formats, escaping) lives in scripts/settings-drift-fixtures/README.md,
# the single tracked source of truth. Callers such as the installers must ignore
# the exit code and never abort on it.
#
# This is the twin of scripts/settings-drift.sh, for machines without jq (a stock
# Windows box has no JSON tool in common with a Mac or Linux one). Windows
# PowerShell 5.1 and PowerShell 7, no modules. scripts/settings-drift-fixtures/ is
# the shared contract: CI runs both implementations over the same fixtures against
# the same expected-output files. Change a rule in one, change it in both.
#
# Why the walk is shaped this way: comparison is case- and type-exact and uses
# PATH ARRAYS, never dotted strings. PowerShell is case-insensitive and
# type-coercing by default (-eq, -contains, -in, dotted property access) and even
# -ceq is culture-sensitive (it ignores a soft hyphen), so none of those touch a
# key or value here: properties are found by iterating PSObject.Properties and
# every string is compared with [string]::Equals(a, b, Ordinal).
#
# A live VALUE is never printed - only its type - and an exception message is
# never printed either (it can quote input): everything after argument validation
# sits in one try/catch that reports "comparison failed". ConvertTo-Json is not
# used for output: 5.1 escapes <>' differently from jq and unrolls one-element
# arrays, so the encoder below is hand-written to match jq's tojson.
#
# Known limitation: ONE DIRECTION. A rule the repo later removes stays in a
# hand-merged file forever; this cannot see it. The convention that covers it is
# a CHANGELOG entry "Removed - delete from a hand-merged settings.json".
#
# Known parser divergence (accepted, kept out of the parity fixtures): PowerShell
# 5.1 and 7 reject keys that differ only in case, and PowerShell 7 tolerates
# comments and trailing commas; jq does the opposite. For such inputs one tool says
# "could not be parsed" and the other reports drift. Number formatting (1.0, large
# ints) and date-looking strings (PowerShell 7 may turn them into DateTime) are
# also unmatched between the two implementations - the repo settings hold neither.

param(
  [string]$Repo,
  [string]$Live
)

$ErrorActionPreference = 'Stop'

# $args catches extra positionals; Mandatory is not used - it would prompt.
if ($args.Count -gt 0 -or -not $Repo -or -not $Live) {
  [Console]::Error.WriteLine('usage: settings-drift.ps1 -Repo <repo-settings> -Live <live-settings>')
  exit 2
}

function Stop-NotChecked([string]$Reason) {
  Write-Output "settings drift: not checked - $Reason"
  exit 2
}

# JSON type name of a parsed value. Tested on the value itself, never on a
# pipeline result, so a one-element array or $null is not unrolled away.
function Get-JType($v) {
  if ($null -eq $v) { return 'null' }
  if ($v -is [string]) { return 'string' }
  if ($v -is [bool]) { return 'boolean' }
  if ($v -is [System.Collections.IList]) { return 'array' }
  if ($v -is [System.Management.Automation.PSCustomObject]) { return 'object' }
  if ($v -is [ValueType] -and $v -isnot [char] -and $v -isnot [datetime]) { return 'number' }
  return 'string'
}

# jq-compatible string escaping: \" \\ \n \t \r \b \f, other control chars as
# \u00xx lowercase hex, DEL (0x7f) as \u007f (jq escapes it too), everything else
# literal.
function ConvertTo-JString([string]$s) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  foreach ($c in $s.ToCharArray()) {
    # Switch on the code point, never on the character: `switch` compares
    # strings culture-sensitively, and under PowerShell 7's ICU a control
    # character is "ignorable" — DEL (0x7f) matched the "`b" case and printed
    # \b. The del-escape fixture caught it on the pwsh leg only.
    switch ([int]$c) {
      34 { [void]$sb.Append('\"') }
      92 { [void]$sb.Append('\\') }
      10 { [void]$sb.Append('\n') }
      9  { [void]$sb.Append('\t') }
      13 { [void]$sb.Append('\r') }
      8  { [void]$sb.Append('\b') }
      12 { [void]$sb.Append('\f') }
      default {
        if ([int]$c -lt 32 -or [int]$c -eq 127) { [void]$sb.Append(('\u{0:x4}' -f [int]$c)) }
        else { [void]$sb.Append($c) }
      }
    }
  }
  [void]$sb.Append('"')
  return $sb.ToString()
}

# Canonical JSON: keys sorted (ordinal, as jq does) recursively, compact.
function ConvertTo-Canon($v) {
  switch (Get-JType $v) {
    'null'    { return 'null' }
    'boolean' { if ($v) { return 'true' } else { return 'false' } }
    'string'  { return (ConvertTo-JString ([string]$v)) }
    'number'  {
      # BigInteger is not IConvertible (the cast below would throw, quoting the value);
      # matched by type name so the assembly need not be loaded on 5.1.
      if ([string]::Equals($v.GetType().FullName, 'System.Numerics.BigInteger', [System.StringComparison]::Ordinal)) {
        return $v.ToString([System.Globalization.CultureInfo]::InvariantCulture)
      }
      if ($v -is [double] -or $v -is [single]) {
        return $v.ToString('R', [System.Globalization.CultureInfo]::InvariantCulture)
      }
      return ([System.IConvertible]$v).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    'array'   {
      $parts = New-Object 'System.Collections.Generic.List[string]'
      foreach ($e in $v) { $parts.Add((ConvertTo-Canon $e)) }
      return '[' + ($parts -join ',') + ']'
    }
    default   {
      $names = New-Object 'System.Collections.Generic.List[string]'
      foreach ($p in $v.PSObject.Properties) { $names.Add([string]$p.Name) }
      $names.Sort([System.StringComparer]::Ordinal)
      $parts = New-Object 'System.Collections.Generic.List[string]'
      foreach ($n in $names) {
        foreach ($p in $v.PSObject.Properties) {
          if ([string]::Equals([string]$p.Name, $n, [System.StringComparison]::Ordinal)) { $parts.Add((ConvertTo-JString $n) + ':' + (ConvertTo-Canon $p.Value)); break }
        }
      }
      return '{' + ($parts -join ',') + '}'
    }
  }
}

# Split text into top-level JSON value texts. ConvertFrom-Json is not trusted to
# notice `{}{}` (it may throw, or return only one value), so a multi-document
# file is detected here, deliberately. Objects/arrays are cut by bracket depth
# with string/escape state; anything else is taken as one value to the end.
function Split-JsonValues([string]$t) {
  $vals = New-Object 'System.Collections.Generic.List[string]'
  $i = 0
  $n = $t.Length
  while ($true) {
    while ($i -lt $n -and [char]::IsWhiteSpace($t[$i])) { $i++ }
    if ($i -ge $n) { break }
    if ($t[$i] -ne '{' -and $t[$i] -ne '[') {
      # A scalar value: cut it at its end so `"a" "b"` is two values, as jq sees it.
      $start = $i
      if ($t[$i] -eq '"') {
        $i++
        while ($i -lt $n -and $t[$i] -ne '"') { if ($t[$i] -eq '\') { $i++ }; $i++ }
        $i++
      } else {
        while ($i -lt $n -and -not [char]::IsWhiteSpace($t[$i])) { $i++ }
      }
      if ($i -gt $n) { $i = $n }
      $vals.Add($t.Substring($start, $i - $start))
      continue
    }
    $start = $i
    $depth = 0
    $inStr = $false
    $esc = $false
    $end = -1
    for (; $i -lt $n; $i++) {
      $c = $t[$i]
      if ($inStr) {
        if ($esc) { $esc = $false }
        elseif ($c -eq '\') { $esc = $true }
        elseif ($c -eq '"') { $inStr = $false }
      } elseif ($c -eq '"') { $inStr = $true }
      elseif ($c -eq '{' -or $c -eq '[') { $depth++ }
      elseif ($c -eq '}' -or $c -eq ']') {
        $depth--
        if ($depth -eq 0) { $end = $i; break }
      }
    }
    if ($end -lt 0) {
      $vals.Add($t.Substring($start))
      break
    }
    $vals.Add($t.Substring($start, $end - $start + 1))
    $i = $end + 1
  }
  return , $vals
}

# Read and parse a settings file. Returns a hashtable: State is ok | empty |
# multi | error; for ok, Value is the parsed root and IsObject says whether the
# root is a JSON object (decided from the text - 5.1 unrolls a root array).
function Read-Settings([string]$path) {
  try {
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($text)) { return @{ State = 'empty' } }
    $vals = Split-JsonValues $text
    $parsed = New-Object 'System.Collections.Generic.List[object]'
    foreach ($raw in $vals) {
      $parsed.Add((ConvertFrom-Json -InputObject $raw -ErrorAction Stop))
    }
    if ($vals.Count -ne 1) { return @{ State = 'multi' } }
    return @{ State = 'ok'; Value = $parsed[0]; IsObject = ([string]::Equals([string]$vals[0][0], '{', [System.StringComparison]::Ordinal)) }
  } catch {
    # Never the exception text: it can quote live content.
    return @{ State = 'error' }
  }
}

$script:drift = New-Object 'System.Collections.Generic.List[string]'

# Walk the repo value $rv against the live value $lv (meaningful only when $ex,
# i.e. the live side exists at this path). $path is a string[] of keys.
function Compare-Node($rv, [bool]$ex, $lv, [string[]]$path) {
  $p = ConvertTo-Canon $path
  $lt = Get-JType $lv
  switch (Get-JType $rv) {
    'object' {
      if ($ex -and $lt -ne 'object') {
        $script:drift.Add("settings drift: differs $p repo object, live $lt")
      } elseif (-not $ex -and @($rv.PSObject.Properties).Count -eq 0) {
        $script:drift.Add("settings drift: missing $p {}")
      } else {
        foreach ($prop in $rv.PSObject.Properties) {
          $k = [string]$prop.Name
          $h = $false
          $child = $null
          if ($ex -and $lt -eq 'object') {
            foreach ($lp in $lv.PSObject.Properties) {
              if ([string]::Equals([string]$lp.Name, $k, [System.StringComparison]::Ordinal)) { $h = $true; $child = $lp.Value; break }
            }
          }
          Compare-Node $prop.Value $h $child ([string[]]($path + $k))
        }
      }
    }
    'array' {
      if ($ex -and $lt -ne 'array') {
        $script:drift.Add("settings drift: differs $p repo array, live $lt")
      } elseif (-not $ex -and $rv.Count -eq 0) {
        $script:drift.Add("settings drift: missing $p []")
      } else {
        $have = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
        if ($ex) { foreach ($x in $lv) { [void]$have.Add((ConvertTo-Canon $x)) } }
        foreach ($e in $rv) {
          $c = ConvertTo-Canon $e
          if (-not $have.Contains($c)) { $script:drift.Add("settings drift: missing $p $c") }
        }
      }
    }
    default {
      $c = ConvertTo-Canon $rv
      if (-not $ex) {
        $script:drift.Add("settings drift: missing $p $c")
      } elseif (-not [string]::Equals($c, (ConvertTo-Canon $lv), [System.StringComparison]::Ordinal)) {
        $script:drift.Add("settings drift: differs $p repo $c, live $lt")
      }
    }
  }
}

# Everything from here sits in one try/catch: an unexpected failure (a value type the
# encoder does not know, a PowerShell 7 parse quirk) must not print the exception,
# which can quote live content.
try {
  # --- repo side: parse, then require something to compare ---
  if (-not (Test-Path -LiteralPath $Repo -PathType Leaf)) {
    Stop-NotChecked 'repo settings.json could not be parsed by PowerShell'
  }
  $r = Read-Settings $Repo
  if ($r.State -eq 'error') { Stop-NotChecked 'repo settings.json could not be parsed by PowerShell' }
  $repoKeys = 0
  if ($r.State -eq 'ok' -and $r.IsObject) {
    foreach ($prop in $r.Value.PSObject.Properties) {
      if (-not [string]::Equals([string]$prop.Name, '$schema', [System.StringComparison]::Ordinal)) { $repoKeys++ }
    }
  }
  if ($repoKeys -eq 0) { Stop-NotChecked 'repo settings.json has nothing to compare' }

  # --- live side ---
  # Get-Item -Force sees a dangling link (Test-Path on 5.1 may not follow one), so the
  # target is tested through .NET, which does follow: a dangling link is "not found",
  # as with sh. A link to a pipe/device would hang Get-Content, so after the Leaf check
  # only a FileInfo outside the \\.\ and \\?\ device namespaces is read.
  $liveItem = Get-Item -LiteralPath $Live -Force -ErrorAction SilentlyContinue
  if ($null -eq $liveItem -or -not ([System.IO.File]::Exists($liveItem.FullName) -or [System.IO.Directory]::Exists($liveItem.FullName))) {
    Stop-NotChecked 'live settings.json not found'
  }
  if (-not (Test-Path -LiteralPath $Live -PathType Leaf)) { Stop-NotChecked 'live settings.json is not a regular file' }
  if ($liveItem -isnot [System.IO.FileInfo] -or $liveItem.FullName.StartsWith('\\.\', [System.StringComparison]::Ordinal) -or $liveItem.FullName.StartsWith('\\?\', [System.StringComparison]::Ordinal)) {
    Stop-NotChecked 'live settings.json is not a regular file'
  }
  $l = Read-Settings $Live
  if ($l.State -eq 'error') { Stop-NotChecked 'live settings.json could not be parsed by PowerShell' }
  if ($l.State -ne 'ok') { Stop-NotChecked 'live settings.json is empty or holds more than one JSON value' }
  if (-not $l.IsObject) { Stop-NotChecked 'live settings.json is not a JSON object' }

  foreach ($prop in $r.Value.PSObject.Properties) {
    if ([string]::Equals([string]$prop.Name, '$schema', [System.StringComparison]::Ordinal)) { continue }
    $h = $false
    $child = $null
    foreach ($lp in $l.Value.PSObject.Properties) {
      if ([string]::Equals([string]$lp.Name, [string]$prop.Name, [System.StringComparison]::Ordinal)) { $h = $true; $child = $lp.Value; break }
    }
    Compare-Node $prop.Value $h $child ([string[]]@([string]$prop.Name))
  }

  if ($script:drift.Count -eq 0) {
    Write-Output 'settings: no repo setting missing or different (live-only settings not checked)'
    exit 0
  }
  foreach ($line in $script:drift) { Write-Output $line }
  exit 1
} catch {
  Write-Output 'settings drift: not checked - comparison failed'
  exit 2
}
