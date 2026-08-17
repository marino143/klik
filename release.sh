#!/usr/bin/env bash
# Build a distributable Klik: Developer ID signature, hardened runtime,
# notarised by Apple and stapled so it opens without a Gatekeeper warning.
#
#   ./release.sh 0.2.0
#
# build.sh signs with an Apple Development certificate, which is right for
# local runs but is rejected on every Mac other than this one. That is what
# this script replaces.
#
# Notarisation needs credentials this script deliberately does not contain.
# Store them once, in your own terminal, and they stay in your keychain:
#
#   xcrun notarytool store-credentials klik-notary \
#       --key ~/Downloads/AuthKey_XXXXXXXXXX.p8 \
#       --key-id XXXXXXXXXX \
#       --issuer <issuer-uuid-from-App-Store-Connect>
#
# Override the profile name with NOTARY_PROFILE if you use a different one.
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "usage: $0 <version>   e.g. $0 0.2.0" >&2
    exit 1
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Klik"
APP_BUNDLE="$HERE/build/$APP_NAME.app"
ZIP="$HERE/build/$APP_NAME.app.zip"
ENTITLEMENTS="$HERE/Resources/$APP_NAME.entitlements"
IDENTITY="${KLIK_RELEASE_IDENTITY:-Developer ID Application: Co Digit d.o.o. (N6P82864Q5)}"
PROFILE="${NOTARY_PROFILE:-klik-notary}"

PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$HERE/Resources/Info.plist")"
if [ "$PLIST_VERSION" != "$VERSION" ]; then
    echo "✗ Info.plist says $PLIST_VERSION but you asked for $VERSION — bump the plist first." >&2
    exit 1
fi

if ! security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
    echo "✗ No signing identity in the keychain matching: $IDENTITY" >&2
    exit 1
fi

echo "→ Building…"
"$HERE/build.sh" release >/dev/null

# Developer ID signature, hardened runtime and a secure timestamp are what the
# notary service requires; --deep is deliberately absent (Apple deprecated it
# and the bundle has nothing nested to sign anyway).
echo "→ Signing with Developer ID…"
codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" "$APP_BUNDLE"
codesign --verify --strict --verbose=2 "$APP_BUNDLE"

# ditto, not zip: it preserves the bundle metadata the notary service expects.
echo "→ Packaging…"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP"

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    cat >&2 <<EOF

✗ No notarytool profile named "$PROFILE".

  The app is built and Developer ID signed at:
      $APP_BUNDLE
  but it is NOT notarised, so macOS will refuse to open it on another Mac.

  Store your credentials once (see the header of this script), then re-run.
EOF
    exit 1
fi

echo "→ Notarising (this waits on Apple, usually a couple of minutes)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "→ Stapling…"
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

# The ticket is stapled into the .app, so the archive has to be rebuilt from it.
echo "→ Repackaging with the ticket…"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP"

echo "→ Verifying as Gatekeeper sees it…"
spctl -a -vvv -t install "$APP_BUNDLE"

echo ""
echo "✓ $ZIP is ready to upload as v$VERSION"
echo ""
echo "  gh release upload v$VERSION \"$ZIP\" --clobber"
