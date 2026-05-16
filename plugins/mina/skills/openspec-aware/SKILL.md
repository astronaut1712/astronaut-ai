---
name: openspec-aware
description: Use this skill BEFORE any planning, brainstorming, write-plan, or execute-plan activity in a project that has an openspec/ directory. Checks for existing OpenSpec change proposals that match the user's request and treats them as authoritative input, preventing duplicate planning work and spec drift. Activates automatically when the user asks to plan, build, implement, or start work on a feature in a spec-driven project.
---

# OpenSpec-aware planning

OpenSpec is the spec source of truth in this project. Skip this skill ONLY if `openspec/` does not exist at the project root.

## Activation protocol

Run this skill BEFORE invoking:
- `/superpowers:brainstorm`, `/superpowers:write-plan`, `/superpowers:execute-plan`
- `/gsd-discuss-phase`, `/gsd-plan-phase`, `/gsd-execute-phase`, `/gsd-quick`
- Any general planning task in a project with `openspec/`

## Steps

### 1. List active changes

```bash
ls openspec/changes/ 2>/dev/null
# or
openspec list --active 2>/dev/null
```

If empty or directory missing, skip to step 4.

### 2. Match user request to a change

Match logic, in order:
1. **Exact name match** — user said `add-dashboard-ssr` and `openspec/changes/add-dashboard-ssr/` exists
2. **Jira key match** — user said `ENG-1234`; grep `openspec/changes/*/proposal.md` for `jira_key: ENG-1234` in frontmatter
3. **Keyword overlap** — extract nouns from request, match against change names and `proposal.md` "why" sections
4. **Capability match** — match against `specs/<capability>/` folder names

### 3. If match found

REPORT to user (do not silently proceed):

```
Found OpenSpec change matching your request:
  • <change-name>
  • Jira: <KEY if any>
  • Status: <validated/draft/in-progress>

Using this spec as input. Files I'll read:
  - openspec/changes/<name>/proposal.md
  - openspec/changes/<name>/design.md
  - openspec/changes/<name>/specs/**/*.md
  - openspec/changes/<name>/tasks.md

Proceed? [Y/n]
```

If user confirms:
- READ those files fully
- SKIP brainstorm/discuss-phase (requirements already captured)
- JUMP to write-plan (Superpowers) or plan-phase (GSD) with spec content as input
- Use `tasks.md` as the basis for plan decomposition, NOT a fresh task generation

### 4. If no match found

Ask user:

```
No OpenSpec change matches this request. Options:
  (a) Create OpenSpec proposal first (recommended for non-trivial work)
      → I'll run /jira-to-spec <KEY> if there's a Jira ticket
      → Or scaffold a fresh change with `openspec create <name>`
  (b) Plan directly without spec (quick fix / experiment)
  (c) Cancel — let me think about it first
```

Default recommendation: (a) for anything that touches >2 files or >50 lines.

### 5. After implementation

REMIND user to close the loop:

```bash
openspec validate <change-name>   # ensure tasks marked done
openspec archive <change-name>    # move changes/<name>/ → specs/
```

## Validation guardrails

Before bridging to plan, run:
```bash
openspec validate <change-name>
```

If validation fails:
- Spec is incomplete (missing scenarios, malformed delta, etc.)
- Do NOT proceed to plan — fix the spec first
- Show user the validation errors

## Anti-patterns

- ❌ Reading spec partially and asking user to "describe what they want"  — the spec already does that
- ❌ Adding tasks during execution that aren't in `tasks.md` — propose a spec update instead
- ❌ Treating `proposal.md` description as instructions to follow literally — read `specs/` for the actual behavior contract
