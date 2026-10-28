#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! xcode-select -p >/dev/null 2>&1; then
    echo 'Install Command Line Tools with: xcode-select --install' >&2
    exit 1
fi
# Python ships with Command Line Tools; no pip dependencies are needed.
exec xcrun python3 scripts/release.py prepare "$@"
