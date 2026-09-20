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

# «Кольцо года»: собирается настоящий YearWidgets.swift с теми же заглушками.
# Верхнеуровневый код Swift пускает только в файле с именем main.swift.
mkdir -p "$out/year"
sed 's/^import UIKit$/import AppKit/' "$root/ios/TogetherlyWidget/YearWidgets.swift" \
  > "$out/year/YearWidgets.swift"
cp "$root/tool/widget_layout/year_main.swift" "$out/year/main.swift"
swiftc -swift-version 5 \
  "$out/year/YearWidgets.swift" \
  "$root/tool/widget_layout/Shims.swift" \
  "$root/tool/widget_layout/YearShims.swift" \
  "$out/year/main.swift" \
  -o "$out/year_probe" -module-name YearProbe

"$out/year_probe" "$out"

# «Вместе»: настоящий TogetherWidget.swift с теми же заглушками. Иначе Swift
# расширения проверяет только релизный прогон, и опечатка всплывает на выпуске.
mkdir -p "$out/together"
sed 's/^import UIKit$/import AppKit/; s/UIImage/NSImage/g' \
  "$root/ios/TogetherlyWidget/TogetherWidget.swift" > "$out/together/TogetherWidget.swift"
cp "$root/tool/widget_layout/together_main.swift" "$out/together/main.swift"
swiftc -swift-version 5 \
  "$out/together/TogetherWidget.swift" \
  "$root/tool/widget_layout/Shims.swift" \
  "$root/tool/widget_layout/TogetherShims.swift" \
  "$out/together/main.swift" \
  -o "$out/together_probe" -module-name TogetherProbe

"$out/together_probe" "$out"
