import SwiftUI
import WidgetKit
import UIKit

// MARK: - Экран блокировки (iOS 16+)
//
// Жалоба тестера: «виджетов на экране блокировки нет, либо я не поняла, как
// они добавляются». Их и правда не было: в бандле не объявлено ни одного
// accessory-семейства, а для экрана блокировки годятся только они.
//
// Данные берём те же, что у больших виджетов: `together_<g>_*` (дни вместе),
// `miss_<g>_*` (счёт «скучаю») и `tgmood_<g>_*` (настроение обоих). Ничего
// нового Flutter писать не должен — эти ключи уже лежат в App Group.
//
// На экране блокировки система рисует виджет одним цветом (accented), поэтому
// цвета темы здесь бессмысленны: нужны крупная цифра, короткая подпись и
// контур. Всё лишнее просто исчезнет.

@available(iOS 16.0, *)
private struct LockDaysData {
    let days: Int
    let names: String
    let anniversary: String
}


/// Сколько календарных дней прошло с даты начала.
///
/// Тот же приём, что у таймера и кольца года: расширение обновляется по
/// своему расписанию и не зависит от того, открывали ли приложение.
func daysSince(startMs: Int, now: Date = Date()) -> Int {
    let cal = Calendar.current
    let from = cal.startOfDay(for: Date(timeIntervalSince1970: Double(startMs) / 1000.0))
    let to = cal.startOfDay(for: now)
    return abs(cal.dateComponents([.day], from: from, to: to).day ?? 0)
}

@available(iOS 16.0, *)
private func loadLockDays() -> LockDaysData {
    let s = Store()
    let g = s.latestGroup("together_latest_group")
    // Дни считаем сами от метки старта: готовое число пишет приложение, а
    // пока оно закрыто, писать некому — и на экране блокировки счётчик
    // застывал на дне последнего запуска. Метки нет (сборка приложения
    // постарше) — берём прежнее число.
    let startMs = s.int("together_\(g)_start_ms")
    let stored = s.int("together_\(g)_days")
    return LockDaysData(
        days: startMs > 0 ? daysSince(startMs: startMs) : stored,
        names: s.string("together_\(g)_names"),
        anniversary: s.string("together_\(g)_anniversary")
    )
}

// MARK: - Дни вместе

@available(iOS 16.0, *)
struct LockDaysView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let data = loadLockDays()
        switch family {
        case .accessoryInline:
            // Одна строка рядом с часами: сюда влезает только короткая фраза.
            Text("Вместе \(data.days) дн.")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(data.days)")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("дней")
                        .font(.system(size: 9, weight: .semibold))
                }
                .padding(4)
            }
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text("Вместе \(data.days) дней")
                    .font(.system(size: 15, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !data.names.isEmpty {
                    Text(data.names)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                } else if !data.anniversary.isEmpty {
                    Text("с \(data.anniversary)")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
            }
        }
    }
}

@available(iOS 16.0, *)
struct LockDaysWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockDaysWidget", provider: RefreshProvider()) { _ in
            LockDaysView().unredacted()
                .widgetURL(URL(string: "loveapp://home"))
                .tgContainerBackground(Color.clear)
        }
        .configurationDisplayName("Вместе · блокировка")
        .description("Сколько дней вы вместе — на экране блокировки.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - «Скучаю»

@available(iOS 16.0, *)
struct LockMissView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = Store()
        let g = s.latestGroup("miss_latest_group")
        let mine = s.int("miss_\(g)_my_count")
        let theirs = s.int("miss_\(g)_partner_count")
        let name = s.string("miss_\(g)_partner_name")

        switch family {
        case .accessoryInline:
            Text("Скучаю \(mine) · \(theirs)")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -1) {
                    Image(systemName: "heart.fill").font(.system(size: 13))
                    Text("\(mine)")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .padding(4)
            }
        default:
            HStack(spacing: 8) {
                Image(systemName: "heart.fill").font(.system(size: 18))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Скучаю")
                        .font(.system(size: 14, weight: .heavy))
                    Text(name.isEmpty
                         ? "от меня \(mine) · в ответ \(theirs)"
                         : "от меня \(mine) · от \(name) \(theirs)")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }
}

@available(iOS 16.0, *)
struct LockMissWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockMissWidget", provider: RefreshProvider()) { _ in
            LockMissView().unredacted()
                // Тап открывает приложение и отправляет импульс — фонового
                // исполнения у виджетов на iOS нет, обещать отправку без
                // открытия нельзя (тот же путь, что у большого «Скучаю»).
                .widgetURL(URL(string: "loveapp://miss"))
                .tgContainerBackground(Color.clear)
        }
        .configurationDisplayName("Скучаю · блокировка")
        .description("Сказать «скучаю» прямо с экрана блокировки.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Настроение обоих

@available(iOS 16.0, *)
struct LockMoodView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = Store()
        let g = s.latestGroup("tgmood_latest_group")
        let mine = s.string("tgmood_\(g)_my_label")
        let theirs = s.string("tgmood_\(g)_partner_label")
        let name = s.string("tgmood_\(g)_partner_name")

        switch family {
        case .accessoryInline:
            Text(theirs.isEmpty ? "Настроение не отмечено" : "\(name.isEmpty ? "Партнёр" : name): \(theirs)")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: theirs.isEmpty ? "face.dashed" : "face.smiling")
                    .font(.system(size: 20))
            }
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text(mine.isEmpty ? "Вы ещё не отметились" : "Я: \(mine)")
                    .font(.system(size: 13, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(theirs.isEmpty
                     ? "\(name.isEmpty ? "Партнёр" : name) молчит"
                     : "\(name.isEmpty ? "Партнёр" : name): \(theirs)")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

@available(iOS 16.0, *)
struct LockMoodWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockMoodWidget", provider: RefreshProvider()) { _ in
            LockMoodView().unredacted()
                .widgetURL(URL(string: "loveapp://mood"))
                .tgContainerBackground(Color.clear)
        }
        .configurationDisplayName("Настроение · блокировка")
        .description("Настроение обоих на экране блокировки.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}
