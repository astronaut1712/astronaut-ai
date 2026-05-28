---
description: Detect and install runtime dependencies (openspec, gsd, superpowers, graphify-rs, acli, jq) and scaffold openspec/
argument-hint: [--yes] [--skip=openspec,acli,...]
---

# Initialize project dependencies

`mina` is glue — the engines (OpenSpec, GSD, Superpowers, acli, jq, graphify-rs) ship separately. This command audits what's present, prompts for what's missing, and runs `openspec init` if the project has no `openspec/` directory yet.

**Safety contract:**
- Read-only detection by default. Every install requires explicit confirmation (or `--yes` to batch).
- Each dep is installed via its own canonical command — no curl-piped scripts, no sudo, no implicit global writes.
- `--skip=<name,name>` opts out of a dep entirely (e.g. team standardizes on Superpowers, never installs GSD).
- Re-runnable. Idempotent on already-installed deps (prints `✓ present`).

## Step 1 — Parse flags

```bash
AUTO_YES=0
SKIP=""
for arg in $ARGUMENTS; do
  case "$arg" in
    --yes|-y) AUTO_YES=1 ;;
    --skip=*) SKIP="${arg#--skip=}" ;;
  esac
done
should_skip() { echo "$SKIP" | tr ',' '\n' | grep -qx "$1"; }
```

## Step 2 — Detect platform

Install commands branch on macOS (brew) vs Linux (apt/cargo). Detect once:

```bash
OS="$(uname -s)"          # Darwin | Linux
HAS_BREW=0; command -v brew >/dev/null 2>&1 && HAS_BREW=1
HAS_APT=0;  command -v apt-get >/dev/null 2>&1 && HAS_APT=1
HAS_CARGO=0; command -v cargo >/dev/null 2>&1 && HAS_CARGO=1
HAS_NPM=0;   command -v npm  >/dev/null 2>&1 && HAS_NPM=1
HAS_NPX=0;   command -v npx  >/dev/null 2>&1 && HAS_NPX=1
```

If neither `npm` nor `npx` is on PATH, halt early — most deps need Node:

```bash
if [ "$HAS_NPM" = "0" ] && [ "$HAS_NPX" = "0" ]; then
  echo "✗ Neither npm nor npx found. Install Node first (https://nodejs.org or 'brew install node')."
  echo "  Skipping Node-based deps. Re-run /mina:init after Node is on PATH."
fi
```

## Step 3 — Detect each dep

For each, print one row of a status table. Use `command -v` (cheap, POSIX) and read version where the tool supports it.

```bash
printf "%-14s %-10s %s\n" "DEP" "STATUS" "VERSION"
printf "%-14s %-10s %s\n" "---" "------" "-------"

check() {
  local name="$1" cmd="$2" ver_cmd="$3"
  if should_skip "$name"; then
    printf "%-14s %-10s %s\n" "$name" "skip" "(--skip)"
    return 2
  fi
  if command -v "$cmd" >/dev/null 2>&1; then
    local v="$(eval "$ver_cmd" 2>/dev/null | head -1)"
    printf "%-14s %-10s %s\n" "$name" "✓ present" "${v:-unknown}"
    return 0
  fi
  printf "%-14s %-10s %s\n" "$name" "✗ missing" "—"
  return 1
}

check jq         jq          'jq --version'
JQ_MISSING=$?
check openspec   openspec    'openspec --version'
OPENSPEC_MISSING=$?
check gsd        npx         'echo "npx-based (no install needed)"'   # validated via npx existence
GSD_MISSING=$?
check graphify   graphify    'graphify --version'
GRAPHIFY_MISSING=$?
check acli       acli        'acli --version'
ACLI_MISSING=$?
```

Superpowers is a Claude Code plugin, not a CLI — detect by looking for its install path:

```bash
SP_MISSING=1
if should_skip superpowers; then
  printf "%-14s %-10s %s\n" "superpowers" "skip" "(--skip)"
  SP_MISSING=2
elif [ -d "$HOME/.claude/plugins/superpowers" ] || [ -d "./.claude/plugins/superpowers" ]; then
  printf "%-14s %-10s %s\n" "superpowers" "✓ present" "(plugin dir found)"
  SP_MISSING=0
else
  printf "%-14s %-10s %s\n" "superpowers" "✗ missing" "—"
fi
```

## Step 4 — Per-dep install (each gated by confirm)

Print one block per missing dep with the exact command and ask. `$AUTO_YES = 1` skips the prompt.

```bash
ask() {
  [ "$AUTO_YES" = "1" ] && return 0
  printf "  Install? [y/N] "; read -r r
  case "$r" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
```

### jq

```bash
if [ "$JQ_MISSING" = "1" ]; then
  echo
  echo "→ jq (statusline + state-write requires it)"
  if [ "$HAS_BREW" = "1" ]; then echo "  brew install jq"
  elif [ "$HAS_APT" = "1" ]; then echo "  sudo apt-get install -y jq"
  else echo "  See https://stedolan.github.io/jq/download/"; fi
  if ask; then
    if [ "$HAS_BREW" = "1" ]; then brew install jq
    elif [ "$HAS_APT" = "1" ]; then sudo apt-get install -y jq
    else echo "  (no supported package manager — install manually)"; fi
  fi
fi
```

### openspec

