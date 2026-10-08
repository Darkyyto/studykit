#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="$(awk -F'"' '/MARKETING_VERSION/{print $2; exit}' "$ROOT/project.yml")"
WORK="${TMPDIR:-/tmp}/FocusKit-release"
DIST="$ROOT/dist"
APP="$WORK/Build/Products/Release/FocusKit.app"
DMG="$DIST/FocusKit-$VERSION.dmg"

rm -rf "$WORK/stage"
mkdir -p "$DIST" "$WORK/stage"

cd "$ROOT"
xcodegen generate --quiet
xcodebuild \
  -project FocusKit.xcodeproj \
  -scheme FocusKit \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$WORK" \
  -quiet \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  build

xattr -cr "$APP"
IDENTITY="-"
KEYCHAIN_ARGS=()
if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then
  IDENTITY="FocusKit Signing"
  KEYCHAIN_ARGS=(--keychain "$SIGNING_KEYCHAIN")
elif [[ -f "$ROOT/signing/build.keychain-db" && -f "$ROOT/signing/p12-password.txt" ]]; then
  security unlock-keychain -p "$(cat "$ROOT/signing/p12-password.txt")" "$ROOT/signing/build.keychain-db"
  IDENTITY="FocusKit Signing"
  KEYCHAIN_ARGS=(--keychain "$ROOT/signing/build.keychain-db")
fi

codesign --force --deep --options runtime "${KEYCHAIN_ARGS[@]}" --sign "$IDENTITY" \
  --entitlements "$ROOT/FocusKit/Resources/FocusKit.entitlements" "$APP"
codesign --verify --strict "$APP"

ditto "$APP" "$WORK/stage/FocusKit.app"
ln -s /Applications "$WORK/stage/Applications"

rm -f "$DMG"
hdiutil create -quiet -volname "FocusKit" -srcfolder "$WORK/stage" -ov -format ULFO "$DMG"

cp "$DMG" "$DIST/FocusKit.dmg"

rm -f "$DIST/FocusKit-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/FocusKit-$VERSION.zip"

echo "App  $(du -sh "$APP" | cut -f1)"
echo "DMG  $(du -h "$DMG" | cut -f1)  $DMG"
