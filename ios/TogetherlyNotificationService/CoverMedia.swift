import CoreGraphics
import Foundation
import ImageIO
import Intents
import UniformTypeIdentifiers
import UserNotifications

/// Картинки и «уведомление о сообщении» для обложки «А» — общие для
/// расширения сервиса уведомлений (пуш) и приложения (своё уведомление из
/// сокета, `NotifCoverBridge`): оба вида должны выглядеть одинаково.
enum CoverMedia {
  static let session: URLSession = {
    let c = URLSessionConfiguration.default
    c.timeoutIntervalForRequest = 10
    c.timeoutIntervalForResource = 20
    return URLSession(configuration: c)
  }()

  /// Ссылки, которые нужны обложке: миниатюра и аватар с рамкой.
  static func urls(for cover: Cover) -> [String: String] {
    var urls: [String: String] = [:]
    // Закрытое фото воспоминания без пропуска не скачать — миниатюры не будет.
    let thumb = cover.thumbnail
    if !thumb.url.isEmpty, !thumb.auth { urls["thumb"] = thumb.url }
    if let p = cover.person {
      if !p.avatar.isEmpty { urls["avatar"] = p.avatar }
      if !p.frame.isEmpty { urls["frame"] = p.frame }
    }
    return urls
  }

  /// Скачать всё разом; ответ — когда пришли все (неудачные — без данных).
  /// Возвращает задачи: расширению их надо гасить, когда время выходит.
  @discardableResult
  static func fetch(_ urls: [String: String], done: @escaping ([String: Data]) -> Void) -> [URLSessionDataTask] {
    if urls.isEmpty { done([:]); return [] }
    let group = DispatchGroup()
    var got: [String: Data] = [:]
    let lock = NSLock()
    var tasks: [URLSessionDataTask] = []
    for (key, raw) in urls {
      guard let url = URL(string: raw) else { continue }
      group.enter()
      var req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10)
      req.setValue("Togetherly-iOS-Notif", forHTTPHeaderField: "User-Agent")
      let task = session.dataTask(with: req) { data, response, _ in
        let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        if ok, let data, !data.isEmpty {
          lock.lock()
          got[key] = data
          lock.unlock()
        }
        group.leave()
      }
      tasks.append(task)
      task.resume()
    }
    group.notify(queue: .global()) { done(got) }
    return tasks
  }

  /// Тексты, категория, миниатюра и — у события партнёра — уведомление о
  /// сообщении с аватаром. nil — система отказала в уведомлении о сообщении
  /// (нет права), тогда показывать [content] как есть.
  static func apply(_ cover: Cover, to content: UNMutableNotificationContent, media got: [String: Data]) -> UNNotificationContent {
    if let data = got["thumb"], let attachment = attachment(from: data, name: cover.kind) {
      content.attachments = [attachment]
    }
    if let person = cover.person,
       let message = asMessage(content, cover: cover, person: person, avatar: got["avatar"], frame: got["frame"]) {
      return message
    }
    return content
  }

  /// Тексты обложки и категория кнопок.
  static func texts(_ cover: Cover, to content: UNMutableNotificationContent) {
    content.title = cover.bannerTitle
    content.subtitle = cover.bannerSubtitle
    if !cover.body.isEmpty { content.body = cover.body }
    content.categoryIdentifier = cover.category
    if content.threadIdentifier.isEmpty { content.threadIdentifier = cover.kind }
  }

  // MARK: - Картинки

  /// Уменьшенная картинка (до [side] точек при разборе: у расширения потолок
  /// памяти около 24 МБ). WebP («Моти», аватары) тоже читается.
  static func image(_ data: Data, side: Int) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: side,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  static func png(_ image: CGImage) -> Data? {
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
  /// Notifications» у приложения; без него система откажет (nil).
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
