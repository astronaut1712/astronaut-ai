---
description: Switch to a fallback model tier (primary, cheap, emergency, backup_provider)
argument-hint: <tier> [reason]
---

# Model switch

Use this when an error has occurred (rate limit, overload, exhausted window) OR the user explicitly wants to drop to a cheaper tier.

## Step 1 — Validate tier

Allowed tiers: `primary`, `cheap`, `emergency`, `backup_provider`.

If `$ARGUMENTS` is empty or invalid, list tiers from `model-routing.json` and ask user to pick.

## Step 2 — Resolve tier → model

Read `model-routing.json`:
```bash
TIER=$(echo "$ARGUMENTS" | awk '{print $1}')
MODEL=$(jq -r ".$TIER" model-routing.json 2>/dev/null)

[ -z "$MODEL" ] || [ "$MODEL" = "null" ] && echo "Tier '$TIER' not in model-routing.json"
```

## Step 3 — Confirm with user

Show:
```
About to switch model:
  Current tier:     primary (claude-opus-4-7)   [inferred from session]
  Switching to:     <tier> (<model>)
  Reason:           <from $ARGUMENTS or recent error>

Estimated cost change for next 10 turns at similar pace:
  Before:  ~$0.45
  After:   ~$0.12  (cheap tier ~75% cheaper)

Note: Claude Code does NOT auto-switch. After confirming, you must run:
  /model <model-short-name>

For opencode: switch via TAB or use /provider command.

Proceed? [Y/n]
```

## Step 4 — Update tracker

If user confirms:

```bash
jq --arg tier "$TIER" --arg model "$MODEL" --arg reason "$REASON" \
  '.active.active_tier = $tier | .active.active_model = $model | .active.switched_at = (now|todate) | .active.switch_reason = $reason |
   .history += [{"ts": (now|todate), "event": "model_switch", "tier": $tier, "model": $model, "reason": $reason}]' \
  .mina/state.json > .mina/state.json.tmp && mv .mina/state.json.tmp .mina/state.json

# Append a marker line to the change's jsonl for audit
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"model_switch\",\"from\":\"$PREV_TIER\",\"to\":\"$TIER\",\"reason\":\"$REASON\"}" \
  >> ".mina/tokens/${ACTIVE_CHANGE:-_session}.jsonl"
```

## Step 5 — Print the switch command

Final output is action-oriented:

```
✓ Recorded switch intent. Now run:

  /model <model-short-name>

Shortcuts by model:
  claude-opus-4-7    → /model opus
  claude-sonnet-4-7  → /model sonnet
  claude-haiku-4-5   → /model haiku

For BYOK / backup_provider, set ANTHROPIC_API_KEY in your shell and
restart Claude Code. Or use a gateway provider (LiteLLM, OpenRouter, TokenMix).

After switching, /mina:model-route will reflect the new active tier.
```

## Step 6 — Remind about return path

```
ℹ️ Reminder: this is a TEMPORARY switch. At the next natural break (new change,
   /clear, session restart), re-evaluate whether to return to primary tier.
   Drift to cheaper tiers degrades work quality silently if not reviewed.
```

## Special case — switching on error

If user invoked `/model-switch` due to a recent error in the session:

| Recent error | Recommended tier |
|---|---|
| 429 rate_limit_error | `backup_provider` if BYOK, else `cheap` |
| 529 overloaded_error | Stay on `primary`, retry first. If persistent, `backup_provider` |
| "rate limited" / "waiting for capacity" | `emergency` if subscription window exhausted, else `cheap` |
| Cost cap hit | `cheap` |

Surface this mapping in step 3's prompt.

## Watchouts

- This command **records intent**; it cannot programmatically change Claude Code's active model. User must run `/model` themselves.
- For opencode, switching is via TAB or `/provider` — instruct accordingly.
- If `model-routing.json` is missing entirely, ask user if they want to scaffold one from `templates/model-routing.json.example`.
- Don't switch quality tier silently mid-task. Always confirm.
- After switch, the next 1-2 turns may "feel" different — surface this to user so they know it's not Claude regressing, it's a different model.
