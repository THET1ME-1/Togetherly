import ImageIO
import UniformTypeIdentifiers
import UserNotifications

/// Расширение сервиса уведомлений: пуш с обложкой «А» (`cover`, релей ставит
/// `mutable-content: 1`) перед показом получает тексты обложки и миниатюру
/// справа — Ту, котика «Моти», подарок, сундук. Баннер рисует система.
///
/// Всё, что не вышло (нет обложки, картинка не скачалась, время на исходе),
/// не мешает показу: уходит то, что успело собраться, в худшем случае —
/// пуш как пришёл.
final class NotificationService: UNNotificationServiceExtension {
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var best: UNMutableNotificationContent?
  private var task: URLSessionDataTask?
  private var delivered = false
  private let lock = NSLock()

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
      deliver()
      return
    }
    content.title = cover.bannerTitle
    content.subtitle = cover.bannerSubtitle
    if !cover.body.isEmpty { content.body = cover.body }
    content.categoryIdentifier = cover.category
    if content.threadIdentifier.isEmpty { content.threadIdentifier = cover.kind }

    // Закрытое фото воспоминания без пропуска не скачать: пропуск живёт у
    // приложения, общей группы с расширением пока нет. Миниатюры не будет.
    let art = cover.thumbnail
    guard !art.url.isEmpty, !art.auth, let url = URL(string: art.url) else {
      deliver()
      return
    }
    var req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 12)
    req.setValue("Togetherly-iOS-Notif", forHTTPHeaderField: "User-Agent")
    task = URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
      guard let self else { return }
      let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
      if ok, let data, let attachment = Self.attachment(from: data, name: cover.kind) {
        self.lock.lock()
        self.best?.attachments = [attachment]
        self.lock.unlock()
      }
      self.deliver()
    }
    task?.resume()
  }

  override func serviceExtensionTimeWillExpire() {
    // Время вышло: картинка не успела — показываем тексты без неё.
    task?.cancel()
    deliver()
  }

  private func deliver() {
    lock.lock()
    defer { lock.unlock() }
    guard !delivered, let handler = contentHandler, let content = best else { return }
    delivered = true
    handler(content)
  }

  /// Миниатюра файлом: картинка уменьшается до 600 точек при разборе (у
  /// расширения потолок памяти около 24 МБ) и всегда пишется PNG — WebP
  /// («Моти», аватары) вложением система не принимает.
  static func attachment(from data: Data, name: String) -> UNNotificationAttachment? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 600,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tg_notif", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("\(name)-\(UUID().uuidString).png")
    guard let dest = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return try? UNNotificationAttachment(
      identifier: "cover",
      url: file,
      options: [UNNotificationAttachmentOptionsTypeHintKey: UTType.png.identifier]
    )
  }
}
