import SwiftUI
import WidgetKit

// MARK: - Обратный отсчёт до события
//
// Данные пишет `HomeWidgetService.syncCountdownEvents` (`tgcd_<g>_*`): список
// ближайших событий с их моментом. Остаток считается здесь по часам телефона
// на каждой записи ленты — правило `countdownAt` в
// `lib/models/countdown_widget.dart`. Готовые числа приложение писало только с
// экрана «Виджеты», и виджет застывал (обращение 197); они остались запасом
// для данных, записанных старой сборкой.

private struct CountdownData {
    let title: String
    let date: String
    let days: Int
    let hours: Int
    let minutes: Int
    let percent: Int

    var isEmpty: Bool { title.isEmpty && date.isEmpty }
}

private func loadCountdown(now: Date = Date()) -> CountdownData {
    let s = Store()
    let g = s.latestGroup("tgcd_latest_group")
    if let raw = s.stringOrNil("tgcd_\(g)_events") {
        let fromMs = Int64(s.string("tgcd_\(g)_from_ms")) ?? 0
        return countdownTick(raw: raw, nowMs: Int64(now.timeIntervalSince1970 * 1000), fromMs: fromMs)
    }
    return CountdownData(
        title: s.string("tgcd_\(g)_title"),
        date: s.string("tgcd_\(g)_date"),
        days: s.int("tgcd_\(g)_days"),
        hours: s.int("tgcd_\(g)_hours"),
        minutes: s.int("tgcd_\(g)_minutes"),
        percent: s.int("tgcd_\(g)_percent")
    )
}

/// Остаток до первого ненаступившего события; все прошли — пустые данные.
private func countdownTick(raw: String, nowMs: Int64, fromMs: Int64) -> CountdownData {
    let empty = CountdownData(title: "", date: "", days: 0, hours: 0, minutes: 0, percent: 0)
    guard let bytes = raw.data(using: .utf8),
          let list = try? JSONSerialization.jsonObject(with: bytes) as? [[String: Any]]
    else { return empty }
    var at = Int64.max
    var title = ""
    var date = ""
    for item in list {
        guard let t = (item["at"] as? NSNumber)?.int64Value else { continue }
        if t > nowMs && t < at {
            at = t
            title = item["t"] as? String ?? ""
            date = item["d"] as? String ?? ""
        }
    }
    if at == Int64.max { return empty }
    let leftMin = (at - nowMs) / 60000
    let dayMin: Int64 = 24 * 60
    let from = (fromMs > 0 && fromMs < at) ? fromMs : at - 30 * dayMin * 60000
    let start = from > nowMs ? nowMs : from
    let total = at - start
    let passed = nowMs - start
    let percent = total <= 0 ? 100 : min(100, max(0, Int((Double(passed) * 100 / Double(total)).rounded())))
    return CountdownData(
        title: title,
        date: date,
        days: Int(leftMin / dayMin),
        hours: Int((leftMin % dayMin) / 60),
        minutes: Int(leftMin % 60),
        percent: percent
    )
}

private struct CountdownView: View {
    var now: Date = Date()
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let data = loadCountdown(now: now)
        let t = WidgetTheme()

        if data.isEmpty {
            TgEmptyView(text: "Заведите событие — до него и будет счёт", theme: t)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(data.title)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(t.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if !data.date.isEmpty {
                    Text(data.date)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(t.onPrimaryContainer)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(t.primaryContainer))
                }

                HStack(spacing: 8) {
                    tile(value: data.days, label: daysWord(data.days), t: t)
                    if family != .systemSmall {
                        tile(value: data.hours, label: "часов", t: t)
                        tile(value: data.minutes, label: "минут", t: t)
                    }
                }

                Spacer(minLength: 0)

                TgProgressBar(
                    value: Double(data.percent) / 100.0,
                    track: t.trackOnSurface,
                    fill: t.primary
                )
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tgContainerBackground(t.surface)
        }
    }

    private func tile(value: Int, label: String, t: WidgetTheme) -> some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .widgetAccentable()
                .foregroundColor(t.onSurface)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(t.onSurfaceVariant)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .tgBlock(t.surfaceContainer, radius: 16)
    }
}

struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CountdownWidget2x2Provider", provider: RefreshProvider()) { entry in
            CountdownView(now: entry.date).unredacted()
        }
        .configurationDisplayName("Обратный отсчёт")
        .description("Сколько осталось до вашего события.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
