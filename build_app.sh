#!/bin/bash
# Builds SwiftFlow.app — a proper menu-bar app bundle so macOS attributes
# Microphone + Accessibility permissions to SwiftFlow itself (not Terminal).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=SwiftFlow.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>SwiftFlow</string>
    <key>CFBundleIdentifier</key><string>com.saimandava.swiftflow</string>
    <key>CFBundleName</key><string>SwiftFlow</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>SwiftFlow needs the microphone to transcribe your speech.</string>
</dict>
</plist>
PLIST

cp .build/release/SwiftFlow "$APP/Contents/MacOS/SwiftFlow"
codesign --force --sign - "$APP"

# Every rebuild changes the ad-hoc signature, which silently invalidates the
# old Accessibility grant. Clear it so macOS prompts fresh instead of showing
# a stale "on" toggle that doesn't actually work.
tccutil reset Accessibility com.saimandava.swiftflow >/dev/null 2>&1 || true

echo ""
echo "Built $PWD/$APP"
echo "Run with:  open $APP"
