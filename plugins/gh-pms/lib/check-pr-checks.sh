#!/usr/bin/env bash
# gh-pms · check-pr-checks.sh
# Verify that a PR's required checks are passing. Exits 0 if all green
# (or skipped/neutral), 1 with a human-readable failure list otherwise.
#
# Usage:
#   check-pr-checks.sh <pr-number-or-url>
#
# Output (exit 1):
#   gh-pms: Gate 4 refuses — failing checks on PR #<N>:
#     ✗ <check-name>     <conclusion>     <details_url>
#   To override (records the reason in the gate evidence comment):
#     gh-advance --ignore-checks "explanation"

set -euo pipefail

PR="${1:?usage: check-pr-checks.sh <pr-number-or-url>}"

command -v gh >/dev/null 2>&1 || { echo "check-pr-checks: gh required" >&2; exit 127; }
command -v jq >/dev/null 2>&1 || { echo "check-pr-checks: jq required" >&2; exit 127; }

CHECKS=$(gh pr view "$PR" --json statusCheckRollup -q '.statusCheckRollup' 2>/dev/null || echo "[]")
[[ -n "$CHECKS" && "$CHECKS" != "null" ]] || CHECKS="[]"

FAILING=$(echo "$CHECKS" | jq -r '
  [ .[]
    | select(.__typename == "CheckRun" and .status == "COMPLETED")
    | select(.conclusion != "SUCCESS" and .conclusion != "SKIPPED" and .conclusion != "NEUTRAL")
  ]')

PENDING=$(echo "$CHECKS" | jq -r '
  [ .[]
    | select(.__typename == "CheckRun" and .status != "COMPLETED")
  ]')

FAIL_COUNT=$(echo "$FAILING" | jq 'length')
PEND_COUNT=$(echo "$PENDING" | jq 'length')

if (( FAIL_COUNT == 0 && PEND_COUNT == 0 )); then
  exit 0
fi

echo "gh-pms: Gate 4 refuses — PR #${PR} checks not all green"
if (( FAIL_COUNT > 0 )); then
  echo "  Failing:"
  echo "$FAILING" | jq -r '.[] | "    ✗ \(.name)\t\(.conclusion // "?")\t\(.detailsUrl // "")"' | column -ts $'\t'
fi
if (( PEND_COUNT > 0 )); then
  echo "  Pending (not yet finished):"
  echo "$PENDING" | jq -r '.[] | "    … \(.name)\t\(.status)\t\(.detailsUrl // "")"' | column -ts $'\t'
  echo "  Wait for these to finish, then re-run."
fi
echo
echo "To override (records the reason in the gate evidence comment):"
echo "  gh-advance #N --ignore-checks \"<short reason — e.g. 'flaky linter, see thread'>\""
exit 1
