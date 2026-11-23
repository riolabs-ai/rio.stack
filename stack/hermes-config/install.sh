#!/usr/bin/env bash
# Render the hermes-config layer onto a Hermes install.
#
#   bash install.sh                        # DRY RUN — the default. Prints every decision, writes nothing.
#   bash install.sh --apply                # write the keys the layer owns
#   bash install.sh --apply --force        # also overwrite keys whose live value differs
#   bash install.sh --profile <name>       # limit to one profile (repeatable)
#   bash install.sh --help
#
# Dry run is the default: this layer changes the configuration of a running fleet, so the first
# invocation must be free. Nothing is written without --apply, and a key whose live value differs
# from the layer's is a CONFLICT that --apply leaves alone unless --force is passed.
#
# It never writes a secret. The layer renders secret REFERENCES (an env var name, a token's env
# key), never a value; every key under secrets.* is refused except secrets.bitwarden.enabled, which
# is a boolean that says whether a profile syncs a store at all.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=${PYTHON:-python3}
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
APPLY=0
FORCE=0
PROFILES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --force) FORCE=1; shift ;;
    --profile) PROFILES+=("${2:?--profile needs a name}"); shift 2 ;;
    --dry-run) APPLY=0; shift ;;
    -h|--help) sed -n '2,17p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "install: unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v "$PY" >/dev/null || { echo "install: no python3 on PATH" >&2; exit 2; }
[ -d "$HERMES_HOME" ] || { echo "install: no Hermes home at $HERMES_HOME" >&2; exit 2; }

MODE="dry-run"; [ "$APPLY" = 1 ] && MODE="apply"
echo "install: hermes-config layer → $HERMES_HOME  [$MODE]"

RENDER="$(mktemp -d "${TMPDIR:-/tmp}/hermes-config.XXXXXX")"
trap 'rm -rf "$RENDER"' EXIT
"$PY" "$HERE/tools/hermes_config_check.py" render --out "$RENDER" >/dev/null

# The plan: one TSV line per owned key. python reads the layer's render and the live configs and
# decides set / keep / conflict; bash performs the writes so every change goes through the
# sanctioned `hermes config set` path rather than an edit to a YAML file.
PLAN="$("$PY" - "$HERE" "$RENDER" "$HERMES_HOME" "${PROFILES[@]+"${PROFILES[@]}"}" <<'PY'
import json, pathlib, sys, yaml

here, render, home = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
only = set(sys.argv[4:])
lock = yaml.safe_load((here / "hermes-config.lock.yaml").read_text(encoding="utf-8")) or {}
pin = lock.get("pinned") or {}
skip_top = set((lock.get("install") or {}).get("not_hermes_keys") or ["role", "verification"])


def flatten(node, prefix=()):
    if isinstance(node, dict):
        for k, v in node.items():
            yield from flatten(v, prefix + (str(k),))
    else:
        yield ".".join(prefix), node


def live_path(profile):
    return home / "config.yaml" if profile == "default" else home / "profiles" / profile / "config.yaml"


def load_live(profile):
    p = live_path(profile)
    if not p.is_file():
        return None
    try:
        return yaml.safe_load(p.read_text(encoding="utf-8")) or {}
    except Exception:
        return None


def get_path(node, dotted):
    cur = node
    for part in dotted.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


def owned(key):
    if key.split(".")[0] in skip_top:
        return False
    if key.startswith("secrets.") and key != "secrets.bitwarden.enabled":
        return False
    return True


def enc(value):
    """A scalar goes through as itself; a list or dict as JSON. `hermes config set` parses both."""
    if isinstance(value, str):
        return value
    return json.dumps(value)


for profile in pin.get("profiles") or {}:
    if only and profile not in only:
        continue
    config = yaml.safe_load((render / f"{profile}.config.yaml").read_text(encoding="utf-8")) or {}
    live = load_live(profile)
    if live is None:
        print(f"ABSENT\t{profile}\t-\t-")
        continue
    for key, want in flatten(config):
        if not owned(key):
            continue
        have = get_path(live, key)
        if have is None:
            print(f"SET\t{profile}\t{key}\t{enc(want)}")
        elif have == want:
            print(f"KEEP\t{profile}\t{key}\t{enc(want)}")
        else:
            print(f"CONFLICT\t{profile}\t{key}\t{enc(want)}")
PY
)"

sets=0; keeps=0; conflicts=0; absent=0; failed=0

while IFS=$'\t' read -r action profile key value; do
  [ -n "${action:-}" ] || continue
  case "$action" in
    SET)
      sets=$((sets+1))
      printf '  set      %-16s %-42s %s\n' "$profile" "$key" "$value"
      if [ "$APPLY" = 1 ]; then
        args=(); [ "$profile" != "default" ] && args=(-p "$profile")
        if ! hermes "${args[@]}" config set "$key" "$value" >/dev/null 2>&1; then
          printf '  FAILED   %-16s %s\n' "$profile" "$key"
          failed=$((failed+1))
        fi
      fi
      ;;
    KEEP)
      keeps=$((keeps+1))
      printf '  keep     %-16s %-42s %s\n' "$profile" "$key" "$value"
      ;;
    CONFLICT)
      conflicts=$((conflicts+1))
      if [ "$FORCE" = 1 ]; then
        printf '  overwrite %-15s %-42s %s\n' "$profile" "$key" "$value"
        if [ "$APPLY" = 1 ]; then
          args=(); [ "$profile" != "default" ] && args=(-p "$profile")
          if ! hermes "${args[@]}" config set "$key" "$value" >/dev/null 2>&1; then
            printf '  FAILED   %-16s %s\n' "$profile" "$key"
            failed=$((failed+1))
          fi
        fi
      else
        printf '  CONFLICT %-16s %-42s live value differs; --force overwrites\n' "$profile" "$key"
      fi
      ;;
    ABSENT)
      absent=$((absent+1))
      printf '  absent   %-16s no config at %s\n' "$profile" "$HERMES_HOME"
      ;;
  esac
done <<< "$PLAN"

# Charters: a persona is not something to overwrite by script. Write only when a profile has none.
souls=0
while IFS= read -r soul; do
  profile="$(basename "$soul" .SOUL.md)"
  if [ "${#PROFILES[@]}" -gt 0 ] && [[ " ${PROFILES[*]} " != *" $profile "* ]]; then continue; fi
  if [ "$profile" = "default" ]; then target="$HERMES_HOME/SOUL.md"; else target="$HERMES_HOME/profiles/$profile/SOUL.md"; fi
  [ -d "$(dirname "$target")" ] || continue
  if [ -f "$target" ]; then
    printf '  keep     %-16s SOUL.md (an existing persona wins)\n' "$profile"
  else
    souls=$((souls+1))
    printf '  write    %-16s SOUL.md\n' "$profile"
    [ "$APPLY" = 1 ] && cp "$soul" "$target"
  fi
done < <(find "$RENDER" -name '*.SOUL.md' | sort)

echo "install: set=$sets keep=$keeps conflict=$conflicts absent=$absent charters=$souls"
if [ "$APPLY" = 0 ]; then
  echo "install: dry run — nothing written. Re-run with --apply to write."
elif [ "$failed" -gt 0 ]; then
  echo "install: applied with $failed failed key(s)." >&2
  exit 1
elif [ "$conflicts" -gt 0 ] && [ "$FORCE" = 0 ]; then
  echo "install: applied; $conflicts conflict(s) left alone. Re-run with --force to overwrite."
else
  echo "install: applied."
fi
