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
codesign --force --deep --options runtime --sign - \
  --entitlements "$ROOT/FocusKit/Resources/FocusKit.entitlements" "$APP"
codesign --verify --strict "$APP"

ditto "$APP" "$WORK/stage/FocusKit.app"
ln -s /Applications "$WORK/stage/Applications"

rm -f "$DMG"
hdiutil create -quiet -volname "FocusKit" -srcfolder "$WORK/stage" -ov -format ULFO "$DMG"

cp "$DMG" "$DIST/FocusKit.dmg"

echo "App  $(du -sh "$APP" | cut -f1)"
echo "DMG  $(du -h "$DMG" | cut -f1)  $DMG"
