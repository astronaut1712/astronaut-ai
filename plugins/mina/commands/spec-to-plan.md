---
description: Bridge an OpenSpec change into a GSD phase or Superpowers plan, ready for execution
argument-hint: <change-name>
---

# Bridge OpenSpec → execution plan

## Preconditions

- `openspec/changes/$ARGUMENTS/` must exist
- Change must validate cleanly: `openspec validate $ARGUMENTS`
- Either `.planning/` (GSD initialized) or Superpowers plugin must be active

If validate fails:
```
❌ Spec has validation errors. Fix the spec before planning:
<paste validate output>
```
STOP.

## Step 1 — Read the spec fully

Read in this order:
1. `openspec/changes/$ARGUMENTS/proposal.md` — why and what
2. `openspec/changes/$ARGUMENTS/design.md` — technical approach
3. `openspec/changes/$ARGUMENTS/specs/**/*.md` — behavior contracts (Given/When/Then)
4. `openspec/changes/$ARGUMENTS/tasks.md` — task breakdown

If `design.md` is empty or just placeholders → STOP and tell user to fill it. Bridging without design = subagents will improvise.

## Step 2 — Detect target execution layer

Check in order:
- If `.planning/` exists at project root → **GSD mode**
- Else if Superpowers plugin commands available (`/superpowers:write-plan`) → **Superpowers mode**
- Else → ask user which to install, abort for now

## Step 3a — GSD mode

Determine next phase number:
```bash
ls .planning/phases/ 2>/dev/null | grep -E '^[0-9]{2}-' | sort -n | tail -1
```
Next phase = last + 1, zero-padded (e.g. `03`).

Create phase directory:
```
.planning/phases/<NN>-$ARGUMENTS/
```

### Write CONTEXT file

`.planning/phases/<NN>-$ARGUMENTS/<NN>-CONTEXT.md`:

```markdown
---
source_spec: openspec/changes/$ARGUMENTS/
phase: <NN>
---

# Context for phase <NN>: $ARGUMENTS

## Goal
<paste "Why" from proposal.md>

## What changes
<paste "What changes" from proposal.md>

## Technical approach
<paste from design.md — full content, this is what subagents need most>

## Behavior contracts
<paste all specs/**/*.md content, organized by capability>

## Affected packages
<from proposal.md Impact section>

## Out of scope
<from proposal.md>
```

Keep this file under 800 lines. If spec is huge, split design into `<NN>-CONTEXT.md` (summary) + `<NN>-DESIGN-FULL.md` (detail), reference detail from plans only when needed.

### Split tasks.md into atomic plans

Read `tasks.md`. Group tasks into **plans of 2-3 tasks each** (GSD aggressive atomicity).

For each group, write `<NN>-<MM>-PLAN.md`:

```markdown
---
phase: <NN>
plan: <MM>
spec_ref: openspec/changes/$ARGUMENTS/specs/<capability>/spec.md
---

# Plan <NN>.<MM>: <short description>

## Tasks
- [ ] <task 1>
- [ ] <task 2>
- [ ] <task 3 (optional)>

## Acceptance
<copy the relevant Given/When/Then scenarios that prove this plan is done>

## Files likely touched
<list paths from design.md>

## Out of scope for this plan
<things to defer to a later plan>

## Verification
<how to test — commands to run, manual checks>
```

### Build wave graph

If multiple plans, identify dependencies:
- Plans touching the same file → sequential
- Plans on independent packages → can run in same wave (parallel)

Write to `.planning/phases/<NN>-$ARGUMENTS/<NN>-WAVES.md`:

```markdown
# Execution waves

Wave 1 (parallel):
  - <NN>-01-PLAN.md
  - <NN>-02-PLAN.md

Wave 2 (after wave 1):
  - <NN>-03-PLAN.md
```

### Update ROADMAP

```bash
# Add entry to .planning/ROADMAP.md under "Active phases"
```

### Confirm and hand off

```
✓ GSD phase <NN> ready: $ARGUMENTS
  Context: 1 file (<lines> lines)
  Plans: <N> files, <M> total tasks
  Waves: <K>

Next: /gsd-execute-phase <NN>
       (or /gsd-progress --next to auto-advance)
```

## Step 3b — Superpowers mode

Write a single plan file at `.superpowers/plans/$ARGUMENTS.md`:

```markdown
# Plan: $ARGUMENTS

## Goal
<from proposal.md "Why">

## Acceptance criteria
<from specs/ — list each scenario as a checkbox>

## Approach
<from design.md>

## Steps
<expand each task from tasks.md into 1-3 implementation steps>
<include test-first reminders where relevant — Superpowers will enforce TDD>

## Files touched
<from design.md>

## Test plan
<from design.md "Test strategy">
```

Then invoke:
```
/superpowers:execute-plan .superpowers/plans/$ARGUMENTS.md
```

Confirm with user before invoking execute.

## Step 3c — Update mina state

After phase scaffolding is done, update `.mina/state.json` so the statusline
hook and `/mina:status` attribute upcoming work to this phase:

```bash
mkdir -p .mina
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
FIRST_PLAN=$(ls .planning/phases/<NN>-$ARGUMENTS/[0-9]*-PLAN.md 2>/dev/null | head -1 | xargs basename)

if [ -f .mina/state.json ]; then
  jq --arg ch "$ARGUMENTS" --arg phase "<NN>" --arg plan "$FIRST_PLAN" --arg ts "$NOW" \
    '.active.change = $ch | .active.phase = $phase | .active.plan = $plan |
     .history += [{"ts": $ts, "event": "phase_started", "change": $ch, "phase": $phase}]' \
    .mina/state.json > .mina/state.json.tmp && mv .mina/state.json.tmp .mina/state.json
else
  jq -n --arg ch "$ARGUMENTS" --arg phase "<NN>" --arg plan "$FIRST_PLAN" --arg ts "$NOW" \
    '{
      "version": "1.3",
      "active": {"change": $ch, "phase": $phase, "plan": $plan, "jira_key": null, "since": $ts},
      "sessions": [],
      "background_processes": [],
      "checkpoints": [],
      "history": [{"ts": $ts, "event": "phase_started", "change": $ch, "phase": $phase}]
    }' > .mina/state.json
fi
```

## Step 4 — Final reminders

Print these reminders regardless of mode:

```
ℹ️ During execution:
  • If spec drift becomes necessary, STOP and propose an OpenSpec update
    (don't silently expand scope)
  • Subagents have fresh context — they will not see this conversation
    Everything they need must be in CONTEXT/PLAN files
  • After all plans complete, run:
      openspec validate $ARGUMENTS
      /jira-update $ARGUMENTS   (to close Jira loop)
      openspec archive $ARGUMENTS   (to make spec authoritative)
```

## Watchouts

- **Do not** rewrite tasks.md during this bridge — copy fidelity matters. If tasks need re-org, do it in OpenSpec first.
- **Do not** invent acceptance criteria not in `specs/`. If a plan has no clear acceptance, the spec is incomplete.
- If the spec changes after bridging, the existing plans will drift. Either abort the phase and re-bridge, or manually sync the CONTEXT file.
