---
description: Update the linked Jira issue after implementation completes
argument-hint: <change-name or jira-key>
---

# Close the Jira loop

## Step 1 — Resolve to Jira key

If `$ARGUMENTS` matches a Jira key pattern (`[A-Z]+-\d+`):
- Use directly as key

Else treat as OpenSpec change name:
- Read `openspec/changes/$ARGUMENTS/proposal.md`
- Extract `jira_key` from YAML frontmatter
- If not found → ask user for the key

If neither path works → abort with helpful message.

## Step 2 — Gather artifacts

Run these in the project root:

```bash
# Current branch
BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Commits since branched from main/master
git log --oneline main..HEAD 2>/dev/null || git log --oneline master..HEAD

# Files changed
git diff --stat main..HEAD 2>/dev/null || git diff --stat master..HEAD

# Test status (project-specific — try common commands)
# Adapt this based on the project's package.json / Makefile / etc.
```

For the project's monorepo (Turborepo/Nx), prefer:
```bash
pnpm turbo run test --filter='[main..HEAD]'
# or
nx affected --target=test --base=main
```

Capture results as a summary, not full output.

## Step 3 — Check spec status

```bash
openspec validate <change-name>
```

If tasks.md still has unchecked items → warn user:
```
⚠️ tasks.md has incomplete items:
  - [ ] <task>
  - [ ] <task>
Continue with Jira update anyway? [y/N]
```

## Step 4 — Compose comment

Pull token totals if available:

```bash
if [ -f ".mina/tokens/<change-name>.jsonl" ]; then
  jq -s '{
    requests: length,
    cost: (map(.cost_usd) | add // 0),
    input: (map(.input) | add // 0),
    output: (map(.output) | add // 0)
  }' ".mina/tokens/<change-name>.jsonl"
fi
```

Use this template (mobile-friendly, concise — Jira PMs read on phones too):

```markdown
🤖 Implementation complete via OpenSpec change `<change-name>`

**Summary**
<one-line summary from proposal.md>

**Changes**
- Branch: `<branch>`
- Files: <N> changed
- Commits: <M>

**Tests**
<pass/fail summary, 1-2 lines max>

**Spec**
`openspec/changes/<change-name>/`
All acceptance scenarios met: <yes/partial — list partial if any>

**Cost** _(if .mina/tokens/ available)_
<N> requests, ~$<X.XX> in tokens

Ready for review.
```

If cost was unusually high (>$5 or >100k output tokens), include a brief
note about why (e.g. "spawned 8 parallel subagents for refactor").
DO NOT include cost data if Jira is customer-visible (service desk tickets).

## Step 5 — Confirm before write

Show the user the composed comment. NEVER auto-execute.

```
About to update <KEY>:

1. Add comment:
   <show the comment>

Proceed? [Y/n/edit]
```

If user picks "edit" — let them rewrite the comment.

No status transition is offered or executed. Transitioning is a workflow
trigger (SLA timers, auto-assign, deployment pipelines, customer comms) that
shouldn't fire from a documentation-style command. If the user wants to
transition, they do it themselves in Jira or via `acli jira workitem
transition <KEY> --status <status>` (syntax in the `jira-via-acli` skill).

## Step 6 — Post the comment

Try Atlassian MCP first (`jira_add_comment`). Fall back to acli:

```bash
# Comment (use file for multi-line; mktemp to avoid /tmp race)
TMP=$(mktemp -t mina-jira-comment-XXXX) || exit 1
printf '%s\n' "<comment-text>" > "$TMP"
acli jira workitem comment <KEY> --body-file "$TMP"
rm -f "$TMP"
```

Do NOT call `acli jira workitem transition` — explicitly out of scope.

## Step 7 — Suggest archival

```
✓ <KEY> updated.
  Comment: posted
  (Status unchanged — transition manually in Jira if needed)

Next:
  openspec archive <change-name>
  → moves openspec/changes/<change-name>/ → openspec/specs/
  → makes the spec authoritative for future reference

Archive now? [y/N]
```

## Watchouts

- **Do not transition status from this command.** Transition is a workflow trigger (SLA timers, auto-assign, deployment pipelines, customer comms). The user owns that decision.
- **Don't** include token output, full file diffs, or test logs in the comment — keep it under 1KB
- **Don't** mention internal-only paths or secrets in the comment if Jira is visible to customers
- If on a service desk ticket, the comment is visible to the customer — phrase accordingly (no internal jargon, no sub-task chatter)
- The Atlassian MCP server can silently truncate long comments — if comment is >2KB, write it to a description update or wiki link instead
