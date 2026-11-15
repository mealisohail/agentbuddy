#!/bin/sh
# ./build.sh            build, install to ~/Applications and launch (for development)
# ./build.sh --release  universal (Apple Silicon + Intel) build → dist/AgentBuddy.zip, and update the Homebrew cask's sha256
set -e
cd "$(dirname "$0")"
VERSION=1.0.1
BUILD=1
BUNDLE_ID=dev.agentbuddy.app

if [ "$1" = "--release" ]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN=.build/apple/Products/Release/AgentBuddy
else
  swift build -c release
  BIN=.build/release/AgentBuddy
fi

APP=build/AgentBuddy.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AgentBuddy"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>AgentBuddy</string>
  <key>CFBundleDisplayName</key><string>AgentBuddy</string>
  <key>CFBundleExecutable</key><string>AgentBuddy</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Sohail Akhtar Ali. MIT License.</string>
  <key>NSAppleEventsUsageDescription</key><string>AgentBuddy uses this to jump to, and type into, the Terminal or iTerm tab that runs a Claude Code session.</string>
</dict></plist>
PLIST
# ponytail: ad-hoc signature, not notarized (no paid Apple Developer account). Installers clear the quarantine flag.
codesign --force --sign - "$APP"

if [ "$1" = "--release" ]; then
  mkdir -p dist
  rm -f dist/AgentBuddy.zip
  ditto -c -k --keepParent "$APP" dist/AgentBuddy.zip
  SHA=$(shasum -a 256 dist/AgentBuddy.zip | cut -d' ' -f1)
  sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" Casks/agentbuddy.rb
  echo "dist/AgentBuddy.zip  ($VERSION, sha256 $SHA)"
  echo "Next: create GitHub release v$VERSION and upload dist/AgentBuddy.zip, then commit Casks/agentbuddy.rb"
  exit 0
fi

pkill -x AgentBuddy 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/AgentBuddy.app
cp -R "$APP" ~/Applications/
open ~/Applications/AgentBuddy.app
echo "Installed ~/Applications/AgentBuddy.app ($VERSION)"
