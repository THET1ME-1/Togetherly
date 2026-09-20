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
//
// Слова и запись чисел приходят готовыми: «Скучаю», «Отправлено» и «Последний
// раз в 20:41» лежали здесь по-русски, а пятизначный счёт печатался как есть.

private struct MissData {
    let myText: String
    let partnerText: String
    let meLabel: String
    let partnerName: String
    let partnerInitial: String
    let partnerAvatar: UIImage?
    let sendLabel: String
    let whenLabel: String
    let todayLabel: String
    let sentToday: Bool
}

private func loadMiss() -> MissData {
    let s = Store()
    let g = s.latestGroup("miss_latest_group")
    return MissData(
        myText: s.string("miss_\(g)_my_text", "\(s.int("miss_\(g)_my_count"))"),
        partnerText: s.string("miss_\(g)_partner_text", "\(s.int("miss_\(g)_partner_count"))"),
        meLabel: s.string("miss_\(g)_me_label"),
        partnerName: s.string("miss_\(g)_partner_name"),
        partnerInitial: s.string("miss_\(g)_partner_initial"),
        partnerAvatar: s.uiImage("miss_\(g)_partner_avatar_path", maxSide: WidgetImage.avatar),
        sendLabel: s.string("miss_\(g)_send_label"),
        whenLabel: s.string("miss_\(g)_when_label"),
        todayLabel: s.string("miss_\(g)_today_label"),
        sentToday: s.bool01("miss_\(g)_sent_today")
    )
}

/// Кегль числа: чем больше знаков, тем мельче. То же правило, что в
/// `missCountSize` (lib/models/miss_widget_spec.dart) и в Kotlin.
private func missCountSize(_ text: String, base: CGFloat) -> CGFloat {
    let size: CGFloat
    switch text.count {
    case 0...2: size = base
    case 3: size = base * 0.86
    case 4: size = base * 0.74
    default: size = base * 0.62
    }
    return max(size, 16)
}

/// Плитка со своим или партнёрским счётом. Обе одной ширины: до 20.09.2026
/// своя была шире, и виджет выглядел перекошенным.
private struct MissTile: View {
    let face: AnyView
    let name: String
    let count: String
    let size: CGFloat
    let background: Color
    let ink: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                face.frame(width: 22, height: 22)
                Text(name)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(ink)
                    .lineLimit(1)
            }
            Text(count)
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .widgetAccentable()
                .foregroundColor(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .tgBlock(background, radius: 18)
    }
}

/// Кнопка во всю ширину: действие тут одно и оно главное.
private struct MissButton: View {
    let label: String
    let sent: Bool
    let background: Color
    let ink: Color
    var height: CGFloat = 44

    var body: some View {
        HStack(spacing: 8) {
            if sent {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(ink)
            } else {
                HeartShape().fill(ink).frame(width: 18, height: 18)
            }
            Text(label)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .tgBlock(background, radius: height / 2)
    }
}

private struct MissSmallView: View {
    let data: MissData
    let t: WidgetTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TgAvatar(image: data.partnerAvatar, initial: data.partnerInitial,
                         background: t.avatarPartner, foreground: t.onTertiaryContainer, size: 26)
                Text(data.partnerName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(t.onSurfaceVariant)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(data.myText)
                    .font(.system(size: missCountSize(data.myText, base: 30),
                                  weight: .heavy, design: .rounded))
                    .widgetAccentable()
                    .foregroundColor(t.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("/ \(data.partnerText)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(t.outline)
                    .lineLimit(1)
            }
            Text(data.whenLabel.isEmpty ? data.todayLabel : data.whenLabel)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(t.outline)
                .lineLimit(1)

            MissButton(label: data.sendLabel, sent: data.sentToday,
                       background: t.primary, ink: t.onPrimary, height: 40)
                .padding(.top, 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tgContainerBackground(t.surface)
    }
}

private struct MissMediumView: View {
    let data: MissData
    let t: WidgetTheme

    var body: some View {
        // Кегль считается по длиннейшему из двух: плитки одного размера, и
        // числа в них должны быть одного роста.
        let longest = data.myText.count >= data.partnerText.count
            ? data.myText : data.partnerText
        let size = missCountSize(longest, base: 30)

        VStack(spacing: 8) {
            HStack(spacing: 10) {
                MissTile(
                    face: AnyView(TgAvatar(image: nil, initial: String(data.meLabel.prefix(1)),
                                           background: t.avatarMine,
                                           foreground: t.onPrimaryContainer, size: 22)),
                    name: data.meLabel,
                    count: data.myText,
                    size: size,
                    background: t.primaryContainer,
                    ink: t.onPrimaryContainer
                )
                MissTile(
                    face: AnyView(TgAvatar(image: data.partnerAvatar,
                                           initial: data.partnerInitial,
                                           background: t.avatarPartner,
                                           foreground: t.onTertiaryContainer, size: 22)),
                    name: data.partnerName,
                    count: data.partnerText,
                    size: size,
                    background: t.tertiaryContainer,
                    ink: t.onTertiaryContainer
                )
            }

            if !data.whenLabel.isEmpty {
                Text(data.whenLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(t.outline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
            }

            MissButton(label: data.sendLabel, sent: data.sentToday,
                       background: t.primary, ink: t.onPrimary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tgContainerBackground(t.surface)
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
            MissWidgetView().unredacted()
        }
        .configurationDisplayName("Скучаю")
        .description("Сказать «скучаю» с рабочего стола.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
