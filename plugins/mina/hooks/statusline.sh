#!/usr/bin/env bash
# statusline.sh — Claude Code statusline that displays cost + logs tokens per OpenSpec change
#
# Behavior:
#   1. Reads JSON from stdin (provided by Claude Code after each assistant message)
#   2. Reads .mina/state.json (written by /jira-to-spec and /spec-to-plan) to know
#      which change/phase is active
#   3. Appends one JSONL line to .mina/tokens/<change>.jsonl (or _session-<id>.jsonl if no change)
#   4. Prints a compact statusline:
#        🤖 opus | 💰 $0.23 sess | 🧠 45% ctx | 📝 feat-add-dashboard-ssr · 3/4 art · 5/8 tasks
#
#      Progress segments (when an OpenSpec change is active):
#        - `N/M art`   — artifact completion from `openspec status --change <name> --json`
#                        (done count / total). Adds `!K` in red if K artifacts are blocked.
#        - `N/M tasks` — checkbox completion from openspec/changes/<change>/tasks.md
#                        (counts nested sub-tasks too).
#
# Install:
#   Add to ~/.claude/settings.json or project .claude/settings.json:
#     {
#       "statusLine": {
#         "type": "command",
#         "command": "${CLAUDE_PLUGIN_ROOT}/hooks/statusline.sh",
#         "padding": 0
#       }
#     }
#
# Requires: jq, bash 4+
#
# Failure mode: NEVER blocks Claude. If jq is missing or input is malformed,
# print empty line and exit 0.

set +e  # never fail loud — statusline must be robust

# Read all of stdin
INPUT=$(cat 2>/dev/null || echo "{}")

# Bail if jq is missing
if ! command -v jq >/dev/null 2>&1; then
  echo ""
  exit 0
fi

# Helpers — extract field with default, never throw
get()        { echo "$INPUT" | jq -r "$1 // \"\"" 2>/dev/null; }
get_num()    { echo "$INPUT" | jq -r "$1 // 0"    2>/dev/null; }

SESSION_ID=$(get '.session_id')
CWD=$(get '.cwd')
MODEL_NAME=$(get '.model.display_name')
[ -z "$MODEL_NAME" ] && MODEL_NAME=$(get '.model.id')
TOTAL_COST=$(get_num '.cost.total_cost_usd')
TRANSCRIPT=$(get '.transcript_path')

# Token counts: Claude Code's statusline stdin does NOT include token fields
# (only .cost.total_cost_usd is provided). Read per-turn usage from the
# transcript JSONL instead — each assistant line has .message.usage with
# per-message input/output/cache figures. Tail-bounded so cost stays O(1)
# per assistant message on long sessions.
INPUT_TOKENS=0
OUTPUT_TOKENS=0
CACHE_READ=0
CACHE_CREATE=0
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  USAGE_LINE=$(tail -200 "$TRANSCRIPT" 2>/dev/null \
    | jq -c 'select(.type=="assistant" and .message.usage != null) | .message.usage' 2>/dev/null \
    | tail -1)
  if [ -n "$USAGE_LINE" ]; then
    INPUT_TOKENS=$(echo  "$USAGE_LINE" | jq -r '.input_tokens                // 0' 2>/dev/null)
    OUTPUT_TOKENS=$(echo "$USAGE_LINE" | jq -r '.output_tokens               // 0' 2>/dev/null)
    CACHE_READ=$(echo    "$USAGE_LINE" | jq -r '.cache_read_input_tokens     // 0' 2>/dev/null)
    CACHE_CREATE=$(echo  "$USAGE_LINE" | jq -r '.cache_creation_input_tokens // 0' 2>/dev/null)
  fi
fi

# Context fill — estimated from transcript size if not provided directly
CONTEXT_PCT=$(get_num '.context.fill_percent')
EXCEEDS_200K=$(get '.exceeds_200k_tokens')

# ── Project dir detection ───────────────────────────────────────────
# CWD from stdin is most reliable. Fallback to PWD.
PROJ_DIR="${CWD:-$PWD}"

# ── Active change detection ─────────────────────────────────────────
STATE_JSON="$PROJ_DIR/.mina/state.json"
ACTIVE_CHANGE=""
ACTIVE_PHASE=""
ACTIVE_PLAN=""
JIRA_KEY=""
if [ -f "$STATE_JSON" ]; then
  # New schema (v1.3+): nested under .active
  ACTIVE_CHANGE=$(jq -r '.active.change // ""' "$STATE_JSON" 2>/dev/null)
  ACTIVE_PHASE=$(jq -r '.active.phase // ""'   "$STATE_JSON" 2>/dev/null)
  ACTIVE_PLAN=$(jq -r '.active.plan // ""'     "$STATE_JSON" 2>/dev/null)
  JIRA_KEY=$(jq -r '.active.jira_key // ""'    "$STATE_JSON" 2>/dev/null)
