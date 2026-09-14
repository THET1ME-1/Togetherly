// Заглушки для сборки LoveWidget.swift на macOS.
//
// Расширение виджетов живёт на UIKit и читает App Group, а раскладку SwiftUI
// одинаково считает и iOS, и macOS. Поэтому файл виджета берётся КАК ЕСТЬ
// (меняется только `import UIKit`), а всё, что он зовёт из соседних файлов,
// подменено здесь: картинки рисуются сплошной заливкой нужной пропорции,
// ключи отдаются из подготовленного набора.

import AppKit
import SwiftUI
import WidgetKit

typealias UIImage = NSImage

extension Image {
    init(uiImage: NSImage) { self.init(nsImage: uiImage) }

    func tgFullColorImage() -> some View { self }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension View {
    func tgContainerBackground(_ color: Color) -> some View { background(color) }
}

struct TgSurface: View {
    let color: Color
    init(_ color: Color) { self.color = color }
    var body: some View { color }
}

struct TgGradientSurface: View {
    let colors: [Color]
    var startPoint: UnitPoint = .topLeading
    var endPoint: UnitPoint = .bottomTrailing
    var body: some View {
        LinearGradient(colors: colors, startPoint: startPoint, endPoint: endPoint)
    }
}

/// Сплошная картинка заданной пропорции: левое фото красное, правое синее —
/// по цвету столбца потом видно, чья это половина.
func solidImage(width: CGFloat, height: CGFloat, color: NSColor) -> NSImage {
    NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
        color.setFill()
        rect.fill()
        return true
    }
}

struct Store {
    /// Набор ключей текущего прогона.
    nonisolated(unsafe) static var strings: [String: String] = [:]
    nonisolated(unsafe) static var images: [String: NSImage] = [:]

    func string(_ key: String, _ fallback: String = "") -> String {
        Store.strings[key] ?? fallback
    }

    func uiImage(_ key: String, maxSide: CGFloat = 700) -> NSImage? {
        Store.images[key]
    }

    func latestGroup(_ pointerKey: String) -> String {
        let g = string(pointerKey)
        return g.isEmpty ? "solo" : g
    }
}

enum WidgetRenderLog {
    static func availableMemoryMB() -> Int { 0 }
    static func familyName(_ family: WidgetFamily) -> String { "medium" }
    static func write(family: String, widget: String, fields: [String: String]) {}
}

struct SimpleEntry: TimelineEntry {
    let date: Date
}

struct RefreshProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry { SimpleEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [SimpleEntry(date: Date())], policy: .never))
    }
}
