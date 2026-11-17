#!/bin/sh
# install.sh — user-level rioctl bootstrap. Idempotent.
#
#   curl -fsSL https://raw.githubusercontent.com/riolabs-ai/rio.stack/main/install.sh | sh
#   sh install.sh --dry-run
#   sh install.sh --ref main --from /path/or/url
#   sh install.sh --write          # also append a PATH line to ~/.bashrc if missing
#
# Creates $RIO_HOME (default ~/.rio):
#   stack/        pinned rio.stack checkout (default pin: main)
#   config.yaml   identities + provider auth references — NEVER secrets
#   bin/rioctl    symlink to stack/bin/rioctl
#
# This script WRITES the home by default (that's the curl|sh contract).
# --dry-run prints the plan and writes nothing.
# Shell rc is never edited unless --write is passed.
#
# Env: RIO_HOME, RIO_STACK_URL, RIO_STACK_REF
# Exit: 0 ok, 2 usage, 1 failure.

set -eu
if (set -o pipefail) >/dev/null 2>&1; then
  set -o pipefail
fi

DEFAULT_SOURCE="https://github.com/riolabs-ai/rio.stack.git"
DEFAULT_REF="main"
DEFAULT_HOME="${HOME}/.rio"

DRY_RUN=0
WRITE_RC=0
WORKTREE=0
FROM="${RIO_STACK_URL:-}"
REF="${RIO_STACK_REF:-$DEFAULT_REF}"
RIO_HOME="${RIO_HOME:-$DEFAULT_HOME}"

usage() {
  sed -n '2,22p' "$0" 2>/dev/null || cat <<'H'
usage: install.sh [--dry-run] [--write] [--ref REF] [--from URL_OR_PATH] [--home DIR] [--worktree]
H
  exit 0
}

die() { printf 'install: %s\n' "$*" >&2; exit 1; }
note() { printf 'install: %s\n' "$*"; }
step() { printf '  %-8s %s\n' "$1" "$2"; }

# $0 is "sh" / "bash" / "-" when the script is piped (curl | sh).
self=$0
case $self in
  -|sh|bash|dash|"-sh"|"-bash"|"-dash") self="" ;;
esac
case $self in
  */sh|*/bash|*/dash) self="" ;;
esac
HERE=""
if [ -n "$self" ] && [ -f "$self" ]; then
  HERE=$(CDPATH= cd -- "$(dirname -- "$self")" && pwd)
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run|-n) DRY_RUN=1; shift ;;
    --write)      WRITE_RC=1; shift ;;
    --worktree)   WORKTREE=1; shift ;;
    --ref)        REF="${2:?--ref needs a value}"; shift 2 ;;
    --from)       FROM="${2:?--from needs a value}"; shift 2 ;;
    --home)       RIO_HOME="${2:?--home needs a value}"; shift 2 ;;
    -h|--help)    usage ;;
    *)            printf 'install: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

# Prefer a local checkout when the script lives in one and --from was not given.
if [ -z "$FROM" ] && [ -n "$HERE" ] && [ -d "$HERE/stack" ] && [ -f "$HERE/bin/rioctl" ] || [ -f "$HERE/install.sh" ]; then
  FROM="$HERE"
fi
[ -n "$FROM" ] || FROM="$DEFAULT_SOURCE"

is_local=0
case "$FROM" in
  *://*|git@*) is_local=0 ;;
  *)
    if [ -d "$FROM" ]; then
      is_local=1
      FROM=$(CDPATH= cd -- "$FROM" && pwd)
    fi
    ;;
esac

if [ "$WORKTREE" -eq 1 ] && [ "$is_local" -eq 0 ]; then
  die "--worktree requires --from to be a local checkout"
fi

STACK="$RIO_HOME/stack"
BIN="$RIO_HOME/bin"
CONF="$RIO_HOME/config.yaml"
RIO_BIN="$BIN/rioctl"
SHELL_RC="${HOME}/.bashrc"
PATH_LINE="export PATH=\"${RIO_HOME}/bin:\$PATH\""

MODE="apply"
[ "$DRY_RUN" -eq 1 ] && MODE="dry-run"

note "rio home $RIO_HOME  [$MODE]"
note "source   $FROM"
note "pin      $REF"
[ "$WORKTREE" -eq 1 ] && note "worktree overlay on (uncommitted files included)"

