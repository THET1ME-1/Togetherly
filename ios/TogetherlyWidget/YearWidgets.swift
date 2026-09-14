import SwiftUI
import WidgetKit

// MARK: - «Кольцо года» и «Календарь лет»
//
// Из Flutter приезжает только дата начала (`ring_<g>_start_ms`), счётчик
// воспоминаний и подпись даты. Дни, месяцы и доля кольца считаются здесь по
// системному времени — тот же приём, что у лепесткового таймера: иначе цифра
// застывала бы до следующего открытия приложения. Расчёт зеркалит `YearMath.kt`
// и `lib/models/year_progress.dart`; правки вносить во все три места.

struct YearMath {
    let daysTotal: Int
    let yearsCompleted: Int
    let monthsCompleted: Int
    let daysIntoYear: Int
    let daysToNextAnniversary: Int

    /// Доля текущего года, 0…1. Знаменатель 365 — как на Android и в Dart.
    var ringProgress: Double { Double(daysIntoYear % 365) / 365.0 }

    static func from(startMs: Int, now: Date = Date()) -> YearMath {
        let cal = Calendar.current
        let from = cal.startOfDay(for: Date(timeIntervalSince1970: Double(startMs) / 1000.0))
        let to = cal.startOfDay(for: now)

        let daysTotal = days(from: from, to: to)

        // Годовщина календарная: пара отмечает её в свою дату, а не через
        // фиксированные 365 суток.
        var years = (cal.component(.year, from: to)) - (cal.component(.year, from: from))
        if let thisYear = sameDate(from, inYear: cal.component(.year, from: to)), thisYear > to {
            years -= 1
        }
        if years < 0 { years = 0 }

        let last = sameDate(from, inYear: cal.component(.year, from: from) + years) ?? from
        let next = sameDate(from, inYear: cal.component(.year, from: from) + years + 1) ?? to

        var months = (cal.component(.year, from: to) - cal.component(.year, from: from)) * 12
            + (cal.component(.month, from: to) - cal.component(.month, from: from))
        if cal.component(.day, from: to) < cal.component(.day, from: from) { months -= 1 }

        return YearMath(
            daysTotal: max(daysTotal, 0),
            yearsCompleted: years,
            monthsCompleted: max(months, 0),
            daysIntoYear: max(days(from: last, to: to), 0),
            daysToNextAnniversary: max(days(from: to, to: next), 0)
        )
    }

    /// Целых суток между полуночами. Через секунды с округлением: перевод часов
    /// делает сутки короче или длиннее, и деление нацело врало бы на день.
    private static func days(from: Date, to: Date) -> Int {
        Int((to.timeIntervalSince(from) / 86400).rounded())
    }

    /// Та же дата в другом году. 29 февраля в невисокосном году Calendar
    /// переносит сам — пара отмечает годовщину в первый существующий день.
    private static func sameDate(_ source: Date, inYear year: Int) -> Date? {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: source)
        comps.year = year
        return cal.date(from: comps)
    }
}

/// «ПЕРВЫЙ ГОД ВМЕСТЕ». Дальше десятого пара доходит редко, там подпись
/// становится числовой.
func yearOrdinal(_ n: Int) -> String {
    let words = ["ПЕРВЫЙ", "ВТОРОЙ", "ТРЕТИЙ", "ЧЕТВЁРТЫЙ", "ПЯТЫЙ",
                 "ШЕСТОЙ", "СЕДЬМОЙ", "ВОСЬМОЙ", "ДЕВЯТЫЙ", "ДЕСЯТЫЙ"]
    let word = (n >= 1 && n <= words.count) ? words[n - 1] : "\(n)-Й"
    return "\(word) ГОД ВМЕСТЕ"
}

/// Та же строка с заглавной: подпись начинается с неё, а не продолжает фразу.
func capitalizedFirst(_ s: String) -> String {
    guard let first = s.first else { return s }
    return String(first).uppercased() + String(s.dropFirst())
}

func monthsWord(_ n: Int) -> String {
    let a = n % 100
    let b = n % 10
    if (11...19).contains(a) { return "месяцев" }
    if b == 1 { return "месяц" }
    if (2...4).contains(b) { return "месяца" }
    return "месяцев"
}

