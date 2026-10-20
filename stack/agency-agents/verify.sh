#!/usr/bin/env bash
# Verify the Agency Agents Stack v1 layer after install.sh.
#
# Confirms exactly the 9 division-lead agents exist, are paused (pauseReason
# "import"), have heartbeat timers disabled, a $0 monthly budget, and the
# opencode_local adapter with a model set, and that reporting lines resolve to
# our core CEO / CTO / vp-engineering (never a second CEO).
#
# Environment (all required):
#   PAPERCLIP_API_URL
#   PAPERCLIP_API_KEY
#   PAPERCLIP_COMPANY_ID
#   CEO_AGENT_ID           our core CEO agent id
#   CTO_AGENT_ID           our core CTO agent id
set -euo pipefail

: "${PAPERCLIP_API_URL:?set PAPERCLIP_API_URL}"
: "${PAPERCLIP_API_KEY:?set PAPERCLIP_API_KEY}"
: "${PAPERCLIP_COMPANY_ID:?set PAPERCLIP_COMPANY_ID}"
: "${CEO_AGENT_ID:?set CEO_AGENT_ID}"
: "${CTO_AGENT_ID:?set CTO_AGENT_ID}"

BASE="${PAPERCLIP_API_URL%/}"
COMPANY_ID="$PAPERCLIP_COMPANY_ID"

# slug -> expected manager key (ceo | cto | vp-engineering)
declare -A EXPECT=(
  [vp-engineering]="cto"
  [creative-director]="ceo"
  [vp-product]="ceo"
  [vp-sales]="ceo"
  [qa-director]="vp-engineering"
  [vp-operations]="ceo"
  [game-dev-director]="ceo"
  [xr-director]="vp-engineering"
  [chief-of-staff]="ceo"
)

# slug -> display name. The importer slugifies each display name into the agent
# `urlKey` (e.g. "VP of Engineering" -> "vp-of-engineering"), so match on the
# stable, unique display name rather than the source slug or the derived urlKey.
declare -A NAME=(
  [vp-engineering]="VP of Engineering"
  [creative-director]="Creative Director"
  [vp-product]="VP of Product"
  [vp-sales]="VP of Sales"
  [qa-director]="QA Director"
  [vp-operations]="VP of Operations"
  [game-dev-director]="Game Development Director"
  [xr-director]="XR Director"
  [chief-of-staff]="Chief of Staff"
)

AGENTS="$(curl -sS -m 60 -H "Authorization: Bearer $PAPERCLIP_API_KEY" "$BASE/api/companies/$COMPANY_ID/agents")"
COMPANY="$(curl -sS -m 60 -H "Authorization: Bearer $PAPERCLIP_API_KEY" "$BASE/api/companies/$COMPANY_ID")"

VP_ID="$(jq -r --arg n "VP of Engineering" '.[] | select(.name == $n) | .id' <<<"$AGENTS" | head -n1)"

failures=0
check() { # $1 ok bool, $2 message
  if [ "$1" = "true" ]; then printf 'PASS  %s\n' "$2"; else printf 'FAIL  %s\n' "$2"; failures=$((failures + 1)); fi
}

# Company budget must be unchanged at $25/month (2500 cents).
BUDGET="$(jq -r '.budgetMonthlyCents' <<<"$COMPANY")"
check "$([ "$BUDGET" = "2500" ] && echo true || echo false)" "company budget unchanged at 2500 cents (got $BUDGET)"

for slug in "${!EXPECT[@]}"; do
  name="${NAME[$slug]}"
  row="$(jq -c --arg n "$name" '.[] | select(.name == $n)' <<<"$AGENTS" | head -n1)"
  if [ -z "$row" ]; then
    check false "$slug present"
    continue
  fi
  check true "$slug present"

  status="$(jq -r '.status' <<<"$row")"
  check "$([ "$status" = "paused" ] && echo true || echo false)" "$slug status=paused (got $status)"

  pause_reason="$(jq -r '.pauseReason // empty' <<<"$row")"
  check "$([ "$pause_reason" = "import" ] && echo true || echo false)" "$slug pauseReason=import (got $pause_reason)"

  budget="$(jq -r '.budgetMonthlyCents' <<<"$row")"
  check "$([ "$budget" = "0" ] && echo true || echo false)" "$slug budget=0 (got $budget)"

  hb="$(jq -r '.runtimeConfig.heartbeat.enabled // false' <<<"$row")"
  check "$([ "$hb" = "false" ] && echo true || echo false)" "$slug heartbeat timers off (enabled=$hb)"

  adapter_type="$(jq -r '.adapterType // empty' <<<"$row")"
  check "$([ "$adapter_type" = "opencode_local" ] && echo true || echo false)" "$slug adapterType=opencode_local (got $adapter_type)"

  adapter_model="$(jq -r '.adapterConfig.model // empty' <<<"$row")"
  check "$([ -n "$adapter_model" ] && echo true || echo false)" "$slug adapterConfig.model non-empty (got $adapter_model)"

  manager_key="${EXPECT[$slug]}"
  case "$manager_key" in
    cto) expected_id="$CTO_AGENT_ID" ;;
    ceo) expected_id="$CEO_AGENT_ID" ;;
    vp-engineering) expected_id="$VP_ID" ;;
    *) expected_id="" ;;
  esac
  reportsTo="$(jq -r '.reportsTo // empty' <<<"$row")"
  if [ -n "$expected_id" ] && [ "$reportsTo" = "$expected_id" ]; then
    check true "$slug reportsTo=$manager_key ($expected_id)"
  else
    check false "$slug reportsTo=$manager_key (got $reportsTo, expected $expected_id)"
  fi
done

echo
if [ "$failures" -ne 0 ]; then
  echo "verify.sh: $failures check(s) FAILED"
  exit 1
fi
echo "verify.sh: all checks passed"
