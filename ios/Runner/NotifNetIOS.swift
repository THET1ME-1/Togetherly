import Foundation

/// Сеть кнопок шторки iPhone — те же запросы, что `notif/NotifActions.kt`
/// у Android: сообщение в `chat_messages` со своим номером (повтор — «уже
/// есть»), «обнять» — `/api/group/miss-you` с `want_hug`, «прочитано» —
/// `chat_reads` по паре и человеку, снежок — `/api/group/snowball`.
///
/// Вход — из prefs приложения (`flutter.pb_auth`, его хранит
/// `PocketBaseService`). Путь — как у `ServerRoute` в Dart: прямой
/// `togetherly.day`, запомнен запасной — сперва `edge.togetherly.day`.
enum NotifNetIOS {
  enum Sent { case ok, retry, giveUp }

  private static let host = "togetherly.day"
  private static let spare = "edge.togetherly.day"
  private static let session: URLSession = {
    let c = URLSessionConfiguration.default
    c.timeoutIntervalForRequest = 8
    c.timeoutIntervalForResource = 12
    return URLSession(configuration: c)
  }()

  private static var auth: [String: Any]? {
    guard let raw = UserDefaults.standard.string(forKey: "flutter.pb_auth"),
          let data = raw.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  static var token: String? {
    let t = auth?["token"] as? String ?? ""
    return t.isEmpty ? nil : t
  }

  static var myUid: String {
    let fromAuth = (auth?["model"] as? [String: Any])?["id"] as? String ?? ""
    return fromAuth.isEmpty ? (UserDefaults.standard.string(forKey: "flutter.uid") ?? "") : fromAuth
  }

  static var myName: String {
    let model = auth?["model"] as? [String: Any]
    let name = (model?["display_name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? (UserDefaults.standard.string(forKey: "flutter.displayName") ?? "") : name
  }

  private static var hosts: [String] {
    let spareSince = (UserDefaults.standard.object(forKey: "flutter.server_route_spare_since_ms") as? NSNumber)?.int64Value ?? 0
    return spareSince > 0 ? [spare, host] : [host, spare]
  }

  static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

  /// Номер записи как у PocketBase: 15 знаков `a-z0-9`.
  static func pbId() -> String {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
    return String((0..<15).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
  }

  /// Ошибки, после которых запрос точно не ушёл на сервер: можно повторить
  /// вторым путём даже «обнять» — объятие не удвоится.
  private static func notSent(_ error: Error?) -> Bool {
    guard let e = error as? URLError else { return false }
    switch e.code {
    case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .secureConnectionFailed,
         .serverCertificateUntrusted, .serverCertificateHasBadDate, .notConnectedToInternet:
      return true
    default:
      return false
    }
  }

  /// Запрос к нашему серверу: сетевой сбой на первом пути — второй.
  /// [idempotent] = false — после возможной доставки (таймаут ответа)
  /// вторым путём не повторяем.
  private static func call(
    _ method: String, _ path: String, json: [String: Any]? = nil, idempotent: Bool = true,
    hostIndex: Int = 0, completion: @escaping (Int, Data) -> Void
  ) {
    let list = hosts
    guard hostIndex < list.count, let url = URL(string: "https://\(list[hostIndex])\(path)") else {
      completion(0, Data())
      return
    }
    var req = URLRequest(url: url)
    req.httpMethod = method
    req.setValue("Togetherly-iOS-Notif", forHTTPHeaderField: "User-Agent")
    if let t = token { req.setValue(t, forHTTPHeaderField: "Authorization") }
    if let json {
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = try? JSONSerialization.data(withJSONObject: json)
    }
    session.dataTask(with: req) { data, response, error in
      if let http = response as? HTTPURLResponse {
        completion(http.statusCode, data ?? Data())
        return
      }
      if idempotent || notSent(error) {
        call(method, path, json: json, idempotent: idempotent, hostIndex: hostIndex + 1, completion: completion)
      } else {
        completion(0, Data())
      }
    }.resume()
  }

  static func sendMessage(_ reply: NotifCoverBridge.Reply, completion: @escaping (Sent) -> Void) {
    let uid = myUid
    guard !uid.isEmpty, token != nil else { completion(.giveUp); return }
    let body: [String: Any] = [
      "id": reply.id, "group_id": reply.group, "user_uid": uid, "user_name": myName,
      "text": reply.text, "ts": reply.ts, "deleted": false,
      // Часы телефона в момент отправки: по ним сервер узнаёт время
      // написания, если ответ досылается позже (`_withSentAt`).
      "sent_at": nowMs(),
    ]
    call("POST", "/api/collections/chat_messages/records", json: body) { code, data in
      let text = String(data: data, encoding: .utf8) ?? ""
      if (200..<300).contains(code) || (code == 400 && text.contains("Value must be unique")) {
        completion(.ok)
      } else if code == 400 || code == 401 || code == 403 {
        completion(.giveUp)
      } else {
        completion(.retry)
      }
    }
  }

  static func hug(group: String, replyTo: String, completion: @escaping (Bool) -> Void) {
    let uid = myUid
    guard !uid.isEmpty else { completion(false); return }
    var body: [String: Any] = [
      "groupId": group, "uid": uid, "vibe": "want_hug", "text": "", "weekday": weekday(), "count": 1,
    ]
    if !replyTo.isEmpty { body["replyTo"] = replyTo }
    call("POST", "/api/group/miss-you", json: body, idempotent: false) { code, _ in
      completion((200..<300).contains(code))
    }
  }

  /// День недели как у приложения: 1 — понедельник.
  private static func weekday() -> Int {
    let w = Calendar(identifier: .gregorian).component(.weekday, from: Date()) // 1 — воскресенье
    return w == 1 ? 7 : w - 1
  }

  static func markRead(group: String, ts: Int64, completion: @escaping (Sent) -> Void) {
    let uid = myUid
    guard !uid.isEmpty, token != nil else { completion(.giveUp); return }
    let filter = "group_id = \"\(group)\" && user_uid = \"\(uid)\""
    let q = filter.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+\"")))
      ?? ""
    call("GET", "/api/collections/chat_reads/records?perPage=1&filter=\(q)") { code, data in
      guard (200..<300).contains(code) else { completion(code == 401 || code == 403 ? .giveUp : .retry); return }
      let item = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
        .flatMap { ($0["items"] as? [[String: Any]])?.first }
      if let item, ((item["last_read_ts"] as? NSNumber)?.int64Value ?? 0) >= ts {
        completion(.ok)
        return
      }
      let iso = ISO8601DateFormatter()
      iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      var body: [String: Any] = ["last_read_ts": ts, "updated_at": iso.string(from: Date())]
      let done: (Int, Data) -> Void = { c, _ in
        completion((200..<300).contains(c) ? .ok : ([400, 401, 403, 404].contains(c) ? .giveUp : .retry))
      }
      if let id = item?["id"] as? String {
        call("PATCH", "/api/collections/chat_reads/records/\(id)", json: body, completion: done)
      } else {
        body["group_id"] = group
        body["user_uid"] = uid
        call("POST", "/api/collections/chat_reads/records", json: body, completion: done)
      }
    }
  }

  /// Снежок в ответ. «Слишком часто» (429) — снежок уже летит, это успех.
  static func snowball(group: String, completion: @escaping (Bool) -> Void) {
    call("POST", "/api/group/snowball", json: ["groupId": group], idempotent: false) { code, _ in
      completion((200..<300).contains(code) || code == 429)
    }
  }
}
