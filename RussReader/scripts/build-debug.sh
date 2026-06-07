#!/bin/bash
set -e

# RussReader Debug Build Script
# Builds for development/testing - NO stripping, NO DMG

# Change to project root (parent of scripts directory)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

echo "🔧 Building RussReader (debug mode)..."

# Configuration
APP_NAME="RussReader"
BUILD_DIR=".build/debug"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
XCODE_PROJECT="../RussReader.xcodeproj"

# Clean previous builds
echo "🧹 Cleaning previous builds..."

if [ -f "Package.swift" ]; then
    rm -rf "$APP_BUNDLE"
    mkdir -p "$BUILD_DIR"

    # Build debug binary (no optimizations, keeps symbols for debugging)
    echo "🔨 Building debug binary..."
    swift build

    # Create app bundle structure
    echo "📦 Creating app bundle..."
    mkdir -p "$MACOS_DIR"
    mkdir -p "$RESOURCES_DIR"

    # Copy executable (NO stripping for debug)
    echo "📋 Copying executable..."
    cp "$BUILD_DIR/RussReader" "$MACOS_DIR/RussReader"

    # Copy resources
    echo "🎨 Copying resources..."
    cp Info.plist "$CONTENTS_DIR/Info.plist"
    cp Sources/Resources/AppIcon.icns "$RESOURCES_DIR/AppIcon.icns"
    if [ -f "Sources/Resources/Localizable.xcstrings" ]; then
        cp Sources/Resources/Localizable.xcstrings "$RESOURCES_DIR/"
    fi

    # Create PkgInfo
    echo "APPL????" > "$CONTENTS_DIR/PkgInfo"
elif [ -f "$XCODE_PROJECT/project.pbxproj" ]; then
    rm -rf "$BUILD_DIR"

    if ! xcodebuild -version >/dev/null 2>&1; then
        echo "❌ xcodebuild is unavailable. Install/select full Xcode before building."
        exit 1
    fi
    DERIVED_DATA_DIR="${TMPDIR:-/tmp}/RussReader-DerivedData-debug"
    echo "🔨 Building debug app with Xcode project..."
    rm -rf "$DERIVED_DATA_DIR"
    xcodebuild -project "$XCODE_PROJECT" -scheme "$APP_NAME" -resolvePackageDependencies -derivedDataPath "$DERIVED_DATA_DIR" -quiet
    xcodebuild -project "$XCODE_PROJECT" -scheme "$APP_NAME" -configuration Debug -derivedDataPath "$DERIVED_DATA_DIR" -quiet
    XCODE_APP="$DERIVED_DATA_DIR/Build/Products/Debug/$APP_NAME.app"
    if [ ! -d "$XCODE_APP" ]; then
        echo "❌ Build succeeded but app bundle was not found at $XCODE_APP"
        exit 1
    fi
    mkdir -p "$BUILD_DIR"
    cp -R "$XCODE_APP" "$APP_BUNDLE"
else
    echo "❌ No Package.swift or Xcode project found to build from."
    exit 1
fi

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
