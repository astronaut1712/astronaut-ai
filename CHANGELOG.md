# Changelog

All notable changes to this plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] — 2026-05-24

### Added
- `/review` command — read-only review of uncommitted + branch diff against the active OpenSpec change. Cross-checks `openspec validate`, artifact status, task completion, spec-delta requirement coverage, and a code-review pass categorized as Bug / Security / Spec-drift / Error-handling / Test-gap / API / Performance / Style. Emits a severity-tagged report (BLOCKER / HIGH / MEDIUM / LOW) with a verdict (APPROVE / APPROVE WITH NITS / REQUEST CHANGES / BLOCK) and best-effort test signal. Supports `--staged`, `--branch`, `--since=<ref>` scopes, and resolution by change name or Jira key. Appends a `reviewed` event to `.mina/state.json` history.

### Changed
- Replaced GSD install reference `npx get-shit-done-cc@latest` → `npx @opengsd/get-shit-done-redux@latest` in `README.md`, `install.sh`, and `plugins/mina/README.md`
- Statusline OpenSpec progress now sources from `openspec status --change <name> --json` (authoritative artifact state) and falls back to a corrected `tasks.md` checkbox count. New segment `N/M art` shows artifact completion (done/total) with `!K` red marker when K artifacts are blocked; the existing `N/M tasks` segment now counts indented sub-tasks via `^[[:space:]]*- \[[ xX-]\]` instead of only top-level `^- \[`.

## [1.3.0] — 2026-05-15

### Added
- `progress-tracking` skill — aggregates OpenSpec tasks + GSD plans + git state + cost into unified view; surfaces mini-status proactively at session start and after task completion
- `process-resume` skill — maps prior sessions/changes/processes to clear resume path; covers Claude Code session resume + workflow resume + background process management
- `/status` command — comprehensive status report (active change, plan checkmarks, git, cost, alive processes, sessions); supports `--mini` 1-line and specific-change scopes
- `/resume` command — interactive picker for resumable contexts; workflow resume restores `state.json.active`; session resume prints `claude --resume <id>` command
- `/processes` command — list/prune/kill/register background processes with liveness checks via `kill -0`; cross-machine hostname filtering
- `/checkpoint` command — save/restore/list/diff named state snapshots; captures git correlation (commit/branch/dirty) without touching code
- Statusline now shows task progress (`3/7 plans` or `5/8 tasks`) and alive background process count (`⚙ 2`)
- `.mina/state.json` history array tracks all workflow events (change_started, phase_started, model_switch, resumed, restored_from_checkpoint)

### Changed (BREAKING)
- **Migrated `.tokens/` → `.mina/`** as the unified state directory:
  - `.tokens/current.json` → `.mina/state.json` (new richer schema with nested `.active.{change,phase,plan,jira_key,since,recommended_model}`, plus `sessions[]`, `background_processes[]`, `checkpoints[]`, `history[]`)
  - `.tokens/<change>.jsonl` → `.mina/tokens/<change>.jsonl`
  - `.tokens/_session-*.jsonl` → `.mina/tokens/_session-*.jsonl`
  - Existing users: rename the `.tokens/` directory manually, or let it stay (statusline writes to new path; legacy data won't be picked up but won't break)
- `statusline.sh` reads new schema (`.active.change` instead of `.change`)
- All commands writing state (`jira-to-spec`, `spec-to-plan`, `model-route`, `model-switch`) updated to new schema
- `.gitignore` template updated: `.mina/state.json` and `.mina/checkpoints/` ignored by default; `.mina/tokens/` optionally ignored (commented out so teams can choose)

### Notes
- Claude Code session JSONL path encoding can vary by version. `/resume` tries common paths and falls back to suggesting `claude --resume` without args (native picker).
- Background process tracking does NOT auto-detect dev servers — must be registered manually via `/processes --register <pid>` or by structured launch wrapping. Plugin can't intercept arbitrary `&`-backgrounded shell commands.
- Subagents (GSD/Superpowers) don't register as background processes since they're not OS-level — they're tracked via `state.json.history` events instead.

## [1.2.0] — 2026-05-14

### Added
- `model-fallback` skill — routing tiers (primary / cheap / emergency / backup_provider), decision rules for 429, 529, cost caps, subagent multipliers, high-stakes work
- `/model-route` command — recommend model based on active change, spend, phase, task description; updates `.tokens/current.json` with `recommended_model`
- `/model-switch` command — record explicit intent to switch tier with confirmation, shows what to run next, appends audit marker to change's jsonl
- `templates/model-routing.json.example` — pre-declared fallback chains, cost caps, high-stakes keywords, subagent tier override
- `templates/opencode.json.example` — multi-provider config (Anthropic + OpenRouter / LiteLLM gateway) for true provider-level fallback
- Statusline now reads `model-routing.json` and surfaces:
  - `⚠ cap $X/$Y` when spend on change exceeds `cost_cap_usd`
  - `↪ try <tier>` when active model differs from recorded recommendation

### Changed
- README: full "Model fallback / routing" section with config example, decision rules table, and caveat about native auto-fallback limitations
- Plugin description and keywords updated to surface fallback support

### Notes
- Claude Code does NOT have native model auto-fallback. `/model-switch` records intent; user must run `/model` themselves. opencode has open feature requests (#7602, #8687).
- For true automatic fallback, route through a gateway (LiteLLM, OpenRouter, TokenMix) at provider layer — see `opencode.json.example`.

## [1.1.0] — 2026-05-14

### Added
- `token-tracking` skill — defines cost-attribution conventions and points to right reporting tool
- `/token-report` command — per-change, daily, weekly, and aggregate cost reports
- `hooks/statusline.sh` — optional Claude Code statusline that:
  - Displays cost, context %, active model, and current change in terminal
  - Logs per-turn token delta to `.tokens/<change>.jsonl` for attribution
  - Computes deltas using sidecar `.last-cost-<session>` files to avoid double-counting
- `templates/settings.json.example` — wiring for the statusline hook
- `.tokens/current.json` tracker — written by `/jira-to-spec` and updated by `/spec-to-plan`
- Token cost summary in `/jira-update` comment (skipped if Jira is customer-visible)
- High-cost warnings (>$5 or >100k output tokens) flagged in reports
- Subagent multiplier warning in `token-tracking` skill

### Changed
- `/jira-to-spec` now initializes `.tokens/current.json` with the change name + Jira key
- `/spec-to-plan` now updates the tracker with phase info
- `.gitignore` adds `.tokens/` (commented for teams who want shared visibility)

## [1.0.0] — 2026-05-14

### Added
- Initial release
- Three auto-triggering skills:
  - `spec-driven-workflow` — meta-skill defining the canonical pipeline
  - `openspec-aware` — checks for existing specs before planning
  - `jira-via-acli` — Atlassian CLI fallback when MCP is unstable
- Four slash commands:
  - `/jira-pick` — list and pick Jira issues
  - `/jira-to-spec` — convert Jira issue to OpenSpec change
  - `/spec-to-plan` — bridge OpenSpec change to GSD or Superpowers plan
  - `/jira-update` — write back to Jira after implementation
- Templates for `CLAUDE.md`, Atlassian MCP config, and OpenSpec proposals
- `install.sh` for opencode and manual Claude Code install
- Marketplace structure for one-line install via `/plugin marketplace add`
