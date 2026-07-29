#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MacWall"
APP_DIR="$ROOT/dist/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
APP_ICON_SOURCE="$ROOT/logo/app-icon/MacWall.icns"
SAVER_NAME="MacWall"
SAVER_DIR="$RESOURCES_DIR/$SAVER_NAME.saver"
SAVER_MACOS_DIR="$SAVER_DIR/Contents/MacOS"
SAVER_EXECUTABLE="MacWall Lock Screen"
DMG_PATH="$ROOT/dist/MacWall-macOS-arm64.dmg"
APP_VERSION="${APP_VERSION:-1.0.0}"
BUNDLE_VERSION="${BUNDLE_VERSION:-7}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
REQUIRE_SIGNING="${REQUIRE_SIGNING:-0}"
DMG_STAGING=""

cleanup() {
  if [ -n "$DMG_STAGING" ] && [ -d "$DMG_STAGING" ]; then
    rm -rf "$DMG_STAGING"
  fi
}
trap cleanup EXIT

cd "$ROOT"
swift build -c release
rm -rf "$ROOT/dist"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$SAVER_MACOS_DIR"
cp "$ROOT/.build/release/MacWall" "$MACOS_DIR/MacWall"
cp "$ROOT/.build/release/macwallctl" "$MACOS_DIR/macwallctl"
cp "$APP_ICON_SOURCE" "$RESOURCES_DIR/MacWall.icns"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>MacWall</string>
  <key>CFBundleIdentifier</key>
  <string>io.github.mingyu1715.MacWall</string>
  <key>CFBundleIconFile</key>
  <string>MacWall.icns</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>MacWall</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUNDLE_VERSION}</string>
  <key>LSUIElement</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST
cat > "$SAVER_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${SAVER_EXECUTABLE}</string>
  <key>CFBundleIdentifier</key>
  <string>io.github.mingyu1715.MacWall.LockScreenSaver</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>MacWall</string>
  <key>CFBundlePackageType</key>
  <string>BNDL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUNDLE_VERSION}</string>
  <key>NSPrincipalClass</key>
  <string>MacWallLockScreenSaverView</string>
</dict>
</plist>
PLIST
clang \
  -fobjc-arc \
  -bundle \
  -framework AppKit \
  -framework AVFoundation \
  -framework CoreMedia \
  -framework QuartzCore \
  -framework ScreenSaver \
  "$ROOT/Sources/MacWallLockScreenSaver/MacWallLockScreenSaverView.m" \
  -o "$SAVER_MACOS_DIR/$SAVER_EXECUTABLE"
chmod +x "$MACOS_DIR/MacWall" "$MACOS_DIR/macwallctl"
chmod +x "$SAVER_MACOS_DIR/$SAVER_EXECUTABLE"
if [ -n "$SIGN_IDENTITY" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$MACOS_DIR/macwallctl"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$MACOS_DIR/MacWall"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$SAVER_DIR"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
  codesign --verify --strict --verbose=2 "$APP_DIR"
elif [ "$REQUIRE_SIGNING" = "1" ]; then
  printf '%s\n' "SIGN_IDENTITY is required when REQUIRE_SIGNING=1." >&2
  exit 1
else
  printf '%s\n' "warning: building an unsigned app; set SIGN_IDENTITY for Developer ID distribution." >&2
fi
DMG_STAGING="$(mktemp -d)"
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null
if [ -n "$SIGN_IDENTITY" ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi
if [ -n "$NOTARY_PROFILE" ]; then
  if [ -z "$SIGN_IDENTITY" ]; then
    printf '%s\n' "NOTARY_PROFILE requires SIGN_IDENTITY because Apple notarization needs a signed app." >&2
    exit 1
  fi
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  spctl -a -vv --type open "$DMG_PATH"
fi
printf '%s\n' "$DMG_PATH"