private struct YearData {
    let startMs: Int
    let memories: Int
    let startDate: String
}

private func loadYear(_ pointer: String, _ prefix: String) -> YearData {
    let s = Store()
    let g = s.latestGroup(pointer)
    return YearData(
        startMs: s.int("\(prefix)_\(g)_start_ms"),
        memories: s.int("\(prefix)_\(g)_memories"),
        startDate: s.string("\(prefix)_\(g)_start_date")
    )
}

// MARK: - Кольцо года
//
// Раскладка «Отсчёт» (макет 14.09.2026) одна на iPhone, Android и превью в
// каталоге: кольцо с числом дней и меткой сегодняшнего дня, справа сколько
// осталось до годовщины, дата и под чертой месяцы с воспоминаниями. Числа и
// правила подгонки живут в `lib/models/year_ring_spec.dart`, здесь повторены
// (сверяет `test/models/year_ring_spec_test.dart`). До этого на iPhone «1288»
// вылезало за кольцо, а подписи красились светлым акцентом, почти равным
// заливке, и сливались с фоном.

/// Правила подгонки текста — те же доли, что в Dart и Kotlin.
enum YearRingFit {
    static let numberShare: CGFloat = 0.74
    static let digitEm: CGFloat = 0.58
    static let letterEm: CGFloat = 0.56
    static let softAlpha: Double = 0.84
    static let trackAlpha: Double = 0.22
    static let hairlineAlpha: Double = 0.28

    /// Кегль числа: помещается во внутренний диаметр при любом числе цифр.
    static func number(inner: CGFloat, digits: Int, max: CGFloat) -> CGFloat {
        min(max, inner * numberShare / (CGFloat(Swift.max(digits, 1)) * digitEm))
    }

    /// Кегль строки: базовый, пока помещается в [width], дальше меньше.
    static func text(base: CGFloat, chars: Int, width: CGFloat) -> CGFloat {
        chars <= 0 ? base : min(base, width / (CGFloat(chars) * letterEm))
    }

    /// Конец дуги: старт на двенадцати часах, по часовой.
    static func arcEnd(center: CGPoint, radius: CGFloat, progress: Double) -> CGPoint {
        let a = -Double.pi / 2 + min(max(progress, 0), 1) * 2 * Double.pi
        return CGPoint(x: center.x + radius * CGFloat(cos(a)),
                       y: center.y + radius * CGFloat(sin(a)))
    }
}

/// «12 мая» — день и месяц годовщины, то есть даты начала.
func anniversaryDayMonth(startMs: Int) -> String {
    let months = ["января", "февраля", "марта", "апреля", "мая", "июня",
                  "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    let date = Date(timeIntervalSince1970: Double(startMs) / 1000.0)
    let c = Calendar.current.dateComponents([.day, .month], from: date)
    guard let d = c.day, let m = c.month, (1...12).contains(m) else { return "" }
    return "\(d) \(months[m - 1])"
}

func memoriesWord(_ n: Int) -> String {
    let a = n % 100
    let b = n % 10
    if (11...19).contains(a) { return "воспоминаний" }
    if b == 1 { return "воспоминание" }
    if (2...4).contains(b) { return "воспоминания" }
    return "воспоминаний"
}

private struct YearRingView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let data = loadYear("year_ring_latest_group", "ring")
        let t = WidgetTheme()

        if data.startMs <= 0 {
            TgEmptyView(text: "Укажите дату начала — и кольцо оживёт", theme: t)
        } else {
            let math = YearMath.from(startMs: data.startMs)
            if family == .systemSmall {
                YearRingSmall(math: math, t: t)
            } else {
                YearRingMedium(
                    math: math,
                    memories: data.memories,
                    anniversary: anniversaryDayMonth(startMs: data.startMs),
                    t: t
                )
            }
        }
    }
}

/// 4×2: размеры в точках среднего виджета 338×158, умноженные на `k`.
struct YearRingMedium: View {
    let math: YearMath
    let memories: Int
    let anniversary: String
    let t: WidgetTheme

