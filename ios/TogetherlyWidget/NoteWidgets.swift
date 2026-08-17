import SwiftUI
import WidgetKit

// MARK: - Заметка на двоих
//
// Текст пишет `HomeWidgetService.syncNote` под `note_<g>_text/author/time`.
// Заметка общая: у каждого своя запись, а виджет показывает свежую из двух —
// разбирается это на стороне Dart, сюда приезжает уже победившая.
//
// Печатать внутри виджета iOS не даёт (на Android для этого заведена отдельная
// прозрачная активность), поэтому тап уводит в приложение по `loveapp://note`,
// где открывается тот же листик с клавиатурой.

private struct NoteData {
    let text: String
    let author: String
    let time: String
}

private func loadNote() -> NoteData {
    let s = Store()
    let g = s.latestGroup("note_latest_group")
    return NoteData(
        text: s.string("note_\(g)_text"),
        author: s.string("note_\(g)_author"),
        time: s.string("note_\(g)_time")
    )
}

private let noteURL = URL(string: "loveapp://note")

/// Общая начинка листика: текст, подпись и время.
private struct NoteBody: View {
    let data: NoteData
    let textColor: Color
    let captionColor: Color
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if data.text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(captionColor)
                    .lineLimit(3)
            } else {
                Text(data.text)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(textColor)
                    .lineLimit(6)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            if !data.author.isEmpty || !data.time.isEmpty {
                HStack(spacing: 6) {
                    if !data.author.isEmpty {
                        Text(data.author)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(captionColor)
                            .lineLimit(1)
                    }
                    if !data.time.isEmpty {
                        Text(data.time)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(captionColor)
                    }
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Вид «карточка M3»

private struct NoteCardView: View {
    var body: some View {
        let t = WidgetTheme()
        let data = loadNote()

        NoteBody(
            data: data,
            textColor: t.onPrimaryContainer,
            captionColor: t.onContainerSoft,
            placeholder: "Нажмите, чтобы написать друг другу"
        )
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tgContainerBackground(t.primaryContainer)
        .widgetURL(noteURL)
    }
}

struct NoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NoteWidget4x2Provider", provider: RefreshProvider()) { _ in
            NoteCardView().unredacted()
        }
        .configurationDisplayName("Заметка")
        .description("Записка на двоих в цвете вашей темы.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Вид «бумажный стикер»

private struct NotePaperView: View {
    // Бумага живёт своими цветами и темой не красится: смысл стикера в том,
    // что он выглядит клочком бумаги на рабочем столе.
    private let paper = Color(hex: 0xFFF3B0)
    private let ink = Color(hex: 0x3E3A2F)
    private let pencil = Color(hex: 0x8A7F5C)

    var body: some View {
        let data = loadNote()

        ZStack(alignment: .topTrailing) {
            NoteBody(
                data: data,
                textColor: ink,
                captionColor: pencil,
                placeholder: "Нажмите, чтобы написать друг другу"
            )
            .padding(16)

            // Загнутый уголок — единственное украшение, ради узнаваемости.
            Path { p in
                p.move(to: CGPoint(x: 26, y: 0))
                p.addLine(to: CGPoint(x: 26, y: 26))
                p.addLine(to: CGPoint(x: 0, y: 26))
                p.closeSubpath()
            }
            .fill(Color.black.opacity(0.08))
            .frame(width: 26, height: 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tgContainerBackground(paper)
        .widgetURL(noteURL)
    }
}

struct NotePaperWidget: Widget {
    var body: some WidgetConfiguration {
        // kind — имя соседнего Android-провайдера того же семейства: Flutter
        // будит все три размера заметки, поэтому бумажный стикер обновляется
        // вместе с карточкой, своего вызова заводить не пришлось.
        StaticConfiguration(kind: "NoteWidget2x2Provider", provider: RefreshProvider()) { _ in
            NotePaperView().unredacted()
        }
        .configurationDisplayName("Заметка — бумага")
        .description("Та же записка, но клочком бумаги.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
