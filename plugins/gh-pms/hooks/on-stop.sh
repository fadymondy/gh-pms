#!/usr/bin/env bash
# gh-pms · Stop hook
# When the agent finishes a turn, surface a one-line reminder if there's
# an in-progress issue with stale activity (no transition in > 1 hour).
# Doesn't block — just prints a notice.

set -euo pipefail

STATE_FILE="${HOME}/.cache/gh-pms/state.json"
[[ -f "$STATE_FILE" ]] || exit 0

# Find any in-progress issue last touched more than 1h ago
NOW=$(date +%s)
STALE=$(jq -r --arg now "$NOW" '
  to_entries
  | map(select(.value.current_status == "in-progress"))
  | map(select(($now | tonumber) - (.value.last_transition_at | fromdateiso8601) > 3600))
  | .[].key
' "$STATE_FILE" 2>/dev/null || true)

if [[ -n "$STALE" ]]; then
  echo "gh-pms: stale in-progress issues — $(echo "$STALE" | tr '\n' ' ')" >&2
fi

exit 0
