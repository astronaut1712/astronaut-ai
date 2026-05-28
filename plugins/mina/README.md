# mina

A Claude Code plugin (also installs into opencode, Codex, Pi, Kiro, Kilo Code via `install.sh`) that wires together Jira, OpenSpec, GSD, and Superpowers into a single spec-driven pipeline.

## Pipeline

```
Jira issue
   │ /jira-pick → /jira-to-spec ENG-1234
   ▼
OpenSpec change (openspec/changes/feat-…/)
   │ /spec-to-plan feat-…
   ▼
GSD phase (.planning/phases/NN-…/)  OR  Superpowers plan
   │ /gsd-execute-phase NN  OR  /superpowers:execute-plan
   ▼
Code + tests + commits
   │ /jira-update feat-…
   ▼
Jira: commented (transition stays manual)
```

## What this plugin provides

**Seven auto-triggering skills:**

- `spec-driven-workflow` — meta-skill defining the canonical pipeline and detection rules
- `openspec-aware` — checks `openspec/changes/` for matching specs BEFORE any planning, prevents duplicate work
- `jira-via-acli` — fallback for Jira operations when Atlassian MCP is unstable
- `token-tracking` — knows where token data lives, when to flag high spend, how to attribute cost to changes
- `model-fallback` — model routing tiers and decision rules for rate limits, overload, cost caps, subagent multipliers
- `progress-tracking` — aggregates OpenSpec tasks + GSD plans + git state + cost into a unified view; surfaces mini-status at session start and after task completion
- `process-resume` — maps prior sessions / changes / background processes to a clear resume path; covers both Claude Code session resume and workflow resume

**Fifteen slash commands:**

- `/mina:init [--yes] [--skip=<dep,...>]` — detect and install runtime deps (`jq`, `openspec`, `gsd` via npx, Superpowers, `graphify-rs`, `acli`); runs `openspec init` if no `openspec/` dir. Read-only detection by default; each install gated by confirm. Idempotent.
- `/mina:doctor [--verbose] [--json]` — read-only health check: deps, `.mina/state.json` integrity, statusline hook wiring, env/auth, `openspec validate`, token-log writability. Exits non-zero on any fail (CI-wireable).
- `/mina:jira-pick` — list Jira issues and pick one to start
- `/mina:jira-to-spec <KEY>` — convert Jira issue → OpenSpec change (initializes `.mina/state.json`)
- `/mina:spec-to-plan <change-name>` — bridge OpenSpec → GSD or Superpowers plan
- `/mina:jira-update <change-or-key>` — post implementation summary as a Jira comment (no status transition; user owns that)
- `/mina:complete [change] [--no-confirm]` — mark active change complete; clears `.active.*` so the statusline drops the change segment (local pointer only; does not touch Jira / openspec / code)
- `/mina:review [change | --staged | --branch | --since=<ref>]` — read-only review of changes against the active OpenSpec change; severity-tagged report with verdict
- `/mina:token-report [scope]` — token usage and cost report, per-change or aggregate
- `/mina:model-route [task]` — show recommended model + reason
- `/mina:model-switch <tier>` — record intent to switch to a fallback tier
- `/mina:status [change | --mini]` — comprehensive status: change, phase, plans, git, cost, processes
- `/mina:resume [change | session-id]` — pick up where you left off; lists candidates if ambiguous
- `/mina:processes [--list | --prune | --kill <pid> | --register <pid> <desc>]` — manage background processes
- `/mina:checkpoint <name> [notes] | --restore <name> | --list` — save or restore named state snapshots

**One optional statusline hook:**

- `hooks/statusline.sh` — displays cost + context + active change + task progress + alive process count + model-routing warnings; logs each turn to `.mina/tokens/<change>.jsonl`. Flags cost-cap breaches and model mismatches inline.

**State layout** (`.mina/` at project root):

```
.mina/
├── state.json            ← active change/phase/plan/sessions/processes/checkpoints/history
├── tokens/<name>.jsonl   ← per-change cost logs (safe to commit if team-shared)
└── checkpoints/<name>.json   ← named state snapshots
```

(When installed via marketplace, commands are namespaced as `/mina:<name>`. When installed manually into `.claude/commands/`, they're flat: `/jira-pick` etc. Codex/Pi use the same flat slash-command surface; Kiro/Kilo have no slash command system — the commands ship as a single `mina-commands-reference.md` for human invocation.)

## Prerequisites

The plugin is the glue — runtime tools are not bundled:

| Tool | Required? | Install |
|---|---|---|
| OpenSpec | Yes | `npm install -g @fission-ai/openspec` |
| GSD | One of GSD or Superpowers | `npx @opengsd/get-shit-done-redux@latest` |
| Superpowers | One of GSD or Superpowers | `/plugin install superpowers@superpowers-marketplace` |
| Atlassian MCP | Recommended | See top-level `templates/mcp.json.example` |
| acli | Fallback for Jira | `brew install --cask acli` |

## Configuration

After install, append the project rules snippet to your project's `CLAUDE.md` (Claude Code) or `AGENTS.md` (opencode). See the top-level repo for `templates/CLAUDE.md.snippet`.

## Security note

Jira content (description, comments) is treated as untrusted input — external reporters and integrations can embed prompt injection. The skills explicitly do not follow embedded commands. See each skill's SKILL.md for details.
