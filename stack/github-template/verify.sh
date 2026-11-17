#!/usr/bin/env bash
# Prove the layer is a template and not a wish.
#
#   bash verify.sh     # exit 0 = shippable; any other exit names the failing check
#
# Renders both account kinds against a throwaway avatar and checks the profile page lands
# where GitHub reads it: <org>/.github/profile for orgs, <user>/<user> for personal accounts.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=${PYTHON:-python3}
fail=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }
echo "verify: github-template v1 ($HERE)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gh-template.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT

echo "-- files"
mapfile -t FILES < <("$PY" -c 'import sys,yaml; [print(f) for f in yaml.safe_load(open(sys.argv[1]))["pinned"]["files"]]' "$HERE/template-v1.lock.yaml")
[ "${#FILES[@]}" -gt 0 ] || bad "lock lists no files"
for f in "${FILES[@]}"; do [ -s "$HERE/$f" ] && ok "present: $f" || bad "missing or empty: $f"; done
EXTRA=$(cd "$HERE" && find template -type f | sort | while read -r f; do printf '%s\n' "${FILES[@]}" | grep -qxF "$f" || echo "$f"; done)
[ -z "$EXTRA" ] && ok "no unpinned files in template/" || bad "template files missing from the lock: $EXTRA"

echo "-- placeholders"
"$PY" - "$HERE" <<'PY' || fail=$((fail+1))
import pathlib, re, sys, yaml
root = pathlib.Path(sys.argv[1]); PH = re.compile(r"\{\{([A-Z][A-Z0-9_]*)\}\}"); bad = 0
for p in sorted(root.rglob("*.y*ml")):
    try: yaml.safe_load(PH.sub("x", p.read_text()))
    except Exception as e: print(f"  FAIL  yaml: {p.relative_to(root)}: {e}"); bad += 1
lock = yaml.safe_load((root / "template-v1.lock.yaml").read_text())["pinned"]
used = set()
for p in (root / "template").rglob("*"):
    if p.is_file(): used |= set(PH.findall(p.read_text()))
keys = set(yaml.safe_load((root / "values.example.yaml").read_text())) - set(lock["render_only"])
for name, a, b in [("template vs values.example", used, keys), ("template vs lock", used, set(lock["placeholders"]))]:
    if a != b: print(f"  FAIL  placeholders differ ({name}): {sorted(a ^ b)}"); bad += 1
    else: print(f"  ok    placeholders agree ({name}): {len(a)}")
sys.exit(1 if bad else 0)
PY

# values variants: org and user, each with a throwaway avatar so asset links can be resolved
printf 'GIF89a\x01\x00\x01\x00\x00\x00\x00;' > "$TMP/avatar.gif"
variant() {  # $1 kind, $2 output file, [$3 key to drop]
  "$PY" - "$HERE/values.example.yaml" "$1" "$TMP/avatar.gif" "${3:-}" > "$2" <<'PY'
import sys, yaml
v = yaml.safe_load(open(sys.argv[1])); v["ACCOUNT_KIND"] = sys.argv[2]
v["AVATAR_SOURCE"] = sys.argv[3]; v["AVATAR_FILE"] = "avatar.gif"
if sys.argv[4]: v.pop(sys.argv[4])
print(yaml.safe_dump(v, allow_unicode=True))
PY
}
variant org "$TMP/org.yaml"; variant user "$TMP/user.yaml"

# every relative link/src in a rendered markdown file must point at a file that exists
links_resolve() {  # $1 root dir
  "$PY" - "$1" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1]); bad = 0
for md in root.rglob("*.md"):
    for ref in re.findall(r'(?:src|href)="([^"]+)"|\]\(([^)]+)\)', md.read_text()):
        ref = next(r for r in ref if r)
        if re.match(r"(https?:|mailto:|#)", ref): continue
        if not (md.parent / ref.split("#")[0]).resolve().exists():
            print(f"        broken: {md.relative_to(root)} -> {ref}"); bad += 1
sys.exit(1 if bad else 0)
PY
}
no_leftovers() { ! grep -rqE '\{\{[A-Z][A-Z0-9_]*\}\}' "$@"; }

