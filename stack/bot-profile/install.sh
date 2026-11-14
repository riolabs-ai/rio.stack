#!/usr/bin/env bash
# Merge the bot-profile template's config into an existing Hermes profile.
#
#   bash install.sh --profile <profile>            # dry run: print every decision, write nothing
#   bash install.sh --profile <profile> --apply    # write it
#   bash install.sh --profile <profile> --apply --force   # overwrite values already set
#
# --apply refuses while a file it would write still carries {{PLACEHOLDERS}}; pass
# --allow-placeholders to install a persona that will introduce itself as {{BOT_NAME}}.
#
# It never touches credentials. It never deletes a key. Kanban ceilings are printed in full because a
# stale ceiling is the one value here that quietly wrecks a host.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE=""
APPLY=0
FORCE=0
ALLOW_PLACEHOLDERS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="${2:?--profile needs a name}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --force) FORCE=1; shift ;;
    --allow-placeholders) ALLOW_PLACEHOLDERS=1; shift ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$PROFILE" ] || { echo "usage: bash install.sh --profile <name> [--apply] [--force] [--allow-placeholders]" >&2; exit 2; }

PY=${PYTHON:-python3}
command -v hermes >/dev/null || { echo "install: no 'hermes' on PATH" >&2; exit 2; }
command -v "$PY" >/dev/null || { echo "install: no python3" >&2; exit 2; }

PROFILE_ARGS=()
[ "$PROFILE" != "default" ] && PROFILE_ARGS=(-p "$PROFILE")

# Resolve the profile home the same way Hermes does.
if [ "$PROFILE" = "default" ]; then HOME_DIR="$HOME/.hermes"; else HOME_DIR="$HOME/.hermes/profiles/$PROFILE"; fi
[ -d "$HOME_DIR" ] || { echo "install: no such profile home: $HOME_DIR" >&2; exit 2; }

echo "install: bot-profile template v1 → profile '$PROFILE' ($HOME_DIR)  [$([ $APPLY = 1 ] && echo apply || echo dry-run)]"

# Flatten config.yaml into "dotted.key<TAB>json-value" lines, then decide each one.
mapfile -t ENTRIES < <("$PY" - "$HERE/profile/config.yaml" <<'PY'
import json, sys, yaml
def walk(node, prefix=()):
    if isinstance(node, dict):
        for k, v in node.items():
            yield from walk(v, prefix + (str(k),))
    else:
        yield ".".join(prefix), json.dumps(node)
data = yaml.safe_load(open(sys.argv[1])) or {}
for key, val in walk(data):
    print(f"{key}\t{val}")
PY
)

# --- placeholder gate, before anything is written --------------------------------------------
# The layer is authored in {{PLACEHOLDERS}}. A profile that receives one gets a bot that introduces
# itself as {{BOT_NAME}}, so --apply refuses before the first write. A dry run only reports what the
# gate would do. Only values count: a {{LIKE_THIS}} inside a YAML comment is documentation, not a key.
conf_phs=""
for entry in "${ENTRIES[@]}"; do
  ph="$(printf '%s' "${entry#*$'\t'}" | grep -ohE '\{\{[A-Z_]+\}\}' || true)"
  if [ -n "$ph" ]; then conf_phs="$conf_phs $ph"; fi
done
if [ -n "$conf_phs" ]; then
  conf_phs="$(printf '%s\n' $conf_phs | sort -u | tr '\n' ' ')"
fi
soul_phs=""
if [ ! -f "$HOME_DIR/SOUL.md" ]; then   # an existing persona wins; ours is never written over it
  soul_phs="$(grep -ohE '\{\{[A-Z_]+\}\}' "$HERE/profile/SOUL.md" 2>/dev/null | sort -u | tr '\n' ' ' || true)"
fi
gated=0
if [ -n "$conf_phs" ]; then
  printf '  GATE    config values carry placeholders: %s\n' "$conf_phs"; gated=1
fi
if [ -n "$soul_phs" ]; then
  printf '  GATE    SOUL.md would be written with placeholders: %s\n' "$soul_phs"; gated=1
fi
if [ $gated = 1 ] && [ $APPLY = 1 ] && [ $ALLOW_PLACEHOLDERS = 0 ]; then
  echo "install: refusing to apply — resolve the placeholders above in $HERE/profile and re-run." >&2
  echo "install: nothing written. (--allow-placeholders overrides; it installs a persona that says {{BOT_NAME}}.)" >&2
  exit 3
fi

sets=0 keeps=0 conflicts=0
for entry in "${ENTRIES[@]}"; do
  key="${entry%%$'\t'*}"; want="${entry#*$'\t'}"
  [ -n "$key" ] || continue
  have="$(hermes "${PROFILE_ARGS[@]}" config get "$key" --json 2>/dev/null | tr -d '\n' || true)"
  if [ -z "$have" ] || [ "$have" = "null" ]; then
    printf '  set      %-38s %s\n' "$key" "$want"
    sets=$((sets+1))
    if [ $APPLY = 1 ]; then hermes "${PROFILE_ARGS[@]}" config set "$key" "$want" >/dev/null; fi
  elif [ "$have" = "$want" ]; then
    printf '  keep     %-38s %s\n' "$key" "$want"
    keeps=$((keeps+1))
  elif [ $FORCE = 1 ]; then
    printf '  overwrite %-37s %s → %s\n' "$key" "$have" "$want"
    conflicts=$((conflicts+1))
    if [ $APPLY = 1 ]; then hermes "${PROFILE_ARGS[@]}" config set "$key" "$want" >/dev/null; fi
  else
    printf '  CONFLICT %-38s has %s, template wants %s\n' "$key" "$have" "$want"
    conflicts=$((conflicts+1))
  fi
done

echo "install: set=$sets keep=$keeps conflict=$conflicts"

# SOUL.md is only written when the profile has none: a persona is not something to overwrite by script.
SOUL="$HOME_DIR/SOUL.md"
if [ -f "$SOUL" ]; then
  echo "install: keep existing $SOUL"
elif [ $APPLY = 1 ]; then
  cp "$HERE/profile/SOUL.md" "$SOUL"
  echo "install: wrote $SOUL (replace {{PLACEHOLDERS}} before the bot runs)"
else
  echo "install: would write $SOUL"
fi

if [ $APPLY = 0 ]; then
  echo "install: dry run — nothing written. Re-run with --apply."
elif [ $conflicts -gt 0 ]; then
  echo "install: applied, but $conflicts key(s) conflicted and were left alone (see above)."
else
  echo "install: applied."
fi

cat <<'NOTE'

install: next steps, in order
  1. Replace every {{PLACEHOLDER}} in the profile's SOUL.md and config.
  2. install -m 600 <this layer>/profile/.env.example <profile home>/.env, then fill it from your
     secret manager — never by pasting into a chat or a card.
  3. Create the board (`hermes kanban boards create <slug>`) and set kanban.orchestrator_profile /
     default_assignee to real profiles, or dispatch has nobody to route to.
  4. Restart the gateway: kanban.max_spawn is read at boot, so the file change is inert until then.
     Confirm with: grep "kanban dispatcher: max_spawn" ~/.hermes/logs/gateway.log | tail -1
NOTE
