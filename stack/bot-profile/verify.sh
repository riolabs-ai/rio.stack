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
         profile/.env.example bot/botforge-template.json render-bot.sh install.sh verify.sh \
         template-v1.lock.yaml; do
  [ -s "$HERE/$f" ] && ok "present: $f" || bad "missing or empty: $f"
done

# --- 2. the persona is resolved, then asserted as a whole document ---------------------------
# The renderer is the only supported import path: bot-forge falls back to a generic render_soul()
# when soul_md is absent, so a bare template file would import the wrong persona silently.
RENDERED="$(mktemp "${TMPDIR:-/tmp}/bot-profile-render.XXXXXX.json")"
COUNTFILE="$(mktemp "${TMPDIR:-/tmp}/bot-profile-fails.XXXXXX")"
trap 'rm -f "$RENDERED" "$COUNTFILE"' EXIT
if bash "$HERE/render-bot.sh" --out "$RENDERED" 2>/dev/null && [ -s "$RENDERED" ]; then
  ok "render-bot.sh resolves soul_md_ref into an import-ready template"
else
  bad "render-bot.sh cannot resolve soul_md_ref"
  printf '{"soul_md": ""}\n' > "$RENDERED"
fi

"$PY" - "$HERE" "$RENDERED" "$COUNTFILE" <<'PY'
import hashlib, json, pathlib, sys, yaml

root = pathlib.Path(sys.argv[1]).resolve()
rendered_path = pathlib.Path(sys.argv[2])
bad = 0


def ok(msg):
    print(f"  ok    {msg}")


def no(msg):
    global bad
    bad += 1
    print(f"  FAIL  {msg}")


PERSONA = root / "profile/SOUL.md"
TEMPLATE = root / "bot/botforge-template.json"
LOCK = root / "template-v1.lock.yaml"
CONFIG = root / "profile/config.yaml"
DIST = root / "profile/distribution.yaml"

# --- the bot half parses, and carries a reference instead of a body ------------------------
bot = None
try:
    bot = json.loads(TEMPLATE.read_text())
    need = {"format", "version", "display_name", "role", "description", "one_job", "soul_md_ref",
            "memory", "toolsets", "routines"}
    missing = need - set(bot)
    assert bot["format"] == "bot-forge/template", f"format is {bot['format']!r}"
    assert bot["version"] == 1, f"version is {bot['version']!r}"
    assert not missing, f"template missing {sorted(missing)}"
    ok(f"bot template parses ({bot['format']} v{bot['version']}, "
       f"{len(bot['toolsets'])} toolsets, {len(bot['routines'])} routine(s))")
except Exception as exc:
    no(f"bot template: {exc}")

# --- one persona source: profile/SOUL.md, referenced and never duplicated ------------------
if bot is not None:
    if "soul_md" in bot:
        no("bot template inlines soul_md — the persona has exactly one source "
           "(profile/SOUL.md, resolved by render-bot.sh); delete the copy")
    ref = bot.get("soul_md_ref")
    try:
        resolved = (TEMPLATE.parent / str(ref)).resolve()
        assert resolved == PERSONA, f"soul_md_ref resolves to {resolved}, not {PERSONA}"
        ok(f"persona single-source: soul_md_ref {ref!r} resolves to profile/SOUL.md")
    except Exception as exc:
        no(f"soul_md_ref: {exc}")

# --- the persona is compared as a whole document, not by its first line --------------------
if bot is not None:
    try:
        rendered = json.loads(rendered_path.read_text(encoding="utf-8"))
        got = rendered["soul_md"].encode("utf-8")
        want = PERSONA.read_bytes()
        if got != want:
            at = next((i for i, (a, b) in enumerate(zip(got, want)) if a != b), min(len(got), len(want)))
            raise AssertionError(
                f"rendered soul_md != profile/SOUL.md ({len(got)} vs {len(want)} bytes; "
                f"first difference at byte {at})")
        extra = set(rendered) - set(bot) - {"soul_md"}
        absent = set(bot) - set(rendered) - {"soul_md_ref"}
        assert not extra, f"render invented keys: {sorted(extra)}"
        assert not absent, f"render dropped keys: {sorted(absent)}"
        ok(f"rendered soul_md == profile/SOUL.md byte-for-byte "
           f"({len(want)} bytes, {len(want.splitlines())} lines, {len(bot)} keys preserved)")
    except Exception as exc:
        no(f"persona document: {exc}")

