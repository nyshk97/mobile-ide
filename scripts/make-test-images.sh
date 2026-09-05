#!/bin/bash
# 画像添付（#8）の検証用テスト画像を /tmp（または $1）に生成する。中身は scripts/make-test-images.swift
set -e
DIR="${1:-/tmp}"
cd "$(dirname "$0")/.."
swift scripts/make-test-images.swift "$DIR"
sips -g pixelWidth -g pixelHeight "$DIR/mobile-ide-test.jpg" "$DIR/mobile-ide-test.png" | grep -E "^/|pixel"
