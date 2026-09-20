// Заглушки для сборки TogetherWidget.swift на macOS.
//
// Палитру задаёт прогон, аватарка рисуется кружком с буквой — настоящую в
// стенде взять неоткуда, а раскладку проверяет именно её габарит.

import SwiftUI

struct WidgetTheme {
    nonisolated(unsafe) static var current: [String: Color] = [:]

    // Палитра запоминается при создании: сетка рисуется после цикла по темам,
    // и чтение в момент отрисовки дало бы всем последнюю тему.
    private let palette = WidgetTheme.current

    private func c(_ role: String) -> Color { palette[role] ?? .gray }

    var primary: Color { c("primary") }
    var onPrimary: Color { c("onPrimary") }
    var onPrimarySoft: Color { c("onPrimarySoft") }
    var onPrimaryContainer: Color { c("onPrimaryContainer") }
    var blockOnPrimary: Color { c("blockOnPrimary") }
    var surface: Color { c("surface") }
    var surfaceContainer: Color { c("surface") }
    var onSurface: Color { c("onSurface") }
    var onSurfaceVariant: Color { c("onSurfaceVariant") }
    var outline: Color { c("outline") }
    var trackOnSurface: Color { c("trackOnSurface") }
    var tertiary: Color { c("tertiary") }
    var tertiaryContainer: Color { c("tertiaryContainer") }
    var onTertiaryContainer: Color { c("onTertiaryContainer") }
    var avatarMine: Color { c("avatarMine") }
    var avatarPartner: Color { c("avatarPartner") }
    var accentOnPrimary: Color { c("onPrimarySoft") }
}

enum WidgetImage {
    static let avatar: CGFloat = 200
}

func daysSince(startMs: Int) -> Int {
    max(0, (nowMs - startMs) / 86_400_000)
}

struct TgAvatar: View {
    let image: NSImage?
    let initial: String
    let background: Color
    let foreground: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(background)
            Text(initial)
                .font(.system(size: size * 0.42, weight: .heavy))
                .foregroundColor(foreground)
        }
        .frame(width: size, height: size)
    }
}

extension View {
    func widgetAccentable(_ accentable: Bool = true) -> some View { self }
    func tgBlock(_ color: Color, radius: CGFloat) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(color))
    }
}
