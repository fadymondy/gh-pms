#!/usr/bin/env bash
# gh-pms · gh-context.sh
# Produce a compact snapshot of the current repo's gh-pms state for agent context.
# Cached at ~/.cache/gh-pms/context-<owner>-<repo>.json with a TTL.
#
# Usage:
#   gh-context.sh [ttl_seconds]
#   ttl_seconds defaults to 300; pass 0 to force a refresh.

set -euo pipefail

CACHE_TTL="${1:-300}"
CACHE_DIR="${HOME}/.cache/gh-pms"
mkdir -p "$CACHE_DIR"

# ---------- preconditions ----------------------------------------------------

command -v gh >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0
gh auth status >/dev/null 2>&1 || exit 0

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || exit 0
[[ -n "$REPO" ]] || exit 0

CACHE_FILE="${CACHE_DIR}/context-${REPO//\//-}.json"

# ---------- portable date helpers (BSD/macOS + GNU/Linux) --------------------

iso_to_epoch() {
  local iso="$1"
  date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null \
    || date -u -d "$iso" +%s 2>/dev/null \
    || echo 0
}

days_ago_iso_date() {
  local n="$1"
  date -u -v-"${n}"d +"%Y-%m-%d" 2>/dev/null \
    || date -u -d "-${n} days" +"%Y-%m-%d"
}

now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
now_epoch() { date +%s; }

# ---------- cache hit --------------------------------------------------------

if (( CACHE_TTL > 0 )) && [[ -f "$CACHE_FILE" ]]; then
  GENERATED=$(jq -r '.generated_at // empty' "$CACHE_FILE" 2>/dev/null || echo "")
  if [[ -n "$GENERATED" ]]; then
    AGE=$(( $(now_epoch) - $(iso_to_epoch "$GENERATED") ))
    if (( AGE < CACHE_TTL )); then
      jq -r '.summary' "$CACHE_FILE"
      exit 0
    fi
  fi
fi

# ---------- gather data ------------------------------------------------------

ME=$(gh api user --jq '.login' 2>/dev/null || echo "")
[[ -n "$ME" ]] || exit 0

ISSUES_JSON=$(gh issue list --repo "$REPO" --state open --limit 200 \
  --json number,title,labels,assignees,milestone,createdAt,url 2>/dev/null || echo "[]")

WIP=$(echo "$ISSUES_JSON" | jq --arg me "$ME" '
  [.[] | select((.assignees // []) | map(.login) | index($me))
        | select((.labels // []) | map(.name) | index("status:in-progress"))]')
WIP_COUNT=$(echo "$WIP" | jq 'length')

count_with_label() {
  echo "$ISSUES_JSON" | jq --arg s "$1" '[.[] | select((.labels // []) | map(.name) | index($s))] | length'
}
top3_with_label() {
  echo "$ISSUES_JSON" | jq -r --arg s "$1" '
    [.[] | select((.labels // []) | map(.name) | index($s)) | .number]
    | .[0:3]
    | map("#\(.)")
    | join(" ")'
}

SEVEN_AGO=$(days_ago_iso_date 7)
RECENT_CLOSED=$(gh issue list --repo "$REPO" --state closed --search "closed:>$SEVEN_AGO" \
  --limit 20 --json number,title,closedAt 2>/dev/null || echo "[]")
RECENT_COUNT=$(echo "$RECENT_CLOSED" | jq 'length')

MILESTONES=$(gh api "repos/$REPO/milestones?state=open" 2>/dev/null || echo "[]")
MS_COUNT=$(echo "$MILESTONES" | jq 'length')

REQ_COUNT=$(count_with_label "type:request")

# ---------- assemble summary -------------------------------------------------

SUMMARY=$(
  echo "gh-pms · ${REPO}"
  echo

  if (( WIP_COUNT > 0 )); then
    echo "Active for @${ME} (${WIP_COUNT})"
    echo "$WIP" | jq -r '.[] | "  #\(.number) \(.title)"' | head -5
    echo
  fi

  echo "Pipeline (open issues by status)"
  for s in todo in-progress ready-for-testing in-testing ready-for-docs in-docs documented in-review blocked; do
    c=$(count_with_label "status:$s")
    if (( c > 0 )); then
      printf "  %-22s %3d   %s\n" "${s}:" "$c" "$(top3_with_label "status:$s")"
    fi
  done
  echo

  if (( MS_COUNT > 0 )); then
    echo "Milestones (open: ${MS_COUNT})"
    echo "$MILESTONES" | jq -r '.[] | "  #\(.number) \(.title)   \(.closed_issues)/\(.open_issues + .closed_issues) closed   \(.due_on // "no due date")"' | head -5
    echo
  fi

  echo "Recent closes (last 7d): ${RECENT_COUNT}"
  if (( RECENT_COUNT > 0 )); then
    echo "$RECENT_CLOSED" | jq -r '.[] | "  #\(.number) \(.title)"' | head -5
    echo
  fi

  echo "Requests (deferred): ${REQ_COUNT}"
)

# ---------- cache + emit -----------------------------------------------------

jq -n --arg s "$SUMMARY" --arg t "$(now_iso)" \
  '{summary: $s, generated_at: $t}' > "$CACHE_FILE"

echo "$SUMMARY"
