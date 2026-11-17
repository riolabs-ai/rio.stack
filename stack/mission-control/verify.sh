#!/usr/bin/env bash
# Prove mission control reads what it claims and rejects what it should.
#   bash verify.sh     # exit 0 = shippable
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PY=${PYTHON:-python3}
fail=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }
echo "verify: mission-control v1 ($HERE)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/mc.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT

echo "-- files"
mapfile -t FILES < <("$PY" -c 'import sys,yaml; [print(f) for f in yaml.safe_load(open(sys.argv[1]))["pinned"]["files"]]' "$HERE/mission-control-v1.lock.yaml")
for f in "${FILES[@]}"; do [ -s "$HERE/$f" ] && ok "present: $f" || bad "missing or empty: $f"; done
for f in $("$PY" -c 'import sys,yaml; [print(f) for f in yaml.safe_load(open(sys.argv[1]))["pinned"]["issue_forms"]]' "$HERE/mission-control-v1.lock.yaml"); do
  [ -s "$ROOT/$f" ] && ok "present: $f" || bad "missing: $f"
done

echo "-- lock and tool agree"
"$PY" - "$HERE" <<'PY' || fail=$((fail+1))
import importlib.util, pathlib, sys, yaml
h = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("mc", h / "tools/mc.py"); mc = importlib.util.module_from_spec(spec); spec.loader.exec_module(mc)
r = yaml.safe_load((h / "mission-control-v1.lock.yaml").read_text())["pinned"]["registry"]
bad = 0
for name, a, b in [("statuses", set(r["statuses"]), mc.STATUSES), ("domains", set(r["domains"]), mc.DOMAINS),
                   ("required", set(r["required"]), set(mc.REQUIRED))]:
    if a != b: print(f"  FAIL  {name} differ: {sorted(a ^ b)}"); bad += 1
    else: print(f"  ok    {name} agree ({len(a)})")
ex = yaml.safe_load((h / "project.example.yaml").read_text())
if ex.get("schema") != "rio.project/v1": print("  FAIL  project.example.yaml schema"); bad += 1
else: print("  ok    project.example.yaml schema rio.project/v1")
sys.exit(1 if bad else 0)
PY

echo "-- registry"
"$PY" "$HERE/tools/mc.py" validate && ok "registry.yaml validates" || bad "registry.yaml invalid"
"$PY" "$HERE/tools/mc.py" status --offline --json > "$TMP/status.json" && "$PY" -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMP/status.json" \
  && ok "status --offline --json runs and emits JSON" || bad "status --offline failed"

echo "-- negative controls (each must FAIL validation)"
neg() {  # $1 label, $2 python expression mutating `r`
  "$PY" - "$HERE/registry.yaml" "$TMP/neg.yaml" "$2" <<'PY'
import sys, yaml
r = yaml.safe_load(open(sys.argv[1])); exec(sys.argv[3]); yaml.safe_dump(r, open(sys.argv[2], "w"))
PY
  if "$PY" "$HERE/tools/mc.py" validate --registry "$TMP/neg.yaml" >/dev/null 2>&1; then bad "accepted: $1"; else ok "rejected: $1"; fi
}
neg "unknown status"        'r["projects"][0]["status"] = "yolo"'
neg "unknown domain"        'r["projects"][0]["domain"] = "misc"'
neg "duplicate id"          'r["projects"].append(dict(r["projects"][0]))'
neg "missing field"         'r["projects"][0].pop("target")'
neg "phantom layer version" 'r["projects"][0]["layers"] = {"github-template": "9.9.9"}'
neg "unknown layer"         'r["projects"][0]["layers"] = {"no-such-layer": "1.0.0"}'
neg "nothing to administer" 'r["projects"][0]["repo"] = None; r["projects"][0]["local"] = None'

echo
[ "$fail" -eq 0 ] && echo "PASS" || { echo "FAIL ($fail)"; exit 1; }
