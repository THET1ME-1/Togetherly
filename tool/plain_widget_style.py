#!/usr/bin/env python3
"""Отключает по одной стилевой конструкции виджетов iPhone — для деления пополам.

Зачем. Виджеты пропали из галереи начиная со сборки 1.25.1 (118); 1.25.0 (117)
показывает их. Между сборками один коммит по расширению — 3cbb20d3, и он ввёл
четыре модификатора: фон карточки через `ViewModifier` с
`@Environment(\\.widgetRenderingMode)`, плашки `tgBlock`/`tgGradientBlock` под
`@available(iOS 16)` и `tgFullColorImage` с `widgetAccentedRenderingMode`
(iOS 18). Каждый оставляет в типе виджета ветку условной доступности.

Симулятор эту поломку не воспроизводит: прогон на 1.25.0 и на 1.25.1 дал
одинаковый приговор, хотя на телефоне первая показывает виджеты, а вторая нет.
Значит делить приходится сборками в TestFlight.

Скрипт переписывает секцию стилей целиком из шаблонов, а вызовы в двадцати двух
виджетах не трогает: две сборки отличаются ровно одной конструкцией.

Запуск: python3 tool/plain_widget_style.py image|block|container|all
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "ios" / "TogetherlyWidget"
THEME = ROOT / "WidgetTheme.swift"
BUNDLE = ROOT / "TogetherlyWidgetBundle.swift"
TIMER = ROOT / "TimerWidgets.swift"

SECTION_START = "extension View {"
SECTION_END = "// MARK: - Мелочи вёрстки"

CONTAINER_TINTED = '''    /// Сплошная заливка под виджет: на iOS 17+ только через
    /// `containerBackground`, иначе система обрезает виджет по своим полям.
    /// В тонированном режиме фон отдаём системе — своя заливка съедает текст.
    @ViewBuilder
    func tgContainerBackground(_ color: Color) -> some View {
        if #available(iOS 17.0, *) {
            self.modifier(TgContainerBackground(color: color))
        } else {
            ZStack {
                color
                self
            }
        }
    }
'''

CONTAINER_PLAIN = '''    /// ОТКЛЮЧЕНО проверкой: фон как в 1.25.0, без опроса режима отрисовки.
    @ViewBuilder
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

BLOCK_TINTED = '''    /// Приподнятая плашка внутри виджета (числа, чипы, ячейки).
    /// В тонированном режиме от неё остаётся только контур.
    @ViewBuilder
    func tgBlock(_ color: Color, radius: CGFloat) -> some View {
        if #available(iOS 16.0, *) {
            self.modifier(TgBlock(color: color, radius: radius))
        } else {
            self.background(
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(color)
            )
        }
    }

    /// То же для градиентной плашки.
    @ViewBuilder
    func tgGradientBlock(colors: [Color], radius: CGFloat) -> some View {
        if #available(iOS 16.0, *) {
            self.modifier(TgGradientBlock(colors: colors, radius: radius))
        } else {
            self.background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: colors,
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
            )
        }
    }
'''

BLOCK_PLAIN = '''    /// ОТКЛЮЧЕНО проверкой: плашки как в 1.25.0, безусловной заливкой.
    @ViewBuilder
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

IMAGE_TINTED = '''extension Image {
    /// Картинка остаётся цветной и в тонированном режиме — иначе фотография
    /// партнёра превращается в силуэт. Звать сразу после `resizable()`.
    @ViewBuilder
    func tgFullColorImage() -> some View {
        if #available(iOS 18.0, *) {
            self.widgetAccentedRenderingMode(.fullColor)
        } else {
            self
        }
    }
}
'''

IMAGE_PLAIN = '''extension Image {
    /// ОТКЛЮЧЕНО проверкой: ветки iOS 18 нет, картинка идёт как есть.
    func tgFullColorImage() -> Image { self }
}
'''

MODIFIER_CONTAINER = '''
@available(iOS 17.0, *)
private struct TgContainerBackground: ViewModifier {
    @Environment(\\.widgetRenderingMode) private var mode
    let color: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if mode == .fullColor {
            content.containerBackground(color, for: .widget)
        } else {
            content.containerBackground(.clear, for: .widget)
        }
    }
}
'''

MODIFIER_BLOCK = '''
@available(iOS 16.0, *)
private struct TgGradientBlock: ViewModifier {
    @Environment(\\.widgetRenderingMode) private var mode
    let colors: [Color]
    let radius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if mode == .fullColor {
            content.background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: colors,
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
            )
        } else {
            content.background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
        }
    }
}

@available(iOS 16.0, *)
private struct TgBlock: ViewModifier {
    @Environment(\\.widgetRenderingMode) private var mode
    let color: Color
    let radius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if mode == .fullColor {
            content.background(
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(color)
            )
        } else {
            content.background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
        }
    }
}
'''


def build_section(off: set) -> str:
    parts = [SECTION_START, "\n"]
    parts.append(CONTAINER_PLAIN if "container" in off else CONTAINER_TINTED)
    parts.append("\n")
    parts.append(BLOCK_PLAIN if "block" in off else BLOCK_TINTED)
    parts.append("}\n\n")
    parts.append(IMAGE_PLAIN if "image" in off else IMAGE_TINTED)
    if "container" not in off:
        parts.append(MODIFIER_CONTAINER)
    if "block" not in off:
        parts.append(MODIFIER_BLOCK)
    parts.append("\n")
    return "".join(parts)


def main() -> None:
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    off = {"image", "block", "container"} if what == "all" else {what}
    if not off <= {"image", "block", "container"}:
        sys.exit("не знаю режим " + what)

    theme = THEME.read_text()
    i = theme.index(SECTION_START)
    j = theme.index(SECTION_END)
    THEME.write_text(theme[:i] + build_section(off) + theme[j:])

    if "container" in off:
        bundle = BUNDLE.read_text().replace(
            "self.modifier(TgWidgetCardBackground(gradient: gradient))",
            "self.containerBackground(for: .widget) { gradient }")
        k = bundle.find("@available(iOS 17.0, *)\nprivate struct TgWidgetCardBackground")
        if k > 0:
            bundle = bundle[:k].rstrip() + "\n"
        BUNDLE.write_text(bundle)

        timer = TIMER.read_text().replace(
            ".modifier(TgCardBackground(gradient: gradient))",
            ".containerBackground(gradient, for: .widget)")
        k = timer.find("@available(iOS 17.0, *)\nprivate struct TgCardBackground")
        if k > 0:
            end = timer.index("\n}\n", k) + 3
            timer = timer[:k].rstrip() + "\n" + timer[end:]
        TIMER.write_text(timer)

    print("отключено:", ", ".join(sorted(off)))


if __name__ == "__main__":
    main()
