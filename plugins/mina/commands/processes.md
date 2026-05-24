---
description: List, prune, or kill background processes tracked by mina
argument-hint: [--list | --prune | --kill <pid> | --register <pid> <description>]
---

# Background processes

Manage long-running background processes (dev servers, watch builds, tunnels) tracked across mina sessions.

## Modes

| `$ARGUMENTS` | Action |
|---|---|
| empty or `--list` | List tracked processes with alive/dead status |
| `--prune` | Remove dead PIDs from state.json |
| `--kill <pid>` | Send SIGTERM to a tracked PID (with confirmation) |
| `--register <pid> "<desc>"` | Add an existing PID to tracking |
| `--restart` | Show original commands for dead processes; user runs them |

## --list (default)

```bash
STATE=".mina/state.json"
[ -f "$STATE" ] || { echo "No state file. Run /mina:resume first."; exit 0; }

echo "Background processes:"
echo ""
jq -c '.background_processes[]?' "$STATE" 2>/dev/null | while read entry; do
  PID=$(echo "$entry" | jq -r '.pid')
  CMD=$(echo "$entry" | jq -r '.command')
  STARTED=$(echo "$entry" | jq -r '.started_at')
  LOG=$(echo "$entry" | jq -r '.log_path // "none"')
  HOST=$(echo "$entry" | jq -r '.hostname // "unknown"')

  # Verify
  if kill -0 "$PID" 2>/dev/null; then
    STATUS="✓ alive"
  else
    STATUS="✗ dead"
  fi

  # Format started_at as relative time
  AGE=$(date -d "$STARTED" +%s 2>/dev/null || date -j -f '%Y-%m-%dT%H:%M:%SZ' "$STARTED" +%s 2>/dev/null)
  NOW=$(date +%s)
  ELAPSED=$((NOW - AGE))
  REL=$(printf '%dh%dm' $((ELAPSED/3600)) $(((ELAPSED%3600)/60)))

  printf "  PID %-7s %-8s  %s  (started %s ago)\n" "$PID" "$STATUS" "$CMD" "$REL"
  printf "         host: %s  log: %s\n" "$HOST" "$LOG"
done
```

Show as table:

```
Background processes:

  PID 12384   ✓ alive   npm run dev:dashboard       (started 4h22m ago)
              host: macbook-quang   log: /tmp/mina-bg-12384.log
  PID 12390   ✗ dead    vite build --watch         (started 6h05m ago)
              host: macbook-quang   log: /tmp/mina-bg-12390.log

Hints:
  /mina:processes --prune                clear dead entries
  /mina:processes --restart              show commands to restart dead procs
  tail -f /tmp/mina-bg-12384.log         watch live output
```

## --prune

```bash
TMP=$(mktemp -t mina-state-XXXX) || exit 1
ALIVE_FILE=$(mktemp -t mina-alive-XXXX) || { rm -f "$TMP"; exit 1; }

# Collect alive PID entries (use -r to avoid backslash mangling)
jq -c '.background_processes[]?' "$STATE" 2>/dev/null | while IFS= read -r entry; do
  PID=$(echo "$entry" | jq -r '.pid')
  kill -0 "$PID" 2>/dev/null && echo "$entry"
done > "$ALIVE_FILE"

ALIVE=$(jq -s . "$ALIVE_FILE")
jq --argjson alive "$ALIVE" '.background_processes = $alive' "$STATE" > "$TMP"
if [ -s "$TMP" ]; then
  mv "$TMP" "$STATE"
  echo "Pruned dead entries. Remaining: $(jq '.background_processes | length' "$STATE")"
else
  rm -f "$TMP"
  echo "✗ jq produced empty output; state.json untouched."
fi
rm -f "$ALIVE_FILE"
```

CONFIRM with user first, list what will be removed.

## --kill <pid>

