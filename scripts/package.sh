#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Quit Macam first; packaging builds the same CLT-only app as local development.
./scripts/build.sh
package_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
package_name="Macam-${package_version}-$(uname -m).zip"
ditto -c -k --sequesterRsrc --keepParent .build/Macam.app ".build/$package_name"
cp ".build/$package_name" .build/Macam.zip
(
    cd .build
    shasum -a 256 "$package_name" > "$package_name.sha256"
)
echo "Packaged .build/$package_name"
echo "Checksum .build/$package_name.sha256"
