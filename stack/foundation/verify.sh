#!/usr/bin/env bash
# verify.sh — mechanical checks for the foundation requirements layer.
# Only requirements with check: verify.sh::<id> are enforced here; the rest are
# manual/observational and are listed at the end so they are not silently ignored.
# Exit 0 = every enforced requirement passed. Exit 1 = at least one failure.
set -uo pipefail

HOME_DIR="${HOME:-/home/$(id -un)}"
HERMES_HOME="${HERMES_HOME:-$HOME_DIR/.hermes}"
PROFILES=(default rio infra blueberry rory)
fail=0
declare -a FAILED=()

pass() { printf '  PASS  %-6s %s\n' "$1" "$2"; }
warn() { printf '  WARN  %-6s %s\n' "$1" "$2"; }
bad()  { printf '  FAIL  %-6s %s\n' "$1" "$2"; fail=1; FAILED+=("$1"); }

hcfg() { # hcfg <profile> <key>
  local p="$1" k="$2"
  if [ "$p" = default ]; then hermes config get "$k" 2>/dev/null
  else hermes -p "$p" config get "$k" 2>/dev/null; fi
}

echo "foundation verify — $(date -Is)"
echo "hermes home: $HERMES_HOME"

# ── R-03 · cwd is a git repo or $HOME ────────────────────────────────────────
echo; echo "R-03  working directory"
for p in "${PROFILES[@]}"; do
  [ -d "$HERMES_HOME/profiles/$p" ] || [ "$p" = default ] || continue
  cwd=$(hcfg "$p" terminal.cwd | tr -d '"' | head -1)
  [ -z "$cwd" ] && cwd="$HOME_DIR"
  cwd="${cwd/#\~/$HOME_DIR}"
  if [ ! -d "$cwd" ]; then
    bad R-03 "$p cwd missing: $cwd"
  elif [ "$cwd" = "$HOME_DIR" ]; then
    pass R-03 "$p cwd = HOME (neutral)"
  elif git -C "$cwd" rev-parse --show-toplevel >/dev/null 2>&1; then
    pass R-03 "$p cwd inside repo ($cwd)"
  else
    bad R-03 "$p cwd is neither a repo nor HOME: $cwd"
  fi
done

# ── R-05 · no world/group-readable secrets ───────────────────────────────────
echo; echo "R-05  secret file modes"
leaks=0
while IFS= read -r f; do
  [ -e "$f" ] || continue
  m=$(stat -c '%a' "$f" 2>/dev/null || echo "?")
  case "$m" in 600|400) ;; *) leaks=$((leaks+1)); bad R-05 "mode $m: $f";; esac
done < <(ls -1 "$HERMES_HOME/.env" "$HERMES_HOME"/profiles/*/.env "$HERMES_HOME"/auth.json 2>/dev/null)
while IFS= read -r d; do
  [ -n "$d" ] || continue
  m=$(stat -c '%a' "$d" 2>/dev/null || echo "?")
  case "$m" in 700|750) ;; *) leaks=$((leaks+1)); bad R-05 "dir mode $m: $d";; esac
done < <(find "$HOME_DIR" -maxdepth 4 -type d -name '.secrets' 2>/dev/null)
[ "$leaks" -eq 0 ] && pass R-05 "all secret files 600, secret dirs 700"

# ── R-06 · backup exists, key is outside the ciphertext ──────────────────────
echo; echo "R-06  sealed backup"
KEY="$HOME_DIR/.config/age/hermes-backup.key"
if [ ! -f "$KEY" ]; then
  bad R-06 "no age key at $KEY"
else
  km=$(stat -c '%a' "$KEY"); [ "$km" = "600" ] && pass R-06 "key mode 600" || bad R-06 "key mode $km"
fi
snapdir="$HERMES_HOME/secrets-backup"
n=$(ls -1 "$snapdir"/*.tar.age 2>/dev/null | wc -l)
[ "$n" -gt 0 ] && pass R-06 "$n encrypted snapshot(s)" || bad R-06 "no snapshots in $snapdir"
if [ -f "$snapdir/$(ls -1t "$snapdir"/*.tar.age 2>/dev/null | head -1 | xargs -r basename)" ] 2>/dev/null; then
  if tar -tf <(age -d -i "$KEY" "$(ls -1t "$snapdir"/*.tar.age | head -1)" 2>/dev/null) 2>/dev/null | grep -q 'hermes-backup.key'; then
    bad R-06 "private key is inside the snapshot"
  else
    pass R-06 "private key absent from newest snapshot"
  fi
fi
if systemctl --user is-enabled secrets-backup.timer >/dev/null 2>&1; then
  systemctl --user is-active secrets-backup.timer >/dev/null 2>&1 \
    && pass R-06 "timer active (next: $(systemctl --user show -p NextElapseUSecRealtime --value secrets-backup.timer 2>/dev/null))" \
    || bad R-06 "timer enabled but not active"
else
  warn R-06 "no secrets-backup.timer — backups are manual"
fi

# ── R-12 · durable worktree naming (prune protection) ────────────────────────
echo; echo "R-12  durable worktree naming"
wtroot="$HERMES_HOME/worktrees"
if [ -d "$wtroot" ]; then
  total=$(find "$wtroot" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | wc -l)
  ok=$(find "$wtroot" -mindepth 2 -maxdepth 2 -type d -name 't_*' 2>/dev/null | wc -l)
  if [ "$total" -eq 0 ]; then warn R-12 "no worktrees present"
  elif [ "$ok" -eq "$total" ]; then pass R-12 "$ok/$total conform to t_<hex>"
  else warn R-12 "$((total-ok))/$total worktrees do NOT match t_<hex> (prune-exposed history)"; fi
else
  warn R-12 "no worktree root at $wtroot"
fi

# ── R-31 · one source per plugin name (fleet-wide; upstream #150414) ──
# PM stages every source dir into ONE uv workspace. Only plugins that ship a pyproject
# become workspace members, so only those can collide. Predicate:
#   enabled anywhere AND (name present with a pyproject in more than one source dir)
echo; echo "R-31  plugin source uniqueness"
dups=$(python3 - "$HERMES_HOME" <<'PY'
import glob, os, sys, yaml
home = sys.argv[1]
def has_py(d):
    return os.path.exists(os.path.join(d, "pyproject.toml"))
src = {"<user>": [p for p in glob.glob(f"{home}/plugins/*") if os.path.isdir(p) and has_py(p)]}
for d in glob.glob(f"{home}/profiles/*/plugins/*"):
    if os.path.isdir(d) and has_py(d):
        src.setdefault(d.split("/profiles/")[1].split("/")[0], []).append(d)
enabled = {}
try:
    root = yaml.safe_load(open(f"{home}/config.yaml")) or {}
    enabled["<default>"] = (root.get("plugins") or {}).get("enabled") or []
except Exception:
    pass
for cfg in glob.glob(f"{home}/profiles/*/config.yaml"):
    prof = cfg.split("/profiles/")[1].split("/")[0]
    try:
        doc = yaml.safe_load(open(cfg)) or {}
    except Exception:
        continue
    enabled[prof] = (doc.get("plugins") or {}).get("enabled") or []
owner = {}
for prof, names in enabled.items():
    for n in names:
        owner.setdefault(n, []).append(prof)
for name, profs in owner.items():
    dirs = [k for k, v in src.items() if any(os.path.basename(d) == name for d in v)]
    if len(dirs) > 1:
        print(f"{name}: {'+'.join(dirs)} (enabled in {','.join(profs)})")
PY
)
if [ -z "$dups" ]; then
  pass R-31 "every enabled python plugin resolves from one source dir"
