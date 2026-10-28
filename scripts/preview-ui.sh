#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path .build/module-cache \
    Sources/MenuViews.swift Tests/MenuPreview.swift -framework AppKit -o .build/menu-preview
.build/menu-preview .build/previews
