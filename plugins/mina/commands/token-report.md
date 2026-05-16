---
description: Report token usage and cost — session, per-change, or aggregate
argument-hint: [session | <change-name> | today | week | all]
---

# Token report

## Step 1 — Determine scope

| `$ARGUMENTS` | Scope |
|---|---|
| empty or `session` | Current Claude Code session (use `/cost`) |
| `<change-name>` | Specific OpenSpec change from `.mina/tokens/<change-name>.jsonl` |
| `today` | All work today across changes |
| `week` | Last 7 days |
| `all` | All time, broken down by change |

If `$ARGUMENTS` looks like a Jira key (e.g. `ENG-1234`), resolve to change name:
```bash
grep -l "jira_key: $ARGUMENTS" openspec/changes/*/proposal.md | xargs dirname | xargs basename
```

## Step 2 — Gather data

### Session scope
Tell user to run `/cost` directly — it's native and authoritative. Don't try to compute.

### Change scope

```bash
CHANGE="$ARGUMENTS"
LOG=".mina/tokens/$CHANGE.jsonl"

if [ ! -f "$LOG" ]; then
  echo "No token log for $CHANGE. Has the statusline hook been installed?"
  echo "Falling back to ccusage session estimate."
  npx ccusage session --json | jq '.'
  exit
fi

# Aggregate
jq -s '{
  requests: length,
  input: (map(.input) | add),
  output: (map(.output) | add),
  cache_read: (map(.cache_read // 0) | add),
  cache_creation: (map(.cache_creation // 0) | add),
  cost_usd: (map(.cost_usd) | add),
  models: (group_by(.model) | map({model: .[0].model, count: length, cost: (map(.cost_usd) | add)})),
  first_ts: (min_by(.ts) | .ts),
  last_ts: (max_by(.ts) | .ts)
}' "$LOG"
```

### Today / Week scope

Use ccusage as authoritative — it parses the JSONL session files directly:

```bash
# Today
npx ccusage daily --since "$(date +%Y%m%d)" --until "$(date +%Y%m%d)" --json

# Week
npx ccusage daily --since "$(date -d '7 days ago' +%Y%m%d)" --until "$(date +%Y%m%d)" --json

# Also combine with .mina/tokens/ data to attribute to changes
for f in .mina/tokens/*.jsonl; do
  CHANGE=$(basename "$f" .jsonl)
  if [ "$CHANGE" = "_session" ] || [[ "$CHANGE" == _session-* ]]; then continue; fi
  # filter by date and sum
  COST=$(jq -s --arg since "$(date -d '7 days ago' -Iseconds)" \
    '[.[] | select(.ts >= $since)] | map(.cost_usd) | add // 0' "$f")
  echo "$CHANGE: \$$COST"
done
```

### All scope

```bash
echo "=== Per-change totals ==="
for f in .mina/tokens/*.jsonl; do
  CHANGE=$(basename "$f" .jsonl)
  if [[ "$CHANGE" == _session* ]]; then continue; fi
  STATS=$(jq -s '{
    requests: length,
    cost: (map(.cost_usd) | add // 0),
    input: (map(.input) | add // 0),
    output: (map(.output) | add // 0)
  }' "$f")
  echo "$CHANGE: $STATS"
done

echo ""
echo "=== Lifetime (from ccusage) ==="
npx ccusage --json | jq '.totals'
```

## Step 3 — Format output

Show as a table (mobile-friendly, max 80 chars):

```
Token report — change: feat-add-dashboard-ssr

  Requests:       42
  Input tokens:   85,200
  Output tokens:  12,400
  Cache read:     203,000
  Cache create:   18,000
  Total cost:     $1.34

  Models:
    opus-4-7:     38 requests, $1.21
    haiku-4-5:     4 requests, $0.13

  First seen:     2026-05-14 09:12
  Last activity:  2026-05-14 14:47
  Duration:       5h 35m
```

For multi-change reports, sort by cost desc:

```
Token report — last 7 days

  Change                          Reqs   Tokens     Cost
  ─────────────────────────────────────────────────────
  feat-add-dashboard-ssr (active)   42   97.6k     $1.34
  fix-flaky-checkout-e2e            18   26.3k     $0.41
  chore-bump-deps                    7    8.1k     $0.09
  _session (untagged)               31   54.2k     $0.78
  ─────────────────────────────────────────────────────
  Total                             98  186.2k     $2.62

  ccusage daily total:  $2.71  (Δ $0.09, likely cache rounding)
```

## Step 4 — Surface warnings

If any change costs >$5 OR has >100k tokens output, flag it:

```
⚠️ High-cost change detected: feat-add-dashboard-ssr ($1.34)
  - 4 subagents spawned, total 23 requests with output >2k tokens
  - Check .mina/tokens/feat-add-dashboard-ssr.jsonl for runaway patterns
```

If `/cost` shows session approaching the 5-hour window limit:
```
⚠️ Session at 78% of 5-hour window. Consider breaking before /clear-ing.
```

## Step 5 — Reconciliation note

Always include this footer when showing dollar amounts:

```
ℹ️  Dollar figures are local estimates from token counts × public pricing.
   For authoritative billing, see console.anthropic.com.
   Cache reads are billed at 10% of input rate — this report reflects that.
```

## Watchouts

- ccusage requires Node 18+ and reads from `~/.claude/projects/`. If user uses a custom claude data dir, set `CLAUDE_CONFIG_DIR` first.
- If `.mina/tokens/` is missing entirely, the statusline hook hasn't been installed — point user to `templates/settings.json.example`.
- Subscription users (Pro/Max) get usage included; dollar figures are reference only, not billing.
- Per-change attribution depends on `.mina/state.json` being kept current by `/jira-to-spec` and `/spec-to-plan`. If those weren't used, all activity logs to `_session-<id>.jsonl`.