```bash
if [ "$OPENSPEC_MISSING" = "1" ] && [ "$HAS_NPM" = "1" ]; then
  echo
  echo "→ openspec (required — spec scaffolding engine)"
  echo "  npm install -g @fission-ai/openspec"
  if ask; then npm install -g @fission-ai/openspec; fi
fi
```

### GSD (no install — just verify npx + warn if `--yes` was set without intent to use)

```bash
if [ "$GSD_MISSING" = "1" ] && ! should_skip gsd; then
  echo
  echo "→ gsd (run via npx — no global install)"
  echo "  Usage: npx @opengsd/get-shit-done-redux@latest"
  echo "  (Skipping — npx will fetch on first /gsd-* call.)"
fi
```

### Superpowers (Claude Code plugin)

```bash
if [ "$SP_MISSING" = "1" ]; then
  echo
  echo "→ superpowers (Claude Code plugin — alternative to GSD for execution)"
  echo "  In Claude Code: /plugin install superpowers@superpowers-marketplace"
  echo "  (Not auto-installable from shell — run the slash command in Claude Code.)"
fi
```

### graphify-rs

```bash
if [ "$GRAPHIFY_MISSING" = "1" ]; then
  echo
  echo "→ graphify-rs (knowledge graph CLI)"
  if [ "$HAS_CARGO" = "1" ]; then echo "  cargo install graphify-rs"
  else echo "  Requires Rust toolchain. Install rustup first: https://rustup.rs"; fi
  if ask && [ "$HAS_CARGO" = "1" ]; then cargo install graphify-rs; fi
fi
```

### acli (Atlassian CLI fallback)

```bash
if [ "$ACLI_MISSING" = "1" ]; then
  echo
  echo "→ acli (Atlassian CLI — fallback for Jira ops when MCP is down)"
  if [ "$OS" = "Darwin" ] && [ "$HAS_BREW" = "1" ]; then
    echo "  brew install --cask acli"
    if ask; then brew install --cask acli; fi
  else
    echo "  See https://developer.atlassian.com/cloud/acli/guides/install/"
  fi
fi
```

## Step 5 — Scaffold `openspec/` if absent

Run `openspec init` only when (a) the CLI exists and (b) no `openspec/` directory yet. Initialization writes to the project — confirm first.

```bash
if command -v openspec >/dev/null 2>&1 && [ ! -d "openspec" ]; then
  echo
  echo "→ No openspec/ directory found in this project."
  echo "  About to run: openspec init"
  if ask; then
    openspec init
  fi
fi
```

If `openspec/` already exists, print `✓ openspec/ already initialized` and skip.

## Step 6 — Print env reminders (no auto-write)

```
Next steps (manual — these touch credentials):

  export ATLASSIAN_AUTH=$(echo -n "email@company.com:api-token" | base64)
  cp templates/mcp.json.example .mcp.json
  cat templates/CLAUDE.md.snippet >> CLAUDE.md

For statusline + cost tracking:
  cp templates/settings.json.example ~/.claude/settings.json
```

Detect what's already present and trim the list — e.g. skip the `mcp.json` line if `.mcp.json` already exists, skip the `CLAUDE.md` line if the snippet's marker is already grepped in `CLAUDE.md`.

```bash
NEEDS=()
[ -z "${ATLASSIAN_AUTH:-}" ] && NEEDS+=("ATLASSIAN_AUTH env var")
[ ! -f ".mcp.json" ] && NEEDS+=(".mcp.json (copy from templates/mcp.json.example)")
if [ -f CLAUDE.md ] && ! grep -q "Spec-driven workflow" CLAUDE.md 2>/dev/null; then
  NEEDS+=("Spec-driven snippet appended to CLAUDE.md")
fi
[ "${#NEEDS[@]}" -gt 0 ] && { echo; echo "Still TODO:"; printf "  • %s\n" "${NEEDS[@]}"; }
```

## Step 7 — Summary

Print a final compact line per dep so the user can re-verify at a glance, plus suggested next command:

```
Summary
  jq          ✓
  openspec    ✓  (initialized openspec/)
  gsd         ✓  (npx-on-demand)
  superpowers ✗  install via /plugin in Claude Code
  graphify    ✓
  acli        ✓

Next: /mina:jira-pick   (or /mina:status to see what's already active)
```

## Watchouts

- **Never run installers without confirm.** Even `brew install` writes to the system; the `ask` gate is non-negotiable. `--yes` is opt-in and surfaces in the summary line.
- **Don't curl-pipe.** No `curl … | sh` for any dep. Users on locked-down corp boxes reject those instantly and the install fails silently.
- **No sudo unless apt requires it.** `brew install` should never be `sudo brew install` — it corrupts the prefix.
- **Skip Superpowers auto-install.** It's a Claude Code plugin; only the in-CC `/plugin install` flow can register it. Shell can't reach the marketplace.
- **`openspec init` is one-shot.** Don't re-run if `openspec/` exists — it will overwrite the AGENTS.md template the user may have customized.
- **`--skip` is per-run.** No persistence — re-running `/mina:init` will re-detect skipped deps. If a user wants permanent skip, document in project `CLAUDE.md`.
- **No state.json write.** This command intentionally does not touch `.mina/state.json`. Init is project-level, state is workflow-level — keep them decoupled.
