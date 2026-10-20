#!/usr/bin/env bash
# Install the Agency Agents Stack v1 layer into the RioLabs AI company.
#
# Imports exactly the 9 division-lead agents, landed paused, with heartbeat
# timers disabled and a $0 monthly budget. It never touches company metadata,
# projects, tasks, or skills, and it never imports the template ceo/cmo.
#
# Requires an actor whose Paperclip role is `ceo` (or the board): the
# `/api/companies/:companyId/imports/*` routes reject any other agent role.
#
# Environment (all required):
#   PAPERCLIP_API_URL      e.g. https://work.riolabs.ai
#   PAPERCLIP_API_KEY      a short-lived agent run JWT with CEO-role authority
#   PAPERCLIP_COMPANY_ID   the target company id
#   CTO_AGENT_ID           (optional) the CTO agent id to receive vp-engineering
#
# Exit codes: 0 success, 1 gate failure, 2 import failure, 3 remap failure.
set -euo pipefail

SOURCE_URL="https://github.com/paperclipai/companies?ref=514503bf4f0ca88ebf16d5dc648e085d587f268f&path=agency-agents"
AGENTS="vp-engineering,creative-director,vp-product,vp-sales,qa-director,vp-operations,game-dev-director,xr-director,chief-of-staff"
EXPECTED_COUNT=9

: "${PAPERCLIP_API_URL:?set PAPERCLIP_API_URL}"
: "${PAPERCLIP_API_KEY:?set PAPERCLIP_API_KEY}"
: "${PAPERCLIP_COMPANY_ID:?set PAPERCLIP_COMPANY_ID}"

BASE="${PAPERCLIP_API_URL%/}"
COMPANY_ID="$PAPERCLIP_COMPANY_ID"

die() { printf 'install.sh: %s\n' "$*" >&2; exit "${2:-1}"; }

api_json() {
  # $1 method (POST), $2 path, $3 body
  curl -sS -m 120 \
    -X "$1" \
    -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$3" \
    "$BASE$2"
}

preview_body() {
  jq -nc \
    --arg src "$SOURCE_URL" \
    --arg cid "$COMPANY_ID" \
    --arg agents "$AGENTS" \
    '{
      source: { type: "github", url: $src },
      include: { company: false, agents: true, projects: false, issues: false, skills: false },
      target: { mode: "existing_company", companyId: $cid },
      agents: ($agents | split(",")),
      collisionStrategy: "skip"
    }'
}

echo "==> Previewing import (dry-run) of $EXPECTED_COUNT division leads"
PREVIEW="$(api_json POST "/api/companies/$COMPANY_ID/imports/preview" "$(preview_body)")"

# Gate: zero errors, zero unresolved reporting lines, zero replacements, and
# exactly the 9 expected leads, all planned as `create`.
ERRORS="$(jq -r '.errors | length' <<<"$PREVIEW")"
PLAN_COUNT="$(jq -r '.plan.agentPlans | length' <<<"$PREVIEW")"
CREATE_COUNT="$(jq -r '[.plan.agentPlans[] | select(.action == "create")] | length' <<<"$PREVIEW")"
UPDATE_COUNT="$(jq -r '[.plan.agentPlans[] | select(.action == "update")] | length' <<<"$PREVIEW")"
SKIP_COUNT="$(jq -r '[.plan.agentPlans[] | select(.action == "skip")] | length' <<<"$PREVIEW")"
UNRESOLVED="$(jq -r '[.warnings[] | select(test("manager|unresolved|overwritten|replace"; "i"))] | length' <<<"$PREVIEW")"

echo "   errors=$ERRORS agents=$PLAN_COUNT create=$CREATE_COUNT update=$UPDATE_COUNT skip=$SKIP_COUNT unresolved=$UNRESOLVED"

if [ "$ERRORS" -ne 0 ]; then die "preview returned errors: $(jq -c '.errors' <<<"$PREVIEW")" 1; fi
if [ "$PLAN_COUNT" -ne "$EXPECTED_COUNT" ]; then die "expected $EXPECTED_COUNT agents, got $PLAN_COUNT" 1; fi
if [ "$CREATE_COUNT" -ne "$EXPECTED_COUNT" ]; then die "expected $EXPECTED_COUNT creates, got $CREATE_COUNT (replacements/collisions present)" 1; fi
if [ "$UNRESOLVED" -ne 0 ]; then die "unresolved reporting lines present: $(jq -c '[.warnings[] | select(test(\"manager|unresolved|overwritten|replace\"; \"i\"))]' <<<"$PREVIEW")" 1; fi

echo "==> Gate passed. Applying import with pauseAutomations (landed paused, \$0, timers off)"
APPLY_BODY="$(jq -nc \
  --arg src "$SOURCE_URL" \
  --arg cid "$COMPANY_ID" \
  --arg agents "$AGENTS" \
  '{
    source: { type: "github", url: $src },
    include: { company: false, agents: true, projects: false, issues: false, skills: false },
    target: { mode: "existing_company", companyId: $cid },
    agents: ($agents | split(",")),
    collisionStrategy: "skip",
    pauseAutomations: true
  }')"

RESULT="$(api_json POST "/api/companies/$COMPANY_ID/imports/apply" "$APPLY_BODY")"
CREATED="$(jq -r '[.agents[] | select(.action == "created")] | length' <<<"$RESULT")"
echo "   created=$CREATED warnings=$(jq -r '.warnings | length' <<<"$RESULT")"
if [ "$CREATED" -ne "$EXPECTED_COUNT" ]; then
  die "import created $CREATED agents, expected $EXPECTED_COUNT: $(jq -c '.agents' <<<"$RESULT")" 2
fi

# Remap vp-engineering to report to our CTO (not a second CEO).
if [ -n "${CTO_AGENT_ID:-}" ]; then
  VP_ID="$(jq -r '.agents[] | select(.slug == "vp-engineering") | .id' <<<"$RESULT")"
  if [ -n "$VP_ID" ] && [ "$VP_ID" != "null" ]; then
    echo "==> Remapping vp-engineering ($VP_ID) -> CTO ($CTO_AGENT_ID)"
    api_json PATCH "/api/agents/$VP_ID" "$(jq -nc --arg cto "$CTO_AGENT_ID" '{ reportsTo: $cto }')" >/dev/null \
      || die "failed to remap vp-engineering to CTO" 3
  else
    echo "!! vp-engineering id not found in result; remap skipped (run verify.sh to confirm)"
  fi
else
  echo "!! CTO_AGENT_ID not set; skipping vp-engineering remap (run verify.sh to confirm)"
fi

echo "==> Done. Run verify.sh to confirm roster, status, budgets, timers, and reporting."
