// Заглушки для сборки YearWidgets.swift на macOS: палитра темы задаётся
// прогоном, остальное повторяет соседние файлы расширения.

import SwiftUI

struct WidgetTheme {
    nonisolated(unsafe) static var current: [String: Color] = [:]

    private func c(_ role: String) -> Color { WidgetTheme.current[role] ?? .gray }

    var primary: Color { c("primary") }
    var onPrimary: Color { c("onPrimary") }
    var tertiaryContainer: Color { c("tertiaryContainer") }
    var surface: Color { c("surface") }
    var surfaceContainer: Color { c("surface") }
    var onSurface: Color { c("onSurface") }
    var onSurfaceVariant: Color { c("onSurface") }
    var trackOnSurface: Color { c("surface") }
}

struct TgEmptyView: View {
    let text: String
    let theme: WidgetTheme
    var body: some View { Text(text) }
}

func daysWord(_ n: Int) -> String {
    let a = n % 100
    let b = n % 10
    if (11...19).contains(a) { return "дней" }
    if b == 1 { return "день" }
    if (2...4).contains(b) { return "дня" }
    return "дней"
}
