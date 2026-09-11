#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Markdown Viewer"
BIN_NAME="MarkdownViewer"
APP_DIR="$ROOT/build/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

echo "==> Cleaning previous build"
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RES"

echo "==> Fetching marked.min.js (if missing)"
if [ ! -f "$ROOT/Resources/marked.min.js" ]; then
  curl -fsSL -o "$ROOT/Resources/marked.min.js" \
    "https://cdn.jsdelivr.net/npm/marked@14.1.3/marked.min.js"
fi

echo "==> Generating app icon (if missing)"
if [ ! -f "$ROOT/Resources/AppIcon.icns" ] \
   || [ "$ROOT/Tools/make_icon.swift" -nt "$ROOT/Resources/AppIcon.icns" ]; then
  ICONSET="$ROOT/build/AppIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  swift "$ROOT/Tools/make_icon.swift" "$ICONSET"
  iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

echo "==> Copying resources"
cp "$ROOT/Resources/template.html"   "$RES/template.html"
cp "$ROOT/Resources/marked.min.js"   "$RES/marked.min.js"
cp "$ROOT/Resources/AppIcon.icns"    "$RES/AppIcon.icns"
cp "$ROOT/Info.plist"                "$CONTENTS/Info.plist"

echo "==> Compiling Swift"
swiftc -O \
  -target arm64-apple-macos13 \
  -parse-as-library \
  -o "$MACOS/$BIN_NAME" \
  "$ROOT/Sources/main.swift"

# Build a universal binary if x86_64 SDK is available (best effort).
if swiftc -target x86_64-apple-macos13 -parse-as-library \
    -o "$ROOT/build/${BIN_NAME}-x86_64" "$ROOT/Sources/main.swift" 2>/dev/null; then
  mv "$MACOS/$BIN_NAME" "$ROOT/build/${BIN_NAME}-arm64"
  lipo -create -output "$MACOS/$BIN_NAME" \
    "$ROOT/build/${BIN_NAME}-arm64" "$ROOT/build/${BIN_NAME}-x86_64"
  rm "$ROOT/build/${BIN_NAME}-arm64" "$ROOT/build/${BIN_NAME}-x86_64"
  echo "    universal binary built"
else
  echo "    arm64-only build (x86_64 SDK not available)"
fi

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP_DIR"

# Refresh Launch Services so file associations pick up the new bundle.
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
  -f "$APP_DIR" >/dev/null 2>&1 || true

echo
echo "Built: $APP_DIR"
echo
echo "Try it:"
echo "  open -a \"$APP_DIR\" path/to/file.md"
echo
echo "To set as default for .md files, right-click any .md file in Finder"
echo "  -> Get Info -> Open with -> '$APP_NAME' -> Change All..."