    var body: some View {
        GeometryReader { geo in
            let g = Geometry(size: geo.size)
            let on = t.onPrimary
            let soft = on.opacity(YearRingFit.softAlpha)
            let leftNum = "\(math.daysToNextAnniversary)"
            let leftWord = daysWord(math.daysToNextAnniversary)
            let countSize = min(
                40 * g.k,
                (g.right - 6 * g.k)
                    / (CGFloat(leftNum.count) * YearRingFit.digitEm
                        + CGFloat(leftWord.count) * YearRingFit.letterEm * 0.375)
            )
            let eyebrow = "До годовщины"
            let date = anniversary.isEmpty ? "Годовщина" : "Годовщина \(anniversary)"
            let monthsShort = "мес."
            let memWord = memoriesWord(memories)
            let stats = "\(math.monthsCompleted) \(monthsShort)    \(memories) \(memWord)"
            let statsSize = YearRingFit.text(
                base: max(12.5 * g.k, 9.5), chars: stats.count, width: g.right)

            HStack(spacing: 0) {
                YearRingDial(
                    math: math,
                    side: g.ring,
                    stroke: g.stroke,
                    maxNumber: 36 * g.k,
                    caption: "\(capitalizedFirst(daysWord(math.daysTotal))) вместе",
                    captionSize: 11.5 * g.k,
                    t: t
                )
                VStack(alignment: .leading, spacing: 0) {
                    Text(eyebrow)
                        .font(.system(size: YearRingFit.text(
                            base: max(11 * g.k, 9), chars: eyebrow.count, width: g.right),
                                      weight: .semibold))
                        .foregroundColor(soft)
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 6 * g.k) {
                        Text(leftNum)
                            .font(.system(size: countSize, weight: .heavy))
                            .kerning(-countSize * 0.03)
                            .foregroundColor(on)
                            .widgetAccentable()
                        Text(leftWord)
                            .font(.system(size: countSize * 0.375, weight: .bold))
                            .foregroundColor(on)
                    }
                    .lineLimit(1)
                    Text(date)
                        .font(.system(size: YearRingFit.text(
                            base: max(12 * g.k, 9.5), chars: date.count, width: g.right),
                                      weight: .medium))
                        .foregroundColor(soft)
                        .lineLimit(1)
                        .padding(.top, 2 * g.k)
                    Rectangle()
                        .fill(on.opacity(YearRingFit.hairlineAlpha))
                        .frame(height: 1)
                        .padding(.top, 10 * g.k)
                        .padding(.bottom, 8 * g.k)
                    HStack(alignment: .firstTextBaseline, spacing: 16 * g.k) {
                        stat("\(math.monthsCompleted)", monthsShort, statsSize, on, soft)
                        stat("\(memories)", memWord, statsSize, on, soft)
                    }
                    .lineLimit(1)
                }
                .frame(width: max(g.right, 0), alignment: .leading)
                .padding(.leading, g.gap)
            }
            .padding(.leading, g.padL)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
        .tgContainerBackground {
            YearRingBackdrop(t: t, arcs: true) { size in
                let g = Geometry(size: size)
                return YearRingFit.arcEnd(
                    center: CGPoint(x: g.padL + g.ring / 2, y: size.height / 2),
                    radius: (g.ring - g.stroke) / 2,
                    progress: math.ringProgress
                )
            }
        }
    }

    private func stat(_ value: String, _ unit: String, _ size: CGFloat,
                      _ on: Color, _ soft: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value).font(.system(size: size, weight: .heavy)).foregroundColor(on)
            Text(unit).font(.system(size: size, weight: .medium)).foregroundColor(soft)
        }
    }

    struct Geometry {
        let k: CGFloat
        let ring: CGFloat
        let stroke: CGFloat
        let padL: CGFloat
        let gap: CGFloat
        let right: CGFloat

        init(size: CGSize) {
            k = min(max(min(size.height / 158, size.width / 338), 0.7), 1.5)
            ring = min(128 * k, size.height - 16)
            stroke = 10 * k
            padL = 14 * k
            gap = 16 * k
            right = size.width - padL - 16 * k - gap - ring
        }
    }
}

/// 2×2: кольцо и под ним сколько осталось до годовщины.
struct YearRingSmall: View {
    let math: YearMath
    let t: WidgetTheme

