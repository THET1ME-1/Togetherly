import SwiftUI
import WidgetKit

// MARK: - Обратный отсчёт до события
//
// Данные пишет `HomeWidgetService.syncCountdown` (`tgcd_<g>_*`). Дни, часы и
// минуты приезжают посчитанными — так же, как на Android: событие у пары одно,
// и пересчитывать его на устройстве незачем, приложение освежает виджет само.

private struct CountdownData {
    let title: String
    let date: String
    let days: Int
    let hours: Int
    let minutes: Int
    let percent: Int

    var isEmpty: Bool { title.isEmpty && date.isEmpty }
}

private func loadCountdown() -> CountdownData {
    let s = Store()
    let g = s.latestGroup("tgcd_latest_group")
    return CountdownData(
        title: s.string("tgcd_\(g)_title"),
        date: s.string("tgcd_\(g)_date"),
        days: s.int("tgcd_\(g)_days"),
        hours: s.int("tgcd_\(g)_hours"),
        minutes: s.int("tgcd_\(g)_minutes"),
        percent: s.int("tgcd_\(g)_percent")
    )
}

private struct CountdownView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let data = loadCountdown()
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
        StaticConfiguration(kind: "CountdownWidget2x2Provider", provider: RefreshProvider()) { _ in
            CountdownView()
        }
        .configurationDisplayName("Обратный отсчёт")
        .description("Сколько осталось до вашего события.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
