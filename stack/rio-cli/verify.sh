#!/usr/bin/env bash
# Prove the rio-cli layer is shippable.
#
#   bash stack/rio-cli/verify.sh
#
# Installs into a throwaway RIO_HOME, runs `rioctl init` preview and --write in a
# temp git repo, checks the files, and deletes the temps. Never touches the
# real ~/.rio, ~/.bashrc, or the Hermes rio wrapper.
set -euo pipefail

HERE="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(CDPATH= cd -- "$HERE/../.." && pwd)"
PY="${PYTHON:-python3}"

fail=0
ok()  { printf '  ok    %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; fail=$((fail + 1)); }

# Abort rather than risk the real home.
if [ "${RIO_HOME:-}" = "${HOME}/.rio" ]; then
  echo "verify: refusing to run with RIO_HOME=$RIO_HOME (that is the real home)" >&2
  exit 2
fi

REAL_HOME="${HOME}/.rio"
REAL_RC="${HOME}/.bashrc"
REAL_RIO="${HOME}/.local/bin/rio"
before_home=""
before_rc=""
before_rio=""
[ -e "$REAL_HOME" ] && before_home="$(ls -la "$REAL_HOME" 2>/dev/null; stat -c '%Y %s %n' "$REAL_HOME" 2>/dev/null || true)"
[ -e "$REAL_RC" ] && before_rc="$(stat -c '%Y %s %n' "$REAL_RC" 2>/dev/null || true)"
[ -e "$REAL_RIO" ] && before_rio="$(stat -c '%Y %s %n' "$REAL_RIO" 2>/dev/null; sha256sum "$REAL_RIO" 2>/dev/null || true)"

TMP="$(mktemp -d /tmp/rio-cli-verify.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

TEST_HOME="$TMP/home"
PROJ="$TMP/project"
echo "verify: rio-cli v1  (tmp $TMP)"

# --- 1. syntax --------------------------------------------------------------
echo "-- syntax"
if sh -n "$ROOT/install.sh"; then ok "install.sh sh -n"; else bad "install.sh sh -n"; fi
if bash -n "$ROOT/bin/rioctl"; then ok "bin/rioctl bash -n"; else bad "bin/rioctl bash -n"; fi
if bash -n "$HERE/verify.sh"; then ok "verify.sh bash -n"; else bad "verify.sh bash -n"; fi
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -s sh "$ROOT/install.sh" && shellcheck -s bash "$ROOT/bin/rioctl" "$HERE/verify.sh"; then
    ok "shellcheck"
  else
    bad "shellcheck"
  fi
else
  ok "shellcheck not installed (skipped)"
fi

# --- 2. hygiene: no secret-shaped strings ----------------------------------
echo "-- hygiene"
secrets="$(
  grep -rInE 'BEGIN [A-Z ]*PRIVATE KEY|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}' \
    --include='*.md' --include='*.yaml' --include='*.yml' --include='*.sh' \
    "$HERE" "$ROOT/install.sh" "$ROOT/bin/rioctl" "$ROOT/skills/rioctl" 2>/dev/null || true
)"
if [ -z "$secrets" ]; then ok "no secret-shaped strings"; else bad "secret-shaped strings found:"; echo "$secrets" | sed 's/^/        /'; fi

# config.yaml template must mention that secrets are forbidden
if grep -q 'Never secrets' "$ROOT/install.sh" && grep -q 'never stored' "$ROOT/install.sh"; then
  ok "install.sh config template forbids secrets"
else
  # The write_config comment says "never stored" / "Do not put tokens"
  if grep -q 'Do not put tokens' "$ROOT/install.sh"; then
    ok "install.sh config template forbids secrets"
  else
    bad "install.sh config template missing a no-secrets warning"
  fi
fi

# --- 3. lock pins exist -----------------------------------------------------
echo "-- lock"
LOCK="$HERE/rio-cli-v1.lock.yaml"
if [ -f "$LOCK" ]; then ok "rio-cli-v1.lock.yaml present"; else bad "missing lock"; fi
for f in install.sh bin/rioctl skills/rioctl/SKILL.md stack/rio-cli/README.md stack/rio-cli/verify.sh; do
  if [ -f "$ROOT/$f" ]; then ok "pinned $f"; else bad "missing $f"; fi
done

