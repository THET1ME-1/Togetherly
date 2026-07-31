import SwiftUI
import WidgetKit
import UIKit

// MARK: - «Скучаю»
//
// Данные пишет `HomeWidgetService.syncMiss` (`miss_<g>_*`). Тап уходит в
// приложение по `loveapp://miss`, оно и отправляет сигнал партнёру. На Android
// отправка идёт фоновым интентом без открытия приложения, но у iOS фонового
// исполнения для виджетов нет, а обещать отправку и не отправить — хуже, чем
// открыть приложение на секунду.

private struct MissData {
    let myCount: Int
    let partnerCount: Int
    let partnerName: String
    let partnerInitial: String
    let partnerAvatar: UIImage?
    let lastTime: String
    let sentToday: Bool
}

private func loadMiss() -> MissData {
    let s = Store()
    let g = s.latestGroup("miss_latest_group")
    return MissData(
        myCount: s.int("miss_\(g)_my_count"),
        partnerCount: s.int("miss_\(g)_partner_count"),
        partnerName: s.string("miss_\(g)_partner_name"),
        partnerInitial: s.string("miss_\(g)_partner_initial"),
        partnerAvatar: s.uiImage("miss_\(g)_partner_avatar_path"),
        lastTime: s.string("miss_\(g)_last_time"),
        sentToday: s.bool01("miss_\(g)_sent_today")
    )
}

private struct MissSmallView: View {
    let data: MissData
    let t: WidgetTheme

    var body: some View {
        VStack(spacing: 8) {
            HeartShape()
                .fill(t.onPrimary)
                .frame(width: 40, height: 40)
            Text(data.sentToday ? "Отправлено сегодня" : "Скучаю")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(t.onPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !data.lastTime.isEmpty {
                Text(data.lastTime)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(t.onPrimarySoft)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tgContainerBackground(t.primary)
    }
}

private struct MissMediumView: View {
    let data: MissData
    let t: WidgetTheme

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(data.sentToday ? "Уже сказали сегодня" : "Скучаю по тебе")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(t.onPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 8) {
                    counter(value: data.myCount, label: "от меня")
                    counter(value: data.partnerCount,
                            label: data.partnerName.isEmpty ? "в ответ" : "от \(data.partnerName)")
                }

                if !data.lastTime.isEmpty {
                    Text("последний раз \(data.lastTime)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(t.onPrimarySoft)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 8) {
                TgAvatar(image: data.partnerAvatar, initial: data.partnerInitial,
                         background: t.avatarPartner, foreground: t.onTertiaryContainer, size: 44)
                HeartShape()
                    .fill(t.accentOnPrimary)
                    .frame(width: 30, height: 30)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tgContainerBackground(t.primary)
    }

    private func counter(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(t.onPrimary)
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(t.accentOnPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(t.blockOnPrimary)
        )
    }
}

struct MissWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let data = loadMiss()
        let t = WidgetTheme()

        Group {
            if family == .systemSmall {
                MissSmallView(data: data, t: t)
            } else {
                MissMediumView(data: data, t: t)
            }
        }
        .widgetURL(URL(string: "loveapp://miss"))
    }
}

struct MissWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MissWidget4x2Provider", provider: RefreshProvider()) { _ in
            MissWidgetView()
        }
        .configurationDisplayName("Скучаю")
        .description("Сказать «скучаю» с рабочего стола.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
