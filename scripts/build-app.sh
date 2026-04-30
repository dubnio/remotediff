#!/bin/bash
set -e

APP_NAME="RemoteDiff"
BUNDLE_ID="com.evargas.RemoteDiff"
VERSION="1.1.0"
BUILD_DIR=".build/release"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENTITLEMENTS="$SCRIPT_DIR/entitlements.plist"
DMG_BG="$SCRIPT_DIR/dmg-resources/dmg-background.png"

# ----------------------------------------------------------------------------
# Signing identity detection
# ----------------------------------------------------------------------------
#
# Resolution order:
#   1. $RD_SIGN_IDENTITY              — explicit env var (full SHA-1 or name)
#   2. First "Developer ID Application: …" identity in the keychain
#   3. Ad-hoc ("-")                   — fallback for users without a paid
#                                       Developer Program account.
#
# Notarisation only runs when both a Developer ID cert AND a stored notarytool
# credential profile (default: "RemoteDiffNotary") are available.
# ----------------------------------------------------------------------------

DEVELOPER_ID_CERT=""
if [ -n "${RD_SIGN_IDENTITY:-}" ]; then
    DEVELOPER_ID_CERT="$RD_SIGN_IDENTITY"
else
    DEVELOPER_ID_CERT=$(security find-identity -p codesigning -v 2>/dev/null \
        | grep -E '"Developer ID Application:' \
        | head -1 \
        | sed -E 's/.*"(Developer ID Application:[^"]+)".*/\1/')
fi

NOTARY_PROFILE="${RD_NOTARY_PROFILE:-RemoteDiffNotary}"
HAS_NOTARY=false
if [ -n "$DEVELOPER_ID_CERT" ] && [ "$DEVELOPER_ID_CERT" != "-" ]; then
    if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" \
        >/dev/null 2>&1; then
        HAS_NOTARY=true
    fi
fi

if [ -n "$DEVELOPER_ID_CERT" ]; then
    echo "🔑 Signing identity: $DEVELOPER_ID_CERT"
    if $HAS_NOTARY; then
        echo "📨 Notary profile:   $NOTARY_PROFILE  (will notarise + staple)"
    else
        echo "ℹ️  No notary profile '$NOTARY_PROFILE' found — will sign but skip notarisation."
        echo "   Run: scripts/setup-signing.sh to configure."
    fi
else
    echo "⚠️  No Developer ID Application cert found — falling back to ad-hoc signing."
    echo "   Run: scripts/setup-signing.sh for instructions."
    DEVELOPER_ID_CERT="-"
fi

# ----------------------------------------------------------------------------
# Build
# ----------------------------------------------------------------------------

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
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.evargas.RemoteDiff</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>remotediff</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Bundle CLI tool and askpass helper
echo "🔧 Bundling CLI tool..."
cp "scripts/remotediff" "$APP_BUNDLE/Contents/Resources/remotediff"
chmod +x "$APP_BUNDLE/Contents/Resources/remotediff"
cp "scripts/remotediff-askpass" "$APP_BUNDLE/Contents/Resources/remotediff-askpass"
chmod +x "$APP_BUNDLE/Contents/Resources/remotediff-askpass"

# ----------------------------------------------------------------------------
# Code signing
# ----------------------------------------------------------------------------
#
# When we have a real Developer ID cert we enable the Hardened Runtime and
# pass an entitlements plist (required for notarisation). Ad-hoc signing
# falls back to the previous, simpler invocation.
# ----------------------------------------------------------------------------

echo "🔏 Code signing..."
if [ "$DEVELOPER_ID_CERT" != "-" ]; then
    codesign --force --deep \
        --sign "$DEVELOPER_ID_CERT" \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --timestamp \
        "$APP_BUNDLE"

    echo "🔍 Verifying signature..."
    codesign --verify --strict --verbose=2 "$APP_BUNDLE"
else
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo "✅ App bundle created: $APP_BUNDLE"
echo "💡 To install the CLI: $APP_BUNDLE/Contents/Resources/remotediff --install"

# ----------------------------------------------------------------------------
# DMG / ZIP packaging
# ----------------------------------------------------------------------------

