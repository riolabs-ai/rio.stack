#!/usr/bin/env bash
# Prove the layer is a template and not a wish: parse every file, refuse secrets, refuse leftovers.
#
#   bash verify.sh            # structural + secret checks
#   bash verify.sh --strict   # also refuse any un-replaced {{PLACEHOLDER}} in a resolved artefact
#
# Exit 0 = the layer is shippable. Any other exit prints the failing check by name.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1
PY=${PYTHON:-python3}
fail=0
ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }

echo "verify: bot-profile template v1 ($HERE)"

# --- 1. every promised file is present -------------------------------------------------------
for f in README.md docs/kanban-conventions.md profile/config.yaml profile/SOUL.md \
         profile/.env.example bot/botforge-template.json install.sh verify.sh template-v1.lock.yaml; do
  [ -s "$HERE/$f" ] && ok "present: $f" || bad "missing or empty: $f"
done

# --- 2. everything parses -------------------------------------------------------------------
"$PY" - "$HERE" <<'PY' || exit 1
import json, sys, yaml, pathlib
root = pathlib.Path(sys.argv[1])
bad = 0
try:
    bot = json.load(open(root / "bot/botforge-template.json"))
    need = {"format", "version", "display_name", "role", "description", "one_job", "soul_md",
            "memory", "toolsets", "routines"}
    missing = need - set(bot)
    assert bot["format"] == "bot-forge/template", f"format is {bot['format']!r}"
    assert bot["version"] == 1, f"version is {bot['version']!r}"
    assert not missing, f"template missing {sorted(missing)}"
    print(f"  ok    bot template parses ({bot['format']} v{bot['version']}, "
          f"{len(bot['toolsets'])} toolsets, {len(bot['routines'])} routine(s))")
except Exception as exc:
    print(f"  FAIL  bot template: {exc}"); bad = 1
for name in ("profile/config.yaml", "template-v1.lock.yaml"):
    try:
        d = yaml.safe_load(open(root / name))
        print(f"  ok    parses: {name} ({len(d or {})} top-level keys)")
    except Exception as exc:
        print(f"  FAIL  parses: {name}: {exc}"); bad = 1
# the soul exists twice; the bot JSON must carry the same opening line as the file
try:
    first = (root / "profile/SOUL.md").read_text().splitlines()[0].strip()
    assert bot["soul_md"].splitlines()[0].strip() == first, "SOUL.md and soul_md disagree on line 1"
    print("  ok    SOUL.md matches the template's soul_md")
except Exception as exc:
    print(f"  FAIL  soul sync: {exc}"); bad = 1
raise SystemExit(bad)
PY
[ $? -ne 0 ] && fail=$((fail+1))

# --- 3. no secrets, ever --------------------------------------------------------------------
# Shapes only: a private key block, a classic GitHub token, an OpenAI-style sk- key, a long
# hex/base64 blob assigned to a KEY=, or anything that looks like a live URL credential.
secrets="$(
  grep -rInE 'BEGIN [A-Z ]*PRIVATE KEY|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|[A-Za-z0-9_]{2,}=\s*[A-Za-z0-9+/=]{32,}' \
    --include='*.md' --include='*.yaml' --include='*.yml' --include='*.json' --include='*.sh' \
    --include='.env.example' "$HERE" 2>/dev/null || true
)"
if [ -z "$secrets" ]; then ok "no secret-shaped strings"; else bad "secret-shaped strings found:"; echo "$secrets" | sed 's/^/        /'; fi

# --- 4. no personal or environment specifics ------------------------------------------------
# Exclude this file: it necessarily contains the patterns it searches for, which is why the first
# run of this check failed on itself.
personal="$(grep -rInE '/home/[a-z][a-z0-9_-]+|jaden|riolabs-ai/[a-z]' --exclude=verify.sh \
  --include='*.md' --include='*.yaml' --include='*.json' --include='*.sh' "$HERE" 2>/dev/null \
  | grep -v '/verify\.sh:' || true)"
if [ -z "$personal" ]; then ok "no machine-specific paths or names"; else bad "machine-specific content:"; echo "$personal" | sed 's/^/        /'; fi

# --- 5. strict: placeholders must be gone from anything already resolved --------------------
if [ $STRICT = 1 ]; then
  left="$(grep -rInoE '\{\{[A-Z_]+\}\}' --include='*.yaml' --include='*.json' "$HERE/profile" "$HERE/bot" 2>/dev/null || true)"
  if [ -z "$left" ]; then ok "strict: no un-replaced placeholders in profile/ or bot/"
  else bad "strict: un-replaced placeholders (expected in the template, fatal once installed):"; echo "$left" | sed 's/^/        /'; fi
else
  ok "placeholders allowed (template mode; use --strict after resolving)"
fi

echo
if [ $fail -eq 0 ]; then echo "verify: PASS"; exit 0; else echo "verify: FAIL ($fail check(s))"; exit 1; fi