# --- helpers ---------------------------------------------------------------
would() { [ "$DRY_RUN" -eq 1 ]; }

write_config() {
  # Identities are the two GitHub accounts this stack is for. Provider auth
  # is a reference to a secret store — never a token, key, or password.
  cat <<'EOF'
# ~/.rio/config.yaml — user-level rio config.
# Provider auth is referenced, never stored. Do not put tokens, keys, or
# passwords in this file. Credentials live in bws (Bitwarden Secrets) or
# the tool's own store (gh, Hermes profile).
schema: rio.config/v1
identities:
  - id: jadenblack
    github: jadenblack
    kind: user
  - id: riolabs-ai
    github: riolabs-ai
    kind: user
    notes: Personal account today. Org conversion is jadenblack/ops#13; transfer the rio-mission-control GitHub App after that.
stack:
  repo: riolabs-ai/rio.stack
  pin: PIN_PLACEHOLDER
  ref: REF_PLACEHOLDER
providers:
  github:
    store: bws
    ref: rio-mission-control    # GitHub App; short-lived installation tokens (rio.stack#39)
  hermes:
    store: hermes-profile
    ref: rio                    # HPS lives on the rio profile
  vercel:
    store: bws
    ref: vercel
  porkbun:
    store: bws
    ref: porkbun
  neon:
    store: bws
    ref: neon
  resend:
    store: bws
    ref: resend
  obsidian:
    store: vault
    ref: riolabs-ai/rio.vault   # Local REST API key stays in the vault plugin data
  bitwarden-secrets:
    store: bws
    ref: cli
EOF
}

resolve_ref() {
  if [ -d "$STACK/.git" ]; then
    git -C "$STACK" rev-parse --short HEAD 2>/dev/null || printf '%s\n' "$REF"
  else
    printf '%s\n' "$REF"
  fi
}

# --- plan / apply ----------------------------------------------------------
if would; then
  if [ ! -e "$RIO_HOME" ]; then
    step would "mkdir $RIO_HOME/{bin,stack}"
  else
    step keep "$RIO_HOME (exists)"
  fi
else
  mkdir -p "$BIN" "$STACK"
  step write "$RIO_HOME/{bin,stack}"
fi

# Stack checkout
if would; then
  if [ -d "$STACK/.git" ]; then
    step would "git fetch + checkout $REF in $STACK"
  elif [ "$WORKTREE" -eq 1 ]; then
    step would "clone $FROM → $STACK, overlay worktree, checkout $REF"
  else
    step would "git clone $FROM → $STACK && checkout $REF"
  fi
