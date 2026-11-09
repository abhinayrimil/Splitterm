#!/usr/bin/env bash
# Builds Splitterm.app and a .dmg installer.
#
#   scripts/build-app.sh                 # universal (arm64 + x86_64) build, ad-hoc signed
#   UNIVERSAL=0 scripts/build-app.sh     # this Mac's architecture only (works with Command Line Tools)
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/build-app.sh
#   SIGN_IDENTITY=... NOTARY_PROFILE=splitterm scripts/build-app.sh   # also notarise and staple
#
# Create the notary profile once with:
#   xcrun notarytool store-credentials splitterm --apple-id you@example.com --team-id TEAMID
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || date +%Y%m%d%H%M)}"
BUNDLE_ID="${BUNDLE_ID:-dev.splitterm.app}"
UNIVERSAL="${UNIVERSAL:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

DIST="$ROOT/dist"
APP="$DIST/Splitterm.app"
DMG="$DIST/Splitterm-$VERSION.dmg"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

command -v swift >/dev/null || { echo "swift not found: install Xcode 16+ or the Command Line Tools"; exit 1; }

step "Compiling (release)"
if [[ "$UNIVERSAL" == "1" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
else
    ARCH_FLAGS=()
fi
swift build -c release "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}" --show-bin-path)"
[[ -x "$BIN_DIR/Splitterm" ]] || { echo "Build output not found in $BIN_DIR"; exit 1; }

step "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Splitterm" "$APP/Contents/MacOS/Splitterm"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" -e "s/__BUNDLE_ID__/$BUNDLE_ID/" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp README.md "$APP/Contents/Resources/README.md"
# SwiftPM resource bundles (if any dependency ships one).
find "$BIN_DIR" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;

step "Building the icon"
ICONSET="$DIST/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

step "Signing (${SIGN_IDENTITY})"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --options runtime \
        --entitlements Resources/Splitterm.entitlements --sign - "$APP"
else
    codesign --force --options runtime --timestamp \
        --entitlements Resources/Splitterm.entitlements \
        --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

step "Creating $DMG"
STAGE="$DIST/dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Splitterm $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
    [[ "$SIGN_IDENTITY" != "-" ]] || { echo "Notarisation needs a Developer ID SIGN_IDENTITY"; exit 1; }
    step "Notarising (this can take a few minutes)"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler staple "$APP"
    spctl --assess --type open --context context:primary-signature -v "$DMG" || true
fi

step "Done"
echo "App: $APP"
echo "DMG: $DMG"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo
    echo "Ad-hoc signed: runs on this Mac. To share it, sign with a Developer ID and notarise,"
    echo "or recipients must right-click the app and choose Open the first time."
fi
