#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "🔨 Building Clip for macOS..."

export CLANG_MODULE_CACHE_PATH="${DIR}/../.cache/clang"
export SWIFT_MODULE_CACHE_PATH="${DIR}/../.cache/swift"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFT_MODULE_CACHE_PATH"

swift build -c release --disable-sandbox

APP_NAME="Clip"
APP_BUNDLE="${DIR}/build/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "📦 Assembling ${APP_NAME}.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"

cp .build/release/Clip "${MACOS}/${APP_NAME}"
cp Sources/Clip/Resources/Info.plist "${CONTENTS}/Info.plist"

if [ -f "Sources/Clip/Resources/AppIcon.icns" ]; then
    cp Sources/Clip/Resources/AppIcon.icns "${RESOURCES}/AppIcon.icns"
fi

echo "🔏 Signing ${APP_NAME}.app with stable identifier..."
codesign --force --deep --sign - --identifier "com.clip.app" -r="designated => identifier \"com.clip.app\"" "$APP_BUNDLE"

echo "✅ Successfully built ${APP_BUNDLE}!"

if [ "$1" = "--install" ]; then
    DEST="${HOME}/Applications"
    mkdir -p "$DEST"
    echo "📲 Installing to ${DEST}/${APP_NAME}.app..."
    rm -rf "${DEST}/${APP_NAME}.app"
    cp -R "$APP_BUNDLE" "${DEST}/"
    echo "🎉 Installed to ${DEST}/${APP_NAME}.app!"
fi

if [ "$1" = "--run" ] || [ "$2" = "--run" ]; then
    echo "🚀 Launching ${APP_NAME}.app..."
    open "$APP_BUNDLE"
fi
