#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product BarFold
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/BarFold.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/BarFold" "$APP/Contents/MacOS/BarFold"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swift scripts/make-icon.swift "$APP/Contents/Resources"
codesign --force --sign - --identifier cn.aichanning.BarFold "$APP"
codesign --verify --strict "$APP"
printf '%s\n' "$APP"
