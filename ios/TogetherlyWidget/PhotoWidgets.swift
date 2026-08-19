import SwiftUI
import WidgetKit
import UIKit

// MARK: - Фото-виджеты (Self / Partner / PhotoDay / Grid)
//
// На Android это PhotoDayWidgetProvider / SelfPhotoWidgetProvider /
// PartnerPhotoWidgetProvider / PhotoGridWidgetProvider. Фото копируются Flutter-ом
// в контейнер App Group (см. AppDelegate.copyToAppGroup + HomeWidgetService
// .syncIosPhotoWidgets), а сюда приходят абсолютные пути под ключами:
//   ios_self_photo_path      — моё фото
//   ios_partner_photo_path   — фото партнёра (+ ios_partner_photo_author)
//   ios_photo_day_path       — «фото дня» (+ ios_photo_day_author)
//   ios_photo_grid_count + ios_photo_grid_0..3 — сетка фото партнёра
//
// kind у каждого виджета совпадает с androidName из HomeWidget.updateWidget,
// чтобы reloadTimelines(ofKind:) перерисовывал нужный виджет.

// MARK: - Общие элементы

private enum PhotoStyle {
    static let corner: CGFloat = 16
    static let placeholderBg = Color(hex: 0xF5F5F5)
    static let placeholderTitle = Color(hex: 0xAAAAAA)
    static let placeholderSubtitle = Color(hex: 0xCCCCCC)
}

/// Какой это фото-виджет. От этого зависит подпись пустого состояния: одна на
/// три виджета врала — в галерее у «Фото партнёра» стояло «Фото дня · Нет
/// воспоминаний», и человек считал, что поставил не тот виджет (жалоба с
/// разбором скриншотов 13 августа 2026).
enum PhotoWidgetKind {
    case mine
    case partner
    case day
    case grid

    var emptyTitle: String {
        switch self {
        case .mine: return "Моё фото"
        case .partner: return "Фото партнёра"
        case .day: return "Фото дня"
        case .grid: return "Сетка фото"
        }
    }

    var emptyHint: String {
        switch self {
        case .mine: return "Выберите фото в приложении"
        case .partner: return "Партнёр ещё не поделился"
        case .day: return "Нет воспоминаний"
        case .grid: return "Соберите фото в приложении"
        }
    }
}

/// Одно фото на всю площадь с centerCrop-обрезкой (как scaleType=centerCrop).
private struct PhotoFill: View {
    /// Путь к файлу: картинка читается уже под размер виджета.
    ///
    /// 18.08.2026: фотография разжималась исправно (901×1200 по журналу), файл
    /// был на месте, памяти хватало — а на экране оставался чёрный квадрат.
    /// Разница между работающими и чёрными виджетами свелась к тому, во сколько
    /// раз картинка крупнее места, куда её кладут: в квадрат 158 точек ехал кадр
    /// в 1200. Теперь читаем ровно под площадь, с запасом на плотность экрана.
    let path: String
    let image: UIImage?
    var kind: PhotoWidgetKind = .day
    var logAs: String = ""
    var family: String = ""
    var body: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height) * 3
            let img = image ?? (path.isEmpty
                ? nil
                : WidgetImage.load(
                    path,
                    maxSide: max(120, side),
                    logAs: logAs,
                    family: family
                ))
            if let img {
                Image(uiImage: img)
                    .resizable()
                    .tgFullColorImage()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                PhotoPlaceholder(
                    kind: kind,
                    emojiSize: min(geo.size.width, geo.size.height) * 0.28
                )
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

/// Плейсхолдер «нет фото» — серый фон + 📷 + подпись своего виджета.
private struct PhotoPlaceholder: View {
    var kind: PhotoWidgetKind = .day
    var emojiSize: CGFloat = 34
    var showText: Bool = true
    var body: some View {
        ZStack {
            PhotoStyle.placeholderBg
            VStack(spacing: 4) {
                Text("📷").font(.system(size: emojiSize)).widgetAccentable()
                if showText {
                    Text(kind.emptyTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(PhotoStyle.placeholderTitle)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(kind.emptyHint)
                        .font(.system(size: 10))
                        .foregroundColor(PhotoStyle.placeholderSubtitle)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                }
            }
        }
    }
}

/// Обёртка-фон виджета: фото + скругление 16pt. На iOS 17+ обязателен
/// containerBackground, иначе система обрежет содержимое.
private struct PhotoWidgetContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(iOS 17.0, *) {
            content()
                .tgContainerBackground(PhotoStyle.placeholderBg)
        } else {
            content()
        }
    }
}

// MARK: - Self / Partner / PhotoDay
//
// Эти три виджета теперь конфигурируемые (iOS 17+) — их определения и
// рендер одиночного фото живут ниже, в секции «Конфигурируемые фото-виджеты».

// MARK: - Photo Grid (1 / 2 / 4 фото)

