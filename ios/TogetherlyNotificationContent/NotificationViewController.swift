import CoreText
import UIKit
import UserNotifications
import UserNotificationsUI

/// Карточка уведомления «А» по долгому нажатию на iPhone — как доска
/// «iPhone» макета (https://claude.ai/artifact/KZx6vHgr6LvacepEysXiGM):
/// сверху полоса цвета события с картинкой (Ту стоит на её нижнем крае,
/// фото — во всю полосу), ниже на светлом поле подпись тона, заголовок
/// Unbounded и текст целиком. Баннер и кнопки под карточкой рисует
/// система (категория `tg_<вид>`, `NotifCoverBridge`); углы скругляет она же.
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
  /// Как картинка ложится в полосу.
  enum Placement: Equatable {
    /// Ту, котик, подарок, сундук — целиком, стоит на нижнем крае.
    case figure
    /// Фото воспоминания или сообщения — во всю полосу.
    case photo
    /// Обложка трека, книги, постер — целиком, по центру.
    case poster
    /// Значок даты — плашкой по центру.
    case symbol
    /// Волна голосового — по ширине.
    case wave
  }

  private let band = UIView()
  private let art = UIImageView()
  private let stack = UIStackView()
  private let kicker = UILabel()
  private let titleLabel = UILabel()
  private let body = UILabel()
  private var bandHeight: NSLayoutConstraint!
  private var stackTop: NSLayoutConstraint!
  private var placed: [NSLayoutConstraint] = []

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = Self.dynamic(light: 0xFBF8FB, dark: 0x241D22)

    band.translatesAutoresizingMaskIntoConstraints = false
    band.clipsToBounds = true
    view.addSubview(band)
    art.translatesAutoresizingMaskIntoConstraints = false
    art.clipsToBounds = true
    art.layer.cornerCurve = .continuous
    art.isAccessibilityElement = false
    band.addSubview(art)

    kicker.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 11, weight: .bold))
    kicker.adjustsFontForContentSizeCategory = true
    kicker.numberOfLines = 1

    titleLabel.font = CardFont.title(size: 20)
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.numberOfLines = 3
    titleLabel.textColor = Self.dynamic(light: 0x22191A, dark: 0xF5EDEF)

    body.adjustsFontForContentSizeCategory = true
    // Текст целиком: ради него карточку и открывают.
    body.numberOfLines = 0
    body.textColor = Self.dynamic(light: 0x524344, dark: 0xD6C9CB)

    stack.axis = .vertical
    stack.alignment = .fill
    stack.spacing = 4
    stack.translatesAutoresizingMaskIntoConstraints = false
    for v in [kicker, titleLabel, body] { stack.addArrangedSubview(v) }
    stack.setCustomSpacing(2, after: kicker)
    view.addSubview(stack)

    bandHeight = band.heightAnchor.constraint(equalToConstant: 200)
    stackTop = stack.topAnchor.constraint(equalTo: band.bottomAnchor, constant: 14)
    NSLayoutConstraint.activate([
      band.topAnchor.constraint(equalTo: view.topAnchor),
      band.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      band.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      bandHeight,
      stackTop,
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
    ])
  }

  func didReceive(_ notification: UNNotification) {
    let content = notification.request.content
    render(cover: Cover.parse(content.userInfo["cover"]), title: content.title, body: content.body,
           image: attachmentImage(content))
  }

  /// Как лечь картинке обложки [cover] в полосу.
  static func placement(for cover: Cover) -> Placement {
    if let chat = cover.chat {
      if !chat.image.isEmpty { return .photo }
      return chat.peaks.isEmpty ? .photo : .wave
    }
    guard let thumb = cover.thumbnail else { return .figure }
    if !thumb.symbol.isEmpty { return .symbol }
    if thumb.auth { return .photo }
    // Обложка трека, книги, постер фильма у воспоминания.
    if cover.kind == "memory" || cover.kind == "comment" { return .poster }
    return .figure
  }

  /// Нарисовать карточку. Отдельно от [didReceive]: стенд снимков
  /// (`tool/notif_card_snapshot`) зовёт её без уведомления.
  func render(cover: Cover?, title: String, body text: String, image: UIImage?) {
    loadViewIfNeeded()
    // Цвета темы человека («Дни вместе»), если даны, иначе тон события.
    let tone = cover?.accent.map { CoverTone(tint: $0.tint, label: $0.label, deep: $0.deep, labelNight: $0.labelNight) }
      ?? CoverTone.of(cover?.tone ?? "app")
    kicker.attributedText = nil
    if let cover, !cover.kicker.isEmpty {
      // Подпись прописными с разрядкой 0,06 em, как в макете.
      kicker.attributedText = NSAttributedString(string: cover.kicker.uppercased(), attributes: [
        .font: kicker.font as Any,
        .kern: 0.66, .foregroundColor: Self.dynamic(light: tone.label, dark: tone.labelNight),
      ])
      kicker.isHidden = false
    } else {
      kicker.isHidden = true
    }
    let heading = cover?.bannerTitle ?? title
    titleLabel.text = heading
    titleLabel.isHidden = heading.isEmpty
    let full = (cover?.body.isEmpty ?? true) ? text : cover!.body
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineHeightMultiple = 1.12
    body.attributedText = NSAttributedString(string: full, attributes: [
      .font: UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 15)),
      .paragraphStyle: paragraph,
      // Цвет явно: у строки с атрибутами `textColor` подписи не действует.
      .foregroundColor: Self.dynamic(light: 0x524344, dark: 0xD6C9CB),
    ])
    body.isHidden = full.isEmpty

    NSLayoutConstraint.deactivate(placed)
    placed = []
    if let image, let cover {
      let place = Self.placement(for: cover)
      art.image = image
      band.isHidden = false
      band.backgroundColor = place == .photo
        ? .clear : Self.dynamic(light: tone.tint, dark: tone.deep, darkAlpha: 0.5)
      bandHeight.constant = 200
      stackTop.constant = 14
      art.layer.cornerRadius = 0
      switch place {
      case .figure:
        art.contentMode = .scaleAspectFit
        placed = [
          art.centerXAnchor.constraint(equalTo: band.centerXAnchor),
          art.bottomAnchor.constraint(equalTo: band.bottomAnchor, constant: 10),
          art.widthAnchor.constraint(equalToConstant: 180),
          art.heightAnchor.constraint(equalToConstant: 180),
        ]
      case .photo:
        art.contentMode = .scaleAspectFill
        placed = [
          art.topAnchor.constraint(equalTo: band.topAnchor),
          art.bottomAnchor.constraint(equalTo: band.bottomAnchor),
          art.leadingAnchor.constraint(equalTo: band.leadingAnchor),
          art.trailingAnchor.constraint(equalTo: band.trailingAnchor),
        ]
      case .poster:
        art.contentMode = .scaleAspectFit
        art.layer.cornerRadius = 10
        placed = [
          art.centerXAnchor.constraint(equalTo: band.centerXAnchor),
          art.centerYAnchor.constraint(equalTo: band.centerYAnchor),
          art.heightAnchor.constraint(equalToConstant: 168),
          art.widthAnchor.constraint(equalTo: art.heightAnchor,
                                     multiplier: max(0.5, min(1.6, image.size.width / max(1, image.size.height)))),
        ]
      case .symbol:
        art.contentMode = .scaleAspectFit
        placed = [
          art.centerXAnchor.constraint(equalTo: band.centerXAnchor),
          art.centerYAnchor.constraint(equalTo: band.centerYAnchor),
          art.widthAnchor.constraint(equalToConstant: 132),
          art.heightAnchor.constraint(equalToConstant: 132),
        ]
      case .wave:
        art.contentMode = .scaleAspectFit
        bandHeight.constant = 120
        placed = [
          art.centerYAnchor.constraint(equalTo: band.centerYAnchor),
          art.leadingAnchor.constraint(equalTo: band.leadingAnchor, constant: 16),
          art.trailingAnchor.constraint(equalTo: band.trailingAnchor, constant: -16),
          art.heightAnchor.constraint(equalToConstant: 88),
        ]
      }
      NSLayoutConstraint.activate(placed)
    } else {
      // Без картинки — только тексты (дни вместе, Плюс открыт, пароль).
      art.image = nil
      band.isHidden = true
      bandHeight.constant = 0
      stackTop.constant = 16
    }
    fit()
  }

  private static func dynamic(light: UInt32, dark: UInt32, darkAlpha: CGFloat = 1) -> UIColor {
    UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(cgColor: CoverTone.cg(dark, alpha: darkAlpha))
        : UIColor(cgColor: CoverTone.cg(light))
    }
  }

  /// Высота карточки по содержимому.
  private func fit() {
    view.setNeedsLayout()
    view.layoutIfNeeded()
    let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
    let size = view.systemLayoutSizeFitting(
      CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
    preferredContentSize = CGSize(width: width, height: ceil(size.height))
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
    return UIFontMetrics(forTextStyle: .title3).scaledFont(for: base)
  }
}