fi

# ── Log token usage to per-change JSONL ─────────────────────────────
# Only log if cost or token info is non-zero (avoid spamming empty events)
if [ "${TOTAL_COST}" != "0" ] && [ "${TOTAL_COST}" != "" ]; then
  TOKENS_DIR="$PROJ_DIR/.mina/tokens"
  mkdir -p "$TOKENS_DIR" 2>/dev/null

  if [ -n "$ACTIVE_CHANGE" ]; then
    LOG_FILE="$TOKENS_DIR/$ACTIVE_CHANGE.jsonl"
  else
    SHORT_ID=$(echo "$SESSION_ID" | cut -c1-8)
    LOG_FILE="$TOKENS_DIR/_session-$SHORT_ID.jsonl"
  fi

  # Cost is cumulative session total → compute delta against sidecar.
  # Tokens are already per-turn (read from .message.usage of the latest
  # assistant transcript line), so log directly — no subtraction.
  LAST_FILE="$TOKENS_DIR/.last-cost-$(echo "$SESSION_ID" | cut -c1-8)"
  LAST_COST=0
  if [ -f "$LAST_FILE" ]; then
    LAST_COST=$(jq -r '.cost // 0' "$LAST_FILE" 2>/dev/null || echo 0)
  fi

  DELTA_COST=$(awk "BEGIN {print $TOTAL_COST - $LAST_COST}")

  # Log if cost moved OR tokens for this turn are non-zero (handles the case
  # where Claude Code reports a flat cost on a cached turn but tokens still flowed).
  POSITIVE_DELTA=$(awk "BEGIN {print ($DELTA_COST > 0) ? 1 : 0}")
  HAS_TOKENS=0
  [ "$INPUT_TOKENS" -gt 0 ] || [ "$OUTPUT_TOKENS" -gt 0 ] && HAS_TOKENS=1

  if [ "$POSITIVE_DELTA" = "1" ] || [ "$HAS_TOKENS" = "1" ]; then
    TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq -n \
      --arg ts "$TS" \
      --arg model "$MODEL_NAME" \
      --arg session "$SESSION_ID" \
      --arg change "$ACTIVE_CHANGE" \
      --arg phase "$ACTIVE_PHASE" \
      --arg jira "$JIRA_KEY" \
      --argjson input "$INPUT_TOKENS" \
      --argjson output "$OUTPUT_TOKENS" \
      --argjson cache_read "$CACHE_READ" \
      --argjson cache_create "$CACHE_CREATE" \
      --argjson cost "$DELTA_COST" \
      '{ts:$ts, model:$model, session:$session, change:$change, phase:$phase, jira_key:$jira, input:$input, output:$output, cache_read:$cache_read, cache_create:$cache_create, cost_usd:$cost}' \
      >> "$LOG_FILE" 2>/dev/null
  fi

  # Update last-known-cumulative cost for next delta calculation.
  # Tokens are per-turn so no need to persist them.
  jq -n --argjson cost "$TOTAL_COST" '{cost:$cost}' > "$LAST_FILE" 2>/dev/null
fi

# ── Model routing check ─────────────────────────────────────────────
# Read model-routing.json if present; flag if active model differs from
# recommended tier (recorded by /model-route or /model-switch).
ROUTING_FILE="$PROJ_DIR/model-routing.json"
RECOMMENDED_MODEL=""
COST_CAP=""
ROUTING_WARN=""

if [ -f "$ROUTING_FILE" ]; then
  COST_CAP=$(jq -r '.cost_cap_usd // empty' "$ROUTING_FILE" 2>/dev/null)
  # If current.json has a recorded recommendation, use it
  if [ -f "$STATE_JSON" ]; then
    RECOMMENDED_MODEL=$(jq -r '.active.recommended_model // ""' "$STATE_JSON" 2>/dev/null)
  fi
fi

# Compute cost spent on active change, compare to cap
COST_ON_CHANGE=0
if [ -n "$ACTIVE_CHANGE" ] && [ -f "$PROJ_DIR/.mina/tokens/$ACTIVE_CHANGE.jsonl" ]; then
  COST_ON_CHANGE=$(jq -s 'map(.cost_usd // 0) | add // 0' "$PROJ_DIR/.mina/tokens/$ACTIVE_CHANGE.jsonl" 2>/dev/null)