```bash
PID="$2"

# Validate: is it tracked?
TRACKED=$(jq --arg pid "$PID" '.background_processes[] | select(.pid == ($pid | tonumber))' "$STATE")
if [ -z "$TRACKED" ]; then
  echo "PID $PID not tracked by mina. To kill anyway, use `kill $PID` directly."
  exit 0
fi

CMD=$(echo "$TRACKED" | jq -r '.command')
echo "Will send SIGTERM to PID $PID ($CMD)."
read -p "Confirm? [y/N] " ANS
[ "$ANS" = "y" ] || exit 0

# Sanity-check: PID may have been reused by the OS. Compare current `ps` command
# against the tracked command before killing.
TRACKED_CMD=$(echo "$TRACKED" | jq -r '.command')
LIVE_CMD=$(ps -p "$PID" -o command= 2>/dev/null | head -c 200)
case "$LIVE_CMD" in
  *"$TRACKED_CMD"*) ;;
  *)
    echo "⚠ PID $PID currently runs: $LIVE_CMD"
    echo "   Tracked as:             $TRACKED_CMD"
    read -p "PID may have been reused. Kill anyway? [y/N] " ANS2
    [ "$ANS2" = "y" ] || exit 0
    ;;
esac

kill "$PID" 2>/dev/null && echo "Sent SIGTERM" || echo "Failed (already dead?)"

# Remove from state (atomic via mktemp)
TMP=$(mktemp -t mina-state-XXXX) || exit 1
jq --arg pid "$PID" '.background_processes |= map(select(.pid != ($pid | tonumber)))' "$STATE" > "$TMP"
[ -s "$TMP" ] && mv "$TMP" "$STATE" || { rm -f "$TMP"; echo "✗ jq empty output; state.json untouched."; exit 1; }
```

## --register <pid> "<description>"

Add an existing PID to tracking. Useful when user started something with raw `&` and wants mina to remember it.

```bash
PID="$2"
DESC="$3"

# Verify alive
kill -0 "$PID" 2>/dev/null || { echo "PID $PID not alive"; exit 1; }

# Get command from ps if available
PS_CMD=$(ps -p "$PID" -o command= 2>/dev/null)
[ -z "$DESC" ] && DESC="$PS_CMD"

HOST=$(hostname)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq --arg pid "$PID" --arg cmd "$DESC" --arg host "$HOST" --arg ts "$NOW" \
  '.background_processes += [{"pid": ($pid | tonumber), "command": $cmd, "started_at": $ts, "hostname": $host, "log_path": null, "registered_by": "manual"}]' \
  "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"

echo "Registered PID $PID: $DESC"
```

## --restart

For each DEAD tracked process, print the original command. DO NOT auto-execute.

```
Dead background processes:

  vite build --watch    (was PID 12390, died ~2h ago)
  
To restart manually:
  vite build --watch &
  echo $!  # capture new PID

Then register the new PID:
  /mina:processes --register <new-pid> "vite build --watch"
```

## Starting a new background process

If user asks to start something long-running:

```
Suggest:
  nohup <command> > /tmp/mina-bg-<name>.log 2>&1 &
  PID=$!
  /mina:processes --register $PID "<command>"
```

This pattern: logs persist, process detaches from terminal, gets registered for later management.

## Watchouts

- **kill -0 checks permission**, not just existence. On some containers/macOS sandboxes, you may not be able to `kill -0` other users' PIDs. Treat permission errors as "unknown state" not "dead".
- **PIDs are reused** by the OS. A tracked PID that's now "alive" might be a different process than originally registered. Sanity-check by comparing process command (`ps -p $PID -o command=`) against the tracked command before any kill operation.
- **Don't auto-prune** without confirmation. User may want to see what died to investigate.
- **Don't auto-restart** even with `--restart`. Print commands; user runs them. Auto-restarting infinite-loop processes is dangerous.
- **Log path may be sensitive**. If `.mina/state.json` is committed to git, log paths get committed too. Don't include sensitive temp paths.
- **Cross-machine state**: PIDs from `macbook-quang` are meaningless on `linux-server`. Filter by hostname before showing as relevant on current machine.
