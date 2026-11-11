import SwiftUI
import WidgetKit

// MARK: - Чем заняты
//
// Две комнатки: слева я, справа партнёр, в каждой Ту показывает, чем человек
// сейчас занят. Данные кладёт `DoingService` (Dart): `doing_<пара>_my_id`,
// `_text`, `_at`, `_wall`, `_avatar` и то же с `partner`; справочник кадров
// `doing_art_<id>` и подписей `doing_name_<id>`.
//
// Виджет неподвижен: двигаться WidgetKit не даёт. Занятие старше трёх часов
// гаснет здесь же, без приложения: Ту возвращается в покой, плашка с
// названием пропадает. Тап уводит в приложение по `loveapp://doing`, где
// открывается выбор занятия.

/// Три часа до покоя. То же число в `kDoingFades` (Dart) и в Kotlin.
private let doingFadesMs: Double = 10_800_000

private let doingPaper = Color(hex: 0xFFFDFC)
private let doingPaperDark = Color(hex: 0xFFF1F3)
private let doingPen = Color(hex: 0x4B2A31)
private let doingHeart = Color(hex: 0xE8556F)

/// Одна половина: что показывать прямо сейчас.
private struct DoingHalf {
    let wall: Color
    let floor: Color
    let art: UIImage?
    let label: String
    let time: String
    let avatar: UIImage?
    let avatarColor: Color
}

private func doingHex(_ css: String) -> UInt32? {
    var text = css.trimmingCharacters(in: .whitespaces)
    if text.hasPrefix("#") { text.removeFirst() }
    guard text.count == 6 else { return nil }
    return UInt32(text, radix: 16)
}

/// Цвет пола и горошка по цвету стены — то же правило, что `roomFloor` в
/// `lib/models/doing.dart`: у белой стены чуть темнее, у светлой светлее, у
/// тёмной светлее на малую долю.
private func doingFloor(_ wall: UInt32) -> UInt32 {
    func linear(_ channel: UInt32) -> Double {
        let v = Double(channel) / 255.0
        return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    let r = (wall >> 16) & 0xFF, g = (wall >> 8) & 0xFF, b = wall & 0xFF
    let brightness = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    func mix(_ to: UInt32, _ share: Double) -> UInt32 {
        func channel(_ a: UInt32, _ c: UInt32) -> UInt32 {
            UInt32((Double(a) + (Double(c) - Double(a)) * share).rounded())
        }
        return (channel(r, (to >> 16) & 0xFF) << 16) | (channel(g, (to >> 8) & 0xFF) << 8) | channel(b, to & 0xFF)
    }
    if brightness > 0.88 { return mix(0x8F7F86, 0.14) }
    if brightness > 0.4 { return mix(0xFFFFFF, 0.55) }
    return mix(0xFFFFFF, 0.16)
}

private func loadDoingHalf(_ s: Store, group: String, side: String, themeRole: String, themeFallback: UInt32, avatarColor: Color, now: Double) -> DoingHalf {
    let prefix = "doing_\(group)_\(side)"
    let id = s.string("\(prefix)_id")
    let text = s.string("\(prefix)_text")
    let at = Double(s.string("\(prefix)_at")) ?? 0
    let wall = doingHex(s.string("\(prefix)_wall")) ?? doingHex(s.string("wtheme_\(themeRole)")) ?? themeFallback

    // Занятие старше трёх часов гаснет: Ту в покое, названия и времени нет.
    let alive = !id.isEmpty && now - at < doingFadesMs
    var label = ""
    if alive { label = id == "own" ? text : s.string("doing_name_\(id)") }

    var art: UIImage? = nil
    if alive && id != "own" { art = s.uiImage("doing_art_\(id)", maxSide: 480) }
    if art == nil { art = s.uiImage("doing_art_idle", maxSide: 480) }

    var time = ""
    if alive && at > 0 {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        time = formatter.string(from: Date(timeIntervalSince1970: at / 1000))
    }
    return DoingHalf(
        wall: Color(hex: wall),
        floor: Color(hex: doingFloor(wall)),
        art: art,
        label: label,
        time: time,
        avatar: s.uiImage("\(prefix)_avatar", maxSide: 200),
        avatarColor: avatarColor
    )
}

/// Скругление только внутренних углов половины: внешние режет сам виджет.
private struct DoingInnerCorners: Shape {
    let radius: CGFloat
    let mine: Bool

    func path(in rect: CGRect) -> Path {
        let corners: UIRectCorner = mine ? [.topRight, .bottomRight] : [.topLeft, .bottomLeft]
        return Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

/// Бумажная плашка с тонким контуром: без него на белой стене её не видно.
private struct DoingChip<Content: View>: View {
    let paper: Color
    let u: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(height: 8 * u)
            .background(Capsule().fill(paper))
            .overlay(Capsule().stroke(doingPen.opacity(0.12), lineWidth: 0.35 * u))
    }
}

private struct DoingRoom: View {
    let half: DoingHalf
    let mine: Bool
    let paper: Color
    let u: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                half.wall

                // Горошек по стене и мягкий пол.
                Canvas { context, size in
                    let step = 6.2 * u
                    var y = 2 * u + step / 2
                    while y < size.height {
                        var x = 1.4 * u + step / 2
                        while x < size.width {
                            context.fill(Path(ellipseIn: CGRect(x: x - 0.85 * u, y: y - 0.85 * u, width: 1.7 * u, height: 1.7 * u)), with: .color(half.floor))
                            x += step
                        }
                        y += step
                    }
                    let floor = CGRect(x: -0.14 * size.width, y: size.height - 11.5 * u, width: size.width * 1.28, height: 22 * u)
                    context.fill(Path(ellipseIn: floor), with: .color(half.floor))
                }

                // Кадр занятия занимает верх половины.
                if let art = half.art {
                    VStack(spacing: 0) {
                        // Без полного цвета тонированная тема рисует Ту силуэтом.
                        Image(uiImage: art)
                            .resizable()
                            .tgFullColorImage()
                            .scaledToFit()
                            .frame(width: min(37.4 * u, geo.size.height - 5.6 * u), height: min(37.4 * u, geo.size.height - 5.6 * u))
                            .padding(.top, 0.4 * u)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                }

                // Нижняя строка: аватарка со временем во внешнем углу, рядом занятие.
                HStack(spacing: 0.9 * u) {
                    if !mine { Spacer(minLength: 0) }
                    if !mine && !half.label.isEmpty { labelChip }
                    whoChip
                    if mine && !half.label.isEmpty { labelChip }
                    if mine { Spacer(minLength: 0) }
                }
                .padding(.horizontal, 1.6 * u)
                .padding(.bottom, 2.2 * u)
            }
        }
        .clipShape(DoingInnerCorners(radius: 2.6 * u, mine: mine))
    }

    private var whoChip: some View {
        DoingChip(paper: paper, u: u) {
            HStack(spacing: u) {
                if !mine && !half.time.isEmpty { timeText.padding(.leading, 1.3 * u) }
                avatar
                if mine && !half.time.isEmpty { timeText.padding(.trailing, 1.3 * u) }
            }
            .padding(0.7 * u)
        }
        .fixedSize()
    }

    private var timeText: some View {
        Text(half.time)
            .font(.system(size: 3 * u, weight: .semibold))
            .foregroundColor(doingPen)
    }

    private var labelChip: some View {
        DoingChip(paper: paper, u: u) {
            Text(half.label)
                .font(.system(size: 3.05 * u, weight: .bold))
                .foregroundColor(doingPen)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 2.1 * u)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        let side = 6.6 * u
        if let photo = half.avatar {
            Image(uiImage: photo)
                .resizable()
                .tgFullColorImage()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipShape(Circle())
        } else {
            // Фото в профиле нет: кружок с силуэтом.
            ZStack {
                Circle().fill(half.avatarColor)
                Image(systemName: "person.fill")
                    .font(.system(size: 3.6 * u))
                    .foregroundColor(paper)
            }
            .frame(width: side, height: side)
        }
    }
}

