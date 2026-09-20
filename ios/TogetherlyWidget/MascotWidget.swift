import SwiftUI
import WidgetKit

// MARK: - «Маскот на столе»: персонаж пары на экране (21.09.2026)

/// Пиксельный (или нарисованный) персонаж пары рядом с иконками.
///
/// Кадры режет приложение (`lib/services/mascot/mascot_widget_service.dart`) и
/// кладёт в контейнер App Group: `ios_mascot_frame_<day|night|sad>`. Подписи
/// приходят готовыми — у расширения нет локализации, и всё, что оно считает
/// само, рано или поздно оказывается русским или неверным.
///
/// Анимации здесь нет и быть не может: WidgetKit не проигрывает кадры и не
/// пускает виджет обновляться чаще нескольких раз в час. На Android персонаж
/// двигается, на iPhone он меняет облик — день, ночь, грусть и ступень роста.
private struct MascotData {
    private let s = Store()

    var name: String { s.string("ios_mascot_name") }
    var stage: String { s.string("ios_mascot_stage_label") }
    var streak: Int { Int(s.string("ios_mascot_streak")) ?? 0 }
    var streakLabel: String { s.string("ios_mascot_streak_label") }
    var nextLabel: String { s.string("ios_mascot_next_label") }
    var record: Int { Int(s.string("ios_mascot_record")) ?? 0 }
    var recordLabel: String { s.string("ios_mascot_record_label") }
    var percent: Int { Int(s.string("ios_mascot_progress")) ?? 0 }
    var sad: Bool { s.string("ios_mascot_sad") == "1" }

    /// Пиксель-арт нельзя сглаживать: он превращается в мыло. У рисованного
    /// маскота сглаживание, наоборот, нужно.
    var isPixelArt: Bool { s.string("ios_mascot_pixel") != "0" }

    var isSet: Bool { !name.isEmpty && !s.string("ios_mascot_frame_day").isEmpty }

    /// Спит ли персонаж прямо сейчас. Окно задаёт человек в настройках, у
    /// каждого героя своё; −1 значит «ночной сцены нет вовсе».
    var asleep: Bool {
        let from = Int(s.string("ios_mascot_sleep_from")) ?? -1
        let to = Int(s.string("ios_mascot_sleep_to")) ?? -1
        guard from >= 0, to >= 0, from != to else { return false }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return from < to ? (now >= from && now < to) : (now >= from || now < to)
    }

    /// Подпись сна кладётся обеими половинами: ночь наступает без приложения.
    var sleepLabel: String {
        let night = s.string("ios_mascot_sleep_label_night")
        return asleep && !night.isEmpty ? night : s.string("ios_mascot_sleep_label_day")
    }

    /// Грусть старше сна, сон старше дня — тот же порядок, что на Android.
    var framePath: String {
        if sad {
            let path = s.string("ios_mascot_frame_sad")
            if !path.isEmpty { return path }
        }
        if asleep {
            let path = s.string("ios_mascot_frame_night")
            if !path.isEmpty { return path }
        }
        return s.string("ios_mascot_frame_day")
    }
}

/// Кадр персонажа. Кадр приезжает один к одному (48 или 96 точек), поэтому
/// разжимать его незачем — расширению память дороже.
private struct MascotFigure: View {
    let path: String
    let pixelArt: Bool
    let side: CGFloat

    var body: some View {
        if !path.isEmpty, let img = WidgetImage.load(path, maxSide: 320, logAs: "mascot") {
            Image(uiImage: img)
                .resizable()
                .interpolation(pixelArt ? .none : .medium)
                .antialiased(!pixelArt)
                .scaledToFit()
                .frame(width: side, height: side)
        } else {
            Color.clear.frame(width: side, height: side)
        }
    }
}

/// Полоса роста до следующей ступени.
private struct MascotBar: View {
    let percent: Int
    let track: Color
    let fill: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(fill)
                    .frame(width: geo.size.width * CGFloat(min(max(percent, 0), 100)) / 100)
            }
        }
        .frame(height: 6)
    }
}

