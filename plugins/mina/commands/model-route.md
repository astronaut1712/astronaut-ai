---
description: Show current model, recommended model for active context, and reason
argument-hint: [optional task description]
---

# Model routing recommendation

## Step 1 — Load config

```bash
CONFIG="model-routing.json"
[ ! -f "$CONFIG" ] && CONFIG="$HOME/.config/mina/model-routing.json"
[ ! -f "$CONFIG" ] && echo "No model-routing.json found. Using built-in defaults."
```

Default tiers if no config:
```json
{
  "primary": "claude-opus-4-7",
  "cheap": "claude-sonnet-4-7",
  "emergency": "claude-haiku-4-5",
  "cost_cap_usd": 5.0,
  "subagent_tier": "cheap"
}
```

## Step 2 — Gather context

Read these to decide:

1. **Active change/phase** from `.mina/state.json`
2. **Current spend on change** from `.mina/tokens/<change>.jsonl` (sum cost_usd)
3. **Session cost** — tell user to check `/cost` (don't compute)
4. **Active model** — tell user to check `/model` or read from session info
5. **OpenSpec phase signal** — if `.planning/phases/<NN>/<NN>-CONTEXT.md` exists, we're in execute phase
6. **User's task description** from `$ARGUMENTS` if provided

## Step 3 — Apply rules in order

```
IF user_arg looks like {security, payment, migration, "critical"}:
  recommend = primary
  reason = "high-stakes work — quality > cost"

ELIF cost_on_change > cost_cap_usd:
  recommend = cheap
  reason = "cost cap exceeded ($X spent on this change); finish on cheap tier"

ELIF active_phase = "execute" AND spec_has_clear_AC:
  recommend = cheap
  reason = "GSD execute phase with clear spec — Opus not needed for mechanical impl"

ELIF task_type IN {title, summary, status_update, lookup}:
  recommend = emergency
  reason = "lightweight task"

ELIF user_arg ~= {brainstorm, design, architecture, "complex"}:
  recommend = primary
  reason = "design/reasoning work"

ELSE:
  recommend = primary
  reason = "default"
```

## Step 4 — Update tracker

Write recommendation to `.mina/state.json` so statusline can flag mismatch:

```bash
jq --arg model "$RECOMMENDED" --arg reason "$REASON" \
  '.active.recommended_model = $model | .active.recommended_reason = $reason | .active.recommended_at = (now|todate)' \
  .mina/state.json > .mina/state.json.tmp && mv .mina/state.json.tmp .mina/state.json
```

## Step 5 — Report

```
Model routing — active change: feat-add-dashboard-ssr (ENG-1234)

  Current spend on this change:  $2.34
  Cost cap:                      $5.00
  Active phase:                  execute (phase 03)
  Spec has clear AC:             yes

  Recommendation:    claude-sonnet-4-7 (cheap tier)
  Reason:            GSD execute phase with clear spec — Opus not needed
                     for mechanical implementation

  To switch:
    /model sonnet                       (Claude Code, current session)
    /mina:model-switch cheap     (sets via this plugin's helper)

  Or accept current:
    Active model in this session is opus (or run /model to verify)
    No change needed if you're comfortable with the trade-off.
```

## Step 6 — Optional: subagent advisory

If user is about to spawn parallel subagents (look for recent `gsd-execute-phase` or
`/superpowers:execute-plan` mentions in session), add:

```
⚠️ Subagent advisory:
   You're about to spawn N parallel subagents. Each runs an independent context.
   Recommended: set subagent_tier = "cheap" in model-routing.json to avoid
   N × Opus cost. See model-fallback skill for examples.
```

## Watchouts

- Cost figures are local estimates, not authoritative. Surface `/cost` for the real session number.
- Don't force a switch — surface the recommendation, let the user decide.
- For security-sensitive work, the cheap tier may not be safe even if the spec is clear. Default to primary unless user explicitly accepts the trade-off.
