---
description: Mark the active OpenSpec change as complete and clear the statusline pointer
argument-hint: [change-name] [--no-confirm]
---

# Complete current task

Clears `.active.*` in `.mina/state.json` so the statusline stops showing the change. Appends a `completed` event to history and removes the orphan statusline cache. Code, OpenSpec files, and Jira are not touched — this command owns local workflow pointer only.

Pair with `/mina:jira-update <change>` (closes Jira loop) and `openspec archive <change>` (moves change → specs) to fully finish work.

## Step 1 — Read active state

```bash
STATE=".mina/state.json"
[ -f "$STATE" ] || { echo "No .mina/state.json — nothing active to complete."; exit 0; }

ACTIVE_CHANGE=$(jq -r '.active.change // ""'  "$STATE")
ACTIVE_PHASE=$(jq -r  '.active.phase  // ""'  "$STATE")
ACTIVE_PLAN=$(jq -r   '.active.plan   // ""'  "$STATE")
JIRA_KEY=$(jq -r      '.active.jira_key // ""' "$STATE")
SINCE=$(jq -r         '.active.since  // ""'  "$STATE")

[ -z "$ACTIVE_CHANGE" ] && { echo "No active change. Nothing to complete."; exit 0; }
```

## Step 2 — Validate argument (if given)

If `$ARGUMENTS` includes a change name (anything that isn't a flag), it must match `$ACTIVE_CHANGE`. Mismatch means the user thinks something else is active — surface and abort rather than silently clearing the wrong pointer.

```bash
ARG_CHANGE=$(echo "$ARGUMENTS" | awk '{for(i=1;i<=NF;i++) if($i !~ /^--/) {print $i; exit}}')
if [ -n "$ARG_CHANGE" ] && [ "$ARG_CHANGE" != "$ACTIVE_CHANGE" ]; then
  echo "✗ Active change is '$ACTIVE_CHANGE', not '$ARG_CHANGE'."
  echo "  /mina:complete only clears the active pointer."
  echo "  Run /mina:resume $ARG_CHANGE first if you want to switch, then complete."
  exit 1
fi

NO_CONFIRM=0
case "$ARGUMENTS" in *--no-confirm*) NO_CONFIRM=1 ;; esac
```

## Step 3 — Compute task summary for the confirm prompt

```bash
CHANGE_DIR="openspec/changes/$ACTIVE_CHANGE"
TASKS_DONE=0; TASKS_TOTAL=0; TASKS_INCOMPLETE=""
if [ -f "$CHANGE_DIR/tasks.md" ]; then
  TASKS_TOTAL=$(grep -cE '^[[:space:]]*- \[[ xX-]\]' "$CHANGE_DIR/tasks.md" 2>/dev/null)
  TASKS_DONE=$(grep  -cE '^[[:space:]]*- \[[xX]\]'   "$CHANGE_DIR/tasks.md" 2>/dev/null)
  TASKS_INCOMPLETE=$(grep -nE '^[[:space:]]*- \[[ -]\]' "$CHANGE_DIR/tasks.md" 2>/dev/null | head -5)
fi
```

## Step 4 — Confirm

Show what's about to clear and any incomplete tasks (lets user catch premature `/complete`):

```
About to mark complete:
  Change:    feat-add-dashboard-ssr
  Jira:      ENG-1234
  Phase:     03  ·  Plan: 03-03-PLAN.md
  Started:   2026-05-14T09:00:00Z  (4d ago)
  Tasks:     5/8 done

⚠ 3 tasks still unchecked:
  L12:   - [ ] Add SSR cache TTL setting
  L18:   - [ ] Wire Prometheus metric
  L22:   - [ ] Update README

This will:
  • Clear .active.{change,phase,plan,jira_key,...}
  • Append `completed` event to .mina/state.json history
  • Remove .mina/.statusline-cache-feat-add-dashboard-ssr.json

Will NOT:
  • Modify code, openspec/, or git
  • Transition Jira (run /mina:jira-update separately)
  • Archive the OpenSpec change (run `openspec archive` separately)

Proceed? [y/N]
```

Skip the prompt when `--no-confirm` is set or when `TASKS_TOTAL == 0` (no tasks file to compare against).

If incomplete tasks exist, default the prompt to N — require explicit `y`. This is the most common misuse: hitting `/complete` mid-phase by mistake.

## Step 5 — Clear active state (atomic write)

Follow the canonical pattern from `CLAUDE.md` — `mktemp`, size-check, `--arg` for all interpolations, atomic `mv`:

```bash
TMP=$(mktemp -t mina-state-XXXX) || exit 1
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq --arg ts "$NOW" \
   --arg change "$ACTIVE_CHANGE" \
   --arg jira "$JIRA_KEY" \
   --arg phase "$ACTIVE_PHASE" \
   --arg plan "$ACTIVE_PLAN" \
   --arg since "$SINCE" \
  '.active = {} |
   .history += [{
     ts: $ts,
     event: "completed",
     change: $change,
     jira_key: $jira,
     phase: $phase,
     plan: $plan,
     was_active_since: $since
   }]' \
  "$STATE" > "$TMP"

if [ -s "$TMP" ]; then
  mv "$TMP" "$STATE"
else
  rm -f "$TMP"
  echo "✗ jq produced empty output; state.json untouched."
  exit 1
fi
```

`.active` is set to `{}` rather than deleted so downstream readers (`jq -r '.active.change // ""'`) keep working without null-handling changes.

## Step 6 — Remove orphan statusline cache

The statusline caches `openspec status --json` per change at `.mina/.statusline-cache-<change>.json` keyed by `tasks.md` mtime. After completion the cache is dead weight — drop it.

```bash
rm -f ".mina/.statusline-cache-$ACTIVE_CHANGE.json"
```

Token logs at `.mina/tokens/<change>.jsonl` are **kept** — those are historical cost data (consumed by `/mina:token-report all`). Never delete on completion.

## Step 7 — Print next steps

```
✓ Completed feat-add-dashboard-ssr (ENG-1234)
  Active pointer cleared. Statusline will drop the change segment on next message.

Suggested follow-ups (run separately):
  /mina:jira-update feat-add-dashboard-ssr   ← post summary comment to Jira (no transition)
  openspec validate feat-add-dashboard-ssr   ← confirm spec is consistent
  openspec archive  feat-add-dashboard-ssr   ← move openspec/changes/ → openspec/specs/

To resume later (e.g. follow-up work, hotfix):
  /mina:resume feat-add-dashboard-ssr
```

Tailor suggestions: skip `jira-update` line if `JIRA_KEY` is empty; skip `archive` line if `openspec` CLI not on PATH.

## Watchouts

- **Pointer only.** This command does NOT mark spec done, transition Jira, or archive. Those are separate confirmations on purpose — bundling them was rejected during design because each has a different blast radius (local vs Atlassian vs filesystem move).
- **Incomplete tasks**: default-N confirm prevents premature completion. If users frequently bypass it with `--no-confirm`, that signals their tasks.md is out of sync with reality — fix the source, don't fight the prompt.
- **Concurrency**: two parallel `/complete` runs race on `state.json` — mktemp + size-check makes the write atomic but last-writer-wins on content. Usually fine; surface in CLAUDE.md if it becomes a problem.
- **No undo**: history event records what was cleared (`was_active_since`, phase, plan, jira_key), so `/mina:resume <change>` can fully restore. If the user immediately regrets `/complete`, point them at `/mina:resume`.
- **Don't auto-run** `openspec archive`. Archive moves files on disk and is hard to reverse — keep it explicit.
