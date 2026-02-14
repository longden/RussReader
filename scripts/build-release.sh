#!/bin/bash
set -e

# RussReader Build Script
# Builds a production-ready .app bundle for local distribution

# Change to project root (parent of scripts directory)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

echo "🚀 Building RussReader for production..."

# Configuration
APP_NAME="RussReader"
BUNDLE_ID="com.russreader.menubar"
VERSION="1.0.0"
BUILD_DIR=".build/release"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf "$APP_BUNDLE"

# Build release binary
echo "🔨 Building release binary..."
swift build -c release \
    -Xswiftc -enforce-exclusivity=checked \
    -Xswiftc -O

# Create app bundle structure
echo "📦 Creating app bundle..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
echo "📋 Copying executable..."
cp "$BUILD_DIR/RussReader" "$MACOS_DIR/RussReader"

# Strip symbols for better obfuscation
echo "🔒 Stripping debug symbols..."
strip -x "$MACOS_DIR/RussReader"

# Copy resources
echo "🎨 Copying resources..."
cp Info.plist "$CONTENTS_DIR/Info.plist"
cp Sources/Resources/AppIcon.icns "$RESOURCES_DIR/AppIcon.icns"
if [ -f "Sources/Resources/Localizable.xcstrings" ]; then
    cp Sources/Resources/Localizable.xcstrings "$RESOURCES_DIR/"
fi

# Create PkgInfo
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

# Sign the app (ad-hoc signature for local distribution)
echo "✍️  Signing app..."
codesign --force --deep --sign - --entitlements RussReader.entitlements "$APP_BUNDLE"

# Verify the app
echo "✅ Verifying app bundle..."
if [ -x "$MACOS_DIR/RussReader" ]; then
    echo "✓ Executable is valid"
else
    echo "✗ Executable is not valid"
    exit 1
fi

if [ -f "$RESOURCES_DIR/AppIcon.icns" ]; then
    echo "✓ Icon is present"
else
    echo "✗ Icon is missing"
    exit 1
fi

# Display bundle info
ORIGINAL_SIZE=$(stat -f%z "$BUILD_DIR/RussReader" 2>/dev/null || echo "0")
STRIPPED_SIZE=$(stat -f%z "$MACOS_DIR/RussReader" 2>/dev/null || echo "0")

echo ""
echo "✨ Build complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "App Bundle: $APP_BUNDLE"
echo "Version: $VERSION"
echo "Bundle ID: $BUNDLE_ID"
if [ "$ORIGINAL_SIZE" != "0" ] && [ "$STRIPPED_SIZE" != "0" ]; then
    SAVED=$((ORIGINAL_SIZE - STRIPPED_SIZE))
    echo "Size: $(numfmt --to=iec $STRIPPED_SIZE 2>/dev/null || echo "$STRIPPED_SIZE bytes")"
    echo "Symbols stripped: $(numfmt --to=iec $SAVED 2>/dev/null || echo "$SAVED bytes") removed"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create DMG
DMG_NAME="RussReader-$VERSION.dmg"
TEMP_DMG="RussReader-temp.dmg"
VOLUME_NAME="RussReader $VERSION"

echo "💿 Creating distributable DMG..."
rm -f "$BUILD_DIR/$DMG_NAME" 2>/dev/null
rm -f "$BUILD_DIR/$TEMP_DMG" 2>/dev/null

hdiutil create -srcfolder "$APP_BUNDLE" -volname "$VOLUME_NAME" \
    -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW \
    "$BUILD_DIR/$TEMP_DMG" -quiet

MOUNT_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$BUILD_DIR/$TEMP_DMG")
MOUNT_DIR=$(echo "$MOUNT_OUTPUT" | grep -o '/Volumes/.*')

if [ -n "$MOUNT_DIR" ]; then
    echo "🔗 Adding Applications link..."
    ln -s /Applications "$MOUNT_DIR/Applications"
    hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach "$MOUNT_DIR" -force -quiet
fi

echo "🗜️  Compressing..."
hdiutil convert "$BUILD_DIR/$TEMP_DMG" -format UDZO -o "$BUILD_DIR/$DMG_NAME" -quiet
rm -f "$BUILD_DIR/$TEMP_DMG"

DMG_SIZE=$(du -h "$BUILD_DIR/$DMG_NAME" | cut -f1)

echo ""
echo "✨ Release build complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 App Bundle: $APP_BUNDLE"
echo "💿 DMG File: $BUILD_DIR/$DMG_NAME ($DMG_SIZE)"
echo "🔒 Code: Stripped & Obfuscated"
echo ""
echo "Ready to distribute! Share the DMG file."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
