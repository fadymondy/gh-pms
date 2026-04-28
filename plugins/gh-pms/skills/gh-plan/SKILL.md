---
name: gh-plan
description: Create a multi-feature plan as a parent GitHub issue. Use when the user request would result in 3+ features, or when they explicitly say "plan X", "create a plan for Y", "design Z". Mirrors Orchestra MCP's `create_plan`. The plan issue holds the high-level objective; child feature issues come from `/gh-pms:gh-breakdown` afterward.
---

# gh-plan

Create a parent plan issue. Use this when the work spans 3+ features.

## When to use

- User says "plan X", "design Y", "let's plan how to do Z"
- A user request, on inspection, decomposes into 3 or more features
- Before any implementation in a multi-step effort

## When NOT to use

- Single bug → use `/gh-pms:gh-bug`
- Single feature → use `/gh-pms:gh-feature`
- Trivial refactor / typo / config change → no issue at all (per gh-pms taxonomy)

## What it does

1. Asks the user for the plan title and brief objective if not already clear
2. Reads the plan template from `${CLAUDE_PLUGIN_ROOT}/templates/plan.md`
3. Substitutes `{{title}}`, `{{objective}}`, `{{services}}` (if any)
4. Creates the issue via `mcp__github__issue_write` with:
   - `title`: `[Plan] {title}`
   - `body`: filled template
   - `labels`: `type:plan`, `status:todo`, plus any `svc:*` if known
5. Comments back with: `Plan #N created. Run /gh-pms:gh-breakdown #N to create the feature sub-issues.`

## Required inputs

- `title` — short, imperative ("Migrate auth flow to bridge")
- `objective` — 1–3 sentences explaining the why and outcome
- `services` (optional) — list of `svc:*` labels

If any are missing, ask the user via plain text — do NOT use AskUserQuestion for these (the user already initiated the work; it's just data collection).

## Output

```
Plan #{N} created: {title}
  Labels: type:plan, status:todo, {svc:* if any}
  URL: https://github.com/{owner}/{repo}/issues/{N}
Next: /gh-pms:gh-breakdown #{N} to add features
```

## Cross-skill contract

After creating the plan, do NOT immediately start implementation. The next step is **always** `gh-breakdown`. Tell the user this in your response.
