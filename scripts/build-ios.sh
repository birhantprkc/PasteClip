#!/bin/bash
# Clipbara iPhone App Store build pipeline (app + keyboard + share extensions).
#
# Usage:
#   bash scripts/build-ios.sh            # archive + export signed .ipa (no upload)
#   UPLOAD=1 bash scripts/build-ios.sh   # archive + upload to App Store Connect
#
# Signing is automatic (project.yml). -allowProvisioningUpdates lets Xcode create the
# App Store profiles with the Apple Account signed in to Xcode, so run it from a
# Terminal where Xcode's account is available (not a sandboxed shell).
set -euo pipefail

cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="/opt/homebrew/bin:$PATH"
export USER="${USER:-$(id -un)}"
export LOGNAME="${LOGNAME:-$USER}"

TEAM_ID="5DH57J8HLC"
SCHEME="ClipbaraiOS"
BUILD_DIR="build/ios"
ARCHIVE_PATH="$BUILD_DIR/Clipbara.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Generating Xcode project"
xcodegen generate

VERSION=$(awk '/^  ClipbaraiOS:$/,/^  ClipbaraKeyboard:$/' project.yml | awk -F'"' '/MARKETING_VERSION/{print $2}')
BUILD_NUM=$(awk '/^  ClipbaraiOS:$/,/^  ClipbaraKeyboard:$/' project.yml | awk -F'"' '/CURRENT_PROJECT_VERSION/{print $2}')
echo "==> Version: $VERSION ($BUILD_NUM)"

echo "==> Archiving $SCHEME (Release)"
xcodebuild archive \
  -project Clipbara.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  | tail -5

DESTINATION=export
[ "${UPLOAD:-0}" = "1" ] && DESTINATION=upload
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>$DESTINATION</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo "==> Exporting ($DESTINATION)"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates

APP="$ARCHIVE_PATH/Products/Applications/Clipbara.app"
echo "==> Entitlements (app)"
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -A1 -E "aps-environment|icloud-container|application-groups" | head -12
if [ "$DESTINATION" = "upload" ]; then
  echo "OK: uploaded $VERSION ($BUILD_NUM). Check App Store Connect > TestFlight for processing."
else
  echo "OK: $(ls "$EXPORT_PATH"/*.ipa) ($VERSION build $BUILD_NUM)"
  echo "To upload: UPLOAD=1 bash scripts/build-ios.sh"
fi
