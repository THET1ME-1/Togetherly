import SwiftUI
import UIKit
import WidgetKit

// MARK: - Палитра активной темы приложения
//
// Цвета кладёт `lib/services/widget_theme_sync.dart` строками «#RRGGBB» под
// ключами `wtheme_<роль>`. Тем в приложении два десятка, и хардкод палитры (как
// в первых виджетах, см. `Palette`) означал бы, что виджет живёт своей жизнью:
// человек сменил тему, а на рабочем столе прежний цвет.
//
// Плагин `home_widget` пишет в тот же контейнер App Group, что читает `Store`,
// поэтому на iOS роли доступны без единой строчки нового Dart-кода.

struct WidgetTheme {
    private let s = Store()

    /// Роль темы; пусто или мусор в значении → [fallback].
    func color(_ role: String, _ fallback: Color) -> Color {
        Color(css: s.string("wtheme_\(role)"), fallback: fallback)
    }

    var isDark: Bool { s.string("wtheme_dark") == "1" }

    // Заливки
    var primary: Color { color("primary", Color(hex: 0x9B86BD)) }
    var primaryContainer: Color { color("primaryContainer", Color(hex: 0xE9DDFF)) }
    var surface: Color { color("surface", Color(hex: 0xFFF7FA)) }
    var surfaceContainer: Color { color("surfaceContainer", Color(hex: 0xF3EBF3)) }
    var tertiaryContainer: Color { color("tertiaryContainer", Color(hex: 0xFFD9E2)) }
    var secondaryContainer: Color { color("secondaryContainer", Color(hex: 0xE8DEF8)) }

    // Текст и иконки
    var onPrimary: Color { color("onPrimary", .white) }
    var onPrimarySoft: Color { color("onPrimarySoft", Color(hex: 0xF0E6FF)) }
    var onPrimaryContainer: Color { color("onPrimaryContainer", Color(hex: 0x24005A)) }
    var onContainerSoft: Color { color("onContainerSoft", Color(hex: 0x5A4A73)) }
    var onSurface: Color { color("onSurface", Color(hex: 0x1D1B20)) }
    var onSurfaceVariant: Color { color("onSurfaceVariant", Color(hex: 0x625B71)) }
    var onTertiaryContainer: Color { color("onTertiaryContainer", Color(hex: 0x3E001D)) }
    var outline: Color { color("outline", Color(hex: 0x7A757F)) }

    // Служебные роли: трек прогресса и приподнятый блок на заливке primary.
    var accentOnPrimary: Color { color("accentOnPrimary", Color(hex: 0xD0BCFF)) }
    var trackOnContainer: Color { color("trackOnContainer", Color(hex: 0xCFC0E8)) }
    var trackOnSurface: Color { color("trackOnSurface", Color(hex: 0xE6DCEF)) }
    var blockOnPrimary: Color { color("blockOnPrimary", Color(hex: 0xA795C4)) }

    // Кружки аватаров, когда фотографии нет.
    var avatarMine: Color { color("avatarMine", Color(hex: 0xD0BCFF)) }
    var avatarPartner: Color { color("avatarPartner", Color(hex: 0xFFD9E2)) }
}

// MARK: - Фон карточки

extension View {
    /// Сплошная заливка под виджет нового каталога.
    ///
    /// На iOS 17+ фон обязан идти через `containerBackground`, иначе система
    /// обрезает виджет по своим полям и заливка не доходит до краёв.
    ///
    /// В тонированном режиме («Прозрачные» и «Однотонные» в настройке экрана
    /// «Домой») система красит ВСЁ содержимое одним цветом по своей подложке.
    /// Наша заливка там становится сплошным пятном поверх текста: у тестера
    /// виджеты выглядели белыми формами без единой цифры. Поэтому в этих
    /// режимах фон не рисуем вовсе — подложку даёт система.
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

    /// Приподнятая плашка внутри виджета (числа, чипы, ячейки).
    ///
    /// В тонированном режиме заливка съедает свой же текст, поэтому от плашки
    /// остаётся только контур.
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

}

/// Сплошная подложка ВНУТРИ виджета: панель, полоска-разделитель, пустое
/// состояние. Кладётся слоем в `ZStack`, а не модификатором.
///
/// В тонированном режиме («Тонированный» в настройке экрана «Домой») система
/// НЕ показывает наши цвета вовсе: всё, что не помечено `widgetAccentable`,
/// становится белым с сохранением альфы. Непрозрачная заливка превращается в
/// белый прямоугольник во весь виджет, а текст поверх — в такой же белый, и
/// виджет читается как пустая форма. Ровно это было на снимках 19.08.2026.
/// Поэтому подложку там не рисуем: фон даёт система, содержимое остаётся
/// поверх обоев.
struct TgSurface: View {
    @Environment(\.widgetRenderingMode) private var mode
    let color: Color

    init(_ color: Color) { self.color = color }

    var body: some View {
        if mode == .fullColor {
            color
        } else {
            Color.clear
        }
    }
}

/// То же для градиентной подложки.
struct TgGradientSurface: View {
    @Environment(\.widgetRenderingMode) private var mode
    let colors: [Color]
    var startPoint: UnitPoint = .topLeading
    var endPoint: UnitPoint = .bottomTrailing

    var body: some View {
        if mode == .fullColor {
            LinearGradient(colors: colors, startPoint: startPoint, endPoint: endPoint)
        } else {
            Color.clear
        }
    }
}

extension Image {
    /// Картинка остаётся цветной и в тонированном режиме — иначе фотография
    /// партнёра превращается в силуэт. Модификатор объявлен на `Image`, потому
    /// звать его надо сразу после `resizable()`, до `frame`/`clipped`.
    @ViewBuilder
    func tgFullColorImage() -> some View {
        if #available(iOS 18.0, *) {
            self.widgetAccentedRenderingMode(.fullColor)
        } else {
            self
        }
    }
}

@available(iOS 17.0, *)
private struct TgContainerBackground: ViewModifier {
    @Environment(\.widgetRenderingMode) private var mode
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

@available(iOS 16.0, *)
private struct TgGradientBlock: ViewModifier {
    @Environment(\.widgetRenderingMode) private var mode
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
    @Environment(\.widgetRenderingMode) private var mode
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

// MARK: - Мелочи вёрстки

/// Кружок аватара: фотография, а без неё — буква на тональной подложке.
struct TgAvatar: View {
    let image: UIImage?
    let initial: String
    let background: Color
    let foreground: Color
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .tgFullColorImage()
                    .scaledToFill()
            } else {
                ZStack {
                    background
                    Text(initial.isEmpty ? "?" : String(initial.prefix(1)))
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundColor(foreground)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// Полоска прогресса со скруглёнными концами.
struct TgProgressBar: View {
    let value: Double
    let track: Color
    let fill: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(fill)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}
