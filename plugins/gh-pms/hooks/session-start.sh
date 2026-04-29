#!/usr/bin/env bash
# gh-pms · SessionStart hook
# When a Claude Code session begins, print a compact summary of the repo's
# gh-pms state to stdout so the harness injects it as agent context.
#
# Silent in:
#   - Non-git directories
#   - Repos that haven't been bootstrapped with gh-pms (no status:* labels)
#   - Missing gh / jq / unauthenticated gh

set -euo pipefail

# Only fire inside a git work tree
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Only fire if gh-pms looks bootstrapped — quick label check, cheap
gh label list --search "status:in-progress" --limit 1 2>/dev/null \
  | grep -q "status:in-progress" || exit 0

# Run the context lib (cached 5 min). Failures are silent — no output beats
# a confusing partial summary.
"${CLAUDE_PLUGIN_ROOT}/lib/gh-context.sh" 300 2>/dev/null || true

exit 0
