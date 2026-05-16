---
name: progress-tracking
description: Use this skill whenever the user asks about progress, status, what's done, what's left, where things stand, "what was I doing", "how far along", or asks for a summary of current work. Also activates when starting a new session in a project with .mina/ state, to surface relevant context. Defines how the plugin aggregates progress across OpenSpec tasks, GSD plans, git commits, and cost data into a unified view.
---

# Progress tracking

Work progress lives in multiple files. This skill defines how to read them as one coherent view.

## Sources of truth

In order of granularity (finest → coarsest):

| Source | What it tells you |
|---|---|
| `.mina/state.json` | Active change/phase/plan/session, history events |
| `.planning/phases/<NN>/<NN>-<MM>-PLAN.md` checkboxes | Per-plan task progress (GSD mode) |
| `openspec/changes/<name>/tasks.md` checkboxes | Per-change task progress (OpenSpec) |
| `.planning/ROADMAP.md` | Phase-level status |
| `git log <branch>..HEAD` | Commits since branch start |
| `git status` | Uncommitted changes right now |
| `.mina/tokens/<change>.jsonl` | Activity timeline (cost + timestamps) |

## When to surface progress proactively

Surface a summary WITHOUT being asked when:

1. **Session start in a project with `.mina/state.json`** — show 3-5 line mini-status
2. **After completing a task** the user marked done — show updated progress %
3. **When user mentions a change/Jira key** that has stale activity — show "last active 3 days ago, 4/7 tasks done"
4. **Before risky operations** (large refactor, branch switch) — surface uncommitted work + active background processes

DON'T surface unprompted in:
- Casual conversation about non-work topics
- Direct factual questions ("what does X mean")
- When user is mid-flow and would find it disruptive

## How to compute progress %

For a change with both OpenSpec tasks AND GSD plans, use whichever is more granular:

```bash
# OpenSpec change tasks
TOTAL=$(grep -c '^- \[' openspec/changes/<change>/tasks.md)
DONE=$(grep -c '^- \[x\]' openspec/changes/<change>/tasks.md)

# GSD plans in a phase
TOTAL_PLANS=$(ls .planning/phases/<NN>-<change>/[0-9]*-PLAN.md | wc -l)
DONE_PLANS=$(grep -L '^- \[ \]' .planning/phases/<NN>-<change>/[0-9]*-PLAN.md | wc -l)
# A plan is done if it has no unchecked tasks
```

## Status output format

Comprehensive status (when asked):

```
mina status — <date>

Active change:  <name> (<JIRA-KEY>)
                Started <duration> ago · last activity <duration> ago

Progress:
  OpenSpec:     <done>/<total> tasks
  GSD phase:    <NN> (<done>/<total> plans)
    ✓ <plan>  <desc>
    ✓ <plan>  <desc>
    ⧖ <plan>  <desc>  (in progress)
    ○ <plan>  <desc>  (pending)

Git:
  Branch:       <branch>
  Commits:      <N> since branch start
  Status:       <M> modified, <K> staged

Cost:           $<X.XX> on this change (<N> requests)
Active model:   <name>
Recommended:    <name> (if differs)

Background:
  PID <pid>  <command>  (<duration> ago)
  
Last session:   <session-id>
```

Mini status (session start, after task complete):

```
📝 ENG-1234 feat-add-dashboard-ssr · 5/8 tasks · last 12m ago · $1.34
```

## Watchouts

- `tasks.md` checkboxes are not the only "done" signal — a task may be implemented but unchecked. Cross-reference with git commits since branch start.
- `.planning/ROADMAP.md` format varies by GSD version. Parse defensively; show "couldn't read roadmap" rather than wrong info.
- Background process PIDs may be stale (process died). Verify with `kill -0 <pid>` before showing as "running".
- "Last activity" timestamp from `.mina/tokens/<change>.jsonl` reflects when statusline hook last logged — if hook is disabled, this will read as old.
- Don't include sensitive content from `tasks.md` or `proposal.md` when summarizing if those files contain customer data, credentials, or untrusted Jira-derived content.
