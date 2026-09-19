import CoreLocation
import Flutter
import Photos
import UIKit
import UserNotifications
import WidgetKit

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
    setupGalleryChannel(engineBridge.pluginRegistry)
    setupApnsChannel(engineBridge.pluginRegistry)
    setupLocationAlwaysChannel(engineBridge.pluginRegistry)
  }

  // MARK: - Разрешение «Всегда» для карты «Где мы»

  /// Менеджер живёт полем: запрос разрешения асинхронный, и у временного
  /// объекта система успевает отпустить владельца раньше, чем человек ответит,
  /// — диалог тогда не показывается вовсе.
  private var alwaysLocationManager: CLLocationManager?
  private var locationAlwaysChannel: FlutterMethodChannel?

  /// Просит «Разрешить всегда» отдельным каналом.
  ///
  /// `geolocator` этого не умеет: на iOS его `requestPermission` зовёт только
  /// `requestWhenInUseAuthorization` (ветка в `PermissionHandler.m`), а до
  /// `requestAlwaysAuthorization` из Dart дотянуться нечем. Без «Всегда» iOS
  /// отдаёт фоновую локацию, лишь пока процесс жив: человек убил приложение —
  /// и метка партнёра стоит до следующего открытия.
  ///
  /// Порядок обязателен: сперва система должна выдать «При использовании»,
  /// иначе Always-запрос молча ничего не покажет. Спрашивать имеет смысл один
  /// раз — повторный вызов при уже принятом решении диалога не даёт.
  private func setupLocationAlwaysChannel(_ registry: FlutterPluginRegistry) {
    guard let messenger = registry
      .registrar(forPlugin: "TogetherlyLocationAlways")?
      .messenger()
    else { return }

    let channel = FlutterMethodChannel(
      name: "love_app/location_always",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "status":
        result(self?.locationAlwaysStatus())
      case "request":
        guard let self else {
          result("unknown")
          return
        }
        let manager = self.alwaysLocationManager ?? CLLocationManager()
        self.alwaysLocationManager = manager
        // Запрос показывается только поверх «При использовании».
        guard manager.authorizationStatus == .authorizedWhenInUse else {
          result(self.locationAlwaysStatus())
          return
        }
        DispatchQueue.main.async {
          manager.requestAlwaysAuthorization()
        }
        result(self.locationAlwaysStatus())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    locationAlwaysChannel = channel
  }

  private func locationAlwaysStatus() -> String {
    let manager = alwaysLocationManager ?? CLLocationManager()
    alwaysLocationManager = manager
    switch manager.authorizationStatus {
    case .authorizedAlways: return "always"
    case .authorizedWhenInUse: return "whenInUse"
    case .denied, .restricted: return "denied"
    case .notDetermined: return "notDetermined"
    @unknown default: return "unknown"
    }
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

  // MARK: - Тихий пуш: обновление виджетов на закрытом телефоне

  /// Движок фонового обновления. Держим ссылку, пока Dart работает: без неё
  /// ARC убьёт его на выходе из метода, и обновление не случится.
  private var backgroundEngine: FlutterEngine?

  /// Страховка на случай, если Dart не ответил: iOS ругается на невызванный
  /// completionHandler и в следующий раз даёт меньше времени.
  private var backgroundTimeout: DispatchWorkItem?

  /// Тихий пуш от сервера (`content-available`), которым мы будим приложение,
  /// когда партнёр поменял данные виджетов.
  ///
  /// У WidgetKit нет фонового обновления: пока приложение закрыто, фото и
  /// статус на рабочем столе застывают до следующего запуска (на Android то же
  /// место закрывает WorkManager). Поэтому здесь поднимается отдельный
  /// безголовый движок Flutter с точкой входа `widgetPushRefresh`: он тянет
  /// свежие данные из PocketBase, перекладывает их в контейнер App Group и
  /// сообщает «готово».
  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    let aps = userInfo["aps"] as? [String: Any]
    let silent = (aps?["content-available"] as? NSNumber)?.intValue == 1
    guard silent else {
      super.application(
        application,
        didReceiveRemoteNotification: userInfo,
        fetchCompletionHandler: completionHandler
      )
      return
    }

    // Приложение на переднем плане обновляет виджеты само, по своему сокету.
    if application.applicationState == .active {
      completionHandler(.noData)
      return
    }

    // Второй пуш, пока работает первый: молча пропускаем, иначе два движка
    // начнут писать в один контейнер.
    if backgroundEngine != nil {
      completionHandler(.noData)
      return
    }

    let engine = FlutterEngine(
      name: "togetherly-widget-refresh",
      project: nil,
      allowHeadlessExecution: true
    )
    guard engine.run(withEntrypoint: "widgetPushRefresh") else {
      completionHandler(.failed)
      return
    }
    GeneratedPluginRegistrant.register(with: engine)
    // Мост медиа виджетов нужен и здесь, а не только в основном движке.
    //
    // Без него `copyToAppGroup` в этом изоляте падает с MissingPluginException,
    // Dart эту ошибку глотает и пишет в ключ пустую строку — то есть каждый
    // тихий пуш «обнови виджеты» СТИРАЛ фото с рабочего стола. На iOS
    // приложение почти всегда выгружено, виджеты живут именно этими фоновыми
    // проходами, поэтому у человека фотографии в парном виджете не появлялись
    // вовсе, хотя в самом приложении и на Android у партнёра они были на месте
    // (связка Android — iOS, 17.08.2026).
    setupWidgetMediaChannel(engine)
    backgroundEngine = engine

    var finished = false
    let finish: (UIBackgroundFetchResult) -> Void = { [weak self] result in
      guard let self, !finished else { return }
      finished = true
      self.backgroundTimeout?.cancel()
      self.backgroundTimeout = nil
      self.backgroundEngine?.destroyContext()
      self.backgroundEngine = nil
      completionHandler(result)
    }

    let channel = FlutterMethodChannel(
      name: "love_app/widget_bg_refresh",
      binaryMessenger: engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      result(nil)
      guard call.method == "done" else { return }
      let changed = (call.arguments as? Bool) ?? true
      DispatchQueue.main.async { finish(changed ? .newData : .noData) }
    }

    // Apple даёт около тридцати секунд; на двадцати пяти закрываемся сами.
    let timeout = DispatchWorkItem { finish(.noData) }
    backgroundTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: timeout)
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

  // MARK: - Пуш о выходе Togetherly Wallet

  /// Касание по пушу «Togetherly Wallet вышел» (`pocketbase/wallet_release.py`)
  /// ведёт на страницу Wallet в App Store: чужое приложение по имени пакета на
  /// iPhone не запустить, а App Store сам покажет «Открыть», если Wallet уже
  /// стоит. Остальные пуши идут дальше как обычно — через плагины.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let info = response.notification.request.content.userInfo
    if (info["kind"] as? String) == "wallet",
       let raw = info["url"] as? String,
       let url = URL(string: raw) {
      DispatchQueue.main.async { UIApplication.shared.open(url) }
    }
    super.userNotificationCenter(
      center,
      didReceive: response,
      withCompletionHandler: completionHandler
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
      // Стереть всё, что виджеты знают о прошлом человеке: и значения, и
      // картинки. Общий контейнер App Group живёт на устройстве, а не внутри
      // аккаунта, поэтому у человека с двумя аккаунтами виджет свежей пары
      // показывал фото из прежней (жалоба 14.08.2026).
      case "wipeWidgetData":
        self?.wipeWidgetData()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    widgetMediaChannel = channel
  }

  /// Полная очистка данных виджетов в App Group: значения и файлы.
  ///
  /// Ключи расширений пишет пакет home_widget в общий `UserDefaults`, а
  /// картинки лежат в каталоге `widget_media`. При смене аккаунта нужно убрать
  /// и то, и другое, иначе виджет рисует прежнюю пару. Таймлайны просим
  /// перечитать, чтобы на экране не осталось нарисованного кадра.
  private func wipeWidgetData() {
    if let defaults = UserDefaults(suiteName: AppDelegate.appGroupId) {
      for key in defaults.dictionaryRepresentation().keys {
        defaults.removeObject(forKey: key)
      }
      defaults.synchronize()
    }
    clearAppGroupMedia(prefix: "")
    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadAllTimelines()
    }
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

// MARK: - Сохранение медиа воспоминаний в «Фото»

/// Канал `love_app/gallery`: кадр ложится в альбом «Togetherly» с датой и
/// местом воспоминания.
///
/// Togetherly при загрузке срезает у снимков дату съёмки, и без неё 94 летних
/// кадра встали бы в «Фото» на день сохранения. PhotoKit позволяет задать
/// `creationDate` и `location` прямо при импорте — это надёжнее EXIF, который
/// «Фото» читает не у всех форматов.
extension AppDelegate {
  func setupGalleryChannel(_ registry: FlutterPluginRegistry) {
    guard let messenger = registry
      .registrar(forPlugin: "TogetherlyGallery")?
      .messenger()
    else { return }

    let channel = FlutterMethodChannel(
      name: "love_app/gallery",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "save":
        let args = call.arguments as? [String: Any] ?? [:]
        // Не на главном потоке: поиск альбома ждёт PhotoKit синхронно. Очередь
        // последовательная, иначе три кадра разом завели бы три альбома.
        GallerySaver.queue.async {
          GallerySaver.save(args) { uri, error in
            DispatchQueue.main.async {
              if let error = error {
                result(error)
              } else {
                result(uri)
              }
            }
          }
        }
      case "open":
        if let url = URL(string: "photos-redirect://") {
          UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        result(nil)
      // Фоновая запись: Dart отдаёт файлы и забирает готовое, а качает
      // системная фоновая сессия — и в свёрнутом, и в выгруженном приложении.
      case "engineSubmit":
        BackgroundSaveEngine.shared.submit(call.arguments as? [String: Any] ?? [:])
        result(nil)
      case "engineStatus":
        result(BackgroundSaveEngine.shared.status())
      case "engineAck":
        let keys = (call.arguments as? [String: Any])?["keys"] as? [String] ?? []
        BackgroundSaveEngine.shared.ack(keys)
        result(nil)
      case "engineCancel":
        let keys = (call.arguments as? [String: Any])?["keys"] as? [String] ?? []
        BackgroundSaveEngine.shared.cancel(keys)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    // Сессия поднимается сразу: события загрузок, начатых до перезапуска,
    // приходят только живой сессии с тем же идентификатором.
    BackgroundSaveEngine.shared.reconnect()
  }

  /// Система будит приложение, когда фоновые загрузки кончились, пока оно
  /// было выгружено. Обработчик отдаём после того, как сессия разберёт события.
  override func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    if identifier == BackgroundSaveEngine.sessionId {
      BackgroundSaveEngine.shared.backgroundCompletion = completionHandler
      BackgroundSaveEngine.shared.reconnect()
      return
    }
    super.application(
      application,
      handleEventsForBackgroundURLSession: identifier,
      completionHandler: completionHandler
    )
  }
}

enum GallerySaver {
  static let queue = DispatchQueue(label: "com.togetherly.love.gallery", qos: .userInitiated)

  static func save(
    _ args: [String: Any],
    completion: @escaping (String?, FlutterError?) -> Void
  ) {
    guard let path = args["path"] as? String else {
      completion(nil, FlutterError(code: "SAVE_FAILED", message: "нет пути", details: nil))
      return
    }
    let kind = args["kind"] as? String ?? "photo"
    if kind == "audio" {
      // Звук «Фото» не принимает: на iPhone он уходит через «Поделиться».
      completion(nil, FlutterError(code: "UNSUPPORTED", message: "звук не для «Фото»", details: nil))
      return
    }
    let millis = (args["takenAt"] as? NSNumber)?.doubleValue
      ?? Date().timeIntervalSince1970 * 1000
    let latitude = (args["latitude"] as? NSNumber)?.doubleValue
    let longitude = (args["longitude"] as? NSNumber)?.doubleValue
    let album = args["album"] as? String ?? "Togetherly"
    let hidden = args["hidden"] as? Bool ?? false
    var name = args["name"] as? String ?? URL(fileURLWithPath: path).lastPathComponent

    var fileURL = URL(fileURLWithPath: path)
    var temp: URL?
    // WebP «Фото» принимает не везде, а четыре кадра из пяти в Togetherly —
    // WebP. Пережимаем в JPEG с запасом по качеству.
    if kind == "photo", fileURL.pathExtension.lowercased() == "webp",
       let image = UIImage(contentsOfFile: path),
       let data = image.jpegData(compressionQuality: 0.95) {
      let t = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".jpg")
      if (try? data.write(to: t)) != nil {
        fileURL = t
        temp = t
        name = (name as NSString).deletingPathExtension + ".jpg"
      }
    }
    let cleanup = {
      if let t = temp { try? FileManager.default.removeItem(at: t) }
    }

    authorize { status in
      guard status == .authorized || status == .limited else {
        cleanup()
        completion(nil, FlutterError(code: "ACCESS_DENIED", message: "нет доступа к «Фото»", details: nil))
        return
      }
      // Альбом доступен только с полным доступом; при «Только добавлять»
      // кадр сохраняется без альбома — лучше так, чем никак.
      let collection = status == .authorized ? findOrCreateAlbum(album) : nil
      write(
        fileURL: fileURL, kind: kind, name: name, millis: millis,
        latitude: latitude, longitude: longitude, hidden: hidden,
        collection: collection
      ) { id, error in
        if id == nil, collection != nil {
          // Альбом не принял — сохраняем хотя бы в медиатеку.
          write(
            fileURL: fileURL, kind: kind, name: name, millis: millis,
            latitude: latitude, longitude: longitude, hidden: hidden,
            collection: nil
          ) { id2, error2 in
            cleanup()
            completion(id2, error2)
          }
          return
        }
        cleanup()
        completion(id, error)
      }
    }
  }

  private static func write(
    fileURL: URL, kind: String, name: String, millis: Double,
    latitude: Double?, longitude: Double?, hidden: Bool,
    collection: PHAssetCollection?,
    completion: @escaping (String?, FlutterError?) -> Void
  ) {
    var placeholder: PHObjectPlaceholder?
    PHPhotoLibrary.shared().performChanges({
      let request = PHAssetCreationRequest.forAsset()
      let options = PHAssetResourceCreationOptions()
      options.originalFilename = name
      request.addResource(with: kind == "video" ? .video : .photo, fileURL: fileURL, options: options)
      request.creationDate = Date(timeIntervalSince1970: millis / 1000)
      if let lat = latitude, let lng = longitude, !(lat == 0 && lng == 0) {
        request.location = CLLocation(latitude: lat, longitude: lng)
      }
      if hidden { request.isHidden = true }
      placeholder = request.placeholderForCreatedAsset
      if let collection = collection,
         let ph = placeholder,
         let albumRequest = PHAssetCollectionChangeRequest(for: collection) {
        albumRequest.addAssets([ph] as NSArray)
      }
    }) { ok, error in
      if ok {
        completion(placeholder?.localIdentifier ?? "", nil)
      } else {
        completion(nil, FlutterError(
          code: "SAVE_FAILED",
          message: error?.localizedDescription ?? "не сохранилось",
          details: nil
        ))
      }
    }
  }

  /// Полный доступ нужен альбому; без него просим «Только добавлять».
  private static func authorize(_ done: @escaping (PHAuthorizationStatus) -> Void) {
    let full = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    switch full {
    case .notDetermined:
      // Ответ приходит на чужом потоке — возвращаемся в свою очередь, иначе
      // три первых кадра разом завели бы три альбома.
      PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
        queue.async { done(status) }
      }
    case .authorized, .limited:
      done(full)
    default:
      let add = PHPhotoLibrary.authorizationStatus(for: .addOnly)
      if add == .notDetermined {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
          queue.async { done(status == .authorized ? .limited : status) }
        }
      } else {
        done(add == .authorized ? .limited : add)
      }
    }
  }

  private static func findOrCreateAlbum(_ title: String) -> PHAssetCollection? {
    let options = PHFetchOptions()
    options.predicate = NSPredicate(format: "title = %@", title)
    if let found = PHAssetCollection.fetchAssetCollections(
      with: .album, subtype: .any, options: options
    ).firstObject {
      return found
    }
    var localId: String?
    do {
      try PHPhotoLibrary.shared().performChangesAndWait {
        localId = PHAssetCollectionChangeRequest
          .creationRequestForAssetCollection(withTitle: title)
          .placeholderForCreatedAssetCollection.localIdentifier
      }
    } catch {
      return nil
    }
    guard let id = localId else { return nil }
    return PHAssetCollection.fetchAssetCollections(
      withLocalIdentifiers: [id], options: nil
    ).firstObject
  }
}

