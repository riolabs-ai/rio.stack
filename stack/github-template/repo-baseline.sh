#!/usr/bin/env bash
# Audit (and optionally apply) the free-tier settings baseline on ONE repo.
#
#   bash repo-baseline.sh --repo owner/name            # audit only, writes nothing
#   bash repo-baseline.sh --repo owner/name --apply    # apply the gaps via gh (needs admin)
#
# One repo per call on purpose: fleet rollouts go one PR/issue per repo, never in bulk.
# Never deletes, never changes visibility, never touches an existing ruleset.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO=""; SPEC="$HERE/repo-baseline.yml"; APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:?}"; shift 2 ;;
    --spec) SPEC="${2:?}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) sed -n '2,8p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$REPO" ] || { echo "usage: bash repo-baseline.sh --repo owner/name [--apply]" >&2; exit 2; }
PY=${PYTHON:-python3}
spec() { "$PY" -c 'import sys,yaml,json; d=yaml.safe_load(open(sys.argv[1])); k=sys.argv[2:]
for x in k: d=d[x]
print(json.dumps(d) if isinstance(d,(dict,list)) else str(d).lower())' "$SPEC" "$@"; }

META=$(gh api "repos/$REPO")
jq_() { printf '%s' "$META" | "$PY" -c 'import sys,json; d=json.load(sys.stdin)
for k in sys.argv[1].split("."):
    d = (d or {}).get(k)
print("" if d is None else (json.dumps(d) if isinstance(d,(dict,list)) else str(d).lower()))' "$1"; }
VIS=$(jq_ visibility); ADMIN=$(jq_ permissions.admin); BRANCH=$(printf '%s' "$META" | "$PY" -c 'import sys,json; print(json.load(sys.stdin)["default_branch"])')
echo "repo-baseline: $REPO ($VIS, default branch $BRANCH, admin=$ADMIN, mode=$([ $APPLY = 1 ] && echo apply || echo audit))"
gaps=0; skipped=0
gap()  { printf '  gap   %s\n' "$1"; gaps=$((gaps+1)); }
ok()   { printf '  ok    %s\n' "$1"; }
skip() { printf '  skip  %s\n' "$1"; skipped=$((skipped+1)); }
do_() { if [ "$APPLY" = 1 ]; then "$@" >/dev/null && printf '  set   %s\n' "$LBL"; fi; }
[ "$APPLY" = 1 ] && [ "$ADMIN" != true ] && { echo "  --apply needs admin on $REPO; you have push at most. Audit only." >&2; APPLY=0; }

echo "-- settings"
PATCH="{}"
for key in $(spec settings | "$PY" -c 'import sys,json; print(" ".join(json.load(sys.stdin)))'); do
  want=$(spec settings "$key"); have=$(jq_ "$key")
  if [ "$have" = "$want" ]; then ok "$key=$have"
  elif [ -z "$have" ]; then skip "$key (not visible without admin)"
  else gap "$key: $have -> $want"
    PATCH=$("$PY" - "$PATCH" "$SPEC" "$key" <<'PY2'
import sys, json, yaml
d = json.loads(sys.argv[1]); d[sys.argv[3]] = yaml.safe_load(open(sys.argv[2]))["settings"][sys.argv[3]]
print(json.dumps(d))
PY2
)
  fi
done
if [ "$PATCH" != "{}" ]; then   # send the whole settings block: GitHub validates squash title+message as a pair
  PATCH=$("$PY" -c 'import sys,json,yaml; print(json.dumps(yaml.safe_load(open(sys.argv[1]))["settings"]))' "$SPEC")
  LBL="settings $PATCH"; do_ gh api -X PATCH "repos/$REPO" --input - <<<"$PATCH"
fi

echo "-- security"
if [ "$ADMIN" != true ]; then skip "security features (need admin to read)"; else
  if gh api "repos/$REPO/vulnerability-alerts" >/dev/null 2>&1; then ok "vulnerability_alerts"
  else gap "vulnerability_alerts off"; LBL=vulnerability_alerts; do_ gh api -X PUT "repos/$REPO/vulnerability-alerts"; fi
  if [ "$(gh api "repos/$REPO/automated-security-fixes" --jq .enabled 2>/dev/null)" = true ]; then ok "automated_security_fixes"
  else gap "automated_security_fixes off"; LBL=automated_security_fixes; do_ gh api -X PUT "repos/$REPO/automated-security-fixes"; fi
  if [ "$VIS" = public ]; then
    if [ "$(gh api "repos/$REPO/private-vulnerability-reporting" --jq .enabled 2>/dev/null)" = true ]; then ok "private_vulnerability_reporting"
    else gap "private_vulnerability_reporting off"; LBL=private_vulnerability_reporting; do_ gh api -X PUT "repos/$REPO/private-vulnerability-reporting"; fi
    for f in secret_scanning secret_scanning_push_protection; do
      if [ "$(jq_ "security_and_analysis.$f.status")" = enabled ]; then ok "$f"
      else gap "$f off"; LBL=$f
        do_ gh api -X PATCH "repos/$REPO" --input - <<<"{\"security_and_analysis\":{\"$f\":{\"status\":\"enabled\"}}}"; fi
    done
  else skip "private_vulnerability_reporting, secret scanning (public_only on Free)"; fi
fi

echo "-- ruleset"
RS_NAME=$(spec ruleset name)
if [ "$VIS" != public ]; then skip "ruleset $RS_NAME (rulesets on private repos need Pro)"
elif gh api "repos/$REPO/rulesets" --jq '.[].name' 2>/dev/null | grep -qxF "$RS_NAME"; then ok "ruleset $RS_NAME"
else gap "ruleset $RS_NAME missing on $BRANCH"; LBL="ruleset $RS_NAME"
  BODY=$("$PY" - "$SPEC" <<'PY'
import sys, json, yaml
r = yaml.safe_load(open(sys.argv[1]))["ruleset"]
print(json.dumps({"name": r["name"], "target": "branch", "enforcement": r["enforcement"],
  "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
  "rules": [{"type": t} for t in r["rules"]]}))
PY
)
  [ "$ADMIN" = true ] && do_ gh api -X POST "repos/$REPO/rulesets" --input - <<<"$BODY"
fi

echo "repo-baseline: $gaps gap(s), $skipped skipped$([ $APPLY = 1 ] && echo ', gaps applied')"
