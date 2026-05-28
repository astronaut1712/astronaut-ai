---
description: Read-only health check — deps, state integrity, env, statusline hook, openspec validity
argument-hint: [--verbose] [--json]
---

# Doctor — verify install health

Read-only counterpart to `/mina:init`. Never mutates state, never installs. Prints `✓ pass | ⚠ warn | ✗ fail` per check, then a summary line. Exits non-zero if any `✗ fail` is recorded so it can be wired into CI / pre-commit if a team wants to.

Run after `/mina:init` to confirm everything is wired. Re-run any time the statusline goes weird, a slash command misbehaves, or `state.json` looks off.

## Step 1 — Parse flags

```bash
VERBOSE=0; JSON=0
for arg in $ARGUMENTS; do
  case "$arg" in
    --verbose|-v) VERBOSE=1 ;;
    --json) JSON=1 ;;
  esac
done

PASS=0; WARN=0; FAIL=0
RESULTS=()

record() {
  # record <status> <name> <message>  — status ∈ pass|warn|fail
  RESULTS+=("$1|$2|$3")
  case "$1" in pass) PASS=$((PASS+1)) ;; warn) WARN=$((WARN+1)) ;; fail) FAIL=$((FAIL+1)) ;; esac
}
```

## Step 2 — Dependency presence

Mirror the `/mina:init` detection list. `pass` if present, `warn` if optional and missing, `fail` if required and missing.

```bash
check_required() {
  local name="$1" cmd="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    local v="$($cmd --version 2>/dev/null | head -1)"
    record pass "$name" "${v:-present}"
  else
    record fail "$name" "missing — required (run /mina:init)"
  fi
}

check_optional() {
  local name="$1" cmd="$2" reason="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    local v="$($cmd --version 2>/dev/null | head -1)"
    record pass "$name" "${v:-present}"
  else
    record warn "$name" "missing — $reason"
  fi
}

check_required jq       jq
check_required openspec openspec
check_optional gsd      npx        "npx-fetched on demand; install Node if absent"
check_optional graphify graphify   "needed only for /graphify knowledge-graph flow"
check_optional acli     acli       "needed only when Atlassian MCP is down"
```

Superpowers (Claude Code plugin — no CLI):

```bash
if [ -d "$HOME/.claude/plugins/superpowers" ] || [ -d "./.claude/plugins/superpowers" ]; then
  record pass superpowers "plugin dir found"
else
  record warn superpowers "missing — install via /plugin in Claude Code (one of GSD or Superpowers required)"
fi
```

## Step 3 — State integrity

`.mina/state.json` is optional (only present after first `/jira-to-spec`). If present, must parse and have expected shape.

```bash
STATE=".mina/state.json"
if [ -f "$STATE" ]; then
  if ! jq -e . "$STATE" >/dev/null 2>&1; then
    record fail "state.json" "exists but is not valid JSON — restore from .mina/checkpoints/ or delete"
  else
    SV=$(jq -r '.version // "missing"' "$STATE")
    case "$SV" in
      missing) record warn "state.json" "no .version field — pre-1.3 layout? consider re-running /mina:init or migrating manually" ;;
      1.3|1.4) record pass "state.json" "schema v$SV, parses" ;;
      *)       record warn "state.json" "schema v$SV — newer than plugin expects; check CHANGELOG for migration" ;;
    esac

    # active change pointer consistency
    ACT=$(jq -r '.active.change // ""' "$STATE")
    if [ -n "$ACT" ]; then
      if [ -d "openspec/changes/$ACT" ]; then
        record pass "active change" "$ACT (openspec/changes/$ACT exists)"
      else
        record fail "active change" "$ACT — pointer set but openspec/changes/$ACT missing; run /mina:complete or /mina:resume <real-change>"
      fi
    fi
  fi
else
  record warn "state.json" "not present — expected before first /jira-to-spec; ignore if just installed"
fi
```

