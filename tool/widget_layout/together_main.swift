// Стенд виджета «Вместе»: собирает настоящий TogetherWidget.swift и рисует
// три размера на четырёх темах.
//
// Зачем: Swift расширения иначе компилируется только релизным прогоном, и
// опечатка всплывает при выпуске. Здесь же видно саму раскладку — дорожку
// вех, растр и то, что подписи не режутся.
//
// Запуск: tool/widget_layout/run.sh (только macOS).

import AppKit
import SwiftUI

let themes: [(String, [String: Color])] = [
    ("розовая-светлая", [
        "primary": Color(hex: 0xE56A77), "onPrimary": Color(hex: 0xFFFFFF),
        "onPrimarySoft": Color(hex: 0xFBEAEC), "blockOnPrimary": Color(hex: 0xE87C87),
        "surface": Color(hex: 0xFFF8F7), "onSurface": Color(hex: 0x22191A),
        "onSurfaceVariant": Color(hex: 0x524344), "outline": Color(hex: 0x857373),
        "trackOnSurface": Color(hex: 0xFBE1E3), "tertiary": Color(hex: 0x775930),
        "tertiaryContainer": Color(hex: 0xFFDDB4),
        "avatarMine": Color(hex: 0xFFB2B7), "avatarPartner": Color(hex: 0xFFDDB4),
        "onPrimaryContainer": Color(hex: 0xFF7E8B),
        "onTertiaryContainer": Color(hex: 0x5C421A),
    ]),
    ("тёмный-лес", [
        "primary": Color(hex: 0x6EAE84), "onPrimary": Color(hex: 0x16161A),
        "onPrimarySoft": Color(hex: 0x27352C), "blockOnPrimary": Color(hex: 0x5D9872),
        "surface": Color(hex: 0x11150F), "onSurface": Color(hex: 0xE4EAE0),
        "onSurfaceVariant": Color(hex: 0xB7C1B2), "outline": Color(hex: 0x8A948A),
        "trackOnSurface": Color(hex: 0x24301F), "tertiary": Color(hex: 0x9CD3E0),
        "tertiaryContainer": Color(hex: 0x214C58),
        "avatarMine": Color(hex: 0xA6D8B6), "avatarPartner": Color(hex: 0x9CD3E0),
        "onPrimaryContainer": Color(hex: 0x123122),
        "onTertiaryContainer": Color(hex: 0xD6EFF6),
    ]),
]

/// Худшие случаи: пара в первой сотне (пройденной вехи нет) и давняя пара с
/// длинными подписями.
let cases: [(String, [String: String])] = [
    ("131 день", [
        "together_latest_group": "g",
        "together_g_days": "131",
        "together_g_days_label": "день вместе",
        "together_g_start_date": "С 12 мая 2026",
        "together_g_names": "THET1ME + JB SHARAN",
        "together_g_mile_percent": "31",
        "together_g_mile_prev_title": "100 дней",
        "together_g_mile_prev_sub": "Прошли 20 августа",
        "together_g_mile_today_title": "Сегодня",
        "together_g_mile_today_sub": "31% пути до 200 дней",
        "together_g_mile_next_title": "200 дней",
        "together_g_mile_next_sub": "через 69 дней",
        "together_g_mile_anni_title": "1 год",
        "together_g_mile_anni_sub": "12 мая",
        "together_g_my_initial": "Т",
        "together_g_partner_initial": "Ш",
    ]),
    ("первая сотня", [
        "together_latest_group": "g",
        "together_g_days": "12",
        "together_g_days_label": "дней вместе",
        "together_g_start_date": "С 8 сентября 2026",
        "together_g_names": "АЛЕКСАНДРА + КОНСТАНТИН",
        "together_g_mile_percent": "12",
        "together_g_mile_prev_title": "",
        "together_g_mile_prev_sub": "",
        "together_g_mile_today_title": "Сегодня",
        "together_g_mile_today_sub": "12% пути до 100 дней",
        "together_g_mile_next_title": "100 дней",
        "together_g_mile_next_sub": "через 88 дней",
        "together_g_mile_anni_title": "1 год",
        "together_g_mile_anni_sub": "8 сентября",
        "together_g_my_initial": "А",
        "together_g_partner_initial": "К",
    ]),
]

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

MainActor.assumeIsolated {
    var rows: [AnyView] = []
    for (themeName, palette) in themes {
        WidgetTheme.current = palette
        for (caseName, data) in cases {
            Store.strings = data
            // Размер выбираем прямым вызовом вида: `\.widgetFamily` читается,
            // но не задаётся, и `.environment` на него не годится.
            let d = loadTogether()
            let t = WidgetTheme()
            let views: [(AnyView, CGFloat, CGFloat)] = [
                (AnyView(TogetherSmallView(data: d, t: t)), 158, 158),
                (AnyView(TogetherMediumView(data: d, t: t)), 338, 158),
                (AnyView(TogetherLargeView(data: d, t: t)), 338, 338),
            ]
            var cells: [AnyView] = []
            for (view, w, h) in views {
                cells.append(AnyView(
                    view
                        .frame(width: w, height: h)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                ))
            }
            rows.append(AnyView(VStack(alignment: .leading, spacing: 6) {
                Text("\(themeName) · \(caseName)").font(.system(size: 13, weight: .semibold))
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<cells.count, id: \.self) { cells[$0] }
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
    let path = "\(outDir)/вместе.png"
    try? png.write(to: URL(fileURLWithPath: path))
    print("вместе.png — \(cg.width)×\(cg.height)")
}
