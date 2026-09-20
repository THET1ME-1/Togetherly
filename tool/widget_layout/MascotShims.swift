// Заглушки, которых просит «Маскот на столе» сверх общих.
//
// Виджет грузит кадр персонажа из контейнера App Group. В стенде контейнера
// нет, поэтому `WidgetImage.load` читает обычный файл с диска: путь стенд
// кладёт в тот же ключ, что и приложение. Так проверяется настоящая
// раскладка с настоящим спрайтом, а не с цветным прямоугольником.
//
// `WidgetImage` здесь дополняется, а не объявляется заново: пустую заготовку
// уже держит `TogetherShims.swift`, и второе объявление не собралось бы.

import AppKit
import SwiftUI

extension WidgetImage {
    static let maxSide: CGFloat = 1200

    static func load(
        _ path: String,
        maxSide: CGFloat = 1200,
        logAs widget: String = "",
        family: String = ""
    ) -> NSImage? {
        guard !path.isEmpty else { return nil }
        return NSImage(contentsOfFile: path)
    }
}
