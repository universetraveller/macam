#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
xcrun clang -std=c11 -Wall -Wextra -Wno-unused-parameter -fsanitize=address,undefined -g \
    -I Sources Sources/Realtime.c Tests/RealtimeTests.c -framework CoreAudio -o .build/realtime-tests
.build/realtime-tests
./scripts/build.sh
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path .build/module-cache \
    -import-objc-header Sources/Realtime.h Sources/Audio.swift Sources/Processes.swift Sources/Ownership.swift \
    Tests/SelectionTests.swift .build/Realtime.o -framework AppKit -framework CoreAudio -o .build/selection-tests
.build/selection-tests
.build/Macam.app/Contents/MacOS/Macam --help >/dev/null
if .build/Macam.app/Contents/MacOS/Macam --probe nan 2>/dev/null; then
    echo 'Invalid diagnostic duration was accepted' >&2; exit 1
fi
plutil -lint .build/Macam.app/Contents/Info.plist
if command -v node >/dev/null 2>&1; then
    node Tests/BrowserPageTests.cjs chromium
    node Tests/BrowserPageTests.cjs safari
    node Tests/ToneSourceTests.cjs
else
    echo 'Node is unavailable; mocked browser-page logic tests skipped.'
fi
