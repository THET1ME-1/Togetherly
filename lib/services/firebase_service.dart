import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart' hide Query;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:home_widget/home_widget.dart';
import 'locale_service.dart';
import 'nickname_service.dart';
import 'pb_media_service.dart';
import 'supabase_service.dart';
import '../config/migration_config.dart';

/// URL базы Realtime Database (регион europe-west1 — не дефолтный).
/// Presence (онлайн/lastSeen) живёт в RTDB, а не в Firestore: статус меняется
/// при каждом foreground/background, и хранение в users/{uid} стоило сотен
/// тысяч Firestore-чтений в день у партнёрских презенс-листенеров.
const String _kRtdbUrl =
    'https://togetherly-d4856-default-rtdb.europe-west1.firebasedatabase.app';

/// Единый сервис для работы с Firebase.
/// Поддерживает группы от 2 до 10 участников + совместные воспоминания.
class FirebaseService {
  static final FirebaseService _instance = FirebaseService._();
  factory FirebaseService() => _instance;
  // Слой данных полностью переехал на PocketBase; здесь остался только
  // живой хвост на Firebase: cutover-cleanup сессии (signOut/isLoggedIn),
  // FCM-пуш (initFCM до §5), резолв legacy-медиа gs:// (до §8) и IAP
  // grantCoinsPurchase. Никакой Supabase/migration-инициализации на старте.
  FirebaseService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

