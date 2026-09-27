#!/bin/sh
# Installs rhun from its GitHub releases, updates it and removes it; no root needed.
#   curl -fsSL https://github.com/vshvedov/rhun/releases/latest/download/install.sh | sh
#   wget -qO- https://github.com/vshvedov/rhun/releases/latest/download/install.sh | sh
#   ... | sh -s -- [options]
#
#   --version X             install X instead of the latest release
#   --prefix DIR            Linux: install under DIR (default ~/.local)
#   --app-dir DIR           macOS: where rhun.app goes (default /Applications, or ~/Applications
#                           when that is not writable)
#   --no-modify-path        leave shell startup files alone
#   --uninstall             remove what the installer put in place (settings stay)
#   --update --target PATH  what rhun runs to update itself: replace the installation at PATH (the
#                           binary, or on macOS the .app) with --version
#
# RHUN_RELEASES_URL and RHUN_TEAM_ID are for tests: another place for the releases, and the team
# the macOS app must be signed by.
#
# Everything is in functions called from the last line, so a download cut short runs nothing.

set -eu

RELEASES=https://github.com/vshvedov/rhun/releases
TEAM_ID=G29V3JRMJJ
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

say() {
    if [ -z "$quiet" ]; then printf '%s\n' "$*"; fi
}

fail() {
    printf 'rhun install: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
usage: install.sh [options]   (curl -fsSL .../install.sh | sh -s -- [options])
  --version X             install X instead of the latest release
  --prefix DIR            Linux: install under DIR (default ~/.local)
  --app-dir DIR           macOS: where rhun.app goes (default /Applications)
  --no-modify-path        leave shell startup files alone
  --uninstall             remove what the installer put in place (settings stay)
EOF
}

have() {
    command -v "$1" >/dev/null 2>&1
}

# platform: sets os (linux, mac) and the archive's name ending
platform() {
    msg="rhun runs on Linux x86-64 and macOS on Apple silicon"
    case "$(uname -s)" in
    Linux)
        case "$(uname -m)" in
        x86_64 | amd64) os=linux; ending=linux-x86_64.tar.gz ;;
        *) fail "$msg; this is Linux on $(uname -m)" ;;
        esac
        ;;
    Darwin)
        # a shell under Rosetta says x86_64: ask the hardware
        if [ "$(uname -m)" = arm64 ] || [ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" = 1 ]; then
            os=mac; ending=macos-arm64.zip
        else
            fail "$msg; this Mac has an Intel processor"
        fi
        ;;
    *) fail "$msg; this is $(uname -s)" ;;
    esac
}

# downloader: curl, else wget
downloader() {
    if have curl; then
        dl=curl
    elif have wget; then
        dl=wget
    else
        fail "needs curl or wget to download rhun"
    fi
}

# fetch URL FILE
fetch() {
    if [ "$dl" = curl ]; then
        if [ -n "${RHUN_RELEASES_URL:-}" ]; then
            curl -fsSL -o "$2" "$1"
        else
            curl -fsSL --proto =https --proto-redir =https -o "$2" "$1"
        fi
    else
        wget -q -O "$2" "$1"
    fi
}

