import Flutter
import UIKit
import UserNotifications

/// Уведомления «А» на iPhone (28.11.2026): кнопки и нажатия.
///
/// Кнопки — категории `tg_<вид>` (их имя ставит релей APNs). Подпись кнопки
/// у iPhone задаётся при регистрации категории, а не в пуше, поэтому
/// регистрирует их Dart при каждом запуске, на языке приложения
/// (`NotifRenderer.registerIosCategories`, канал `love_app/notif`), из тех
/// же подписей, что у сервера.
///
/// Нажатие на сам пуш и кнопки экрана открывают `loveapp://open/<экран>`,
/// ответ, «обнять», «прочитано» и снежок телефон делает сам — теми же
/// запросами, что Android (`notif/NotifActions.kt`). Ответ без сети ждёт в
/// очереди и уходит, как только приложение снова активно.
enum NotifCoverBridge {
  private static var channel: FlutterMethodChannel?
  private static let pendingKey = "tg_notif_pending_replies"

  static func setup(_ registry: FlutterPluginRegistry) {
    guard let messenger = registry.registrar(forPlugin: "TogetherlyNotifCover")?.messenger() else { return }
    let ch = FlutterMethodChannel(name: "love_app/notif", binaryMessenger: messenger)
    ch.setMethodCallHandler { call, result in
      switch call.method {
      case "categories":
        register(call.arguments as? [[String: Any]] ?? [])
        result(true)
      case "show":
        // Своё уведомление из сокета (`PbPushService`) — тем же видом, что пуш.
        guard let args = call.arguments as? [String: Any],
              let raw = args["cover"] as? String, let cover = Cover.parse(raw) else {
          result(false)
          return
        }
        show(cover, raw: raw, title: args["title"] as? String ?? "", body: args["body"] as? String ?? "",
             tag: (args["tag"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? cover.kind) { ok in
          DispatchQueue.main.async { result(ok) }
        }
      case "schedule":
        // Своё уведомление по расписанию (капсула, праздник, Ту, приглашение).
        guard let args = call.arguments as? [String: Any],
              let id = (args["id"] as? NSNumber)?.intValue,
              let when = (args["when"] as? NSNumber)?.int64Value,
              let raw = args["cover"] as? String, let cover = Cover.parse(raw) else {
          result(false)
          return
        }
        schedule(cover, raw: raw, id: id, whenMs: when,
                 title: args["title"] as? String ?? "", body: args["body"] as? String ?? "") { ok in
          DispatchQueue.main.async { result(ok) }
        }
      case "cancelScheduled":
        if let id = ((call.arguments as? [String: Any])?["id"] as? NSNumber)?.intValue {
          let center = UNUserNotificationCenter.current()
          center.removePendingNotificationRequests(withIdentifiers: ["\(id)"])
          center.removeDeliveredNotifications(withIdentifiers: ["\(id)"])
        }
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = ch
    mirrorToken()
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { _ in
      flushPending()
      mirrorToken()
    }
    // Вход и выход меняют пропуск, пока приложение открыто.
    NotificationCenter.default.addObserver(
      forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
    ) { _ in mirrorToken() }
  }

  // MARK: - Категории

  /// `[{kind, actions: [{id, label, link}]}]` → категории `tg_<вид>`. Чужие
  /// категории (плагинов) остаются как были.
  private static func register(_ kinds: [[String: Any]]) {
    var ours: [UNNotificationCategory] = []
    for k in kinds {
      guard let kind = k["kind"] as? String, !kind.isEmpty else { continue }
      var actions: [UNNotificationAction] = []
      for case let a as [String: Any] in k["actions"] as? [Any] ?? [] {
        guard let id = a["id"] as? String, let label = a["label"] as? String, !label.isEmpty else { continue }
        let link = a["link"] as? String ?? ""
        if id == "reply" {
          actions.append(UNTextInputNotificationAction(
            identifier: id, title: label, options: [], textInputButtonTitle: label, textInputPlaceholder: ""))
        } else if link.isEmpty {
          // Действие телефона: приложение будится в фоне, экран не открывается.
          actions.append(UNNotificationAction(identifier: id, title: label, options: []))
        } else {
          actions.append(UNNotificationAction(identifier: id, title: label, options: [.foreground]))
        }
      }
      ours.append(UNNotificationCategory(
        identifier: "tg_\(kind)", actions: actions, intentIdentifiers: [], options: []))
    }
    let center = UNUserNotificationCenter.current()
    center.getNotificationCategories { existing in
      let others = existing.filter { !$0.identifier.hasPrefix("tg_") }
      center.setNotificationCategories(Set(others).union(ours))
    }
  }

  // MARK: - Своё уведомление

  /// Показать обложку своим уведомлением: тексты, миниатюра и аватар
  /// партнёра — `CoverMedia`, как в расширении. Номер `tg_<метка>`: новое
  /// того же вида заменяет прежнее, как на Android.
  private static func show(_ cover: Cover, raw: String, title: String, body: String, tag: String,
                           done: @escaping (Bool) -> Void) {
    let content = local(cover, raw: raw, title: title, body: body, thread: tag)
    CoverMedia.urls(for: cover) { urls in
      CoverMedia.fetch(urls) { got in
        let final = CoverMedia.apply(cover, to: content, media: got)
        let request = UNNotificationRequest(identifier: "tg_\(tag)", content: final, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in done(error == nil) }
      }
    }
  }

  /// По расписанию: картинка качается сейчас и хранится системой до
  /// срабатывания. Номер — как у плагина уведомлений (`"\(id)"`): его
  /// отмена по номеру снимает и наше.
  private static func schedule(_ cover: Cover, raw: String, id: Int, whenMs: Int64, title: String, body: String,
                               done: @escaping (Bool) -> Void) {
    let content = local(cover, raw: raw, title: title, body: body, thread: cover.kind)
    let seconds = max(1, Double(whenMs - NotifNetIOS.nowMs()) / 1000)
    CoverMedia.urls(for: cover) { urls in
      CoverMedia.fetch(urls) { got in
        let final = CoverMedia.apply(cover, to: content, media: got)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: "\(id)", content: final, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in done(error == nil) }
      }
    }
  }

  /// Своё уведомление: тексты обложки, категория кнопок и метка «наше» —
  /// по ней `presentsItself` показывает его поверх открытого приложения.
  private static func local(_ cover: Cover, raw: String, title: String, body: String, thread: String)
    -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.threadIdentifier = thread
    content.userInfo = ["cover": raw, "kind": cover.kind, "tg_local": true]
    CoverMedia.texts(cover, to: content)
    return content
  }

  /// Пропуск входа — в общую группу: расширение уведомлений качает по нему
  /// закрытое фото воспоминания. Вышел человек — пропуск убирается.
  static func mirrorToken() {
    let group = UserDefaults(suiteName: CoverMedia.groupId)
    let token = NotifNetIOS.token
    if let token {
      if group?.string(forKey: CoverMedia.tokenKey) != token { group?.set(token, forKey: CoverMedia.tokenKey) }
    } else {
      group?.removeObject(forKey: CoverMedia.tokenKey)
    }
  }

  /// Своё уведомление с обложкой показываем и поверх открытого приложения:
  /// его ставит `PbPushService`, только когда это уместно (не в открытом чате).
  static func presentsItself(_ notification: UNNotification) -> Bool {
    let request = notification.request
    guard !(request.trigger is UNPushNotificationTrigger) else { return false }
    return request.content.userInfo["cover"] != nil && (request.content.userInfo["tg_local"] as? Bool) == true
  }

  // MARK: - Нажатия

  /// Разобрать нажатие на уведомление с обложкой. false — не наше, его
  /// отдают плагинам как раньше. true — completion позовётся здесь.
  static func handle(_ response: UNNotificationResponse, completion: @escaping () -> Void) -> Bool {
    let info = response.notification.request.content.userInfo
    guard let cover = Cover.parse(info["cover"]) else { return false }
    let id = response.actionIdentifier
    if id == UNNotificationDismissActionIdentifier {
      completion()
      return true
    }
    if id == UNNotificationDefaultActionIdentifier {
      open(cover.link)
      completion()
      return true
    }
    guard let action = cover.actions.first(where: { $0.id == id }) else {
      open(cover.link)
      completion()
      return true
    }
    if !action.isNative {
      open(action.link)
      completion()
      return true
    }
    let text = (response as? UNTextInputNotificationResponse)?.userText
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let thread = response.notification.request.content.threadIdentifier
    // Фоновое действие: iOS даёт около 30 с, держим задачу до ответа сети.
    var bg = UIBackgroundTaskIdentifier.invalid
    bg = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(bg) }
    run(action.id, cover: cover, text: text, thread: thread) {
      completion()
      if bg != .invalid { UIApplication.shared.endBackgroundTask(bg) }
    }
    return true
  }

  /// Ссылку разбирает Dart тем же путём, что ссылки виджетов (`app_links` →
  /// `DeepLinkService` → главная, `_openFromNotification`).
  private static func open(_ link: String) {
    guard let url = URL(string: Cover.safeLink(link)) else { return }
    DispatchQueue.main.async { UIApplication.shared.open(url) }
  }

  // MARK: - Действия телефона

  private static func run(_ action: String, cover: Cover, text: String, thread: String, done: @escaping () -> Void) {
    let group = cover.group.isEmpty ? (cover.chat?.groupId ?? "") : cover.group
    guard !group.isEmpty else { done(); return }
    switch action {
    case "reply":
      guard !text.isEmpty else { done(); return }
      let reply = Reply(group: group, id: NotifNetIOS.pbId(), text: text, ts: NotifNetIOS.nowMs())
      NotifNetIOS.sendMessage(reply) { sent in
        switch sent {
        case .ok: break
        case .retry:
          // Ответ ждёт связи — человек видит это, а не тишину.
          enqueue(reply)
          let queued = cover.chat?.queued ?? ""
          notifyLocal(title: cover.chat?.fromName ?? cover.title, body: queued.isEmpty ? cover.failed : queued,
                      thread: thread)
        case .giveUp:
          notifyLocal(title: cover.title, body: cover.failed, thread: thread)
        }
        done()
      }
    case "hug":
      NotifNetIOS.hug(group: group, replyTo: cover.eventId) { ok in
        if !ok { notifyLocal(title: cover.title, body: cover.failed, thread: thread) }
        done()
      }
    case "read":
      let ts = (cover.chat?.ts ?? 0) > 0 ? cover.chat!.ts : NotifNetIOS.nowMs()
      NotifNetIOS.markRead(group: group, ts: ts) { _ in done() }
    case "throw":
      NotifNetIOS.snowball(group: group) { ok in
        if !ok { notifyLocal(title: cover.title, body: cover.failed, thread: thread) }
        done()
      }
    default:
      done()
    }
  }

  /// Сказать в шторке, что действие не дошло, — молча терять нельзя.
  private static func notifyLocal(title: String, body: String, thread: String) {
    guard !body.isEmpty else { return }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.threadIdentifier = thread
    let request = UNNotificationRequest(identifier: "tg_notif_failed_\(thread)", content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
  }

  // MARK: - Очередь ответов без сети

  struct Reply: Codable {
    let group: String
    let id: String
    let text: String
    let ts: Int64
  }

  private static func enqueue(_ reply: Reply) {
    var all = pending()
    all.append(reply)
    if let data = try? JSONEncoder().encode(Array(all.suffix(20))) {
      UserDefaults.standard.set(data, forKey: pendingKey)
    }
  }

  private static func pending() -> [Reply] {
    guard let data = UserDefaults.standard.data(forKey: pendingKey) else { return [] }
    return (try? JSONDecoder().decode([Reply].self, from: data)) ?? []
  }

  /// Досылка ответов, набранных без сети. Номер свой, повтор — «уже есть».
  static func flushPending() {
    let all = pending()
    guard !all.isEmpty else { return }
    UserDefaults.standard.removeObject(forKey: pendingKey)
    for reply in all {
      NotifNetIOS.sendMessage(reply) { sent in
        if sent == .retry { enqueue(reply) }
      }
    }
  }
}
