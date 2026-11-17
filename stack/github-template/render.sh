#!/usr/bin/env bash
# Render the GitHub template for one account or org.
#
#   org:  bash render.sh --values v.yaml --out <org>/.github [--apply]
#   user: bash render.sh --values v.yaml --out <user>/.github --profile-out <user>/<user> [--apply]
#
# Dry run by default: lists every file it would write and checks the values, writes nothing.
# Refuses (exit 1, nothing written) when a placeholder has no value, a value is empty,
# ACCOUNT_KIND is not org|user, or a user render has no --profile-out.
#
# Where the profile page goes:
#   org   -> <out>/profile/README.md + <out>/profile/assets/   (GitHub reads <org>/.github/profile)
#   user  -> <profile-out>/README.md + <profile-out>/assets/   (GitHub reads <user>/<user>)
#            and <out>/profile/README.md becomes a pointer to it, so there is one source.
# Never deletes anything; existing files at the same path are overwritten on --apply.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES=""; OUT=""; PROFILE_OUT=""; APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --values) VALUES="${2:?--values needs a file}"; shift 2 ;;
    --out) OUT="${2:?--out needs a dir}"; shift 2 ;;
    --profile-out) PROFILE_OUT="${2:?--profile-out needs a dir}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) sed -n '2,15p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$VALUES" ] && [ -n "$OUT" ] || { echo "usage: bash render.sh --values <file> --out <dir> [--profile-out <dir>] [--apply]" >&2; exit 2; }
exec "${PYTHON:-python3}" - "$HERE/template" "$VALUES" "$OUT" "$PROFILE_OUT" "$APPLY" <<'PY'
import pathlib, re, shutil, sys, yaml
tpl, values_path, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
profile_out = pathlib.Path(sys.argv[4]) if sys.argv[4] else None
apply = sys.argv[5] == "1"
PH = re.compile(r"\{\{([A-Z][A-Z0-9_]*)\}\}")
def die(msg): print(f"render: {msg}", file=sys.stderr); sys.exit(1)

values = yaml.safe_load(values_path.read_text()) or {}
values = {k: ("" if v is None else str(v)) for k, v in values.items()}
kind = values.get("ACCOUNT_KIND", "")
if kind not in ("org", "user"): die(f"ACCOUNT_KIND must be org or user, got {kind!r}")
if kind == "user" and profile_out is None: die("ACCOUNT_KIND user needs --profile-out <user>/<user> (that repo is the profile page)")
if kind == "org" and profile_out is not None: die("--profile-out is only for ACCOUNT_KIND user; an org profile lives in .github/profile")

files = sorted(p for p in tpl.rglob("*") if p.is_file())
used = set()
for p in files: used |= set(PH.findall(p.read_text()))
missing = sorted(k for k in used if not values.get(k, "").strip())
if missing: die("missing or empty values: " + ", ".join(missing))

def render(p):
    text = PH.sub(lambda m: values[m.group(1)], p.read_text())
    if PH.findall(text): die(f"{p.relative_to(tpl)} still has {PH.findall(text)}")
    return text

plan = []   # (destination, text)
profile_page = render(tpl / "profile" / "README.md")
for p in files:
    rel = p.relative_to(tpl)
    if rel.parts[0] == "_user" or rel == pathlib.Path("profile/README.md"):
        continue
    plan.append((out / rel, render(p)))
if kind == "org":
    plan.append((out / "profile" / "README.md", profile_page))
    assets = out / "profile" / "assets"
else:
    plan.append((out / "profile" / "README.md", render(tpl / "_user" / "profile-pointer.md")))
    plan.append((profile_out / "README.md", profile_page))
    assets = profile_out / "assets"

mode = "apply" if apply else "dry-run"
print(f"render: {kind} '{values['ORG_NAME']}', {len(used)} placeholders, {len(plan)} files  [{mode}]")
for dest, text in plan:
    print(f"  {'write' if apply else 'would write'}  {dest}")
    if apply:
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(text)
src = values.get("AVATAR_SOURCE", "").strip()
avatar = assets / values["AVATAR_FILE"]
if src:
    if not pathlib.Path(src).is_file(): die(f"AVATAR_SOURCE not found: {src}")
    print(f"  {'copy' if apply else 'would copy'}  {src} -> {avatar}")
    if apply:
        avatar.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, avatar)
elif not avatar.exists():
    print(f"  note  no AVATAR_SOURCE and no {avatar}: add the avatar by hand")
PY
