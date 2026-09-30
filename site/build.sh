#!/bin/sh
# Builds the site (published on GitHub Pages by .github/workflows/pages.yml) into OUT: the pages in
# site/ with the version and date filled in, the screenshots from site/img (retaken with
# site/shots/take.sh), the brand font, icon and social card from assets/, and the guide as guide.md
# and, after llms.txt, as llms-full.txt.
# usage: site/build.sh OUT
set -eu
cd "$(dirname "$0")/.."
out=${1:?usage: site/build.sh OUT}
# the latest release: VERSION, or the last tag without a dash while VERSION is a prerelease
version=$(cat VERSION)
case $version in
*-*) version=$(git describe --tags --abbrev=0 --match 'v*' --exclude 'v*-*' 2>/dev/null | sed 's/^v//') ;;
esac
date=$(date -u +%Y-%m-%d)
mkdir -p "$out/img" "$out/fonts"
for f in index.html 404.html robots.txt sitemap.xml llms.txt; do
    sed -e "s/@VERSION@/$version/g" -e "s/@DATE@/$date/g" "site/$f" > "$out/$f"
done
cp site/img/*.webp "$out/img/"
cp site/style.css site/site.js "$out/"
cp site/fonts/* "$out/fonts/"
cp assets/social/card.png "$out/img/card.png"
cp assets/icons/rhun.svg "$out/favicon.svg"
cp assets/icons/rhun-256.png "$out/apple-touch-icon.png"
cp assets/fonts/IosevkaFixed-Regular.ttf assets/fonts/LICENSE-Iosevka.md "$out/fonts/"
cp docs/guide.md "$out/guide.md"
{ cat "$out/llms.txt"; printf '\n---\n\n'; cat docs/guide.md; } > "$out/llms-full.txt"
echo "site $version in $out"
