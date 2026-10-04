#!/bin/sh
# macOS release: rhun.app signed with a Developer ID (hardened runtime), notarized and stapled, in
# build/rhun-VERSION-macos-arm64.zip (for install.sh and updates) and build/rhun-VERSION-macos-arm64.dmg.
# usage: tools/package-mac.sh
#   RHUN_SIGN_ID          signing identity (default: the first Developer ID Application certificate)
#   RHUN_NOTARY_PROFILE   notarytool keychain profile (default rhun-notary), stored once with
#                         xcrun notarytool store-credentials rhun-notary --apple-id ID --team-id TEAM
#   RHUN_NOTARY_KEY, RHUN_NOTARY_KEY_ID, RHUN_NOTARY_ISSUER
#                         an App Store Connect API key (the .p8 file, its key id, the issuer id) in
#                         place of the profile; the release workflow uses these
#   RHUN_NOTARIZE=0       sign only for local use, and no disk image; forbidden with RHUN_DIST=1
set -eu
cd "$(dirname "$0")/.."
notarize=${RHUN_NOTARIZE:-1}
case "$notarize" in 0|1) ;; *) echo "package-mac: RHUN_NOTARIZE must be 0 or 1" >&2; exit 1 ;; esac
if [ "${RHUN_DIST:-0}" = 1 ] && [ "$notarize" != 1 ]; then
    echo "package-mac: distribution builds must be notarized" >&2
    exit 1
fi
if [ "$notarize" = 1 ] && [ -n "${RHUN_NOTARY_KEY:-}" ]; then
    [ -s "$RHUN_NOTARY_KEY" ] || { echo "package-mac: notary API key is missing or empty" >&2; exit 1; }
    : "${RHUN_NOTARY_KEY_ID:?missing notary API key id}"
    : "${RHUN_NOTARY_ISSUER:?missing notary API issuer id}"
fi
id=${RHUN_SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"$/\1/p' | head -1)}
[ -n "$id" ] || { echo "package-mac: no Developer ID Application certificate in the keychain" >&2; exit 1; }
profile=${RHUN_NOTARY_PROFILE:-rhun-notary}
if [ "$notarize" = 1 ] && [ -z "${RHUN_NOTARY_KEY:-}" ] &&
    ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
    echo "package-mac: no notarytool profile '$profile'; store one with" >&2
    echo "  xcrun notarytool store-credentials $profile --apple-id YOUR_APPLE_ID --team-id TEAM_ID" >&2
    echo "or run with RHUN_NOTARIZE=0 to sign only" >&2
    exit 1
fi
version=$(cat VERSION)
app=build/rhun.app
zip=build/rhun-$version-macos-arm64.zip
dmg=build/rhun-$version-macos-arm64.dmg

tools/build-mac.sh release
codesign --force --options runtime --timestamp --sign "$id" "$app"
codesign --verify --strict --verbose=2 "$app"

submit() { # file: notarize and wait
    if [ -n "${RHUN_NOTARY_KEY:-}" ]; then
        xcrun notarytool submit "$1" --key "$RHUN_NOTARY_KEY" --key-id "$RHUN_NOTARY_KEY_ID" \
            --issuer "$RHUN_NOTARY_ISSUER" --wait --timeout 20m --output-format json > build/notary.json || {
                cat build/notary.json >&2; return 1;
            }
    else
        xcrun notarytool submit "$1" --keychain-profile "$profile" --wait --timeout 20m --output-format json > build/notary.json || {
            cat build/notary.json >&2; return 1;
        }
    fi
    cat build/notary.json
    python3 -c 'import json, sys; sys.exit(0 if json.load(open(sys.argv[1]))["status"] == "Accepted" else 1)' build/notary.json
}
if [ "$notarize" = 1 ]; then
    ditto -c -k --keepParent "$app" build/rhun.zip
    submit build/rhun.zip
    rm build/rhun.zip
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
fi
# the app for install.sh and updates; ditto keeps the signature and the stapled ticket
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

echo "$zip"
[ "$notarize" = 1 ] || exit 0

# the disk image: the app and a link to Applications
stage=$(mktemp -d)
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
rm -f "$dmg"
hdiutil create -quiet -volname rhun -srcfolder "$stage" -format UDZO -o "$dmg"
rm -rf "$stage"
codesign --force --timestamp --sign "$id" "$dmg"
submit "$dmg"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
echo "$dmg"
