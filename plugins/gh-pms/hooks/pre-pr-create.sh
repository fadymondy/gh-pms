#!/usr/bin/env bash
# gh-pms · PreToolUse hook for mcp__github__create_pull_request
# Ensures every PR created via the agent has a `Closes #N` keyword in its body.
# If missing, blocks the call and tells the agent to add it.

set -euo pipefail

INPUT="$(cat)"
TOOL_INPUT="$(echo "$INPUT" | jq -r '.tool_input // {}')"
BODY="$(echo "$TOOL_INPUT" | jq -r '.body // ""')"

# Look for any of: Closes #N, Fixes #N, Resolves #N (case-insensitive)
if echo "$BODY" | grep -iE '(closes|fixes|resolves)[[:space:]]+#[0-9]+' >/dev/null 2>&1; then
  # OK — let it through
  exit 0
fi

# Block with a clear reason
cat <<EOF
{
  "decision": "block",
  "reason": "gh-pms: PR body must contain a closing keyword (Closes #N, Fixes #N, or Resolves #N) so the linked issue auto-closes on merge. Re-call create_pull_request with the keyword added to the body."
}
EOF
