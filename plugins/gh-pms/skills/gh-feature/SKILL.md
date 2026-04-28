---
name: gh-feature
description: Create a single feature/chore/hotfix/testcase issue (any kind except plan/bug/prd/request, which have their own skills). Use for one-off work that doesn't need a multi-feature plan. Auto-invoke when the user says "build X", "add Y", "implement Z", "refactor Q", "clean up W" — and the work fits in one feature.
---

# gh-feature

Create a single issue for actionable work.

## When to use

- User wants one piece of functionality built
- Work spans 1 service or fits in one logical PR
- For bugs, use `/gh-pms:gh-bug`. For multi-feature work, use `/gh-pms:gh-plan`.

## What it does

1. Determines the `kind`:
   - `feature` (default) — new functionality
   - `chore` — refactoring, cleanup, CI/build, deps
   - `hotfix` — urgent prod fix
   - `testcase` — QA test case (must specify `parent_feature`)

2. Reads template from `${CLAUDE_PLUGIN_ROOT}/templates/{kind}.md`

3. Substitutes `{{title}}`, `{{objective}}`, `{{services}}`, `{{parent_feature}}` (if testcase)

4. Calls `mcp__github__issue_write`:
   - `title`: `[{Kind}] {title}`
   - `body`: filled template
   - `labels`: `type:{kind}`, `status:todo`, `svc:*`
   - `assignees`: `[me]` if user said "I'll do this", otherwise omit

5. If kind is `testcase`, links to parent via `mcp__github__sub_issue_write`

6. Reports:
   ```
   {Kind} #{N} created: {title}
     Labels: type:{kind}, status:todo, {svc:*}
     URL: https://github.com/{owner}/{repo}/issues/{N}
   Next: /gh-pms:gh-current #{N} to start work
   ```

## Required inputs

- `title` (required)
- `objective` (required, 1–3 sentences)
- `kind` (default `feature`)
- `services` (optional)
- `parent_feature` (required iff `kind=testcase`)

If missing, ask via plain text.

## Cross-skill contract

After creation, the agent should typically run `/gh-pms:gh-current #N` immediately to set `status:in-progress` and begin work — unless the user says "create the issue but don't start yet".
