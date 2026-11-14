#!/usr/bin/env bash
# Render the import-ready bot template: resolve `soul_md_ref` against the one persona source.
#
#   bash render-bot.sh                      # JSON on stdout
#   bash render-bot.sh --out /tmp/lead.json # JSON to a file
#   import_agent path=/tmp/lead.json display_name="Lead"
#
# The layer keeps exactly one copy of the persona (`profile/SOUL.md`); the bot template carries a
# reference and never a second body. `bot-forge` falls back to render_soul() — a generic persona,
# silently — when `soul_md` is absent, so an import goes through this renderer, never the bare file.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=${PYTHON:-python3}
OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="${2:?--out needs a path}"; shift 2 ;;
    -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "render: unknown argument: $1" >&2; exit 2 ;;
  esac
done
command -v "$PY" >/dev/null || { echo "render: no python3" >&2; exit 2; }

"$PY" - "$HERE" "$OUT" <<'PY'
import json, pathlib, sys

root = pathlib.Path(sys.argv[1]).resolve()
out = sys.argv[2]
tpl_path = root / "bot/botforge-template.json"

tpl = json.loads(tpl_path.read_text())
ref = tpl.get("soul_md_ref")
if not ref:
    raise SystemExit(f"render: {tpl_path} carries no soul_md_ref")
if "soul_md" in tpl:
    raise SystemExit("render: the template inlines soul_md as well as soul_md_ref — one source, not two")

persona = (tpl_path.parent / ref).resolve()
if not persona.is_file():
    raise SystemExit(f"render: soul_md_ref {ref!r} does not resolve to a file ({persona})")

# Keep key order and put the resolved persona exactly where the reference stood, so the rendered
# file diffs cleanly against the template.
rendered = {}
for key, value in tpl.items():
    rendered["soul_md" if key == "soul_md_ref" else key] = persona.read_bytes().decode() if key == "soul_md_ref" else value

text = json.dumps(rendered, indent=2, ensure_ascii=False) + "\n"
if out:
    pathlib.Path(out).write_text(text, encoding="utf-8")
else:
    sys.stdout.write(text)
PY
