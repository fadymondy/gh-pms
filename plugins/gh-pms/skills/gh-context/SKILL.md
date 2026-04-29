---
name: gh-context
description: Print a compact summary of the current repo's gh-pms state — WIP for the user, open issues by status, milestone progress, recent closes, deferred requests. Auto-runs at session start so the agent picks up where the last session left off. User-invocable for an on-demand refresh.
---

# gh-context

Hand the agent a one-screen snapshot of the project so a new Claude Code session isn't blind to the issue tracker.

## When to use

- Auto-fires on `SessionStart` via `hooks/session-start.sh` — runs once per session
- User says "what's going on", "where were we", "give me context", "session refresh"
- Before any planning work where current WIP / pipeline state matters

## What it does

1. Resolves the current GitHub repo via `gh repo view`. Exits silently if not a GitHub repo or `gh` is not authenticated.
2. Calls `${CLAUDE_PLUGIN_ROOT}/lib/gh-context.sh <ttl_seconds>` — defaults to `300` (5 min cache).
3. Prints the compact summary to stdout so the harness injects it as context.

The cache lives at `~/.cache/gh-pms/context-<owner>-<repo>.json`. Hits return instantly; misses query GitHub and re-cache.

## Output shape

```
gh-pms · {owner}/{repo}

Active for @{me} (1)
  #9 [Feature] gh-context — summarize repo state at session start

Pipeline (open issues by status)
  todo:                13   #5 #6 #7
  in-progress:          1   #9
  in-review:            0
  blocked:              0

Milestones (open: 1)
  #1 v0.5 — adoption gaps   1/14 closed   no due date

Recent closes (last 7d): 2
  #2 Support severity labels across all issue kinds (not just bugs)
  #3 (PR auto-closed)

Requests (deferred): 0
```

## Forcing a refresh

The skill always re-runs the underlying script; if you want to bypass the cache explicitly:

```bash
rm -f ~/.cache/gh-pms/context-*.json
```

Or pass `0` as the TTL when calling the lib directly:

```bash
${CLAUDE_PLUGIN_ROOT}/lib/gh-context.sh 0
```

## Cross-skill contract

- `gh-status` is the deeper, interactive dashboard. `gh-context` is the lightweight session-warmup variant — use it when you only need to know "what was I doing".
- `gh-current` and `gh-advance` invalidate this cache after they transition an issue, so subsequent calls reflect the change.

## Notes

- Output is capped to ~30 lines so it doesn't dominate the conversation context.
- Empty buckets are omitted.
- Timestamps use the user's local timezone for "started Xh ago" but absolute UTC for cache freshness.
