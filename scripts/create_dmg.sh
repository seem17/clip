#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

# Ensure the app is built
./scripts/build_app.sh

APP_NAME="Clip"
DMG_NAME="Clip.dmg"
STAGING_DIR="${DIR}/build/dmg_staging"
OUTPUT_DMG="${DIR}/build/${DMG_NAME}"

echo "📦 Creating DMG package..."
rm -rf "$STAGING_DIR" "$OUTPUT_DMG"
mkdir -p "$STAGING_DIR"

# Copy Clip.app
cp -R "${DIR}/build/${APP_NAME}.app" "$STAGING_DIR/"

# Create Applications symlink for drag-and-drop installation
ln -s /Applications "$STAGING_DIR/Applications"

echo "💿 Generating disk image: ${OUTPUT_DMG}..."
hdiutil create -volname "${APP_NAME}" -srcfolder "$STAGING_DIR" -ov -format UDZO "$OUTPUT_DMG"

rm -rf "$STAGING_DIR"
echo "✅ Done! DMG created at: ${OUTPUT_DMG}"
