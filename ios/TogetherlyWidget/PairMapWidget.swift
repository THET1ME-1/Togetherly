import SwiftUI
import WidgetKit

// MARK: - «Где мы»: карта на двоих (19.09.2026)

/// Виджет с картой пары: подложка в цветах темы (или глобус, если вы далеко),
/// шарики с аватарками, дуга между людьми и расстояние прямо на ней.
///
/// Живую карту WidgetKit не покажет, поэтому картинку целиком рисует
/// приложение (`lib/services/map/pair_map_widget_service.dart`) и кладёт в
/// контейнер App Group — путь под ключом `ios_map_<small|medium|large>_path`.
/// Приложение перерисовывает её при каждом входе и по тихому пушу, а потом
/// зовёт `reloadTimelines(ofKind: "PairMapWidget")`. Нажатие открывает карту.
private struct PairMapWidgetView: View {
    @Environment(\.widgetFamily) private var family

    private var key: String {
        switch family {
        case .systemSmall: return "ios_map_small_path"
        case .systemLarge: return "ios_map_large_path"
        default: return "ios_map_medium_path"
        }
    }

    /// Имя файла в общем контейнере: `mapw_<размер>_<номер>.png.jpg`
    /// (его кладёт Dart через мост App Group).
    private var filePrefix: String {
        switch family {
        case .systemSmall: return "mapw_s_"
        case .systemLarge: return "mapw_l_"
        default: return "mapw_m_"
        }
    }

    /// Свежая картинка прямо из общего контейнера — на случай, когда ключ пуст
    /// или указывает на файл, которого уже нет. Ключ пишет приложение, и если
    /// запись не дошла, виджет оставался с заглушкой при готовой картинке под
    /// боком (разбор 21.09.2026: за всю историю журнала карта не нарисовалась
    /// на iPhone ни разу).
    private func pathFromContainer() -> String {
        guard let dir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.id
        )?.appendingPathComponent("widget_media", isDirectory: true) else { return "" }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let mine = files.filter { $0.hasPrefix(filePrefix) }.sorted()
        guard let last = mine.last else { return "" }
        return dir.appendingPathComponent(last).path
    }

    /// Путь к картинке: сперва ключ от приложения, затем поиск в контейнере.
    /// Вычисляется вне `body`: там ViewBuilder, и обычным операторам не место.
    private var imagePath: String {
        let stored = Store().string(key)
        if !stored.isEmpty, FileManager.default.fileExists(atPath: stored) {
            return stored
        }
        let fallback = pathFromContainer()
        WidgetRenderLog.write(
            family: WidgetRenderLog.familyName(family),
            widget: "map",
            fields: [
                "ключ": stored.isEmpty ? "пусто" : "файла нет",
                "контейнер": fallback.isEmpty ? "пусто" : "нашлась",
            ]
        )
        return fallback
    }

    var body: some View {
        let path = imagePath
        let theme = WidgetTheme()
        GeometryReader { geo in
            // Картинка уже нарисована под размер виджета и не крупнее тысячи
            // точек: больше разжимать незачем, памяти у расширения мало.
            let side = min(1100, max(geo.size.width, geo.size.height) * 3)
            if !path.isEmpty,
               let img = WidgetImage.load(
                   path,
                   maxSide: side,
                   logAs: "map",
                   family: WidgetRenderLog.familyName(family)
               ) {
                Image(uiImage: img)
                    .resizable()
                    .tgFullColorImage()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                // Приложение ещё ни разу не рисовало карту: откроют — появится.
                VStack(spacing: 6) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(theme.primary)
                    Text("Откройте Togetherly — карта нарисуется")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                }
                .padding(14)
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .widgetURL(URL(string: "loveapp://map"))
        .tgContainerBackground(theme.surfaceContainer)
    }
}

struct PairMapWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PairMapWidget", provider: RefreshProvider()) { _ in
            PairMapWidgetView().unredacted()
        }
        .configurationDisplayName("Где мы")
        .description("Карта на двоих и расстояние между вами.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        // Карта идёт под край: системные поля iOS 17 оставили бы рамку.
        .contentMarginsDisabled()
    }
}
