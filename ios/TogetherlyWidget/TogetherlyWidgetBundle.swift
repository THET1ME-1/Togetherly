import SwiftUI
import WidgetKit

// MARK: - Точка входа расширения

@main
struct TogetherlyWidgetBundle: WidgetBundle {
    // ЗОНД (17.08.2026): бандл урезан до семи базовых виджетов.
    //
    // Прошлые зонды отключали стили поверх main и ничего не дали. Значит либо
    // поломок несколько, либо дело не в стилях вовсе. Здесь не объявлены ни
    // виджеты экрана блокировки, ни конфигурируемые фото (AppIntents), ни новый
    // каталог — остаётся самое простое, что работало в 1.25.0.
    //
    // Появились виджеты в галерее — виноват один из отключённых блоков, и делим
    // дальше. Не появились — причина вне бандла, и искать надо в сборке.
    @WidgetBundleBuilder
    var body: some Widget {
        LoveWidget()
        DaysCounterWidget()
        TimerWidget()
        PetalTimerWidget()
        MoodWidget()
        StreakWidget()
        RelationshipStatsWidget()
    }
}

// MARK: - Общий таймлайн-провайдер

/// Виджеты не держат данные в Entry — каждый View читает свежие данные из
/// App Group в момент отрисовки. Поэтому Entry несёт только дату, а провайдер
/// один на всех. Flutter дёргает `WidgetCenter.reloadTimelines(ofKind:)` через
/// `HomeWidget.updateWidget(name:)` при каждом изменении данных → виджет
/// перерисовывается мгновенно. Дополнительные точки таймлайна держат
/// «дни/часы» актуальными, даже если приложение не открывали.
struct SimpleEntry: TimelineEntry {
    let date: Date
}

struct RefreshProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry { SimpleEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let now = Date()
        var entries: [SimpleEntry] = []
        // Обновляемся каждые 15 минут в течение часа, затем система запросит ещё.
        for offset in stride(from: 0, through: 45, by: 15) {
            if let d = Calendar.current.date(byAdding: .minute, value: offset, to: now) {
                entries.append(SimpleEntry(date: d))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Фон карточки (совместимо с iOS 14–17+)

extension View {
    /// Единый фон-градиент. На iOS 17+ используется `containerBackground`
    /// (обязателен, иначе виджет обрезается), на ранних — ZStack.
    @ViewBuilder
    func widgetCardBackground(_ accent: Color) -> some View {
        let gradient = LinearGradient(
            colors: [Palette.cardBackground, accent.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        if #available(iOS 17.0, *) {
            self.modifier(TgWidgetCardBackground(gradient: gradient))
        } else {
            ZStack {
                gradient
                self
            }
        }
    }
}

/// Тонированный режим («Прозрачные» на экране «Домой») красит содержимое одним
/// цветом поверх нашего градиента, и виджет читался как пустая белая форма.
/// Там фон отдаём системе.
@available(iOS 17.0, *)
private struct TgWidgetCardBackground: ViewModifier {
    @Environment(\.widgetRenderingMode) private var mode
    let gradient: LinearGradient

    @ViewBuilder
    func body(content: Content) -> some View {
        if mode == .fullColor {
            content.containerBackground(for: .widget) { gradient }
        } else {
            content.containerBackground(.clear, for: .widget)
        }
    }
}
