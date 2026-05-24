#!/usr/bin/env bash
# astronaut-ai installer — multi-tool
#
# Supported targets:
#   claude-code  →  .claude/{skills,commands}/                (native frontmatter)
#   opencode     →  .opencode/{skills,command}/               (native frontmatter)
#   codex        →  .codex/{skills,prompts}/                  (drops `tools`/`model` fm)
#   pi           →  .pi/agent/git/astronaut-ai/{skills,prompts}/ (Pi git-package layout)
#   kiro         →  .kiro/steering/                           (skills→steering; commands→reference doc)
#   kilo         →  .kilocode/rules/                          (skills→rules;     commands→reference doc)
#   all          →  every target above, project scope only
#
# For Claude Code, prefer the marketplace install instead of this script:
#   /plugin marketplace add astronaut1712/astronaut-ai
#   /plugin install mina@mina
#
# Usage:
#   ./install.sh                          # interactive picker
#   ./install.sh <target>                 # project scope (current dir)
#   ./install.sh <target> --user          # user scope (~/.<tool>/ etc.)
#   ./install.sh both                     # claude-code + opencode (legacy alias)
#   ./install.sh all                      # every supported target (project scope)
#
# Translation notes:
#   - Codex: SKILL.md frontmatter cleaned (`tools` / `model` stripped) — Codex
#     spec doesn't accept those fields. Body kept as-is.
#   - Pi: same skill/prompt convention as Codex; mina is installed as a Pi git
#     package directory under `.pi/agent/git/astronaut-ai/`. After install, run
#     `pi config` to enable.
#   - Kiro / Kilo: no native slash-command system. Skills become always-on rules
#     (semantically lossier than Claude Code's auto-trigger). Commands are
#     concatenated into a single `commands-reference.md` for human invocation.

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
dim()  { printf '\033[2m%s\033[0m\n' "$1"; }
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
  echo "  3) Codex (.codex/)"
  echo "  4) Pi (.pi/agent/git/astronaut-ai/)"
  echo "  5) Kiro (.kiro/steering/)"
  echo "  6) Kilo Code (.kilocode/rules/)"
  echo "  7) claude-code + opencode"
  echo "  8) All supported tools (project scope)"
  echo "  9) Cancel"
  read -rp "Choice [1-9]: " choice
  case "$choice" in
    1) TARGET="claude-code" ;;
    2) TARGET="opencode" ;;
    3) TARGET="codex" ;;
    4) TARGET="pi" ;;
    5) TARGET="kiro" ;;
    6) TARGET="kilo" ;;
    7) TARGET="both" ;;
    8) TARGET="all" ;;
    9) echo "Cancelled."; exit 0 ;;
    *) err "Invalid choice"; exit 1 ;;
  esac
fi

# ── Generic helpers ──────────────────────────────────────────────────

copy_with_check() {
  local src="$1" dst="$2" label="$3"
  if [ -e "$dst" ]; then
    warn "Exists, skipping: $label (delete to reinstall)"
  else
    if [ -d "$src" ]; then cp -r "$src" "$dst"
    else                   cp    "$src" "$dst"
    fi
    ok "$label"
  fi
}

# Strip YAML frontmatter (`---` … `---` at top of file). Output to stdout.
strip_frontmatter() {
  awk 'BEGIN{in_fm=0; done=0}
       NR==1 && $0=="---" {in_fm=1; next}
       in_fm && $0=="---" {in_fm=0; done=1; next}
       in_fm {next}
       {print}' "$1"
}

# Rewrite Codex SKILL.md: drop `tools:` and `model:` lines from frontmatter,
# keep `name:` and `description:`. Body is untouched.
codex_clean_skill() {
  awk 'BEGIN{in_fm=0; fm_open=0}
       NR==1 && $0=="---" {in_fm=1; fm_open=1; print; next}
       in_fm && $0=="---" {in_fm=0; print; next}
       in_fm {
         if ($1=="tools:" || $1=="model:") next
         print; next
       }
       {print}' "$1"
}

# ── Per-tool install functions ───────────────────────────────────────