private struct PhotoGridView: View {
    var body: some View {
        let store = Store()
        let count = max(1, min(4, store.int("ios_photo_grid_count", 1)))
        // Пути, а не картинки: ячейка прочитает файл под свой размер. Здесь их
        // четыре в одном виджете, и полноразмерные кадры бьют по памяти сильнее
        // всего (расширению дают около 30 МБ).
        let paths: [String] = (0..<4).map { store.string("ios_photo_grid_\($0)") }

        PhotoWidgetContainer {
            grid(count: count, paths: paths)
                .clipShape(RoundedRectangle(cornerRadius: PhotoStyle.corner, style: .continuous))
        }
    }

    @ViewBuilder
    private func grid(count: Int, paths: [String]) -> some View {
        switch count {
        case 2:
            HStack(spacing: 1) {
                cell(paths[0])
                cell(paths[1])
            }
        case 3, 4:
            VStack(spacing: 1) {
                HStack(spacing: 1) {
                    cell(paths[0])
                    cell(paths[1])
                }
                HStack(spacing: 1) {
                    cell(paths[2])
                    cell(paths[3])
                }
            }
        default:
            cell(paths[0])
        }
    }

    private func cell(_ path: String) -> some View {
        PhotoFillCell(path: path)
    }
}

/// Ячейка сетки: фото centerCrop либо мелкий плейсхолдер без текста.
private struct PhotoFillCell: View {
    let path: String
    var body: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height) * 3
            let img = path.isEmpty
                ? nil
                : WidgetImage.load(path, maxSide: max(120, side))
            if let img {
                Image(uiImage: img)
                    .resizable()
                    .tgFullColorImage()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                PhotoPlaceholder(
                    kind: .grid,
                    emojiSize: min(geo.size.width, geo.size.height) * 0.3,
                    showText: false
                )
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

struct PhotoGridWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PhotoGridWidgetProvider", provider: RefreshProvider()) { _ in
            PhotoGridView().unredacted()
        }
        .configurationDisplayName("Сетка фото")
        .description("Несколько фото партнёра в одной сетке.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Фото-виджеты: почему без выбора снимка
//
// До 18.08.2026 «Моё фото», «Фото партнёра» и «Фото дня» были конфигурируемыми:
// AppIntent, каталог снимков в App Group, выбор в «Изменить виджет». На iPhone
// тестера (iOS 26, сборка 1.29.3) они рисовались ЧЁРНЫМ и не оставляли в журнале
// отрисовки ни одной записи — то есть система не доходила даже до построения
// таймлайна, хотя парный виджет с обычной статической конфигурацией работал и
// показывал те же фотографии.
//
// Поэтому вернулись к статике: виджет читает путь прямо из общего контейнера
// (ios_self_photo_path и соседние). Выбор конкретного снимка пропал, зато
// фотография показывается. Каталоги `ios_photo_catalog_*` приложение писать
// продолжает — они понадобятся, когда выбор вернём.

/// Фото по ключу контейнера — без выбора конкретного снимка.
///
/// 18.08.2026: конфигурируемые версии (AppIntent, iOS 17+) на iPhone тестера
/// рисовались чёрным и не оставляли в журнале ни одной записи — то есть система
/// не доходила даже до построения таймлайна. Парный виджет, объявленный обычной
/// статической конфигурацией, при этом работал. Возвращаем статику: показать
/// фотографию важнее, чем дать выбрать, какую именно.
private struct KeyPhotoView: View {
    let storeKey: String
    let kind: PhotoWidgetKind
    @Environment(\.widgetFamily) private var family
    var body: some View {
        PhotoWidgetContainer {
            PhotoFill(
                path: Store().string(storeKey),
                image: nil,
                kind: kind,
                logAs: "photo-\(kind)",
                family: WidgetRenderLog.familyName(family)
            )
            .clipShape(RoundedRectangle(cornerRadius: PhotoStyle.corner, style: .continuous))
        }
    }
}

// MARK: - Виджеты фото

struct SelfPhotoWidgetConfigurable: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SelfPhotoWidgetProvider", provider: RefreshProvider()) { _ in
            KeyPhotoView(storeKey: "ios_self_photo_path", kind: .mine).unredacted()
        }
        .configurationDisplayName("Моё фото")
        .description("Фото, которым вы делитесь с партнёром.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PartnerPhotoWidgetConfigurable: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PartnerPhotoWidgetProvider", provider: RefreshProvider()) { _ in
            KeyPhotoView(storeKey: "ios_partner_photo_path", kind: .partner).unredacted()
        }
        .configurationDisplayName("Фото партнёра")
        .description("Фото, которым с вами поделился партнёр.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PhotoDayWidgetConfigurable: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PhotoDayWidgetProvider", provider: RefreshProvider()) { _ in
            KeyPhotoView(storeKey: "ios_photo_day_path", kind: .day).unredacted()
        }
        .configurationDisplayName("Фото дня")
        .description("Тёплое фото из ваших воспоминаний.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