# --- and it lives in exactly one file: no second copy to drift ----------------------------
try:
    body = PERSONA.read_bytes()
    copies = [p.relative_to(root).as_posix() for p in root.rglob("*")
              if p.is_file() and ".git" not in p.parts and p != PERSONA and p.read_bytes() == body]
    assert not copies, f"the persona body also lives in {copies} — one source only"
    ok("persona body exists in exactly one file")
except Exception as exc:
    no(f"persona copies: {exc}")

# --- the lock is enforced, not decorative: a stale pin or a bogus key must fail -----------
lock = {}
try:
    lock = yaml.safe_load(LOCK.read_text()) or {}
    ok(f"parses: template-v1.lock.yaml ({len(lock)} top-level keys)")
except Exception as exc:
    no(f"parses: template-v1.lock.yaml: {exc}")
try:
    cfg = yaml.safe_load(CONFIG.read_text()) or {}
    ok(f"parses: profile/config.yaml ({len(cfg)} top-level keys)")
except Exception as exc:
    cfg = {}
    no(f"parses: profile/config.yaml: {exc}")

if lock and bot is not None:
    pinned = (lock.get("pinned") or {}).get("bot") or {}
    drift = []
    for key in ("file", "format", "version", "display_name", "role", "one_job"):
        want = "bot/botforge-template.json" if key == "file" else bot.get(key)
        if pinned.get(key) != want:
            drift.append(f"{key}: locked {pinned.get(key)!r} != template {want!r}")
    if pinned.get("toolsets") != bot["toolsets"]:
        drift.append(f"toolsets: locked {len(pinned.get('toolsets') or [])} "
                     f"{pinned.get('toolsets')} != template {len(bot['toolsets'])} {bot['toolsets']}")
    if pinned.get("routines") != len(bot["routines"]):
        drift.append(f"routines: locked {pinned.get('routines')} != template {len(bot['routines'])}")
    if drift:
        no("lock pins drift from the bot template: " + "; ".join(drift))
    else:
        ok(f"lock pins hold for the bot half ({len(bot['toolsets'])} toolsets, "
           f"{len(bot['routines'])} routine, one_job, role, display_name)")

    ppin = (lock.get("pinned") or {}).get("profile") or {}
    if ppin.get("file") != "profile/config.yaml" or ppin.get("distribution") != "profile/distribution.yaml":
        no(f"lock points the profile half at {ppin.get('file')!r} / "
           f"{ppin.get('distribution')!r}, not profile/config.yaml / profile/distribution.yaml")

    def flat(node, prefix=()):
        if isinstance(node, dict):
            for k, v in node.items():
                yield from flat(v, prefix + (str(k),))
        else:
            yield ".".join(prefix)

    actual = set(flat(cfg))
    locked = set(ppin.get("keys") or [])
    if bot is not None and locked != actual:
        no(f"lock keys != profile/config.yaml keys — unpinned: {sorted(actual - locked)}; "
           f"pinned but absent: {sorted(locked - actual)}")
    elif locked:
        ok(f"lock pins all {len(actual)} config keys and no more")

    try:
        dist = yaml.safe_load(DIST.read_text()) or {}
        want = (lock.get("layer"), str(lock.get("version")))
        got = (dist.get("name"), str(dist.get("version")))
        assert got == want, f"distribution {got} != lock layer/version {want}"
        ok(f"distribution manifest matches the lock ({dist.get('name')} v{dist.get('version')})")
    except Exception as exc:
        no(f"distribution manifest: {exc}")

# --- the persona pin: any edited line fails, not just the first one -----------------------
try:
    ppin = (lock.get("pinned") or {}).get("persona") or {}
    digest = hashlib.sha256(PERSONA.read_bytes()).hexdigest()
    assert ppin.get("file") == "profile/SOUL.md", f"locked persona file is {ppin.get('file')!r}"
    assert ppin.get("sha256") == digest, (
        f"persona changed: locked {str(ppin.get('sha256'))[:12]}…, profile/SOUL.md is "
        f"{digest[:12]}… — edit and re-pin (template-v1.lock.yaml) in the same commit")
    ok(f"persona pin holds for the whole document (sha256 {digest[:12]}…)")
except Exception as exc:
    no(f"persona pin: {exc}")

pathlib.Path(sys.argv[3]).write_text(str(bad))
raise SystemExit(bad)
PY
rc=$?
if [ "$rc" -ne 0 ]; then
  # Count what the python block actually failed on, not just "it exited non-zero".
  pyfail="$(cat "$COUNTFILE" 2>/dev/null || true)"
  fail=$((fail + ${pyfail:-1}))
fi

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