DMG_PATH=""
ZIP_PATH=""
if command -v create-dmg &> /dev/null; then
    echo "📀 Creating DMG..."
    DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
    rm -f "$DMG_PATH"

    DMG_ARGS=(
        --volname "$APP_NAME"
        --volicon "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
        --window-pos 200 120
        --window-size 660 400
        --icon-size 80
        --icon "$APP_NAME.app" 165 180
        --app-drop-link 495 180
        --hide-extension "$APP_NAME.app"
        --no-internet-enable
    )

    if [ -f "$DMG_BG" ]; then
        DMG_ARGS+=(--background "$DMG_BG")
    fi

    create-dmg "${DMG_ARGS[@]}" "$DMG_PATH" "$APP_BUNDLE"
    echo "✅ DMG created: $DMG_PATH"

    # Sign the DMG container itself with the Developer ID cert so that
    # `spctl --assess --type install` also accepts the .dmg file directly
    # (the .app inside is already signed; this just covers the disk image).
    if [ "$DEVELOPER_ID_CERT" != "-" ]; then
        echo "🔏 Signing DMG..."
        codesign --force --sign "$DEVELOPER_ID_CERT" --timestamp "$DMG_PATH"
        codesign --verify --verbose=2 "$DMG_PATH"
    fi
else
    echo "⚠️  'create-dmg' not found. Install with: brew install create-dmg"
    echo "📀 Creating ZIP instead..."
    ZIP_PATH="$BUILD_DIR/$APP_NAME-$VERSION.zip"
    rm -f "$ZIP_PATH"
    (cd "$BUILD_DIR" && zip -qr -y "$APP_NAME-$VERSION.zip" "$APP_NAME.app")
    echo "✅ ZIP created: $ZIP_PATH"
fi

# ----------------------------------------------------------------------------
# Notarisation (only when both a Developer ID cert and a notary profile exist)
# ----------------------------------------------------------------------------

if $HAS_NOTARY; then
    if [ -n "$DMG_PATH" ]; then
        TARGET="$DMG_PATH"
    else
        TARGET="$ZIP_PATH"
    fi

    echo ""
    echo "📨 Submitting $(basename "$TARGET") to Apple for notarisation..."
    echo "   (This typically takes 1–5 minutes.)"
    if xcrun notarytool submit "$TARGET" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait; then
        echo "✅ Notarisation accepted."

        # Stapling embeds the ticket so Gatekeeper trusts the file even offline.
        # Stapling .zip is not supported — we'd need to re-zip post-staple.
        if [ -n "$DMG_PATH" ]; then
            echo "📎 Stapling notarisation ticket to DMG..."
            xcrun stapler staple "$DMG_PATH"
            xcrun stapler validate "$DMG_PATH"
            echo "✅ Ticket stapled."
        else
            # Staple the .app, then re-zip so the ticket travels with it.
            echo "📎 Stapling notarisation ticket to .app..."
            xcrun stapler staple "$APP_BUNDLE"
            xcrun stapler validate "$APP_BUNDLE"
            rm -f "$ZIP_PATH"
            (cd "$BUILD_DIR" && zip -qr -y "$APP_NAME-$VERSION.zip" "$APP_NAME.app")
            echo "✅ Ticket stapled. ZIP rebuilt: $ZIP_PATH"
        fi
    else
        echo "❌ Notarisation failed. Check logs with:"
        echo "   xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE"
        exit 1
    fi
elif [ "$DEVELOPER_ID_CERT" != "-" ]; then
    echo ""
    echo "ℹ️  App is Developer ID signed but NOT notarised."
    echo "   Recipients on macOS 10.15+ will see a Gatekeeper warning the first"
    echo "   time they open it (right-click → Open to bypass)."
    echo "   To enable notarisation: scripts/setup-signing.sh"
else
    echo ""
    echo "⚠️  This app is ad-hoc signed (no Apple Developer ID)."
    echo "   If macOS says it's damaged, the recipient should run:"
    echo "   xattr -cr /Applications/RemoteDiff.app"
fi
