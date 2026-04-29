#!/usr/bin/env bash
# gh-pms · ghcall.sh
# Wrapper around the GitHub CLI for operations the GitHub MCP doesn't expose
# directly: label/project/milestone/issue-type management, batch ops, GraphQL
# fallbacks. Skills SHOULD prefer mcp__github__* for issue read/write; use this
# only when the MCP doesn't have the operation.

set -euo pipefail

CMD="${1:-}"
shift || true

# ---------- helpers ----------------------------------------------------------

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

ensure_project_scope() {
  if ! gh auth status 2>&1 | grep -q "'project'"; then
    echo "ghcall: token missing 'project' scope. Run: gh auth refresh -s project" >&2
    exit 2
  fi
}

current_repo() {
  gh repo view --json nameWithOwner -q .nameWithOwner
}

current_owner() {
  gh repo view --json owner -q .owner.login
}

owner_is_org() {
  local owner="${1:-$(current_owner)}"
  local kind
  kind=$(gh api "users/${owner}" --jq '.type' 2>/dev/null || echo "User")
  [[ "$kind" == "Organization" ]]
}

# ---------- labels (legacy fallback) ----------------------------------------

ensure_label() {
  local name="$1" color="$2" desc="$3"
  gh label create "$name" --color "$color" --description "$desc" --force >/dev/null 2>&1 \
    && echo "  ✓ $name"
}

