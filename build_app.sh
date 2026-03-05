#!/bin/bash

set -e

APP_NAME="Metal"
APP_DIR="zig-out/bin/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE="metal"

# Build the executable first
echo "Building metal executable..."
zig build -Doptimize=ReleaseFast

# Create bundle directories
echo "Creating app bundle structure at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp "zig-out/bin/$EXECUTABLE" "$MACOS_DIR/"

# Copy Info.plist
cp Info.plist "$CONTENTS_DIR/"

echo "App bundle created successfully."
echo "You can now run it from Finder or with: open $APP_DIR"