# --- 4. install.sh --dry-run writes nothing --------------------------------
echo "-- install --dry-run"
mkdir -p "$TEST_HOME"
if RIO_HOME="$TEST_HOME" sh "$ROOT/install.sh" --dry-run --from "$ROOT" --worktree --ref HEAD >/dev/null; then
  # TEST_HOME may exist (we created it) but should have no stack checkout or config
  if [ -f "$TEST_HOME/config.yaml" ] || [ -e "$TEST_HOME/bin/rioctl" ] || [ -d "$TEST_HOME/stack/bin" ]; then
    bad "dry-run wrote files under $TEST_HOME"
    find "$TEST_HOME" -maxdepth 3 | sed 's/^/        /'
  else
    ok "dry-run wrote nothing inside RIO_HOME"
  fi
else
  bad "install.sh --dry-run exited non-zero"
fi

# --- 5. install.sh apply into the temp home --------------------------------
echo "-- install apply"
if RIO_HOME="$TEST_HOME" sh "$ROOT/install.sh" --from "$ROOT" --worktree --ref HEAD; then
  ok "install.sh apply exited 0"
else
  bad "install.sh apply failed"
fi

# Re-run is idempotent (and must not clobber config.yaml)
if [ -f "$TEST_HOME/config.yaml" ]; then
  echo "# user edit marker" >> "$TEST_HOME/config.yaml"
  if RIO_HOME="$TEST_HOME" sh "$ROOT/install.sh" --from "$ROOT" --worktree --ref HEAD >/dev/null; then
    if grep -q "user edit marker" "$TEST_HOME/config.yaml"; then
      ok "re-install keeps existing config.yaml"
    else
      bad "re-install overwrote config.yaml"
    fi
  else
    bad "idempotent re-install failed"
  fi
fi

check_home() {
  local p="$1" msg="$2"
  if [ -e "$p" ]; then ok "$msg"; else bad "missing $msg ($p)"; fi
}
check_home "$TEST_HOME/config.yaml" "config.yaml"
check_home "$TEST_HOME/bin/rioctl" "bin/rioctl"
check_home "$TEST_HOME/stack/bin/rioctl" "stack/bin/rioctl"
if [ -L "$TEST_HOME/bin/rioctl" ]; then
  tgt="$(readlink -f "$TEST_HOME/bin/rioctl")"
  exp="$(readlink -f "$TEST_HOME/stack/bin/rioctl")"
  if [ "$tgt" = "$exp" ]; then ok "bin/rioctl symlink target"; else bad "bin/rioctl points at $tgt (want $exp)"; fi
else
  bad "bin/rioctl is not a symlink"
fi
if [ -e "$TEST_HOME/bin/rio" ]; then
  bad "install created $TEST_HOME/bin/rio (rio is the Hermes wrapper, not this CLI)"
else
  ok "install did not create bin/rio"
fi
if grep -q "jadenblack" "$TEST_HOME/config.yaml" && grep -q "riolabs-ai" "$TEST_HOME/config.yaml"; then
  ok "config.yaml has both identities"
else
  bad "config.yaml missing identities"
fi
if grep -qiE 'token:|password:|gh[pousr]_|BEGIN ' "$TEST_HOME/config.yaml"; then
  bad "config.yaml looks like it contains a secret"
else
  ok "config.yaml has no secret-shaped values"
fi

# --- 6. rioctl version / help / doctor against the installed CLI --------------
echo "-- cli"
RIO="$TEST_HOME/bin/rioctl"
export RIO_HOME="$TEST_HOME"
if out="$("$RIO" version 2>&1)" && printf '%s\n' "$out" | grep -q '^rioctl 1\.0\.0'; then
  ok "rioctl version: $(printf '%s' "$out" | tr '\n' ' ')"
else
  bad "rioctl version failed: $out"
fi
if "$RIO" help >/dev/null; then ok "rioctl help"; else bad "rioctl help"; fi
if "$RIO" doctor; then ok "rioctl doctor"; else bad "rioctl doctor"; fi

# --- 7. init in a temp git repo --------------------------------------------
echo "-- init preview / write"
mkdir -p "$PROJ"
git -C "$PROJ" init -q
git -C "$PROJ" config user.name "rio-cli-verify"
git -C "$PROJ" config user.email "verify@rio.invalid"
git -C "$PROJ" checkout -q -b main
git -C "$PROJ" remote add origin https://github.com/riolabs-ai/rio.stack.git
printf 'seed\n' > "$PROJ/README.md"
git -C "$PROJ" add README.md
git -C "$PROJ" commit -q -m "seed"

# preview must write nothing
if (CDPATH= cd -- "$PROJ" && "$RIO" init >/dev/null); then
  if [ -e "$PROJ/rio.project.yaml" ] || [ -e "$PROJ/.rio" ]; then
    bad "init preview wrote files"
  else
    ok "init preview wrote nothing"
  fi
else
  bad "init preview exited non-zero"
