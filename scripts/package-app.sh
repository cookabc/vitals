#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project Vitals.xcodeproj -scheme Vitals -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData build
mkdir -p dist
stage="$(mktemp -d "$PWD/dist/.package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto .build/DerivedData/Build/Products/Release/Vitals.app "$stage/Vitals.app"
codesign --verify --deep --strict "$stage/Vitals.app"
if [[ -e dist/Vitals.app ]]; then mv dist/Vitals.app "$stage/previous.app"; fi
if ! mv "$stage/Vitals.app" dist/Vitals.app; then
    if [[ -e "$stage/previous.app" ]]; then mv "$stage/previous.app" dist/Vitals.app; fi
    exit 1
fi
printf 'Built %s/dist/Vitals.app (local build)\n' "$PWD"