echo "-- org render (profile in <org>/.github/profile)"
if bash "$HERE/render.sh" --values "$TMP/org.yaml" --out "$TMP/org/.github" --apply >/dev/null; then
  no_leftovers "$TMP/org" && ok "org: zero leftover placeholders" || bad "org: leftover placeholders"
  grep -q '^# Acme Labs' "$TMP/org/.github/profile/README.md" && ok "org: full profile page in .github/profile/README.md" || bad "org: profile page missing"
  [ -f "$TMP/org/.github/profile/assets/avatar.gif" ] && ok "org: avatar in .github/profile/assets/" || bad "org: avatar not copied"
  links_resolve "$TMP/org" && ok "org: every relative link resolves" || bad "org: broken relative links"
else bad "org: render failed"; fi

echo "-- user render (profile in <user>/<user>, pointer in .github)"
if bash "$HERE/render.sh" --values "$TMP/user.yaml" --out "$TMP/user/.github" --profile-out "$TMP/user/acme" --apply >/dev/null; then
  no_leftovers "$TMP/user" && ok "user: zero leftover placeholders" || bad "user: leftover placeholders"
  grep -q '^# Acme Labs' "$TMP/user/acme/README.md" && ok "user: full profile page in <user>/<user>/README.md" || bad "user: profile repo README missing"
  [ -f "$TMP/user/acme/assets/avatar.gif" ] && ok "user: avatar in <user>/<user>/assets/" || bad "user: avatar not copied"
  grep -q 'github.com/acme/acme' "$TMP/user/.github/profile/README.md" && ! grep -q '^# Acme Labs' "$TMP/user/.github/profile/README.md" \
    && ok "user: .github/profile/README.md is a pointer, not a second copy" || bad "user: .github/profile is not a pointer"
  [ ! -e "$TMP/user/.github/profile/assets" ] && ok "user: no duplicate assets in .github" || bad "user: assets duplicated into .github"
  links_resolve "$TMP/user/acme" && ok "user: every relative link in the profile repo resolves" || bad "user: broken relative links"
else bad "user: render failed"; fi

echo "-- negative controls (a check that cannot fail is not a check)"
refuses() {  # $1 label, rest = render args
  local label="$1"; shift
  if bash "$HERE/render.sh" "$@" --apply >/dev/null 2>&1; then bad "render accepted: $label"
  elif [ -e "$TMP/neg" ]; then bad "render wrote files before refusing: $label"
  else ok "render refuses, writes nothing: $label"; fi
}
variant org "$TMP/missing.yaml" TAGLINE
refuses "missing TAGLINE" --values "$TMP/missing.yaml" --out "$TMP/neg"
refuses "user without --profile-out" --values "$TMP/user.yaml" --out "$TMP/neg"
refuses "org with --profile-out" --values "$TMP/org.yaml" --out "$TMP/neg" --profile-out "$TMP/neg/p"
sed 's/^ACCOUNT_KIND: .*/ACCOUNT_KIND: team/' "$TMP/org.yaml" > "$TMP/kind.yaml"
refuses "ACCOUNT_KIND team" --values "$TMP/kind.yaml" --out "$TMP/neg"
printf '[broken](./nope.md)\n' > "$TMP/org/.github/broken.md"
links_resolve "$TMP/org" >/dev/null && bad "link check accepted a broken link" || ok "link check catches a broken link"

echo "-- hygiene"
if grep -rnEI '(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY)' "$HERE" --exclude=verify.sh; then bad "secret-shaped string"; else ok "no secret-shaped strings"; fi
if grep -rnE '/home/[a-z]|/Users/[A-Za-z]' "$HERE/template" "$HERE/values.example.yaml"; then bad "machine-specific path in template"; else ok "no machine-specific paths"; fi
if grep -rniE '@[a-z0-9-]+\.(com|io|ai|net|org)\b' "$HERE/template"; then bad "real-looking email in template (use a placeholder)"; else ok "no hard-coded emails in template"; fi

echo; [ $fail -eq 0 ] && echo "verify: PASS" || echo "verify: $fail check(s) failed"
exit $([ $fail -eq 0 ] && echo 0 || echo 1)
