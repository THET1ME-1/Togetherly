#!/usr/bin/env bash
# Собирает LoveWidget.swift под macOS с заглушками и рисует раскладку.
# Только macOS: SwiftUI на Linux нет. В CI гоняется ios-widget-layout.yml.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$root/build/widget_layout"
mkdir -p "$out"

# Файл виджета берётся как есть, меняется только импорт UIKit.
sed 's/^import UIKit$/import AppKit/' "$root/ios/TogetherlyWidget/LoveWidget.swift" \
  > "$out/LoveWidget.swift"

swiftc -swift-version 5 \
  "$out/LoveWidget.swift" \
  "$root/tool/widget_layout/Shims.swift" \
  "$root/tool/widget_layout/main.swift" \
  -o "$out/probe"

"$out/probe" "$out"
