#!/bin/bash
set -e

APP_NAME="Snip"
BIN_NAME="snip"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

# Build the release binary
echo "Building release binary..."
swift build -c release

# Create directories
mkdir -p "${MACOS_DIR}"
mkdir -p "${CONTENTS_DIR}/Resources"

# Copy binary
cp .build/release/${BIN_NAME} "${MACOS_DIR}/${APP_NAME}"

# Create Info.plist
cat << 'PLIST' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Snip</string>
    <key>CFBundleIdentifier</key>
    <string>com.duong1326.snip</string>
    <key>CFBundleName</key>
    <string>Snip</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Successfully created ${APP_DIR}!"