bootstrap_labels() {
  ensure_gh
  echo "Creating gh-pms labels in $(current_repo)..."

  # Type (used as fallback if issue types not available)
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

  # Severity — read from merged config when available so per-repo
  # severity scales create the right labels. Falls back to the canonical
  # four if load-config.sh is unavailable (yq missing, etc.).
  local plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  local loader="${plugin_root}/lib/load-config.sh"
  local cfg=""
  if [[ -x "$loader" ]] && cfg=$("$loader" 0 2>/dev/null) && [[ -n "$cfg" ]]; then
    echo "$cfg" | jq -r '.severities.values[] | [.label, .description] | @tsv' \
      | while IFS=$'\t' read -r label desc; do
        [[ -n "$label" ]] || continue
        # Color tier by position in the list (deterministic)
        local color="FBCA04"
        case "$label" in
          *critical*|*blocker*|*p0*) color="B60205" ;;
          *high*|*p1*)               color="D93F0B" ;;
          *medium*|*p2*)             color="FBCA04" ;;
          *low*|*nit*|*p3*)          color="0E8A16" ;;
        esac
        ensure_label "$label" "$color" "$desc"
      done
  else
    ensure_label "severity:critical"  "B60205" "P0 — drop everything"
    ensure_label "severity:high"      "D93F0B" "P1 — fix this sprint"
    ensure_label "severity:medium"    "FBCA04" "P2 — schedule"
    ensure_label "severity:low"       "0E8A16" "P3 — nice to fix"
  fi

  # Effort — T-shirt sizing for velocity tracking
  ensure_label "effort:S"   "B7E1CD" "S — < 1 day"
  ensure_label "effort:M"   "73C997" "M — 1-3 days"
  ensure_label "effort:L"   "3FB950" "L — 3-7 days"
  ensure_label "effort:XL"  "1A7F37" "XL — > 1 week (consider breakdown)"

  # Service taxonomy — also read from merged config when present
  if [[ "${SKIP_SERVICES:-0}" != "1" ]]; then
    if [[ -n "$cfg" ]]; then
      local svc_options
      svc_options=$(echo "$cfg" | jq -r '
        (.github_features.project_fields // [])
        | map(select(.name == "Service"))
        | first.options // []
        | .[]')
      if [[ -n "$svc_options" ]]; then
        while IFS= read -r svc; do
          [[ -n "$svc" ]] || continue
          ensure_label "svc:${svc}" "C5DEF5" "Service: ${svc}"
        done <<< "$svc_options"
      else
        ensure_label "svc:app"      "C5DEF5" "Frontend / app code"
        ensure_label "svc:bridge"   "C5DEF5" "Backend / API"
        ensure_label "svc:studio"   "C5DEF5" "Studio / admin"
        ensure_label "svc:edge"     "C5DEF5" "Edge functions"
        ensure_label "svc:db"       "C5DEF5" "Database / migrations"
        ensure_label "svc:devops"   "C5DEF5" "CI / deploy / infra"
      fi
    else
      ensure_label "svc:app"      "C5DEF5" "Frontend / app code"
      ensure_label "svc:bridge"   "C5DEF5" "Backend / API"
      ensure_label "svc:studio"   "C5DEF5" "Studio / admin"
      ensure_label "svc:edge"     "C5DEF5" "Edge functions"
      ensure_label "svc:db"       "C5DEF5" "Database / migrations"
      ensure_label "svc:devops"   "C5DEF5" "CI / deploy / infra"
    fi
  fi
  echo "Done."
}

# ---------- feature detection -----------------------------------------------

# Outputs JSON: { issue_types: bool, projects_scope: bool, owner_kind: "Organization"|"User", types: [...] }
detect_features() {
  ensure_gh
  local owner repo
  repo=$(current_repo)
  owner="${repo%%/*}"

  local kind
  kind=$(gh api "users/${owner}" --jq '.type' 2>/dev/null || echo "User")

  local types_json="[]"
  local has_types=false
  if [[ "$kind" == "Organization" ]]; then
    types_json=$(gh api graphql -f query="query { organization(login: \"${owner}\") { issueTypes(first: 50) { nodes { id name color isEnabled } } } }" 2>/dev/null \
      | jq -c '.data.organization.issueTypes.nodes // []' 2>/dev/null || echo "[]")
    if [[ "$(echo "$types_json" | jq 'length')" -gt 0 ]]; then
      has_types=true
    fi
  fi

  local has_project_scope=false
  if gh auth status 2>&1 | grep -q "'project'"; then
    has_project_scope=true
  fi

  jq -n \
    --argjson issue_types "$has_types" \
    --argjson projects_scope "$has_project_scope" \
    --arg owner_kind "$kind" \
    --argjson types "$types_json" \
    '{issue_types: $issue_types, projects_scope: $projects_scope, owner_kind: $owner_kind, types: $types}'
}

# ---------- issue types ------------------------------------------------------

# Resolve issue type ID by name within an org. Output: ID or empty string.
resolve_issue_type_id() {
  local org="$1" name="$2"
  gh api graphql -f query="query { organization(login: \"${org}\") { issueTypes(first: 50) { nodes { id name } } } }" 2>/dev/null \
    | jq -r --arg n "$name" '.data.organization.issueTypes.nodes[] | select(.name == $n) | .id'
}

# Set issue type on an existing issue. Args: <issue_node_id> <issue_type_id>
set_issue_type() {
  local issue_node_id="$1" type_id="$2"
  gh api graphql -f query="mutation { updateIssue(input: { id: \"${issue_node_id}\", issueTypeId: \"${type_id}\" }) { issue { id } } }" >/dev/null
}

# Resolve issue node ID from issue number. Args: <owner> <repo> <issue_number>
issue_node_id() {
  local owner="$1" repo="$2" num="$3"
  gh api "repos/${owner}/${repo}/issues/${num}" --jq '.node_id'
}

# ---------- projects v2 ------------------------------------------------------

# Find or create a project owned by the repo's owner. Args: <project_name>
# Output: project number (e.g. "3")
ensure_project() {
  ensure_project_scope
  local name="$1"
  local owner="$(current_owner)"

  local existing
  existing=$(gh project list --owner "$owner" --format json 2>/dev/null \
    | jq -r --arg n "$name" '.projects[]? | select(.title == $n) | .number' \
    | head -1)
  if [[ -n "$existing" ]]; then
    echo "$existing"
    return 0
  fi

  local created
  created=$(gh project create --owner "$owner" --title "$name" --format json | jq -r '.number')
  echo "$created"
}

# Get project ID from number. Args: <owner> <project_number>
project_id() {
  local owner="$1" number="$2"
  gh project view "$number" --owner "$owner" --format json | jq -r '.id'
}

# Add an issue to a project. Args: <owner> <project_number> <issue_url>
project_item_add() {
  ensure_project_scope
  local owner="$1" number="$2" url="$3"
  gh project item-add "$number" --owner "$owner" --url "$url" --format json | jq -r '.id'
}

# Set a single-select field value on a project item. Args: <owner> <project_number> <item_id> <field_name> <option_name>
project_item_set_field() {
  ensure_project_scope
  local owner="$1" number="$2" item_id="$3" field_name="$4" option_name="$5"

  # Resolve project + field IDs
  local proj_id field_id option_id
  proj_id=$(project_id "$owner" "$number")
  local fields_json
  fields_json=$(gh project field-list "$number" --owner "$owner" --format json)
  field_id=$(echo "$fields_json" | jq -r --arg n "$field_name" '.fields[] | select(.name == $n) | .id')
  option_id=$(echo "$fields_json" | jq -r --arg fn "$field_name" --arg on "$option_name" '
    .fields[] | select(.name == $fn) | .options[]? | select(.name == $on) | .id')

  if [[ -z "$field_id" || -z "$option_id" ]]; then
    echo "project_item_set_field: field=$field_name option=$option_name not found" >&2
    return 1
  fi

  gh project item-edit \
    --id "$item_id" \
    --project-id "$proj_id" \
    --field-id "$field_id" \
    --single-select-option-id "$option_id" >/dev/null
}

# Ensure a single-select field exists with the given options.
# Args: <project_number> <field_name> <option1> [option2 ...]
ensure_project_field() {
  ensure_project_scope
  local number="$1" field_name="$2"
  shift 2
  local owner="$(current_owner)"

  local existing
  existing=$(gh project field-list "$number" --owner "$owner" --format json \
    | jq -r --arg n "$field_name" '.fields[] | select(.name == $n) | .id')

  if [[ -z "$existing" ]]; then
    local opts_csv
    opts_csv=$(printf "%s," "$@" | sed 's/,$//')
    gh project field-create "$number" \
      --owner "$owner" \
      --name "$field_name" \
      --data-type SINGLE_SELECT \
      --single-select-options "$opts_csv" >/dev/null
    echo "  ✓ field $field_name"
  else
    echo "  · field $field_name (exists)"
  fi
}

# ---------- milestones -------------------------------------------------------

# Create or get a milestone by title. Args: <title> [description] [due_iso]
# Output: milestone number
ensure_milestone() {
  local title="$1" desc="${2:-}" due="${3:-}"
  local repo="$(current_repo)"

  local existing
  existing=$(gh api "repos/${repo}/milestones?state=all" \
    --jq --arg t "$title" '.[] | select(.title == $t) | .number' | head -1)
  if [[ -n "$existing" ]]; then
    echo "$existing"
    return 0
  fi

  local payload
  payload=$(jq -n --arg t "$title" --arg d "$desc" --arg due "$due" \
    '{title: $t, description: $d} + (if $due == "" then {} else {due_on: $due} end)')
  gh api "repos/${repo}/milestones" --method POST --input - <<< "$payload" \
    | jq -r '.number'
}

# Attach an issue to a milestone. Args: <issue_number> <milestone_number>
issue_set_milestone() {
  local issue="$1" milestone="$2"
  local repo="$(current_repo)"
  gh api "repos/${repo}/issues/${issue}" --method PATCH \
    -f "milestone=$milestone" >/dev/null
}

close_milestone() {
  local milestone="$1"
  local repo="$(current_repo)"
  gh api "repos/${repo}/milestones/${milestone}" --method PATCH -f state=closed >/dev/null
}

# ---------- relationships ---------------------------------------------------

# Append a relationship to an issue's body. Args: <issue> <section> <target> [reason]
# Reads current body, finds or creates the section, appends "- {target}".
issue_relate() {
  local issue="$1" section="$2" target="$3" reason="${4:-}"
  local repo="$(current_repo)"

  local body
  body=$(gh issue view "$issue" --json body -q .body)

  if echo "$body" | grep -q "^## ${section}"; then
    body=$(echo "$body" | awk -v s="## ${section}" -v line="- ${target}${reason:+ — ${reason}}" '
      $0 == s { print; print line; in_sec=1; next }
      in_sec && /^## / { in_sec=0 }
      { print }
    ')
  else
    body="${body}

## ${section}
- ${target}${reason:+ — ${reason}}"
  fi

  gh issue edit "$issue" --body "$body" >/dev/null
}

# Mark an issue as duplicate of another. Closes self with reason 'not planned'.
duplicate_of() {
  local self="$1" target="$2"
  issue_relate "$self" "Duplicate of" "$target"
  gh issue close "$self" --reason "not planned" --comment "Duplicate of $target" >/dev/null
}

# ---------- status setter (preferred path) ----------------------------------

# Set a gh-pms status on an issue. Uses Project Status field if available,
# otherwise falls back to status:* labels. Updates both for visibility when
# both are configured. Args: <issue_number> <status_name (e.g. "In Progress")>
set_status() {
  local issue="$1" status_name="$2"
  local repo="$(current_repo)"
  local owner="${repo%%/*}"

  # Always update the label (cheap, visible at a glance)
  local label_status
  label_status=$(echo "$status_name" | tr '[:upper:] ' '[:lower:]-')
  local current_status_labels
  current_status_labels=$(gh issue view "$issue" --json labels --jq '.labels[].name' | grep '^status:' || true)
  if [[ -n "$current_status_labels" ]]; then
    while IFS= read -r l; do
      [[ -n "$l" ]] && gh issue edit "$issue" --remove-label "$l" >/dev/null 2>&1 || true
    done <<< "$current_status_labels"
  fi
  gh issue edit "$issue" --add-label "status:${label_status}" >/dev/null 2>&1 || true

  # Update Project Status field if a project is attached
  if gh auth status 2>&1 | grep -q "'project'"; then
    local proj_number proj_owner item_id
    proj_owner="$owner"
    proj_number=$(gh project list --owner "$proj_owner" --format json 2>/dev/null \
      | jq -r '.projects[]? | select(.title == "gh-pms") | .number' | head -1 || true)
    if [[ -n "$proj_number" ]]; then
      local issue_url="https://github.com/${repo}/issues/${issue}"
      item_id=$(gh project item-list "$proj_number" --owner "$proj_owner" --format json 2>/dev/null \
        | jq -r --arg url "$issue_url" '.items[]? | select(.content.url == $url) | .id' | head -1 || true)
      if [[ -n "$item_id" ]]; then
        project_item_set_field "$proj_owner" "$proj_number" "$item_id" "Status" "$status_name" 2>/dev/null \
          || echo "  (project Status not updated — Status field/option may be missing)" >&2
      fi
    fi
  fi

  echo "#${issue}: status → ${status_name}"
}

# ---------- legacy: explicit label-based set-status -------------------------

set_status_label() {
  ensure_gh
  local issue="$1" from="$2" to="$3"
  gh issue edit "$issue" \
    --remove-label "status:${from}" \
    --add-label    "status:${to}" >/dev/null
  echo "#${issue}: status:${from} → status:${to}"
}

# ---------- subcommand dispatch ---------------------------------------------

case "$CMD" in
  bootstrap-labels)        bootstrap_labels ;;
  detect-features)         detect_features ;;
  ensure-project)          ensure_project "$@" ;;
  ensure-project-field)    ensure_project_field "$@" ;;
  project-item-add)        project_item_add "$@" ;;
  project-item-set-field)  project_item_set_field "$@" ;;
  ensure-milestone)        ensure_milestone "$@" ;;
  issue-set-milestone)     issue_set_milestone "$@" ;;
  close-milestone)         close_milestone "$@" ;;
  set-issue-type)          set_issue_type "$@" ;;
  resolve-issue-type-id)   resolve_issue_type_id "$@" ;;
  issue-node-id)           issue_node_id "$@" ;;
  issue-relate)            issue_relate "$@" ;;
  duplicate-of)            duplicate_of "$@" ;;
  set-status)              set_status "$@" ;;
  set-status-label)        set_status_label "$@" ;;
  ensure-label)            ensure_gh; ensure_label "$@" ;;
  *)
    cat >&2 <<EOF
ghcall.sh — gh CLI helpers for gh-pms

Usage: $0 <subcommand> [args...]

Subcommands:
  bootstrap-labels                         create gh-pms label set in current repo
  detect-features                          JSON: which native primitives are available
  ensure-project <name>                    find/create org-owned project, output number
  ensure-project-field <num> <name> <opts> add single-select field
  project-item-add <owner> <num> <url>     add issue to project
  project-item-set-field <o> <n> <id> <fld> <opt>
  ensure-milestone <title> [desc] [due]    find/create milestone, output number
  issue-set-milestone <issue> <num>        attach issue to milestone
  close-milestone <num>                    close milestone
  set-issue-type <node_id> <type_id>       set native issue type via GraphQL
  resolve-issue-type-id <org> <name>       look up type ID by name
  issue-node-id <owner> <repo> <num>       get GraphQL node ID for an issue
  issue-relate <issue> <section> <target>  append "- target" to body section
  duplicate-of <self> <target>             mark dup, close self
  set-status <issue> <status_name>         update Project Status + status:* label
  set-status-label <issue> <from> <to>     swap status:* label only (legacy)
  ensure-label <name> <color> <desc>       idempotent label create
EOF
    exit 64
    ;;
esac
