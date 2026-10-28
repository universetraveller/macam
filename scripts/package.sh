#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# The default builds first. --no-build packages an already verified app without
# changing its files, so it can also be used after interactive UI verification.
case "${1:-}" in
    '') ./scripts/build.sh ;;
    --no-build) codesign --verify --strict .build/Macam.app ;;
    *) echo 'Usage: scripts/package.sh [--no-build]' >&2; exit 2 ;;
esac
package_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' .build/Macam.app/Contents/Info.plist)"
package_name="Macam-${package_version}-$(uname -m).zip"
ditto -c -k --sequesterRsrc --keepParent .build/Macam.app ".build/$package_name"
cp ".build/$package_name" .build/Macam.zip
(
    cd .build
    shasum -a 256 "$package_name" > "$package_name.sha256"
)
echo "Packaged .build/$package_name"
echo "Checksum .build/$package_name.sha256"