else
  if [ "$is_local" -eq 1 ]; then
    if [ -d "$STACK/.git" ]; then
      # Already a cache. Update from the local source when it is a git repo.
      if [ -d "$FROM/.git" ]; then
        git -C "$STACK" fetch --quiet "$FROM" "$REF" 2>/dev/null \
          || git -C "$STACK" fetch --quiet "$FROM" || true
        if git -C "$STACK" checkout --quiet "$REF" 2>/dev/null; then
          step update "$STACK @ $REF"
        else
          # fetch may have stored it as FETCH_HEAD
          if git -C "$FROM" rev-parse --verify --quiet "$REF^{commit}" >/dev/null; then
            sha=$(git -C "$FROM" rev-parse "$REF")
            git -C "$STACK" fetch --quiet "$FROM" "$sha"
            git -C "$STACK" checkout --quiet "$sha"
            step update "$STACK @ $sha"
          else
            die "cannot checkout $REF in $STACK"
          fi
        fi
      else
        step keep "$STACK (no .git in source to fetch)"
      fi
    else
      # Fresh clone from a local path. Unborn / empty sources fall back to a copy.
      if [ -d "$FROM/.git" ] && git -C "$FROM" rev-parse --verify --quiet HEAD >/dev/null; then
        git clone --quiet "$FROM" "$STACK" || die "git clone failed: $FROM"
        if ! git -C "$STACK" checkout --quiet "$REF" 2>/dev/null; then
          # Local uncommitted-only branch names may not exist; stay on clone default.
          step note "$STACK cloned; $REF not on the source, left at $(git -C "$STACK" rev-parse --abbrev-ref HEAD)"
        else
          step write "$STACK (cloned $FROM @ $REF)"
        fi
      else
        mkdir -p "$STACK"
        step write "$STACK (source has no usable git history; copying)"
        WORKTREE=1
      fi
    fi
    if [ "$WORKTREE" -eq 1 ]; then
      if command -v rsync >/dev/null 2>&1; then
        rsync -a --exclude .git --exclude '*.pyc' --exclude '__pycache__' "$FROM"/ "$STACK"/
      else
        # Portable overlay: copy files, do not touch $STACK/.git
        (CDPATH= cd -- "$FROM" && find . -name .git -prune -o -name __pycache__ -prune -o -name '*.pyc' -prune -o -print) \
          | while IFS= read -r p; do
              [ "$p" = "." ] && continue
              src="$FROM/${p#./}"
              dst="$STACK/${p#./}"
              if [ -d "$src" ] && [ ! -L "$src" ]; then
                mkdir -p "$dst"
              else
                mkdir -p "$(dirname -- "$dst")"
                cp -a "$src" "$dst"
              fi
            done
      fi
      step write "$STACK (worktree overlay from $FROM)"
    fi
  else
    if [ -d "$STACK/.git" ]; then
      git -C "$STACK" fetch --quiet origin || die "git fetch failed in $STACK"
      git -C "$STACK" checkout --quiet "$REF" || die "git checkout $REF failed in $STACK"
      # Fast-forward a branch when origin has it.
      if git -C "$STACK" show-ref --verify --quiet "refs/remotes/origin/$REF"; then
        git -C "$STACK" merge --ff-only --quiet "origin/$REF" || die "ff-only update of $REF failed"
      fi
      step update "$STACK @ $REF"
    else
      # Empty dir from mkdir -p: clone into a temp name, then move.
      tmp="${STACK}.clone.$$"
      rm -rf "$tmp"
      if git clone --quiet --branch "$REF" --single-branch "$FROM" "$tmp" 2>/dev/null; then
        :
      else
        git clone --quiet "$FROM" "$tmp" || die "git clone failed: $FROM"
        git -C "$tmp" checkout --quiet "$REF" || die "git checkout $REF failed after clone"
      fi
      # Replace the empty stack/ placeholder.
      rmdir "$STACK" 2>/dev/null || rm -rf "$STACK"
      mv "$tmp" "$STACK"
      step write "$STACK (cloned $FROM @ $REF)"
    fi
  fi
fi

RESOLVED="(dry-run)"
if ! would; then
  RESOLVED=$(resolve_ref)
  note "resolved $RESOLVED"
fi

# config.yaml — write only when missing (never clobber user edits, never secrets)
if [ -f "$CONF" ]; then
  step keep "$CONF (exists, not overwritten)"
elif would; then
  step would "write $CONF (identities + provider refs, no secrets)"
else
  write_config | sed "s/PIN_PLACEHOLDER/$REF/; s/REF_PLACEHOLDER/$RESOLVED/" > "$CONF"
  step write "$CONF"
fi

# bin/rioctl symlink
TARGET="$STACK/bin/rioctl"
if would; then
  step would "symlink $RIO_BIN -> $TARGET"
else
  if [ ! -f "$TARGET" ]; then
    die "expected CLI at $TARGET (is this a rio.stack checkout?)"
  fi
  chmod +x "$TARGET" 2>/dev/null || true
  ln -sfn "$TARGET" "$RIO_BIN"
  step write "$RIO_BIN -> $TARGET"
fi

# PATH hint — printed always; shell rc only with --write and not --dry-run
note "add this to your PATH (this script will not edit shell rc unless you pass --write):"
printf '  %s\n' "$PATH_LINE"

if [ "$WRITE_RC" -eq 1 ]; then
  if would; then
    step would "append PATH line to $SHELL_RC (if missing)"
  else
    if [ -f "$SHELL_RC" ] && grep -F -q "$RIO_HOME/bin" "$SHELL_RC"; then
      step keep "$SHELL_RC already mentions $RIO_HOME/bin"
    else
      printf '\n# rioctl (install.sh)\n%s\n' "$PATH_LINE" >> "$SHELL_RC"
      step write "appended PATH to $SHELL_RC"
    fi
  fi
fi

if would; then
  note "dry run — nothing written. Re-run without --dry-run to apply."
else
  note "done. Try: $RIO_BIN doctor"
fi
