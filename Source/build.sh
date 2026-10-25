#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT_DIR=${1:-"$SCRIPT_DIR/.."}
APP="$OUT_DIR/S5M2 Compatibility Tool.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ICON_WORK=$(mktemp -d "${TMPDIR:-/tmp}/s5m2-icon.XXXXXX")
trap 'rm -rf "$ICON_WORK"' EXIT
xcrun clang -fobjc-arc -O2 "$SCRIPT_DIR/MakeIcon.m" -framework Cocoa -o "$ICON_WORK/make-icon"
"$ICON_WORK/make-icon" "$ICON_WORK/AppIcon.iconset"
iconutil -c icns "$ICON_WORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
xcrun clang -fobjc-arc -fblocks -O2 -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations \
  -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
  "$SCRIPT_DIR/Main.m" "$SCRIPT_DIR/PatchCore.m" -framework Cocoa \
  -o "$APP/Contents/MacOS/S5M2Compatibility"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.s5m2.compatibility-tool</string>
<key>CFBundleName</key><string>S5M2 Compatibility Tool</string>
<key>CFBundleDisplayName</key><string>S5M2 Compatibility Tool</string>
<key>CFBundleExecutable</key><string>S5M2Compatibility</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Independent experimental compatibility tool. Not affiliated with Capture One or Panasonic.</string>
</dict></plist>
PLIST
codesign --force --sign - --timestamp=none --options runtime "$APP"
codesign --verify --deep --strict "$APP"
printf '%s\n' "$APP"