valid_version() {
    [ ${#1} -le 31 ] && printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'
}

latest_version() {
    fetch "$base/latest/download/VERSION" "$tmp/VERSION" || fail "could not find the latest release at $base"
    tr -d ' \r\n' < "$tmp/VERSION"
}

# download: the archive of $version into $tmp, checked against the release's SHA256SUMS
download() {
    name=rhun-$version-$ending
    fetch "$base/download/v$version/$name" "$tmp/$name" || fail "could not download $name; is $version a release?"
    fetch "$base/download/v$version/SHA256SUMS" "$tmp/SHA256SUMS" || fail "could not download the checksums of $version"
    want=$(awk -v f="$name" '$2 == f || $2 == "*" f { print $1 }' "$tmp/SHA256SUMS")
    [ -n "$want" ] || fail "$name is not in the checksums of $version"
    if have sha256sum; then
        got=$(sha256sum "$tmp/$name" | awk '{ print $1 }')
    elif have shasum; then
        got=$(shasum -a 256 "$tmp/$name" | awk '{ print $1 }')
    else
        fail "needs sha256sum or shasum to check the download"
    fi
    [ "$got" = "$want" ] || fail "$name does not match its checksum; nothing was installed"
}

# installed_version TARGET: the version the installation reports, or nothing
installed_version() {
    exe=$1
    if [ "$os" = mac ]; then exe=$1/Contents/MacOS/rhun; fi
    if [ -x "$exe" ]; then
        "$exe" --version 2>/dev/null | sed -n 's/^rhun //p' || true
    fi
}

# ---------------- Linux ----------------

unpack_linux() {
    mkdir "$tmp/x"
    tar -xzf "$tmp/$name" -C "$tmp/x" || fail "could not unpack $name"
    src=$tmp/x/rhun-$version
    [ -f "$src/bin/rhun" ] || fail "$name has no bin/rhun"
}

# place_binary DEST: a new file renamed over the old one, so a running rhun keeps its copy
place_binary() {
    dir=$(dirname "$1")
    mkdir -p "$dir"
    cp "$src/bin/rhun" "$dir/.rhun.new"
    chmod 755 "$dir/.rhun.new"
    mv -f "$dir/.rhun.new" "$1"
}

# place_desktop PREFIX EXE: the desktop entry, which starts EXE by its path (graphical sessions often
# lack ~/.local/bin in PATH), and the icons
place_desktop() {
    apps=$1/share/applications
    mkdir -p "$apps"
    exe=$2
    case "$exe" in *" "*) exe="\"$exe\"" ;; esac
    exe=$(printf '%s' "$exe" | sed 's/[&|\\]/\\&/g')
    sed "s|^Exec=rhun |Exec=$exe |" "$src/share/applications/rhun.desktop" > "$apps/.rhun.desktop.new"
    mv -f "$apps/.rhun.desktop.new" "$apps/rhun.desktop"
    for d in scalable 256x256 512x512; do
        for f in "$src/share/icons/hicolor/$d/apps"/rhun.*; do
            if [ -f "$f" ]; then
                mkdir -p "$1/share/icons/hicolor/$d/apps"
                cp "$f" "$1/share/icons/hicolor/$d/apps/"
            fi
        done
    done
    refresh_desktop "$1"
}

# refresh_desktop PREFIX: menus and icon caches of whatever desktop there is
refresh_desktop() {
    if have update-desktop-database; then update-desktop-database -q "$1/share/applications" 2>/dev/null || true; fi
    if have gtk-update-icon-cache; then gtk-update-icon-cache -qtf "$1/share/icons/hicolor" 2>/dev/null || true; fi
    if have xdg-desktop-menu; then xdg-desktop-menu forceupdate 2>/dev/null || true; fi
    case "${XDG_CURRENT_DESKTOP:-}" in
    *KDE*)
        if have kbuildsycoca6; then
            kbuildsycoca6 >/dev/null 2>&1 || true
        elif have kbuildsycoca5; then
            kbuildsycoca5 >/dev/null 2>&1 || true
        fi
        ;;
    esac
}

# ---------------- macOS ----------------

unpack_mac() {
    mkdir "$tmp/x"
    ditto -x -k "$tmp/$name" "$tmp/x" || fail "could not unpack $name"
    src=$tmp/x/rhun.app
    [ -d "$src" ] || fail "$name has no rhun.app"
    codesign --verify --strict --deep "$src" 2>/dev/null || fail "the signature of rhun.app is not valid; nothing was installed"
    team=$(codesign -dv "$src" 2>&1 | sed -n 's/^TeamIdentifier=//p')
    [ "$team" = "${RHUN_TEAM_ID:-$TEAM_ID}" ] || fail "rhun.app is not signed by rhun's developer ($team); nothing was installed"
}

# place_app DEST: the bundle unpacked beside DEST and swapped in by renames, so a running rhun keeps
# its code
place_app() {
    dir=$(dirname "$1")
    mkdir -p "$dir"
    rm -rf "$dir/.rhun.app.new" "$dir/.rhun.app.old"
    ditto "$src" "$dir/.rhun.app.new"
    if [ -e "$1" ]; then mv "$1" "$dir/.rhun.app.old"; fi
    mv "$dir/.rhun.app.new" "$1"
    rm -rf "$dir/.rhun.app.old"
    if [ -x "$LSREGISTER" ]; then "$LSREGISTER" -f "$1" >/dev/null 2>&1 || true; fi
}

# place_wrapper APP: ~/.local/bin/rhun starts the app's binary from a terminal
place_wrapper() {
    mkdir -p "$HOME/.local/bin"
    printf '#!/bin/sh\nexec "%s/Contents/MacOS/rhun" "$@"\n' "$1" > "$HOME/.local/bin/.rhun.new"
    chmod 755 "$HOME/.local/bin/.rhun.new"
    mv -f "$HOME/.local/bin/.rhun.new" "$HOME/.local/bin/rhun"
}

default_app_dir() {
    if [ -w /Applications ]; then echo /Applications; else echo "$HOME/Applications"; fi
}

# ---------------- PATH ----------------

# add_path BIN: BIN into PATH in the shell's startup file, between "# rhun" and "# rhun end"
add_path() {
    case ":$PATH:" in *":$1:"*) return 0 ;; esac
    hint="add $1 to PATH to start rhun from a terminal"
    if [ -z "$modify_path" ]; then
        say "$hint"
        return 0
    fi
    case "$(basename "${SHELL:-sh}")" in
    zsh) add_path_to "$HOME/.zshrc" "$1" ;;
    bash)
        add_path_to "$HOME/.bashrc" "$1"
        if [ "$os" = mac ]; then add_path_to "$HOME/.bash_profile" "$1"; fi
        ;;
    fish)
        f=$HOME/.config/fish/conf.d/rhun.fish
        mkdir -p "$(dirname "$f")"
        printf '# rhun\nfish_add_path "%s"\n# rhun end\n' "$1" > "$f"
        say "added $1 to PATH in $f; open a new terminal to use it"
        ;;
    *) say "$hint" ;;
    esac
}

