---
name: gh-bug
description: File a bug report — sets GitHub native Issue Type "Bug" when available, falls back to `type:bug` label. Adds severity field/label, links related feature, attaches to active project. Mirrors Orchestra MCP's `create_bug_report`. Bugs auto-skip Gate 3 (docs).
---

# gh-bug

Create a bug-report issue with whichever GitHub primitives are available.

## When to use

- User reports a defect
- Regression found in testing
- Post-merge unexpected behavior

## What it does

### Step 1 — Collect inputs

Required:
- `title` — what's broken
- `steps_to_reproduce` — bullet list
- `expected` — what should happen
- `actual` — what happens

Optional:
- `services` — `svc:*` labels
- `severity` — resolved against `workflows/default.yaml.severities.values[]`. Defaults to that file's `severities.default` (`medium` out of the box). Same scale used by `gh-feature` and `gh-task` — bugs no longer own a private severity definition.
- `related_feature` — original feature issue number if regression

### Step 2 — Detect features

```bash
FEATURES=$(${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh detect-features)
USE_TYPES=$(echo "$FEATURES" | jq -r .issue_types)
```

### Step 3 — Create issue

Use `mcp__github__issue_write`:
- `title`: `[Bug] {title}`
- `body`: filled `templates/bug.md`
- `labels`: `type:bug`, `status:todo`, `severity:{severity}`, `svc:*`
- Capture issue number `N`

### Step 4 — Set native issue type

If `USE_TYPES=true`:
```bash
NODE_ID=$(${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh issue-node-id "{owner}" "{repo}" "{N}")
TYPE_ID=$(${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh resolve-issue-type-id "{owner}" "Bug")
${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh set-issue-type "$NODE_ID" "$TYPE_ID"
```

### Step 5 — Add to project + set fields

If project exists, add to it and set:
- `Status` → `Todo`
- `Severity` → match input
- `Service` → primary service

### Step 6 — Link related feature

If `related_feature`:
- Comment on original feature: `Regression filed: #{N}`
- Use `/gh-pms:gh-relate` (or `${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh issue-relate`):
  ```bash
  ${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh issue-relate "{N}" "Related to" "#{related_feature}"
  ```

### Step 7 — Report

```
Bug #{N} created: {title}
  Issue Type:  Bug (or "label fallback: type:bug")
  Severity:    {severity}
  Related to:  #{related_feature or "—"}
  URL:         https://github.com/{owner}/{repo}/issues/{N}
Next: /gh-pms:gh-current #{N} to start fixing
```

## Cross-skill contract

Bug → `gh-current` → fix → `gh-advance` Gate 1 → tests → Gate 2 → **Gate 3 auto-skipped** → `gh-review` Gate 4 → user approves → done.
