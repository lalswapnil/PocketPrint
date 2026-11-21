#!/bin/bash
# Builds dist/PocketPrint.ipa.
#
#   scripts/build_ipa.sh              Unsigned IPA (sign/install it with Sideloadly, AltStore, etc.)
#   TEAM_ID=ABCDE12345 scripts/build_ipa.sh
#                                     Signed development IPA for your own devices
#                                     (Xcode must be signed in to that Apple ID/team).
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate --quiet
fi

BUILD_DIR="build/release"
rm -rf "$BUILD_DIR" dist/PocketPrint.ipa
mkdir -p "$BUILD_DIR" dist

if [[ -n "${TEAM_ID:-}" ]]; then
    xcodebuild -project PocketPrint.xcodeproj -scheme PocketPrint -configuration Release \
        -destination 'generic/platform=iOS' -archivePath "$BUILD_DIR/PocketPrint.xcarchive" \
        DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates archive

    cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>debugging</string>
    <key>teamID</key><string>${TEAM_ID}</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
    xcodebuild -exportArchive -archivePath "$BUILD_DIR/PocketPrint.xcarchive" \
        -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" -exportPath "$BUILD_DIR/export" -allowProvisioningUpdates
    cp "$BUILD_DIR/export/PocketPrint.ipa" dist/PocketPrint.ipa
else
    xcodebuild -project PocketPrint.xcodeproj -scheme PocketPrint -configuration Release \
        -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$BUILD_DIR/DerivedData" \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build

    APP="$BUILD_DIR/DerivedData/Build/Products/Release-iphoneos/PocketPrint.app"
    # Ad-hoc signature so the bundle is structurally valid; sideloading tools re-sign it.
    codesign --force --sign - --timestamp=none "$APP"
    mkdir -p "$BUILD_DIR/ipa/Payload"
    cp -R "$APP" "$BUILD_DIR/ipa/Payload/"
    (cd "$BUILD_DIR/ipa" && zip -qry ../../../dist/PocketPrint.ipa Payload)
fi

echo "Built $(pwd)/dist/PocketPrint.ipa"
