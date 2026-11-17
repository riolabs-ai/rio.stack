#!/usr/bin/env bash
# deps/obsidian.sh — install | verify | migrate the Obsidian dependency for the rio Hermes stack.
#
#   ./deps/obsidian.sh verify          # what is installed now, and is it the pinned version
#   ./deps/obsidian.sh install         # install the pinned .deb (needs sudo), link the CLI
#   ./deps/obsidian.sh migrate         # install, repoint the CLI, then remove the Flatpak
#
# Safe by default: `migrate` removes the Flatpak only when the .deb is installed AND its binary runs.
set -uo pipefail

PIN="1.15.1"
VER="1.15.1"
DEB="obsidian_${VER}_amd64.deb"
URL="https://github.com/obsidianmd/obsidian-releases/releases/download/v${PIN}/${DEB}"
SHA="f77b6dfc8c040214f2febad2b1b9b051b6a838a47b0f4fb90a31cfcb79b8fcec"
CACHE="$HOME/.hermes/cache/scratch"
APPDIR="/opt/Obsidian"

ok()   { printf '  OK    %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; }
note() { printf '  ..    %s\n' "$*"; }

have_deb()  { dpkg-query -W -f='${Status}' obsidian 2>/dev/null | grep -q "ok installed"; }   # a held package reports "hold ok installed", not "install ok installed"
deb_ver()   { dpkg-query -W -f='${Version}' obsidian 2>/dev/null; }
have_flat() { flatpak list --app 2>/dev/null | grep -q md.obsidian.Obsidian; }

verify() {
  local rc=0
  echo "Obsidian dependency — pin $PIN"
  if have_deb; then
    [ "$(deb_ver)" = "$PIN" ] && ok "dpkg: obsidian $(deb_ver)" || { bad "dpkg: $(deb_ver) (pin $PIN)"; rc=1; }
  else
    bad "dpkg: obsidian not installed"
    rc=1
  fi
  [ -x "$APPDIR/obsidian" ]     && ok "binary $APPDIR/obsidian"     || { bad "binary missing"; rc=1; }
  [ -x "$APPDIR/obsidian-cli" ] && ok "cli $APPDIR/obsidian-cli"   || { bad "cli missing"; rc=1; }
  for l in "$HOME/.local/bin/obsidian-cli" "$HOME/.local/bin/obsidian"; do
    if [ -L "$l" ]; then
      t=$(readlink -f "$l")
      case "$t" in
        "$APPDIR"/*) ok "$l -> $t" ;;
        *flatpak*)   { bad "$l still points into the Flatpak: $t"; rc=1; } ;;
        *)           { note "$l -> $t"; } ;;
      esac
    else
      bad "$l missing"
      rc=1
    fi
  done
  want=$(dpkg-deb -f "$CACHE/$DEB" Version 2>/dev/null)
  [ "$want" = "$PIN" ] && ok "cached package matches pin" || note "no cached package (install will download)"
  if have_flat; then
    note "Flatpak still installed — two installs, two config dirs, ambiguous CLI symlink"
  else
    ok "no Flatpak copy"
  fi
  # app-dependent surfaces
  if pgrep -f "obsidian" >/dev/null 2>&1; then
    if curl -sk -m 5 -o /dev/null -w '%{http_code}' https://127.0.0.1:27124/ 2>/dev/null | grep -q 200; then
      ok "Local REST API answering on 27124"
    else
      bad "app running but REST API not answering (plugin disabled?)"
      rc=1
    fi
  else
    note "app not running — CLI and REST API are in-process and will not answer"
  fi
  return $rc
}

fetch_deb() {
  mkdir -p "$CACHE"
  if [ -f "$CACHE/$DEB" ] && [ "$(sha256sum "$CACHE/$DEB" | cut -d' ' -f1)" = "$SHA" ]; then
    ok "package already cached and hash-verified"
    return 0
  fi
  note "downloading $DEB"
  curl -fsSL -o "$CACHE/$DEB" "$URL" || { bad "download failed"; return 1; }
  got=$(sha256sum "$CACHE/$DEB" | cut -d' ' -f1)
  [ "$got" = "$SHA" ] && ok "sha256 verified" || { bad "sha256 mismatch: $got"; rm -f "$CACHE/$DEB"; return 1; }
}

install_deb() {
  fetch_deb || return 1
  note "installing (sudo) — pulls libgtk-3-0, libnss3, libsecret-1-0, libatspi2.0-0, …"
  sudo apt-get install -y "$CACHE/$DEB" || { bad "apt install failed"; return 1; }
  sudo apt-mark hold obsidian >/dev/null 2>&1 && ok "version pinned (apt-mark hold obsidian)"
  link_cli
}

link_cli() {
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$APPDIR/obsidian-cli" "$HOME/.local/bin/obsidian-cli"
  ln -sfn "$APPDIR/obsidian-cli" "$HOME/.local/bin/obsidian"
  ok "~/.local/bin/obsidian{,-cli} -> $APPDIR/obsidian-cli"
}

drop_flatpak() {
  have_deb && [ -x "$APPDIR/obsidian" ] || { bad "refusing to remove the Flatpak: pinned .deb is not installed"; return 1; }
  note "removing the Flatpak copy"
  flatpak uninstall -y md.obsidian.Obsidian || { bad "flatpak uninstall failed"; return 1; }
  ok "Flatpak removed (its old profile stays at ~/.var/app/md.obsidian.Obsidian — 89 MB, delete after a day of use)"
}

case "${1:-verify}" in
  verify)  verify ;;
  install) install_deb && echo && verify ;;
  migrate) install_deb && drop_flatpak && echo && verify ;;
  *) echo "usage: $0 {verify|install|migrate}"; exit 2 ;;
esac
