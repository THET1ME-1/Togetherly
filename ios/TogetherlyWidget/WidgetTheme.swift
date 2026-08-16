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
    /// ОТКЛЮЧЕНО проверкой: фон как в 1.25.0, без опроса режима отрисовки.
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

    /// ОТКЛЮЧЕНО проверкой: плашки как в 1.25.0, безусловной заливкой.
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
}

extension Image {
    /// ОТКЛЮЧЕНО проверкой: ветки iOS 18 нет, картинка идёт как есть.
    func tgFullColorImage() -> Image { self }
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
