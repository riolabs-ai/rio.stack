#!/usr/bin/env bash
# Prove the hermes-config layer is shippable.
#
#   bash verify.sh          # hermetic: layer files, invariants, negative controls. Runs in CI.
#   bash verify.sh --host   # also audit the local install against the layer (needs hermes + ~/.hermes)
#
# Exit 0 = the layer is shippable. Any other exit prints the failing check by name.
#
# The default mode is hermetic on purpose: this repository's CI runs every stack/*/verify.sh on a
# clean ubuntu runner, so a check that needs a live Hermes install would have to be skipped there —
# and a skipped check is not a check. The six invariants are proved against the layer's own render
# and its own negative controls; --host is the extra audit for the machine you installed onto.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=${PYTHON:-python3}
HOST=0
[ "${1:-}" = "--host" ] && HOST=1

fail=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }

echo "verify: hermes-config v0.1.0 ($HERE)"

# --- 1. every promised file is present ------------------------------------------------------
mapfile -t FILES < <("$PY" -c 'import sys, yaml; [print(f) for f in (yaml.safe_load(open(sys.argv[1])) or {}).get("pinned", {}).get("files", [])]' "$HERE/hermes-config.lock.yaml")
[ "${#FILES[@]}" -gt 0 ] && ok "lock lists ${#FILES[@]} file(s)" || bad "lock lists no files"
for f in "${FILES[@]}"; do
  if [ -s "$HERE/$f" ]; then ok "present: $f"; else bad "missing or empty: $f"; fi
done

# --- 2. the lock parses and states its own contract -----------------------------------------
if "$PY" -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$HERE/hermes-config.lock.yaml" 2>/dev/null; then
  ok "lock parses: hermes-config.lock.yaml"
else
  bad "lock does not parse: hermes-config.lock.yaml"
fi
if "$PY" -c 'import sys, yaml; d=yaml.safe_load(open(sys.argv[1])) or {}; sys.exit(0 if (d.get("install") or {}).get("default") == "dry-run" else 1)' "$HERE/hermes-config.lock.yaml"; then
  ok "install defaults to dry-run"
else
  bad "install.default is not dry-run"
fi
if bash "$HERE/install.sh" --help 2>/dev/null | grep -qi 'dry run'; then
  ok "install.sh --help states the dry-run default"
else
  bad "install.sh --help does not state the dry-run default"
fi

# --- 3. the six invariants, each producing a line -------------------------------------------
echo "-- invariants"
if "$PY" "$HERE/tools/hermes_config_check.py" check; then
  ok "all six invariants hold"
else
  bad "an invariant failed (see the lines above)"
fi

# --- 4. the negative controls: each invariant must REFUSE its mutation ----------------------
echo "-- negative controls"
if "$PY" "$HERE/tools/hermes_config_check.py" neg; then
  ok "every mutation was refused"
else
  bad "a mutation was accepted — that invariant is decorative"
fi

# --- 5. no secrets, ever --------------------------------------------------------------------
# Shapes only: a private key, a GitHub token, a Slack token, or a credential-shaped assignment.
# The layer names secret KEYS (DATABASE_URL, NEON_AUTH_*) as things to refuse; a name is not a value.
secrets="$(grep -rInE 'BEGIN [A-Z ]*PRIVATE KEY|gh[pousr]_[A-Za-z0-9]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{20,}' \
  --include='*.md' --include='*.yaml' --include='*.yml' --include='*.sh' --include='*.py' "$HERE" 2>/dev/null || true)"
if [ -z "$secrets" ]; then ok "no secret-shaped strings"; else bad "secret-shaped strings found:"; printf '%s\n' "$secrets" | sed 's/^/        /'; fi

# --- 6. the layer renders, and renders complete --------------------------------------------
RENDER="$(mktemp -d "${TMPDIR:-/tmp}/hermes-config-verify.XXXXXX")"
trap 'rm -rf "$RENDER"' EXIT
if "$PY" "$HERE/tools/hermes_config_check.py" render --out "$RENDER" >/dev/null 2>&1; then
  ok "every profile renders with no placeholder left"
else
  bad "render failed — a template still carries a placeholder or a profile is unreadable"
fi
count="$(find "$RENDER" -name '*.config.yaml' 2>/dev/null | wc -l | tr -d ' ')"
declared="$("$PY" -c 'import sys, yaml; print(len((yaml.safe_load(open(sys.argv[1])) or {}).get("pinned", {}).get("profiles", {})))' "$HERE/hermes-config.lock.yaml")"
if [ "$count" = "$declared" ]; then ok "rendered $count profile config(s), as the lock declares"; else bad "rendered $count config(s) but the lock declares $declared profile(s)"; fi

# --- 7. optional: audit the live install ----------------------------------------------------
if [ "$HOST" = 1 ]; then
  echo "-- host audit"
  HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
  if [ ! -d "$HERMES_HOME" ]; then
    bad "no Hermes home at $HERMES_HOME"
  else
    # A dry run computes the same decisions --apply would take, without writing anything.
    plan="$(bash "$HERE/install.sh" 2>&1)"
    drift="$(printf '%s\n' "$plan" | grep -cE '^  (CONFLICT|absent)' || true)"
    adds="$(printf '%s\n' "$plan" | grep -cE '^  set ' || true)"
    if [ "$drift" = "0" ]; then
      ok "host matches the layer: no conflicting key, no absent profile"
    else
      bad "host differs from the layer in $drift place(s) — 'bash install.sh' prints the full plan"
      # Grouped by profile so a long drift list stays readable; the full plan is install.sh's job.
      printf '%s\n' "$plan" | grep -E '^  (CONFLICT|absent)' | sed -E 's/^  (CONFLICT|absent) +([^ ]+).*/\2/' | sort | uniq -c | sort -rn | head -8 | sed 's/^/        /'
    fi
    if [ "$adds" != "0" ]; then
      ok "host is missing $adds key(s) the layer owns — 'bash install.sh --apply' writes them"
    fi
  fi
fi

echo
if [ "$fail" -eq 0 ]; then echo "verify: PASS"; exit 0; else echo "verify: FAIL ($fail check(s))"; exit 1; fi