private struct MascotTile<Content: View>: View {
    let caption: String
    let background: Color
    let ink: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 4) {
            content
            Text(caption)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 6)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MascotWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let theme = WidgetTheme()
        let data = MascotData()

        Group {
            if !data.isSet {
                MascotEmptyView(theme: theme)
            } else {
                switch family {
                case .systemLarge: MascotLargeView(data: data, theme: theme)
                case .systemMedium: MascotMediumView(data: data, theme: theme)
                default: MascotSmallView(data: data, theme: theme)
                }
            }
        }
        .widgetURL(URL(string: "loveapp://mascot"))
        .tgContainerBackground(theme.surface)
    }
}

/// Персонажа ещё не выбрали: виджет обязан назвать себя, иначе человек решит,
/// что он не добавился.
private struct MascotEmptyView: View {
    let theme: WidgetTheme

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "pawprint.circle.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(theme.primary)
            Text("Выберите маскота в приложении")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .padding(14)
    }
}

/// 2×2 «Полка»: имя и ступень сверху, полоса роста снизу.
private struct MascotSmallView: View {
    let data: MascotData
    let theme: WidgetTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(data.name)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(theme.onSurface)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(data.stage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(theme.onTertiaryContainer)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(theme.tertiaryContainer))
                    .lineLimit(1)
            }

            GeometryReader { geo in
                MascotFigure(
                    path: data.framePath,
                    pixelArt: data.isPixelArt,
                    side: min(geo.size.width, geo.size.height)
                )
                .frame(width: geo.size.width, height: geo.size.height)
            }

            MascotBar(percent: data.percent, track: theme.trackOnContainer, fill: theme.primary)
            Text(data.nextLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(theme.onSurfaceVariant)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
    }
}

/// 4×2 «Рост»: персонаж слева, счётчик и полоса справа.
private struct MascotMediumView: View {
    let data: MascotData
    let theme: WidgetTheme

    var body: some View {
        HStack(spacing: 12) {
            MascotFigure(path: data.framePath, pixelArt: data.isPixelArt, side: 88)
                .frame(width: 118, height: 118)
                .background(theme.primaryContainer)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(data.name)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundColor(theme.onSurface)
                    .lineLimit(1)
                Text("\(data.stage) · \(data.streak) \(data.streakLabel)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.onSurfaceVariant)
                    .lineLimit(1)
                Spacer(minLength: 6)
                MascotBar(percent: data.percent, track: theme.trackOnContainer, fill: theme.primary)
                Text(data.nextLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(theme.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

/// 4×4 «Комната»: сцена сверху, три плитки снизу.
private struct MascotLargeView: View {
    let data: MascotData
    let theme: WidgetTheme

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(theme.primaryContainer)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    // Персонаж стоит на кромке пола, а не поверх него.
                    MascotFigure(path: data.framePath, pixelArt: data.isPixelArt, side: 118)
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(theme.trackOnContainer)
                        .frame(height: 44)
                }

                HStack(alignment: .top) {
                    Text("\(data.name) · \(data.stage)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(theme.onSurface)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(theme.surface))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if !data.sleepLabel.isEmpty {
                        Text(data.sleepLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(theme.onTertiaryContainer)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(theme.tertiaryContainer))
                            .lineLimit(1)
                    }
                }
                .padding(12)
            }

            HStack(spacing: 8) {
                MascotTile(
                    caption: data.streakLabel,
                    background: theme.primaryContainer,
                    ink: theme.onSurfaceVariant
                ) {
                    Text("\(data.streak)")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundColor(theme.onPrimaryContainer)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                MascotTile(
                    caption: data.nextLabel,
                    background: theme.primaryContainer,
                    ink: theme.onSurfaceVariant
                ) {
                    MascotBar(
                        percent: data.percent,
                        track: theme.trackOnContainer,
                        fill: theme.primary
                    )
                    .padding(.horizontal, 6)
                }

                MascotTile(
                    caption: data.recordLabel.components(separatedBy: " ").first ?? "",
                    background: theme.primaryContainer,
                    ink: theme.onSurfaceVariant
                ) {
                    Text("\(data.record)")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundColor(theme.onPrimaryContainer)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(height: 76)
        }
        .padding(12)
    }
}

struct MascotWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MascotWidget", provider: RefreshProvider()) { _ in
            MascotWidgetView().unredacted()
        }
        .configurationDisplayName("Маскот на столе")
        .description("Персонаж пары растёт вместе с серией.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
