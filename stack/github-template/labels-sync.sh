#!/usr/bin/env bash
# Create or update the standard labels on one repo. Never deletes a label.
#
#   bash labels-sync.sh --repo owner/name [--file template/labels.yml]           # dry run
#   bash labels-sync.sh --repo owner/name [--file template/labels.yml] --apply   # write via gh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO=""; FILE="$HERE/template/labels.yml"; APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:?}"; shift 2 ;;
    --file) FILE="${2:?}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) sed -n '2,5p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$REPO" ] || { echo "usage: bash labels-sync.sh --repo owner/name [--apply]" >&2; exit 2; }
"${PYTHON:-python3}" - "$FILE" <<'PYEOF' |
import sys, yaml
for l in yaml.safe_load(open(sys.argv[1])):
    print("\t".join([l["name"], str(l["color"]), l.get("description", "")]))
PYEOF
while IFS=$'\t' read -r name color desc; do
  if [ "$APPLY" = 1 ]; then
    gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" --force >/dev/null && echo "  set   $name"
    sleep 1
  else
    echo "  would set  $name ($color)"
  fi
done
