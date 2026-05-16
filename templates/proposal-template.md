---
source:
  jira_key: PROJ-XXXX
  jira_url: https://your-org.atlassian.net/browse/PROJ-XXXX
  jira_type: Story
  jira_epic: PROJ-YYYY
  jira_priority: Medium
  jira_fix_version: 2026-Q2
  synced_at: 2026-05-14T10:00:00Z
status: draft
---

# <Title — matches Jira summary>

## Why

<Problem statement. First paragraph of Jira description, cleaned up.
If no description, write "See Jira issue for context — needs elaboration before plan.">

## What changes

<User-visible / functional changes. Derive from acceptance criteria.
- Bullet list
- Each item ≤ 1 sentence
- No implementation details (those go in design.md)>

## Impact

**Affected packages / remotes:**
- <e.g. `apps/dashboard`, `packages/ui`, `packages/tokens`>

**Affected capabilities (existing specs to update):**
- <list specs/ entries that need updating, if any>

**New capabilities:**
- <list new specs/ entries this change introduces>

**Breaking changes:**
- <list any API/contract changes; "none" if N/A>

## Out of scope

<Things the issue mentions but are explicitly deferred. Be specific.
Leave blank if unclear, but try to call this out — it prevents scope creep
during execution.>

## Rollback strategy

<For risky changes (DB migrations, contract changes, infra). Skip otherwise.>

## Open questions

<Things the spec author can't resolve alone. Tag with owners.
- [ ] @<person>: <question>>
