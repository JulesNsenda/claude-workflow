#!/usr/bin/env bash
#
# install.sh — symlink this repo's Claude Code config into ~/.claude
#
# Links:
#   ~/.claude/CLAUDE.md          -> <repo>/CLAUDE.md
#   ~/.claude/settings.json      -> <repo>/settings.json   (only into an empty slot —
#                                   a real settings.json is never displaced)
#   ~/.claude/agents/<name>.md   -> <repo>/agents/<name>.md (one link per agent file)
#   ~/.claude/skills/<name>      -> <repo>/skills/<name>   (one link per skill dir)
#
# Safe to re-run. Any existing REAL file/dir at a target is backed up to
# "<target>.backup.<timestamp>" before the symlink is created. Existing symlinks
# are replaced in place (they hold no data).
#
# Usage:
#   ./install.sh               # link everything
#   ./install.sh --dry-run     # show what would happen, change nothing
#   ./install.sh --uninstall   # remove links owned by this repo; restore newest backups
#
# (--uninstall and --dry-run can be combined.)

set -euo pipefail
shopt -s nullglob

# git-bash / MSYS / Cygwin have no real `ln -s` by default — it silently DEEP-
# COPIES, which "succeeds" but leaves stale copies that never receive repo
# updates. Refuse and point at the PowerShell installer instead.
# (CLAUDE_WORKFLOW_ALLOW_MSYS=1 bypasses the guard, for testing only.)
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    if [[ "${CLAUDE_WORKFLOW_ALLOW_MSYS:-}" != "1" ]]; then
      echo "error: this shell can't create real symlinks ('ln -s' silently copies here)." >&2
      echo "On Windows, use the PowerShell installer instead:  .\\install.ps1" >&2
      exit 1
    fi
    ;;
esac

DRY_RUN=0
UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)   DRY_RUN=1 ;;
    --uninstall) UNINSTALL=1 ;;
    *) echo "unknown option: $arg (use --dry-run and/or --uninstall)" >&2; exit 2 ;;
  esac
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
STAMP="$(date +%Y%m%d%H%M%S)"

say()  { printf '%s\n' "$*"; }
info() { printf '  %s\n' "$*"; }

link() {
  # link <source> <target>
  local src="$1" dst="$2"

  if [[ ! -e "$src" ]]; then
    info "skip (source missing): $src"
    return
  fi

  # Already the correct symlink? Nothing to do.
  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    info "ok (already linked): ${dst/#$HOME/\~}"
    return
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    if [[ -e "$dst" || -L "$dst" ]]; then
      info "would back up + link: ${dst/#$HOME/\~} -> ${src/#$HOME/\~}"
    else
      info "would link: ${dst/#$HOME/\~} -> ${src/#$HOME/\~}"
    fi
    return
  fi

  # Back up a real file/dir; a stale symlink is just removed.
  if [[ -L "$dst" ]]; then
    rm -f "$dst"
  elif [[ -e "$dst" ]]; then
    mv "$dst" "${dst}.backup.${STAMP}"
    info "backed up existing -> ${dst##*/}.backup.${STAMP}"
  fi

  ln -sfn "$src" "$dst"
  info "linked: ${dst/#$HOME/\~} -> ${src/#$HOME/\~}"
}

unlink_target() {
  # unlink_target <target> — remove the link if it points into this repo, then
  # restore the newest backup when the slot is (or would be) empty. Anything
  # that isn't our link is left strictly alone.
  local dst="$1" tgt removed=0 newest="" b

  if [[ -L "$dst" ]]; then
    tgt="$(readlink "$dst")"
    case "$tgt" in
      "$REPO_DIR"|"$REPO_DIR"/*)
        if [[ $DRY_RUN -eq 1 ]]; then
          info "would unlink: ${dst/#$HOME/\~}"
        else
          rm -f "$dst"
          info "unlinked: ${dst/#$HOME/\~}"
        fi
        removed=1
        ;;
      *) info "skip (links elsewhere): ${dst/#$HOME/\~}" ;;
    esac
  elif [[ -e "$dst" ]]; then
    info "skip (not a link — left in place): ${dst/#$HOME/\~}"
  fi

  # Backup names are timestamped, so the lexicographically last match is newest.
  for b in "$dst".backup.*; do newest="$b"; done
  if [[ -n "$newest" ]] && { [[ $removed -eq 1 ]] || [[ ! -e "$dst" && ! -L "$dst" ]]; }; then
    if [[ $DRY_RUN -eq 1 ]]; then
      info "would restore backup: ${newest##*/}"
    else
      mv "$newest" "$dst"
      info "restored backup: ${newest##*/}"
    fi
  fi
}

say "claude-workflow installer"
say "  repo:   $REPO_DIR"
say "  target: $CLAUDE_DIR"
if [[ $UNINSTALL -eq 1 ]]; then say "  mode:   uninstall"; fi
if [[ $DRY_RUN -eq 1 ]]; then say "  (dry run — no changes)"; fi
say ""

if [[ $UNINSTALL -eq 1 ]]; then
  say "CLAUDE.md:"
  unlink_target "$CLAUDE_DIR/CLAUDE.md"

  say ""
  say "settings.json:"
  unlink_target "$CLAUDE_DIR/settings.json"

  say ""
  say "agents:"
  found=0
  for agent in "$REPO_DIR"/agents/*.md; do
    found=1
    unlink_target "$CLAUDE_DIR/agents/$(basename "$agent")"
  done
  if [[ $found -eq 0 ]]; then info "(none in repo)"; fi

  say ""
  say "skills:"
  found=0
  for skill in "$REPO_DIR"/skills/*/; do
    found=1
    unlink_target "$CLAUDE_DIR/skills/$(basename "$skill")"
  done
  if [[ $found -eq 0 ]]; then info "(none in repo)"; fi

  say ""
  say "Done. Restart Claude Code to pick up changes."
  exit 0
fi

mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/agents"

say "CLAUDE.md:"
link "$REPO_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"

say ""
say "settings.json:"
# Special-cased: a user's existing REAL settings.json holds accumulated
# permission decisions and hook wiring — never displace it, even with a backup.
# Link only into an empty slot (or over a symlink, which holds no data).
if [[ ! -L "$CLAUDE_DIR/settings.json" && -e "$CLAUDE_DIR/settings.json" ]]; then
  info "skip (real settings.json exists — the repo's permission rules are NOT active until you merge $REPO_DIR/settings.json into it)"
else
  link "$REPO_DIR/settings.json" "$CLAUDE_DIR/settings.json"
fi

say ""
say "agents:"
found=0
for agent in "$REPO_DIR"/agents/*.md; do
  found=1
  link "$agent" "$CLAUDE_DIR/agents/$(basename "$agent")"
done
if [[ $found -eq 0 ]]; then info "(none in repo yet)"; fi

say ""
say "skills:"
found=0
for skill in "$REPO_DIR"/skills/*/; do
  found=1
  name="$(basename "$skill")"
  link "${skill%/}" "$CLAUDE_DIR/skills/$name"
done
if [[ $found -eq 0 ]]; then info "(none in repo yet)"; fi

say ""
say "Done. Restart Claude Code to pick up changes."
