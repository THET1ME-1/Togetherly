import SwiftUI
import WidgetKit
import UIKit

// MARK: - Парный виджет нового каталога («Вместе»)
//
// Данные пишет `HomeWidgetService.syncTogether` под ключами `together_<g>_*`.
// Дни приходят готовыми, а вот ближайшая веха считается здесь — ровно как в
// `TogetherWidgetProvider.nextMilestone` на Android: сотни дней и годовщины,
// что раньше, то и берём. Считать её в Dart нельзя по той же причине, по
// которой там не считаются дни года: цифра застыла бы до открытия приложения.

private struct TogetherData {
    let days: Int
    let startDate: String
    let names: String
    let anniversary: String
    let myAvatar: UIImage?
    let partnerAvatar: UIImage?
    let myInitial: String
    let partnerInitial: String

    var isEmpty: Bool { days <= 0 && startDate.isEmpty }
}

private func loadTogether() -> TogetherData {
    let s = Store()
    let g = s.latestGroup("together_latest_group")
    return TogetherData(
        days: s.int("together_\(g)_days"),
        startDate: s.string("together_\(g)_start_date"),
        names: s.string("together_\(g)_names"),
        anniversary: s.string("together_\(g)_anniversary"),
        myAvatar: s.uiImage("together_\(g)_my_avatar_path"),
        partnerAvatar: s.uiImage("together_\(g)_partner_avatar_path"),
        myInitial: s.string("together_\(g)_my_initial"),
        partnerInitial: s.string("together_\(g)_partner_initial")
    )
}

/// Ближайшая круглая дата и доля пути до неё.
struct Milestone {
    let target: Int
    let daysLeft: Int
    let percent: Int
    let label: String

    static func next(days: Int) -> Milestone {
        let nextHundred = ((days / 100) + 1) * 100
        let nextYear = ((days / 365) + 1) * 365
        let target = nextHundred <= nextYear ? nextHundred : nextYear
        let prev = nextHundred <= nextYear ? target - 100 : target - 365
        let span = max(target - prev, 1)
        let raw = Int((Double(days - prev) / Double(span) * 100).rounded())
        let label = target % 365 == 0 ? "года" : "\(target) дней"
        return Milestone(
            target: target,
            daysLeft: target - days,
            percent: min(max(raw, 0), 100),
            label: label
        )
    }
}

/// «день / дня / дней» — в русском без этого цифра выглядит машинной.
func daysWord(_ n: Int) -> String {
    let a = n % 100
    let b = n % 10
    if (11...19).contains(a) { return "дней" }
    if b == 1 { return "день" }
    if (2...4).contains(b) { return "дня" }
    return "дней"
}

// MARK: - Виды

private struct TogetherSmallView: View {
    let data: TogetherData
    let t: WidgetTheme

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: -8) {
                TgAvatar(image: data.myAvatar, initial: data.myInitial,
                         background: t.avatarMine, foreground: t.onPrimaryContainer, size: 34)
                TgAvatar(image: data.partnerAvatar, initial: data.partnerInitial,
                         background: t.avatarPartner, foreground: t.onTertiaryContainer, size: 34)
            }
            VStack(spacing: 0) {
                Text("\(data.days)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundColor(t.onPrimary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(daysWord(data.days))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(t.onPrimarySoft)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tgContainerBackground(t.primary)
    }
}

private struct TogetherMediumView: View {
    let data: TogetherData
    let t: WidgetTheme

    var body: some View {
        let milestone = Milestone.next(days: data.days)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    if !data.startDate.isEmpty {
                        Text(data.startDate)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(t.onPrimarySoft)
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(data.days)")
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .foregroundColor(t.onPrimary)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text(daysWord(data.days))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(t.onPrimarySoft)
                    }
                }
                Spacer()
                HeartShape()
                    .fill(t.accentOnPrimary)
                    .frame(width: 34, height: 34)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("До \(milestone.label) — \(milestone.daysLeft) \(daysWord(milestone.daysLeft))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(t.onPrimarySoft)
                        .lineLimit(1)
                    Spacer()
                    Text("\(milestone.percent)%")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(t.onPrimarySoft)
                }
                TgProgressBar(
                    value: Double(milestone.percent) / 100.0,
                    track: t.blockOnPrimary,
                    fill: t.accentOnPrimary
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tgContainerBackground(t.primary)
    }
}

