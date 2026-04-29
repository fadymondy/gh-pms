---
name: gh-test-plan
description: Auto-generate `testcase` sub-issues from a feature's `## Acceptance criteria` checkboxes. QA coverage tracks the spec automatically — every unchecked criterion becomes a testcase, idempotent on re-run. Auto-invoke when the user says "generate test plan for #N", "tests for #N", "QA #N".
---

# gh-test-plan

Walk a feature's acceptance criteria and create a `testcase` sub-issue per criterion that doesn't already have one. Closes the gap between "spec exists" and "QA tracks spec".

## When to use

- A feature has been broken down (Gates 1–2 still ahead) and QA wants tracked coverage
- After a feature's acceptance criteria changed and new tests need adding
- Pre-release sweep: confirm every criterion has at least one testcase

## Inputs

```
gh-test-plan <feature-issue> [--kind unit|integration|e2e|manual] [--assignee <user>] [--dry]
```

| Flag | Default | Effect |
|---|---|---|
| `<feature-issue>` | required | Issue number of the parent feature. |
| `--kind` | `manual` | Default test type. Each generated testcase pre-checks this box in the template; user can adjust later. |
| `--assignee` | unset | Default assignee for generated testcases. |
| `--dry` | off | Print what would be created without filing anything. |

## What it does

### Step 1 — Read the feature issue

```bash
gh issue view {N} --json body,title,labels --jq '{title, body, labels}'
```

Extract:
- The `## Acceptance criteria` section (between `## Acceptance criteria` and the next `##` heading)
- Each `- [ ]` (unchecked) and `- [x]` (checked) bullet — keep the unchecked ones for testcase generation; ignore checked ones (already done means already tested per the lifecycle's gates)
- Severity inheritance: read the feature's `severity:*` label

### Step 2 — Find existing testcases (idempotency)

```bash
gh issue list --repo {owner}/{repo} --label type:testcase --state all --limit 200 \
  --search "in:title \"#{N}\"" --json number,title,body
```

For each existing testcase, parse the `## Parent feature` and `## Scenario` sections. Build a set of "already covered scenarios". A criterion is considered already covered if any existing testcase's scenario fuzzy-matches its text (case-insensitive substring + trimmed).

### Step 3 — For each uncovered criterion

Build a testcase issue:

- `title`: `[Testcase] {feature_title}: {criterion_text_truncated_to_60_chars}`
- `body`: filled `templates/testcase.md`:
  - `{{parent_feature}}` = `#{N}`
  - `{{objective}}` (Scenario) = the criterion text
  - `{{services}}` = inherited from parent
  - `{{severity}}` = inherited from parent
  - `## Test type` checks `--kind` value
- `labels`: `type:testcase`, `status:todo`, plus inherited `svc:*` and `severity:*`
- `assignee`: from `--assignee` if set; else from parent feature

Then:

- Set native Issue Type "Task" + label `type:testcase` (per `kind_to_issue_type`)
- Link as sub-issue of the parent feature via `mcp__github__sub_issue_write`
- Attach to parent's milestone if any
- Add to the gh-pms project board if active

### Step 4 — Update the parent feature

Append a one-line comment on the feature:

```
🧪 Generated 3 testcases from acceptance criteria: #M1 #M2 #M3
```

### Step 5 — Report

```
gh-test-plan for #{N}: {feature_title}
  Criteria total:        7
  Already covered:       2
  Newly created:         5  (#101, #102, #103, #104, #105)
  Default test type:     manual
  Default severity:      inherited (high)

Next: assign and run /gh-pms:gh-current on each, OR /gh-pms:gh-bulk
to set assignee/severity in batch.
```

## Cross-skill contract

- A generated testcase is a real `type:testcase` issue — it goes through Gates 1–2 (Gate 3 auto-skipped per kind), so QA's coverage is part of the lifecycle, not parallel to it.
- If a feature's `## Acceptance criteria` is edited mid-flight, re-run `gh-test-plan` to top up — idempotent.
- A criterion that gets `[x]` checked **without** a corresponding testcase being closed is a smell — `gh-status` could surface this drift. Out of scope for this skill but worth noting.

## Notes

- Out of scope: auto-running the tests (that's the test framework's job, e.g. Pest, Jest)
- Out of scope: deriving test STEPS from the criterion (the LLM could; would be unreliable; left to the user). Scenario + Expected are filled; Steps stays a stub for the engineer to fill in.
- Out of scope: tying testcase pass/fail back to the parent feature's gate evidence — Gate 2 already covers this manually via the `## Results` section.
