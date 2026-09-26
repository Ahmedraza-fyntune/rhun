#!/bin/sh
# usage: tools/install.sh [prefix]   (default ~/.local; builds a release binary first)
set -e
cd "$(dirname "$0")/.."
prefix=${1:-$HOME/.local}
if [ "$(uname -s)" = Darwin ]; then
    # rhun.app into /Applications (~/Applications when that is not writable), rhun into prefix/bin
    ./build.sh release
    apps=/Applications
    [ -w "$apps" ] || apps=$HOME/Applications
    mkdir -p "$apps" "$prefix/bin"
    rm -rf "$apps/rhun.app"
    cp -R build/rhun.app "$apps/"
    printf '#!/bin/sh\nexec "%s/rhun.app/Contents/MacOS/rhun" "$@"\n' "$apps" > "$prefix/bin/rhun"
    chmod 755 "$prefix/bin/rhun"
    echo "installed $apps/rhun.app and $prefix/bin/rhun"
    exit 0
fi
./build.sh release
install -Dm755 build/rhun "$prefix/bin/rhun"
install -Dm644 assets/rhun.desktop "$prefix/share/applications/rhun.desktop"
install -Dm644 assets/icons/rhun.svg "$prefix/share/icons/hicolor/scalable/apps/rhun.svg"
command -v update-desktop-database >/dev/null && update-desktop-database -q "$prefix/share/applications" || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -qtf "$prefix/share/icons/hicolor" 2>/dev/null || true
echo "installed to $prefix"
