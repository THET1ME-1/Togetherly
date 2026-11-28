import CoreText
import UIKit
import UserNotifications
import UserNotificationsUI

/// Карточка уведомления «А» по долгому нажатию на iPhone: баннер рисует
/// система, а карточку — мы. Панель в цвете события, подпись тона,
/// заголовок Unbounded и текст целиком; картинка — вложение, которое
/// положило расширение сервиса (Ту, котик «Моти», подарок, значок даты, фото).
/// У сообщения порядок как в переписке: имя, текст, под ним фото из него.
/// Кнопки под карточкой — категория `tg_<вид>` (`NotifCoverBridge`).
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
  private let panel = UIView()
  private let stack = UIStackView()
  private let art = UIImageView()
  private let kicker = UILabel()
  private let titleLabel = UILabel()
  private let body = UILabel()
  private let photo = UIImageView()
  private var artHeight: NSLayoutConstraint?
  private var photoHeight: NSLayoutConstraint?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear

    panel.layer.cornerRadius = 24
    panel.layer.cornerCurve = .continuous
    panel.clipsToBounds = true
    panel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(panel)

    for image in [art, photo] {
      image.clipsToBounds = true
      image.layer.cornerCurve = .continuous
      image.isAccessibilityElement = false
      image.isHidden = true
    }
    photo.contentMode = .scaleAspectFill
    photo.layer.cornerRadius = 16

    kicker.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 12, weight: .bold))
    kicker.adjustsFontForContentSizeCategory = true
    kicker.numberOfLines = 1

    titleLabel.font = CardFont.title(size: 22)
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.numberOfLines = 3
    titleLabel.textColor = .label

    body.font = .preferredFont(forTextStyle: .body)
    body.adjustsFontForContentSizeCategory = true
    // Текст целиком: ради него карточку и открывают.
    body.numberOfLines = 0
    body.textColor = .secondaryLabel

    stack.axis = .vertical
    stack.alignment = .fill
    stack.spacing = 6
    stack.translatesAutoresizingMaskIntoConstraints = false
    for v in [art, kicker, titleLabel, body, photo] { stack.addArrangedSubview(v) }
    stack.setCustomSpacing(16, after: art)
    stack.setCustomSpacing(12, after: body)
    panel.addSubview(stack)

    let artHeight = art.heightAnchor.constraint(equalToConstant: 140)
    let photoHeight = photo.heightAnchor.constraint(equalToConstant: 200)
    self.artHeight = artHeight
    self.photoHeight = photoHeight
    NSLayoutConstraint.activate([
      panel.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
      panel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      panel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
      stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 20),
      stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -20),
      stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -20),
      artHeight,
      photoHeight,
    ])
  }

  func didReceive(_ notification: UNNotification) {
    let content = notification.request.content
    render(cover: Cover.parse(content.userInfo["cover"]), title: content.title, body: content.body,
           image: attachmentImage(content))
  }

  /// Нарисовать карточку. Отдельно от [didReceive]: стенд снимков
  /// (`tool/notif_card_snapshot`) зовёт её без уведомления.
  func render(cover: Cover?, title: String, body text: String, image: UIImage?) {
    loadViewIfNeeded()
    art.isHidden = true
    photo.isHidden = true
    guard let cover else {
      // Не наша обложка — обычные тексты, без картинки.
      panel.backgroundColor = .secondarySystemBackground
      kicker.isHidden = true
      titleLabel.text = title
      body.text = text
      body.isHidden = text.isEmpty
      fit()
      return
    }
    let tone = CoverTone.of(cover.tone)
    panel.backgroundColor = Self.color(light: tone.tint, dark: tone.deep, darkAlpha: 0.32)
    kicker.textColor = Self.color(light: tone.label, dark: tone.labelNight)
    kicker.text = cover.kicker.uppercased()
    kicker.isHidden = cover.kicker.isEmpty
    titleLabel.text = cover.bannerTitle
    titleLabel.isHidden = cover.bannerTitle.isEmpty
    let full = cover.body.isEmpty ? text : cover.body
    body.text = full
    body.isHidden = full.isEmpty

    if let image {
      if cover.chat != nil {
        // Фото из сообщения — под текстом, как в переписке.
        photo.image = image
        photo.isHidden = false
        photoHeight?.constant = height(of: image, maxHeight: 220)
      } else if cover.thumbnail?.auth == true {
        // Фото воспоминания — во всю ширину, со скруглением.
        art.image = image
        art.contentMode = .scaleAspectFill
        art.layer.cornerRadius = 18
        artHeight?.constant = height(of: image, maxHeight: 200)
        art.isHidden = false
      } else {
        // Картинка каталога (Ту, котик, подарок) или значок — целиком.
        art.image = image
        art.contentMode = .scaleAspectFit
        art.layer.cornerRadius = 0
        artHeight?.constant = 140
        art.isHidden = false
      }
    }
    fit()
  }

  /// Высота картинки по ширине карточки (поля панели и стопки — 64 точки):
  /// не выше [maxHeight].
  private func height(of image: UIImage, maxHeight: CGFloat) -> CGFloat {
    let outer = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
    let width = max(1, outer - 64)
    guard image.size.width > 0 else { return maxHeight }
    return min(maxHeight, max(120, width * image.size.height / image.size.width))
  }

  private static func color(light: UInt32, dark: UInt32, darkAlpha: CGFloat = 1) -> UIColor {
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
    return UIFontMetrics(forTextStyle: .title2).scaledFont(for: base)
  }
}
