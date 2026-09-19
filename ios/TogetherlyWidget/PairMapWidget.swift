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

    var body: some View {
        let path = Store().string(key)
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
