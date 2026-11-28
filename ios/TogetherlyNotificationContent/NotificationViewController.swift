import CoreText
import UIKit
import UserNotifications
import UserNotificationsUI

/// Карточка уведомления «А» по долгому нажатию на iPhone: баннер рисует
/// система, а карточку — мы. Панель в цвете события, крупная картинка
/// (миниатюра, которую положило расширение сервиса), подпись тона,
/// заголовок Unbounded и текст целиком. Кнопки под карточкой — категория
/// `tg_<вид>`, их регистрирует приложение (`NotifCoverBridge`).
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
  private let panel = UIView()
  private let stack = UIStackView()
  private let art = UIImageView()
  private let kicker = UILabel()
  private let titleLabel = UILabel()
  private let body = UILabel()
  private var artHeight: NSLayoutConstraint?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear

    panel.layer.cornerRadius = 24
    panel.layer.cornerCurve = .continuous
    panel.clipsToBounds = true
    panel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(panel)

    art.contentMode = .scaleAspectFit
    art.clipsToBounds = true
    art.layer.cornerCurve = .continuous
    art.isAccessibilityElement = false

    kicker.font = .systemFont(ofSize: 12, weight: .bold)
    kicker.numberOfLines = 1
    kicker.adjustsFontForContentSizeCategory = true

    titleLabel.font = CardFont.title(size: 22)
    titleLabel.numberOfLines = 3
    titleLabel.textColor = .label

    body.font = .preferredFont(forTextStyle: .body)
    body.adjustsFontForContentSizeCategory = true
    body.numberOfLines = 6
    body.textColor = .secondaryLabel

    stack.axis = .vertical
    stack.alignment = .fill
    stack.spacing = 6
    stack.translatesAutoresizingMaskIntoConstraints = false
    for v in [art, kicker, titleLabel, body] { stack.addArrangedSubview(v) }
    stack.setCustomSpacing(16, after: art)
    panel.addSubview(stack)

    let height = art.heightAnchor.constraint(equalToConstant: 128)
    artHeight = height
    NSLayoutConstraint.activate([
      panel.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
      panel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      panel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
      stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 20),
      stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -20),
      stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -20),
      height,
    ])
  }

  func didReceive(_ notification: UNNotification) {
    let content = notification.request.content
    guard let cover = Cover.parse(content.userInfo["cover"]) else {
      // Не наша обложка — обычные тексты, без картинки.
      panel.backgroundColor = .secondarySystemBackground
      kicker.isHidden = true
      art.isHidden = true
      titleLabel.text = content.title
      body.text = content.body
      fit()
      return
    }
    let tone = CardTone.of(cover.tone)
    panel.backgroundColor = tone.panel
    kicker.textColor = tone.label
    kicker.text = cover.kicker.uppercased()
    kicker.isHidden = cover.kicker.isEmpty
    titleLabel.text = cover.chat != nil ? cover.title : cover.bannerTitle
    let text = cover.body.isEmpty ? content.body : cover.body
    body.text = text
    body.isHidden = text.isEmpty

    if let image = attachmentImage(content) {
      art.image = image
      art.isHidden = false
      // Аватар человека — кругом, картинка события — плашкой.
      let round = cover.chat != nil
      artHeight?.constant = round ? 96 : 128
      art.layer.cornerRadius = round ? 48 : 22
      art.contentMode = round ? .scaleAspectFill : .scaleAspectFit
    } else {
      art.isHidden = true
    }
    fit()
  }

  /// Высота карточки по содержимому: система держит её до перерисовки.
  private func fit() {
    view.layoutIfNeeded()
    let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
    let size = view.systemLayoutSizeFitting(
      CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
    preferredContentSize = CGSize(width: width, height: size.height)
  }

  /// Картинка, которую расширение сервиса положило вложением.
  private func attachmentImage(_ content: UNNotificationContent) -> UIImage? {
    guard let attachment = content.attachments.first else { return nil }
    let url = attachment.url
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: url) else { return nil }
    return UIImage(data: data)
  }
}

/// Unbounded из файла расширения: имя берётся из самого шрифта.
enum CardFont {
  private static let name: String? = {
    guard let url = Bundle.main.url(forResource: "Unbounded-SemiBold", withExtension: "ttf"),
          let provider = CGDataProvider(url: url as CFURL),
          let font = CGFont(provider) else { return nil }
    CTFontManagerRegisterGraphicsFont(font, nil)
    return font.postScriptName as String?
  }()

  static func title(size: CGFloat) -> UIFont {
    let base = name.flatMap { UIFont(name: $0, size: size) } ?? .systemFont(ofSize: size, weight: .semibold)
    return UIFontMetrics(forTextStyle: .title2).scaledFont(for: base)
  }
}

/// Цвета карточки по виду события — как `Tones.kt` на Android: плашка тона
/// и подпись; в тёмной теме плашка — насыщенный цвет приглушённо, подпись
/// светлая.
struct CardTone {
  let panel: UIColor
  let label: UIColor

  private static func c(_ hex: UInt32) -> UIColor {
    UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
  }

  private static func make(tint: UInt32, label: UInt32, deep: UInt32, labelNight: UInt32) -> CardTone {
    CardTone(
      panel: UIColor { $0.userInterfaceStyle == .dark ? c(deep).withAlphaComponent(0.32) : c(tint) },
      label: UIColor { $0.userInterfaceStyle == .dark ? c(labelNight) : c(label) }
    )
  }

  private static let all: [String: CardTone] = [
    "miss": make(tint: 0xFFE1DC, label: 0x8C2F27, deep: 0xB8433A, labelNight: 0xFFB4A9),
    "mood": make(tint: 0xFFEDE4, label: 0x9A4458, deep: 0xB4506A, labelNight: 0xFFB1C3),
    "chat": make(tint: 0xE8E6FB, label: 0x3F3794, deep: 0x4F46A8, labelNight: 0xC4BFFF),
    "memory": make(tint: 0xCFE3DB, label: 0x245446, deep: 0x2E6B5A, labelNight: 0x9DD3BF),
    "gift": make(tint: 0xEFE6FA, label: 0x5A3C90, deep: 0x6C4BA6, labelNight: 0xD2BCFF),
    "evening": make(tint: 0xE6E4F7, label: 0x2D2A60, deep: 0x33306B, labelNight: 0xC3C0F5),
    "chest": make(tint: 0xFBEBD3, label: 0x714812, deep: 0x8A5A1F, labelNight: 0xF2C27E),
    "plus": make(tint: 0xFBEBD3, label: 0x714812, deep: 0x8A5A1F, labelNight: 0xF2C27E),
    "date": make(tint: 0xFFE6EC, label: 0x8A3550, deep: 0xA8405F, labelNight: 0xFFB0C6),
    "draw": make(tint: 0xE2F0FB, label: 0x24557A, deep: 0x2D6690, labelNight: 0xA6CDF0),
    "snow": make(tint: 0xE2F0FB, label: 0x24557A, deep: 0x2D6690, labelNight: 0xA6CDF0),
    "app": make(tint: 0xF3E9EB, label: 0x6B5B5C, deep: 0x8C2F27, labelNight: 0xD9C2C4),
  ]

  static func of(_ name: String) -> CardTone { all[name] ?? all["app"]! }
}