fi

# Flag if cost cap exceeded
if [ -n "$COST_CAP" ] && [ "$COST_CAP" != "null" ] && [ "$COST_CAP" != "0" ]; then
  OVER_CAP=$(awk "BEGIN {print ($COST_ON_CHANGE > $COST_CAP) ? 1 : 0}")
  if [ "$OVER_CAP" = "1" ]; then
    ROUTING_WARN="cost-cap"
  fi
fi

# Flag if active model doesn't match recommendation
MODEL_MISMATCH=0
if [ -n "$RECOMMENDED_MODEL" ] && [ -n "$MODEL_NAME" ]; then
  # Normalize: check if MODEL_NAME contains key parts of RECOMMENDED_MODEL
  # (e.g. "opus" matches "claude-opus-4-7", "sonnet" matches "claude-sonnet-4-7")
  REC_SHORT=$(echo "$RECOMMENDED_MODEL" | grep -oE 'opus|sonnet|haiku' | head -1)
  ACT_SHORT=$(echo "$MODEL_NAME" | grep -oE -i 'opus|sonnet|haiku' | head -1 | tr A-Z a-z)
  if [ -n "$REC_SHORT" ] && [ -n "$ACT_SHORT" ] && [ "$REC_SHORT" != "$ACT_SHORT" ]; then
    MODEL_MISMATCH=1
    [ -z "$ROUTING_WARN" ] && ROUTING_WARN="model-mismatch"
  fi
fi

# ── Format statusline output ────────────────────────────────────────
# Compact: 🤖 model | 💰 $cost | 🧠 ctx% | 📝 change

# Cost formatting
COST_FMT=$(awk "BEGIN {printf \"%.2f\", $TOTAL_COST}")

# Color helpers (terminal escape codes — Claude Code's statusline supports ANSI)
GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; DIM='\033[2m'; RESET='\033[0m'

# Color for context
if [ "$EXCEEDS_200K" = "true" ]; then
  CTX_COLOR="$RED"
elif (( $(awk "BEGIN {print ($CONTEXT_PCT > 80) ? 1 : 0}") )); then
  CTX_COLOR="$YELLOW"
else
  CTX_COLOR="$GREEN"
fi

# Color for cost (warning when single session > $5)
if (( $(awk "BEGIN {print ($TOTAL_COST > 5) ? 1 : 0}") )); then
  COST_COLOR="$RED"
elif (( $(awk "BEGIN {print ($TOTAL_COST > 1) ? 1 : 0}") )); then
  COST_COLOR="$YELLOW"
else
  COST_COLOR="$GREEN"
fi

OUT="🤖 ${MODEL_NAME:-?}"
OUT="$OUT ${DIM}|${RESET} 💰 ${COST_COLOR}\$${COST_FMT}${RESET}"

if (( $(awk "BEGIN {print ($CONTEXT_PCT > 0) ? 1 : 0}") )); then
  CTX_FMT=$(awk "BEGIN {printf \"%.0f\", $CONTEXT_PCT}")
  OUT="$OUT ${DIM}|${RESET} 🧠 ${CTX_COLOR}${CTX_FMT}%${RESET}"
fi