// MARK: - Фоновая запись в «Фото»

/// Очередь фоновой записи в «Фото» (19.09.2026) — живёт без Dart.
///
/// Файлы качает фоновая сессия `URLSession`: система продолжает загрузку,
/// когда приложение свёрнуто и даже выгружено, и будит его, когда всё готово.
/// Готовый файл сразу уходит в «Фото» через [GallerySaver] — с датой и местом
/// воспоминания, в альбом «Togetherly». Итоги лежат на диске, пока Dart их не
/// подтвердит; повторная постановка того же ключа ничего не удваивает.
/// Когда всё кончилось, а приложение не на экране, — уведомление «В галерее: 94».
final class BackgroundSaveEngine: NSObject, URLSessionDownloadDelegate {
  static let shared = BackgroundSaveEngine()
  static let sessionId = "com.togetherly.love.gallery-save"

  var backgroundCompletion: (() -> Void)?

  private let queue = DispatchQueue(label: "com.togetherly.love.gallery-engine")
  private var items: [String: [String: Any]] = [:]
  private var results: [[String: Any]] = []
  private var labels: [String: String] = [:]
  private var attempts: [String: Int] = [:]
  /// Файлы, которые прямо сейчас пишутся в «Фото» или качаются задачей этого
  /// процесса: повторный подъём очереди их не трогает, иначе кадр лёг бы дважды.
  private var active: Set<String> = []
  private var resumed = false
  private var savingNow: Set<String> = []
  private var batchDone = 0
  private var batchFailed = 0
  private var lastTitle = ""
  private var loaded = false

