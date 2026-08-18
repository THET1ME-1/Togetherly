import SwiftUI
import WidgetKit

// MARK: - Точка входа расширения

@main
struct TogetherlyWidgetBundle: WidgetBundle {
    // Разбито на под-блоки: один @WidgetBundleBuilder-блок поддерживает не
    // более 10 виджетов, а у нас их 22.
    //
    // НИ ОДНОГО `if #available` здесь быть не может — ни отдельным свойством,
    // ни рядом с безусловными виджетами. Каждая такая ветка компилируется в
    // `WidgetBundleBuilder.buildLimitedAvailability`, и расширение падает
    // внутри неё с SIGTRAP, когда chronod запускает его за списком виджетов.
    // Дескрипторы не приходят, и в галерее пропадают ВСЕ виджеты, а не только
    // условные. Ровно с этого люди пишут «нажимаю плюс, а приложения нет».
    //
    // Стек падения, снятый с релизной сборки расширения (1.28.4+195):
    //   libswiftCore  _assertionFailure(_:_:file:line:flags:)
    //   Togetherly    WidgetBundleBuilder.buildLimitedAvailability(_:)
    //   Togetherly    TogetherlyWidgetBundle.body.getter
    //   SwiftUI       WidgetBundleBodyAccessor.updateBody(of:changed:)
    //
    // Перенос ветки из своего свойства в общий блок (5900fff2) поломку не
    // вылечил именно поэтому: ветка осталась, а с ней и вызов. Вместо ветвей
    // минимальная версия РАСШИРЕНИЯ поднята до iOS 17 — тогда и accessory
    // экрана блокировки (iOS 16+), и конфигурируемые фото на AppIntents
    // (iOS 17+) объявляются безусловно. Приложение по-прежнему живёт с iOS 15,
    // просто на iOS 15–16 виджетов нет; до сих пор их не было ни у кого.
    @WidgetBundleBuilder
    var body: some Widget {
        coreWidgets
        photoWidgets
        newWidgets
        lockWidgets
    }

    @WidgetBundleBuilder
    var coreWidgets: some Widget {
        LoveWidget()
        DaysCounterWidget()
        TimerWidget()
        PetalTimerWidget()
        MoodWidget()
        StreakWidget()
        RelationshipStatsWidget()
    }

    @WidgetBundleBuilder
    var photoWidgets: some Widget {
        // Self/Partner/PhotoDay — конфигурируемые (выбор фото на экземпляр) на
        // `AppIntentConfiguration`, то есть iOS 17+. Раз минимальная версия
        // расширения теперь 17.0, ветка доступности им не нужна.
        PhotoGridWidget()
        SelfPhotoWidgetConfigurable()
        PartnerPhotoWidgetConfigurable()
        PhotoDayWidgetConfigurable()
    }

    /// Экран блокировки: accessory-семейства, iOS 16+.
    @WidgetBundleBuilder
    var lockWidgets: some Widget {
        LockDaysWidget()
        LockMissWidget()
        LockMoodWidget()
    }

    /// Новый каталог — восемь виджетов, до июля жившие только на Android.
    /// Данные им пишет тот же `home_widget`, поэтому Dart-сторона не менялась:
    /// ключи `together_*`, `note_*`, `miss_*`, `tgmood_*`, `tgcd_*`, `ring_*`
    /// и `grid_*` уже лежат в общем контейнере App Group.
    @WidgetBundleBuilder
    var newWidgets: some Widget {
        TogetherWidget()
        NoteWidget()
        NotePaperWidget()
        MissWidget()
        MoodTilesWidget()
        CountdownWidget()
        YearRingWidget()
        YearGridWidget()
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
        // Снимок просят и для галереи добавления: так журнал наполняется даже
        // тогда, когда виджет ещё не стоит на рабочем столе.
        WidgetRenderLog.write(
            family: WidgetRenderLog.familyName(context.family),
            widget: "static",
            fields: [
                "stage": "snapshot",
                "preview": context.isPreview ? "1" : "0",
                "mem": String(WidgetRenderLog.availableMemoryMB()),
            ]
        )
        completion(SimpleEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        // Отметка о самом факте построения: если для какого-то размера её нет,
        // значит система до нас не дошла или расширение умерло раньше.
        WidgetRenderLog.write(
            family: WidgetRenderLog.familyName(context.family),
            widget: "static",
            fields: [
                "stage": "timeline",
                "mem": String(WidgetRenderLog.availableMemoryMB()),
            ]
        )
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