fi

# --write applies, and should pick up the rio-stack registry entry
if (CDPATH= cd -- "$PROJ" && "$RIO" init --write); then
  ok "init --write exited 0"
else
  bad "init --write failed"
fi

for p in rio.project.yaml .rio/rio.project.yaml .rio/stack.lock .rio/overrides/README.md .rio/overrides/.gitignore; do
  if [ -f "$PROJ/$p" ]; then ok "wrote $p"; else bad "missing $p"; fi
done

if [ -f "$PROJ/rio.project.yaml" ]; then
  if grep -q 'schema: rio.project/v1' "$PROJ/rio.project.yaml" \
    && grep -q 'id: rio-stack' "$PROJ/rio.project.yaml" \
    && grep -q 'owner: riolabs-ai' "$PROJ/rio.project.yaml" \
    && grep -q 'repo: riolabs-ai/rio.stack' "$PROJ/rio.project.yaml" \
    && grep -q 'domain: rio' "$PROJ/rio.project.yaml"; then
    ok "manifest matches registry entry rio-stack"
  else
    bad "manifest fields do not match the rio-stack registry entry"
    sed 's/^/        /' "$PROJ/rio.project.yaml"
  fi
  if "$PY" -c 'import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); assert d["schema"]=="rio.project/v1"' \
      "$PROJ/rio.project.yaml" 2>/dev/null; then
    ok "rio.project.yaml parses"
  else
    bad "rio.project.yaml does not parse"
  fi
  if cmp -s "$PROJ/rio.project.yaml" "$PROJ/.rio/rio.project.yaml"; then
    ok "root manifest matches .rio/rio.project.yaml"
  else
    bad "root and .rio manifests differ"
  fi
fi

if [ -f "$PROJ/.rio/stack.lock" ]; then
  if "$PY" -c 'import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); assert d["schema"]=="rio.stack.lock/v1"; assert "rio-cli" in (d.get("layers") or {})' \
      "$PROJ/.rio/stack.lock" 2>/dev/null; then
    ok "stack.lock parses and lists rio-cli"
  else
    bad "stack.lock missing or does not list rio-cli"
    sed 's/^/        /' "$PROJ/.rio/stack.lock"
  fi
fi

# second --write without --force is idempotent (unchanged files are kept)
if (CDPATH= cd -- "$PROJ" && "$RIO" init --write >/dev/null); then
  ok "second init --write is idempotent"
else
  bad "second init --write failed (should keep identical files)"
fi

# sync / promote are stubs and must not write
before="$(find "$PROJ" -type f -printf '%p %s\n' | sort)"
if (CDPATH= cd -- "$PROJ" && "$RIO" sync >/dev/null && "$RIO" promote >/dev/null); then
  after="$(find "$PROJ" -type f -printf '%p %s\n' | sort)"
  if [ "$before" = "$after" ]; then ok "sync and promote wrote nothing"; else bad "sync/promote mutated the project"; fi
else
  bad "sync or promote exited non-zero"
fi

# status --offline should run (uses mission-control from the cached stack)
if (CDPATH= cd -- "$PROJ" && "$RIO" status --offline >/dev/null); then
  ok "rioctl status --offline"
else
  bad "rioctl status --offline failed"
fi

# --- 8. the real ~/.rio and ~/.bashrc were not touched ---------------------
echo "-- isolation"
after_home=""
after_rc=""
after_rio=""
[ -e "$REAL_HOME" ] && after_home="$(ls -la "$REAL_HOME" 2>/dev/null; stat -c '%Y %s %n' "$REAL_HOME" 2>/dev/null || true)"
[ -e "$REAL_RC" ] && after_rc="$(stat -c '%Y %s %n' "$REAL_RC" 2>/dev/null || true)"
[ -e "$REAL_RIO" ] && after_rio="$(stat -c '%Y %s %n' "$REAL_RIO" 2>/dev/null; sha256sum "$REAL_RIO" 2>/dev/null || true)"
if [ "$before_home" = "$after_home" ]; then ok "real ~/.rio untouched"; else bad "real ~/.rio changed"; fi
if [ "$before_rc" = "$after_rc" ]; then ok "real ~/.bashrc untouched"; else bad "real ~/.bashrc changed"; fi
if [ "$before_rio" = "$after_rio" ]; then ok "Hermes rio wrapper (~/.local/bin/rio) untouched"; else bad "Hermes rio wrapper changed"; fi

echo
if [ "$fail" -eq 0 ]; then
  echo "verify: PASS"
  exit 0
fi
echo "verify: FAIL ($fail check(s))"
exit 1
