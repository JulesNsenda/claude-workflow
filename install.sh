#!/usr/bin/env bash
#
# install.sh — symlink this repo's Claude Code config into ~/.claude
#
# Links:
#   ~/.claude/CLAUDE.md          -> <repo>/CLAUDE.md
#   ~/.claude/skills/<name>      -> <repo>/skills/<name>   (one link per skill dir)
#
# Safe to re-run. Any existing REAL file/dir at a target is backed up to
# "<target>.backup.<timestamp>" before the symlink is created. Existing symlinks
# are replaced in place (they hold no data).
#
# Usage:
#   ./install.sh            # link everything
#   ./install.sh --dry-run  # show what would happen, change nothing

set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

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

say "claude-workflow installer"
say "  repo:   $REPO_DIR"
say "  target: $CLAUDE_DIR"
[[ $DRY_RUN -eq 1 ]] && say "  (dry run — no changes)"
say ""

mkdir -p "$CLAUDE_DIR/skills"

say "CLAUDE.md:"
link "$REPO_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"

say ""
say "skills:"
shopt -s nullglob
found=0
for skill in "$REPO_DIR"/skills/*/; do
  found=1
  name="$(basename "$skill")"
  link "${skill%/}" "$CLAUDE_DIR/skills/$name"
done
[[ $found -eq 0 ]] && info "(none in repo yet)"

say ""
say "Done. Restart Claude Code to pick up changes."
