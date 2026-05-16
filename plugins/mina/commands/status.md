---
description: Comprehensive status of active change, phase, plans, git, cost, processes
argument-hint: [change-name | --mini]
---

# Status

## Step 1 — Resolve scope

If `$ARGUMENTS` is empty → show status for active change (from `.mina/state.json`)
If `$ARGUMENTS = --mini` → 1-line summary, no full report
If `$ARGUMENTS` is a change name → show status for that specific change
If no `.mina/state.json` exists → say so and run inference (see Step 7)

## Step 2 — Read state

```bash
STATE=".mina/state.json"
[ -f "$STATE" ] || { echo "No .mina/state.json — run /mina:resume to initialize"; exit 0; }

CHANGE=$(jq -r '.active.change // ""' "$STATE")
PHASE=$(jq -r '.active.phase // ""' "$STATE")
PLAN=$(jq -r '.active.plan // ""' "$STATE")
JIRA=$(jq -r '.active.jira_key // ""' "$STATE")
SINCE=$(jq -r '.active.since // ""' "$STATE")
```

## Step 3 — Compute task progress

```bash
# OpenSpec tasks
if [ -f "openspec/changes/$CHANGE/tasks.md" ]; then
  OS_TOTAL=$(grep -c '^- \[' "openspec/changes/$CHANGE/tasks.md")
  OS_DONE=$(grep -c '^- \[x\]' "openspec/changes/$CHANGE/tasks.md")
fi

# GSD plans
PHASE_DIR=$(ls -d .planning/phases/${PHASE}-* 2>/dev/null | head -1)
if [ -n "$PHASE_DIR" ]; then
  PLANS=$(ls "$PHASE_DIR"/[0-9]*-PLAN.md 2>/dev/null)
  TOTAL_PLANS=$(echo "$PLANS" | wc -l)
  DONE_PLANS=0
  for p in $PLANS; do
    if ! grep -q '^- \[ \]' "$p" 2>/dev/null; then
      DONE_PLANS=$((DONE_PLANS+1))
    fi
  done
fi
```

## Step 4 — Git state

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
[ -z "$BASE_BRANCH" ] && BASE_BRANCH=main
COMMITS=$(git rev-list --count "$BASE_BRANCH..HEAD" 2>/dev/null)
MODIFIED=$(git diff --name-only | wc -l)
STAGED=$(git diff --cached --name-only | wc -l)
```

## Step 5 — Cost & model

```bash
COST=0
REQUESTS=0
LAST_TS=""
if [ -f ".mina/tokens/$CHANGE.jsonl" ]; then
  COST=$(jq -s 'map(.cost_usd // 0) | add // 0' ".mina/tokens/$CHANGE.jsonl")
  REQUESTS=$(wc -l < ".mina/tokens/$CHANGE.jsonl")
  LAST_TS=$(jq -s -r 'max_by(.ts) | .ts' ".mina/tokens/$CHANGE.jsonl")
fi

RECOMMENDED=$(jq -r '.active.recommended_model // ""' "$STATE")
```

## Step 6 — Background processes (verify alive)

```bash
ALIVE_PROCS=()
for entry in $(jq -c '.background_processes[]' "$STATE" 2>/dev/null); do
  PID=$(echo "$entry" | jq -r '.pid')
  if kill -0 "$PID" 2>/dev/null; then
    CMD=$(echo "$entry" | jq -r '.command')
    STARTED=$(echo "$entry" | jq -r '.started_at')
    ALIVE_PROCS+=("  PID $PID  $CMD  (started $STARTED)")
  fi
done
```

## Step 7 — If no active state, infer

If `state.json` doesn't exist or has empty `active`:

```bash
# Infer from openspec/changes/ most recently modified
LATEST_CHANGE=$(ls -1t openspec/changes/*/proposal.md 2>/dev/null | head -1 | xargs dirname | xargs basename)

# Infer from git branch
if [[ "$BRANCH" =~ ^(feat|fix|chore)/(.+)$ ]]; then
  BRANCH_HINT="${BASH_REMATCH[2]}"
fi

echo "No active state. Inferred candidates:"
echo "  From openspec/changes/: $LATEST_CHANGE"
echo "  From git branch:        $BRANCH_HINT"
echo "  Run /mina:resume to pick one."
```

## Step 8 — Format full report (default)

```
mina status — <human-readable date>

Active change:    <CHANGE> (<JIRA-KEY>)
                  Started <since-relative> · last activity <last-relative>

Progress:
  OpenSpec:       <OS_DONE>/<OS_TOTAL> tasks
  GSD phase:      <PHASE> (<DONE_PLANS>/<TOTAL_PLANS> plans)
    <list plans with ✓ ⧖ ○ markers based on checkbox state>

Git:
  Branch:         <BRANCH>
  Commits:        <COMMITS> since <BASE_BRANCH>
  Status:         <MODIFIED> modified, <STAGED> staged

Cost on change:   $<COST> (<REQUESTS> requests)
Active model:     (run /model to see)
Recommended:      <RECOMMENDED> (if differs; from /mina:model-route)

Background:
  <ALIVE_PROCS>
  (or "none" if empty)

Sessions:
  <list from state.json.sessions, mark active vs ended>
```

## Step 9 — Mini variant

If `--mini`:

```
📝 <JIRA> <CHANGE> · <DONE_PLANS>/<TOTAL_PLANS> plans · last <last-relative> · $<COST>
```

## Step 10 — Helpful next-step suggestions

After the report, suggest 1-3 contextual next steps:

```
Suggested next:
  /gsd-execute-phase <PHASE>          ← <DONE_PLANS>/<TOTAL_PLANS> done; continue
  /mina:checkpoint <name>             ← save state before risky change
  /mina:jira-update <CHANGE>          ← all plans done; close Jira loop
```

Pick based on actual state: if all plans done → suggest jira-update; if mid-phase → suggest execute; if many uncommitted → suggest commit.

## Watchouts

- Don't show stale data. If `last activity > 24h ago`, prefix the report with a "⚠ Stale state" warning.
- Verify `kill -0` permission — on some setups (containers), checking other users' PIDs fails. Handle gracefully.
- If `state.json` says active change X but git branch suggests change Y, surface the mismatch — don't silently trust state.
