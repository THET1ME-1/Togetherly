// Стенд виджета «Скучаю»: собирает настоящий MissWidget.swift и рисует оба
// размера на двух темах с худшими числами.
//
// Зачем: Swift расширения иначе проверяет только релизный прогон. Здесь же
// видно то, ради чего виджет и переделывали, — что «1000» не рвётся на две
// строки и плитки одной ширины.

import AppKit
import SwiftUI

let themes: [(String, [String: Color])] = [
    ("розовая-светлая", [
        "primary": Color(hex: 0xE56A77), "onPrimary": Color(hex: 0xFFFFFF),
        "onPrimarySoft": Color(hex: 0xFBEAEC), "blockOnPrimary": Color(hex: 0xE87C87),
        "primaryContainer": Color(hex: 0xFEEAF1), "onPrimaryContainer": Color(hex: 0xFF7E8B),
        "surface": Color(hex: 0xFFF8F7), "onSurface": Color(hex: 0x22191A),
        "onSurfaceVariant": Color(hex: 0x524344), "outline": Color(hex: 0x857373),
        "tertiary": Color(hex: 0x775930), "tertiaryContainer": Color(hex: 0xFFDDB4),
        "onTertiaryContainer": Color(hex: 0x5C421A),
        "avatarMine": Color(hex: 0xFFB2B7), "avatarPartner": Color(hex: 0xFFDDB4),
    ]),
    ("тёмный-лес", [
        "primary": Color(hex: 0x6EAE84), "onPrimary": Color(hex: 0x16161A),
        "onPrimarySoft": Color(hex: 0x27352C), "blockOnPrimary": Color(hex: 0x5D9872),
        "primaryContainer": Color(hex: 0x1D2A1F), "onPrimaryContainer": Color(hex: 0xA6D8B6),
        "surface": Color(hex: 0x11150F), "onSurface": Color(hex: 0xE4EAE0),
        "onSurfaceVariant": Color(hex: 0xB7C1B2), "outline": Color(hex: 0x8A948A),
        "tertiary": Color(hex: 0x9CD3E0), "tertiaryContainer": Color(hex: 0x214C58),
        "onTertiaryContainer": Color(hex: 0xD6EFF6),
        "avatarMine": Color(hex: 0xA6D8B6), "avatarPartner": Color(hex: 0x9CD3E0),
    ]),
]

/// Худшие числа: четыре знака у себя, три у партнёра и длинное имя.
let cases: [(String, [String: String])] = [
    ("1000 и 198", [
        "miss_latest_group": "g",
        "miss_g_my_text": "1000",
        "miss_g_partner_text": "198",
        "miss_g_me_label": "Вы",
        "miss_g_partner_name": "JB Sharan",
        "miss_g_partner_initial": "Ш",
        "miss_g_send_label": "Скучаю",
        "miss_g_when_label": "Последний раз в 20:41",
        "miss_g_today_label": "Сегодня",
        "miss_g_sent_today": "0",
    ]),
    ("отправлено, 12,3K", [
        "miss_latest_group": "g",
        "miss_g_my_text": "12,3K",
        "miss_g_partner_text": "9",
        "miss_g_me_label": "Вы",
        "miss_g_partner_name": "Константин",
        "miss_g_partner_initial": "К",
        "miss_g_send_label": "Отправлено",
        "miss_g_when_label": "Только что",
        "miss_g_today_label": "Сегодня",
        "miss_g_sent_today": "1",
    ]),
]

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

MainActor.assumeIsolated {
    var rows: [AnyView] = []
    for (themeName, palette) in themes {
        WidgetTheme.current = palette
        for (caseName, data) in cases {
            Store.strings = data
            let d = loadMiss()
            let t = WidgetTheme()
            let cells: [(AnyView, CGFloat, CGFloat)] = [
                (AnyView(MissSmallView(data: d, t: t)), 158, 158),
                (AnyView(MissMediumView(data: d, t: t)), 338, 158),
            ]
            rows.append(AnyView(VStack(alignment: .leading, spacing: 6) {
                Text("\(themeName) · \(caseName)").font(.system(size: 13, weight: .semibold))
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<cells.count, id: \.self) { i in
                        cells[i].0
                            .frame(width: cells[i].1, height: cells[i].2)
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
    try? png.write(to: URL(fileURLWithPath: "\(outDir)/скучаю.png"))
    print("скучаю.png — \(cg.width)×\(cg.height)")
}
