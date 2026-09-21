import SwiftUI
import WidgetKit

// MARK: - «Рисунок на столе»: общий холст пары (21.09.2026)

/// Виджет — это сам холст, без подписей и рамок.
///
/// Картинку рисует приложение (`lib/services/canvas/canvas_widget_service.dart`)
/// тем же художником, что и плитки галереи, и кладёт её в контейнер App Group
/// под ключом `ios_canvas_path`. Штрихи живут в Postgres, и собрать их у
/// расширения нет ни сессии, ни времени.
///
/// Выбора холста здесь нет: показываем тот, который трогали последним.
/// Конфигурируемые виджеты в этом проекте уже пробовали — на iPhone тестера
/// они рисовались чёрными и не доходили даже до таймлайна (см. PhotoWidgets).
/// Рисовать прямо в виджете iOS тоже нельзя: код расширения не выполняется,
/// интерактив ограничен кнопками AppIntent. Тап открывает холст в приложении.
private struct CanvasWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let theme = WidgetTheme()
        let store = Store()
        let path = store.string("ios_canvas_path")
        let canvasId = store.string("ios_canvas_id")

        GeometryReader { geo in
            // Картинка уже нарисована под виджет: разжимать её крупнее незачем,
            // расширению память дороже.
            let side = min(1100, max(geo.size.width, geo.size.height) * 3)
            if !path.isEmpty,
               let img = WidgetImage.load(
                   path,
                   maxSide: side,
                   logAs: "canvas",
                   family: WidgetRenderLog.familyName(family)
               ) {
                Image(uiImage: img)
                    .resizable()
                    .tgFullColorImage()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "paintbrush.pointed.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(theme.primary)
                    Text("Нарисуйте что-нибудь вдвоём")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                }
                .padding(14)
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .widgetURL(URL(string: canvasId.isEmpty
            ? "loveapp://draw"
            : "loveapp://draw?canvas=\(canvasId)"))
        .tgContainerBackground(theme.surface)
    }
}

struct CanvasWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CanvasWidget", provider: RefreshProvider()) { _ in
            CanvasWidgetView().unredacted()
        }
        .configurationDisplayName("Рисунок на столе")
        .description("Общий холст пары рядом с иконками.")
        // Широкого прямоугольника здесь нет намеренно: рисунки вертикальные,
        // и от листа 4:5 в нём осталась бы узкая полоса поперёк рисунка.
        // Вертикального размера WidgetKit не даёт вовсе — он есть только на
        // Android (2×3).
        .supportedFamilies([.systemSmall, .systemLarge])
        // Рисунок идёт под край: системные поля iOS 17 оставили бы рамку.
        .contentMarginsDisabled()
    }
}
