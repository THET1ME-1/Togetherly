// Стенд раскладки парного виджета: рисует настоящий LoveWidgetView в картинку
// и меряет, сколько столбцов занимает каждая половина.
//
// Жалоба с iPhone (14.09.2026): левое фото забирает больше половины виджета,
// правое сжато в полоску, подпись обрезана. Половины обязаны быть равными при
// любой пропорции снимков — это и проверяется.
//
// Запуск: tool/widget_layout/run.sh (только macOS, в CI — ios-widget-layout.yml).

import AppKit
import SwiftUI

struct Case {
    let name: String
    let left: CGSize
    let right: CGSize
}

let cases = [
    Case(name: "слева-широкое", left: CGSize(width: 1800, height: 1000), right: CGSize(width: 900, height: 1600)),
    Case(name: "справа-широкое", left: CGSize(width: 900, height: 1600), right: CGSize(width: 1800, height: 1000)),
    Case(name: "оба-широкие", left: CGSize(width: 2000, height: 900), right: CGSize(width: 1600, height: 1000)),
    Case(name: "оба-высокие", left: CGSize(width: 900, height: 1600), right: CGSize(width: 1000, height: 1800)),
]

// Средний виджет у iPhone разных размеров: вся площадь и она же за вычетом
// системных полей в 16 точек — какую из них получит вьюха, решает система.
let sizes = [
    CGSize(width: 338, height: 158),
    CGSize(width: 306, height: 126),
    CGSize(width: 364, height: 170),
    CGSize(width: 321, height: 152),
]

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
var failures = 0

MainActor.assumeIsolated {
    for c in cases {
        Store.strings = [
            "love_widget_group_id": "g1",
            "my_status": "о",
            "partner_status": "ты когда будешь дома",
        ]
        Store.images = [
            "my_photo_path": solidImage(width: c.left.width, height: c.left.height, color: .red),
            "partner_photo_path": solidImage(width: c.right.width, height: c.right.height, color: .blue),
        ]

        for size in sizes {
            let renderer = ImageRenderer(
                content: LoveWidgetView().frame(width: size.width, height: size.height)
            )
            renderer.scale = 1
            guard let cg = renderer.cgImage else {
                print("✗ \(c.name) \(Int(size.width))×\(Int(size.height)): картинка не собралась")
                failures += 1
                continue
            }

            let w = cg.width, h = cg.height
            var px = [UInt8](repeating: 0, count: w * h * 4)
            let ctx = CGContext(
                data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

            // Строка у самого верха: текст и аватарки туда не достают.
            let row = 2
            var red = 0, blue = 0, firstRed = -1, lastBlue = -1
            for x in 0..<w {
                let i = (row * w + x) * 4
                let r = Int(px[i]), b = Int(px[i + 2]), g = Int(px[i + 1])
                if r > 120 && g < 60 && b < 60 {
                    red += 1
                    if firstRed < 0 { firstRed = x }
                } else if b > 120 && r < 60 && g < 60 {
                    blue += 1
                    lastBlue = x
                }
            }

            let equal = abs(red - blue) <= 2
            let edges = firstRed == 0 && lastBlue == w - 1
            let ok = equal && edges
            if !ok { failures += 1 }
            print("\(ok ? "✓" : "✗") \(c.name) \(w)×\(h): левая \(red), правая \(blue), края \(firstRed)…\(lastBlue)")

            let rep = NSBitmapImageRep(cgImage: cg)
            let file = "\(outDir)/\(c.name)-\(w)x\(h).png"
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: file))
        }
    }
}

print(failures == 0 ? "ИТОГ: половины равны везде" : "ИТОГ: провалов \(failures)")
exit(failures == 0 ? 0 : 1)
