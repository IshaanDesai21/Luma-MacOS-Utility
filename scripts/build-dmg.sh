#!/usr/bin/env bash
#
# Builds Luma (Release) and packages it into a distributable DMG.
# Requires full Xcode (not just Command Line Tools).
#
#   ./scripts/build-dmg.sh
#
# Output: build/Luma.dmg
#
set -euo pipefail

PROJECT="Luma.xcodeproj"
SCHEME="Luma"
CONFIG="Release"
APP="Luma.app"
VOLUME="Luma"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
DERIVED="$BUILD/DerivedData"
STAGE="$BUILD/dmg"
DMG="$BUILD/Luma.dmg"

cd "$ROOT"
rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "▸ Building $SCHEME ($CONFIG)…"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  clean build

APP_PATH="$DERIVED/Build/Products/$CONFIG/$APP"
if [ ! -d "$APP_PATH" ]; then
  echo "✗ Build product not found at: $APP_PATH" >&2
  exit 1
fi

echo "▸ Staging disk image…"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"

echo "▸ Creating ${DMG}"
rm -f "$DMG"

BACKGROUND="$ROOT/scripts/dmg-background.png"
if command -v create-dmg >/dev/null 2>&1 && [ -f "$BACKGROUND" ]; then
  # Styled window: custom background, positioned icons, drag arrow.
  create-dmg \
    --volname "$VOLUME" \
    --background "$BACKGROUND" \
    --window-pos 200 120 \
    --window-size 660 440 \
    --icon-size 128 \
    --icon "$APP" 165 210 \
    --hide-extension "$APP" \
    --app-drop-link 495 210 \
    --no-internet-enable \
    "$DMG" \
    "$STAGE"
else
  # Fallback: plain DMG with an Applications shortcut.
  ln -s /Applications "$STAGE/Applications"
  hdiutil create \
    -volname "$VOLUME" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG"
fi

echo "▸ Zipping app (alternative download)…"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$BUILD/Luma.zip"

echo ""
echo "✓ Done → $DMG"
echo "         $BUILD/Luma.zip"
echo "  Drag Luma into Applications from the mounted image."
