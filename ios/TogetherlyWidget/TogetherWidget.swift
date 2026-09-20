import SwiftUI
import WidgetKit
import UIKit

// MARK: - Парный виджет нового каталога («Вместе»)
//
// Данные пишет `HomeWidgetService.syncTogether` под ключами `together_<g>_*`.
// Дни расширение считает само от метки старта — иначе число застыло бы на дне
// последнего запуска приложения. А вот вехи и все подписи приходят готовыми:
// сотни дней, годовщины и склонения «день / дня / дней» раньше лежали прямо
// здесь, и немец с испанцем читали русские слова.
//
// Подписи нарочно без сегодняшнего числа: его расширение пересчитывает каждый
// день, и фраза с числом протухала бы к утру.

private struct TogetherData {
    let days: Int
    let daysLabel: String
    let startDate: String
    let names: String
    let percent: Int
    let prevTitle: String
    let prevSub: String
    let todayTitle: String
    let todaySub: String
    let nextTitle: String
    let nextSub: String
    let anniversaryTitle: String
    let anniversarySub: String
    let myAvatar: UIImage?
    let partnerAvatar: UIImage?
    let myInitial: String
    let partnerInitial: String

    var isEmpty: Bool { days <= 0 && startDate.isEmpty }
    var hasPrevious: Bool { !prevTitle.isEmpty }
}

private func loadTogether() -> TogetherData {
    let s = Store()
    let g = s.latestGroup("together_latest_group")
    return TogetherData(
        days: s.int("together_\(g)_start_ms") > 0
            ? daysSince(startMs: s.int("together_\(g)_start_ms"))
            : s.int("together_\(g)_days"),
        daysLabel: s.string("together_\(g)_days_label"),
        startDate: s.string("together_\(g)_start_date"),
        names: s.string("together_\(g)_names"),
        percent: s.int("together_\(g)_mile_percent"),
        prevTitle: s.string("together_\(g)_mile_prev_title"),
        prevSub: s.string("together_\(g)_mile_prev_sub"),
        todayTitle: s.string("together_\(g)_mile_today_title"),
        todaySub: s.string("together_\(g)_mile_today_sub"),
        nextTitle: s.string("together_\(g)_mile_next_title"),
        nextSub: s.string("together_\(g)_mile_next_sub"),
        anniversaryTitle: s.string("together_\(g)_mile_anni_title"),
        anniversarySub: s.string("together_\(g)_mile_anni_sub"),
        myAvatar: s.uiImage("together_\(g)_my_avatar_path", maxSide: WidgetImage.avatar),
        partnerAvatar: s.uiImage("together_\(g)_partner_avatar_path", maxSide: WidgetImage.avatar),
        myInitial: s.string("together_\(g)_my_initial"),
        partnerInitial: s.string("together_\(g)_partner_initial")
    )
}

// MARK: - Растр и дорожка

/// Фон растром: точки растут к правому нижнему углу и мельчают к левому
/// верхнему, где лежит число. Та же рябь, что у HalftonePainter в приложении.
struct TgHalftone: View {
    let color: Color

    /// Непрозрачный растр на маленькой ячейке превращается в горошек и спорит
    /// с числом — держим его вполсилы.
    private let dotOpacity: Double = 0.55

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 15
            let maxR: CGFloat = 5.2
            let far = sqrt(size.width * size.width + size.height * size.height)
            var y = step / 2
            while y < size.height {
                var x = step / 2
                while x < size.width {
                    let t = sqrt(x * x + y * y) / far
                    let r = (t - 0.18) * maxR
                    if r >= 0.5 {
                        let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(color.opacity(dotOpacity)))
                    }
                    x += step
                }
                y += step
            }
        }
    }
}

/// Горизонтальная дорожка вех: линия, пройденная часть и отметки.
struct TgTrackLine: View {
    let percent: Int
    let hasPrevious: Bool
    let midStop: Bool
    let track: Color
    let fill: Color
    let ring: Color

