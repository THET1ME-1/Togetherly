// Стенд виджета «Маскот на столе»: собирает настоящий MascotWidget.swift и
// рисует все три размера на двух темах.
//
// Зачем: расширение виджетов иначе проверяет только релизный прогон, а
// увидеть iPhone-раскладку с ноутбука без macOS нечем. Здесь видно главное —
// что персонаж не мылится, стоит на кромке пола и не перекрывает плитки.

import AppKit
import SwiftUI

let themes: [(String, [String: Color])] = [
    ("розовая-светлая", [
        "primary": Color(hex: 0xE56A77), "onPrimary": Color(hex: 0xFFFFFF),
        "primaryContainer": Color(hex: 0xFEEAF1), "onPrimaryContainer": Color(hex: 0xFF7E8B),
        "surface": Color(hex: 0xFFF8F7), "surfaceContainer": Color(hex: 0xF6E4E4),
        "onSurface": Color(hex: 0x22191A), "onSurfaceVariant": Color(hex: 0x524344),
        "outline": Color(hex: 0x857373), "trackOnContainer": Color(hex: 0xF8C9D1),
        "tertiary": Color(hex: 0x775930), "tertiaryContainer": Color(hex: 0xFFDDB4),
        "onTertiaryContainer": Color(hex: 0x5C421A),
    ]),
    ("розовая-тёмная", [
        "primary": Color(hex: 0xFFCACD), "onPrimary": Color(hex: 0x16161A),
        "primaryContainer": Color(hex: 0xFFB2B7), "onPrimaryContainer": Color(hex: 0x16161A),
        "surface": Color(hex: 0x1A1112), "surfaceContainer": Color(hex: 0x312828),
        "onSurface": Color(hex: 0xF0DEDE), "onSurfaceVariant": Color(hex: 0xD7C1C2),
        "outline": Color(hex: 0x9F8C8D), "trackOnContainer": Color(hex: 0xFFB8BD),
        "tertiary": Color(hex: 0xE7C08E), "tertiaryContainer": Color(hex: 0x5C421A),
        "onTertiaryContainer": Color(hex: 0xFFDDB4),
    ]),
]

/// Кадр берётся настоящий — тот же спрайт, которым рисуются превью лончера.
let framePath = FileManager.default.currentDirectoryPath + "/tools/assets/mascot_preview_frame.png"

let cases: [(String, [String: String])] = [
    ("подросток, серия 12", [
        "ios_mascot_name": "Пудя",
        "ios_mascot_stage_label": "подросток",
        "ios_mascot_streak": "12",
        "ios_mascot_streak_label": "дней серии",
        "ios_mascot_next_label": "до взрослого 18 дней",
        "ios_mascot_progress": "22",
        "ios_mascot_record": "64",
        "ios_mascot_record_label": "рекорд 64 дня",
        "ios_mascot_sleep_from": "1380",
        "ios_mascot_sleep_to": "420",
        "ios_mascot_sleep_label_day": "Не спит до 23:00",
        "ios_mascot_sleep_label_night": "Спит до 07:00",
        "ios_mascot_sad": "0",
        "ios_mascot_pixel": "1",
        "ios_mascot_frame_day": framePath,
    ]),
    ("длинное имя, серия оборвалась", [
        "ios_mascot_name": "Кристалик-Половинка",
        "ios_mascot_stage_label": "малыш",
        "ios_mascot_streak": "0",
        "ios_mascot_streak_label": "дней серии",
        "ios_mascot_next_label": "до подростка 7 дней",
        "ios_mascot_progress": "0",
        "ios_mascot_record": "128",
        "ios_mascot_record_label": "рекорд 128 дней",
        "ios_mascot_sleep_from": "-1",
        "ios_mascot_sleep_to": "-1",
        "ios_mascot_sleep_label_day": "",
        "ios_mascot_sleep_label_night": "",
        "ios_mascot_sad": "1",
        "ios_mascot_pixel": "1",
        "ios_mascot_frame_day": framePath,
        "ios_mascot_frame_sad": framePath,
    ]),
]

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

MainActor.assumeIsolated {
    var rows: [AnyView] = []
    for (themeName, palette) in themes {
        WidgetTheme.current = palette
        for (caseName, data) in cases {
            Store.strings = data
            let d = MascotData()
            let t = WidgetTheme()
            let cells: [(AnyView, CGFloat, CGFloat)] = [
                (AnyView(MascotSmallView(data: d, theme: t)), 158, 158),
                (AnyView(MascotMediumView(data: d, theme: t)), 338, 158),
                (AnyView(MascotLargeView(data: d, theme: t)), 338, 354),
            ]
            rows.append(AnyView(VStack(alignment: .leading, spacing: 6) {
                Text("\(themeName) · \(caseName)").font(.system(size: 13, weight: .semibold))
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<cells.count, id: \.self) { i in
                        cells[i].0
                            .frame(width: cells[i].1, height: cells[i].2)
                            .background(t.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
            }))
        }
    }

    let sheet = VStack(alignment: .leading, spacing: 16) {
        ForEach(0..<rows.count, id: \.self) { rows[$0] }
    }
    .padding(20)
    .background(Color(white: 0.93))

    let renderer = ImageRenderer(content: sheet)
    renderer.scale = 2
    guard let cg = renderer.cgImage else {
        FileHandle.standardError.write("не удалось отрисовать\n".data(using: .utf8)!)
        exit(1)
    }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try? png.write(to: URL(fileURLWithPath: "\(outDir)/маскот.png"))
    print("маскот.png — \(cg.width)×\(cg.height)")
}
