<#
.SYNOPSIS
  Symlink this repo's Claude Code config into ~/.claude (Windows).

.DESCRIPTION
  Links:
    ~/.claude/CLAUDE.md       -> <repo>/CLAUDE.md
    ~/.claude/skills/<name>   -> <repo>/skills/<name>   (one link per skill dir)

  Safe to re-run. Any existing REAL file/dir at a target is backed up to
  "<target>.backup.<timestamp>" before linking; existing links are replaced.
  If a step can't complete, the original is restored — the script never leaves
  a target empty.

  Windows elevation:
    - Skill DIRECTORIES fall back to a Junction, which needs no elevation, so
      they always link cleanly.
    - The CLAUDE.md FILE needs a symbolic link. Windows only allows those with
      Developer Mode on (Settings > Privacy & security > For developers) or from
      an elevated shell. If neither is available the file step is deferred (with
      instructions) and everything else still links. A hardlink is deliberately
      NOT used: it would silently serve stale content after a `git pull`.

.EXAMPLE
  .\install.ps1
.EXAMPLE
  .\install.ps1 -DryRun
#>
[CmdletBinding()]
param([switch]$DryRun)

$ErrorActionPreference = 'Stop'

$RepoDir   = $PSScriptRoot
$ClaudeDir = Join-Path $env:USERPROFILE '.claude'
$Stamp     = Get-Date -Format 'yyyyMMddHHmmss'
$script:Deferred = @()

function Info($msg) { Write-Host "  $msg" }

function Get-LinkTarget($path) {
  $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
  if ($item -and $item.LinkType) { return ($item.Target -join '') }  # symlink or junction
  return $null
}

function New-Link {
  # Returns $true on success (or dry-run/no-op), $false if the step was deferred.
  param([string]$Source, [string]$Target, [switch]$IsDir)

  if (-not (Test-Path -LiteralPath $Source)) {
    Info "skip (source missing): $Source"
    return $true
  }

  # Already the correct link? Nothing to do.
  if ((Get-LinkTarget $Target) -ieq $Source) {
    Info "ok (already linked): $Target"
    return $true
  }

  $shortTarget = $Target.Replace($env:USERPROFILE, '~')
  $shortSource = $Source.Replace($env:USERPROFILE, '~')

  if ($DryRun) {
    if (Test-Path -LiteralPath $Target) { Info "would back up + link: $shortTarget -> $shortSource" }
    else                                { Info "would link: $shortTarget -> $shortSource" }
    return $true
  }

  # Stash whatever is at the target: delete a stale link, back up real data.
  $backup = $null
  if (Get-LinkTarget $Target) {
    (Get-Item -LiteralPath $Target -Force).Delete()
  } elseif (Test-Path -LiteralPath $Target) {
    $backup = "$Target.backup.$Stamp"
    Move-Item -LiteralPath $Target -Destination $backup
  }

  # Prefer a real symlink; fall back to a junction for directories only.
  try {
    New-Item -ItemType SymbolicLink -Path $Target -Value $Source -Force | Out-Null
    if ($backup) { Info "backed up existing -> $(Split-Path $backup -Leaf)" }
    Info "linked (symlink): $shortTarget -> $shortSource"
    return $true
  } catch {
    if ($IsDir) {
      New-Item -ItemType Junction -Path $Target -Value $Source -Force | Out-Null
      if ($backup) { Info "backed up existing -> $(Split-Path $backup -Leaf)" }
      Info "linked (junction): $shortTarget -> $shortSource"
      return $true
    }
    # Files: no elevation-free link that survives `git pull`. Restore and defer.
    if ($backup) { Move-Item -LiteralPath $backup -Destination $Target }
    Info "DEFERRED (needs elevation): $shortTarget"
    $script:Deferred += $shortTarget
    return $false
  }
}

Write-Host "claude-workflow installer"
Write-Host "  repo:   $RepoDir"
Write-Host "  target: $ClaudeDir"
if ($DryRun) { Write-Host "  (dry run - no changes)" }
Write-Host ""

New-Item -ItemType Directory -Force -Path (Join-Path $ClaudeDir 'skills') | Out-Null

Write-Host "CLAUDE.md:"
New-Link -Source (Join-Path $RepoDir 'CLAUDE.md') -Target (Join-Path $ClaudeDir 'CLAUDE.md') | Out-Null

Write-Host ""
Write-Host "skills:"
$skillsRoot = Join-Path $RepoDir 'skills'
$skillDirs  = @()
if (Test-Path -LiteralPath $skillsRoot) {
  $skillDirs = @(Get-ChildItem -LiteralPath $skillsRoot -Directory -ErrorAction SilentlyContinue)
}
if ($skillDirs.Count -eq 0) {
  Info "(none in repo yet)"
} else {
  foreach ($skill in $skillDirs) {
    New-Link -Source $skill.FullName -Target (Join-Path $ClaudeDir "skills\$($skill.Name)") -IsDir | Out-Null
  }
}

Write-Host ""
if ($script:Deferred.Count -gt 0) {
  Write-Warning "Deferred (Windows needs elevation for file symlinks):"
  foreach ($d in $script:Deferred) { Write-Warning "  $d" }
  Write-Host ""
  Write-Host "To finish, do ONE of these, then re-run this script:" -ForegroundColor Yellow
  Write-Host "  * Re-run from an elevated PowerShell (Run as administrator), or" -ForegroundColor Yellow
  Write-Host "  * Enable Developer Mode: Settings > Privacy & security > For developers." -ForegroundColor Yellow
  Write-Host ""
  Write-Host "Skills linked fine; only the deferred item(s) above still need this."
  exit 1
}
Write-Host "Done. Restart Claude Code to pick up changes."