    var body: some View {
        Canvas { context, size in
            let pad: CGFloat = 9
            let left = pad
            let right = size.width - pad
            let cy = size.height / 2
            var line = Path()
            line.move(to: CGPoint(x: left, y: cy))
            line.addLine(to: CGPoint(x: right, y: cy))
            context.stroke(line, with: .color(track),
                           style: StrokeStyle(lineWidth: 5, lineCap: .round))

            let here = left + (right - left) * CGFloat(min(max(percent, 0), 100)) / 100
            var done = Path()
            done.move(to: CGPoint(x: left, y: cy))
            done.addLine(to: CGPoint(x: here, y: cy))
            context.stroke(done, with: .color(fill),
                           style: StrokeStyle(lineWidth: 5, lineCap: .round))

            func dot(_ x: CGFloat, _ r: CGFloat, _ c: Color) {
                let rect = CGRect(x: x - r, y: cy - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(c))
            }
            dot(left, 6, hasPrevious ? fill : track)
            if midStop { dot((left + right) / 2, 6, track) }
            dot(right, 6, track)
            // Сегодняшняя отметка крупнее и с обводкой цвета фона: она главная.
            dot(here, 9.5, ring)
            dot(here, 7, fill)
        }
    }
}

/// Вертикальная лента вех для большого размера.
struct TgTrackColumn: View {
    let rows: Int
    let current: Int
    let track: Color
    let fill: Color
    let ring: Color
    let last: Color

    var body: some View {
        Canvas { context, size in
            guard rows > 0 else { return }
            let cx = size.width / 2
            func y(_ i: Int) -> CGFloat {
                size.height * (CGFloat(i) + 0.5) / CGFloat(rows)
            }
            var line = Path()
            line.move(to: CGPoint(x: cx, y: y(0)))
            line.addLine(to: CGPoint(x: cx, y: y(rows - 1)))
            context.stroke(line, with: .color(track),
                           style: StrokeStyle(lineWidth: 4, lineCap: .round))

            if current < rows {
                var done = Path()
                done.move(to: CGPoint(x: cx, y: y(0)))
                done.addLine(to: CGPoint(x: cx, y: y(current)))
                context.stroke(done, with: .color(fill),
                               style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }

            func dot(_ i: Int, _ r: CGFloat, _ c: Color) {
                let rect = CGRect(x: cx - r, y: y(i) - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(c))
            }
            for i in 0..<rows {
                if i == current {
                    dot(i, 9.5, ring)
                    dot(i, 7, fill)
                } else if i == rows - 1 {
                    dot(i, 7, last)
                } else if i < current {
                    dot(i, 7, fill)
                } else {
                    dot(i, 7, track)
                }
            }
        }
    }
}

/// Строка ленты: заголовок и подпись под ним.
private struct TgTrackRow: View {
    let title: String
    let sub: String
    let titleColor: Color
    let subColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(titleColor)
                .lineLimit(1)
            if !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(subColor)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Виды

private struct TogetherSmallView: View {
    let data: TogetherData
    let t: WidgetTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: -8) {
                TgAvatar(image: data.myAvatar, initial: data.myInitial,
                         background: t.avatarMine, foreground: t.onPrimaryContainer, size: 30)
                TgAvatar(image: data.partnerAvatar, initial: data.partnerInitial,
                         background: t.avatarPartner, foreground: t.onTertiaryContainer, size: 30)
            }
            .padding(.bottom, 8)

