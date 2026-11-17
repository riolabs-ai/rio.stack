#!/usr/bin/env bash
# Render the GitHub template into a ready-to-push <owner>/.github tree.
#
#   bash render.sh --values <file.yaml> --out <dir>           # dry run: list files, check values, write nothing
#   bash render.sh --values <file.yaml> --out <dir> --apply   # write it
#
# Refuses (exit 1) when a placeholder in template/ has no value, or a value is empty.
# Never deletes anything in --out; existing files with the same path are overwritten on --apply.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES=""; OUT=""; APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --values) VALUES="${2:?--values needs a file}"; shift 2 ;;
    --out) OUT="${2:?--out needs a dir}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) sed -n '2,8p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$VALUES" ] && [ -n "$OUT" ] || { echo "usage: bash render.sh --values <file> --out <dir> [--apply]" >&2; exit 2; }
exec "${PYTHON:-python3}" - "$HERE/template" "$VALUES" "$OUT" "$APPLY" <<'PY'
import pathlib, re, shutil, sys, yaml
tpl, values_path, out, apply = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]), sys.argv[4] == "1"
PH = re.compile(r"\{\{([A-Z][A-Z0-9_]*)\}\}")
values = yaml.safe_load(values_path.read_text()) or {}
values = {k: ("" if v is None else str(v)) for k, v in values.items()}
files = sorted(p for p in tpl.rglob("*") if p.is_file())
used = set()
for p in files:
    used |= set(PH.findall(p.read_text()))
missing = sorted(k for k in used if not values.get(k, "").strip())
mode = "apply" if apply else "dry-run"
print(f"render: {len(files)} files, {len(used)} placeholders -> {out}  [{mode}]")
if missing:
    print("render: missing or empty values: " + ", ".join(missing), file=sys.stderr)
    sys.exit(1)
for p in files:
    rel = p.relative_to(tpl)
    text = PH.sub(lambda m: values[m.group(1)], p.read_text())
    left = PH.findall(text)
    if left:
        print(f"render: {rel} still has {left}", file=sys.stderr); sys.exit(1)
    print(f"  {'write' if apply else 'would write'}  {rel}")
    if apply:
        dest = out / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(text)
src = values.get("AVATAR_SOURCE", "").strip()
if src:
    dest = out / "profile" / "assets" / values["AVATAR_FILE"]
    print(f"  {'copy' if apply else 'would copy'}  {src} -> {dest.relative_to(out)}")
    if apply:
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dest)
else:
    print("  note  no AVATAR_SOURCE: add profile/assets/" + values.get("AVATAR_FILE", "?") + " by hand")
if values.get("ACCOUNT_KIND") == "user":
    o = values.get("ORG_NAME")
    print(f"  note  personal account: the profile page is the README of {o}/{o}; copy profile/ there")
PY