private struct DoingWidgetView: View {
    var body: some View {
        let s = Store()
        let theme = WidgetTheme()
        let group = s.latestGroup("doing_latest_group")
        let now = Date().timeIntervalSince1970 * 1000
        let paper = theme.isDark ? doingPaperDark : doingPaper
        let my = loadDoingHalf(s, group: group, side: "my", themeRole: "primaryContainer", themeFallback: 0xE9DDFF, avatarColor: theme.color("avatarMine", Color(hex: 0xD0BCFF)), now: now)
        let partner = loadDoingHalf(s, group: group, side: "partner", themeRole: "tertiaryContainer", themeFallback: 0xFFD9E2, avatarColor: theme.color("avatarPartner", Color(hex: 0xFFD8E4)), now: now)

        GeometryReader { geo in
            // Единица — сотая доля ширины, как в макете и на Android.
            let u = geo.size.width / 100
            ZStack {
                HStack(spacing: 1.1 * u) {
                    DoingRoom(half: my, mine: true, paper: paper, u: u)
                    DoingRoom(half: partner, mine: false, paper: paper, u: u)
                }
                // Сердце на стыке половин.
                ZStack {
                    Circle().fill(paper)
                    Circle().stroke(doingPen.opacity(0.12), lineWidth: 0.35 * u)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 4.6 * u))
                        .foregroundColor(doingHeart)
                }
                .frame(width: 9.6 * u, height: 9.6 * u)
            }
        }
        .tgContainerBackground(paper)
        .widgetURL(URL(string: "loveapp://doing"))
    }
}

struct DoingWidget: Widget {
    var body: some WidgetConfiguration {
        // kind — имя Android-провайдера: Flutter будит виджет одним вызовом
        // `HomeWidget.updateWidget(name:)` на обеих платформах.
        StaticConfiguration(kind: "DoingWidgetProvider", provider: RefreshProvider()) { _ in
            DoingWidgetView().unredacted()
        }
        .configurationDisplayName("Чем заняты")
        .description("Чем сейчас занят каждый из вас: Ту показывает сам.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
