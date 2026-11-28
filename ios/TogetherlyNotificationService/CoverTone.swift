import CoreGraphics
import CoreText
import Foundation

/// Цвета обложки «А» по виду события — те же, что `notif/Tones.kt` на
/// Android (макет https://claude.ai/artifact/KZx6vHgr6LvacepEysXiGM).
///
/// [tint] — плашка под картинкой, [label] — подпись тона, [deep] — значок
/// даты и насыщенная плашка в тёмной теме, [labelNight] — подпись на тёмном
/// фоне. Общий для расширения сервиса (плашка значка, буква без фото),
/// карточки по долгому нажатию и приложения — только CoreGraphics.
struct CoverTone: Equatable {
  let tint: UInt32
  let label: UInt32
  let deep: UInt32
  let labelNight: UInt32

  static let all: [String: CoverTone] = [
    "miss": CoverTone(tint: 0xFFE1DC, label: 0x8C2F27, deep: 0xB8433A, labelNight: 0xFFB4A9),
    "mood": CoverTone(tint: 0xFFEDE4, label: 0x9A4458, deep: 0xB4506A, labelNight: 0xFFB1C3),
    "chat": CoverTone(tint: 0xE8E6FB, label: 0x3F3794, deep: 0x4F46A8, labelNight: 0xC4BFFF),
    "memory": CoverTone(tint: 0xCFE3DB, label: 0x245446, deep: 0x2E6B5A, labelNight: 0x9DD3BF),
    "gift": CoverTone(tint: 0xEFE6FA, label: 0x5A3C90, deep: 0x6C4BA6, labelNight: 0xD2BCFF),
    "evening": CoverTone(tint: 0xE6E4F7, label: 0x2D2A60, deep: 0x33306B, labelNight: 0xC3C0F5),
    "chest": CoverTone(tint: 0xFBEBD3, label: 0x714812, deep: 0x8A5A1F, labelNight: 0xF2C27E),
    "plus": CoverTone(tint: 0xFBEBD3, label: 0x714812, deep: 0x8A5A1F, labelNight: 0xF2C27E),
    "date": CoverTone(tint: 0xFFE6EC, label: 0x8A3550, deep: 0xA8405F, labelNight: 0xFFB0C6),
    "draw": CoverTone(tint: 0xE2F0FB, label: 0x24557A, deep: 0x2D6690, labelNight: 0xA6CDF0),
    "snow": CoverTone(tint: 0xE2F0FB, label: 0x24557A, deep: 0x2D6690, labelNight: 0xA6CDF0),
    "app": CoverTone(tint: 0xF3E9EB, label: 0x6B5B5C, deep: 0x8C2F27, labelNight: 0xD9C2C4),
  ]

  /// Тон по имени; незнакомый — нейтральный тон приложения.
  static func of(_ name: String) -> CoverTone { all[name] ?? all["app"]! }

  static func cg(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
  }

  /// Первая буква имени для кружка без фото (как `Tones.monogram`); пусто — «?».
  static func monogram(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.first else { return "?" }
    return String(first).uppercased()
  }
}

/// Значки Material Symbols — тот же шрифт, что у выбора значка даты в
/// приложении (`assets/fonts/MaterialSymbolsRounded.ttf`). Расширение берёт
/// его из ресурсов приложения, в котором лежит (`PlugIns/…appex` → две
/// папки вверх), отдельной копии не держит.
enum CoverSymbol {
  static let font: CGFont? = {
    guard let url = fontURL(), let provider = CGDataProvider(url: url as CFURL) else { return nil }
    return CGFont(provider)
  }()

