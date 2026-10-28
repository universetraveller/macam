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
source_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
if [ "$package_version" != "$source_version" ]; then
    echo 'App/source versions differ. Rebuild before packaging.' >&2
    exit 1
fi
package_arch="$(lipo -archs .build/Macam.app/Contents/MacOS/Macam)"
case "$package_arch" in
    arm64|x86_64) ;;
    *) echo "Unsupported release architecture: $package_arch" >&2; exit 1 ;;
esac
package_name="Macam-${package_version}-${package_arch}.zip"
ditto -c -k --sequesterRsrc --keepParent .build/Macam.app ".build/$package_name"
cp ".build/$package_name" .build/Macam.zip
(
    cd .build
    shasum -a 256 "$package_name" > "$package_name.sha256"
)
echo "Packaged .build/$package_name"
echo "Checksum .build/$package_name.sha256"
