# astronaut-ai

A Claude Code plugin marketplace and opencode-compatible skill bundle for spec-driven development. Wires together **Jira → OpenSpec → GSD/Superpowers → code → Jira** into a single pipeline.

## Install

### Path A — Claude Code (via marketplace)

```
/plugin marketplace add astronaut1712/astronaut-ai
/plugin install mina@mina
```

Restart Claude Code. Verify with `/help` — you should see `/mina:jira-pick` and the other three commands.

### Path B — opencode (via install script)

```bash
git clone https://github.com/astronaut1712/astronaut-ai.git
cd astronaut-ai
chmod +x install.sh
./install.sh opencode           # project scope
./install.sh opencode --user    # user scope (~/.config/opencode/)
```

### Path C — Claude Code (manual, no marketplace)

If you want to edit the skills/commands directly in your project (e.g. customize for your team's stack), skip the marketplace and use the install script:

```bash
./install.sh claude-code           # project scope, into .claude/
./install.sh claude-code --user    # user scope, into ~/.claude/
./install.sh both                  # both Claude Code and opencode
```

The trade-off: manual install gives flat command names (`/jira-pick`), marketplace gives namespaced (`/mina:jira-pick`).

## Repo layout

```
astronaut-ai/
├── .claude-plugin/
│   └── marketplace.json              ← marketplace catalog
├── plugins/
│   └── mina/                         ← the plugin
│       ├── .claude-plugin/
│       │   └── plugin.json
│       ├── skills/
│       │   ├── spec-driven-workflow/
│       │   ├── openspec-aware/
│       │   ├── jira-via-acli/
│       │   ├── token-tracking/
│       │   ├── model-fallback/
│       │   ├── progress-tracking/
│       │   └── process-resume/
│       ├── commands/
│       │   ├── jira-pick.md
│       │   ├── jira-to-spec.md
│       │   ├── spec-to-plan.md
│       │   ├── jira-update.md
│       │   ├── token-report.md
│       │   ├── model-route.md
│       │   ├── model-switch.md
│       │   ├── status.md
│       │   ├── resume.md
│       │   ├── processes.md
│       │   └── checkpoint.md
│       ├── hooks/
│       │   └── statusline.sh         ← progress + cost + routing warnings
│       └── README.md
├── templates/
│   ├── CLAUDE.md.snippet
│   ├── mcp.json.example              ← Atlassian MCP config
│   ├── settings.json.example         ← Claude Code statusline wiring
│   ├── model-routing.json.example    ← model tiers + fallback chains
│   ├── opencode.json.example         ← opencode multi-provider config
│   └── proposal-template.md          ← OpenSpec proposal with Jira frontmatter
├── install.sh                        ← opencode + manual installer
├── setup-and-push.sh                 ← personalize + git init
├── README.md                         ← you are here
├── LICENSE
├── CHANGELOG.md
└── .gitignore
```

The project also expects `.mina/` to be created at runtime in your working project:

```
<your-project>/.mina/
├── state.json                        ← active change/phase/plan/sessions/processes/checkpoints/history
├── tokens/<change>.jsonl             ← per-change cost logs
└── checkpoints/<name>.json           ← named state snapshots
```

## Post-install

Required regardless of install path:

1. **Add project rules** — append `templates/CLAUDE.md.snippet` to your project's `CLAUDE.md` (Claude Code) or `AGENTS.md` (opencode)

2. **Set up Atlassian credentials**
   ```bash
   # Create API token at https://id.atlassian.com/manage-profile/security/api-tokens
   export ATLASSIAN_AUTH=$(echo -n "email@company.com:your-api-token" | base64)
   # Add to ~/.zshrc or ~/.bashrc to persist
   ```
   Then copy `templates/mcp.json.example` to `.mcp.json` at your project root.

3. **Install the runtime tools** (the plugin is glue, not the engine):
   ```bash
   npm install -g @fission-ai/openspec     # required
   npx get-shit-done-cc@latest             # if using GSD execution
   # Superpowers via /plugin in Claude Code
   brew install --cask acli                # optional Jira fallback
   ```

4. **Initialize OpenSpec in your project**:
   ```bash
   openspec init
   ```

5. **(Optional) Enable cost tracking statusline** — see the next section.

## Token / cost tracking

The plugin logs token usage per OpenSpec change so you can attribute spend to specific work, not just sessions. This is opt-in and requires a one-time statusline setup.

### Enable

Copy `templates/settings.json.example` to `~/.claude/settings.json` (user-wide) or `<project>/.claude/settings.json` (per-project). The example wires:

```json
{
  "statusLine": {
    "type": "command",
    "command": "${CLAUDE_PLUGIN_ROOT}/hooks/statusline.sh",
    "padding": 0
  }
}
```

Restart Claude Code. You'll see a statusline like:

```
🤖 opus | 💰 $0.23 | 🧠 45% | 📝 ENG-1234 feat-add-dashboard-ssr
```

### Reports

```
/mina:token-report                    # current session, points to /cost
/mina:token-report feat-add-dash-ssr  # specific change
/mina:token-report today              # all changes today
/mina:token-report week               # last 7 days
/mina:token-report ENG-1234           # resolve Jira key to change
```

The report combines `.tokens/<change>.jsonl` (per-change attribution from the hook) with ccusage daily totals (authoritative session counts) and flags high-cost changes (>$5 or >100k output tokens).

### How it works

When you run `/jira-to-spec` and `/spec-to-plan`, those commands write the active change to `.tokens/current.json`. After every assistant message, the statusline hook reads `current.json` and appends a JSONL line to `.tokens/<change>.jsonl` with the token delta and cost.

If no change is active (e.g. quick fix, exploration), token data logs to `.tokens/_session-<id>.jsonl` so nothing is lost.

### Manual fallback

If you don't enable the statusline, you can still:
- Run `/cost` in Claude Code for session totals
- Run `npx ccusage daily` for historical reports
- The `/mina:token-report` command falls back to ccusage when `.tokens/` is missing

## Model fallback / routing

When rate limits, overload errors, or cost caps hit, the plugin provides a pre-declared fallback chain so switching is deterministic, not ad-hoc.

### Configure once

Copy `templates/model-routing.json.example` to `model-routing.json` at your project root. Adjust tiers and thresholds:

```json
{
  "primary": "claude-opus-4-7",
  "cheap": "claude-sonnet-4-7",
  "emergency": "claude-haiku-4-5",
  "backup_provider": null,
  "cost_cap_usd": 5.0,
  "subagent_tier": "cheap",
  "high_stakes_keywords": ["security", "payment", "migration"]
}
```

For opencode, also copy `templates/opencode.json.example` to `opencode.json` — sets up multi-provider (Anthropic + OpenRouter / LiteLLM gateway) so fallback works at provider level too.

### Use

```
/mina:model-route                  # show recommendation for current context
/mina:model-route "auth redesign"  # recommend for upcoming task
/mina:model-switch cheap           # switch to cheap tier with confirmation
/mina:model-switch backup_provider # switch to BYOK API key
```

### Automatic warnings

If the statusline hook is enabled, it surfaces:

- `⚠ cap $5.23/$5.00` — cost on current change exceeded `cost_cap_usd`
- `↪ try sonnet` — active model doesn't match `recommended_model` set by `/model-route`

### Decision rules built in

| Trigger | Recommendation |
|---|---|
| Cost on change > `cost_cap_usd` | switch to `cheap` for remainder |
| Task touches `high_stakes_keywords` | stay on `primary` regardless of cost |
| GSD execute phase + clear AC | `cheap` tier (mechanical impl) |
| Title / summary / status update | `emergency` tier (Haiku) |
| 5+ parallel subagents about to spawn | force `subagent_tier` (default `cheap`) |
| 429 rate limit | `backup_provider` if BYOK, else `cheap` |
| 529 overload | retry primary 3-4x with backoff, then `backup_provider` |

### Important caveat

Claude Code has no native auto-fallback — the user must run `/model` themselves. opencode has open feature requests (#7602, #8687) for this. The plugin's `/model-switch` **records intent** and tells the user what to run, but cannot programmatically swap models mid-session. For true automatic fallback, route through a gateway like LiteLLM, OpenRouter, or TokenMix at the provider layer (see `opencode.json.example`).

## Progress & resume

The plugin aggregates progress from multiple sources (OpenSpec tasks, GSD plans, git, cost) into one view, and lets you pick up where you left off — even from a different machine.

### See what's going on

```
/mina:status                                  # full report
/mina:status --mini                           # 1-line summary
/mina:status feat-add-dashboard-ssr           # specific change
```

Full report shows: active change & Jira key, OpenSpec task completion, GSD plan completion with checkmarks, git branch + uncommitted state, cost spent + active model + recommendation, alive background processes, recent sessions.

The statusline also shows live progress: `📝 ENG-1234 feat-… · 3/7 plans · ⚙ 2`.

### Resume

```
/mina:resume                                  # interactive picker
/mina:resume feat-add-dashboard-ssr           # workflow resume to a change
/mina:resume abc12345                         # show how to resume a Claude Code session
```

Two kinds of resume:

1. **Workflow resume** — restores `state.json.active` pointer. Works cross-machine after `git pull`. Shows current change/phase/plan; status command gives full detail.
2. **Claude Code session resume** — prints the `claude --resume <id>` command for you to run from your shell (must run outside Claude Code).

### Background processes

Track long-running dev servers, watch builds, tunnels across sessions:

```
/mina:processes                                    # list with alive/dead status
/mina:processes --prune                            # remove dead entries
/mina:processes --register <pid> "<description>"   # track an existing PID
/mina:processes --kill <pid>                       # SIGTERM tracked PID (with confirm)
/mina:processes --restart                          # show original commands of dead procs
```

Each entry includes PID, command, hostname, start time, log path. Cross-machine state filtered.

### Checkpoints

Save named state snapshots before risky operations:

```
/mina:checkpoint before-refactor "tests pass, about to refactor MF wiring"
/mina:checkpoint --list
/mina:checkpoint --restore before-refactor
/mina:checkpoint --diff before-refactor
```

Captures `.mina/state.json` plus git commit/branch/dirty status. Code is NOT touched — checkpoint is state-only. If you `--restore` and code has moved on, plan/phase references may not match current code.

## Pipeline overview

```
┌─────────┐  /jira-pick     ┌──────────┐  /spec-to-plan   ┌─────────────┐
│  Jira   │ ───────────────▶│ OpenSpec │ ────────────────▶│ GSD or      │
│ (work)  │ /jira-to-spec   │ (specs)  │                  │ Superpowers │
└─────────┘                 └──────────┘                  └─────────────┘
     ▲                                                           │
     │ /jira-update                                              │ execute
     │                                                           ▼
     └───────────────────────────────────────────────────── code, tests, commits
```

## Forking under a different account

This repo is configured for `github.com/astronaut1712/astronaut-ai`, with marketplace name `mina`. To host it under your own account:

```bash
# Re-personalize all manifests in one shot
./setup-and-push.sh --override-user=yourgithub --override-repo=your-repo-name

# Or with custom display name and marketplace name
./setup-and-push.sh \
  --override-user=yourgithub \
  --override-name="Your Name" \
  --override-repo=your-repo-name \
  --override-marketplace=your-marketplace-name
```

The script updates `plugin.json`, `marketplace.json`, `LICENSE`, and `README.md` in place, then preps git for push.

### Three names, three jobs

| Identifier | Default | Where it appears | Job |
|---|---|---|---|
| Repo name | `astronaut-ai` | `github.com/<user>/<repo>` | GitHub repository location |
| Marketplace name | `mina` | `marketplace.json` → `name` | Suffix in `/plugin install <plugin>@<marketplace>` |
| Plugin name | `mina` | `plugin.json` → `name` | Slash command prefix `/mina:` |

These three are **independent** by design. The repo could be named anything; users install by marketplace name; commands use plugin name.

After pushing under defaults, your team installs with:

```
/plugin marketplace add yourgithub/your-repo-name
/plugin install mina@your-marketplace-name
```

## Updating the marketplace

After making changes:

```bash
git add -A
git commit -m "..."
git tag v1.2.0       # bump version in plugin.json + marketplace.json first
git push --tags
git push
```

Users refresh with:
```
/plugin marketplace update mina
```

## Submitting to the official Anthropic marketplace

Once stable, you can submit this plugin to the official directory at https://claude.ai/settings/plugins/submit. Anthropic reviews for quality and security before listing in `claude-plugins-official`.

## Verify

```
/help
```

Should show:
- `/mina:jira-pick` (or `/jira-pick` if manual install)
- `/mina:jira-to-spec`
- `/mina:spec-to-plan`
- `/mina:jira-update`

And skills active:
- `spec-driven-workflow`
- `openspec-aware`
- `jira-via-acli`

## Security notes

- **Jira content can carry prompt injection.** External reporters, customer service desks, and automated integrations can insert instructions into descriptions and comments. The bundle's skills treat Jira content as untrusted data, never as commands. Don't override this.
- **API tokens = full account access.** Never commit credentials. Use env vars or a secret manager.
- **The bundle never auto-transitions Jira status.** All write operations require explicit user confirmation.
- **IP allowlisting:** if your org restricts Atlassian Cloud by IP, MCP requests must come from allowed IPs. Coffee shop networks may be blocked.

## License

MIT — see [LICENSE](LICENSE).

## Contributing

PRs welcome. Especially for:
- Adapters for other issue trackers (Linear, GitHub Issues, Asana)
- Microfrontend-specific spec templates (Module Federation, single-spa, qiankun)
- Test fixtures for the skills (so they trigger reliably across model versions)

## Acknowledgements

- [OpenSpec](https://github.com/Fission-AI/OpenSpec) by Fission AI
- [GSD](https://github.com/gsd-build/get-shit-done) by Lex Christopherson / TACHES
- [Superpowers](https://github.com/obra/superpowers) by Jesse Vincent
- [Atlassian MCP](https://github.com/atlassian/atlassian-mcp-server)
