#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Markdown Viewer"
APP_PATH="$ROOT/build/$APP_NAME.app"
DMG_PATH="$ROOT/build/$APP_NAME.dmg"
DMG_TMP="$ROOT/build/${APP_NAME}.tmp.dmg"
STAGE="$ROOT/build/dmg-stage"
BG_SRC="$ROOT/Resources/dmg-background.png"

if [ ! -d "$APP_PATH" ]; then
  echo "App not found at $APP_PATH"
  echo "Run ./build.sh first."
  exit 1
fi

echo "==> Generating DMG background (if missing)"
if [ ! -f "$BG_SRC" ] \
   || [ "$ROOT/Tools/make_dmg_background.swift" -nt "$BG_SRC" ]; then
  swift "$ROOT/Tools/make_dmg_background.swift" "$BG_SRC"
fi

echo "==> Preparing staging directory"
rm -rf "$STAGE" "$DMG_PATH" "$DMG_TMP"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Re-signing ad-hoc"
codesign --force --deep --sign - "$STAGE/$APP_NAME.app" >/dev/null

echo "==> Creating writable DMG"
# Size = staged content + 10 MB headroom, rounded up.
STAGE_MB=$(du -sm "$STAGE" | cut -f1)
DMG_MB=$((STAGE_MB + 10))
hdiutil create \
  -size ${DMG_MB}m \
  -volname "$APP_NAME" \
  -fs "HFS+" \
  -ov \
  "$DMG_TMP" >/dev/null

echo "==> Mounting"
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TMP" \
  | egrep '^/dev/' | sed 1q | awk '{print $1}')
MOUNT_POINT="/Volumes/$APP_NAME"
sleep 1

echo "==> Copying contents into volume"
cp -R "$STAGE/$APP_NAME.app" "$MOUNT_POINT/"
ln -s /Applications "$MOUNT_POINT/Applications"
rm -rf "$STAGE"

echo "==> Installing background image"
mkdir -p "$MOUNT_POINT/.background"
cp "$BG_SRC" "$MOUNT_POINT/.background/background.png"

echo "==> Styling window via Finder"
# This may briefly require Automation permission for Terminal (or Claude) the first time.
osascript <<APPLESCRIPT || echo "    (Finder styling skipped — DMG will still work, just unstyled.)"
tell application "Finder"
    tell disk "$APP_NAME"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set sidebar width of container window to 0
        set the bounds of container window to {200, 120, 800, 548}
        set opts to icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 96
        set text size of opts to 13
        set background picture of opts to file ".background:background.png"
        set position of item "$APP_NAME.app" of container window to {150, 220}
        set position of item "Applications" of container window to {450, 220}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Ensure metadata is flushed before unmounting.
sync
sleep 1

echo "==> Unmounting"
hdiutil detach "$DEVICE" >/dev/null

echo "==> Converting to compressed read-only"
hdiutil convert "$DMG_TMP" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH" >/dev/null
rm "$DMG_TMP"

SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo
echo "Built: $DMG_PATH ($SIZE)"
echo
echo "To share:"
echo "  1. Send the .dmg (AirDrop, email, etc.)"
echo "  2. They double-click it — sees the Markdown Viewer icon, an arrow,"
echo "     and an Applications shortcut. Drag one onto the other."
echo "  3. First launch on their Mac: right-click the app -> Open."
