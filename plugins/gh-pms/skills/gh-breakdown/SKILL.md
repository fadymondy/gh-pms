---
name: gh-breakdown
description: Break a plan issue into child feature sub-issues with dependencies. Mirrors Orchestra MCP's `breakdown_plan`. Each child becomes a real GitHub sub-issue (parent linkage via mcp__github__sub_issue_write), labeled `type:feature` (or kind specified in the breakdown), `status:todo`, and any service label. Use immediately after `/gh-pms:gh-plan` or whenever a plan needs more children.
---

# gh-breakdown

Decompose a plan into child issues using GitHub's native sub-issue feature.

## When to use

- Right after `gh-plan` creates a parent
- User says "break down the plan", "create the features for #N", "split this plan"
- A plan has fewer children than its checklist suggests

## What it does

1. Accepts a parent plan issue number (e.g. `#42`) and a JSON array of child specs:
   ```json
   [
     {"kind": "feature", "title": "Bridge endpoint", "objective": "...", "services": ["bridge"], "depends_on": []},
     {"kind": "feature", "title": "React hook", "objective": "...", "services": ["app"], "depends_on": [1]},
     {"kind": "testcase", "title": "E2E flow", "objective": "...", "services": ["app"], "depends_on": [1, 2]}
   ]
   ```
   `depends_on` references **0-based indices** within this same array. The skill resolves them to real issue numbers after creation.

2. For each child (in order):
   - Reads template from `${CLAUDE_PLUGIN_ROOT}/templates/{kind}.md`
   - Substitutes `{{title}}`, `{{objective}}`, `{{parent_plan}}`, `{{depends_on}}`
   - Calls `mcp__github__issue_write` with title `[{Kind}] {title}`, body, labels `type:{kind}`, `status:todo`, `svc:*`
   - Calls `mcp__github__sub_issue_write` to link the new issue as a sub-issue of the plan
   - Records the new issue number for `depends_on` resolution

3. Adds a "## Breakdown" section comment to the parent plan listing every child as `- [ ] #N — {title}`

4. Reports a tree:
   ```
   Plan #42 broken into 3 sub-issues:
     ├── #43 [Feature] Bridge endpoint (svc:bridge)
     ├── #44 [Feature] React hook (svc:app, depends on #43)
     └── #45 [Testcase] E2E flow (svc:app, depends on #43, #44)
   ```

## Cross-skill contract

After breakdown, the agent picks the **first child with no unmet dependencies** and runs `/gh-pms:gh-current` on it.

## Notes

- If `mcp__github__sub_issue_write` fails (older GH plans), fall back to a task-list comment on the parent: `- [ ] #43`. GitHub still cross-references it natively.
- `depends_on` is encoded in the child issue body as `**Depends on**: #43, #44` so it shows in the timeline.
