import UserNotifications

/// Расширение сервиса уведомлений: пуш с обложкой «А» (`cover`, релей ставит
/// `mutable-content: 1`) перед показом получает тексты обложки, миниатюру
/// справа — Ту, котика «Моти», подарок, сундук — и, у событий партнёра,
/// его аватар в рамке слева (уведомление о сообщении). Баннер рисует
/// система; картинки и сообщение — `CoverMedia`, общий с приложением.
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
    CoverMedia.texts(cover, to: content)
    let running = CoverMedia.fetch(CoverMedia.urls(for: cover)) { [weak self] got in
      guard let self else { return }
      // Копия: по истечении времени из другого потока уйдёт `best`, и одно
      // содержимое не должно правиться в двух местах разом.
      guard let working = content.mutableCopy() as? UNMutableNotificationContent else { return }
      self.deliver(CoverMedia.apply(cover, to: working, media: got))
    }
    lock.lock()
    tasks = running
    lock.unlock()
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
}
