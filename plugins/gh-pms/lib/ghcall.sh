#!/usr/bin/env bash
# gh-pms · ghcall.sh
# Thin wrapper around the GitHub CLI for operations that the GitHub MCP can't
# handle directly (label creation, batch updates, project board management).
# Skills SHOULD prefer the MCP tools (mcp__github__*) for issue read/write.
# Use this only when MCP doesn't have the operation.
#
# Subcommands:
#   bootstrap-labels                          — create the gh-pms label set
#   set-status <issue> <from> <to>            — swap status:* labels atomically
#   ensure-label <name> <color> <description> — idempotent label create
#
# Exit non-zero on failure with a one-line message on stderr.

set -euo pipefail

CMD="${1:-}"
shift || true

ensure_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "ghcall: gh CLI not installed. Install from https://cli.github.com" >&2
    exit 127
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "ghcall: gh CLI not authenticated. Run 'gh auth login' first." >&2
    exit 1
  fi
}

ensure_label() {
  local name="$1" color="$2" desc="$3"
  gh label create "$name" --color "$color" --description "$desc" --force >/dev/null 2>&1 \
    && echo "  ✓ $name"
}

bootstrap_labels() {
  ensure_gh
  echo "Creating gh-pms labels in $(gh repo view --json nameWithOwner -q .nameWithOwner)..."

  # Type
  ensure_label "type:feature"   "0E8A16" "New functionality or enhancement"
  ensure_label "type:bug"       "D73A4A" "Defect report"
  ensure_label "type:hotfix"    "B60205" "Urgent production fix"
  ensure_label "type:chore"     "FBCA04" "Maintenance, refactor, CI work"
  ensure_label "type:plan"      "5319E7" "Multi-feature plan"
  ensure_label "type:prd"       "1D76DB" "Product requirement doc"
  ensure_label "type:testcase"  "C5DEF5" "QA test case"
  ensure_label "type:request"   "BFDADC" "Mid-flow user request, awaiting triage"

  # Status
  ensure_label "status:todo"               "FFFFFF" "Backlogged"
  ensure_label "status:in-progress"        "1F883D" "Active development"
  ensure_label "status:ready-for-testing"  "0969DA" "Code complete, awaiting QA"
  ensure_label "status:in-testing"         "8250DF" "Tests being run"
  ensure_label "status:ready-for-docs"     "9333EA" "Tests pass, awaiting docs"
  ensure_label "status:in-docs"            "A371F7" "Docs in progress"
  ensure_label "status:documented"         "3FB950" "Docs complete, awaiting review"
  ensure_label "status:in-review"          "BF8700" "PR open, awaiting user approval"
  ensure_label "status:blocked"            "CF222E" "Halted by external dependency"
  ensure_label "status:done"               "1A7F37" "Merged + verified"

  # Severity (used by bugs)
  ensure_label "severity:critical"  "B60205" "P0 — drop everything"
  ensure_label "severity:high"      "D93F0B" "P1 — fix this sprint"
  ensure_label "severity:medium"    "FBCA04" "P2 — schedule"
  ensure_label "severity:low"       "0E8A16" "P3 — nice to fix"

  # Generic services (skipped if user opted out)
  if [[ "${SKIP_SERVICES:-0}" != "1" ]]; then
    ensure_label "svc:app"      "C5DEF5" "Frontend / app code"
    ensure_label "svc:bridge"   "C5DEF5" "Backend / API"
    ensure_label "svc:studio"   "C5DEF5" "Studio / admin"
    ensure_label "svc:edge"     "C5DEF5" "Edge functions"
    ensure_label "svc:db"       "C5DEF5" "Database / migrations"
    ensure_label "svc:devops"   "C5DEF5" "CI / deploy / infra"
  fi

  echo "Done."
}

set_status() {
  ensure_gh
  local issue="$1" from="$2" to="$3"
  gh issue edit "$issue" \
    --remove-label "status:${from}" \
    --add-label    "status:${to}" >/dev/null
  echo "#${issue}: status:${from} → status:${to}"
}

case "$CMD" in
  bootstrap-labels) bootstrap_labels ;;
  set-status)       set_status "$@" ;;
  ensure-label)     ensure_gh; ensure_label "$@" ;;
  *)
    echo "Usage: $0 {bootstrap-labels|set-status <issue> <from> <to>|ensure-label <name> <color> <desc>}" >&2
    exit 64
    ;;
esac
