---
description: Save or restore a named workflow state snapshot
argument-hint: <name> [notes] | --list | --restore <name>
---

# Checkpoint

Save the current `.mina/state.json` as a named snapshot. Useful before risky changes, branch switches, or as a "save point" you can return to.

This does NOT modify your code — it only snapshots workflow state (active change, phase, plan, sessions, processes), plus a reference to current git commit so you can correlate.

## Modes

| `$ARGUMENTS` | Action |
|---|---|
| `<name> [notes]` | Save checkpoint with optional notes |
| `--list` | List all checkpoints |
| `--restore <name>` | Restore state from checkpoint (current state moves to `<name>-previous`) |
| `--diff <name>` | Show diff between current state and checkpoint |
| `--delete <name>` | Remove a checkpoint |

## Save

```bash
NAME="$1"
NOTES="${@:2}"

# Sanitize name
NAME=$(echo "$NAME" | tr -c 'a-zA-Z0-9_-' '-' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
[ -z "$NAME" ] && { echo "Invalid name. Use a-z0-9_-"; exit 1; }

# Verify state exists
[ -f .mina/state.json ] || { echo "No state.json. Nothing to checkpoint."; exit 1; }

# Already exists?
if [ -f ".mina/checkpoints/$NAME.json" ]; then
  read -p "Checkpoint '$NAME' exists. Overwrite? [y/N] " ANS
  [ "$ANS" = "y" ] || exit 0
fi

mkdir -p .mina/checkpoints

# Capture git state too
GIT_COMMIT=$(git rev-parse HEAD 2>/dev/null)
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
GIT_STATUS=$(git status --short 2>/dev/null | head -20)
GIT_DIRTY=$(test -n "$GIT_STATUS" && echo "true" || echo "false")

# Build checkpoint
jq --arg name "$NAME" \
   --arg notes "$NOTES" \
   --arg commit "$GIT_COMMIT" \
   --arg branch "$GIT_BRANCH" \
   --argjson dirty "$GIT_DIRTY" \
   --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '. + {
     "checkpoint_meta": {
       "name": $name,
       "notes": $notes,
       "saved_at": $ts,
       "git": {
         "commit": $commit,
         "branch": $branch,
         "dirty": $dirty
       }
     }
   }' .mina/state.json > ".mina/checkpoints/$NAME.json"

# Also record in state.json checkpoints[]
jq --arg name "$NAME" --arg notes "$NOTES" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg commit "$GIT_COMMIT" \
   '.checkpoints += [{"name": $name, "timestamp": $ts, "git_commit": $commit, "notes": $notes}]' \
   .mina/state.json > .mina/state.json.tmp && mv .mina/state.json.tmp .mina/state.json

echo "✓ Saved checkpoint '$NAME'"
echo "  Active: $(jq -r '.active.change' .mina/state.json)"
echo "  Phase:  $(jq -r '.active.phase' .mina/state.json)"
echo "  Plan:   $(jq -r '.active.plan' .mina/state.json)"
echo "  Git:    $GIT_BRANCH @ ${GIT_COMMIT:0:7} (dirty: $GIT_DIRTY)"
[ -n "$NOTES" ] && echo "  Notes:  $NOTES"
```

## --list

```bash
ls -1 .mina/checkpoints/*.json 2>/dev/null | while read f; do
  NAME=$(basename "$f" .json)
  jq -r --arg name "$NAME" \
    '"\($name) | \(.checkpoint_meta.saved_at) | change: \(.active.change // "none") | phase: \(.active.phase // "-") | notes: \(.checkpoint_meta.notes // "-")"' \
    "$f"
done | column -t -s '|'
```

Output:

```
before-refactor      2026-05-14T12:00:00Z   change: feat-add-dashboard-ssr   phase: 03   notes: All tests passing, about to refactor module fed wiring
mid-session-paused   2026-05-14T15:30:00Z   change: feat-add-dashboard-ssr   phase: 03   notes: Going to lunch, plan 03-02 in progress
```

## --restore

```bash
NAME="$2"
CKPT=".mina/checkpoints/$NAME.json"
[ -f "$CKPT" ] || { echo "No checkpoint named '$NAME'"; exit 1; }

# Save current state as <name>-previous (so restore is reversible)
PREV_NAME="${NAME}-previous-$(date +%s)"
cp .mina/state.json ".mina/checkpoints/$PREV_NAME.json"

# Show what will change
echo "Will restore state from checkpoint '$NAME'."
echo ""
echo "Current → Checkpoint:"
echo "  Active change:  $(jq -r '.active.change' .mina/state.json) → $(jq -r '.active.change' "$CKPT")"
echo "  Active phase:   $(jq -r '.active.phase' .mina/state.json) → $(jq -r '.active.phase' "$CKPT")"
echo "  Active plan:    $(jq -r '.active.plan' .mina/state.json) → $(jq -r '.active.plan' "$CKPT")"
echo ""
echo "Current state will be saved as: $PREV_NAME"
echo "Git is NOT touched (state-only restore)."
echo ""
read -p "Proceed? [y/N] " ANS
[ "$ANS" = "y" ] || exit 0

# Restore (strip checkpoint_meta from the restored file)
jq 'del(.checkpoint_meta) | .history += [{"ts": (now|todate), "event": "restored_from_checkpoint", "name": "'$NAME'"}]' \
  "$CKPT" > .mina/state.json
echo "✓ Restored. Run /mina:status to verify."
```

## --diff

```bash
NAME="$2"
CKPT=".mina/checkpoints/$NAME.json"
[ -f "$CKPT" ] || { echo "No checkpoint named '$NAME'"; exit 1; }

diff <(jq -S 'del(.checkpoint_meta) | del(.history)' "$CKPT") \
     <(jq -S 'del(.history)' .mina/state.json) | head -40
```

## When to checkpoint (auto-suggest)

Surface a suggestion to `/mina:checkpoint <name>` when:

- About to start a destructive operation (large refactor, merge, rebase)
- Switching branches mid-phase
- Before invoking GSD with 5+ subagents (high cost; failure means re-run)
- User says "I'll be back in a bit" or similar pause indicators
- Just before `openspec archive` — captures final state of the change

Don't checkpoint silently; always ask before saving.

## Watchouts

- **Checkpoints don't include code state**. Git commit hash is recorded for correlation, but checkpoint restore doesn't `git checkout`. If you restore a checkpoint but your code has moved on, the active plan reference may not match current code.
- **Don't auto-restore**. Restore is destructive of current state (even with backup) — always require explicit confirm.
- **Restoring across machines** is risky — PIDs and session IDs in `background_processes` and `sessions` won't be valid. Restoring strips those by default? Actually no — be explicit and ask "Include processes/sessions from checkpoint? [y/N]" defaulting to N.
- **Naming**: enforce sanitized names. Don't accept names with slashes, spaces, or special chars — they'll mess up the file path.
- **Checkpoints accumulate**. After 10+ checkpoints, suggest pruning old ones with `--delete`.
