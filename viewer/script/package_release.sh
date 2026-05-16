#!/usr/bin/env bash
set -euo pipefail

APP_NAME="HTTMELY"
BUNDLE_NAME="HTTMELY"
BUNDLE_ID="dev.realitytest.httmely"
MIN_SYSTEM_VERSION="14.0"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
TEAM_ID="${TEAM_ID:-}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-HTTMELY}"
NOTARIZE="${NOTARIZE:-0}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(cd "$ROOT_DIR/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/release"
WORK_DIR="$RELEASE_DIR/work"
DMG_ROOT="$WORK_DIR/dmg-root"
APP_BUNDLE="$RELEASE_DIR/$BUNDLE_NAME.app"
DMG_PATH="$RELEASE_DIR/$BUNDLE_NAME-$VERSION.dmg"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
APP_ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"
WELCOME_SOURCE="$ROOT_DIR/Resources/Welcome"
INFO_PLIST="$APP_CONTENTS/Info.plist"

echo "Building $BUNDLE_NAME $VERSION ($BUILD_NUMBER)"

cd "$ROOT_DIR"
swift build -c release
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$RELEASE_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$DMG_ROOT"

cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$APP_ICON_SOURCE" ]]; then
  cp "$APP_ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
fi

if [[ -d "$WELCOME_SOURCE" ]]; then
  cp -R "$WELCOME_SOURCE" "$APP_RESOURCES/Welcome"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$BUNDLE_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$BUNDLE_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$INFO_PLIST"

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing app with: $SIGN_IDENTITY"
  /usr/bin/codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BINARY"
  /usr/bin/codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
  echo "No SIGN_IDENTITY provided; using ad-hoc app signing for local builds."
  /usr/bin/codesign --force --options runtime --sign - "$APP_BINARY"
  /usr/bin/codesign --force --options runtime --sign - "$APP_BUNDLE"
fi
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

cp -R "$APP_BUNDLE" "$DMG_ROOT/$BUNDLE_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"

rm -f "$DMG_PATH"
/usr/bin/hdiutil create \
  -volname "$BUNDLE_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing DMG"
  /usr/bin/codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
  /usr/bin/codesign --verify --verbose=2 "$DMG_PATH"
else
  echo "Skipping DMG signing because SIGN_IDENTITY is not set."
fi

if [[ "$NOTARIZE" == "1" ]]; then
  echo "Submitting DMG for notarization with keychain profile: $NOTARY_PROFILE"
  /usr/bin/xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  /usr/bin/xcrun stapler staple "$DMG_PATH"
  /usr/sbin/spctl -a -vv -t open --context context:primary-signature "$DMG_PATH"
else
  echo "Skipping notarization. Set NOTARIZE=1 after storing a notarytool keychain profile."
fi

rm -rf "$WORK_DIR"

echo "Release app: $APP_BUNDLE"
echo "Release DMG: $DMG_PATH"
echo "Release docs: $PROJECT_ROOT/release-docs"
