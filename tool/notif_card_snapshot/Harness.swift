import UIKit

// Стенд снимков карточки уведомления «А» (ios-notif-card-snapshot.yml).
//
// Собирается из НАСТОЯЩИХ файлов расширений: карточка
// (ios/TogetherlyNotificationContent/NotificationViewController.swift), разбор
// обложки, цвета и значки (ios/TogetherlyNotificationService/Cover.swift,
// CoverTone.swift, CoverMedia.swift) — плюс этот файл. Обложки — примеры
// сервера (test/fixtures/push_cover_cases.json), картинки — настоящие записи
// каталога, скачанные прогоном в fixtures/. Карточка рисуется в окне
// симулятора в светлой и тёмной теме, снимки — PNG в Documents.
//
// Системную шапку уведомления и кнопки рисует iOS, их здесь нет: стенд
// проверяет только нашу часть.

@main
final class HarnessApp: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  private var failures: [String] = []

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let window = UIWindow(frame: UIScreen.main.bounds)
    let host = UIViewController()
    host.view.backgroundColor = .white
    window.rootViewController = host
    window.makeKeyAndVisible()
    self.window = window
    DispatchQueue.main.async { self.run(host) }
    return true
  }

  private func fixture(_ name: String) -> URL {
    Bundle.main.bundleURL.appendingPathComponent("fixtures").appendingPathComponent(name)
  }

  private func check(_ name: String, _ ok: Bool, _ extra: String = "") {
    print((ok ? "  ✓ " : "  ✗ ") + name + (extra.isEmpty ? "" : " — \(extra)"))
    if !ok { failures.append(name) }
  }

  private func save(_ image: UIImage, _ name: String) {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    try? image.pngData()?.write(to: docs.appendingPathComponent("\(name).png"))
  }

  /// Фото «воспоминания» и «кружка»: закрытые файлы стенду не скачать.
  private func photo(_ size: CGSize, _ a: UIColor, _ b: UIColor) -> UIImage {
    UIGraphicsImageRenderer(size: size).image { ctx in
      let colors = [a.cgColor, b.cgColor] as CFArray
      let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
      ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
      UIColor.white.withAlphaComponent(0.85).setFill()
      UIBezierPath(ovalIn: CGRect(x: size.width * 0.3, y: size.height * 0.25,
                                  width: size.width * 0.4, height: size.width * 0.4)).fill()
    }
  }

  private func image(_ file: String) -> UIImage? {
    guard let data = try? Data(contentsOf: fixture(file)) else { return nil }
    return UIImage(data: data)
  }

  private func run(_ host: UIViewController) {
    guard let data = try? Data(contentsOf: fixture("push_cover_cases.json")),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let cases = root["cases"] as? [[String: Any]] else {
      print("ИТОГ: не прочитал примеры")
      exit(1)
    }
    func cover(_ kind: String, _ lang: String) -> [String: Any]? {
      cases.first { $0["kind"] as? String == kind && $0["lang"] as? String == lang }?["cover"] as? [String: Any]
    }

    // Значок даты и буква без фото — те же функции, что у расширения сервиса.
    check("шрифт значков найден", CoverSymbol.font != nil)
    if let tile = CoverSymbol.tile("theater_comedy", tone: CoverTone.of("date"), side: 300) {
      save(UIImage(cgImage: tile), "symbol_theater_comedy")
    } else { check("плашка значка", false) }
    let frame = try? Data(contentsOf: fixture("frame.png"))
    for (name, ring) in [("avatar_letter", nil as Data?), ("avatar_letter_frame", frame)] {
      if let png = CoverMedia.framedAvatar(avatar: nil, frame: ring, hole: 27, name: "алина", tone: CoverTone.of("chat")),
         let img = UIImage(data: png) {
        save(img, name)
      } else { check(name, false) }
    }
    if let png = CoverMedia.framedAvatar(avatar: try? Data(contentsOf: fixture("avatar.jpg")), frame: frame, hole: 27,
                                         name: "Алина", tone: CoverTone.of("chat")),
       let img = UIImage(data: png) {
      save(img, "avatar_photo_frame")
    }

    func symbol(_ name: String, _ tone: String) -> UIImage? {
      CoverSymbol.tile(name, tone: CoverTone.of(tone), side: 300).map { UIImage(cgImage: $0) }
    }
    var longChat = cover("chat", "ru") ?? [:]
    longChat["body"] = "Ты уже дома? Я купила те самые мандарины, и ещё нашла кафе, про которое ты говорил. "
      + "Давай в субботу сходим, а потом погуляем по набережной, если не будет дождя."

    let shots: [(String, [String: Any]?, UIImage?)] = [
      ("miss_ru", cover("miss", "ru"), image("art_act_miss.png")),
      ("mood_ru", cover("mood", "ru"), image("moti_love.webp")),
      ("chat_ru", cover("chat", "ru"), photo(CGSize(width: 400, height: 400), .systemPink, .systemOrange)),
      ("chat_long_ru", longChat, nil),
      ("memory_ru", cover("memory", "ru"), photo(CGSize(width: 400, height: 300), .systemTeal, .systemIndigo)),
      ("date_es", cover("date", "es"), symbol("theater_comedy", "date")),
      ("gift_pt", cover("gift", "pt"), image("gift_bouquet.png")),
      ("evening_ru", cover("evening", "ru"), image("art_act_rest.png")),
      ("chest_uk", cover("chest", "uk"), image("art_chest_idle2.png")),
      ("capsule_ru", cover("capsule", "ru"), symbol("mail", "evening")),
      ("reels_ru", cover("reels", "ru"), image("art_act_phone.png")),
      ("days_ru", cover("days", "ru"), nil),
      ("date_remind_ru", cover("date_remind", "ru"), symbol("cake", "date")),
    ]

    for (name, raw, picture) in shots {
      guard let raw, let parsed = Cover.parse(raw) else {
        check("\(name): пример есть и разобран", false)
        continue
      }
      for style in [UIUserInterfaceStyle.light, .dark] {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 900))
        container.overrideUserInterfaceStyle = style
        // Подложка — как плашка уведомления системы.
        container.backgroundColor = style == .dark ? UIColor(white: 0.13, alpha: 1) : UIColor(white: 0.96, alpha: 1)
        host.view.addSubview(container)
        let vc = NotificationViewController()
        vc.overrideUserInterfaceStyle = style
        host.addChild(vc)
        vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 900)
        container.addSubview(vc.view)
        vc.didMove(toParent: host)
        vc.render(cover: parsed, title: parsed.bannerTitle, body: parsed.body, image: picture)
        let height = vc.preferredContentSize.height
        check("\(name)/\(style == .dark ? "тёмная" : "светлая"): высота по содержимому", height > 80 && height < 900,
              "\(Int(height))")
        vc.view.frame.size.height = height
        container.frame.size.height = height
        container.layoutIfNeeded()
        let shot = UIGraphicsImageRenderer(bounds: container.bounds).image { _ in
          container.drawHierarchy(in: container.bounds, afterScreenUpdates: true)
        }
        save(shot, "\(name)_\(style == .dark ? "dark" : "light")")
        vc.willMove(toParent: nil)
        vc.view.removeFromSuperview()
        vc.removeFromParent()
        container.removeFromSuperview()
      }
    }
    print(failures.isEmpty ? "ИТОГ: ВСЁ ВЕРНО" : "ИТОГ: ОШИБКИ — \(failures.joined(separator: ", "))")
    exit(failures.isEmpty ? 0 : 1)
  }
}
