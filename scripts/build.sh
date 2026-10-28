#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! xcode-select -p >/dev/null 2>&1; then
    echo 'Install Command Line Tools with: xcode-select --install' >&2
    exit 1
fi
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
if [ "${SDK_VERSION%%.*}" -lt 26 ]; then
    echo "Macam requires a macOS 26+ SDK; selected SDK is $SDK_VERSION. Update Command Line Tools." >&2
    exit 1
fi
BUILD="$PWD/.build"
APP="$BUILD/Macam.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD/module-cache"
export CLANG_MODULE_CACHE_PATH="$BUILD/module-cache"
xcrun clang -isysroot "$SDK" -mmacosx-version-min=14.2 -O2 -std=c11 -Wall -Wextra -Wno-unused-parameter \
    -c Sources/Realtime.c -o "$BUILD/Realtime.o"
xcrun swiftc -sdk "$SDK" -target "$(uname -m)-apple-macosx14.2" -swift-version 5 -O -g \
    -module-cache-path "$BUILD/module-cache" -import-objc-header Sources/Realtime.h \
    Sources/*.swift "$BUILD/Realtime.o" -framework AppKit -framework CoreAudio \
    -o "$APP/Contents/MacOS/Macam"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/ReceiverTest.html Resources/ToneSource.html LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
codesign --force --timestamp=none --sign "${MACAM_SIGN_IDENTITY:--}" --identifier org.macam.Macam "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
