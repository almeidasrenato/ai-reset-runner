#!/bin/bash
# Builds build/AIResetRunner.app (menu bar only, LSUIElement) and signs it ad-hoc.
# Ad-hoc is enough: the app never reads the Keychain through the Security API
# (it goes through /usr/bin/security and the claude CLI), so there is no
# "Always Allow" grant that a stable identity would need to preserve.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
swift build -c release
APP=build/AIResetRunner.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp "$(swift build -c release --show-bin-path)/AIResetRunner" "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.local.airesetrunner</string>
  <key>CFBundleName</key><string>AI ResetRunner</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>AIResetRunner</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
rm -f build/AIResetRunner.zip
ditto -c -k --keepParent "$APP" build/AIResetRunner.zip
echo "Built $APP ($VERSION) and build/AIResetRunner.zip"
