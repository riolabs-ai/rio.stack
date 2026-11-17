#!/usr/bin/env bash
# Read-only status of every project in registry.yaml.
#   bash status.sh [--offline] [--json] [--registry FILE]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${PYTHON:-python3}" "$HERE/tools/mc.py" status "$@"
