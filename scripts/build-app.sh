#!/bin/bash
set -e

APP_NAME="RemoteDiff"
BUNDLE_ID="com.evargas.RemoteDiff"
VERSION="1.0.0"
BUILD_DIR=".build/release"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "🔨 Building release..."
swift build -c release

echo "📦 Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy resource bundle (contains Assets.xcassets)
if [ -d "$BUILD_DIR/RemoteDiff_RemoteDiff.bundle" ]; then
    cp -R "$BUILD_DIR/RemoteDiff_RemoteDiff.bundle" "$APP_BUNDLE/Contents/Resources/"
fi

# Generate icon from asset catalog
ICONSET_DIR="RemoteDiff/Assets.xcassets/AppIcon.appiconset"
if [ -d "$ICONSET_DIR" ]; then
    echo "🎨 Creating app icon..."
    ICON_TMP=$(mktemp -d)
    mkdir -p "$ICON_TMP/AppIcon.iconset"
    cp "$ICONSET_DIR/icon_16.png" "$ICON_TMP/AppIcon.iconset/icon_16x16.png"
    cp "$ICONSET_DIR/icon_32.png" "$ICON_TMP/AppIcon.iconset/icon_16x16@2x.png"
    cp "$ICONSET_DIR/icon_32.png" "$ICON_TMP/AppIcon.iconset/icon_32x32.png"
    cp "$ICONSET_DIR/icon_64.png" "$ICON_TMP/AppIcon.iconset/icon_32x32@2x.png"
    cp "$ICONSET_DIR/icon_128.png" "$ICON_TMP/AppIcon.iconset/icon_128x128.png"
    cp "$ICONSET_DIR/icon_256.png" "$ICON_TMP/AppIcon.iconset/icon_128x128@2x.png"
    cp "$ICONSET_DIR/icon_256.png" "$ICON_TMP/AppIcon.iconset/icon_256x256.png"
    cp "$ICONSET_DIR/icon_512.png" "$ICON_TMP/AppIcon.iconset/icon_256x256@2x.png"
    cp "$ICONSET_DIR/icon_512.png" "$ICON_TMP/AppIcon.iconset/icon_512x512.png"
    cp "$ICONSET_DIR/icon_1024.png" "$ICON_TMP/AppIcon.iconset/icon_512x512@2x.png"
    iconutil -c icns "$ICON_TMP/AppIcon.iconset" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$ICON_TMP"
fi

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>RemoteDiff</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026. All rights reserved.</string>
</dict>
</plist>
EOF

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "✅ App bundle created: $APP_BUNDLE"

# Optionally create a DMG
if command -v create-dmg &> /dev/null; then
    echo "📀 Creating DMG..."
    DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
    rm -f "$DMG_PATH"
    create-dmg \
        --volname "$APP_NAME" \
        --window-size 500 300 \
        --icon "$APP_NAME.app" 150 150 \
        --app-drop-link 350 150 \
        "$DMG_PATH" \
        "$APP_BUNDLE"
    echo "✅ DMG created: $DMG_PATH"
else
    # Create a simple zip instead
    echo "📀 Creating ZIP..."
    ZIP_PATH="$BUILD_DIR/$APP_NAME-$VERSION.zip"
    rm -f "$ZIP_PATH"
    cd "$BUILD_DIR" && zip -r -y "$APP_NAME-$VERSION.zip" "$APP_NAME.app"
    echo "✅ ZIP created: $BUILD_DIR/$APP_NAME-$VERSION.zip"
fi
