import SwiftUI
import WidgetKit

// MARK: - Плитки настроения
//
// Данные пишет `HomeWidgetService.syncMoodTiles` (`tgmood_<g>_*`), неделя
// приезжает строкой «моё/партнёра» через запятую — home_widget умеет класть
// только скаляры.
//
// Маленький размер — три кнопки выбора: тап уходит в приложение по
// `loveapp://mood?id=<id>`, и отметка ставится там. На Android то же действие
// выполняет фоновый интент; на iPhone фонового исполнения у виджетов нет, и
// открытие приложения — единственный честный путь.

private let moodGood = "happy"
private let moodOk = "no_emotion"
private let moodBad = "sad"

private struct MoodTilesData {
    let myLabel: String
    let myId: String
    let partnerLabel: String
    let partnerName: String
    let week: [(mine: Int, partner: Int)]
    let matched: Int
}

private func loadMoodTiles() -> MoodTilesData {
    let s = Store()
    let g = s.latestGroup("tgmood_latest_group")
    let raw = s.string("tgmood_\(g)_week")
    let week = raw.split(separator: ",").map { pair -> (mine: Int, partner: Int) in
        let parts = pair.split(separator: "/").map(String.init)
        let a = parts.count > 0 ? (Int(parts[0]) ?? -1) : -1
        let b = parts.count > 1 ? (Int(parts[1]) ?? -1) : -1
        return (mine: a, partner: b)
    }
    return MoodTilesData(
        myLabel: s.string("tgmood_\(g)_my_label"),
        myId: s.string("tgmood_\(g)_my_id"),
        partnerLabel: s.string("tgmood_\(g)_partner_label"),
        partnerName: s.string("tgmood_\(g)_partner_name"),
        week: week,
        matched: s.int("tgmood_\(g)_matched")
    )
}

// MARK: - Маленький размер: две строки и три кнопки

private struct MoodTilesSmallView: View {
    let data: MoodTilesData
    let t: WidgetTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("НАСТРОЕНИЕ")
                .font(.system(size: 8, weight: .heavy))
                .foregroundColor(t.onSurfaceVariant)

            line(dot: data.myLabel.isEmpty ? t.outline : t.primary,
                 text: data.myLabel.isEmpty ? "Я · не отмечено" : "Я · \(data.myLabel)")
            line(dot: data.partnerLabel.isEmpty ? t.outline : t.avatarPartner,
                 text: {
                     let name = data.partnerName.isEmpty ? "Партнёр" : data.partnerName
                     return data.partnerLabel.isEmpty ? "\(name) · не отмечено"
                                                      : "\(name) · \(data.partnerLabel)"
                 }())

            Spacer(minLength: 0)

            // На маленьком размере WidgetKit не различает отдельные ссылки —
            // тап всегда уходит в `widgetURL`. Поэтому кнопки тут показывают
            // выбранное, а отметку человек ставит в приложении.
            HStack(spacing: 6) {
                tile(id: moodGood, symbol: "😊")
                tile(id: moodOk, symbol: "😐")
                tile(id: moodBad, symbol: "😔")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tgContainerBackground(t.surface)
        .widgetURL(URL(string: "loveapp://mood"))
    }

    private func line(dot: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(t.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func tile(id: String, symbol: String) -> some View {
        let active = id == data.myId
        return Text(symbol)
            .font(.system(size: 17))
            .widgetAccentable()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .tgBlock(active ? t.primaryContainer : t.surfaceContainer, radius: 14)
    }
}

// MARK: - Средний размер: неделя столбиками

private struct MoodTilesMediumView: View {
    let data: MoodTilesData
    let t: WidgetTheme

    private let dayNames = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("НАСТРОЕНИЕ ЗА НЕДЕЛЮ")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundColor(t.onSurfaceVariant)
                Spacer()
                if data.matched > 0 {
                    Text("совпало \(data.matched) из 7")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(t.outline)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(t.surfaceContainer)
                            HStack(alignment: .bottom, spacing: 2) {
                                bar(percent: value(index)?.mine ?? -1, color: t.primary)
                                bar(percent: value(index)?.partner ?? -1, color: t.avatarPartner)
                            }
                            .padding(3)
                        }
                        .frame(height: 52)
                        Text(dayNames[index])
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(t.outline)
                    }
                }
            }

            Spacer(minLength: 0)

            // Средний размер уже различает отдельные ссылки, поэтому отметка
            // ставится в одно касание: тап открывает приложение по
            // `loveapp://mood?id=<id>`, и запись идёт там. Фонового исполнения
            // у виджетов iOS нет, обещать отправку «без открытия» нельзя.
            HStack(spacing: 8) {
                pick(id: moodGood, symbol: "😊", label: "хорошо")
                pick(id: moodOk, symbol: "😐", label: "нормально")
                pick(id: moodBad, symbol: "😔", label: "тяжело")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tgContainerBackground(t.surface)
    }

    private func pick(id: String, symbol: String, label: String) -> some View {
        let active = id == data.myId
        return Link(destination: URL(string: "loveapp://mood?id=\(id)")!) {
            HStack(spacing: 5) {
                Text(symbol).font(.system(size: 14))
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(active ? t.onPrimaryContainer : t.onSurfaceVariant)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .tgBlock(active ? t.primaryContainer : t.surfaceContainer, radius: 14)
        }
    }

    private func value(_ index: Int) -> (mine: Int, partner: Int)? {
        index < data.week.count ? data.week[index] : nil
    }

    /// -1 означает «в этот день никто не отмечался» — столбика нет вовсе.
    @ViewBuilder
    private func bar(percent: Int, color: Color) -> some View {
        if percent >= 0 {
            GeometryReader { geo in
                VStack {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color)
                        .frame(height: max(3, geo.size.height * CGFloat(percent) / 100.0))
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            Color.clear.frame(maxWidth: .infinity)
        }
    }
}

struct MoodTilesWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let data = loadMoodTiles()
        let t = WidgetTheme()

        if family == .systemSmall {
            MoodTilesSmallView(data: data, t: t)
        } else {
            MoodTilesMediumView(data: data, t: t)
        }
    }
}

struct MoodTilesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MoodTilesWidget2x2Provider", provider: RefreshProvider()) { _ in
            MoodTilesWidgetView().unredacted()
        }
        .configurationDisplayName("Настроение — плитки")
        .description("Отметить день в одно касание и увидеть неделю.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
