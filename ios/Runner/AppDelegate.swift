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
      default:
        result(FlutterMethodNotImplemented)
      }
    }
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