add_path_to() { # FILE BIN
    if [ -f "$1" ] && grep -q '^# rhun$' "$1"; then return 0; fi
    # shellcheck disable=SC2016 # $PATH is for the shell that reads the file
    printf '\n# rhun\nexport PATH="%s:$PATH"\n# rhun end\n' "$2" >> "$1"
    say "added $2 to PATH in $1; open a new terminal to use it"
}

# remove_path_from FILE: the lines add_path wrote
remove_path_from() {
    if [ -f "$1" ] && grep -q '^# rhun$' "$1"; then
        awk '/^# rhun$/ { skip = 1; next } /^# rhun end$/ { skip = 0; next } !skip' "$1" > "$tmp/rc"
        cat "$tmp/rc" > "$1"
    fi
}

# ---------------- what the options ask ----------------

install_fresh() {
    download
    if [ "$os" = linux ]; then
        prefix=${prefix:-$HOME/.local}
        unpack_linux
        place_binary "$prefix/bin/rhun"
        place_desktop "$prefix" "$prefix/bin/rhun"
        add_path "$prefix/bin"
        say "rhun $version is installed in $prefix"
        say "start it from your applications, or run: rhun [folder]"
    else
        appdir=${appdir:-$(default_app_dir)}
        unpack_mac
        place_app "$appdir/rhun.app"
        place_wrapper "$appdir/rhun.app"
        add_path "$HOME/.local/bin"
        say "rhun $version is installed in $appdir"
        say "start it from Launchpad or Spotlight, or run: rhun [folder]"
    fi
}

update() {
    [ -n "$target" ] || fail "--update needs --target"
    if [ "$(installed_version "$target")" = "$version" ]; then return 0; fi
    dir=$(dirname "$target")
    if [ "$os" = mac ]; then
        case "$target" in *.app) ;; *) fail "$target is not an app" ;; esac
    fi
    [ -w "$dir" ] || fail "$dir is not writable; run the installer again"
    download
    if [ "$os" = linux ]; then
        unpack_linux
        place_binary "$target"
        # the desktop entry and icons too when the installer put them there
        prefix=$(dirname "$dir")
        if [ -f "$prefix/share/applications/rhun.desktop" ] && [ -w "$prefix/share/applications" ]; then
            place_desktop "$prefix" "$target"
        fi
    else
        unpack_mac
        place_app "$target"
    fi
}

uninstall() {
    if [ "$os" = linux ]; then
        prefix=${prefix:-$HOME/.local}
        rm -f "$prefix/bin/rhun" "$prefix/share/applications/rhun.desktop"
        for d in scalable/apps/rhun.svg 256x256/apps/rhun.png 512x512/apps/rhun.png; do
            rm -f "$prefix/share/icons/hicolor/$d"
        done
        refresh_desktop "$prefix"
        say "rhun is removed from $prefix"
    else
        if [ -n "$appdir" ]; then
            rm -rf "$appdir/rhun.app"
        else
            rm -rf /Applications/rhun.app "$HOME/Applications/rhun.app" 2>/dev/null || true
        fi
        if [ -f "$HOME/.local/bin/rhun" ] && grep -q 'rhun.app/Contents/MacOS/rhun' "$HOME/.local/bin/rhun"; then
            rm -f "$HOME/.local/bin/rhun"
        fi
        say "rhun is removed"
    fi
    remove_path_from "$HOME/.zshrc"
    remove_path_from "$HOME/.bashrc"
    remove_path_from "$HOME/.bash_profile"
    rm -f "$HOME/.config/fish/conf.d/rhun.fish"
    say "your settings are still in ${XDG_CONFIG_HOME:-$HOME/.config}/rhun"
}

main() {
    version='' prefix='' appdir='' modify_path=1 mode=install target='' quiet=''
    while [ $# -gt 0 ]; do
        case $1 in
        --version) version=${2:-}; shift ;;
        --prefix) prefix=${2:-}; shift ;;
        --app-dir) appdir=${2:-}; shift ;;
        --no-modify-path) modify_path= ;;
        --uninstall) mode=uninstall ;;
        --update) mode=update; quiet=1 ;;
        --target) target=${2:-}; shift ;;
        -h | --help) usage; exit 0 ;;
        *) fail "unknown option $1 (see --help)" ;;
        esac
        shift
    done
    [ -n "${HOME:-}" ] || fail "HOME is not set"
    platform
    tmp=$(mktemp -d 2>/dev/null || mktemp -d -t rhun)
    trap 'rm -rf "$tmp"' EXIT
    trap 'exit 1' HUP INT TERM
    if [ "$mode" = uninstall ]; then
        uninstall
        return 0
    fi
    base=${RHUN_RELEASES_URL:-$RELEASES}
    downloader
    if [ -z "$version" ]; then version=$(latest_version); fi
    valid_version "$version" || fail "$version is not a version"
    if [ "$mode" = update ]; then
        update
    else
        install_fresh
    fi
}

main "$@"