## Step 4 — Statusline hook

Hook lives at `~/.claude/settings.json` → `statusLine.command`. Verify the file path it points to exists and is executable.

```bash
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
  HOOK=$(jq -r '.statusLine.command // ""' "$SETTINGS" 2>/dev/null)
  if [ -z "$HOOK" ]; then
    record warn "statusline" "configured settings.json has no statusLine.command — copy from templates/settings.json.example"
  else
    # Hook command often is "bash /path/to/statusline.sh" — extract file arg
    HOOK_FILE=$(echo "$HOOK" | awk '{for(i=1;i<=NF;i++) if($i ~ /statusline\.sh$/) {print $i; exit}}')
    if [ -n "$HOOK_FILE" ] && [ ! -f "$HOOK_FILE" ]; then
      record fail "statusline" "settings.json points at $HOOK_FILE which does not exist"
    elif [ -n "$HOOK_FILE" ] && [ ! -x "$HOOK_FILE" ]; then
      record warn "statusline" "$HOOK_FILE is not executable (chmod +x to fix)"
    else
      record pass "statusline" "wired to $HOOK_FILE"
    fi
  fi
else
  record warn "statusline" "$SETTINGS not found — statusline disabled; copy from templates/settings.json.example to enable"
fi
```

## Step 5 — Env + auth

```bash
if [ -n "${ATLASSIAN_AUTH:-}" ]; then
  # Length sanity — base64 of "email:token" is typically 40-80 chars
  L=${#ATLASSIAN_AUTH}
  if [ "$L" -lt 20 ]; then
    record warn "ATLASSIAN_AUTH" "set but length=$L looks too short — should be base64 of email:api-token"
  else
    record pass "ATLASSIAN_AUTH" "set (length=$L)"
  fi
else
  record warn "ATLASSIAN_AUTH" "not set — /mina:jira-* commands will fall back to Atlassian MCP or fail"
fi

if [ -f ".mcp.json" ]; then
  if jq -e '.mcpServers.atlassian // .mcpServers["atlassian-remote"] // empty' .mcp.json >/dev/null 2>&1; then
    record pass ".mcp.json" "atlassian server configured"
  else
    record warn ".mcp.json" "present but no atlassian server entry — copy from templates/mcp.json.example"
  fi
else
  record warn ".mcp.json" "not present — copy from templates/mcp.json.example"
fi

if [ -f "CLAUDE.md" ]; then
  if grep -q "Spec-driven workflow" CLAUDE.md 2>/dev/null; then
    record pass "CLAUDE.md" "spec-driven snippet appended"
  else
    record warn "CLAUDE.md" "exists but snippet missing — cat templates/CLAUDE.md.snippet >> CLAUDE.md"
  fi
else
  record warn "CLAUDE.md" "not present — Claude Code projects should have one; cat templates/CLAUDE.md.snippet > CLAUDE.md"
fi
```

## Step 6 — OpenSpec validity

If `openspec/` exists and the CLI is on PATH, run `openspec validate` quickly and surface any structural problems. Skip silently if either is absent (already recorded in earlier steps).

```bash
if [ -d "openspec" ] && command -v openspec >/dev/null 2>&1; then
  if openspec validate >/dev/null 2>&1; then
    CHANGES=$(ls openspec/changes 2>/dev/null | wc -l | tr -d ' ')
    record pass "openspec/" "validates clean ($CHANGES change(s))"
  else
    record fail "openspec/" "openspec validate failed — run 'openspec validate' for details"
  fi
elif [ -d "openspec" ] && ! command -v openspec >/dev/null 2>&1; then
  record warn "openspec/" "directory exists but openspec CLI missing — install via /mina:init"
fi
```

## Step 7 — Token log writability

The statusline appends one JSONL line per assistant message to `.mina/tokens/`. If the dir is read-only, the statusline degrades silently and the user never sees their cost.

