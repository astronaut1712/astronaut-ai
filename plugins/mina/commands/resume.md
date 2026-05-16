---
description: Resume work — pick up where you left off, or resume a Claude Code session
argument-hint: [change-name | session-id | --pick]
---

# Resume

Two kinds of resume, this command handles both:

1. **Workflow resume** — restore active change/phase/plan context in `.mina/state.json`
2. **Session resume** — print the `claude --resume` command to use

## Step 1 — Parse argument

| `$ARGUMENTS` | Action |
|---|---|
| empty | Show what's resumable; let user pick |
| matches `^[a-f0-9]{8,}$` | Treat as Claude Code session ID |
| matches an OpenSpec change name | Workflow resume to that change |
| matches a Jira key | Resolve to change, then workflow resume |
| `--pick` | Force interactive picker |
| `--list` | List candidates without resuming |

## Step 2 — Gather candidates

```bash
# Active change from state.json
ACTIVE_CHANGE=$(jq -r '.active.change // ""' .mina/state.json 2>/dev/null)

# Recently touched changes (top 5)
RECENT_CHANGES=$(ls -1t openspec/changes/*/proposal.md 2>/dev/null | head -5 | xargs -n1 dirname | xargs -n1 basename)

# Recent sessions from state.json
SESSIONS=$(jq -r '.sessions[]? | "\(.id)|\(.started_at)|\(.change // "untagged")"' .mina/state.json 2>/dev/null)

# Claude Code's native session storage (alternative path)
PROJ_ENCODED=$(pwd | sed 's|/|-|g' | sed 's|^-||')
CLAUDE_SESSIONS_DIR="$HOME/.claude/projects/-$PROJ_ENCODED"
if [ -d "$CLAUDE_SESSIONS_DIR" ]; then
  NATIVE_SESSIONS=$(ls -1t "$CLAUDE_SESSIONS_DIR"/*.jsonl 2>/dev/null | head -5)
fi

# Background processes still alive
ALIVE_PROCS=$(jq -c '.background_processes[]?' .mina/state.json 2>/dev/null | while read entry; do
  PID=$(echo "$entry" | jq -r '.pid')
  kill -0 "$PID" 2>/dev/null && echo "$entry"
done)
```

## Step 3 — Empty `$ARGUMENTS` → interactive picker

Show:

```
Resumable contexts:

  Active change (from state.json):
    [a] feat-add-dashboard-ssr (ENG-1234) · last touched 6h ago

  Recent changes (not currently active):
    [b] fix-flaky-checkout-e2e (ENG-1240) · 2d ago, 5/5 tasks
    [c] chore-bump-deps · 3d ago, archived

  Claude Code sessions (last 5):
    [1] abc12345 · started 6h ago · change: feat-add-dashboard-ssr
    [2] xyz98765 · 1d ago · change: fix-flaky-checkout-e2e
    [3] qwe45678 · 3d ago · change: untagged

  Alive background processes:
    PID 12384  npm run dev:dashboard  (4h)

Pick a letter or session number, or:
  /mina:resume <change-name>     workflow resume only
  /mina:resume <session-id>      session resume only
  /mina:resume --list            show this list, don't ask
```

## Step 4 — On selection: workflow resume

When user picks a change (letter or names it directly):

1. Update `.mina/state.json`:
   ```bash
   jq --arg ch "$CHANGE" \
      --arg jira "$JIRA_KEY" \
      '.active.change = $ch | .active.jira_key = $jira | .active.since = (now | todate) |
       .history += [{"ts": (now|todate), "event": "resumed", "change": $ch}]' \
      .mina/state.json > .mina/state.json.tmp && mv .mina/state.json.tmp .mina/state.json
   ```

2. Verify git branch matches:
   ```bash
   BRANCH=$(git rev-parse --abbrev-ref HEAD)
   EXPECTED_BRANCH=$(grep -r "branch:" openspec/changes/$CHANGE/ 2>/dev/null | head -1)
   ```
   If mismatch, ask: "Branch is X but spec mentions Y. Switch? [Y/n]"

3. Check for stale background processes (last seen > 1 day ago) — suggest pruning

4. Run `/mina:status` to show the resumed state

## Step 5 — On selection: session resume

When user picks a session number/ID:

```
To resume this Claude Code session, run in your shell:

  claude --resume <session-id>

This will restore the conversation context. Inside the resumed session:
  - The SessionStart hook (if enabled) will print mini-status
  - Run /mina:status for full progress view
```

DO NOT try to invoke `claude --resume` from within Claude Code — it must be run from the OS shell.

If state.json maps this session to a change, also surface that:
```
  Session was last active on change: feat-add-dashboard-ssr (ENG-1234)
```

## Step 6 — Combined resume (both workflow + session)

If user wants both:
```
For a full resume (conversation + workflow):

  # 1. Exit current Claude Code (if running)
  # 2. Resume the session
  claude --resume <session-id>

  # 3. Once inside, verify workflow state:
  /mina:status

If you also need to restart background processes:
  /mina:processes --restart
```

## Step 7 — No `.mina/state.json` (cold start)

```
No prior state found. Best guesses:

  Git branch:        feat/eng-1234-add-dashboard-ssr
                     → suggests change: feat-add-dashboard-ssr
  OpenSpec changes:  
                     • feat-add-dashboard-ssr (modified 6h ago) ←
                     • fix-flaky-checkout-e2e (modified 2d ago)
  Native sessions:   3 sessions exist for this directory

Initialize state from one of these? [Y/n]
```

If user confirms, scaffold `state.json`:
```bash
mkdir -p .mina
cat > .mina/state.json <<EOF
{
  "version": "1.3",
  "active": {
    "change": "<chosen>",
    "jira_key": "<from-proposal-or-empty>",
    "since": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  },
  "sessions": [],
  "background_processes": [],
  "checkpoints": [],
  "history": [
    {"ts": "$(date -u +%Y-%m-%dT%H:%M:%SZ)", "event": "state_initialized", "from": "inference"}
  ]
}
EOF
```

## Watchouts

- **Don't auto-invoke** `claude --resume` — print the command for user to run themselves.
- **Native session JSONL path encoding varies by Claude Code version**. If `~/.claude/projects/-<encoded>/` doesn't exist, try `~/.config/claude/projects/...` (older versions). Fall back to "run `claude --resume` to see picker".
- **Background process restart isn't automatic** — those processes died with the original shell. Show the original command but require user confirmation before any auto-restart attempt.
- **State.json may be from another machine** if the team commits it. Detect hostname mismatch in `background_processes` entries; warn but don't block.
- **Spec changes during the gap** (since last activity) — if `openspec/changes/<name>/` files were modified since last state.json update, surface "Spec changed since you last worked on this" and suggest reviewing diff first.
