import Foundation

/// Уведомление «А. Обложка» (28.11.2026): что показать, собранное сервером
/// (`pocketbase/hotpath/push_cover.py`). Здесь только разбор, на Foundation:
/// его проверяет `tool/notif_cover_check/main.swift` по примерам сервера
/// (`test/fixtures/push_cover_cases.json`), как Kotlin — `CoverTest.kt`.
struct CoverArt: Equatable {
  var url: String = ""
  /// Файл закрыт (фото воспоминания): нужен пропуск своим входом.
  var auth: Bool = false
  /// Значок Material Symbols по имени (`theater_comedy`).
  var symbol: String = ""

  /// Иконка приложения: ни ссылки, ни значка.
  var isApp: Bool { url.isEmpty && symbol.isEmpty }

  init(url: String = "", auth: Bool = false, symbol: String = "") {
    self.url = url
    self.auth = auth
    self.symbol = symbol
  }

  init(_ any: Any?) {
    guard let o = any as? [String: Any] else { return }
    let raw = o["url"] as? String ?? ""
    // Только https: обложку собирает сервер, но расширение не должно ходить
    // куда попало, даже если её подменят.
    url = raw.hasPrefix("https://") ? raw : ""
    auth = o["auth"] as? Bool ?? false
    symbol = o["symbol"] as? String ?? ""
  }
}

struct CoverAction: Equatable {
  let id: String
  let label: String
  /// `loveapp://open/<экран>` или пусто — действие телефона (`reply`, `hug`,
  /// `read`, `throw`).
  let link: String
  var isNative: Bool { link.isEmpty }
}

struct CoverChat: Equatable {
  let fromUid: String
  let fromName: String
  let groupId: String
  let messageId: String
  let ts: Int64
  let avatar: String
  let frame: String
  let frameHole: Double
  let image: String
  /// «Отправлю, когда появится связь» — ответ из шторки без сети.
  let queued: String
}

/// Отправитель события партнёра: его аватар в рамке iPhone ставит слева.
struct CoverPerson: Equatable {
  let uid: String
  let name: String
  let avatar: String
  let frame: String
  /// Радиус фото под рамкой в единицах 0..100 (`AvatarFrame.hole`).
  let frameHole: Double

  init?(_ any: Any?) {
    guard let o = any as? [String: Any], let uid = o["uid"] as? String, !uid.isEmpty else { return nil }
    func https(_ k: String) -> String {
      let v = o[k] as? String ?? ""
      return v.hasPrefix("https://") ? v : ""
    }
    self.uid = uid
    name = o["name"] as? String ?? ""
    avatar = https("avatar")
    frame = https("frame")
    let hole = (o["frame_hole"] as? NSNumber)?.doubleValue ?? 31
    frameHole = min(31, max(18, hole.isNaN ? 31 : hole))
  }
}

struct Cover: Equatable {
  static let nativeActions: Set<String> = ["reply", "hug", "read", "throw"]

  let kind: String
  let kicker: String
  let title: String
  let body: String
  let tone: String
  let art: CoverArt
  let artBig: CoverArt?
  let actions: [CoverAction]
  let link: String
  let group: String
  let eventId: String
  let failed: String
  let chat: CoverChat?
  let person: CoverPerson?

  /// Пуш от самого приложения: слева иконка, картинка события — миниатюрой.
  var fromApp: Bool { art.isApp && artBig != nil }

  /// Картинка для миниатюры справа и карточки: у событий партнёра — его
  /// картинка, у уведомлений приложения — картинка события из развёрнутого
  /// вида (или значок даты). У сообщения — фото из него (кадр кружка,
  /// закрытое); без фото — ничего: аватар уже стоит слева, повторять его
  /// справа незачем. Только если отправителя нет — аватар миниатюрой.
  var thumbnail: CoverArt? {
    if let chat {
      if !chat.image.isEmpty { return CoverArt(url: chat.image, auth: true) }
      return person == nil && !art.url.isEmpty ? art : nil
    }
    let picture = artBig ?? art
    return picture.isApp ? nil : picture
  }

  /// Категория кнопок, как ставит релей APNs (`tg_<вид>`).
  var category: String { "tg_\(kind)" }

  /// Своя ссылка уведомлений; чужая или пустая — главная.
  static func safeLink(_ link: String) -> String {
    link.hasPrefix("loveapp://open/") ? link : "loveapp://open/home"
  }

  /// Обложка из поля `cover` пуша: словарь (APNs) или строка JSON. nil —
  /// старая версия, мусор, пусто: пуш показывается как пришёл.
  static func parse(_ any: Any?) -> Cover? {
    var dict = any as? [String: Any]
    if dict == nil, let s = any as? String, let data = s.data(using: .utf8) {
      dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    guard let o = dict, (o["v"] as? NSNumber)?.intValue == 1,
          let kind = o["kind"] as? String, !kind.isEmpty else { return nil }
    var actions: [CoverAction] = []
    for case let a as [String: Any] in o["actions"] as? [Any] ?? [] {
      let id = a["id"] as? String ?? ""
      let label = a["label"] as? String ?? ""
      let raw = a["link"] as? String ?? ""
      guard !id.isEmpty, !label.isEmpty else { continue }
      // Кнопка без ссылки, которую телефон делать не умеет, — пропускаем.
      if raw.isEmpty && !nativeActions.contains(id) { continue }
      actions.append(CoverAction(id: id, label: label, link: raw.isEmpty ? "" : safeLink(raw)))
    }
    var chat: CoverChat?
    if let c = o["chat"] as? [String: Any] {
      func https(_ k: String) -> String {
        let v = c[k] as? String ?? ""
        return v.hasPrefix("https://") ? v : ""
      }
      let hole = (c["frame_hole"] as? NSNumber)?.doubleValue ?? 31
      chat = CoverChat(
        fromUid: c["from_uid"] as? String ?? "",
        fromName: c["from_name"] as? String ?? "",
        groupId: c["group_id"] as? String ?? "",
        messageId: c["message_id"] as? String ?? "",
        ts: (c["ts"] as? NSNumber)?.int64Value ?? 0,
        avatar: https("avatar"),
        frame: https("frame"),
        frameHole: min(31, max(18, hole.isNaN ? 31 : hole)),
        image: https("image"),
        queued: c["queued"] as? String ?? ""
      )
    }
    return Cover(
      kind: kind,
      kicker: o["kicker"] as? String ?? "",
      title: o["title"] as? String ?? "",
      body: o["body"] as? String ?? "",
      tone: o["tone"] as? String ?? "app",
      art: CoverArt(o["art"]),
      artBig: o["art_big"].map { CoverArt($0) },
      actions: Array(actions.prefix(4)),
      link: safeLink(o["link"] as? String ?? ""),
      group: o["group"] as? String ?? "",
      eventId: o["event_id"] as? String ?? "",
      failed: o["failed"] as? String ?? "",
      chat: chat,
      person: CoverPerson(o["person"])
    )
  }

  /// Тексты баннера iPhone. Баннер рисует система, поэтому подпись тона
  /// («Скучаю · Алина») уходит подзаголовком, а у сообщения заголовок —
  /// имя, как в мессенджере.
  var bannerTitle: String { title.isEmpty ? kicker : title }
  var bannerSubtitle: String { chat != nil || title.isEmpty ? "" : kicker }
}