    var body: some View {
        GeometryReader { geo in
            let k = min(max(min(geo.size.width, geo.size.height) / 158, 0.7), 1.6)
            let line = "Ещё \(math.daysToNextAnniversary) \(daysWord(math.daysToNextAnniversary))"
            let lineSize = YearRingFit.text(
                base: max(11.5 * k, 9.5), chars: line.count, width: geo.size.width - 24 * k)
            VStack(spacing: 9 * k) {
                YearRingDial(
                    math: math,
                    side: 112 * k,
                    stroke: 10 * k,
                    maxNumber: 34 * k,
                    caption: capitalizedFirst(daysWord(math.daysTotal)),
                    captionSize: 11 * k,
                    t: t
                )
                Text(line)
                    .font(.system(size: lineSize, weight: .bold))
                    .foregroundColor(t.onPrimary)
                    .lineLimit(1)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .tgContainerBackground {
            YearRingBackdrop(t: t, arcs: false) { size in
                let k = min(max(min(size.width, size.height) / 158, 0.7), 1.6)
                let ring = 112 * k
                let block = ring + 9 * k + 11.5 * k * 1.2
                return YearRingFit.arcEnd(
                    center: CGPoint(x: size.width / 2, y: (size.height - block) / 2 + ring / 2),
                    radius: (ring - 10 * k) / 2,
                    progress: math.ringProgress
                )
            }
        }
    }
}

/// Кольцо с числом дней внутри и меткой сегодняшнего дня на конце дуги.
/// Рисуется дугой SwiftUI — на Android то же самое уходит картинкой.
struct YearRingDial: View {
    let math: YearMath
    let side: CGFloat
    let stroke: CGFloat
    let maxNumber: CGFloat
    let caption: String
    let captionSize: CGFloat
    let t: WidgetTheme

    var body: some View {
        let on = t.onPrimary
        let inner = side - 2 * stroke
        let number = "\(math.daysTotal)"
        let numberSize = YearRingFit.number(inner: inner, digits: number.count, max: maxNumber)
        let r = (side - stroke) / 2
        let progress = math.ringProgress
        let end = YearRingFit.arcEnd(center: CGPoint(x: side / 2, y: side / 2),
                                     radius: r, progress: progress)
        ZStack {
            Circle()
                .inset(by: stroke / 2)
                .stroke(on.opacity(YearRingFit.trackAlpha), lineWidth: stroke)
            if progress > 0.002 {
                Circle()
                    .inset(by: stroke / 2)
                    .trim(from: 0, to: progress)
                    .stroke(on, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Circle()
                .fill(t.primary)
                .overlay(Circle().stroke(on, lineWidth: stroke * 0.55))
                .frame(width: stroke * 1.9, height: stroke * 1.9)
                .position(end)
            VStack(spacing: 3) {
                Text(number)
                    .font(.system(size: numberSize, weight: .heavy))
                    .kerning(-numberSize * 0.03)
                    .foregroundColor(on)
                    .widgetAccentable()
                    .lineLimit(1)
                Text(caption)
                    .font(.system(size: YearRingFit.text(
                        base: captionSize, chars: caption.count, width: inner * 0.86),
                                  weight: .semibold))
                    .foregroundColor(on.opacity(YearRingFit.softAlpha))
                    .lineLimit(1)
            }
        }
        .frame(width: side, height: side)
    }
}

/// Фон «Кольца года»: заливка темы с градиентом к светлому и глубокому тону
/// под 140°, пятно третьего цвета в правом верхнем углу, свечение у конца
/// дуги и, если нужно, две полупрозрачные дуги в углу. Повторяет
/// `YearRingBackdropPainter` из приложения и `WidgetImages.ringBackdrop`.
///
/// Уходит только в `tgContainerBackground { }`: в тонированном режиме его
/// заменяет системная подложка.
struct YearRingBackdrop: View {
    let t: WidgetTheme
    let arcs: Bool
    let glowAt: (CGSize) -> CGPoint

    /// Светлее заливки сверху слева, глубже снизу справа.
    private static let shade: [Gradient.Stop] = [
        .init(color: .white.opacity(0.08), location: 0),
        .init(color: .clear, location: 0.45),
        .init(color: .black.opacity(0.18), location: 1),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let dx: CGFloat = 0.6428
            let dy: CGFloat = 0.7660
            let len = w * dx + h * dy
            let from = UnitPoint(x: (w / 2 - dx * len / 2) / w, y: (h / 2 - dy * len / 2) / h)
            let to = UnitPoint(x: (w / 2 + dx * len / 2) / w, y: (h / 2 + dy * len / 2) / h)
            let glow = glowAt(geo.size)
            ZStack {
                Rectangle().fill(t.primary)
                Rectangle().fill(LinearGradient(stops: Self.shade, startPoint: from, endPoint: to))
                Rectangle()
                    .fill(
                        RadialGradient(
                            colors: [t.tertiaryContainer.opacity(0.38), t.tertiaryContainer.opacity(0)],
                            center: .topTrailing, startRadius: 0, endRadius: 126
                        )
                    )
                    .scaleEffect(x: 1, y: 140.0 / 180.0, anchor: .topTrailing)
                Rectangle().fill(
                    RadialGradient(
                        colors: [t.onPrimary.opacity(0.26), t.onPrimary.opacity(0)],
                        center: UnitPoint(x: glow.x / w, y: glow.y / h),
                        startRadius: 0, endRadius: 84
                    )
                )
                if arcs {
                    Circle()
                        .stroke(t.onPrimary.opacity(0.10), lineWidth: 18)
                        .frame(width: 180, height: 180)
                        .position(x: w - 38, y: -10)
                    Circle()
                        .stroke(t.onPrimary.opacity(0.06), lineWidth: 10)
                        .frame(width: 260, height: 260)
                        .position(x: w - 38, y: -10)
                }
            }
        }
    }
}

struct YearRingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "YearRingWidget4x2Provider", provider: RefreshProvider()) { _ in
            YearRingView().unredacted()
        }
        .configurationDisplayName("Кольцо года")
        .description("Сколько прошло от годовщины до годовщины.")
        .supportedFamilies([.systemSmall, .systemMedium])
        // Раскладка считает поля сама (левое 14, правое 16 точек) и фон идёт
        // под край: системные поля iOS 17 сжимали бы её внутрь.
        .contentMarginsDisabled()
    }
}

