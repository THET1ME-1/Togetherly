import Foundation

// Разбор обложки «А» на iPhone (ios/TogetherlyNotificationService/Cover.swift)
// по примерам сервера — как CoverTest.kt на Android.
//
// swiftc ios/TogetherlyNotificationService/Cover.swift tool/notif_cover_check/main.swift -o /tmp/cover_check
// /tmp/cover_check test/fixtures/push_cover_cases.json

var failures: [String] = []
func check(_ name: String, _ ok: Bool, _ extra: String = "") {
  print((ok ? "  ✓ " : "  ✗ ") + name + (extra.isEmpty ? "" : " — \(extra)"))
  if !ok { failures.append(name) }
}

let path = CommandLine.arguments.dropFirst().first ?? "test/fixtures/push_cover_cases.json"
guard let data = FileManager.default.contents(atPath: path),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let cases = root["cases"] as? [[String: Any]] else {
  print("ИТОГ: не прочитал \(path)")
  exit(1)
}

check("примеров не меньше 20", cases.count >= 20, "\(cases.count)")
for c in cases {
  let kind = c["kind"] as? String ?? "?"
  let lang = c["lang"] as? String ?? "?"
  guard let cover = Cover.parse(c["cover"]) else {
    check("\(kind)/\(lang) разобран", false)
    continue
  }
  let raw = c["cover"] as? [String: Any] ?? [:]
  check("\(kind)/\(lang): вид и категория", cover.kind == kind && cover.category == "tg_\(kind)")
  check("\(kind)/\(lang): ссылка своя", cover.link.hasPrefix("loveapp://open/"), cover.link)
  check("\(kind)/\(lang): заголовок баннера не пуст", !cover.bannerTitle.isEmpty)
  for a in cover.actions {
    check("\(kind)/\(a.id): действие телефона или экран", a.isNative || a.link.hasPrefix("loveapp://open/"))
  }
  // Миниатюра — та же картинка, что у сервера (у приложения — из развёрнутого).
  let expected = (raw["art_big"] ?? raw["art"]) as? [String: Any] ?? [:]
  check("\(kind)/\(lang): миниатюра", cover.thumbnail.url == (expected["url"] as? String ?? ""))
  // Отправитель — у событий партнёра с номером, у приложения его нет.
  let rawPerson = raw["person"] as? [String: Any]
  check("\(kind)/\(lang): отправитель", (cover.person != nil) == (rawPerson != nil))
  if let p = cover.person, let rp = rawPerson {
    check("\(kind)/\(lang): аватар и рамка отправителя",
          p.avatar == (rp["avatar"] as? String ?? "") && p.frame == (rp["frame"] as? String ?? ""))
  }
  if kind == "chat" {
    check("chat/\(lang): подзаголовка нет, заголовок — имя",
          cover.bannerSubtitle.isEmpty && cover.bannerTitle == (raw["title"] as? String ?? ""))
  }
}

// Чужое и мусор.
let evil: [String: Any] = [
  "v": 1, "kind": "miss", "title": "x", "link": "https://evil.example/",
  "art": ["url": "http://plain.example/a.png"],
  "actions": [["id": "open", "label": "О", "link": "intent://x"], ["id": "wipe", "label": "Стереть"]],
]
if let c = Cover.parse(evil) {
  check("чужая ссылка — главная", c.link == "loveapp://open/home")
  check("http — без картинки", c.art.isApp)
  check("незнакомое действие выброшено", c.actions.map(\.id) == ["open"])
}
check("строка JSON разбирается", Cover.parse("{\"v\":1,\"kind\":\"chest\",\"title\":\"t\"}")?.kind == "chest")
check("мусор — nil", Cover.parse("{не json") == nil && Cover.parse(nil) == nil)
check("чужая версия — nil", Cover.parse(["v": 2, "kind": "miss"]) == nil)

print(failures.isEmpty ? "ИТОГ: всё сходится" : "ИТОГ: провалов \(failures.count)")
exit(failures.isEmpty ? 0 : 1)
