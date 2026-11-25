import SwiftUI
import UIKit
import ImageIO

// Стенд снимка парного виджета на симуляторе (ios-widget-snapshot.yml).
//
// Собирается из НАСТОЯЩИХ файлов расширения (ios/TogetherlyWidget/*.swift,
// кроме бандла с @main) плюс этот файл. Кладёт в общий UserDefaults те же
// ключи, что пишет приложение, и рисует `LoveWidgetView` в PNG через
// ImageRenderer — тем же кодом SwiftUI, что рисует виджет на столе. Движения
// виджет не умеет, так что неподвижного снимка для проверки достаточно.
//
// Два случая в одном прогоне, иначе сбой стенда не отличить от сбоя фичи:
//   control.png — обычное фото (синее с белым кругом);
//   live.png — то же фото плюс раскадровка живого фото: на моей половине
//              обязан стоять первый кадр (красный), а не синее фото.
// Итог печатается строками «ИТОГ: …», код выхода 0 только если оба верны.

@main
struct SnapshotHarness: App {
    init() {
        Task { @MainActor in Self.run() }
    }

    var body: some Scene {
        WindowGroup { Color.white }
    }

    static func fixture(_ name: String) -> String {
        Bundle.main.bundlePath + "/fixtures/" + name
    }

    static func reset() {
        guard let d = AppGroup.defaults else { return }
        for k in d.dictionaryRepresentation().keys { d.removeObject(forKey: k) }
    }

    static func base() {
        let d = AppGroup.defaults
        d?.set("g1", forKey: "love_widget_group_id")
        d?.set("Аня", forKey: "my_name")
        d?.set("Боря", forKey: "partner_name")
        d?.set("Скучаю", forKey: "my_status")
        d?.set(fixture("photo.jpg"), forKey: "my_photo_path")
    }

    @MainActor
    static func render(_ name: String) -> UIImage? {
        let view = LoveWidgetView()
            .frame(width: 364, height: 170)
            .background(Color(white: 0.92))
        let r = ImageRenderer(content: view)
        r.scale = 3
        guard let img = r.uiImage, let png = img.pngData() else {
            print("ИТОГ: \(name) — ImageRenderer не дал картинку")
            return nil
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? png.write(to: docs.appendingPathComponent("\(name).png"))
        print("записан \(name).png \(Int(img.size.width))×\(Int(img.size.height))")
        return img
    }

    /// Цвет точки картинки (x, y в долях ширины и высоты).
    static func color(_ img: UIImage, _ fx: CGFloat, _ fy: CGFloat) -> (Int, Int, Int)? {
        guard let cg = img.cgImage else { return nil }
        let x = Int(CGFloat(cg.width) * fx), y = Int(CGFloat(cg.height) * fy)
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
        return (Int(px[0]), Int(px[1]), Int(px[2]))
    }

    @MainActor
    static func run() {
        var ok = true

        // ── обычное фото: контроль стенда ──
        reset(); base()
        let control = render("control")
        // точка моей половины в стороне от подписей и аватарки: у левого края
        let c0 = control.flatMap { color($0, 0.06, 0.6) }
        print("control: точка моей половины \(String(describing: c0))")
        let blue = c0.map { $0.2 > 120 && $0.0 < 120 } ?? false
        print("ИТОГ: control — \(blue ? "синее фото на месте" : "фото НЕ видно")")
        ok = ok && blue

        // ── живое фото: первый кадр поверх фото ──
        reset(); base()
        let manifest = (try? String(contentsOfFile: fixture("manifest.json"), encoding: .utf8)) ?? ""
        AppGroup.defaults?.set(fixture("sheet.webp"), forKey: LiveSheet.keyPath)
        AppGroup.defaults?.set(manifest, forKey: LiveSheet.keyManifest)

        let frame = LiveSheet.firstFrame(Store())
        print("первый кадр: \(frame.map { "\(Int($0.size.width))×\(Int($0.size.height))" } ?? "НЕ прочитан (WebP?)")")
        let f0 = frame.flatMap { color($0, 0.5, 0.8) }
        print("первый кадр, цвет: \(String(describing: f0))")

        let live = render("live")
        let l0 = live.flatMap { color($0, 0.06, 0.6) }
        print("live: точка моей половины \(String(describing: l0))")
        let red = l0.map { $0.0 > 150 && $0.2 < 110 } ?? false
        print("ИТОГ: live — \(red ? "первый кадр на месте" : "первого кадра НЕТ")")
        ok = ok && red && frame != nil

        print("ИТОГ: \(ok ? "ВСЁ ВЕРНО" : "ЕСТЬ ОШИБКИ")")
        exit(ok ? 0 : 1)
    }
}
