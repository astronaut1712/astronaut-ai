#!/usr/bin/env bash
# astronaut-ai installer
#
# For Claude Code, prefer the marketplace install (no need for this script):
#   /plugin marketplace add astronaut1712/astronaut-ai
#   /plugin install mina@mina
#
# Use this script for:
#   - opencode (no plugin marketplace yet)
#   - Manual install into a project's .claude/ folder (skip namespacing)
#
# Usage:
#   ./install.sh                     # interactive
#   ./install.sh claude-code         # project scope, .claude/
#   ./install.sh opencode            # project scope, .opencode/
#   ./install.sh both
#   ./install.sh claude-code --user  # user scope (~/.claude/ or ~/.config/opencode/)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/plugins/mina"
TARGET="${1:-}"
SCOPE="project"

for arg in "$@"; do
  case "$arg" in
    --user) SCOPE="user" ;;
    --project) SCOPE="project" ;;
  esac
done

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '\033[33m⚠\033[0m %s\n' "$1"; }
err()  { printf '\033[31m✗\033[0m %s\n' "$1"; }

if [ ! -d "$PLUGIN_DIR" ]; then
  err "Plugin directory not found: $PLUGIN_DIR"
  err "Run this script from the repo root."
  exit 1
fi

if [ -z "$TARGET" ]; then
  bold "Where do you want to install?"
  echo "  1) Claude Code (.claude/)"
  echo "  2) opencode (.opencode/)"
  echo "  3) Both"
  echo "  4) Cancel"
  read -rp "Choice [1-4]: " choice
  case "$choice" in
    1) TARGET="claude-code" ;;
    2) TARGET="opencode" ;;
    3) TARGET="both" ;;
    4) echo "Cancelled."; exit 0 ;;
    *) err "Invalid choice"; exit 1 ;;
  esac
fi

copy_with_check() {
  local src="$1"
  local dst="$2"
  local label="$3"
  if [ -e "$dst" ]; then
    warn "Exists, skipping: $label (delete to reinstall)"
  else
    if [ -d "$src" ]; then
      cp -r "$src" "$dst"
    else
      cp "$src" "$dst"
    fi
    ok "$label"
  fi
}

install_claude_code() {
  local base
  if [ "$SCOPE" = "user" ]; then
    base="$HOME/.claude"
  else
    base="$(pwd)/.claude"
  fi

  bold "Installing Claude Code components to $base"
  mkdir -p "$base/skills" "$base/commands"

  for skill_dir in "$PLUGIN_DIR/skills"/*/; do
    skill_name="$(basename "$skill_dir")"
    copy_with_check "$skill_dir" "$base/skills/$skill_name" "Skill: $skill_name"
  done

  for cmd_file in "$PLUGIN_DIR/commands"/*.md; do
    cmd_name="$(basename "$cmd_file")"
    copy_with_check "$cmd_file" "$base/commands/$cmd_name" "Command: /$(basename "$cmd_file" .md)"
  done
}

install_opencode() {
  local base
  if [ "$SCOPE" = "user" ]; then
    base="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
  else
    base="$(pwd)/.opencode"
  fi

  bold "Installing opencode components to $base"
  mkdir -p "$base/skills" "$base/command"

  for skill_dir in "$PLUGIN_DIR/skills"/*/; do
    skill_name="$(basename "$skill_dir")"
    copy_with_check "$skill_dir" "$base/skills/$skill_name" "Skill: $skill_name"
  done

  for cmd_file in "$PLUGIN_DIR/commands"/*.md; do
    cmd_name="$(basename "$cmd_file")"
    copy_with_check "$cmd_file" "$base/command/$cmd_name" "Command: /$(basename "$cmd_file" .md)"
  done
}

show_post_install() {
  echo ""
  bold "Next steps"
  echo ""
  echo "  1. Append project rules to CLAUDE.md / AGENTS.md:"
  echo "       cat $SCRIPT_DIR/templates/CLAUDE.md.snippet >> CLAUDE.md"
  echo ""
  echo "  2. Set up Atlassian credentials:"
  echo "       export ATLASSIAN_AUTH=\$(echo -n 'email:token' | base64)"
  echo "       cp $SCRIPT_DIR/templates/mcp.json.example .mcp.json"
  echo ""
  echo "  3. Install runtime tools (if not already):"
  echo "       npm install -g @fission-ai/openspec && openspec init"
  echo "       npx get-shit-done-cc@latest    # if using GSD"
  echo ""
  echo "  4. (Optional) Enable cost-tracking statusline:"
  if ! command -v jq >/dev/null 2>&1; then
    warn "jq is NOT installed — required for statusline + token tracking"
    echo "       brew install jq          (macOS)"
    echo "       apt-get install jq       (Linux)"
  else
    ok "jq detected — statusline ready to enable"
  fi
  echo "       cp $SCRIPT_DIR/templates/settings.json.example ~/.claude/settings.json"
  echo ""
  echo "  5. Restart your agent, then verify:"
  echo "       /help"
  echo ""
  ok "Done."
}

case "$TARGET" in
  claude-code) install_claude_code ;;
  opencode)    install_opencode ;;
  both)        install_claude_code; echo; install_opencode ;;
  *) err "Unknown target: $TARGET"; exit 1 ;;
esac

show_post_install
