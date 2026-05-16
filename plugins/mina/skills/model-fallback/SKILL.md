---
name: model-fallback
description: Use this skill whenever errors occur related to rate limits (429), overload (529), 5-hour window exhaustion, "rate limited" or "waiting for capacity" messages, or whenever context exceeds 80%, cost on a single change exceeds $5, or the user explicitly asks about switching models or fallback. Defines the project's model routing tiers and the decision rules for when to switch.
---

# Model fallback policy

This project pre-declares a fallback chain so model switching is deterministic, not ad-hoc. Read `model-routing.json` at the project root (or `templates/model-routing.json.example` for defaults).

## Tiers (typical config)

| Tier | Model | When |
|---|---|---|
| **primary** | `claude-opus-4-7` | Default. Brainstorm, design, complex reasoning, architecture |
| **cheap** | `claude-sonnet-4-7` | Code execution from clear spec, GSD subagents, refactors |
| **emergency** | `claude-haiku-4-5` | Title generation, simple lookups, when primary exhausted |
| **backup_provider** | API key (BYOK) or alt provider | When subscription 5-hour window exhausted |

## When to switch (decision rules)

### Hard triggers — switch immediately

| Trigger | Action |
|---|---|
| **429 rate_limit_error** | Subscription users: wait or invoke `/model-switch emergency`. API users: check `retry-after` header, switch to next tier if wait > 5 min |
| **529 overloaded_error** | Exponential backoff (1s, 2s, 4s, 8s); after 4 retries, switch to backup_provider |
| **5-hour window exhausted** | `/model-switch backup_provider` if BYOK configured, else wait for reset |
| **Cost on change > config.cost_cap_usd** (default $5) | Suggest `/model-switch cheap` for remaining tasks on this change |
| **Context > 80%** | Run `/clear` or `/compact` BEFORE switching model (model swap doesn't help context) |
| **Subagent spawn (>3 parallel)** | Force cheap tier per subagent — Opus × N subagents = catastrophic cost |

### Soft triggers — recommend, don't force

| Trigger | Action |
|---|---|
| Spec-driven phase = `execute` and spec has clear AC | Recommend cheap tier (Opus quality not needed for mechanical implementation) |
| Task type = title, summary, status update | Recommend emergency tier |
| Task type = security, payments, data migration | Stay on primary even if cost is high. Quality > cost here |

## Anti-patterns

- **Silent downgrade**: never switch quality tiers without surfacing it to user, especially mid-task
- **Switch then forget**: after fallback, return to primary at the next natural break (new change, /clear)
- **Switch on first 529**: 529 is server overload, usually transient. Retry first; only switch after 3-4 attempts
- **Use Haiku for spec-driven plan-phase work**: too lossy for design decisions; if Opus exhausted, prefer waiting or backup_provider

## What this skill DOES vs DOESN'T do

✅ Knows the rules, recommends, surfaces tradeoffs
✅ Reads `model-routing.json` to honor team config
✅ Updates `.mina/state.json` with `recommended_model` field
✅ Flags in statusline when active model ≠ recommended

❌ Cannot programmatically force Claude Code to switch models mid-session — user runs `/model` or `/model-switch`
❌ Cannot intercept API errors before they surface (no PreLLMCall hook in Claude Code yet)
❌ Cannot guarantee fallback succeeds — provider outages are real

## Subagent multiplier reminder

Each GSD subagent runs Opus by default = each consumes its own 200k context at $15/M input + $75/M output. A 5-subagent wave on a non-trivial phase: easily $20-50. Reports from the community: 49-subagent run = $8k-15k, 23-subagent multi-day = $47k.

Always cap subagent model to `cheap` tier in `model-routing.json` unless the task genuinely requires Opus reasoning (architecture review, novel algorithm design).

## Helpful commands

- `/model-route` — show current model, recommended model, why
- `/model-switch <tier>` — switch to a named tier with confirmation
- `/cost` — see if cost threshold is approached on current session
- `/mina:token-report <change>` — see total spend on current change

## Provider-specific notes

### Claude Code

No native fallback chain. `model` field in `settings.json` sets default; `/model` overrides for session; `ANTHROPIC_MODEL` env for launch-time override. When 429/529 hits, you must manually switch.

### opencode

Has provider abstraction. `model` field supports a single model; `small_model` for cheap tasks. Multi-model fallback is an open feature request (#7602, #8687) — for now, use a gateway (LiteLLM, OpenRouter) as the provider, configured to handle fallback upstream.

### BYOK (bring your own key)

Both runtimes support pointing at API key instead of subscription. This bypasses 5-hour windows but bills per-token. Useful as `backup_provider` tier. Set up via `ANTHROPIC_API_KEY` env var or in runtime config.