install_claude_code() {
  local base
  if [ "$SCOPE" = "user" ]; then base="$HOME/.claude"
  else                            base="$(pwd)/.claude"
  fi

  bold "Installing Claude Code components to $base"
  mkdir -p "$base/skills" "$base/commands"

  for skill_dir in "$PLUGIN_DIR/skills"/*/; do
    local skill_name="$(basename "$skill_dir")"
    copy_with_check "$skill_dir" "$base/skills/$skill_name" "Skill: $skill_name"
  done

  for cmd_file in "$PLUGIN_DIR/commands"/*.md; do
    local cmd_name="$(basename "$cmd_file")"
    copy_with_check "$cmd_file" "$base/commands/$cmd_name" "Command: /$(basename "$cmd_file" .md)"
  done
}

install_opencode() {
  local base
  if [ "$SCOPE" = "user" ]; then base="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
  else                            base="$(pwd)/.opencode"
  fi

  bold "Installing opencode components to $base"
  mkdir -p "$base/skills" "$base/command"

  for skill_dir in "$PLUGIN_DIR/skills"/*/; do
    local skill_name="$(basename "$skill_dir")"
    copy_with_check "$skill_dir" "$base/skills/$skill_name" "Skill: $skill_name"
  done

  for cmd_file in "$PLUGIN_DIR/commands"/*.md; do
    local cmd_name="$(basename "$cmd_file")"
    copy_with_check "$cmd_file" "$base/command/$cmd_name" "Command: /$(basename "$cmd_file" .md)"
  done
}

install_codex() {
  local base
  if [ "$SCOPE" = "user" ]; then base="${CODEX_HOME:-$HOME/.codex}"
  else                            base="$(pwd)/.codex"
  fi

  bold "Installing Codex CLI components to $base"
  mkdir -p "$base/skills" "$base/prompts"

  for skill_dir in "$PLUGIN_DIR/skills"/*/; do
    local skill_name="$(basename "$skill_dir")"
    local dst="$base/skills/$skill_name"
    if [ -e "$dst" ]; then
      warn "Exists, skipping: Skill: $skill_name (delete to reinstall)"
      continue
    fi
    mkdir -p "$dst"
    codex_clean_skill "$skill_dir/SKILL.md" > "$dst/SKILL.md"
    # Copy any sibling files (scripts/, references/, etc.)
    find "$skill_dir" -mindepth 1 -maxdepth 1 ! -name SKILL.md \
      -exec cp -r {} "$dst/" \; 2>/dev/null || true
    ok "Skill: $skill_name (frontmatter cleaned)"
  done

  for cmd_file in "$PLUGIN_DIR/commands"/*.md; do
    local cmd_name="$(basename "$cmd_file")"
    copy_with_check "$cmd_file" "$base/prompts/$cmd_name" "Prompt: /$(basename "$cmd_file" .md)"
  done
}

install_pi() {
  local base
  if [ "$SCOPE" = "user" ]; then base="$HOME/.pi/agent/git/astronaut-ai"
  else                            base="$(pwd)/.pi/agent/git/astronaut-ai"
  fi

  bold "Installing Pi git-package components to $base"
  mkdir -p "$base/skills" "$base/prompts"

  for skill_dir in "$PLUGIN_DIR/skills"/*/; do
    local skill_name="$(basename "$skill_dir")"
    copy_with_check "$skill_dir" "$base/skills/$skill_name" "Skill: $skill_name"
  done

  for cmd_file in "$PLUGIN_DIR/commands"/*.md; do
    local cmd_name="$(basename "$cmd_file")"
    copy_with_check "$cmd_file" "$base/prompts/$cmd_name" "Prompt: /$(basename "$cmd_file" .md)"
  done

  # Minimal Pi package manifest so `pi list` / `pi config` recognize it.
  if [ ! -f "$base/package.json" ]; then
    cat > "$base/package.json" <<'JSON'
{
  "name": "astronaut-ai",
  "description": "Spec-driven Jira → OpenSpec → GSD workflow (mina plugin) ported to Pi.",
  "keywords": ["pi-package"],
  "pi": {
    "skills": ["./skills"],
    "prompts": ["./prompts"]
  }
}
JSON
    ok "Wrote package.json (Pi manifest)"
  fi
}

# Kiro and Kilo share an install shape: stripped-frontmatter skills go into a
# single rules/steering directory, and commands collapse into one index doc.
install_flat_rules() {
  local label="$1" base="$2" rules_dir="$3" cmd_index="$4" snippet_path="$5"

  bold "Installing $label components to $base"
  mkdir -p "$base/$rules_dir"

  # Skills → individual rule files
  for skill_dir in "$PLUGIN_DIR/skills"/*/; do
    local skill_name="$(basename "$skill_dir")"
    local dst="$base/$rules_dir/$skill_name.md"
    if [ -e "$dst" ]; then
      warn "Exists, skipping: Rule: $skill_name (delete to reinstall)"
      continue
    fi
    {
      echo "# $skill_name"
      echo ""
      echo "_Always-on rule ported from the mina spec-driven workflow plugin._"
      echo ""
      strip_frontmatter "$skill_dir/SKILL.md"
    } > "$dst"
    ok "Rule: $skill_name (frontmatter stripped)"
  done

  # Commands → single concatenated reference doc
  local cmd_path="$base/$rules_dir/$cmd_index"
  if [ -e "$cmd_path" ]; then
    warn "Exists, skipping: $cmd_index (delete to reinstall)"
  else
    {
      echo "# mina command reference ($label has no native slash commands)"
      echo ""
      echo "$label doesn't expose a slash-command surface like Claude Code or Codex."
      echo "These are the workflow steps the original commands automate — invoke them"
      echo "by asking the agent in natural language, or paste the relevant block."
      echo ""
      for cmd_file in "$PLUGIN_DIR/commands"/*.md; do
        local cmd_name="$(basename "$cmd_file" .md)"
        echo "---"
        echo ""
        echo "## /$cmd_name"
        echo ""
        strip_frontmatter "$cmd_file"
        echo ""
      done
    } > "$cmd_path"
    ok "Reference: $cmd_index (all 13 commands concatenated)"
  fi

  # Snippet path is informational only — printed in post-install notes
  : "$snippet_path"
}

install_kiro() {
  local base
  if [ "$SCOPE" = "user" ]; then base="$HOME/.kiro"
  else                            base="$(pwd)/.kiro"
  fi
  install_flat_rules "Kiro" "$base" "steering" "mina-commands-reference.md" \
    "$base/steering/mina-rules.md"
}

install_kilo() {
  local base
  if [ "$SCOPE" = "user" ]; then base="$HOME/.kilocode"
  else                            base="$(pwd)/.kilocode"
  fi
  install_flat_rules "Kilo Code" "$base" "rules" "mina-commands-reference.md" \
    "$base/rules/mina-rules.md"
}

# ── Post-install notes ───────────────────────────────────────────────

show_post_install() {
  echo ""
  bold "Next steps"
  echo ""
  echo "  1. Append project rules to your agent's context file:"
  echo "       cat $SCRIPT_DIR/templates/CLAUDE.md.snippet >> <CLAUDE.md|AGENTS.md|.kiro/steering/project.md>"
  echo ""
  echo "  2. Atlassian credentials:"
  echo "       export ATLASSIAN_AUTH=\$(echo -n 'email:token' | base64)"
  echo "       cp $SCRIPT_DIR/templates/mcp.json.example .mcp.json"
  echo ""
  echo "  3. Runtime engines (plugin is glue, not the engine):"
  echo "       npm install -g @fission-ai/openspec && openspec init"
  echo "       npx @opengsd/get-shit-done-redux@latest    # if using GSD"
  echo ""
  echo "  4. Tool-specific finalization:"
  case "$TARGET" in
    claude-code|both|all)
      echo "       Claude Code:  restart, then run /help — commands appear as /<name>"
      ;;
  esac
  case "$TARGET" in
    opencode|both|all)
      echo "       opencode:     restart, /help; commands under .opencode/command/"
      ;;
  esac
  case "$TARGET" in
    codex|all)
      echo "       Codex:        restart codex; /skills lists installed skills"
      echo "                     /<name> invokes prompts from .codex/prompts/"
      ;;
  esac
  case "$TARGET" in
    pi|all)
      echo "       Pi:           run \`pi config\` to enable installed skills + prompts"
      echo "                     (alternative: \`pi install git:github.com/astronaut1712/astronaut-ai\`)"
      ;;
  esac
  case "$TARGET" in
    kiro|all)
      echo "       Kiro:         steering files load automatically. There are no"
      echo "                     slash commands — ask Kiro to follow the workflow"
      echo "                     described in .kiro/steering/mina-commands-reference.md"
      ;;
  esac
  case "$TARGET" in
    kilo|all)
      echo "       Kilo Code:    rules auto-load. No slash commands — paste from"
      echo "                     .kilocode/rules/mina-commands-reference.md as needed"
      ;;
  esac
  echo ""
  echo "  5. (Optional, Claude Code only) Enable cost-tracking statusline:"
  if ! command -v jq >/dev/null 2>&1; then
    warn "jq is NOT installed — required for statusline + token tracking"
    echo "       brew install jq          (macOS)"
    echo "       apt-get install jq       (Linux)"
  else
    ok "jq detected — statusline ready to enable"
  fi
  echo "       cp $SCRIPT_DIR/templates/settings.json.example ~/.claude/settings.json"
  echo ""
  ok "Done."
}

# ── Dispatch ─────────────────────────────────────────────────────────

case "$TARGET" in
  claude-code) install_claude_code ;;
  opencode)    install_opencode ;;
  codex)       install_codex ;;
  pi)          install_pi ;;
  kiro)        install_kiro ;;
  kilo)        install_kilo ;;
  both)        install_claude_code; echo; install_opencode ;;
  all)
    install_claude_code; echo
    install_opencode;    echo
    install_codex;       echo
    install_pi;          echo
    install_kiro;        echo
    install_kilo
    ;;
  *) err "Unknown target: $TARGET"; exit 1 ;;
esac

show_post_install