  private static func fontURL() -> URL? {
    let file = "MaterialSymbolsRounded"
    if let own = Bundle.main.url(forResource: file, withExtension: "ttf") { return own }
    var app = Bundle.main.bundleURL
    if app.pathExtension == "appex" { app = app.deletingLastPathComponent().deletingLastPathComponent() }
    let url = app.appendingPathComponent("Frameworks/App.framework/flutter_assets/assets/fonts/\(file).ttf")
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  /// Плашка значка [name] стороны [side]: фон тона, значок насыщенным
  /// цветом, как `NotifArt.tile` на Android. Шрифта нет — nil.
  static func tile(_ name: String, tone: CoverTone, side: Int) -> CGImage? {
    guard let font, let ctx = context(side) else { return nil }
    let s = CGFloat(side)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                       cornerWidth: s * 0.25, cornerHeight: s * 0.25, transform: nil))
    ctx.clip()
    ctx.setFillColor(CoverTone.cg(tone.tint))
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    let ct = CTFontCreateWithGraphicsFont(font, s * 0.58, nil, nil)
    var line = self.line(name, font: ct, color: CoverTone.cg(tone.deep))
    // Имя без лигатуры шире плашки: такого значка нет — сердце.
    if CTLineGetTypographicBounds(line, nil, nil, nil) > Double(s * 0.9) {
      line = self.line("favorite", font: ct, color: CoverTone.cg(tone.deep))
    }
    center(line, in: ctx, side: s)
    return ctx.makeImage()
  }

  /// Волна голосового, как пузырь в чате и `NotifArt.waveform` на Android:
  /// [peaks] — до 40 цифр 0–9 (`VoicePeaks`), столбики насыщенного цвета
  /// тона на его плашке.
  static func waveform(_ peaks: String, tone: CoverTone, width: Int, height: Int) -> CGImage? {
    guard let ctx = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    let w = CGFloat(width), h = CGFloat(height)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                       cornerWidth: h * 0.22, cornerHeight: h * 0.22, transform: nil))
    ctx.setFillColor(CoverTone.cg(tone.tint))
    ctx.fillPath()
    var levels = peaks.compactMap { $0.wholeNumberValue }.map { CGFloat(min(9, max(0, $0))) / 9 }
    if levels.isEmpty { levels = Array(repeating: 0.35, count: 40) }
    let padX = w * 0.08
    let step = (w - 2 * padX) / CGFloat(levels.count)
    let bar = step * 0.55
    let maxH = h * 0.62
    ctx.setFillColor(CoverTone.cg(tone.deep))
    for (i, v) in levels.enumerated() {
      // Тишина — короткая засечка, а не разрыв, как в чате.
      let barH = max(bar, maxH * max(0.12, v))
      let x = padX + CGFloat(i) * step + (step - bar) / 2
      ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: (h - barH) / 2, width: bar, height: barH),
                         cornerWidth: bar / 2, cornerHeight: bar / 2, transform: nil))
    }
    ctx.fillPath()
    return ctx.makeImage()
  }

  /// Кружок с буквой имени — партнёр без фото, как `NotifArt.avatar`.
  static func monogram(_ name: String, tone: CoverTone, in ctx: CGContext, rect: CGRect) {
    ctx.saveGState()
    ctx.setFillColor(CoverTone.cg(tone.tint))
    ctx.fillEllipse(in: rect)
    let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, rect.width * 0.44, nil)
      ?? CTFontCreateWithName("Helvetica-Bold" as CFString, rect.width * 0.44, nil)
    let line = self.line(CoverTone.monogram(name), font: font, color: CoverTone.cg(tone.label))
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.textPosition = CGPoint(x: rect.midX - bounds.midX, y: rect.midY - bounds.midY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
  }

  static func context(_ side: Int) -> CGContext? {
    CGContext(
      data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  }

  private static func line(_ text: String, font: CTFont, color: CGColor) -> CTLine {
    let attrs: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
      // Значок собирается из букв имени лигатурой.
      NSAttributedString.Key(kCTLigatureAttributeName as String): 1,
    ]
    return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
  }

  private static func center(_ line: CTLine, in ctx: CGContext, side s: CGFloat) {
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.textPosition = CGPoint(x: (s - bounds.width) / 2 - bounds.minX, y: (s - bounds.height) / 2 - bounds.minY)
    CTLineDraw(line, ctx)
  }
}
