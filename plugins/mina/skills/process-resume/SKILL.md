---
name: process-resume
description: Use this skill whenever the user asks to resume work, pick up where they left off, continue a previous session, restart an interrupted task, or asks about background processes (dev servers, watch builds, long-running tests). Also activates when the user mentions session IDs, `claude --resume`, `--continue`, or "yesterday's work". Defines how to map prior sessions/changes/processes to a clear resume path.
---

# Process & resume

Two distinct things both called "resume":

1. **Claude Code session resume** — `claude --resume <id>` or `claude --continue`, restores conversation context
2. **Workflow resume** — pick up the same OpenSpec change / GSD phase / plan from any new session, using state files

This skill handles both. Background process tracking is bonus.

## Where state lives

```
.mina/
├── state.json            ← workflow state (active change/phase/plan, history, sessions, processes, checkpoints)
├── tokens/
│   └── <change>.jsonl    ← timeline of activity per change
└── checkpoints/
    └── <name>.json       ← named state snapshots
```

`state.json` structure:

```json
{
  "version": "1.3",
  "active": {
    "change": "feat-add-dashboard-ssr",
    "phase": "03",
    "plan": "03-03-PLAN.md",
    "jira_key": "ENG-1234",
    "since": "2026-05-14T09:00:00Z",
    "recommended_model": "claude-sonnet-4-7",
    "recommended_reason": "GSD execute phase with clear AC",
    "active_tier": "cheap",
    "switch_reason": "cost cap exceeded"
  },
  "sessions": [
    {"id": "abc12345", "started_at": "...", "change": "...", "status": "active"}
  ],
  "background_processes": [
    {"pid": 12384, "command": "npm run dev", "started_at": "...", "log_path": "...", "hostname": "macbook-quang"}
  ],
  "checkpoints": [
    {"name": "before-refactor", "timestamp": "...", "git_commit": "abc1234", "notes": "..."}
  ],
  "history": [
    {"ts": "...", "event": "change_started", "change": "..."},
    {"ts": "...", "event": "phase_started", "phase": "03"},
    {"ts": "...", "event": "model_switch", "tier": "cheap", "model": "claude-sonnet-4-7"},
    {"ts": "...", "event": "reviewed", "change": "...", "verdict": "APPROVE WITH NITS"}
  ]
}
```

State schema is versioned independently of the plugin version. Schema `"1.3"` was introduced in plugin 1.3.0 and is still current as of plugin 1.4.0; the 1.4 changes are additive optional fields, no migration required.

## Resume strategies

### Strategy 1 — workflow resume (cross-session, cross-machine)

When user says "where was I", "resume", "continue":

1. Read `.mina/state.json` → `active` field
2. Show: change, phase, current plan, last activity time
3. Cross-check git: is branch matching? Any uncommitted changes?
4. If state.json missing (new clone, fresh checkout): infer from openspec/changes/ most recently modified + git branch name

Output:
```
You were working on:
  ENG-1234  feat-add-dashboard-ssr
  Phase 03 plan 03-03-PLAN.md (Performance gating)
  Last touched 6 hours ago

To pick up:
  1. Confirm branch: feat/eng-1234-add-dashboard-ssr ← currently checked out: yes
  2. Run /mina:status for full progress view
  3. Continue work via /gsd-execute-phase 3 or direct edits
```

### Strategy 2 — Claude Code session resume

Native commands:
- `claude --resume` → interactive picker showing recent sessions
- `claude --resume <session-id>` → directly resume that session
- `claude --continue` → most recent session in current cwd
- `claude --resume <id> --print "..."` → resume in non-interactive mode

Map session ID → change via `state.json.sessions[]`. If user picks a session for resume, surface the matching change so they understand the work context.

### Strategy 3 — workflow + session combined

Often the user wants both: resume conversation context AND continue the work. Recommend:

```bash
# In your shell (outside Claude Code)
claude --resume <session-id-from-state.json>
```

Inside the resumed session, the SessionStart hook (if enabled) will print current `state.json` summary so you're oriented.

## Background processes

Claude Code's Bash tool supports `is_background: true` for long-running commands. Those processes:

- Persist across tool calls in the same session
- Do NOT persist across `--clear` or new sessions automatically
- Show in Claude Code's bash session manager (current versions)

### Register a background process manually

When user starts something long-running (dev server, watch test, build daemon) that should be tracked across sessions:

```bash
# After starting, capture PID and register
echo "{\"pid\": $!, \"command\": \"npm run dev\", \"started_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"log_path\": \"/tmp/mina-bg-$!.log\"}" \
  >> .mina/processes-register.jsonl

# Then /mina:processes will pick it up
```

### Check liveness

```bash
# Verify a tracked PID is still alive
for entry in $(jq -c '.background_processes[]' .mina/state.json 2>/dev/null); do
  PID=$(echo "$entry" | jq -r '.pid')
  kill -0 "$PID" 2>/dev/null && echo "$PID alive" || echo "$PID dead"
done
```

### Cleanup dead PIDs

`/mina:processes --prune` removes entries where PID no longer responds to `kill -0`.

## Watchouts

- **Session resume requires that session JSONL still exists** at `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`. If Claude Code was uninstalled or cache cleared, resume fails. Always verify file exists before suggesting resume.
- **Cross-machine resume only restores workflow state**, not session context. The conversation buffer doesn't sync (it lives on local disk). User will be in fresh chat but with full state knowledge from state.json.
- **PIDs collide across machines**. Don't compare PIDs across reboots or hosts — only meaningful on the machine where they were started. `state.json.background_processes` should include hostname for safety.
- **Subagents don't have separate PIDs** — they're calls within the parent agent's process. Don't track GSD/Superpowers subagents as background processes; track them via `state.json.history` events instead.
- **Don't auto-kill processes** when cleaning up. Always confirm with user — that "stale" dev server might be the production tunnel.
- **Resume into mid-execute-phase**: if a GSD phase was interrupted (partial completion), wave graph reset logic depends on GSD version. Best to surface the state and let user decide whether to re-run failed plans or pick up at next plan.
