#!/bin/bash
set -e

# RSS Reader Debug Build Script
# Builds for development/testing - NO stripping, NO DMG

echo "🔧 Building RSS Reader (debug mode)..."

# Configuration
APP_NAME="RSS Reader"
BUILD_DIR=".build/debug"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf "$APP_BUNDLE"

# Build debug binary (no optimizations, keeps symbols for debugging)
echo "🔨 Building debug binary..."
swift build

# Create app bundle structure
echo "📦 Creating app bundle..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable (NO stripping for debug)
echo "📋 Copying executable..."
cp "$BUILD_DIR/RSSReader" "$MACOS_DIR/RSSReader"

# Copy resources
echo "🎨 Copying resources..."
cp Info.plist "$CONTENTS_DIR/Info.plist"
cp Sources/Resources/AppIcon.icns "$RESOURCES_DIR/AppIcon.icns"
if [ -f "Sources/Resources/Localizable.xcstrings" ]; then
    cp Sources/Resources/Localizable.xcstrings "$RESOURCES_DIR/"
fi

# Create PkgInfo
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

# Sign the app
echo "✍️  Signing app..."
codesign --force --deep --sign - --entitlements RSSReader.entitlements "$APP_BUNDLE" 2>/dev/null

echo ""
echo "✨ Debug build complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "App Bundle: $APP_BUNDLE"
echo "Mode: Debug (symbols included, not stripped)"
echo ""
echo "To run: open '$APP_BUNDLE'"
echo "To build for release: ./scripts/build-release.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
