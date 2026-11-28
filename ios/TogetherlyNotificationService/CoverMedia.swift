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

  /// Общая группа приложения и расширений: туда приложение кладёт пропуск
  /// входа (`NotifCoverBridge.mirrorToken`).
  static let groupId = "group.com.togetherly.love"
  static let tokenKey = "tg_pb_token"

  private static var authToken: String? {
    let t = UserDefaults(suiteName: groupId)?.string(forKey: tokenKey) ?? ""
    return t.isEmpty ? nil : t
  }

  /// Пропуск к закрытым файлам (`/api/files/token`) своим входом; nil —
  /// человек не вошёл или сервер не ответил.
  static func fileToken(done: @escaping (String?) -> Void) {
    guard let auth = authToken, let url = URL(string: "https://togetherly.day/api/files/token") else {
      done(nil)
      return
    }
    var req = URLRequest(url: url, timeoutInterval: 8)
    req.httpMethod = "POST"
    req.setValue(auth, forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = Data("{}".utf8)
    session.dataTask(with: req) { data, response, _ in
      guard (response as? HTTPURLResponse)?.statusCode == 200, let data,
            let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let token = o["token"] as? String, !token.isEmpty else {
        done(nil)
        return
      }
      done(token)
    }.resume()
  }

  /// Ссылки, которые нужны обложке: миниатюра и аватар с рамкой. Закрытое
  /// фото воспоминания — с пропуском; не дали — без миниатюры.
  static func urls(for cover: Cover, done: @escaping ([String: String]) -> Void) {
    var urls: [String: String] = [:]
    if let p = cover.person {
      if !p.avatar.isEmpty { urls["avatar"] = p.avatar }
      if !p.frame.isEmpty { urls["frame"] = p.frame }
    }
    guard let thumb = cover.thumbnail, !thumb.url.isEmpty else { done(urls); return }
    guard thumb.auth else {
      urls["thumb"] = thumb.url
      done(urls)
      return
    }
    fileToken { token in
      if let token { urls["thumb"] = thumb.url + (thumb.url.contains("?") ? "&" : "?") + "token=" + token }
      done(urls)
    }
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
    } else if let symbol = cover.thumbnail?.symbol, !symbol.isEmpty,
              let tile = CoverSymbol.tile(symbol, tone: CoverTone.of(cover.tone), side: 300),
              let bytes = png(tile), let attachment = attachment(png: bytes, name: cover.kind) {
      // Значок даты (капсула — письмо, праздник — торт) — плашкой тона,
      // как на Android: без картинки дата была бы единственной без обложки.
      content.attachments = [attachment]
    } else if let peaks = cover.chat?.peaks, !peaks.isEmpty,
              let wave = CoverSymbol.waveform(peaks, tone: CoverTone.of("chat"), width: 720, height: 240),
              let bytes = png(wave), let attachment = attachment(png: bytes, name: cover.kind) {
      // Голосовое — его волной, как пузырь в чате.
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
    return attachment(png: bytes, name: name)
  }

  /// Готовый PNG вложением: система переносит файл к себе.
  static func attachment(png bytes: Data, name: String) -> UNNotificationAttachment? {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tg_notif", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("\(name)-\(UUID().uuidString).png")
    guard (try? bytes.write(to: file)) != nil else { return nil }
    return try? UNNotificationAttachment(
      identifier: "cover", url: file,
      options: [UNNotificationAttachmentOptionsTypeHintKey: UTType.png.identifier])
  }

  /// Аватар в рамке, как `FramedAvatar` приложения: рамка в 100/62 раза
  /// больше фото, фото ужато до `hole / 31`. Без фото — кружок с буквой
  /// имени цвета [tone] (как `NotifArt.avatar` на Android), в рамке, если она есть.
  static func framedAvatar(avatar: Data?, frame: Data?, hole: Double, name: String, tone: CoverTone) -> Data? {
    let side = 256
    let photo = avatar.flatMap { image($0, side: side) }
    let ring = frame.flatMap { image($0, side: side) }
    guard let ctx = CoverSymbol.context(side) else { return nil }
    let s = CGFloat(side)
    let photoSide = ring != nil ? s * 62 / 100 * CGFloat(hole / 31) : s
    let origin = (s - photoSide) / 2
    let circle = CGRect(x: origin, y: origin, width: photoSide, height: photoSide)
    if photo == nil {
      CoverSymbol.monogram(name, tone: tone, in: ctx, rect: circle)
    }
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
    let face = framedAvatar(
      avatar: avatar, frame: frame, hole: person.frameHole, name: person.name, tone: CoverTone.of(cover.tone)
    ).map { INImage(imageData: $0) }
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