            Text("\(data.days)")
                .font(.system(size: 42, weight: .heavy, design: .rounded))
                .widgetAccentable()
                .foregroundColor(t.onPrimary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(data.daysLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(t.onPrimarySoft)
                .lineLimit(1)

            Spacer(minLength: 0)

            TgTrackLine(percent: data.percent, hasPrevious: data.hasPrevious,
                        midStop: false, track: t.blockOnPrimary,
                        fill: t.onPrimary, ring: t.primary)
                .frame(height: 22)
            HStack {
                Text(data.prevTitle)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(t.onPrimarySoft)
                    .lineLimit(1)
                Spacer()
                Text(data.nextTitle)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(t.onPrimarySoft)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TgHalftone(color: t.blockOnPrimary))
        .tgContainerBackground(t.primary)
    }
}

private struct TogetherMediumView: View {
    let data: TogetherData
    let t: WidgetTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(data.days)")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .widgetAccentable()
                        .foregroundColor(t.onPrimary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(data.daysLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(t.onPrimarySoft)
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: -8) {
                    TgAvatar(image: data.myAvatar, initial: data.myInitial,
                             background: t.avatarMine, foreground: t.onPrimaryContainer, size: 30)
                    TgAvatar(image: data.partnerAvatar, initial: data.partnerInitial,
                             background: t.avatarPartner, foreground: t.onTertiaryContainer, size: 30)
                }
            }
            if !data.startDate.isEmpty {
                Text(data.startDate)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(t.onPrimarySoft)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            TgTrackLine(percent: data.percent, hasPrevious: data.hasPrevious,
                        midStop: true, track: t.blockOnPrimary,
                        fill: t.onPrimary, ring: t.primary)
                .frame(height: 26)
            HStack(alignment: .top) {
                Text(data.prevTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(t.onPrimarySoft)
                    .lineLimit(1)
                Spacer()
                Text([data.nextTitle, data.nextSub].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(t.onPrimary)
                    .lineLimit(1)
                Spacer()
                Text(data.anniversaryTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(t.onPrimarySoft)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TgHalftone(color: t.blockOnPrimary))
        .tgContainerBackground(t.primary)
    }
}

private struct TogetherLargeView: View {
    let data: TogetherData
    let t: WidgetTheme

    var body: some View {
        let rows = data.hasPrevious ? 4 : 3

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if !data.names.isEmpty {
                    Text(data.names)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(t.onSurfaceVariant)
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: -8) {
                    TgAvatar(image: data.myAvatar, initial: data.myInitial,
                             background: t.avatarMine, foreground: t.onPrimaryContainer, size: 28)
                    TgAvatar(image: data.partnerAvatar, initial: data.partnerInitial,
                             background: t.avatarPartner, foreground: t.onTertiaryContainer, size: 28)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text("\(data.days)")
                    .font(.system(size: 58, weight: .heavy, design: .rounded))
                    .widgetAccentable()
                    .foregroundColor(t.onSurface)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(data.daysLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(t.onSurfaceVariant)
                        .lineLimit(1)
                    if !data.startDate.isEmpty {
                        Text(data.startDate)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(t.outline)
                            .lineLimit(1)
                    }
                }
            }

            HStack(alignment: .top, spacing: 8) {
                TgTrackColumn(rows: rows, current: data.hasPrevious ? 1 : 0,
                              track: t.trackOnSurface, fill: t.primary,
                              ring: t.surface, last: t.tertiaryContainer)
                    .frame(width: 24)
                VStack(spacing: 0) {
                    if data.hasPrevious {
                        TgTrackRow(title: data.prevTitle, sub: data.prevSub,
                                   titleColor: t.onSurface, subColor: t.onSurfaceVariant)
                    }
                    TgTrackRow(title: data.todayTitle, sub: data.todaySub,
                               titleColor: t.onSurface, subColor: t.onSurfaceVariant)
                    TgTrackRow(title: data.nextTitle, sub: data.nextSub,
                               titleColor: t.onSurface, subColor: t.onSurfaceVariant)
                    TgTrackRow(title: data.anniversaryTitle, sub: data.anniversarySub,
                               titleColor: t.onSurface, subColor: t.tertiary)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TgHalftone(color: t.trackOnSurface))
        .tgContainerBackground(t.surface)
    }
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
        .description("Дни вместе, пройденные вехи и ближайшая круглая дата.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
