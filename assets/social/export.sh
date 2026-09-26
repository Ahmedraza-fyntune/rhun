#!/bin/sh
# Renders the PNGs here from their SVG sources. --shots first retakes the app screenshots.
# Needs google-chrome or chromium; screenshots also need build/rhun and python3-pil.
set -e
cd "$(dirname "$0")"
here=$PWD
root=$(cd ../.. && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ "$1" = --shots ]; then
    # a fake home with the demo agent sessions, so no real session ends up in a picture
    slug=$(printf '%s' "$root" | sed 's/[^A-Za-z0-9]/-/g')
    mkdir -p "$tmp/home/.claude/projects/$slug" "$tmp/home/.codex/sessions/2026/09/26"
    sed "s|@PROJECT@|$root|g" demo/claude.jsonl > "$tmp/home/.claude/projects/$slug/d1.jsonl"
    sed "s|@PROJECT@|$root|g" demo/codex.jsonl > "$tmp/home/.codex/sessions/2026/09/26/rollout-d2.jsonl"
    shot() { # name script size config
        rm -rf "$tmp/home/c" "$tmp/home/s"
        mkdir -p "$tmp/home/c/rhun"
        printf '%b' "$4" > "$tmp/home/c/rhun/config"
        sed "s|@OUT@|$tmp/$1.ppm|" "demo/$2" > "$tmp/$1.rsc"
        (cd "$root" && HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/c" XDG_STATE_HOME="$tmp/home/s" \
            build/rhun "$root" src/app/wrap.s --headless "$3" --scale 2 --script "$tmp/$1.rsc")
        python3 "$root/tools/ppm2png.py" "$tmp/$1.ppm" "$1.png"
    }
    shot screenshot-dark hero.rsc 2560x1600 '[ui]\ntheme = rhun-dark\n'
    shot screenshot-light hero.rsc 2560x1600 '[ui]\ntheme = rhun-light\n'
    shot window-dark window.rsc 2000x1560 '[ui]\ntheme = rhun-dark\nsidebar = false\n'
fi

chrome=$(command -v google-chrome || command -v chromium || command -v chromium-browser || true)
[ -n "$chrome" ] || { echo "export.sh: needs google-chrome or chromium" >&2; exit 1; }
render() { # svg png width height scale
    "$chrome" --headless=new --disable-gpu --hide-scrollbars --no-first-run --no-default-browser-check \
        --allow-file-access-from-files --user-data-dir="$tmp/chrome" --default-background-color=00000000 \
        --force-device-scale-factor="$5" --window-size="$3,$4" --screenshot="$here/$2" "file://$here/$1" \
        >/dev/null 2>&1
    echo "$2"
}
render ../icons/rhun.svg icon-1024.png 64 64 16
render avatar.svg avatar.png 1024 1024 1
render card.svg card.png 1200 630 1
render card.svg card@2x.png 1200 630 2
render github.svg github.png 1280 640 1
render github.svg github@2x.png 1280 640 2
render square.svg square.png 1080 1080 1
render banner.svg banner.png 1500 500 1
render banner.svg banner@2x.png 1500 500 2
