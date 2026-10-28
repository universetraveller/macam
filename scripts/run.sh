#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -x .build/Macam.app/Contents/MacOS/Macam ]; then ./scripts/build.sh; fi
open .build/Macam.app
