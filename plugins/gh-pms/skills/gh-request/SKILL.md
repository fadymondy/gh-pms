---
name: gh-request
description: Save a deferred user request as a `type:request` issue and continue current work. Mirrors Orchestra MCP's `create_request`. Auto-invoke when the user asks for something unrelated to the in-progress issue — captures it for later instead of dropping current flow.
---

# gh-request

Capture a mid-flow ask without losing context.

## When to use

- An issue is `status:in-progress` and the user mentions a new feature/bug
- User says "while you're at it, also...", "btw, can you also...", "after this, do X"
- The new ask is **distinct** from the current issue (otherwise just amend the current issue)

## When NOT to use

- The user is correcting your current approach → adjust, don't defer
- The user is asking a question → answer it, don't issue
- The user says "stop, drop everything" → STOP and switch focus (per Sentra Rule 5)

## What it does

1. Reads template from `${CLAUDE_PLUGIN_ROOT}/templates/request.md`
2. Substitutes `{{summary}}`, `{{context}}` (the in-progress issue # if any), `{{originator}}` (current user)
3. Calls `mcp__github__issue_write`:
   - `title`: `[Request] {summary}`
   - `body`: filled template
   - `labels`: `type:request`, `status:todo`, plus best-guess `svc:*`
4. Acknowledges to user inline:
   ```
   Saved as #{R}. I'll continue with #{current}.
   ```
5. Returns control to the in-progress flow — does NOT switch focus.

## Triage flow

When the current issue closes, the agent calls `/gh-pms:gh-status` and surfaces open `type:request` issues. The user picks one to convert (`type:request → type:feature` or `type:bug`) via re-labeling, then runs `/gh-pms:gh-current`.

## Notes

- Requests are intentionally lightweight — they're a backlog, not a commitment
- Stale requests can be closed with `wontfix` after 30 days (manual cleanup)
