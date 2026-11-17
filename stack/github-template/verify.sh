#!/usr/bin/env bash
# Prove the layer is a template and not a wish.
#
#   bash verify.sh     # exit 0 = shippable; any other exit names the failing check
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=${PYTHON:-python3}
fail=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }
echo "verify: github-template v1 ($HERE)"

# 1. every promised file is present (the list lives in the lock)
mapfile -t FILES < <("$PY" -c 'import sys,yaml; [print(f) for f in yaml.safe_load(open(sys.argv[1]))["pinned"]["files"]]' "$HERE/template-v1.lock.yaml")
[ "${#FILES[@]}" -gt 0 ] || bad "lock lists no files"
for f in "${FILES[@]}"; do [ -s "$HERE/$f" ] && ok "present: $f" || bad "missing or empty: $f"; done

# 2. YAML parses; placeholders in template/ == keys in values.example.yaml == lock
"$PY" - "$HERE" <<'PY' || fail=$((fail+1))
import pathlib, re, sys, yaml
root = pathlib.Path(sys.argv[1]); PH = re.compile(r"\{\{([A-Z][A-Z0-9_]*)\}\}"); bad = 0
for p in sorted(root.rglob("*.y*ml")):
    try: yaml.safe_load(PH.sub("x", p.read_text()))
    except Exception as e: print(f"  FAIL  yaml: {p.relative_to(root)}: {e}"); bad += 1
used = set()
for p in (root / "template").rglob("*"):
    if p.is_file(): used |= set(PH.findall(p.read_text()))
keys = set(yaml.safe_load((root / "values.example.yaml").read_text())) - {"AVATAR_SOURCE", "ACCOUNT_KIND"}
locked = set(yaml.safe_load((root / "template-v1.lock.yaml").read_text())["pinned"]["placeholders"])
for name, a, b in [("template vs values.example", used, keys), ("template vs lock", used, locked)]:
    if a != b: print(f"  FAIL  placeholders differ ({name}): {sorted(a ^ b)}"); bad += 1
    else: print(f"  ok    placeholders agree ({name}): {len(a)}")
sys.exit(1 if bad else 0)
PY

# 3. renders clean with the example values
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gh-template.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
if bash "$HERE/render.sh" --values "$HERE/values.example.yaml" --out "$TMP/out" --apply >/dev/null; then
  if grep -rqE '\{\{[A-Z][A-Z0-9_]*\}\}' "$TMP/out"; then bad "render left placeholders"; else ok "renders with zero leftover placeholders"; fi
else bad "render.sh failed on values.example.yaml"; fi

# 4. negative control: a missing value must make render refuse (a check that cannot fail is not a check)
grep -v '^TAGLINE:' "$HERE/values.example.yaml" > "$TMP/broken.yaml"
if bash "$HERE/render.sh" --values "$TMP/broken.yaml" --out "$TMP/neg" --apply >/dev/null 2>&1; then
  bad "negative control: render accepted a missing TAGLINE"
else ok "negative control: render refuses a missing value"; fi
[ -e "$TMP/neg" ] && bad "negative control: render wrote files before refusing" || ok "negative control: nothing written on refusal"

# 5. no secrets, no machine paths, no real identities in the template
if grep -rnEI '(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY)' "$HERE" --exclude=verify.sh; then bad "secret-shaped string"; else ok "no secret-shaped strings"; fi
if grep -rnE '/home/[a-z]|/Users/[A-Za-z]' "$HERE/template" "$HERE/values.example.yaml"; then bad "machine-specific path in template"; else ok "no machine-specific paths"; fi
if grep -rniE '@[a-z0-9-]+\.(com|io|ai|net|org)\b' "$HERE/template"; then bad "real-looking email in template (use a placeholder)"; else ok "no hard-coded emails in template"; fi

echo; [ $fail -eq 0 ] && echo "verify: PASS" || echo "verify: $fail check(s) failed"
exit $([ $fail -eq 0 ] && echo 0 || echo 1)
