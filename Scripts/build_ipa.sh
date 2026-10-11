#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 Scripts/generate_project.py
xcodebuild -project WianTribeKeyboard.xcodeproj -scheme WianTribeKeyboard \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
python3 Scripts/package_ipa.py
