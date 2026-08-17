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
                ring(math: math, t: t, side: 92, showCaption: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tgContainerBackground(t.primary)
            } else {
                HStack(spacing: 16) {
                    ring(math: math, t: t, side: 104, showCaption: false)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(yearOrdinal(math.yearsCompleted + 1))
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(t.accentOnPrimary)
                            .lineLimit(1)
                        Text("Ещё \(math.daysToNextAnniversary) \(daysWord(math.daysToNextAnniversary))")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(t.onPrimary)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            tile(label: "МЕСЯЦЕВ", value: "\(math.monthsCompleted)", t: t)
                            tile(label: "ВОСПОМИНАНИЙ", value: "\(data.memories)", t: t)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tgContainerBackground(t.primary)
            }
        }
    }

    /// Кольцо рисуется дугой SwiftUI — на Android под это пришлось заводить
    /// bitmap, потому что дуг у RemoteViews нет.
    private func ring(math: YearMath, t: WidgetTheme, side: CGFloat, showCaption: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(t.blockOnPrimary, lineWidth: 9)
            Circle()
                .trim(from: 0, to: max(0.004, math.ringProgress))
                .stroke(t.accentOnPrimary, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(math.daysTotal)")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(t.onPrimary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(showCaption ? "\(daysWord(math.daysTotal)) вместе" : daysWord(math.daysTotal))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(t.onPrimarySoft)
                    .lineLimit(1)
            }
            .padding(10)
        }
        .frame(width: side, height: side)
    }

    private func tile(label: String, value: String, t: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .heavy))
                .foregroundColor(t.accentOnPrimary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(t.onPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .tgBlock(t.blockOnPrimary, radius: 14)
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
