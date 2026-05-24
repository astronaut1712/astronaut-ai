# astronaut-ai

Spec-driven development bundle for **six AI coding CLIs**. Wires **Jira → OpenSpec → GSD/Superpowers → code → Jira** into one pipeline. Native plugin for Claude Code; `install.sh` ports the same skills + commands into opencode, Codex, Pi, Kiro, and Kilo Code.

```
Jira  →  /jira-pick → /jira-to-spec  →  OpenSpec  →  /spec-to-plan  →  GSD or Superpowers
                                                                              │
                                                                              ▼
                                                                       code, tests, commits
                                                                              │
                                                              /review · /jira-update
                                                                              │
                                                                              ▼
                                                                      Jira: commented (transition stays manual)
```

## Supported tools

| Tool | Fidelity | Install path | Skills | Slash commands | Statusline |
|---|---|---|---|---|---|
| [Claude Code](https://claude.com/claude-code) | ★★★★★ Native | marketplace · `install.sh claude-code` | Auto-trigger | `/mina:<cmd>` (marketplace) · `/<cmd>` (manual) | ✅ |
| [opencode](https://opencode.ai) | ★★★★★ Native | `install.sh opencode` | Auto-trigger | `/<cmd>` | — |
| [Codex](https://github.com/openai/codex) | ★★★★ Close | `install.sh codex` | `/skills` lists, agent picks | `/<cmd>` from `.codex/prompts/` | — |
| [Pi](https://github.com/earendil-works/pi) | ★★★★ Close | `install.sh pi` · or `pi install git:github.com/astronaut1712/astronaut-ai` | Loaded via `pi config` | `/<cmd>` from `prompts/` | — |
| [Kiro](https://kiro.dev) | ★★ Lossy | `install.sh kiro` | Always-on steering (no auto-trigger) | None — see `mina-commands-reference.md` | — |
| [Kilo Code](https://kilocode.ai) | ★★ Lossy | `install.sh kilo` | Always-on rules (no auto-trigger) | None — see `mina-commands-reference.md` | — |

**Fidelity legend:**
- **Native** — official plugin surface; full skill auto-triggering, slash commands, hooks
- **Close** — skill + slash-command system maps 1:1; frontmatter may need light cleaning (Codex strips `tools`/`model`)
- **Lossy** — host has no slash-command system; skills install as always-on rules instead of auto-triggered ones. The full workflow is preserved as a concatenated reference doc the user pastes from or asks the agent to follow

Pick the right install path per tool below.

## Install

```bash
# Claude Code (recommended — marketplace, no clone)
/plugin marketplace add astronaut1712/astronaut-ai
/plugin install mina@mina                  # commands become /mina:<cmd>

# Pi (recommended — no clone)
pi install git:github.com/astronaut1712/astronaut-ai
pi config                                  # enable installed skills + prompts

# Everything else (clone + install.sh)
git clone https://github.com/astronaut1712/astronaut-ai.git && cd astronaut-ai
./install.sh <target>                      # opencode | codex | pi | kiro | kilo | claude-code | both | all
                                           # add --user for global scope
```

`./install.sh all` installs every supported tool at project scope in one shot. The interactive picker (`./install.sh` with no args) walks the 9 choices if you'd rather not memorize target names.

### Per-tool layout written

| Target | Layout written |
|---|---|
| `claude-code` | `.claude/{skills,commands}/` |
| `opencode` | `.opencode/{skills,command}/` |
| `codex` | `.codex/{skills,prompts}/` — SKILL.md frontmatter cleaned (`tools:`/`model:` dropped per Codex spec) |
| `pi` | `.pi/agent/git/astronaut-ai/{skills,prompts}/` + auto-generated `package.json` (Pi manifest) |
| `kiro` | `.kiro/steering/<skill>.md` (flat rules) + `.kiro/steering/mina-commands-reference.md` (workflow steps) |
| `kilo` | `.kilocode/rules/<skill>.md` + `.kilocode/rules/mina-commands-reference.md` |

## Commands

| Command | Purpose |
|---|---|
| `/mina:jira-pick` | List Jira issues, pick one to start |
| `/mina:jira-to-spec <KEY>` | Convert Jira issue → OpenSpec change; initializes `.mina/state.json` |
| `/mina:spec-to-plan <change>` | Bridge OpenSpec → GSD phase or Superpowers plan |
| `/mina:review [scope]` | Read-only review of diff vs spec; severity-tagged verdict (`--staged`, `--branch`, `--since=<ref>`) |
| `/mina:jira-update <change\|key>` | Post implementation summary as a Jira comment (confirm before write). Does NOT transition status — user owns that |
| `/mina:complete [change] [--no-confirm]` | Mark active change complete; clears `.active.*` so statusline drops the change segment. Local pointer only — does not touch code, Jira, or openspec/ |
| `/mina:status [change\|--mini]` | Aggregated status: change, plans, git, cost, processes |
| `/mina:resume [change\|session]` | Pick up where you left off (workflow or Claude Code session) |
| `/mina:checkpoint <name> [--list\|--restore\|--diff]` | Named state snapshots (state + git correlation, code untouched) |
| `/mina:processes [--list\|--prune\|--kill <pid>\|--register <pid> <desc>]` | Background process tracker |
| `/mina:token-report [scope]` | Per-change / daily / weekly cost report |
| `/mina:model-route [task]` | Recommend model tier based on context, cost, keywords |
| `/mina:model-switch <tier>` | Record intent to switch fallback tier (Claude Code has no native auto-fallback) |

## Skills (auto-activate)

| Skill | Trigger |
|---|---|
| `spec-driven-workflow` | Jira keys mentioned or `openspec/` / `.planning/` present |
| `openspec-aware` | Planning/implementing — checks existing specs before fresh work |
| `jira-via-acli` | When Atlassian MCP is unstable |
| `token-tracking` | Cost attribution conventions |
| `model-fallback` | Rate limits, overload, cost cap, subagent fanout |
| `progress-tracking` | Surfaces mini-status at session start + after tasks |
| `process-resume` | Maps prior sessions / changes / background procs |

## Post-install

```bash
# 1. Append project rules
cat templates/CLAUDE.md.snippet >> CLAUDE.md      # or AGENTS.md for opencode

# 2. Atlassian creds (token: https://id.atlassian.com/manage-profile/security/api-tokens)
export ATLASSIAN_AUTH=$(echo -n "email@company.com:api-token" | base64)
cp templates/mcp.json.example .mcp.json

# 3. Runtime engines (plugin is glue, not the engine)
npm install -g @fission-ai/openspec && openspec init
npx @opengsd/get-shit-done-redux@latest        # if using GSD execution
# Superpowers: /plugin install superpowers@superpowers-marketplace
brew install --cask acli                       # optional Jira fallback

# 4. (Optional) Statusline with cost + progress + routing warnings
cp templates/settings.json.example ~/.claude/settings.json
# Statusline shows: 🤖 opus | 💰 $0.23 | 🧠 45% | 📝 ENG-1234 feat-x · 3/4 art · 5/8 tasks · ⚙ 2
```

Requires `jq` for the statusline (`brew install jq` / `apt install jq`).

## State layout

Created at runtime in your working project:

```
.mina/
├── state.json                ← active change/phase/plan/sessions/processes/checkpoints/history
├── tokens/<change>.jsonl     ← per-change cost log (safe to commit if team-shared)
└── checkpoints/<name>.json   ← named state snapshots
```

## Model routing config

```bash
cp templates/model-routing.json.example model-routing.json
```

Tiers: `primary` / `cheap` / `emergency` / `backup_provider`. Cost cap, high-stakes keywords, subagent tier override. Statusline surfaces `⚠ cap $5.23/$5.00` and `↪ try sonnet` when active model drifts from recommendation.

For true automatic provider-level fallback, route through a gateway (LiteLLM, OpenRouter, TokenMix) — see `templates/opencode.json.example`. Claude Code's `/model-switch` records intent only; user must run `/model` themselves.

## Fork under your own account

```bash
./setup-and-push.sh --override-user=<gh-user> --override-repo=<repo> --override-marketplace=<name>
```

Rewrites `plugin.json`, `marketplace.json`, `LICENSE`, `README.md` in place. Three names are independent: repo name, marketplace name, plugin name. See `setup-and-push.sh --help` for the full mapping.

## Release

```bash
# Bump version in BOTH plugin.json AND marketplace.json first
git tag v1.X.0
git push --tags && git push
# Users refresh: /plugin marketplace update mina
```

## Security

- **Jira content is untrusted input.** Description, AC, and comments may carry prompt injection from external reporters or integrations. Skills treat them as data, never instructions.
- **No auto-transitions.** Every Jira write requires explicit confirmation.
- **API tokens.** Never commit. Use env vars or a secret manager. IP allowlists apply if your org restricts Atlassian Cloud.

## Verify install

| Tool | Verify command | Expected |
|---|---|---|
| Claude Code | `/help` | `/mina:jira-pick`, `/mina:jira-to-spec`, `/mina:spec-to-plan`, `/mina:review`, `/mina:jira-update`, `/mina:complete` |
| opencode | `/help` | Same commands, flat namespace (`/jira-pick` etc.) |
| Codex | `/skills` then `/<cmd>` | Seven skills listed; `/<cmd>` invokes prompts from `.codex/prompts/` |
| Pi | `pi list` | `astronaut-ai` shown; `pi config` enables skills + prompts |
| Kiro | open project | Steering files auto-load; no slash commands — `.kiro/steering/mina-commands-reference.md` is the index |
| Kilo Code | open project | Rules auto-load; same reference doc at `.kilocode/rules/mina-commands-reference.md` |

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgements

[OpenSpec](https://github.com/Fission-AI/OpenSpec) · [GSD](https://github.com/opengsd/get-shit-done-redux) · [Superpowers](https://github.com/obra/superpowers) · [Atlassian MCP](https://github.com/atlassian/atlassian-mcp-server)