```bash
TOKEN_DIR=".mina/tokens"
if [ -d "$TOKEN_DIR" ]; then
  if [ -w "$TOKEN_DIR" ]; then
    record pass "tokens dir" "$TOKEN_DIR writable"
  else
    record fail "tokens dir" "$TOKEN_DIR not writable — chown/chmod to fix"
  fi
elif [ -d ".mina" ]; then
  if [ -w ".mina" ]; then
    record pass "tokens dir" "will be created on first message (.mina is writable)"
  else
    record fail "tokens dir" ".mina exists but not writable — statusline will silently fail to log"
  fi
fi
```

## Step 8 — Render results

If `--json`, emit one object per check + summary. Otherwise pretty-print.

```bash
if [ "$JSON" = "1" ]; then
  printf '['
  first=1
  for r in "${RESULTS[@]}"; do
    IFS='|' read -r st nm msg <<< "$r"
    [ "$first" = "1" ] || printf ','
    first=0
    printf '{"status":"%s","check":"%s","message":"%s"}' "$st" "$nm" "$(echo "$msg" | sed 's/"/\\"/g')"
  done
  printf '],{"summary":{"pass":%d,"warn":%d,"fail":%d}}\n' "$PASS" "$WARN" "$FAIL"
else
  echo
  printf "%-20s  %s\n" "CHECK" "RESULT"
  printf "%-20s  %s\n" "-----" "------"
  for r in "${RESULTS[@]}"; do
    IFS='|' read -r st nm msg <<< "$r"
    case "$st" in
      pass) icon="✓" ;;
      warn) icon="⚠" ;;
      fail) icon="✗" ;;
    esac
    printf "%-20s  %s %s\n" "$nm" "$icon" "$msg"
  done
  echo
  echo "Summary: $PASS pass · $WARN warn · $FAIL fail"
  if [ "$FAIL" -gt 0 ]; then
    echo
    echo "Action: run /mina:init for missing deps, or read the fail lines above for specific fixes."
  fi
fi

[ "$FAIL" -gt 0 ] && exit 1
exit 0
```

## Sample output

```
CHECK                 RESULT
-----                 ------
jq                    ✓ jq-1.7.1
openspec              ✓ 0.14.2
gsd                   ✓ npx 10.8.2
graphify              ⚠ missing — needed only for /graphify knowledge-graph flow
acli                  ✓ 1.0.0
superpowers           ✓ plugin dir found
state.json            ✓ schema v1.3, parses
active change         ✓ feat-add-dashboard-ssr (openspec/changes/feat-add-dashboard-ssr exists)
statusline            ✓ wired to /Users/me/.claude/plugins/mina/hooks/statusline.sh
ATLASSIAN_AUTH        ✓ set (length=68)
.mcp.json             ✓ atlassian server configured
CLAUDE.md             ✓ spec-driven snippet appended
openspec/             ✓ validates clean (1 change(s))
tokens dir            ✓ .mina/tokens writable

Summary: 13 pass · 1 warn · 0 fail
```

## Watchouts

- **Read-only contract.** Doctor never writes, installs, transitions, or touches `.mina/state.json`. If a check needs a fix, surface it — do not auto-apply.
- **Exit code is contract.** `0` = no fails (warns OK). `1` = at least one fail. Wire into CI as `mina:doctor || exit 1`.
- **`--json` shape is stable.** Two top-level objects: results array + summary. Don't restructure without bumping plugin minor; downstream scripts may consume.
- **Don't double-print on warns.** Doctor reports state; `/mina:init` fixes it. Sending users to `init` once at the end is enough — do not append fix instructions per warning row (noise).
- **No network calls.** Detection is local (`command -v`, file checks, jq parse). Network is `/mina:init`'s job, not doctor's. Doctor must run offline.
- **Statusline hook check is best-effort.** Settings.json layout differs across users (`statusLine.command` vs older `statusLineCommand`); if extraction fails, record a `warn` with a pointer to the example, not a `fail`.
