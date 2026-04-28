---
name: gh-breakdown
description: Break a plan (milestone + tracker issue) into child sub-issues with dependencies. Each child becomes a real GitHub sub-issue, sets its native issue type when available, attaches to the plan's milestone, and joins the gh-pms project board. Mirrors Orchestra MCP's `breakdown_plan`.
---

# gh-breakdown

Decompose a plan into child issues using GitHub's native milestone + sub-issue + project primitives.

## When to use

- Right after `gh-plan` creates a parent
- User says "break down the plan", "create the features for milestone X", "split this plan"
- A plan needs more children than its checklist suggests

## Inputs

- Tracker issue number (e.g. `#42`) — the plan's tracker
- A JSON array of child specs:
  ```json
  [
    {"kind": "feature", "title": "Bridge endpoint", "objective": "...", "services": ["bridge"], "depends_on": []},
    {"kind": "feature", "title": "React hook", "objective": "...", "services": ["app"], "depends_on": [0]},
    {"kind": "testcase", "title": "E2E flow", "objective": "...", "services": ["app"], "depends_on": [0, 1]}
  ]
  ```
  `depends_on` references **0-based indices** within this array. The skill resolves them to real issue numbers after each child is created.

## What it does

### Step 1 — Read the plan tracker

`mcp__github__issue_read` for the tracker `#42`. Pull out:
- Title (used to find the milestone)
- Labels (carry `svc:*` forward to children if not specified)

### Step 2 — Resolve the milestone

```bash
M=$(${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh ensure-milestone "{tracker_title}")
```

Idempotent — returns existing milestone number if found.

### Step 3 — Detect features once

```bash
FEATURES=$(${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh detect-features)
USE_TYPES=$(echo "$FEATURES" | jq -r .issue_types)
```

### Step 4 — For each child (in array order)

Substituting `{{title}}`, `{{objective}}`, `{{parent_plan}}`, `{{depends_on}}` (resolved to real numbers from previously-created children):

a. Create issue via `mcp__github__issue_write`:
   - `title`: `[{Kind}] {title}`
   - `body`: filled `templates/{kind}.md`
   - `labels`: `type:{kind}`, `status:todo`, `svc:*`
   - Capture new issue number

b. Set native issue type if `USE_TYPES=true` (mapping per `kind_to_issue_type` in workflows YAML)

c. Attach to milestone:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh issue-set-milestone "{N}" "$M"
   ```

d. Sub-issue link via `mcp__github__sub_issue_write`:
   - parent: tracker issue (#42)
   - child: new issue
   
   If sub-issue API fails (older repos), fall back to a task-list comment on the tracker: `- [ ] #N`.

e. Add to gh-pms project (if active) with `Status: Todo`

f. Record `index → issue_number` mapping for `depends_on` resolution

### Step 5 — Update tracker body

Append/update the `## Breakdown` section in the tracker body to list all children:

```markdown
## Breakdown
- [ ] #43 — [Feature] Bridge endpoint
- [ ] #44 — [Feature] React hook (depends on #43)
- [ ] #45 — [Testcase] E2E flow (depends on #43, #44)
```

### Step 6 — Report

```
Plan #{42} broken into {N} sub-issues, all attached to milestone #{M} "{title}":
  ├── #43 [Feature] Bridge endpoint   (svc:bridge, type:Feature, on project)
  ├── #44 [Feature] React hook        (svc:app, type:Feature, depends on #43)
  └── #45 [Testcase] E2E flow         (svc:app, type:Task, depends on #43+#44)

Milestone progress: 0% (0 of 3 closed)
Next actionable: #43 (no unmet deps) — /gh-pms:gh-current #43
```

## Cross-skill contract

The agent should pick the **first child with no unmet dependencies** and run `/gh-pms:gh-current` on it.