if [ -n "$ACTIVE_CHANGE" ]; then
  TAG="$ACTIVE_CHANGE"
  [ -n "$JIRA_KEY" ] && TAG="$JIRA_KEY $ACTIVE_CHANGE"
  OUT="$OUT ${DIM}|${RESET} 📝 $TAG"

  # Task progress: prefer GSD plans if phase active, else OpenSpec status
  if [ -n "$ACTIVE_PHASE" ]; then
    PHASE_DIR=$(ls -d "$PROJ_DIR/.planning/phases/${ACTIVE_PHASE}-"* 2>/dev/null | head -1)
    if [ -n "$PHASE_DIR" ]; then
      PLANS=$(ls "$PHASE_DIR"/[0-9]*-PLAN.md 2>/dev/null)
      TOTAL_PLANS=$(echo "$PLANS" | grep -c .)
      DONE_PLANS=0
      for p in $PLANS; do
        grep -q '^- \[ \]' "$p" 2>/dev/null || DONE_PLANS=$((DONE_PLANS+1))
      done
      [ "$TOTAL_PLANS" -gt 0 ] && OUT="$OUT ${DIM}·${RESET} ${DONE_PLANS}/${TOTAL_PLANS} plans"
    fi
  else
    CHANGE_DIR="$PROJ_DIR/openspec/changes/$ACTIVE_CHANGE"
    TASKS_FILE="$CHANGE_DIR/tasks.md"

    # 1. Artifact-level progress via openspec CLI (authoritative).
    #    Cache by tasks.md mtime so we only re-invoke openspec when the change
    #    actually moved — avoids ~200-500ms per assistant message on large repos.
    if [ -d "$CHANGE_DIR" ] && command -v openspec >/dev/null 2>&1; then
      CACHE_DIR="$PROJ_DIR/.mina"
      CACHE_FILE="$CACHE_DIR/.statusline-cache-$ACTIVE_CHANGE.json"
      TASKS_MTIME=0
      [ -f "$CHANGE_DIR/tasks.md" ] && TASKS_MTIME=$(stat -f %m "$CHANGE_DIR/tasks.md" 2>/dev/null || stat -c %Y "$CHANGE_DIR/tasks.md" 2>/dev/null || echo 0)
      CACHED_MTIME=0
      [ -f "$CACHE_FILE" ] && CACHED_MTIME=$(jq -r '.mtime // 0' "$CACHE_FILE" 2>/dev/null)

      if [ "$TASKS_MTIME" -gt 0 ] && [ "$TASKS_MTIME" = "$CACHED_MTIME" ]; then
        OS_STATUS_JSON=$(jq -c '.status' "$CACHE_FILE" 2>/dev/null)
      else
        OS_STATUS_JSON=$(cd "$PROJ_DIR" && openspec status --change "$ACTIVE_CHANGE" --json 2>/dev/null)
        if [ -n "$OS_STATUS_JSON" ] && [ "$TASKS_MTIME" -gt 0 ]; then
          mkdir -p "$CACHE_DIR" 2>/dev/null
          jq -n --argjson mtime "$TASKS_MTIME" --argjson status "$OS_STATUS_JSON" \
            '{mtime:$mtime, status:$status}' > "$CACHE_FILE" 2>/dev/null
        fi
      fi

      if [ -n "$OS_STATUS_JSON" ]; then
        ART_TOTAL=$(echo "$OS_STATUS_JSON" | jq -r '.artifacts | length // 0' 2>/dev/null)
        ART_DONE=$(echo "$OS_STATUS_JSON"  | jq -r '[.artifacts[]? | select(.status=="done")]    | length // 0' 2>/dev/null)
        ART_BLOCKED=$(echo "$OS_STATUS_JSON" | jq -r '[.artifacts[]? | select(.status=="blocked")] | length // 0' 2>/dev/null)
        if [ "${ART_TOTAL:-0}" -gt 0 ]; then
          OUT="$OUT ${DIM}·${RESET} ${ART_DONE}/${ART_TOTAL} art"
          [ "${ART_BLOCKED:-0}" -gt 0 ] && OUT="$OUT ${RED}!${ART_BLOCKED}${RESET}"
        fi
      fi
    fi

    # 2. Task-level progress from tasks.md (counts nested checkboxes too)
    if [ -f "$TASKS_FILE" ]; then
      OS_TOTAL=$(grep -cE '^[[:space:]]*- \[[ xX-]\]' "$TASKS_FILE" 2>/dev/null)
      OS_DONE=$(grep  -cE '^[[:space:]]*- \[[xX]\]'   "$TASKS_FILE" 2>/dev/null)
      [ "${OS_TOTAL:-0}" -gt 0 ] && OUT="$OUT ${DIM}·${RESET} ${OS_DONE}/${OS_TOTAL} tasks"
    fi
  fi
fi

# Background processes count (alive only)
if [ -f "$STATE_JSON" ]; then
  ALIVE_COUNT=0
  for PID in $(jq -r '.background_processes[]?.pid' "$STATE_JSON" 2>/dev/null); do
    kill -0 "$PID" 2>/dev/null && ALIVE_COUNT=$((ALIVE_COUNT+1))
  done
  [ "$ALIVE_COUNT" -gt 0 ] && OUT="$OUT ${DIM}|${RESET} ⚙ ${ALIVE_COUNT}"
fi

# Routing warnings (appended last so they're visible)
if [ "$ROUTING_WARN" = "cost-cap" ]; then
  CAP_FMT=$(awk "BEGIN {printf \"%.2f\", $COST_CAP}")
  CHG_FMT=$(awk "BEGIN {printf \"%.2f\", $COST_ON_CHANGE}")
  OUT="$OUT ${RED}⚠ cap \$$CHG_FMT/\$$CAP_FMT${RESET}"
elif [ "$ROUTING_WARN" = "model-mismatch" ]; then
  OUT="$OUT ${YELLOW}↪ try $REC_SHORT${RESET}"
fi

printf "%b\n" "$OUT"
