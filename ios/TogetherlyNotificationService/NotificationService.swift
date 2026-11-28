import CoreGraphics
import ImageIO
import Intents
import UniformTypeIdentifiers
import UserNotifications

/// Расширение сервиса уведомлений: пуш с обложкой «А» (`cover`, релей ставит
/// `mutable-content: 1`) перед показом получает тексты обложки, миниатюру
/// справа — Ту, котика «Моти», подарок, сундук — и, у событий партнёра,
/// его аватар в рамке слева (уведомление о сообщении, `INSendMessageIntent`).
/// Баннер рисует система.
///
/// Всё, что не вышло (нет обложки, картинка не скачалась, время на исходе,
/// у приложения нет права на уведомления о сообщениях), не мешает показу:
/// уходит то, что успело собраться, в худшем случае — пуш как пришёл.
final class NotificationService: UNNotificationServiceExtension {
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var best: UNMutableNotificationContent?
  private var tasks: [URLSessionDataTask] = []
  private var delivered = false
  private let lock = NSLock()

  private static let session: URLSession = {
    let c = URLSessionConfiguration.default
    c.timeoutIntervalForRequest = 10
    c.timeoutIntervalForResource = 20
    return URLSession(configuration: c)
  }()

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
      contentHandler(request.content)
      return
    }
    best = content
    guard let cover = Cover.parse(content.userInfo["cover"]) else {
      deliver(content)
      return
    }
    content.title = cover.bannerTitle
    content.subtitle = cover.bannerSubtitle
    if !cover.body.isEmpty { content.body = cover.body }
    content.categoryIdentifier = cover.category
    if content.threadIdentifier.isEmpty { content.threadIdentifier = cover.kind }

    // Закрытое фото воспоминания без пропуска не скачать: пропуск живёт у
    // приложения, общей группы с расширением пока нет — миниатюры не будет.
    let thumb = cover.thumbnail
    var urls: [String: String] = [:]
    if !thumb.url.isEmpty, !thumb.auth { urls["thumb"] = thumb.url }
    if let p = cover.person {
      if !p.avatar.isEmpty { urls["avatar"] = p.avatar }
      if !p.frame.isEmpty { urls["frame"] = p.frame }
    }
    fetch(urls) { [weak self] got in
      guard let self else { return }
      if let data = got["thumb"], let attachment = Self.attachment(from: data, name: cover.kind) {
        content.attachments = [attachment]
      }
      if let person = cover.person,
         let updated = Self.asMessage(content, cover: cover, person: person,
                                      avatar: got["avatar"], frame: got["frame"]) {
        self.deliver(updated)
      } else {
        self.deliver(content)
      }
    }
  }

  override func serviceExtensionTimeWillExpire() {
    // Время вышло: что не скачалось — без него.
    lock.lock()
    let running = tasks
    lock.unlock()
    running.forEach { $0.cancel() }
    if let content = best { deliver(content) }
  }

  private func deliver(_ content: UNNotificationContent) {
    lock.lock()
    defer { lock.unlock() }
    guard !delivered, let handler = contentHandler else { return }
    delivered = true
    handler(content)
  }

  /// Скачать всё разом; ответ — когда пришли все (неудачные — без данных).
  private func fetch(_ urls: [String: String], done: @escaping ([String: Data]) -> Void) {
    if urls.isEmpty { done([:]); return }
    let group = DispatchGroup()
    var got: [String: Data] = [:]
    let gotLock = NSLock()
    for (key, raw) in urls {
      guard let url = URL(string: raw) else { continue }
      group.enter()
      var req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10)
      req.setValue("Togetherly-iOS-Notif", forHTTPHeaderField: "User-Agent")
      let task = Self.session.dataTask(with: req) { data, response, _ in
        let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        if ok, let data, !data.isEmpty {
          gotLock.lock()
          got[key] = data
          gotLock.unlock()
        }
        group.leave()
      }
      lock.lock()
      tasks.append(task)
      lock.unlock()
      task.resume()
    }
    group.notify(queue: .global()) { done(got) }
  }

  // MARK: - Картинки

  /// Уменьшенная картинка (до [side] точек при разборе: у расширения потолок
  /// памяти около 24 МБ). WebP («Моти», аватары) тоже читается.
  private static func image(_ data: Data, side: Int) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: side,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  private static func png(_ image: CGImage) -> Data? {
    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest) ? out as Data : nil
  }

  /// Миниатюра файлом PNG: WebP вложением система не принимает.
  static func attachment(from data: Data, name: String) -> UNNotificationAttachment? {
    guard let img = image(data, side: 600), let bytes = png(img) else { return nil }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tg_notif", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("\(name)-\(UUID().uuidString).png")
    guard (try? bytes.write(to: file)) != nil else { return nil }
    return try? UNNotificationAttachment(
      identifier: "cover", url: file,
      options: [UNNotificationAttachmentOptionsTypeHintKey: UTType.png.identifier])
  }

  /// Аватар в рамке, как `FramedAvatar` приложения: рамка в 100/62 раза
  /// больше фото, фото ужато до `hole / 31`. Без фото — только рамка.
  static func framedAvatar(avatar: Data?, frame: Data?, hole: Double) -> Data? {
    let side = 256
    let photo = avatar.flatMap { image($0, side: side) }
    let ring = frame.flatMap { image($0, side: side) }
    guard photo != nil || ring != nil else { return nil }
    guard let ctx = CGContext(
      data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    let s = CGFloat(side)
    let photoSide = ring != nil ? s * 62 / 100 * CGFloat(hole / 31) : s
    let origin = (s - photoSide) / 2
    let circle = CGRect(x: origin, y: origin, width: photoSide, height: photoSide)
    if let photo {
      ctx.saveGState()
      ctx.addEllipse(in: circle)
      ctx.clip()
      // Фото по центру с обрезкой краёв.
      let w = CGFloat(photo.width), h = CGFloat(photo.height)
      let k = max(photoSide / w, photoSide / h)
      ctx.draw(photo, in: CGRect(x: origin + (photoSide - w * k) / 2, y: origin + (photoSide - h * k) / 2,
                                 width: w * k, height: h * k))
      ctx.restoreGState()
    }
    if let ring { ctx.draw(ring, in: CGRect(x: 0, y: 0, width: s, height: s)) }
    return ctx.makeImage().flatMap(png)
  }

  // MARK: - Уведомление о сообщении

  /// Событие партнёра — уведомлением о сообщении: слева его аватар в рамке,
  /// в углу маленькая иконка приложения. Нужно право «Communication
  /// Notifications» у приложения; без него система откажет, и уйдёт
  /// обычный пуш с миниатюрой (nil).
  static func asMessage(
    _ content: UNMutableNotificationContent, cover: Cover, person: CoverPerson, avatar: Data?, frame: Data?
  ) -> UNNotificationContent? {
    let face = framedAvatar(avatar: avatar, frame: frame, hole: person.frameHole).map { INImage(imageData: $0) }
    let sender = INPerson(
      personHandle: INPersonHandle(value: person.uid, type: .unknown),
      nameComponents: nil,
      displayName: person.name,
      image: face,
      contactIdentifier: nil,
      customIdentifier: person.uid
    )
    // Разговор — пара: все события партнёра в одной ветке.
    let conversation = cover.group.isEmpty ? person.uid : cover.group
    let intent = INSendMessageIntent(
      recipients: nil,
      outgoingMessageType: .outgoingMessageText,
      content: content.body,
      speakableGroupName: nil,
      conversationIdentifier: conversation,
      serviceName: nil,
      sender: sender,
      attachments: nil
    )
    if let face { intent.setImage(face, forParameterNamed: \.sender) }
    let interaction = INInteraction(intent: intent, response: nil)
    interaction.direction = .incoming
    interaction.donate(completion: nil)
    // У сообщения заголовок — имя (его ставит система); у остальных событий
    // текст события уходит подзаголовком. Правим копию: откажет система —
    // обычный пуш уйдёт с прежними текстами.
    guard let copy = content.mutableCopy() as? UNMutableNotificationContent else { return nil }
    if cover.chat == nil, !cover.bannerTitle.isEmpty {
      copy.subtitle = cover.bannerTitle
    }
    return try? copy.updating(from: intent)
  }
}
