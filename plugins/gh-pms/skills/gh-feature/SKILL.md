---
name: gh-feature
description: Create a single feature/chore/hotfix/testcase issue. Sets the GitHub native Issue Type when available (org-level), falls back to `type:*` labels. Adds to the gh-pms project and the active milestone (if any). Auto-invoke when the user says "build X", "add Y", "implement Z", "refactor Q".
---

# gh-feature

Create a single issue for actionable work, using whichever native primitive is available.

## When to use

- User wants one piece of functionality built
- Work fits in one logical PR
- For bugs use `/gh-pms:gh-bug`, for multi-feature work `/gh-pms:gh-plan`

## What it does

### Step 1 — Collect inputs

Required:
- `title` (imperative)
- `objective` (1–3 sentences)
- `kind` (default `feature`; one of: feature/chore/hotfix/testcase)

Optional:
- `services` — `svc:*` labels
- `parent_feature` — required if `kind=testcase`
- `milestone` — milestone title or number to attach to (if working under a plan)
- `severity` — `critical | high | medium | low` (default: `medium`, per `workflows/default.yaml.severities.default`). Applies to every kind — a P0 feature blocking launch is meaningfully different from a polish item. Hotfixes default to `critical`. Resolved against `workflows/default.yaml.severities.values[]` so per-repo scales work.

### Step 2 — Resolve issue type (if available)

```bash
FEATURES=$(${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh detect-features)
USE_TYPES=$(echo "$FEATURES" | jq -r .issue_types)
OWNER_KIND=$(echo "$FEATURES" | jq -r .owner_kind)
```

Map `kind` → GitHub type via `workflows/default.yaml.kind_to_issue_type`:

| kind | GH type |
|---|---|
| feature | Feature |
| bug | Bug |
| hotfix | Bug (+ `priority:critical` label) |
| chore | Task |
| testcase | Task (+ `type:testcase` label) |

### Step 3 — Create the issue

Use `mcp__github__issue_write`:
- `title`: `[{Kind}] {title}`
- `body`: filled `templates/{kind}.md` (set `## Severity` to the resolved severity name)
- `labels`: always include `type:{kind}` (even when issue type is set, for at-a-glance filtering), `status:todo`, `severity:{severity}`, plus `svc:*`. Add `priority:critical` for hotfix.
- `assignees`: `[me]` if user said "I'll do this", otherwise omit

Capture the new issue number `N`.

### Step 4 — Set native issue type (if applicable)

If `USE_TYPES=true`:
```bash
NODE_ID=$(${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh issue-node-id "{owner}" "{repo}" "{N}")
TYPE_ID=$(${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh resolve-issue-type-id "{owner}" "{type_name}")
${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh set-issue-type "$NODE_ID" "$TYPE_ID"
```

### Step 5 — Attach to milestone (if under a plan)

If `milestone` provided:
```bash
M=$(${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh ensure-milestone "{title}")  # idempotent
${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh issue-set-milestone "{N}" "$M"
```

### Step 6 — Add to project (if active)

If a `gh-pms` project exists:
```bash
PN=$(...)  # from gh project list
ITEM_ID=$(${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh project-item-add "{owner}" "$PN" "https://github.com/{owner}/{repo}/issues/{N}")
${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh project-item-set-field "{owner}" "$PN" "$ITEM_ID" "Status"   "Todo"
${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh project-item-set-field "{owner}" "$PN" "$ITEM_ID" "Severity" "{Severity}"   # title-cased project value, e.g. "Medium"
${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh project-item-set-field "{owner}" "$PN" "$ITEM_ID" "Service"  "{primary_service}"
```

### Step 7 — Sub-issue link (if testcase)

If `kind=testcase`:
```
mcp__github__sub_issue_write — link {N} as sub-issue of {parent_feature}
```

### Step 8 — Report

```
{Kind} #{N} created: {title}
  Issue Type:  {Feature/Bug/Task or "label fallback: type:{kind}"}
  Status:      Todo (project field {if project} + status:todo label)
  Severity:    {severity}
  Milestone:   {title or "—"}
  Labels:      {labels list}
  URL:         https://github.com/{owner}/{repo}/issues/{N}
Next: /gh-pms:gh-current #{N} to start work
```

## Cross-skill contract

After creation, run `/gh-pms:gh-current #N` immediately unless user said "create but don't start".
