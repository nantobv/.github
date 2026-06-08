#!/usr/bin/env bash
# Apply nantobv org-wide policy: custom properties + production ruleset.
#
# Idempotent — safe to re-run. Reads the ruleset JSON from rulesets/ and
# injects the dynamic repository_id for the `workflows` rule that requires
# nantobv/.github's pinact-check workflow.
#
# Usage:
#   ORG=nantobv ./scripts/apply-org-policy.sh
#
# Requires:
#   - gh CLI authenticated as an org owner (gh auth login)
#   - jq

set -euo pipefail

ORG="${ORG:-nantobv}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULESET_JSON="${SCRIPT_DIR}/rulesets/production.json"
DOT_GITHUB_REPO=".github"

for cmd in gh jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: $cmd not installed" >&2
    exit 1
  fi
done

if ! gh auth status >/dev/null 2>&1; then
  echo "error: gh is not authenticated. Run: gh auth login" >&2
  exit 1
fi

echo "==> Target org: ${ORG}"

# ---------------------------------------------------------------------------
# 1. Custom properties
# ---------------------------------------------------------------------------
echo "==> Custom properties"

upsert_property() {
  local name="$1"
  local description="$2"
  shift 2
  local allowed_values_json
  allowed_values_json=$(printf '%s\n' "$@" | jq -R . | jq -s .)

  jq -n \
    --arg description "$description" \
    --argjson allowed_values "$allowed_values_json" \
    '{
      value_type: "single_select",
      required: false,
      description: $description,
      allowed_values: $allowed_values
    }' \
    | gh api --method PUT "orgs/${ORG}/properties/schema/${name}" --input - >/dev/null

  echo "    - ${name}: ${allowed_values_json}"
}

upsert_property "language" \
  "Primary language for this repo (drives required CI workflow selection)" \
  "go" "rust" "python" "mixed" "none"

upsert_property "tier" \
  "Maturity tier (drives ruleset strictness)" \
  "production" "internal" "experiment" "archived"

# ---------------------------------------------------------------------------
# 2. Rulesets
# ---------------------------------------------------------------------------

# Find an org ruleset by name (empty if absent), then PUT (update) or POST
# (create) the given JSON payload. Idempotent.
upsert_ruleset() {
  local name="$1"
  local payload="$2"
  local existing_id
  existing_id=$(gh api --paginate "orgs/${ORG}/rulesets" \
    --jq ".[] | select(.name==\"${name}\") | .id" | head -n1 || true)

  if [ -n "$existing_id" ]; then
    printf '%s' "$payload" \
      | gh api --method PUT "orgs/${ORG}/rulesets/${existing_id}" --input - >/dev/null
    echo "    - updated ${name} (id=${existing_id})"
  else
    printf '%s' "$payload" \
      | gh api --method POST "orgs/${ORG}/rulesets" --input - >/dev/null
    echo "    - created ${name}"
  fi
}

# nantobv/.github's numeric repo id, needed by every `workflows` rule.
dot_github_repo_id=$(gh api "repos/${ORG}/${DOT_GITHUB_REPO}" --jq .id)

# --- 2a. production-main: branch protection for every tier=production repo ---
echo "==> Ruleset: production-main"

# Optional: inject a `workflows` rule that requires a named workflow file
# from nantobv/.github@main to pass before merge. Off by default because
# it requires the target workflow file to (a) exist on `main` at apply
# time, and (b) have one of pull_request / pull_request_target /
# merge_queue triggers — a reusable (workflow_call-only) workflow is
# rejected by the API with HTTP 422. Enable once a non-reusable wrapper
# (e.g. required-pinact-check.yml) is on main.
#
#   REQUIRED_WORKFLOW_PATH=.github/workflows/required-pinact-check.yml \
#     ./scripts/apply-org-policy.sh
REQUIRED_WORKFLOW_PATH="${REQUIRED_WORKFLOW_PATH:-}"

if [ -n "$REQUIRED_WORKFLOW_PATH" ]; then
  echo "    - injecting required workflow: ${DOT_GITHUB_REPO}/${REQUIRED_WORKFLOW_PATH}@main"
  ruleset_payload=$(jq \
    --argjson repo_id "$dot_github_repo_id" \
    --arg path "$REQUIRED_WORKFLOW_PATH" \
    '.rules += [{
      type: "workflows",
      parameters: {
        workflows: [{
          repository_id: $repo_id,
          path: $path,
          ref: "refs/heads/main"
        }]
      }
    }]' \
    "$RULESET_JSON")
else
  ruleset_payload=$(cat "$RULESET_JSON")
fi

upsert_ruleset "production-main" "$ruleset_payload"

# --- 2b. production-<lang>-ci: require org-default CI per language ----------
#
# Branch protection (production-main) only requires *a* PR; on its own it
# lets a red build merge. These rulesets add a `workflows` rule that gates
# merge on the matching required-<lang>-ci.yml wrapper, scoped to repos
# tagged BOTH tier=production AND language=<lang> (repository_property
# includes are ANDed). A python repo never has Go CI forced on it.
#
# Prerequisite: the required-<lang>-ci.yml wrappers must already be on
# nantobv/.github@main, or the API rejects the `workflows` rule with 422.
# Skip this block while bootstrapping with: APPLY_REQUIRED_CI=false
APPLY_REQUIRED_CI="${APPLY_REQUIRED_CI:-true}"