  lazy var session: URLSession = {
    let config = URLSessionConfiguration.background(withIdentifier: Self.sessionId)
    config.sessionSendsLaunchEvents = true
    config.isDiscretionary = false
    config.allowsCellularAccess = true
    return URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }()

  private var stateURL: URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("gallery_save_engine.json")
  }

  func reconnect() {
    queue.async {
      self.load()
      // Сессию с нашим идентификатором надо создать при каждом запуске: иначе
      // система не отдаст события загрузок, начатых до перезапуска.
      let session = self.session
      guard !self.resumed else { return }
      self.resumed = true
      // Загрузки, потерянные вместе с процессом, ставим заново. Живые задачи
      // система помнит сама — их не трогаем.
      session.getAllTasks { tasks in
        let running = Set(tasks.compactMap { $0.taskDescription })
        self.queue.async {
          for (key, args) in self.items where !running.contains(key) && !self.active.contains(key) {
            if let path = args["path"] as? String {
              self.saveFile(key: key, path: path, args: args, deleteAfter: args["deleteAfter"] as? Bool ?? false)
            } else if let url = args["url"] as? String {
              self.startTask(key: key, url: url)
            }
          }
        }
      }
    }
  }

  func submit(_ args: [String: Any]) {
    queue.async {
      self.load()
      if let l = args["labels"] as? [String: String] { self.labels = l }
      guard let key = args["key"] as? String else { return }
      let known = self.items[key] != nil
        || self.results.contains { ($0["key"] as? String) == key }
      if known { return }
      self.items[key] = args
      if let title = args["title"] as? String, !title.isEmpty { self.lastTitle = title }
      self.persist()
      if let path = args["path"] as? String {
        self.saveFile(key: key, path: path, args: args, deleteAfter: args["deleteAfter"] as? Bool ?? false)
      } else if let url = args["url"] as? String {
        self.startTask(key: key, url: url)
      } else {
        self.record(key: key, code: "FAILED", uri: nil, error: "нет ни пути, ни ссылки")
      }
    }
  }

  func status() -> [String: Any] {
    return queue.sync { () -> [String: Any] in
      self.load()
      return ["results": self.results, "pending": self.items.count]
    }
  }

  func ack(_ keys: [String]) {
    queue.async {
      self.results.removeAll { keys.contains(($0["key"] as? String) ?? "") }
      self.persist()
    }
  }

  /// Крестик в приложении: Dart уже знает, итогов не нужно.
  func cancel(_ keys: [String]) {
    queue.async {
      for k in keys {
        self.items.removeValue(forKey: k)
        self.attempts.removeValue(forKey: k)
      }
      self.persist()
      self.session.getAllTasks { tasks in
        for t in tasks where keys.contains(t.taskDescription ?? "") { t.cancel() }
      }
      if self.items.isEmpty { self.finishBatch() }
    }
  }

  /// Вызывать на [queue].
  private func startTask(key: String, url: String) {
    guard let u = URL(string: url) else {
      record(key: key, code: "FAILED", uri: nil, error: "плохая ссылка")
      return
    }
    active.insert(key)
    let task = session.downloadTask(with: u)
    task.taskDescription = key
    task.resume()
  }

  /// Вызывать на [queue].
  private func saveFile(key: String, path: String, args: [String: Any], deleteAfter: Bool) {
    active.insert(key)
    savingNow.insert(key)
    var dict = args
    dict["path"] = path
    GallerySaver.queue.async {
      GallerySaver.save(dict) { uri, error in
        if deleteAfter { try? FileManager.default.removeItem(atPath: path) }
        self.queue.async {
          if let error = error {
            self.record(key: key, code: error.code == "ACCESS_DENIED" ? "ACCESS_DENIED" : "FAILED",
                        uri: nil, error: error.message)
          } else {
            self.record(key: key, code: "OK", uri: uri, error: nil)
          }
        }
      }
    }
  }

  /// Вызывать на [queue].
  private func record(key: String, code: String, uri: String?, error: String?) {
    active.remove(key)
    savingNow.remove(key)
    guard items.removeValue(forKey: key) != nil else { return }
    attempts.removeValue(forKey: key)
    var r: [String: Any] = ["key": key, "code": code]
    if let uri = uri { r["uri"] = uri }
    if let error = error { r["error"] = error }
    results.append(r)
    if code == "OK" { batchDone += 1 } else { batchFailed += 1 }
    persist()
    if items.isEmpty { finishBatch() }
  }

  /// Вызывать на [queue].
  private func finishBatch() {
    let done = batchDone, failed = batchFailed, title = lastTitle
    batchDone = 0
    batchFailed = 0
    persist()
    guard done + failed > 0 else { return }
    let labels = self.labels
    DispatchQueue.main.async {
      // На экране итог показывает островок — уведомление только в фоне.
      guard UIApplication.shared.applicationState != .active else { return }
      let content = UNMutableNotificationContent()
      content.title = failed > 0
        ? (labels["failed"] ?? "Не сохранилось: {n}").replacingOccurrences(of: "{n}", with: "\(failed)")
        : (labels["done"] ?? "В галерее: {n}").replacingOccurrences(of: "{n}", with: "\(done)")
      content.body = title
      let request = UNNotificationRequest(
        identifier: "gallery-save-done", content: content, trigger: nil)
      UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
  }

  // MARK: URLSessionDownloadDelegate

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let key = downloadTask.taskDescription else { return }
    let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
    // Файл во временной папке живёт только до выхода из этого метода —
    // переносим сразу.
    var moved: URL?
    if code == 200 {
      let name = queue.sync { self.items[key]?["name"] as? String } ?? "file.bin"
      let ext = (name as NSString).pathExtension
      let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + (ext.isEmpty ? "" : "." + ext))
      if (try? FileManager.default.moveItem(at: location, to: dest)) != nil { moved = dest }
    }
    queue.async {
      // Файла уже ждать некому (сняли крестиком) или его пишет другая
      // загрузка того же ключа — лишнюю копию выбрасываем.
      guard let args = self.items[key], !(moved != nil && self.savingNow.contains(key)) else {
        if let m = moved { try? FileManager.default.removeItem(at: m) }
        return
      }
      if let m = moved {
        self.saveFile(key: key, path: m.path, args: args, deleteAfter: true)
      } else if (400..<500).contains(code) {
        self.record(key: key, code: "FAILED", uri: nil, error: "HTTP \(code)")
      } else {
        self.retry(key: key, error: "HTTP \(code)")
      }
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let error = error, let key = task.taskDescription else { return }
    // Отмену крестиком не повторяем: файл уже снят из [items], и [retry]
    // выйдет сам. Отмена системой (приложение смахнули из недавних) — повод
    // поставить загрузку снова.
    queue.async { self.retry(key: key, error: error.localizedDescription) }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    DispatchQueue.main.async {
      self.backgroundCompletion?()
      self.backgroundCompletion = nil
    }
  }

  /// Вызывать на [queue]. Три попытки: мобильная сеть рвётся.
  private func retry(key: String, error: String) {
    active.remove(key)
    guard let args = items[key], let url = args["url"] as? String else { return }
    let n = (attempts[key] ?? 0) + 1
    attempts[key] = n
    if n >= 3 {
      record(key: key, code: "FAILED", uri: nil, error: error)
    } else {
      startTask(key: key, url: url)
    }
  }

  // MARK: Диск

  /// Вызывать на [queue].
  private func load() {
    if loaded { return }
    loaded = true
    guard let data = try? Data(contentsOf: stateURL),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return }
    items = obj["items"] as? [String: [String: Any]] ?? [:]
    results = obj["results"] as? [[String: Any]] ?? []
    labels = obj["labels"] as? [String: String] ?? [:]
    lastTitle = obj["lastTitle"] as? String ?? ""
    batchDone = obj["batchDone"] as? Int ?? 0
    batchFailed = obj["batchFailed"] as? Int ?? 0
  }

  /// Вызывать на [queue].
  private func persist() {
    let obj: [String: Any] = [
      "items": items, "results": results, "labels": labels, "lastTitle": lastTitle,
      "batchDone": batchDone, "batchFailed": batchFailed,
    ]
    guard JSONSerialization.isValidJSONObject(obj),
          let data = try? JSONSerialization.data(withJSONObject: obj)
    else { return }
    try? data.write(to: stateURL, options: .atomic)
  }
}
