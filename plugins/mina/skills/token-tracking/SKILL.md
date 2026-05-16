---
name: token-tracking
description: Use this skill whenever the user asks about token usage, costs, spend, how much a session cost, burn rate, or "how expensive was that". Also activates when the user mentions /cost, /usage, ccusage, or asks for a cost breakdown by change/phase/Jira issue. Defines the project's token tracking conventions and points to the right reporting tool.
---

# Token tracking

This project logs token usage per OpenSpec change and per GSD phase, so cost can be attributed to specific work — not just to a session.

## What gets tracked

When the spec-driven workflow is in use, token costs are logged to `.mina/tokens/`, and active state lives in `.mina/state.json`:

```
.mina/
├── state.json                ← active change/phase/plan/sessions/processes/checkpoints/history
├── tokens/
│   ├── <change-name>.jsonl   ← one line per assistant message (cost data only)
│   └── _session-<id>.jsonl   ← session-level log (fallback when no change is active)
└── checkpoints/
    └── <name>.json           ← named state snapshots (from /mina:checkpoint)
```

Each line in a change's `.jsonl` looks like:

```json
{"ts":"2026-05-14T10:00:00Z","model":"claude-opus-4-7","input":1024,"output":456,"cache_read":4096,"cost_usd":0.0234,"phase":"03","jira_key":"ENG-1234"}
```

## Sources of truth

In order of trust:

1. **Anthropic Console** (`console.anthropic.com`) — authoritative billing
2. **`/usage`** command in Claude Code — current 5-hour window
3. **`/cost`** command in Claude Code — session breakdown by model
4. **ccusage** — parses local JSONL session files, very accurate
5. **`.mina/tokens/` files** — derived from statusline hook, per-change attribution
6. **Estimates from context** — least trustworthy, use only if nothing else available

## When to check token usage

Proactively surface token usage when:
- User completes a phase/change and asks to "wrap up"
- User asks "how much did this cost" or similar
- A single change exceeds 100k tokens or $5 — flag this as unusually high
- Before spawning many parallel subagents (warn about multiplier effect)

## How to report

For session-level: tell the user to run `/cost` or `/usage` directly — these are native and most accurate.

For change-level: run the `/token-report` command (provided by this plugin).

For external aggregation: ccusage handles daily/monthly/by-project breakdowns:
```bash
npx ccusage daily --since 20260501 --until 20260514
npx ccusage session
npx ccusage daily --project <project-name>
```

## Subagent cost warning

GSD spawns subagents with fresh 200k contexts. Each subagent burns tokens independently. If a phase has N parallel plans, the cost ≈ N × single-plan cost.

Reported real incidents from the community: 49-subagent workflows have cost $8,000–$15,000 in a single run; a 23-subagent code-quality project consumed $47,000 over 3 days.

Always:
- Cap parallelism in CLAUDE.md (e.g. max 5 parallel subagents)
- Never leave subagent chains unattended overnight
- Check `.mina/tokens/<change>.jsonl` after a phase to spot runaway loops

## Optional: enable the statusline hook

This plugin ships a statusline script at `hooks/statusline.sh` that:
- Displays cost + context + active change in your terminal
- Logs each turn to `.mina/tokens/<current-change>.jsonl` automatically

To enable, add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "${CLAUDE_PLUGIN_ROOT}/hooks/statusline.sh",
    "padding": 0
  }
}
```

See `templates/settings.json.example` in the marketplace repo for the full config.

If the hook is not enabled, change-level tracking falls back to manual ccusage queries; everything still works, just less granular.

## Privacy

`.mina/tokens/` contains cost data, not transcripts. Safe to commit if you want team visibility into where the budget goes. Add to `.gitignore` if not.
