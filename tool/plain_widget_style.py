#!/usr/bin/env python3
"""Отключает по одной стилевой конструкции виджетов iPhone — для деления пополам.

Зачем. Виджеты пропали из галереи начиная со сборки 1.25.1 (118); 1.25.0 (117)
показывает их. Между сборками один коммит по расширению — 3cbb20d3, и он ввёл
четыре модификатора: фон карточки через `ViewModifier` с
`@Environment(\\.widgetRenderingMode)`, плашки `tgBlock`/`tgGradientBlock` под
`@available(iOS 16)` и `tgFullColorImage` с `widgetAccentedRenderingMode`
(iOS 18). Каждый оставляет в типе виджета ветку условной доступности — ровно
та форма, которая уже роняла расширение в бандле.

Скрипт правит РЕАЛИЗАЦИЮ модификатора, а вызовы в виджетах не трогает: тогда
две сборки отличаются одной конструкцией, и виноватую видно сразу.

Запуск: python3 tool/plain_widget_style.py image|block|container|all
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "ios" / "TogetherlyWidget"
THEME = ROOT / "WidgetTheme.swift"
BUNDLE = ROOT / "TogetherlyWidgetBundle.swift"
TIMER = ROOT / "TimerWidgets.swift"

# Картинка: убираем iOS-18-only ветку целиком, картинка остаётся как есть.
IMAGE_PLAIN = '''extension Image {
    /// ОТКЛЮЧЕНО проверкой: ветка iOS 18 убрана, картинка идёт как есть.
    func tgFullColorImage() -> Image { self }
}'''

# Плашки: безусловная заливка, как было до 13 августа.
BLOCK_PLAIN = '''    @ViewBuilder
    func tgBlock(_ color: Color, radius: CGFloat) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(color)
        )
    }

    @ViewBuilder
    func tgGradientBlock(colors: [Color], radius: CGFloat) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: colors,
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
        )
    }
'''

# Фон карточки: прямой containerBackground под одиночным #available, как в 1.25.0.
CONTAINER_PLAIN = '''    @ViewBuilder
    func tgContainerBackground(_ color: Color) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(color, for: .widget)
        } else {
            ZStack {
                color
                self
            }
        }
    }
'''


def cut(text: str, start: str, end: str) -> tuple[str, str]:
    """Возвращает (кусок, текст без куска). Границы ищутся буквально."""
    i = text.index(start)
    j = text.index(end, i) + len(end)
    return text[i:j], text[:i] + text[j:]


def strip_image(theme: str) -> str:
    piece, rest = cut(theme, "extension Image {", "\n}")
    return rest.replace("// MARK: - Мелочи вёрстки",
                        IMAGE_PLAIN + "\n\n// MARK: - Мелочи вёрстки", 1)


def strip_block(theme: str) -> str:
    # Реализации-обёртки и сами типы модификаторов.
    _, theme = cut(theme, "    /// Приподнятая плашка внутри виджета",
                   "    }\n\n}")
    theme = theme.replace("extension Image {", BLOCK_PLAIN + "\n}\n\nextension Image {", 1)
    for name in ("TgBlock", "TgGradientBlock"):
        marker = f"@available(iOS 16.0, *)\nprivate struct {name}: ViewModifier {{"
        if marker in theme:
            _, theme = cut(theme, marker, "\n}")
    return theme


def strip_container(theme: str, bundle: str, timer: str) -> tuple[str, str, str]:
    _, theme = cut(theme, "    @ViewBuilder\n    func tgContainerBackground",
                   "        }\n    }")
    theme = theme.replace("    /// Приподнятая плашка внутри виджета",
                          CONTAINER_PLAIN + "\n    /// Приподнятая плашка внутри виджета", 1)
    marker = "@available(iOS 17.0, *)\nprivate struct TgContainerBackground: ViewModifier {"
    if marker in theme:
        _, theme = cut(theme, marker, "\n}")

    bundle = bundle.replace("self.modifier(TgWidgetCardBackground(gradient: gradient))",
                            "self.containerBackground(for: .widget) { gradient }")
    marker = "@available(iOS 17.0, *)\nprivate struct TgWidgetCardBackground: ViewModifier {"
    if marker in bundle:
        _, bundle = cut(bundle, marker, "\n}")

    timer = timer.replace(".modifier(TgCardBackground(gradient: gradient))",
                          ".containerBackground(gradient, for: .widget)")
    marker = "@available(iOS 17.0, *)\nprivate struct TgCardBackground: ViewModifier {"
    if marker in timer:
        _, timer = cut(timer, marker, "\n}")
    return theme, bundle, timer


def main() -> None:
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    theme, bundle, timer = THEME.read_text(), BUNDLE.read_text(), TIMER.read_text()

    if what in ("image", "all"):
        theme = strip_image(theme)
    if what in ("block", "all"):
        theme = strip_block(theme)
    if what in ("container", "all"):
        theme, bundle, timer = strip_container(theme, bundle, timer)

    THEME.write_text(theme)
    BUNDLE.write_text(bundle)
    TIMER.write_text(timer)

    left = len(re.findall(r"#available", theme + bundle + timer))
    print(f"отключено: {what}; веток #available в стилях осталось: {left}")


if __name__ == "__main__":
    main()
