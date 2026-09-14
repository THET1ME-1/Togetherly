// Стенд «Кольца года»: рисует настоящие YearRingMedium и YearRingSmall на
// четырёх темах и худших числах и складывает картинки в одну сетку.
//
// Запуск: tool/widget_layout/run.sh (только macOS).

import AppKit
import SwiftUI

let themes: [(String, [String: Color])] = [
    ("розовая-светлая", ["primary": Color(hex: 0xFF7E8B), "onPrimary": Color(hex: 0xFFFFFF), "tertiaryContainer": Color(hex: 0xFFDDB4)]),
    ("розовая-тёмная", ["primary": Color(hex: 0xFFCACD), "onPrimary": Color(hex: 0x16161A), "tertiaryContainer": Color(hex: 0x5C421A)]),
    ("вишнёвая", ["primary": Color(hex: 0xA03D5C), "onPrimary": Color(hex: 0xFFFFFF), "tertiaryContainer": Color(hex: 0xFFDCBE)]),
    ("тёмный-лес", ["primary": Color(hex: 0x6EAE84), "onPrimary": Color(hex: 0x16161A), "tertiaryContainer": Color(hex: 0x214C58)]),
]

// Сегодня зафиксировано, чтобы картинки не менялись от прогона к прогону.
let now = Date(timeIntervalSince1970: 1_789_400_000)
func start(daysAgo: Int) -> Int {
    Int(now.addingTimeInterval(-Double(daysAgo) * 86400).timeIntervalSince1970 * 1000)
}

let cases: [(Int, Int)] = [(125, 10), (1288, 10), (12345, 1234)]
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

MainActor.assumeIsolated {
    var rows: [AnyView] = []
    for (name, palette) in themes {
        WidgetTheme.current = palette
        var cells: [AnyView] = []
        for (i, (days, memories)) in cases.enumerated() {
            let ms = start(daysAgo: days)
            let math = YearMath.from(startMs: ms, now: now)
            let medium = YearRingMedium(
                math: math, memories: memories,
                anniversary: anniversaryDayMonth(startMs: ms), t: WidgetTheme()
            )
            // Третий случай — тесная ячейка лончера поменьше.
            let size = i == 2 ? CGSize(width: 321, height: 152) : CGSize(width: 338, height: 158)
            cells.append(AnyView(medium.frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))))
            if i < 2 {
                cells.append(AnyView(YearRingSmall(math: math, t: WidgetTheme())
                    .frame(width: 158, height: 158)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))))
            }
        }
        rows.append(AnyView(VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.system(size: 13, weight: .semibold))
            HStack(alignment: .top, spacing: 12) { ForEach(0..<cells.count, id: \.self) { cells[$0] } }
        }))
    }
    let sheet = VStack(alignment: .leading, spacing: 16) {
        ForEach(0..<rows.count, id: \.self) { rows[$0] }
    }
    .padding(20)
    .background(Color(white: 0.93))

    let renderer = ImageRenderer(content: sheet)
    renderer.scale = 2
    guard let cg = renderer.cgImage else {
        print("✗ сетка не собралась")
        exit(1)
    }
    let rep = NSBitmapImageRep(cgImage: cg)
    try? rep.representation(using: .png, properties: [:])?
        .write(to: URL(fileURLWithPath: "\(outDir)/кольцо-года.png"))
    print("✓ кольцо года: \(cg.width)×\(cg.height)")
}
