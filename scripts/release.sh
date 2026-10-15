#!/bin/bash
# Builds an Apple-Silicon-only (arm64), ad-hoc-signed Import Photos.app and packages it as a DMG.
# No Apple Developer account needed. Friends must do the one-time "Open Anyway" (see FRIENDS-READ-ME.txt).
# Usage: scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep -E '^\s*MARKETING_VERSION:' project.yml | head -1 | awk '{print $2}')
APP_NAME="Import Photos"
BUILD=build/release
DIST=dist
APP="$BUILD/Build/Products/Release/$APP_NAME.app"

echo "==> Tests"
swift test 2>&1 | grep -E "Executed .* tests|error:" | tail -1

echo "==> Generate project"
xcodegen generate >/dev/null

echo "==> Build Release (arm64 only, ad-hoc signed)"
rm -rf "$BUILD"
xcodebuild -project PhotoImport.xcodeproj -scheme PhotoImport -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$BUILD" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  build 2>&1 | grep -E "error:|warning: .*(sign|entitle)|BUILD (SUCCEEDED|FAILED)"

echo "==> Verify"
codesign --verify --deep --strict "$APP" && echo "signature ok (ad-hoc)"
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -E "app-sandbox|user-selected|bookmarks" | sed 's/^/   /'
ARCHS_FOUND=$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")
echo "   architectures: $ARCHS_FOUND"
[ "$ARCHS_FOUND" = "arm64" ] || { echo "ERROR: expected an arm64-only binary, got: $ARCHS_FOUND"; exit 1; }

echo "==> Package DMG"
rm -rf "$DIST/stage"; mkdir -p "$DIST/stage"
cp -R "$APP" "$DIST/stage/"
ln -s /Applications "$DIST/stage/Applications"
cp scripts/FRIENDS-READ-ME.txt "$DIST/stage/READ ME FIRST.txt"
DMG="$DIST/ImportPhotos-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$DIST/stage" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$DIST/stage"
echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1))"
shasum -a 256 "$DMG"