else
  bad R-31 "$(echo "$dups" | wc -l) enabled python plugin(s) staged from >1 source: $(echo "$dups" | head -3 | tr '\n' ' ')"
fi

# ── R-30 · every config file parses (silent-default mode is a total failure) ──
echo; echo "R-30  config validity"
for p in "${PROFILES[@]}"; do
  [ -d "$HERMES_HOME/profiles/$p" ] || [ "$p" = default ] || continue
  out=$(hcfg "$p" _config_version 2>&1; hermes ${p:+$([ "$p" = default ] || echo "-p $p")} config check 2>&1)
  if echo "$out" | grep -qiE "formatting error|invalid YAML|not valid YAML"; then
    bad R-30 "$p config does not parse — that profile is running on defaults"
  else
    pass R-30 "$p config parses"
  fi
done

# ── R-17 · toolsets resolve per profile ──────────────────────────────────────
echo; echo "R-17  toolsets present"
for p in "${PROFILES[@]}"; do
  [ -d "$HERMES_HOME/profiles/$p" ] || [ "$p" = default ] || continue
  ts=$(hcfg "$p" platform_toolsets | tr -d '[]" ' | tr ',' ' ')
  if [ -z "$ts" ] || echo "$ts" | grep -qi 'none'; then
    warn R-17 "$p has no explicit toolset (inherits all)"
  else
    pass R-17 "$p -> $(echo "$ts" | wc -w) toolset(s)"
  fi
done

# ── R-18 · every enabled plugin resolves and loads ───────────────────────────
echo; echo "R-18  plugin resolution"
plugbad=0
for p in "${PROFILES[@]}"; do
  [ -d "$HERMES_HOME/profiles/$p" ] || [ "$p" = default ] || continue
  for name in $(hcfg "$p" plugins.enabled | grep -E '^\s+-' | sed -E 's/^\s*-\s*//; s/["'\'']//g' | tr -d ' \t'); do
    if [ -d "$HERMES_HOME/plugins/$name" ] || [ -d "$HERMES_HOME/profiles/$p/plugins/$name" ] \
       || [ -d "$HERMES_HOME/hermes-agent/plugins/$name" ]; then
      :
    else
      bad R-18 "$p enables '$name' but no plugin dir resolves"; plugbad=$((plugbad+1))
    fi
  done
done
[ "$plugbad" -eq 0 ] && pass R-18 "every enabled plugin name resolves to a real plugin dir"

# ── Manual requirements (recorded so they are not forgotten) ─────────────────
echo
echo "Manual / observational (not machine-checkable here):"
printf '  %-6s %s\n' R-01 "profile isolation — diff effective config per profile" \
  R-02 "charter prohibitions mapped to mechanisms" \
  R-04 "per-profile live provider call" \
  R-07 "board as sole source of in-flight truth" \
  R-08 "completion refused when contract fails" \
  R-09 "block stops the bound worker" \
  R-10 "branch claimed by one card" \
  R-11 "restart counts as interrupted, not failed" \
  R-13 "settings apply without restart" \
  R-14 "reply under 500 words or artifact-wrapped" \
  R-15 "finding leads the reply" \
  R-16 "load-bearing claims carry evidence" \
  R-19 "guard never blocks a session it cannot observe" \
  R-20 "fallback proven by live call" \
  R-21 "client memory does not leak across profiles" \
  R-22 "durable artifact for every lesson"

echo
if [ "$fail" -eq 0 ]; then
  echo "RESULT: pass (enforced requirements)"
  exit 0
else
  echo "RESULT: fail — ${#FAILED[@]} enforced failure(s): ${FAILED[*]}"
  exit 1
fi
