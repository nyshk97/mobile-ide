#!/usr/bin/env bash
# AppIcon.appiconset の icon-1024.png（light）と icon-1024-dark.png（dark）を生成する。
# iOS は 1024x1024 の単一サイズだけ入れれば Xcode が各サイズを作る。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT_SCRIPT="$ROOT/scripts/generate-app-icon.swift"
ICONSET="$ROOT/MobileIDE/Resources/Assets.xcassets/AppIcon.appiconset"

mkdir -p "$ICONSET"
echo "==> render icon-1024.png (light)"
swift "$SWIFT_SCRIPT" "$ICONSET/icon-1024.png" 1024 light
echo "==> render icon-1024-dark.png (dark)"
swift "$SWIFT_SCRIPT" "$ICONSET/icon-1024-dark.png" 1024 dark
echo "done: $ICONSET"
