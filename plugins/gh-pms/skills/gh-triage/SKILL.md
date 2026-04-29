---
name: gh-triage
description: Drain the `type:request` inbox — for each deferred user ask, decide accept-as-feature / accept-as-bug / reject / defer-again. Promotes accepted requests into real work; closes rejected ones with a documented reason. Auto-invoke when the user says "triage requests", "drain the inbox", "what's in the request queue".
---

# gh-triage

Walk the `type:request` queue and convert each item into a decision: real work, rejected, or punt for later. Closes the loop on `gh-request`'s deferred captures.

## When to use

- User says "triage requests", "drain the inbox", "review the queue"
- The request count in `gh-context` / `gh-status` is creeping up
- Pre-planning: before cutting a milestone, drain the requests so anything urgent gets folded in

## What it does

### Step 1 — List the queue

```bash
gh issue list --repo {owner}/{repo} --label type:request --state open --limit 100 \
  --json number,title,body,createdAt,labels,assignees \
  --jq 'sort_by(.createdAt)'
```

Oldest first — the longer something has sat unpromoted, the higher the priority on triage.

If the queue is empty, report `No requests to triage. ✓` and exit.

### Step 2 — For each item, ask the user

Use `AskUserQuestion` with four options. Title shown is the request body's first line, plus the days-since-filed:

```
Request #{N}: "{first line of body}"
Filed {days} days ago by @{author}.

  [a] Accept as feature → run /gh-pms:gh-feature with this body as objective
  [b] Accept as bug     → run /gh-pms:gh-bug with this body as steps_to_reproduce
  [r] Reject             → close with reason (you'll be asked for the reason)
  [d] Defer again        → leave it; increment a `Deferred` counter in the body
```

### Step 3a — Accept as feature

1. Call `/gh-pms:gh-feature` with:
   - `title` = request title (strip `[Request]` prefix if present)
   - `objective` = request body
   - `kind` = `feature` (or `chore` if the user picked that variant)
   - Severity inherited from the request's `severity:*` label if set, else default
2. Capture the new issue number `M`
3. On the original request `#N`:
   - Post a comment: `🔁 Promoted to #${M} (feature)`
   - Close as `completed` with reason "Promoted to issue #${M}"
4. Report: `✓ #${N} → #${M} (feature)`

### Step 3b — Accept as bug

Same as 3a but call `/gh-pms:gh-bug`. The request body becomes the bug's `## Actual` section; ask the user for a 1-line `## Expected` if the body doesn't already have one.

### Step 3c — Reject

1. `AskUserQuestion`: "Why are you rejecting #${N}? (free-text reason)"
2. Append a `## Rejection reason` section to the request body (or update if exists)
3. Post a comment: `❌ Rejected: ${reason}`
4. Close as `not_planned` (`gh issue close ${N} --reason "not planned"`)
5. Report: `✗ #${N} rejected — ${reason}`

### Step 3d — Defer again

1. Read the request body. Find a `## Deferred` section; if missing, add one with `1`. If present, increment.
2. Update the body via `mcp__github__issue_write` (`update_issue`).
3. Post a one-line comment: `⏸  Deferred #${N} (count: ${new_count})`. If count crosses 3, also tag with `severity:low` to surface the staleness next triage round.
4. Report: `… #${N} deferred (now ${new_count})`

### Step 4 — Repeat or stop

If the user passed `--all`, jump back to Step 2 with the next item until the queue is empty or the user picks "stop".

Otherwise, after one item: ask "Continue with next request? [yes/no/stop]" and loop or exit accordingly.

### Step 5 — Final summary

```
Triage session done.
  Accepted as feature : 2  (#42 #43)
  Accepted as bug     : 1  (#44)
  Rejected            : 3  (#21 #22 #23)
  Deferred again      : 1  (#19)
  Skipped (still open): 0
```

## Notes

- **Idempotent**: re-running on an already-empty queue is a no-op.
- **No bulk-accept**: each request gets a deliberate decision. Bulk-reject is supported via `--all` because the user keeps clicking "Reject", but there's no single-keystroke "reject everything" — that would defeat the purpose.
- The original request issue is **closed** when accepted (not deleted) so the audit trail stays. Cross-references (`#${M} promoted from #${N}`) appear in both timelines.

## Cross-skill contract

- Pairs with `/gh-pms:gh-request` (which files them) and `/gh-pms:gh-context` (which surfaces the count). Triage is the closing of the loop.
- A request with `severity:critical` should ideally never sit in the queue more than 24h — `gh-status` could flag it; `gh-triage` doesn't enforce, only reports.