// MARK: - Календарь лет

private struct YearGridView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let data = loadYear("year_grid_latest_group", "grid")
        let t = WidgetTheme()

        if data.startMs <= 0 {
            TgEmptyView(text: "Укажите дату начала — и календарь оживёт", theme: t)
        } else {
            let math = YearMath.from(startMs: data.startMs)
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(math.daysTotal)")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .widgetAccentable()
                        .foregroundColor(t.onSurface)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(capitalizedFirst(daysWord(math.daysTotal)))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(t.onSurfaceVariant)
                    Text("\(math.monthsCompleted) \(monthsWord(math.monthsCompleted))")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(t.primary)
                        .padding(.top, 4)
                    if !data.startDate.isEmpty {
                        Text(data.startDate)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(t.onSurfaceVariant)
                            .padding(.top, 2)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                MonthsGrid(filled: math.monthsCompleted, theme: t)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tgContainerBackground(t.surface)
        }
    }
}

/// Сетка месяцев: колонок всегда 12, ряды растут шестилетиями.
private struct MonthsGrid: View {
    let filled: Int
    let theme: WidgetTheme

    private var rows: Int { (filled / 72 + 1) * 6 }

    var body: some View {
        GeometryReader { geo in
            let columns = 12
            let gap: CGFloat = 3
            let dot = min(
                (geo.size.width - CGFloat(columns - 1) * gap) / CGFloat(columns),
                (geo.size.height - CGFloat(rows - 1) * gap) / CGFloat(rows)
            )
            VStack(spacing: gap) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            Circle()
                                .fill(color(for: index))
                                .frame(width: max(dot, 2), height: max(dot, 2))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func color(for index: Int) -> Color {
        if index < filled { return theme.primary }
        if index == filled { return theme.primary.opacity(0.55) }
        return theme.trackOnSurface
    }
}

struct YearGridWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "YearGridWidget4x2Provider", provider: RefreshProvider()) { _ in
            YearGridView().unredacted()
        }
        .configurationDisplayName("Календарь лет")
        .description("Каждый прожитый вместе месяц — точка.")
        .supportedFamilies([.systemMedium])
    }
}