if [ "$APPLY_REQUIRED_CI" = "true" ]; then
  echo "==> Rulesets: production-<lang>-ci (required CI gates)"
  for entry in \
    "go:.github/workflows/required-go-ci.yml" \
    "python:.github/workflows/required-python-ci.yml" \
    "rust:.github/workflows/required-rust-ci.yml"; do
    lang="${entry%%:*}"
    wrapper="${entry#*:}"
    payload=$(jq -n \
      --arg name "production-${lang}-ci" \
      --arg lang "$lang" \
      --argjson repo_id "$dot_github_repo_id" \
      --arg path "$wrapper" \
      '{
        name: $name,
        target: "branch",
        enforcement: "active",
        conditions: {
          ref_name: { include: ["~DEFAULT_BRANCH"], exclude: [] },
          repository_property: {
            include: [
              { name: "tier", property_values: ["production"] },
              { name: "language", property_values: [$lang] }
            ],
            exclude: []
          }
        },
        rules: [{
          type: "workflows",
          parameters: {
            workflows: [{
              repository_id: $repo_id,
              path: $path,
              ref: "refs/heads/main"
            }]
          }
        }],
        bypass_actors: []
      }')
    upsert_ruleset "production-${lang}-ci" "$payload"
  done
else
  echo "==> Skipping production-<lang>-ci rulesets (APPLY_REQUIRED_CI=false)"
fi

# --- 2c. Copilot review: advisory only -------------------------------------
#
# production-copilot-review enables Copilot's PR review (advisory). It is NOT a
# merge gate.
#
# There is deliberately NO production-review-gate ruleset. A required-workflow
# rule demanding "Copilot reviewed HEAD" deadlocked every PR and is
# unachievable in this environment:
#   - GitHub runs ruleset-required workflows only on pull_request/merge_group,
#     so the gate fired once at push time (before Copilot reviewed the new
#     HEAD) and never re-ran;
#   - Copilot does not auto-review on push here (review_on_push does not fire),
#     so nothing turns the check green;
#   - a review-event re-run is approval-gated — the Copilot bot is the
#     triggering actor, so the run is action_required and never executes.
# Thread resolution is already enforced natively by production-main
# (required_review_thread_resolution); that is the working guarantee we keep.
# Skip with: APPLY_REVIEW_GATE=false
APPLY_REVIEW_GATE="${APPLY_REVIEW_GATE:-true}"

if [ "$APPLY_REVIEW_GATE" = "true" ]; then
  echo "==> Ruleset: production-copilot-review (advisory Copilot review)"
  copilot_payload=$(jq -n '{
    name: "production-copilot-review",
    target: "branch",
    enforcement: "active",
    conditions: {
      ref_name: { include: ["~DEFAULT_BRANCH"], exclude: [] },
      repository_property: {
        include: [{ name: "tier", property_values: ["production"] }],
        exclude: []
      }
    },
    rules: [{
      type: "copilot_code_review",
      parameters: { review_on_push: true, review_draft_pull_requests: false }
    }],
    bypass_actors: []
  }')
  upsert_ruleset "production-copilot-review" "$copilot_payload"

  # Idempotently remove the deadlocking required-workflow gate if an earlier
  # apply (or a prior policy version) created it.
  echo "==> Removing stale production-review-gate ruleset (deadlocking gate)"
  gate_id=$(gh api --paginate "orgs/${ORG}/rulesets" \
    --jq '.[] | select(.name=="production-review-gate") | .id' | head -n1 || true)
  if [ -n "$gate_id" ]; then
    gh api -X DELETE "orgs/${ORG}/rulesets/${gate_id}" >/dev/null
    echo "    - removed production-review-gate (id=${gate_id})"
  else
    echo "    - not present (nothing to remove)"
  fi
else
  echo "==> Skipping Copilot-review ruleset (APPLY_REVIEW_GATE=false)"
fi

# ---------------------------------------------------------------------------
# 3. Next steps
# ---------------------------------------------------------------------------
cat <<EOF

==> Done.

Next steps (one-time, per repo):

  Mark a repo as production so the ruleset takes effect:
    gh api -X PATCH "orgs/${ORG}/properties/values" \\
      -F 'repository_names[]=<repo-name>' \\
      -F 'properties[][property_name]=tier' \\
      -F 'properties[][value]=production'

  Tag a repo with its primary language:
    gh api -X PATCH "orgs/${ORG}/properties/values" \\
      -F 'repository_names[]=<repo-name>' \\
      -F 'properties[][property_name]=language' \\
      -F 'properties[][value]=go'

Review state in the UI:
  - Properties: https://github.com/organizations/${ORG}/settings/properties
  - Rulesets:   https://github.com/organizations/${ORG}/settings/rules
EOF
