#!/usr/bin/env bash
# Setup script — initialize git and prepare for GitHub push
#
# Usage:
#   ./setup-and-push.sh
#
# The plugin is pre-configured for github.com/astronaut1712. If you're forking
# under a different account, edit plugin.json, marketplace.json, LICENSE, and
# README.md manually (or pass --override-user <name> below).
#
# This script:
#   1. Optionally re-personalizes manifests if you pass --override-user
#   2. Initializes git (if not already)
#   3. Prints next steps for pushing to GitHub
#
# This script never runs `git push` for you — you do that step manually.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
dim()  { printf '\033[2m%s\033[0m\n' "$1"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }

OVERRIDE_USER=""
OVERRIDE_NAME=""
OVERRIDE_REPO=""
OVERRIDE_MARKETPLACE=""
for arg in "$@"; do
  case "$arg" in
    --override-user=*) OVERRIDE_USER="${arg#*=}" ;;
    --override-name=*) OVERRIDE_NAME="${arg#*=}" ;;
    --override-repo=*) OVERRIDE_REPO="${arg#*=}" ;;
    --override-marketplace=*) OVERRIDE_MARKETPLACE="${arg#*=}" ;;
  esac
done

# Defaults baked into the repo
CURRENT_USER="astronaut1712"
CURRENT_NAME="astronaut1712"
CURRENT_REPO="astronaut-ai"
CURRENT_MARKETPLACE="mina"

# Detect sed flavor (macOS vs GNU)
if sed --version >/dev/null 2>&1; then
  SED_INPLACE=(sed -i)
else
  SED_INPLACE=(sed -i '')
fi

# Optional re-personalization
if [ -n "$OVERRIDE_USER" ] || [ -n "$OVERRIDE_REPO" ] || [ -n "$OVERRIDE_NAME" ] || [ -n "$OVERRIDE_MARKETPLACE" ]; then
  NEW_USER="${OVERRIDE_USER:-$CURRENT_USER}"
  NEW_NAME="${OVERRIDE_NAME:-$NEW_USER}"
  NEW_REPO="${OVERRIDE_REPO:-$CURRENT_REPO}"
  NEW_MARKETPLACE="${OVERRIDE_MARKETPLACE:-$CURRENT_MARKETPLACE}"

  bold "Re-personalizing manifests..."
  echo "  user:        $CURRENT_USER → $NEW_USER"
  echo "  name:        $CURRENT_NAME → $NEW_NAME"
  echo "  repo:        $CURRENT_REPO → $NEW_REPO"
  echo "  marketplace: $CURRENT_MARKETPLACE → $NEW_MARKETPLACE"
  echo ""

  # Replace in all text files
  FILES_TO_UPDATE=(
    .claude-plugin/marketplace.json
    plugins/mina/.claude-plugin/plugin.json
    README.md
    LICENSE
    plugins/mina/README.md
  )
  for f in "${FILES_TO_UPDATE[@]}"; do
    [ -f "$f" ] || continue
    "${SED_INPLACE[@]}" "s|$CURRENT_USER/$CURRENT_REPO|$NEW_USER/$NEW_REPO|g" "$f"
    "${SED_INPLACE[@]}" "s|github.com/$CURRENT_USER|github.com/$NEW_USER|g" "$f"
    "${SED_INPLACE[@]}" "s|\"name\": \"$CURRENT_NAME\"|\"name\": \"$NEW_NAME\"|g" "$f"
    "${SED_INPLACE[@]}" "s|Copyright (c) 2026 $CURRENT_NAME|Copyright (c) 2026 $NEW_NAME|g" "$f"
  done

  # Marketplace name: only in marketplace.json's top-level "name" and in install commands
  "${SED_INPLACE[@]}" "s|\"name\": \"$CURRENT_MARKETPLACE\"|\"name\": \"$NEW_MARKETPLACE\"|" .claude-plugin/marketplace.json
  "${SED_INPLACE[@]}" "s|mina@$CURRENT_MARKETPLACE|mina@$NEW_MARKETPLACE|g" README.md
  "${SED_INPLACE[@]}" "s|marketplace update $CURRENT_MARKETPLACE|marketplace update $NEW_MARKETPLACE|g" README.md

  ok "Manifests re-personalized"
  GH_USER="$NEW_USER"
  REPO_NAME="$NEW_REPO"
  CURRENT_MARKETPLACE="$NEW_MARKETPLACE"
else
  GH_USER="$CURRENT_USER"
  REPO_NAME="$CURRENT_REPO"
  dim "Using baked-in defaults: github.com/$GH_USER/$REPO_NAME (marketplace: $CURRENT_MARKETPLACE)"
  dim "  (override with --override-user=foo --override-repo=bar --override-marketplace=baz)"
fi

echo ""

# Validate JSON
bold "Validating JSON..."
python3 -m json.tool plugins/mina/.claude-plugin/plugin.json > /dev/null && ok "plugin.json"
python3 -m json.tool .claude-plugin/marketplace.json > /dev/null && ok "marketplace.json"
echo ""

# Init git
if [ ! -d .git ]; then
  bold "Initializing git..."
  git init -q
  git branch -M main
  ok "Initialized empty git repo"
else
  dim "Git already initialized — skipping init"
fi

# Stage everything
git add .
ok "Staged files"
echo ""

bold "Status:"
git status --short
echo ""

bold "Next steps (run manually):"
echo ""
echo "  # 1. Review the staged changes:"
echo "  git diff --cached | head -100"
echo ""
echo "  # 2. Commit:"
echo "  git commit -m 'Initial commit: astronaut-ai (mina marketplace)'"
echo ""
echo "  # 3. Create the repo on GitHub (via gh CLI):"
echo "  gh repo create $GH_USER/$REPO_NAME --public --source=. --remote=origin --push"
echo ""
echo "  # OR if you've already created the repo on github.com:"
echo "  git remote add origin git@github.com:$GH_USER/$REPO_NAME.git"
echo "  git push -u origin main"
echo ""
echo "  # 4. (Optional) Tag the release:"
echo "  git tag v1.2.0"
echo "  git push --tags"
echo ""
echo "  # 5. Share install command with your team:"
echo "      /plugin marketplace add $GH_USER/$REPO_NAME"
echo "      /plugin install mina@$CURRENT_MARKETPLACE"
echo ""
echo "  # (Marketplace name '$CURRENT_MARKETPLACE' comes from marketplace.json,"
echo "  #  not from the repo name. They're independent.)"
echo ""
ok "Setup complete."
