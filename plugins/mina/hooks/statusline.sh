#!/usr/bin/env bash
# statusline.sh — Claude Code statusline that displays cost + logs tokens per OpenSpec change
#
# Behavior:
#   1. Reads JSON from stdin (provided by Claude Code after each assistant message)
#   2. Reads .mina/state.json (written by /jira-to-spec and /spec-to-plan) to know
#      which change/phase is active
#   3. Appends one JSONL line to .mina/tokens/<change>.jsonl (or _session-<id>.jsonl if no change)
#   4. Prints a compact statusline:
#        🤖 opus | 💰 $0.23 sess | 🧠 45% ctx | 📝 feat-add-dashboard-ssr
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

# Newer Claude Code versions provide token counts; older might not
INPUT_TOKENS=$(get_num '.cost.total_input_tokens')
OUTPUT_TOKENS=$(get_num '.cost.total_output_tokens')
CACHE_READ=$(get_num '.cost.total_cache_read_input_tokens')
CACHE_CREATE=$(get_num '.cost.total_cache_creation_input_tokens')

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

  # Each line is delta-from-last-known total. To avoid double-counting, store
  # cumulative cost in a sidecar file per session and compute delta on each call.
  LAST_FILE="$TOKENS_DIR/.last-cost-$(echo "$SESSION_ID" | cut -c1-8)"
  LAST_COST=0
  LAST_INPUT=0
  LAST_OUTPUT=0
  if [ -f "$LAST_FILE" ]; then
    LAST_COST=$(jq -r '.cost // 0'   "$LAST_FILE" 2>/dev/null || echo 0)
    LAST_INPUT=$(jq -r '.input // 0'  "$LAST_FILE" 2>/dev/null || echo 0)
    LAST_OUTPUT=$(jq -r '.output // 0' "$LAST_FILE" 2>/dev/null || echo 0)
  fi

  # Compute deltas
  DELTA_COST=$(awk "BEGIN {print $TOTAL_COST - $LAST_COST}")
  DELTA_INPUT=$((INPUT_TOKENS - LAST_INPUT))
  DELTA_OUTPUT=$((OUTPUT_TOKENS - LAST_OUTPUT))

  # Only log if there's actually new activity
  POSITIVE_DELTA=$(awk "BEGIN {print ($DELTA_COST > 0) ? 1 : 0}")
  if [ "$POSITIVE_DELTA" = "1" ]; then
    TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq -n \
      --arg ts "$TS" \
      --arg model "$MODEL_NAME" \
      --arg session "$SESSION_ID" \
      --arg change "$ACTIVE_CHANGE" \
      --arg phase "$ACTIVE_PHASE" \
      --arg jira "$JIRA_KEY" \
      --argjson input "$DELTA_INPUT" \
      --argjson output "$DELTA_OUTPUT" \
      --argjson cache_read "$CACHE_READ" \
      --argjson cache_create "$CACHE_CREATE" \
      --argjson cost "$DELTA_COST" \
      '{ts:$ts, model:$model, session:$session, change:$change, phase:$phase, jira_key:$jira, input:$input, output:$output, cache_read:$cache_read, cache_create:$cache_create, cost_usd:$cost}' \
      >> "$LOG_FILE" 2>/dev/null
  fi

  # Update last-known-cumulative for next delta calculation
  jq -n \
    --argjson cost "$TOTAL_COST" \
    --argjson input "$INPUT_TOKENS" \
    --argjson output "$OUTPUT_TOKENS" \
    '{cost:$cost, input:$input, output:$output}' \
    > "$LAST_FILE" 2>/dev/null
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

  # Task progress: prefer GSD plans if phase active, else OpenSpec tasks
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
  elif [ -f "$PROJ_DIR/openspec/changes/$ACTIVE_CHANGE/tasks.md" ]; then
    OS_TOTAL=$(grep -c '^- \[' "$PROJ_DIR/openspec/changes/$ACTIVE_CHANGE/tasks.md" 2>/dev/null)
    OS_DONE=$(grep -c '^- \[x\]' "$PROJ_DIR/openspec/changes/$ACTIVE_CHANGE/tasks.md" 2>/dev/null)
    [ "$OS_TOTAL" -gt 0 ] && OUT="$OUT ${DIM}·${RESET} ${OS_DONE}/${OS_TOTAL} tasks"
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
