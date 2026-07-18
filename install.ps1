<#
.SYNOPSIS
  Symlink this repo's Claude Code config into ~/.claude (Windows).

.DESCRIPTION
  Links:
    ~/.claude/CLAUDE.md         -> <repo>/CLAUDE.md
    ~/.claude/settings.json     -> <repo>/settings.json  (only into an empty slot -
                                   a real settings.json is never displaced)
    ~/.claude/agents/<name>.md  -> <repo>/agents/<name>.md (one link per agent file)
    ~/.claude/skills/<name>     -> <repo>/skills/<name>   (one link per skill dir)

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
.EXAMPLE
  .\install.ps1 -Uninstall
  # Removes the links this repo owns and restores the newest backup of anything
  # the installer displaced. Links pointing anywhere else are left alone.
#>
[CmdletBinding()]
param([switch]$DryRun, [switch]$Uninstall)

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
    # Windows PowerShell 5.1's New-Item ignores the Developer Mode
    # unprivileged-symlink flag; cmd's mklink honors it. Try it before
    # deferring (redirects inside cmd so a privilege failure stays silent).
    cmd /c "mklink ""$Target"" ""$Source"" >nul 2>&1"
    if ((Get-LinkTarget $Target) -ieq $Source) {
      if ($backup) { Info "backed up existing -> $(Split-Path $backup -Leaf)" }
      Info "linked (symlink): $shortTarget -> $shortSource"
      return $true
    }
    # Files: no elevation-free link that survives `git pull`. Restore and defer.
    if ($backup) { Move-Item -LiteralPath $backup -Destination $Target }
    Info "DEFERRED (needs elevation): $shortTarget"
    $script:Deferred += $shortTarget
    return $false
  }
}

function Remove-Link {
  # Removes the target if it is a link owned by this repo, then restores the
  # newest backup when the slot is (or would be) empty. Anything that isn't our
  # link is left strictly alone. (.Delete() on a junction/symlink removes only
  # the reparse point — never the linked repo content.)
  param([string]$Target)

  $short = $Target.Replace($env:USERPROFILE, '~')
  $removed = $false
  $linkTarget = Get-LinkTarget $Target

  if ($linkTarget) {
    if ($linkTarget.StartsWith($RepoDir, [System.StringComparison]::OrdinalIgnoreCase)) {
      if ($DryRun) { Info "would unlink: $short" }
      else { (Get-Item -LiteralPath $Target -Force).Delete(); Info "unlinked: $short" }
      $removed = $true
    } else {
      Info "skip (links elsewhere): $short"
    }
  } elseif (Test-Path -LiteralPath $Target) {
    Info "skip (not a link - left in place): $short"
  }

  # Backup names are timestamped, so the last one sorted by name is newest.
  $backups = @(Get-ChildItem -Path "$Target.backup.*" -Force -ErrorAction SilentlyContinue | Sort-Object Name)
  if ($backups.Count -gt 0 -and ($removed -or -not (Test-Path -LiteralPath $Target))) {
    $newest = $backups[-1]
    if ($DryRun) { Info "would restore backup: $($newest.Name)" }
    else { Move-Item -LiteralPath $newest.FullName -Destination $Target; Info "restored backup: $($newest.Name)" }
  }
}

Write-Host "claude-workflow installer"
Write-Host "  repo:   $RepoDir"
Write-Host "  target: $ClaudeDir"
if ($Uninstall) { Write-Host "  mode:   uninstall" }
if ($DryRun) { Write-Host "  (dry run - no changes)" }
Write-Host ""

if ($Uninstall) {
  Write-Host "CLAUDE.md:"
  Remove-Link -Target (Join-Path $ClaudeDir 'CLAUDE.md')

  Write-Host ""
  Write-Host "settings.json:"
  Remove-Link -Target (Join-Path $ClaudeDir 'settings.json')

  Write-Host ""
  Write-Host "agents:"
  $repoAgents = @()
  if (Test-Path -LiteralPath (Join-Path $RepoDir 'agents')) {
    $repoAgents = @(Get-ChildItem -LiteralPath (Join-Path $RepoDir 'agents') -Filter '*.md' -File -ErrorAction SilentlyContinue)
  }
  if ($repoAgents.Count -eq 0) { Info "(none in repo)" }
  else { foreach ($a in $repoAgents) { Remove-Link -Target (Join-Path $ClaudeDir "agents\$($a.Name)") } }

  Write-Host ""
  Write-Host "skills:"
  $repoSkills = @()
  if (Test-Path -LiteralPath (Join-Path $RepoDir 'skills')) {
    $repoSkills = @(Get-ChildItem -LiteralPath (Join-Path $RepoDir 'skills') -Directory -ErrorAction SilentlyContinue)
  }
  if ($repoSkills.Count -eq 0) { Info "(none in repo)" }
  else { foreach ($s in $repoSkills) { Remove-Link -Target (Join-Path $ClaudeDir "skills\$($s.Name)") } }

  Write-Host ""
  Write-Host "Done. Restart Claude Code to pick up changes."
  exit 0
}

New-Item -ItemType Directory -Force -Path (Join-Path $ClaudeDir 'skills') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $ClaudeDir 'agents') | Out-Null

Write-Host "CLAUDE.md:"
New-Link -Source (Join-Path $RepoDir 'CLAUDE.md') -Target (Join-Path $ClaudeDir 'CLAUDE.md') | Out-Null

Write-Host ""
Write-Host "settings.json:"
# A user's existing REAL settings.json holds accumulated permission decisions
# and hook wiring - never displace it, even with a backup. Link only into an
# empty slot (or over an existing link, which holds no data).
$settingsTarget = Join-Path $ClaudeDir 'settings.json'
if ((Test-Path -LiteralPath $settingsTarget) -and -not (Get-LinkTarget $settingsTarget)) {
  Info "skip (real settings.json exists - the repo's permission rules are NOT active until you merge $(Join-Path $RepoDir 'settings.json') into it)"
} else {
  New-Link -Source (Join-Path $RepoDir 'settings.json') -Target $settingsTarget | Out-Null
}

Write-Host ""
Write-Host "agents:"
$agentsRoot = Join-Path $RepoDir 'agents'
$agentFiles = @()
if (Test-Path -LiteralPath $agentsRoot) {
  $agentFiles = @(Get-ChildItem -LiteralPath $agentsRoot -Filter '*.md' -File -ErrorAction SilentlyContinue)
}
if ($agentFiles.Count -eq 0) {
  Info "(none in repo yet)"
} else {
  foreach ($agent in $agentFiles) {
    New-Link -Source $agent.FullName -Target (Join-Path $ClaudeDir "agents\$($agent.Name)") | Out-Null
  }
}

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
  Write-Host "Until they link, anything that references them by name (e.g. the workflow's named subagents) won't resolve."
  exit 1
}
Write-Host "Done. Restart Claude Code to pick up changes."
