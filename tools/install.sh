#!/bin/sh
# usage: tools/install.sh [prefix]   (default ~/.local; builds a release binary first)
set -e
cd "$(dirname "$0")/.."
prefix=${1:-$HOME/.local}
./build.sh release
install -Dm755 build/rhun "$prefix/bin/rhun"
install -Dm644 assets/rhun.desktop "$prefix/share/applications/rhun.desktop"
install -Dm644 assets/icons/rhun.svg "$prefix/share/icons/hicolor/scalable/apps/rhun.svg"
command -v update-desktop-database >/dev/null && update-desktop-database -q "$prefix/share/applications" || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -qtf "$prefix/share/icons/hicolor" 2>/dev/null || true
echo "installed to $prefix"