private struct TogetherLargeView: View {
    let data: TogetherData
    let t: WidgetTheme

    var body: some View {
        let milestone = Milestone.next(days: data.days)
        let years = data.days / 365

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TgAvatar(image: data.myAvatar, initial: data.myInitial,
                         background: t.avatarMine, foreground: t.onPrimaryContainer, size: 38)
                TgAvatar(image: data.partnerAvatar, initial: data.partnerInitial,
                         background: t.avatarPartner, foreground: t.onTertiaryContainer, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    if !data.names.isEmpty {
                        Text(data.names)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(t.onPrimary)
                            .lineLimit(1)
                    }
                    if !data.startDate.isEmpty {
                        Text(data.startDate)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(t.onPrimarySoft)
                    }
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("\(data.days)")
                    .font(.system(size: 58, weight: .heavy, design: .rounded))
                    .foregroundColor(t.onPrimary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("\(daysWord(data.days)) вместе")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(t.onPrimarySoft)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("До \(milestone.label)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(t.onPrimarySoft)
                    Spacer()
                    Text("\(milestone.daysLeft) \(daysWord(milestone.daysLeft))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(t.onPrimarySoft)
                }
                TgProgressBar(
                    value: Double(milestone.percent) / 100.0,
                    track: t.blockOnPrimary,
                    fill: t.accentOnPrimary,
                    height: 8
                )
            }

            if years > 0 || !data.anniversary.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if years > 0 {
                            Text("\(years) \(yearsWord(years))")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(t.onTertiaryContainer)
                        }
                        if !data.anniversary.isEmpty {
                            Text(data.anniversary)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(t.onTertiaryContainer.opacity(0.8))
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .padding(12)
                .tgBlock(t.tertiaryContainer, radius: 18)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tgContainerBackground(t.primary)
    }
}

/// «год / года / лет».
func yearsWord(_ n: Int) -> String {
    let a = n % 100
    let b = n % 10
    if (11...19).contains(a) { return "лет" }
    if b == 1 { return "год" }
    if (2...4).contains(b) { return "года" }
    return "лет"
}

struct TogetherWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let data = loadTogether()
        let t = WidgetTheme()

        if data.isEmpty {
            TgEmptyView(text: "Откройте Togetherly, чтобы виджет ожил", theme: t)
        } else {
            switch family {
            case .systemSmall: TogetherSmallView(data: data, t: t)
            case .systemLarge: TogetherLargeView(data: data, t: t)
            default: TogetherMediumView(data: data, t: t)
            }
        }
    }
}

/// Заглушка на случай, когда данных ещё нет: пустые нули выглядят поломкой.
struct TgEmptyView: View {
    let text: String
    let theme: WidgetTheme

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(theme.onSurfaceVariant)
            .multilineTextAlignment(.center)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tgContainerBackground(theme.surfaceContainer)
    }
}

struct TogetherWidget: Widget {
    var body: some WidgetConfiguration {
        // kind совпадает с именем Android-провайдера: Flutter будит виджеты
        // через `HomeWidget.updateWidget(name:)`, и на iOS это имя приезжает в
        // `WidgetCenter.reloadTimelines(ofKind:)`.
        StaticConfiguration(kind: "TogetherWidget4x2Provider", provider: RefreshProvider()) { _ in
            TogetherWidgetView().unredacted()
        }
        .configurationDisplayName("Вместе")
        .description("Дни вместе, ближайшая круглая дата и вы двое.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
