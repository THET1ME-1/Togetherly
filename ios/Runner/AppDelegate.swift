import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Канал для копирования фото в контейнер App Group, чтобы расширение
  /// виджета (TogetherlyWidget) могло читать изображения. Файлы из обычного
  /// app-sandbox (getApplicationSupportDirectory) виджету недоступны.
  private var widgetMediaChannel: FlutterMethodChannel?

  /// Идентификатор App Group — совпадает с entitlements Runner и виджета.
  private static let appGroupId = "group.com.togetherly.love"

  /// Подкаталог внутри контейнера App Group, куда складываем медиа виджетов.
  private static let widgetMediaDir = "widget_media"

  /// Окно активной сцены.
  ///
  /// Приложение живёт на UIScene (`FlutterSceneDelegate` в Info.plist), поэтому
  /// окно принадлежит сцене, а делегат приложения о нём не знает. Плагины,
  /// которые ищут контроллер старым путём —
  /// `UIApplication.shared.delegate?.window??.rootViewController`, — получают
  /// nil. Так у нас молча не работала вся полноэкранная реклама Яндекса на
  /// iPhone: SDK отвечала «no view controller present» десятки раз в час, а
  /// показ ни разу не начинался. Отдаём таким плагинам окно сцены.
  private var activeSceneWindow: UIWindow? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let foreground = scenes.filter { $0.activationState == .foregroundActive }
    let candidates = foreground.isEmpty ? scenes : foreground
    return candidates.flatMap { $0.windows }.first { $0.isKeyWindow }
      ?? candidates.flatMap { $0.windows }.first
  }

  override var window: UIWindow? {
    get { super.window ?? activeSceneWindow }
    set { super.window = newValue }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Без делегата iOS не показывает локальные уведомления, пока приложение
    // открыто: отвечать на willPresent некому, и баннер не рисуется. Плагин
    // flutter_local_notifications ставит делегата сам только на macOS, на iOS
    // это делается здесь (см. пример плагина, ios/Runner/AppDelegate.swift).
    //
    // Вместе с отсутствием APNs это давало «уведомления не приходят вообще»:
    // в фоне их нет, потому что сокет мёртв, а на переднем плане — из-за этой
    // строки.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    setupWidgetMediaChannel(engineBridge.pluginRegistry)
    setupApnsChannel(engineBridge.pluginRegistry)
  }

  // MARK: - Токен APNs

  /// Канал токена устройства.
  ///
  /// Уведомления рисует приложение по своему сокету, а iOS выгружает процесс —
  /// вместе с ним умирает и сокет, поэтому с закрытым приложением человек не
  /// узнаёт ни о сообщении, ни о «скучаю». Единственный путь — пуш от Apple, а
  /// для него нужен токен устройства. Забираем его здесь и отдаём в Dart, тот
  /// кладёт в профиль (`users.apns_token`), откуда его берёт серверный хук.
  private var apnsChannel: FlutterMethodChannel?

  /// Токен может прийти раньше, чем Dart успеет попросить: держим последний.
  private var lastApnsToken: String?

  private func setupApnsChannel(_ registry: FlutterPluginRegistry) {
    guard let messenger = registry
      .registrar(forPlugin: "TogetherlyApns")?
      .messenger()
    else { return }

    let channel = FlutterMethodChannel(
      name: "love_app/apns",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "register":
        DispatchQueue.main.async {
          UIApplication.shared.registerForRemoteNotifications()
        }
        result(self?.lastApnsToken)
      case "token":
        result(self?.lastApnsToken)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    apnsChannel = channel
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    lastApnsToken = hex
    apnsChannel?.invokeMethod("token", arguments: hex)
    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
    )
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("APNs: устройство не зарегистрировалось — %@", error.localizedDescription)
    super.application(
      application,
      didFailToRegisterForRemoteNotificationsWithError: error
    )
  }

  // MARK: - Мост медиа виджетов

  private func setupWidgetMediaChannel(_ registry: FlutterPluginRegistry) {
    guard let messenger = registry
      .registrar(forPlugin: "TogetherlyWidgetMedia")?
      .messenger()
    else { return }

    let channel = FlutterMethodChannel(
      name: "love_app/ios_widget_media",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "copyToAppGroup":
        let args = call.arguments as? [String: Any]
        let srcPath = args?["srcPath"] as? String ?? ""
        let name = args?["name"] as? String ?? ""
        result(self?.copyToAppGroup(srcPath: srcPath, name: name))
      case "clearAppGroupMedia":
        let prefix = (call.arguments as? [String: Any])?["prefix"] as? String ?? ""
        self?.clearAppGroupMedia(prefix: prefix)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    widgetMediaChannel = channel
  }

  /// Каталог `widget_media` внутри контейнера App Group (создаёт при отсутствии).
  private func widgetMediaDirectory() -> URL? {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: AppDelegate.appGroupId
    ) else { return nil }
    let dir = container.appendingPathComponent(AppDelegate.widgetMediaDir, isDirectory: true)
    if !FileManager.default.fileExists(atPath: dir.path) {
      try? FileManager.default.createDirectory(
        at: dir, withIntermediateDirectories: true
      )
    }
    return dir
  }

  /// Копирует файл `srcPath` в контейнер App Group под именем `<name>.jpg`.
  /// Возвращает абсолютный путь внутри контейнера (читается расширением виджета)
  /// или nil при ошибке.
  private func copyToAppGroup(srcPath: String, name: String) -> String? {
    guard !srcPath.isEmpty, !name.isEmpty,
          FileManager.default.fileExists(atPath: srcPath),
          let dir = widgetMediaDirectory()
    else { return nil }

    let safeName = name.replacingOccurrences(of: "/", with: "_")
    let dest = dir.appendingPathComponent("\(safeName).jpg")
    do {
      if FileManager.default.fileExists(atPath: dest.path) {
        try FileManager.default.removeItem(at: dest)
      }
      try FileManager.default.copyItem(atPath: srcPath, toPath: dest.path)
      return dest.path
    } catch {
      return nil
    }
  }

  /// Удаляет файлы медиа виджетов, чьи имена начинаются с `prefix`
  /// (пустой prefix — очищает весь каталог).
  private func clearAppGroupMedia(prefix: String) {
    guard let dir = widgetMediaDirectory() else { return }
    let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    for file in files where prefix.isEmpty || file.hasPrefix(prefix) {
      try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
    }
  }
}