  /// Realtime Database (presence). Регион europe-west1, см. [_kRtdbUrl].
  FirebaseDatabase get _rtdb =>
      FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: _kRtdbUrl);

  DatabaseReference _presenceRef(String uid) => _rtdb.ref('presence/$uid');

  // Завершается, когда Firebase Auth восстановил сессию на старте (первое
  // непустое событие authStateChanges) ЛИБО истёк короткий грейс (юзер
  // разлогинен). accessToken-колбэк Supabase (main.dart) ждёт его ПЕРЕД выдачей
  // токена — иначе первые запросы холодного старта уходят анонимно (currentUser
  // ещё null) и RLS их отбивает (см. _write / «not a group member»).
  final Completer<void> _authReady = Completer<void>();
  Future<void> get authReady => _authReady.future;


  // In-memory cache — eliminates repeated users/{uid} reads on hot paths.
  String? _cachedDisplayName;
  String? _cachedAvatarUrl;

  // ══════════════════════════════════════════════
  //  AUTH
  // ══════════════════════════════════════════════

  User? get currentUser => _auth.currentUser;
  bool get isLoggedIn => _auth.currentUser != null;
  String? get uid => _auth.currentUser?.uid;

  // ══════════════════════════════════════════════
  //  МИГРАЦИЯ Supabase (Фаза 1)
  // ══════════════════════════════════════════════

  final SupabaseService _sb = SupabaseService();

  /// true — текущий пользователь участвует в Фазе 1 миграции:
  /// его данные зеркалятся в Supabase (dual-write) и читаются оттуда.
  bool get _mig =>
      MigrationConfig.isConfigured &&
      MigrationConfig.isPhase1User(_auth.currentUser?.email);

  /// Сессионный снапшот «смешанных» групп (партнёр на СТАРОЙ версии по вердикту
  /// прошлой сессии). Грузится из prefs на старте и НЕ меняется в течение сессии
  /// (источник чтения стабилен, без mid-session ребинда). Дефолт — пусто, т.е.
  /// все группы (включая свежие установки) читают Supabase; сюда попадают только
  /// пары, где партнёр подтверждён старым. См. [_readSb], [_kGroupMixedPersist].
  final Set<String> _sessionMixedGroups = {};

  /// Можно ли ЧИТАТЬ эту группу из Supabase (Stage 3). НОВАЯ МОДЕЛЬ: Supabase —
  /// дефолт для всех мигрирующих пользователей (в т.ч. свежих установок из
  /// Google Play — сразу, без «ждать следующей сессии»). На Firebase откатываемся
  /// ТОЛЬКО когда compat-резолв прошлой сессии увидел партнёра на СТАРОЙ версии
  /// (группа в [_sessionMixedGroups]) — тогда оба держатся на Firebase, пока
  /// партнёр не обновится. Решение стабильно в течение сессии (без mid-session
  /// ребинда листенеров); связь при подключении лишь обновляет персист-отметку
  /// для следующего старта. Пустой groupId/per-user чтения никогда не флипаются.
  /// Запись при этом остаётся дуальной (см. [_writeFb]), пока оба партнёра не
  /// подтвердят чтение из Supabase — старый партнёр продолжает видеть наши данные.
  bool _readSb(String groupId) =>
      MigrationConfig.stage3ReadFromSupabase &&
      _mig &&
      groupId.isNotEmpty &&
      !_sessionMixedGroups.contains(groupId);

  /// Публичный гейт миграции — нужен другим сервисам (WidgetService /
  /// HomeWidgetService), чтобы маршрутизировать чтения widget_data в Supabase.
  bool get isMigrationUser => _mig;

  /// Cached display name — use this instead of reading users/{uid} from Firestore.
  String get displayName =>
      _cachedDisplayName ?? _auth.currentUser?.displayName ?? '';

  /// Cached avatar URL — always reflects the latest save, even before Firestore syncs.
  String get avatarUrl => _cachedAvatarUrl ?? _auth.currentUser?.photoURL ?? '';

  Future<void> signOut() async {
    try {
      await setOnlineStatus(false);
    } catch (_) {}
    _disposePresenceWatcher();
    try {
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
    } catch (_) {}
    await _auth.signOut();
  }

  // ─────────────────────────────────────────────
  // Local notifications plugin (for foreground FCM)
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _localNotificationsInitialized = false;
  static const String _kChannelId = 'miss_you';
  static const String _kChannelName = 'Скучаю';

  /// groupId чата, открытого прямо сейчас на экране (или null). Пока пользователь
  /// смотрит этот чат, foreground-уведомление о новом сообщении не показываем —
  /// он его и так видит. В фоновом изолите это поле всегда null, поэтому
  /// фоновые пуши не подавляются.
  static String? activeChatGroupId;
  // ─────────────────────────────────────────────

  /// Инициализация FCM: запрашиваем разрешение и сохраняем токен.
  Future<void> initFCM() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // Настраиваем локальные уведомления и канал Android
      await _initLocalNotifications();

      final token = await messaging.getToken();
      if (token != null) await _saveFcmToken(token);

      // Обновляем токен при ротации
      messaging.onTokenRefresh.listen(_saveFcmToken);

      // Сохраняем токен после входа (для новых пользователей, у которых токен ещё не сохранён)
      _auth.authStateChanges().listen((user) async {
        if (user != null) {
          final t = await messaging.getToken();
          if (t != null) await _saveFcmToken(t);
        }
      });

      // Обрабатываем сообщения пока приложение открыто (foreground)
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    } catch (e) {
      debugPrint('initFCM failed: $e');
    }
  }

  static Future<void> _initLocalNotifications() async {
    if (_localNotificationsInitialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@drawable/ic_notification',
    );
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotifications.initialize(settings: initSettings);

    // Создаём канал уведомлений для Android 8+
    const channel = AndroidNotificationChannel(
      _kChannelId,
      _kChannelName,
      description: 'Уведомления от партнёра',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    _localNotificationsInitialized = true;
  }

  /// Ключи SharedPreferences для настроек уведомлений (совпадают с ProfileScreen)
  static const _kNotifMissYou = 'notif_miss_you';
  static const _kNotifNewMemory = 'notif_new_memory';
  static const _kNotifMood = 'notif_mood';
  static const _kNotifChat = 'notif_chat';

  void _handleForegroundMessage(RemoteMessage message) async {
    final shouldShow = await _shouldShowNotification(message);
    if (!shouldShow) return;

    final content = await _buildLocalNotificationContent(message);
    if (content == null) return;

    await _showLocalNotification(
      id: _notificationIdFor(message),
      title: content.title,
      body: content.body,
      channelId: _channelIdFor(message),
    );
  }

  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    if (message.data['type'] == 'widget_update') {
      await _handleWidgetUpdateMessage(message);
      return;
    }

    final shouldShow = await _shouldShowNotification(message);
    if (!shouldShow) return;

    final content = await _buildLocalNotificationContent(message);
    if (content == null) return;

    await _showLocalNotification(
      id: _notificationIdFor(message),
      title: content.title,
      body: content.body,
      channelId: _channelIdFor(message),
    );
  }

  static Future<void> _handleWidgetUpdateMessage(RemoteMessage message) async {
    try {
      final d = message.data;
      // Обновляем ТОЛЬКО присутствующие в сообщении поля. Отсутствующий ключ
      // означает «это поле не менялось» — его нельзя затирать пустой строкой,
      // иначе, например, смена настроения обнуляла статус/сообщение/музыку
      // партнёра на виджете (сервер шлёт лишь изменившиеся поля).
      const keyMap = {
        'status': 'partner_status',
        'moodLabel': 'partner_mood',
        'message': 'partner_message',
        'musicTitle': 'partner_music_title',
        'musicArtist': 'partner_music_artist',
      };
      final updates = <Future<void>>[];
      keyMap.forEach((dataKey, widgetKey) {
        if (d.containsKey(dataKey)) {
          updates.add(
            HomeWidget.saveWidgetData<String>(
              widgetKey,
              (d[dataKey] ?? '').toString(),
            ),
          );
        }
      });
      if (updates.isEmpty) return;
      await Future.wait(updates);
      await HomeWidget.updateWidget(
        name: 'LoveWidgetProvider',
        androidName: 'LoveWidgetProvider',
      );
    } catch (e) {
      debugPrint('_handleWidgetUpdateMessage failed: $e');
    }
  }

  static Future<bool> _shouldShowNotification(RemoteMessage message) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final type = message.data['type'] ?? '';
      if (type == 'miss_you' && !(prefs.getBool(_kNotifMissYou) ?? true)) {
        debugPrint(
          'FCM foreground: miss_you notification suppressed by user prefs',
        );
        return false;
      }
      if (type == 'new_memory' && !(prefs.getBool(_kNotifNewMemory) ?? true)) {
        debugPrint(
          'FCM foreground: new_memory notification suppressed by user prefs',
        );
        return false;
      }
      if (type == 'mood' && !(prefs.getBool(_kNotifMood) ?? true)) {
        debugPrint(
          'FCM foreground: mood notification suppressed by user prefs',
        );
        return false;
      }
      if (type == 'chat') {
        // Пользователь уже открыл именно этот чат — не дублируем уведомление.
        if (activeChatGroupId != null &&
            message.data['groupId'] == activeChatGroupId) {
          debugPrint('FCM foreground: chat open, notification suppressed');
          return false;
        }
        if (!(prefs.getBool(_kNotifChat) ?? true)) {
          debugPrint(
            'FCM foreground: chat notification suppressed by user prefs',
          );
          return false;
        }
      }
    } catch (e) {
      debugPrint('FCM foreground pref check failed: \$e');
    }

    return true;
  }

  static Future<_LocalNotificationContent?> _buildLocalNotificationContent(
    RemoteMessage message,
  ) async {
    final type = message.data['type'] ?? '';

    const vibeTypes = {'miss_you', 'thinking_of_you', 'want_hug', 'custom'};
    if (vibeTypes.contains(type)) {
      await NicknameService.instance.init();
      await LocaleService.instance.init();

      final senderUid = message.data['senderUid'] ?? '';
      final fallbackSenderName = message.data['senderName'] ?? 'Partner';
      final senderName = NicknameService.instance.resolve(
        senderUid,
        fallbackSenderName,
      );
      final strings = LocaleService.current;
      final body = (message.data['body'] ?? '').toString().trim();

      switch (type) {
        case 'miss_you':
          return _LocalNotificationContent(
            title: strings.missYouNotifTitle(senderName),
            body: body.isNotEmpty ? body : strings.missYouNotifBody,
          );
        case 'thinking_of_you':
          return _LocalNotificationContent(
            title: strings.thinkingOfYouNotifTitle(senderName),
            body: body,
          );
        case 'want_hug':
          return _LocalNotificationContent(
            title: strings.wantHugNotifTitle(senderName),
            body: body,
          );
        case 'custom':
          return _LocalNotificationContent(
            title: strings.customVibeNotifTitle(senderName),
            body: body.isNotEmpty ? body : '✉️',
          );
      }
    }

    if (type == 'chat') {
      await NicknameService.instance.init();
      await LocaleService.instance.init();
      final senderUid = message.data['senderUid'] ?? '';
      final fallbackSenderName = message.data['senderName'] ?? 'Partner';
      final senderName = NicknameService.instance.resolve(
        senderUid,
        fallbackSenderName,
      );
      final body = (message.data['body'] ?? '').toString().trim();
      return _LocalNotificationContent(
        title: LocaleService.current.chatNotifTitle(senderName),
        body: body.isNotEmpty ? body : '✉️',
      );
    }

    if (type == 'mood') {
      await NicknameService.instance.init();
      await LocaleService.instance.init();
      final senderUid = message.data['senderUid'] ?? '';
      final fallbackSenderName = message.data['senderName'] ?? 'Partner';
      final senderName = NicknameService.instance.resolve(
        senderUid,
        fallbackSenderName,
      );
      final moodLabel = (message.data['moodLabel'] ?? '').toString().trim();
      // moodLabel хранится на языке отправителя; локализуем только заголовок.
      return _LocalNotificationContent(
        title: LocaleService.current.moodNotifTitle(senderName),
        body: moodLabel.isNotEmpty
            ? moodLabel
            : (message.data['body'] ?? '').toString().trim(),
      );
    }

    final notification = message.notification;
    final title = (notification?.title ?? message.data['title'] ?? '')
        .toString()
        .trim();
    final body = (notification?.body ?? message.data['body'] ?? '')
        .toString()
        .trim();

    if (title.isEmpty && body.isEmpty) return null;

    return _LocalNotificationContent(title: title, body: body);
  }

  /// Публичная обёртка для разовых локальных уведомлений (например, выдача
  /// бейджа спонсора/помощника). Использует общий канал с FCM-уведомлениями.
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
  }) => _showLocalNotification(
    id: id,
    title: title,
    body: body,
    channelId: _kChannelId,
  );

  static Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
    required String channelId,
  }) async {
    await _initLocalNotifications();

    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          _kChannelName,
          channelDescription: 'Уведомления от партнёра',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  static int _notificationIdFor(RemoteMessage message) {
    final messageId = message.messageId;
    if (messageId != null && messageId.isNotEmpty) return messageId.hashCode;
    return Object.hashAll([
      message.data['type'],
      message.data['groupId'],
      message.data['senderUid'],
      message.sentTime?.millisecondsSinceEpoch,
    ]);
  }

  static String _channelIdFor(RemoteMessage message) {
    return message.notification?.android?.channelId ?? _kChannelId;
  }

  Future<void> _saveFcmToken(String token) async {
    final u = currentUser;
    if (u == null) return;
    try {
      // Пишем в Firestore только если токен изменился — иначе каждый запуск
      // делает лишний write в users/{uid}, который тригерит listener у партнёра.
      final prefs = await SharedPreferences.getInstance();
      final key = 'fcmToken_${u.uid}';
      final saved = prefs.getString(key);
      if (saved == token) return;

      await _db.collection('users').doc(u.uid).set({
        'fcmToken': token,
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));

      // Зеркалим токен в RTDB, чтобы Cloud Function пуша читала токены оттуда
      // (даром), а не из users/{uid} (Firestore-чтение на каждый пуш).
      try {
        await _rtdb.ref('push/${u.uid}/tokens').child(token).set(true);
      } catch (e) {
        debugPrint('_saveFcmToken RTDB mirror failed: $e');
      }

      await prefs.setString(key, token);
    } catch (e) {
      debugPrint('_saveFcmToken failed: $e');
    }
  }

  // ── Коины: серверная логика ─────────────────────────────────────────────
  // Клиент НЕ может писать coins/ownedThemes/devCoinsGranted/lastDailyBonusAt/
  // adRewardsDate напрямую. Начисления/списания идут только через сервер:
  //   • _mig-юзеры → Supabase Postgres RPC (supabase/coins.sql), Cloud Functions
  //     для них не нужны;
  //   • остальные → Firebase Cloud Functions (functions/index.js).

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<Map<String, dynamic>?> _callCoinFn(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    final u = currentUser;
    if (u == null) return null;
    // Stage 2: коины через Firebase Cloud Functions (баланс — Firebase, как у
    // старой версии). Stage 3 (_readSb) — через Supabase RPC.
    if (_readSb('')) {
      return _sb.callCoinRpc(name, u.uid, data ?? const {});
    }
    try {
      final res = await _functions
          .httpsCallable(name)
          .call<Map<dynamic, dynamic>>(data ?? const {})
          .timeout(const Duration(seconds: 15));
      return Map<String, dynamic>.from(res.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('$name failed: ${e.code} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('$name failed: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> callGrantCoinsPurchase({
    required String productId,
    required String purchaseToken,
  }) => _callCoinFn('grantCoinsPurchase', {
    'productId': productId,
    'purchaseToken': purchaseToken,
  });

  // ══════════════════════════════════════════════
  //  MEMORIES — shared timeline for each group
  //  Firestore: groups/{groupId}/memories/{memoryId}
  // ══════════════════════════════════════════════

  // ══════════════════════════════════════════════════════════════════════════════
  // FILE UPLOAD (Storage)
  // ══════════════════════════════════════════════════════════════════════════════

  // ── Signed URL ──────────────────────────────────────────────────────────────

  // Кэш подписанных URL: gsPath → {url, expiresAt}.
  // TTL 55 мин — облачная функция выдаёт на 60 мин, буфер 5 мин на запрос.
  final Map<String, _SignedUrlEntry> _signedUrlCache = {};

  /// Получить временный Signed URL для gs:// пути ИЛИ sb:// пути.
  /// Результат кэшируется на 55 минут. https:// URL возвращается как есть.
  /// Резолвит медиа-URL в проигрываемый http(s)-URL для видеоплеера / launchUrl.
  /// sb://→signed (Supabase), gs://bucket/path→signed (CF), http/file→как есть.
  /// Картинки делают то же через StorageImage; видео раньше получало сырой
  /// sb://, из-за чего плеер не запускался (показывалось только превью).
  Future<String> resolveMediaUrl(String url) async {
    if (url.isEmpty) return url;
    // pb:// (PocketBase protected media) → HTTPS c file-токеном. Без этого
    // pb://-видео уходили в плеер нерезолвленными (PlatformException).
    if (PbMediaService().isPbRef(url)) {
      return (await PbMediaService().resolveUrlAuthed(url)) ?? url;
    }
    if (url.startsWith('sb://')) {
      return (await getSignedUrl(url)) ?? url;
    }
    if (url.startsWith('gs://')) {
      final bare = url.replaceFirst(RegExp(r'^gs://[^/]+/'), '');
      return (await getSignedUrl(bare)) ?? url;
    }
    return url; // http(s) или локальный файл — играем как есть
  }

  Future<String?> getSignedUrl(String path) async {
    if (path.isEmpty) return null;
    // Обратная совместимость: старые записи хранят download URL
    if (path.startsWith('http')) return path;
    // Фаза 1: Supabase Storage
    if (path.startsWith('sb://')) {
      debugPrint('[SB] getSignedUrl: resolving $path');
      return _sb.getStorageSignedUrl(path);
    }
    debugPrint('[FB] getSignedUrl: calling Cloud Function for $path');

    final cached = _signedUrlCache[path];
    if (cached != null && cached.isValid) return cached.url;

    try {
      final res = await _functions
          .httpsCallable('getSignedUrl')
          .call<Map<dynamic, dynamic>>({'gsPath': path})
          .timeout(const Duration(seconds: 15));
      final data = Map<String, dynamic>.from(res.data);
      final url = data['url'] as String?;
      final expiresAt = data['expiresAt'] as int?;
      if (url != null && expiresAt != null) {
        _signedUrlCache[path] = _SignedUrlEntry(
          url,
          DateTime.fromMillisecondsSinceEpoch(expiresAt),
        );
        return url;
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint('getSignedUrl failed: ${e.code} ${e.message}');
    } catch (e) {
      debugPrint('getSignedUrl failed: $e');
    }
    return null;
  }

  /// Удалить файл из Firebase Storage (gs:// / https://) или Supabase (sb://).
  Future<void> deleteFileByUrl(String url) async {
    if (url.startsWith('sb://')) {
      await _sb.deleteStorageFile(url);
      return;
    }
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
      debugPrint('deleteFileByUrl: deleted $url');
    } catch (e) {
      debugPrint('deleteFileByUrl failed: $e');
    }
  }

  // ══════════════════════════════════════════════
  //  PRESENCE — отслеживание статуса онлайн/офлайн
  //  RTDB: presence/{uid} = { online: bool, lastSeen: ms-since-epoch }
  //  Хранится в Realtime Database, а не в Firestore: статус дёргается на каждом
  //  foreground/background, а партнёры держат на нём листенер — в Firestore это
  //  выливалось в сотни тысяч чтений users/{uid} в день. RTDB к тому же даёт
  //  honest-offline через onDisconnect при жёстком убийстве приложения.
  // ══════════════════════════════════════════════

  bool? _lastOnlineStatus;
  StreamSubscription<DatabaseEvent>? _presenceConnSub;

  /// Обновляет статус присутствия текущего пользователя.
  /// Вызывается из AppLifecycleListener при переходе foreground/background.
  Future<void> setOnlineStatus(bool isOnline) async {
    final u = currentUser;
    if (u == null) return;
    // AppLifecycleListener fires onPause + onHide + onDetach in quick
    // succession on Android — without this guard every backgrounding paid
    // for redundant presence writes (and reads on the partner side).
    if (_lastOnlineStatus == isOnline) return;
    _lastOnlineStatus = isOnline;
    final ref = _presenceRef(u.uid);
    try {
      if (isOnline) {
        // Re-arm onDisconnect on every (re)connect so a crash/kill flips us
        // offline server-side even after a transient network blip.
        _ensurePresenceConnectionWatcher();
        await ref.onDisconnect().set({
          'online': false,
          'lastSeen': ServerValue.timestamp,
        });
        await ref
            .set({'online': true, 'lastSeen': ServerValue.timestamp})
            .timeout(const Duration(seconds: 8));
      } else {
        // Explicit background/sign-out: cancel the disconnect handler and mark
        // offline now.
        await ref.onDisconnect().cancel();
        await ref
            .set({'online': false, 'lastSeen': ServerValue.timestamp})
            .timeout(const Duration(seconds: 8));
      }
      debugPrint('setOnlineStatus: uid=${u.uid}, isOnline=$isOnline');
    } catch (e) {
      // Restore so a retry attempt can go through.
      _lastOnlineStatus = null;
      debugPrint('setOnlineStatus failed: $e');
    }
  }

  /// Пока мы считаем себя онлайн, при каждом восстановлении RTDB-соединения
  /// заново ставим online:true и перевешиваем onDisconnect (он одноразовый —
  /// после срабатывания на разрыве его нужно вооружить снова).
  void _ensurePresenceConnectionWatcher() {
    _presenceConnSub ??= _rtdb.ref('.info/connected').onValue.listen((
      event,
    ) async {
      if (event.snapshot.value != true) return;
      final u = currentUser;
      if (u == null || _lastOnlineStatus != true) return;
      final ref = _presenceRef(u.uid);
      try {
        await ref.onDisconnect().set({
          'online': false,
          'lastSeen': ServerValue.timestamp,
        });
        await ref.set({'online': true, 'lastSeen': ServerValue.timestamp});
      } catch (_) {}
    });
  }

  /// Снимает watcher соединения (при выходе из аккаунта).
  void _disposePresenceWatcher() {
    _presenceConnSub?.cancel();
    _presenceConnSub = null;
  }
}

class _LocalNotificationContent {
  final String title;
  final String body;

  const _LocalNotificationContent({required this.title, required this.body});
}

class _SignedUrlEntry {
  final String url;
  final DateTime expiresAt;
  _SignedUrlEntry(this.url, this.expiresAt);
  // Считаем валидным пока до истечения больше 5 минут
  bool get isValid => expiresAt.difference(DateTime.now()).inMinutes > 5;
}
