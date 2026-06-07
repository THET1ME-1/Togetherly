import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
// Transaction скрыт: коллизия имён с firebase_database (RTDB-транзакция в
// _seedMissYouCountsIfEmpty). Firestore-транзакции используют выводимый тип
// колбэка `(tx)`, поэтому имя Transaction из cloud_firestore тут не нужно.
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
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
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:home_widget/home_widget.dart';
import 'package:video_compress/video_compress.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/mascot.dart';
import '../models/memory.dart';
import '../models/comment.dart';
import '../models/timer_item.dart';
import 'analytics_service.dart';
import 'locale_service.dart';
import 'nickname_service.dart';
import 'rate_limiter_service.dart';

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
  FirebaseService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

  /// Realtime Database (presence). Регион europe-west1, см. [_kRtdbUrl].
  FirebaseDatabase get _rtdb =>
      FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: _kRtdbUrl);

  DatabaseReference _presenceRef(String uid) => _rtdb.ref('presence/$uid');

  /// Счётчики «Я скучаю» по группе. Живут в RTDB, а не в Firestore: фича — №1
  /// по нажатиям, и хранение счётчика в живо-слушаемом group-doc заставляло
  /// listenToPair/listenToMissYouCount пере-читать документ на каждый тап у
  /// обоих партнёров. Здесь только per-user счётчики; total = их сумма.
  /// Пуш-уведомления по-прежнему идут через Firestore missYouEvents → функцию.
  DatabaseReference _missYouCountsRef(String groupId) =>
      _rtdb.ref('missYou/$groupId/counts');

  /// Кеш участников группы из последнего [_parseGroupDoc]. Нужен, чтобы класть
  /// recipientUids прямо в missYouEvents и Cloud Function пуша не читала
  /// group-doc на каждый тап. Самовосстанавливается при любом изменении группы.
  final Map<String, List<String>> _groupMembersCache = {};

  /// Получатели пуша = участники группы из кеша минус отправитель.
  /// Пусто, если кеш ещё холодный — тогда функция читает group-doc сама.
  List<String> _cachedRecipients(String groupId, String senderUid) {
    final members = _groupMembersCache[groupId];
    if (members == null) return const [];
    return members.where((m) => m.isNotEmpty && m != senderUid).toList();
  }

  /// Группы, для которых уже выполнен (или запущен) разовый перенос счётчиков
  /// «Я скучаю» из Firestore в RTDB в этой сессии.
  final Set<String> _missYouSeeded = {};

  /// Переносит старый Firestore-счётчик «Я скучаю» текущего пользователя в RTDB.
  /// Idempotent и reset-безопасно.
  ///
  /// Мигрируем ТОЛЬКО свой uid (`counts/{myUid}`) — тем же путём/правом, что и
  /// боевой инкремент в [sendMissYou]. Свой legacy-счёт переносит каждое
  /// устройство само, поэтому не нужна запись в чужие узлы (её запретят
  /// security-правила RTDB). Транзакция ставит значение лишь когда узел ещё
  /// пуст: живой счётчик никогда не затирается.
  ///
  /// Раньше тут был check-then-`set()` ЦЕЛОГО узла counts: между чтением
  /// «пусто» и записью мог пройти тап (или сид со второго устройства), и `set`
  /// откатывал счётчик к замороженному legacy-значению.
  Future<void> _seedMissYouCountsIfEmpty(String groupId, Map raw) async {
    final myUid = uid;
    if (myUid == null) return;
    final mine = (raw[myUid] as num?)?.toInt() ?? 0;
    if (mine <= 0) return;
    try {
      await _missYouCountsRef(groupId).child(myUid).runTransaction((current) {
        // Уже есть живое значение — не трогаем (никаких откатов).
        if (current != null) return Transaction.abort();
        return Transaction.success(mine);
      });
    } catch (e) {
      debugPrint('_seedMissYouCountsIfEmpty failed: $e');
    }
  }

  // In-memory cache — eliminates repeated users/{uid} reads on hot paths.
  String? _cachedDisplayName;
  String? _cachedAvatarUrl;

  // Ref-counted, multiplexed snapshot listeners for hot single-doc paths.
  // Each group doc had 4+ independent snapshot subscriptions
  // (listenToPair / listenToTimers / listenToMissYouCount / listenToMissYouCounts /
  //  listenToCanvasBgColor + ...). Firestore meters each subscription separately,
  // so a single field change was billed 4+ times. The hub keeps ONE underlying
  // snapshot per groupId and fans the data out to every consumer.
  final Map<String, _DocSnapshotHub> _groupDocHubs = {};
  final Map<String, _DocSnapshotHub> _userDocHubs = {};

  Stream<DocumentSnapshot<Map<String, dynamic>>> _groupDocStream(String groupId) {
    return _groupDocHubs
        .putIfAbsent(
          groupId,
          () => _DocSnapshotHub(_db.collection('groups').doc(groupId)),
        )
        .stream;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _userDocStream(String uid) {
    return _userDocHubs
        .putIfAbsent(
          uid,
          () => _DocSnapshotHub(_db.collection('users').doc(uid)),
        )
        .stream;
  }

  // ══════════════════════════════════════════════
  //  AUTH
  // ══════════════════════════════════════════════

  User? get currentUser => _auth.currentUser;
  bool get isLoggedIn => _auth.currentUser != null;
  String? get uid => _auth.currentUser?.uid;

  /// Cached display name — use this instead of reading users/{uid} from Firestore.
  String get displayName => _cachedDisplayName ?? _auth.currentUser?.displayName ?? '';

  /// Cached avatar URL — always reflects the latest save, even before Firestore syncs.
  String get avatarUrl => _cachedAvatarUrl ?? _auth.currentUser?.photoURL ?? '';

  Future<User?> signInWithGoogle() async {
    try {
      final googleAccount = await _googleSignIn.signIn().timeout(
        const Duration(seconds: 30),
      );
      if (googleAccount == null) return null;

      final googleAuth = await googleAccount.authentication.timeout(
        const Duration(seconds: 15),
      );
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      debugPrint('Firebase Auth: signing in...');
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) return null;

      debugPrint('Firebase Auth success: ${user.uid}');

      try {
        await _db
            .collection('users')
            .doc(user.uid)
            .set({
              'displayName': user.displayName ?? '',
              'email': user.email ?? '',
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('Firestore save failed: $e');
      }

      return user;
    } catch (e) {
      debugPrint('signInWithGoogle failed: $e');
      rethrow;
    }
  }

  /// Создание аккаунта через email/пароль
  Future<User?> signUpWithEmailPassword({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      debugPrint('Firebase Auth: creating account with email...');
      final userCredential = await _auth
          .createUserWithEmailAndPassword(email: email, password: password)
          .timeout(const Duration(seconds: 15));
      final user = userCredential.user;
      if (user == null) return null;

      // Обновляем displayName
      await user.updateDisplayName(displayName);
      await user.reload();

      debugPrint('Firebase Auth success: ${user.uid}');

      try {
        await _db
            .collection('users')
            .doc(user.uid)
            .set({
              'displayName': displayName,
              'email': email,
              'avatarUrl': '',
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('Firestore save failed: $e');
      }

      return _auth.currentUser;
    } catch (e) {
      debugPrint('signUpWithEmailPassword failed: $e');
      rethrow;
    }
  }

  /// Вход через email/пароль
  Future<User?> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      debugPrint('Firebase Auth: signing in with email...');
      final userCredential = await _auth
          .signInWithEmailAndPassword(email: email, password: password)
          .timeout(const Duration(seconds: 15));
      return userCredential.user;
    } catch (e) {
      debugPrint('signInWithEmailPassword failed: $e');
      rethrow;
    }
  }

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

  /// Тихий вход без показа диалога Google.
  /// Восстанавливает сессию при перезапуске приложения:
  /// сначала проверяет кэш Firebase Auth, затем пробует GoogleSignIn.signInSilently().
  Future<User?> signInSilently() async {
    try {
      // Firebase Auth уже авторизован — возвращаем текущего пользователя
      final current = _auth.currentUser;
      if (current != null) return current;

      // Пробуем восстановить Google-аккаунт без диалога
      final googleAccount = await _googleSignIn.signInSilently();
      if (googleAccount == null) return null;

      final googleAuth = await googleAccount.authentication.timeout(
        const Duration(seconds: 15),
      );
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      debugPrint('signInSilently success: ${userCredential.user?.uid}');
      return userCredential.user;
    } catch (e) {
      debugPrint('signInSilently failed: $e');
      return null;
    }
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

  /// Сохраняет настройку уведомлений в Firestore, чтобы Cloud Functions
  /// могли проверять её перед отправкой push-уведомлений.
  Future<void> updateNotifPrefs({
    bool? missYou,
    bool? newMemory,
    bool? mood,
    bool? chat,
  }) async {
    final u = currentUser;
    if (u == null) return;
    final updates = <String, dynamic>{};
    if (missYou != null) updates['notifMissYou'] = missYou;
    if (newMemory != null) updates['notifNewMemory'] = newMemory;
    if (mood != null) updates['notifMood'] = mood;
    if (chat != null) updates['notifChat'] = chat;
    if (updates.isEmpty) return;
    try {
      await _db
          .collection('users')
          .doc(u.uid)
          .set(updates, SetOptions(merge: true));
      // Зеркалим настройку «Я скучаю» в RTDB — функция пуша читает её оттуда
      // вместе с токенами, без Firestore-чтения.
      if (missYou != null) {
        try {
          await _rtdb.ref('push/${u.uid}/notifMissYou').set(missYou);
        } catch (e) {
          debugPrint('updateNotifPrefs RTDB mirror failed: $e');
        }
      }
    } catch (e) {
      debugPrint('updateNotifPrefs failed: \$e');
    }
  }

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

    const _vibeTypes = {'miss_you', 'thinking_of_you', 'want_hug', 'custom'};
    if (_vibeTypes.contains(type)) {
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
  }) =>
      _showLocalNotification(
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

  // ══════════════════════════════════════════════
  //  EMAIL LINK AUTHENTICATION (Passwordless)
  // ══════════════════════════════════════════════

  /// Отправить ссылку для входа на электронную почту
  Future<bool> sendSignInLinkToEmail(String email) async {
    try {
      debugPrint('Firebase Auth: sending sign-in link to $email');

      final actionCodeSettings = ActionCodeSettings(
        // URL для перенаправления - используем web.app домен
        url: 'https://togetherly-d4856.web.app/',
        handleCodeInApp: true,
        androidPackageName: 'com.togetherly.love',
        androidInstallApp: true,
        androidMinimumVersion: '21',
      );

      await _auth.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: actionCodeSettings,
      );

      debugPrint('Sign-in link sent successfully');
      return true;
    } catch (e) {
      debugPrint('sendSignInLinkToEmail failed: $e');
      return false;
    }
  }

  /// Проверить, является ли ссылка ссылкой для входа
  bool isSignInWithEmailLink(String emailLink) {
    return _auth.isSignInWithEmailLink(emailLink);
  }

  /// Войти используя ссылку из email
  Future<User?> signInWithEmailLink({
    required String email,
    required String emailLink,
  }) async {
    try {
      debugPrint('Firebase Auth: signing in with email link...');

      final userCredential = await _auth.signInWithEmailLink(
        email: email,
        emailLink: emailLink,
      );

      final user = userCredential.user;
      if (user == null) return null;

      debugPrint('Firebase Auth success: ${user.uid}');

      // Сохранить профиль в Firestore
      try {
        await _db
            .collection('users')
            .doc(user.uid)
            .set({
              'displayName': user.displayName ?? '',
              'email': user.email ?? '',
              'avatarUrl': user.photoURL ?? '',
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('Firestore save failed: $e');
      }

      return user;
    } catch (e) {
      debugPrint('signInWithEmailLink failed: $e');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════
  //  USER PROFILE
  // ══════════════════════════════════════════════

  Future<void> saveUserProfile({
    required String displayName,
    required String email,
    required String gender,
    String avatarUrl = '',
    bool clearPairData = false,
  }) async {
    final u = currentUser;
    if (u == null) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final data = <String, dynamic>{
        'displayName': displayName,
        'email': email,
        'gender': gender,
        'appVersion': '${info.version}+${info.buildNumber}',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Only write avatarUrl if non-empty — never overwrite a real avatar with ''
      if (avatarUrl.isNotEmpty) {
        data['avatarUrl'] = avatarUrl;
      }

      // Clear pair data if this is a new registration
      if (clearPairData) {
        data['pairId'] = '';
        data['pairIds'] = [];
      }

      await _db
          .collection('users')
          .doc(u.uid)
          .set(data, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
      _cachedDisplayName = displayName;
      if (avatarUrl.isNotEmpty) _cachedAvatarUrl = avatarUrl;
    } catch (e) {
      debugPrint('saveUserProfile failed: $e');
    }
  }

  // ── Коины: вызовы серверных Cloud Functions ─────────────────────────────
  // Клиент НЕ может писать поля coins/ownedThemes/devCoinsGranted/lastDailyBonusAt/
  // adRewardsDate/adRewardsToday напрямую — это запрещено Firestore Rules.
  // Все начисления и списания идут только через эти вызовы.

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<Map<String, dynamic>?> _callCoinFn(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    if (currentUser == null) return null;
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

  Future<Map<String, dynamic>?> callPurchaseTheme(int themeId) =>
      _callCoinFn('purchaseTheme', {'themeId': themeId});

  Future<Map<String, dynamic>?> callPurchaseIcon(String iconId) =>
      _callCoinFn('purchaseIcon', {'iconId': iconId});

  Future<Map<String, dynamic>?> callPurchaseFeature(String featureId) =>
      _callCoinFn('purchaseFeature', {'featureId': featureId});

  Future<Map<String, dynamic>?> callSpendCoins(String actionId) =>
      _callCoinFn('spendCoins', {'actionId': actionId});

  Future<Map<String, dynamic>?> callGrantDailyBonus() =>
      _callCoinFn('grantDailyBonus');

  Future<Map<String, dynamic>?> callGrantCoinsPurchase({
    required String productId,
    required String purchaseToken,
  }) =>
      _callCoinFn('grantCoinsPurchase', {
        'productId': productId,
        'purchaseToken': purchaseToken,
      });

  Future<Map<String, dynamic>?> callGrantDevCoins() =>
      _callCoinFn('grantDevCoins');

  Future<Map<String, dynamic>?> callGrantMemoryReward() =>
      _callCoinFn('grantMemoryReward');

  /// Начисляет награду за rewarded-видео Яндекса (у которого нет Google-SSV).
  /// Сервер enforce'ит дневной лимит; счётчик общий с AdMob-SSV.
  Future<Map<String, dynamic>?> callGrantAdReward() =>
      _callCoinFn('grantAdReward');

  Future<Map<String, dynamic>?> callGrantPartnerInviteReward() =>
      _callCoinFn('grantPartnerInviteReward');

  Future<Map<String, dynamic>?> callGrantMoodStreakReward(String groupId) =>
      _callCoinFn('grantMoodStreakReward', {'groupId': groupId});

  /// Устанавливает закреплённую иконку-бейдж пользователя.
  /// Пустая строка снимает иконку (записывает пустое значение).
  Future<void> setBadge(String badge) async {
    final u = currentUser;
    if (u == null) return;
    try {
      await _db
          .collection('users')
          .doc(u.uid)
          .set({'badge': badge}, SetOptions(merge: true))
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('setBadge failed: $e');
    }
  }

  /// Сохраняет список выданных иконок-наград (Sponsor/Helper) и, опционально,
  /// текущий закреплённый бейдж за одну запись.
  Future<void> saveGrantedBadges(List<String> grantedBadges,
      {String? badge}) async {
    final u = currentUser;
    if (u == null) return;
    try {
      final data = <String, dynamic>{'grantedBadges': grantedBadges};
      if (badge != null) data['badge'] = badge;
      await _db
          .collection('users')
          .doc(u.uid)
          .set(data, SetOptions(merge: true))
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('saveGrantedBadges failed: $e');
    }
  }

  /// Updates the user's avatar URL in all groups they belong to.
  /// This ensures that partner devices receive the new avatar via the group listener.
  Future<void> updateNameInGroups(String displayName) async {
    final u = currentUser;
    if (u == null) return;
    try {
      final userDoc = await _db.collection('users').doc(u.uid).get();
      if (!userDoc.exists) return;
      final userData = userDoc.data()!;

      final pairIds = <String>{};
      final legacyPairId = userData['pairId'] as String?;
      if (legacyPairId != null && legacyPairId.isNotEmpty) {
        pairIds.add(legacyPairId);
      }
      final pairIdsList = userData['pairIds'] as List<dynamic>?;
      if (pairIdsList != null) {
        pairIds.addAll(
          pairIdsList.whereType<String>().where((s) => s.isNotEmpty),
        );
      }

      final nameBatch = _db.batch();
      for (final groupId in pairIds) {
        nameBatch.update(
          _db.collection('groups').doc(groupId),
          {'memberNames.${u.uid}': displayName},
        );
      }
      await nameBatch.commit().timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('updateNameInGroups failed: $e');
    }
  }

  Future<void> updateAvatarInGroups(String avatarUrl) async {
    final u = currentUser;
    if (u == null) return;
    try {
      final userDoc = await _db.collection('users').doc(u.uid).get();
      if (!userDoc.exists) return;
      final userData = userDoc.data()!;

      final pairIds = <String>{};
      final legacyPairId = userData['pairId'] as String?;
      if (legacyPairId != null && legacyPairId.isNotEmpty) {
        pairIds.add(legacyPairId);
      }
      final pairIdsList = userData['pairIds'] as List<dynamic>?;
      if (pairIdsList != null) {
        pairIds.addAll(
          pairIdsList.whereType<String>().where((s) => s.isNotEmpty),
        );
      }

      final avatarBatch = _db.batch();
      for (final groupId in pairIds) {
        avatarBatch.update(
          _db.collection('groups').doc(groupId),
          {'memberAvatars.${u.uid}': avatarUrl},
        );
      }
      await avatarBatch.commit().timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('updateAvatarInGroups failed: $e');
    }
  }

  Future<Map<String, dynamic>?> loadUserProfile({bool fromServer = false}) async {
    final u = currentUser;
    if (u == null) return null;
    try {
      final doc = await _db
          .collection('users')
          .doc(u.uid)
          .get(fromServer ? const GetOptions(source: Source.server) : null)
          .timeout(const Duration(seconds: 10));
      final data = doc.data();
      if (data != null) {
        _cachedDisplayName = data['displayName'] as String?;
        _cachedAvatarUrl = data['avatarUrl'] as String?;
      }
      return data;
    } catch (e) {
      debugPrint('loadUserProfile failed: $e');
      // On network error fall back to cache
      if (fromServer) {
        try {
          final cached = await _db
              .collection('users')
              .doc(u.uid)
              .get(const GetOptions(source: Source.cache));
          final cachedData = cached.data();
          if (cachedData != null) {
            _cachedDisplayName = cachedData['displayName'] as String?;
            _cachedAvatarUrl = cachedData['avatarUrl'] as String?;
          }
          return cachedData;
        } catch (_) {}
      }
      return null;
    }
  }

  // ══════════════════════════════════════════════
  //  INVITE CODES
  // ══════════════════════════════════════════════

  Future<String> generateInviteCode() async {
    final u = currentUser;
    if (u == null) return '';

    try {
      final userDoc = await _db
          .collection('users')
          .doc(u.uid)
          .get()
          .timeout(const Duration(seconds: 10));
      final existingCode = userDoc.data()?['inviteCode'] as String?;
      if (existingCode != null && existingCode.isNotEmpty) {
        return existingCode;
      }

      String code;
      bool exists;
      do {
        code = _generateCode();
        final codeDoc = await _db
            .collection('inviteCodes')
            .doc(code)
            .get()
            .timeout(const Duration(seconds: 5));
        exists = codeDoc.exists;
      } while (exists);

      final batch = _db.batch();
      batch.set(_db.collection('inviteCodes').doc(code), {
        'ownerUid': u.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.update(_db.collection('users').doc(u.uid), {'inviteCode': code});
      await batch.commit().timeout(const Duration(seconds: 10));

      return code;
    } catch (e) {
      debugPrint('generateInviteCode failed: $e');
      return '';
    }
  }

  Future<String> generateNewInviteCode({String? oldCode}) async {
    final u = currentUser;
    if (u == null) return '';

    // Force-refresh the ID token so Firestore always sees a valid auth claim.
    // This is critical for freshly-created email accounts where the token may
    // not have propagated to Firestore's security backend yet.
    try {
      await u.getIdToken(true);
    } catch (_) {}

    Future<String> attempt() async {
      if (oldCode != null && oldCode.isNotEmpty) {
        try {
          await _db.collection('inviteCodes').doc(oldCode).delete();
        } catch (_) {}
      }

      String code;
      bool exists;
      do {
        code = _generateCode();
        final codeDoc = await _db
            .collection('inviteCodes')
            .doc(code)
            .get()
            .timeout(const Duration(seconds: 5));
        exists = codeDoc.exists;
      } while (exists);

      await _db
          .collection('inviteCodes')
          .doc(code)
          .set({'ownerUid': u.uid, 'createdAt': FieldValue.serverTimestamp()})
          .timeout(const Duration(seconds: 10));

      return code;
    }

    try {
      return await attempt();
    } catch (e) {
      debugPrint('generateNewInviteCode first attempt failed: $e — retrying…');
      // Retry once after a short pause + token refresh (email sign-up timing fix)
      try {
        await Future.delayed(const Duration(milliseconds: 800));
        await u.getIdToken(true);
        return await attempt();
      } catch (e2) {
        debugPrint('generateNewInviteCode retry failed: $e2');
        return '';
      }
    }
  }

  /// Returns true if [code] exists in Firestore and belongs to the current user.
  /// Returns true (don't invalidate) on network errors.
  Future<bool> isOwnedInviteCodeValid(String code) async {
    if (code.isEmpty) return false;
    final u = currentUser;
    if (u == null) return false;
    try {
      final doc = await _db
          .collection('inviteCodes')
          .doc(code)
          .get()
          .timeout(const Duration(seconds: 5));
      return doc.exists && doc.data()?['ownerUid'] == u.uid;
    } catch (_) {
      return true; // network error — assume valid, don't wipe it
    }
  }

  /// Checks whether [code] exists on the Firestore SERVER (bypasses local cache).
  /// Returns true  → code is confirmed on server and owned by current user.
  /// Returns false → code is not on server (was never written or write failed).
  /// Returns null  → offline / unreachable, cannot determine.
  Future<bool?> isInviteCodeOnServer(String code) async {
    if (code.isEmpty) return false;
    final u = currentUser;
    if (u == null) return false;
    try {
      final doc = await _db
          .collection('inviteCodes')
          .doc(code)
          .get(GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 6));
      return doc.exists && doc.data()?['ownerUid'] == u.uid;
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable' || e.code == 'failed-precondition') {
        return null; // offline
      }
      return false;
    } catch (_) {
      return null; // timeout or other error — treat as offline
    }
  }

  /// Create invite code tied to a specific group (for adding more members)
  Future<String> generateGroupInviteCode(
    String groupId, {
    String? oldCode,
  }) async {
    final u = currentUser;
    if (u == null) return '';

    try {
      if (oldCode != null && oldCode.isNotEmpty) {
        await _db.collection('inviteCodes').doc(oldCode).delete();
      }

      String code;
      bool exists;
      do {
        code = _generateCode();
        final codeDoc = await _db
            .collection('inviteCodes')
            .doc(code)
            .get()
            .timeout(const Duration(seconds: 5));
        exists = codeDoc.exists;
      } while (exists);

      await _db
          .collection('inviteCodes')
          .doc(code)
          .set({
            'ownerUid': u.uid,
            'groupId': groupId,
            'createdAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 10));

      return code;
    } catch (e) {
      debugPrint('generateGroupInviteCode failed: $e');
      return '';
    }
  }

  Future<String> regenerateInviteCode({String? oldCode}) async {
    return generateNewInviteCode(oldCode: oldCode);
  }

  // ══════════════════════════════════════════════
  //  GROUPS (replaces old PAIRING)
  //
  //  Firestore structure:
  //    groups/{groupId}:
  //      members: [uid1, uid2, ...]
  //      memberNames: {uid1: "Alice", uid2: "Bob"}
  //      memberAvatars: {uid1: "url", uid2: "url"}
  //      maxMembers: 2 | 10
  //      startDate: Timestamp
  //      createdAt: Timestamp
  //
  //    users/{uid}:
  //      pairId: "last groupId" (legacy compat)
  //      pairIds: ["groupId1", "groupId2"]
  // ══════════════════════════════════════════════

  /// Accept invite code → join or create a group.
  Future<Map<String, dynamic>> acceptInviteCode(String code) async {
    final u = currentUser;
    if (u == null) return {'success': false, 'message': 'Не авторизован'};

    code = code.toUpperCase().trim();
    debugPrint('acceptInviteCode: looking up code $code');

    try {
      final codeDoc = await _db.collection('inviteCodes').doc(code).get();
      if (!codeDoc.exists) {
        debugPrint('acceptInviteCode: code not found');
        return {'success': false, 'message': 'Код не найден'};
      }

      final ownerUid = codeDoc.data()!['ownerUid'] as String;
      if (ownerUid == u.uid) {
        return {'success': false, 'message': 'Это ваш собственный код!'};
      }

      // Check if there's a groupId tied to this code
      final codeGroupId = codeDoc.data()!['groupId'] as String?;
      debugPrint('acceptInviteCode: owner=$ownerUid, groupId=$codeGroupId');

      final ownerDoc = await _db.collection('users').doc(ownerUid).get();
      if (!ownerDoc.exists) {
        return {'success': false, 'message': 'Пользователь не найден'};
      }
      final ownerData = ownerDoc.data()!;

      final myDoc = await _db.collection('users').doc(u.uid).get();
      final myData = myDoc.data() ?? {};

      // If code has a groupId → join existing group
      if (codeGroupId != null && codeGroupId.isNotEmpty) {
        debugPrint('acceptInviteCode: code has groupId, joining $codeGroupId');
        return _joinExistingGroup(
          groupId: codeGroupId,
          code: code,
          myData: myData,
          ownerUid: ownerUid,
          ownerData: ownerData,
        );
      }

      // Code has no groupId — check if the owner already has a group
      final ownerPairId = ownerData['pairId'] as String?;
      bool canJoinOwnerGroup = false;

      if (ownerPairId != null && ownerPairId.isNotEmpty) {
        debugPrint(
          'acceptInviteCode: owner has pairId=$ownerPairId, trying to join',
        );
        try {
          final groupDoc = await _db
              .collection('groups')
              .doc(ownerPairId)
              .get();
          if (groupDoc.exists) {
            final groupData = groupDoc.data()!;
            final groupMembers = List<String>.from(groupData['members'] ?? []);
            // Already in this group together — no need to do anything
            if (groupMembers.contains(ownerUid) &&
                groupMembers.contains(u.uid)) {
              return {
                'success': false,
                'message': 'Вы уже подключены к этому пользователю',
              };
            }
            if (groupMembers.contains(ownerUid) &&
                !groupMembers.contains(u.uid)) {
              // Check if I already have a different pairId
              final myPairId = myData['pairId'] as String?;
              if (myPairId != null &&
                  myPairId.isNotEmpty &&
                  myPairId != ownerPairId) {
                // I'm already in a different group — don't join, create new group instead
                debugPrint(
                  'acceptInviteCode: I have different group $myPairId, cannot join $ownerPairId',
                );
                canJoinOwnerGroup = false;
              } else {
                canJoinOwnerGroup = true;
                return _joinExistingGroup(
                  groupId: ownerPairId,
                  code: code,
                  myData: myData,
                  ownerUid: ownerUid,
                  ownerData: ownerData,
                );
              }
            }
          }
        } catch (e) {
          debugPrint('acceptInviteCode: reading owner group failed: $e');
          // Can't read group (not a member) — just create a new one
        }
      }

      // Also check owner's pairIds list for any group we can join
      final ownerPairIds = ownerData['pairIds'] as List<dynamic>?;
      if (ownerPairIds != null &&
          ownerPairIds.isNotEmpty &&
          !canJoinOwnerGroup) {
        for (var pid in ownerPairIds) {
          final pidStr = pid.toString();
          if (pidStr.isEmpty) continue;
          try {
            final groupDoc = await _db.collection('groups').doc(pidStr).get();
            if (groupDoc.exists) {
              final groupData = groupDoc.data()!;
              final groupMembers = List<String>.from(
                groupData['members'] ?? [],
              );
              // Already in this group together — no need to do anything
              if (groupMembers.contains(ownerUid) &&
                  groupMembers.contains(u.uid)) {
                return {
                  'success': false,
                  'message': 'Вы уже подключены к этому пользователю',
                };
              }
              if (groupMembers.contains(ownerUid) &&
                  !groupMembers.contains(u.uid)) {
                // Check if I already have a different pairId
                final myPairId = myData['pairId'] as String?;
                if (myPairId != null &&
                    myPairId.isNotEmpty &&
                    myPairId != pidStr) {
                  // I'm already in a different group — skip this one and try next
                  debugPrint(
                    'acceptInviteCode: I have different group $myPairId, cannot join $pidStr',
                  );
                  continue;
                }
                return _joinExistingGroup(
                  groupId: pidStr,
                  code: code,
                  myData: myData,
                  ownerUid: ownerUid,
                  ownerData: ownerData,
                );
              }
            }
          } catch (e) {
            debugPrint('acceptInviteCode: reading group $pidStr failed: $e');
            // Can't read group — skip
          }
        }
      }

      // Check if there's a disbanded group between these two users to restore
      final disbandedId = await _findDisbandedGroup(ownerUid);
      if (disbandedId != null) {
        debugPrint('acceptInviteCode: restoring disbanded group $disbandedId');
        return _restoreGroup(
          groupId: disbandedId,
          code: code,
          ownerUid: ownerUid,
          ownerData: ownerData,
          myData: myData,
        );
      }

      // Owner has no group yet — create a new 2-person group (pair)
      debugPrint(
        'acceptInviteCode: creating new group for $ownerUid + ${u.uid}',
      );
      return _createNewGroup(
        code: code,
        ownerUid: ownerUid,
        ownerData: ownerData,
        myData: myData,
      );
    } catch (e) {
      debugPrint('acceptInviteCode FAILED: $e');
      return {'success': false, 'message': 'Ошибка: $e'};
    }
  }

  /// Create a brand new group between owner and current user.
  Future<Map<String, dynamic>> _createNewGroup({
    required String code,
    required String ownerUid,
    required Map<String, dynamic> ownerData,
    required Map<String, dynamic> myData,
  }) async {
    final u = currentUser!;
    final groupRef = _db.collection('groups').doc();
    final now = FieldValue.serverTimestamp();

    // Step 1: Create the group document (allowed by create rule)
    await groupRef.set({
      'members': [ownerUid, u.uid],
      'memberNames': {
        ownerUid: ownerData['displayName'] ?? '',
        u.uid: myData['displayName'] ?? u.displayName ?? '',
      },
      'memberAvatars': {
        ownerUid: ownerData['avatarUrl'] ?? '',
        u.uid: myData['avatarUrl'] ?? u.photoURL ?? '',
      },
      'maxMembers': 2,
      'relationshipType': 'couple',
      'customRelationshipLabel': '',
      'customRelationshipEmoji': '',
      'customRelationshipTypes': <Map<String, String>>[],
      'memoriesCount': 0,
      'drawingsCount': 0,
      'startDate': now,
      'createdAt': now,
    });
    debugPrint('_createNewGroup: group ${groupRef.id} created');

    // Step 2: Update MY user document (allowed — own doc)
    await _db.collection('users').doc(u.uid).update({
      'pairId': groupRef.id,
      'pairIds': FieldValue.arrayUnion([groupRef.id]),
    });
    debugPrint('_createNewGroup: my user doc updated');

    // Step 3: Update OWNER's user document (allowed by new rules — only pairId/pairIds)
    try {
      await _db.collection('users').doc(ownerUid).update({
        'pairId': groupRef.id,
        'pairIds': FieldValue.arrayUnion([groupRef.id]),
      });
      debugPrint('_createNewGroup: owner user doc updated');
    } catch (e) {
      debugPrint(
        '_createNewGroup: owner doc update failed (owner will pick it up via listener): $e',
      );
      // Not critical — owner's real-time listener will detect the group
    }

    // Step 4: Delete invite code (allowed by new rules)
    try {
      await _db.collection('inviteCodes').doc(code).delete();
      debugPrint('_createNewGroup: invite code $code deleted');
    } catch (e) {
      debugPrint('_createNewGroup: could not delete invite code: $e');
    }

    return {
      'success': true,
      'message': 'Connected!',
      'partnerName': ownerData['displayName'] ?? 'Partner',
      'partnerAvatar': ownerData['avatarUrl'] ?? '',
      'pairId': groupRef.id,
      'startDate': DateTime.now(),
      'relationshipType': 'couple',
      'customRelationshipLabel': '',
      'customRelationshipEmoji': '',
      'customRelationshipTypes': <Map<String, String>>[],
      'members': [
        {
          'uid': ownerUid,
          'name': ownerData['displayName'] ?? 'Partner',
          'avatar': ownerData['avatarUrl'] ?? '',
        },
        {
          'uid': u.uid,
          'name': myData['displayName'] ?? u.displayName ?? 'You',
          'avatar': myData['avatarUrl'] ?? u.photoURL ?? '',
        },
      ],
    };
  }

  /// Find a disbanded group that contains both the current user and [ownerUid].
  /// Returns the groupId of the most recently disbanded match, or null.
  ///
  /// Queries by membership instead of reading the user's pairIds: a disbanded
  /// group is REMOVED from both members' pairIds at leave time (see
  /// [unpairById]), so it can no longer be found there. The `members` array is
  /// left intact on soft-delete, so an `arrayContains` query still finds it —
  /// and stays scoped to the user's own groups (not the whole collection).
  Future<String?> _findDisbandedGroup(String ownerUid) async {
    final u = currentUser;
    if (u == null) return null;
    try {
      final snap = await _db
          .collection('groups')
          .where('members', arrayContains: u.uid)
          .get();

      String? bestId;
      Timestamp? bestTs;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['disbanded'] != true) continue;
        final docMembers = List<String>.from(data['members'] ?? []);
        if (!docMembers.contains(ownerUid)) continue;
        final ts = data['disbandedAt'] as Timestamp?;
        if (bestId == null ||
            (ts != null && (bestTs == null || ts.compareTo(bestTs) > 0))) {
          bestId = doc.id;
          bestTs = ts;
        }
      }
      return bestId;
    } catch (e) {
      debugPrint('_findDisbandedGroup error: $e');
      return null;
    }
  }

  /// Restore a disbanded group when the same two users reconnect.
  Future<Map<String, dynamic>> _restoreGroup({
    required String groupId,
    required String code,
    required String ownerUid,
    required Map<String, dynamic> ownerData,
    required Map<String, dynamic> myData,
  }) async {
    final u = currentUser!;
    Map<String, dynamic> groupData;
    try {
      final groupDoc = await _db.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) {
        return _createNewGroup(
          code: code,
          ownerUid: ownerUid,
          ownerData: ownerData,
          myData: myData,
        );
      }
      groupData = groupDoc.data()!;
    } catch (e) {
      debugPrint('_restoreGroup: read failed, creating new: $e');
      return _createNewGroup(
        code: code,
        ownerUid: ownerUid,
        ownerData: ownerData,
        myData: myData,
      );
    }

    // Restore: clear disbanded flag, refresh member display info
    await _db.collection('groups').doc(groupId).update({
      'disbanded': FieldValue.delete(),
      'disbandedAt': FieldValue.delete(),
      'memberNames.$ownerUid': ownerData['displayName'] ?? '',
      'memberAvatars.$ownerUid': ownerData['avatarUrl'] ?? '',
      'memberNames.${u.uid}':
          myData['displayName'] ?? u.displayName ?? '',
      'memberAvatars.${u.uid}': myData['avatarUrl'] ?? u.photoURL ?? '',
    });
    debugPrint('_restoreGroup: group $groupId restored');

    // Add group back to both users' pairIds
    await _db.collection('users').doc(u.uid).update({
      'pairId': groupId,
      'pairIds': FieldValue.arrayUnion([groupId]),
    });
    try {
      await _db.collection('users').doc(ownerUid).update({
        'pairId': groupId,
        'pairIds': FieldValue.arrayUnion([groupId]),
      });
    } catch (e) {
      debugPrint('_restoreGroup: owner update failed: $e');
    }

    // Delete invite code
    try {
      await _db.collection('inviteCodes').doc(code).delete();
    } catch (e) {
      debugPrint('_restoreGroup: code delete failed: $e');
    }

    final members = List<String>.from(groupData['members'] ?? []);
    final memberNames = Map<String, dynamic>.from(
      groupData['memberNames'] ?? {},
    );
    final memberAvatars = Map<String, dynamic>.from(
      groupData['memberAvatars'] ?? {},
    );
    memberNames[ownerUid] = ownerData['displayName'] ?? 'Partner';
    memberAvatars[ownerUid] = ownerData['avatarUrl'] ?? '';
    memberNames[u.uid] = myData['displayName'] ?? u.displayName ?? 'Partner';
    memberAvatars[u.uid] = myData['avatarUrl'] ?? u.photoURL ?? '';

    return {
      'success': true,
      'message': 'Reconnected!',
      'partnerName': ownerData['displayName'] ?? 'Partner',
      'partnerAvatar': ownerData['avatarUrl'] ?? '',
      'pairId': groupId,
      'startDate':
          (groupData['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      'relationshipType': groupData['relationshipType'] as String? ?? 'couple',
      'customRelationshipLabel':
          groupData['customRelationshipLabel'] as String? ?? '',
      'customRelationshipEmoji':
          groupData['customRelationshipEmoji'] as String? ?? '',
      'customRelationshipTypes':
          groupData['customRelationshipTypes'] as List<dynamic>? ?? <dynamic>[],
      'members': members
          .map(
            (uid) => {
              'uid': uid,
              'name': memberNames[uid] ?? '',
              'avatar': memberAvatars[uid] ?? '',
            },
          )
          .toList(),
      'restored': true,
    };
  }

  /// Join an existing group by groupId.
  Future<Map<String, dynamic>> _joinExistingGroup({
    required String groupId,
    required String code,
    required Map<String, dynamic> myData,
    required String ownerUid,
    required Map<String, dynamic> ownerData,
  }) async {
    final u = currentUser!;
    debugPrint('_joinExistingGroup: trying to join group $groupId');

    // Try to read the group doc directly
    Map<String, dynamic>? groupData;
    List<String> members;
    int maxMembers;

    try {
      final groupDoc = await _db.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) {
        debugPrint('_joinExistingGroup: group $groupId not found');
        return {'success': false, 'message': 'Group not found'};
      }
      groupData = groupDoc.data()!;
      members = List<String>.from(groupData['members'] ?? []);
      maxMembers = (groupData['maxMembers'] as int?) ?? 10;
    } catch (e) {
      // Can't read group (not a member yet) — that's expected
      // We know the group exists because the owner has it, so just proceed
      debugPrint(
        '_joinExistingGroup: cant read group (expected), will add self directly',
      );
      members = [ownerUid]; // We know owner is there
      maxMembers = 2;
      groupData = null;
    }

    if (members.contains(u.uid)) {
      return {'success': false, 'message': 'Вы уже в этой группе'};
    }
    if (members.length >= maxMembers) {
      return {
        'success': false,
        'message': 'Группа заполнена (макс $maxMembers)',
      };
    }

    final myName = myData['displayName'] ?? u.displayName ?? '';
    final myAvatar = myData['avatarUrl'] ?? u.photoURL ?? '';

    // Step 1: Add self to group (allowed by new rules — uid will be in new members)
    try {
      await _db.collection('groups').doc(groupId).update({
        'members': FieldValue.arrayUnion([u.uid]),
        'memberNames.${u.uid}': myName,
        'memberAvatars.${u.uid}': myAvatar,
      });
      debugPrint('_joinExistingGroup: added self to group');
    } catch (e) {
      debugPrint('_joinExistingGroup: failed to update group: $e');
      return {
        'success': false,
        'message': 'Не удалось присоединиться к группе',
      };
    }

    // Step 2: Update MY user document
    try {
      await _db.collection('users').doc(u.uid).update({
        'pairId': groupId,
        'pairIds': FieldValue.arrayUnion([groupId]),
      });
      debugPrint('_joinExistingGroup: my user doc updated');
    } catch (e) {
      debugPrint('_joinExistingGroup: user doc update failed: $e');
    }

    // Step 3: Delete code if group is now full
    if (members.length + 1 >= maxMembers) {
      try {
        await _db.collection('inviteCodes').doc(code).delete();
      } catch (e) {
        debugPrint('_joinExistingGroup: code delete failed: $e');
      }
    }

    // Build response from groupData if available, otherwise from owner data
    final memberNames = groupData != null
        ? Map<String, dynamic>.from(groupData['memberNames'] ?? {})
        : <String, dynamic>{ownerUid: ownerData['displayName'] ?? 'Partner'};
    final memberAvatars = groupData != null
        ? Map<String, dynamic>.from(groupData['memberAvatars'] ?? {})
        : <String, dynamic>{ownerUid: ownerData['avatarUrl'] ?? ''};
    memberNames[u.uid] = myName;
    memberAvatars[u.uid] = myAvatar;

    final otherUid = members.isNotEmpty ? members.first : ownerUid;
    return {
      'success': true,
      'message': 'Joined the group!',
      'partnerName': memberNames[otherUid] ?? 'Partner',
      'partnerAvatar': memberAvatars[otherUid] ?? '',
      'pairId': groupId,
      'startDate': groupData != null
          ? ((groupData['startDate'] as Timestamp?)?.toDate() ?? DateTime.now())
          : DateTime.now(),
      'relationshipType': groupData?['relationshipType'] as String? ?? 'couple',
      'customRelationshipLabel':
          groupData?['customRelationshipLabel'] as String? ?? '',
      'customRelationshipEmoji':
          groupData?['customRelationshipEmoji'] as String? ?? '',
      'customRelationshipTypes':
          groupData?['customRelationshipTypes'] as List<dynamic>? ??
          <dynamic>[],
      'members': [...members, u.uid]
          .map(
            (uid) => {
              'uid': uid,
              'name': memberNames[uid] ?? '',
              'avatar': memberAvatars[uid] ?? '',
            },
          )
          .toList(),
    };
  }

  /// Update group maxMembers
  Future<void> updateGroupMaxMembers(String groupId, int maxMembers) async {
    try {
      await _db.collection('groups').doc(groupId).update({
        'maxMembers': maxMembers,
      });
    } catch (e) {
      debugPrint('updateGroupMaxMembers failed: $e');
    }
  }

  /// Update group relationship type with all fields
  Future<void> updateGroupRelationshipType(
    String groupId, {
    required String type,
    required int maxMembers,
    String customLabel = '',
    String customEmoji = '',
  }) async {
    try {
      await _db.collection('groups').doc(groupId).update({
        'relationshipType': type,
        'maxMembers': maxMembers,
        'customRelationshipLabel': customLabel,
        'customRelationshipEmoji': customEmoji,
      });
    } catch (e) {
      debugPrint('updateGroupRelationshipType failed: $e');
    }
  }

  // ── Celebration dates ──────────────────────────────────────────────────────

  /// Сохраняет дату годовщины для пары (общая для группы).
  Future<void> updateAnniversaryDate(String groupId, DateTime? date) async {
    try {
      await _db.collection('groups').doc(groupId).set(
        {'anniversaryDate': date != null ? Timestamp.fromDate(date) : null},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('updateAnniversaryDate failed: $e');
    }
  }

  /// Сохраняет дату первого поцелуя для пары (общая для группы).
  Future<void> updateFirstKissDate(String groupId, DateTime? date) async {
    try {
      await _db.collection('groups').doc(groupId).set(
        {'firstKissDate': date != null ? Timestamp.fromDate(date) : null},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('updateFirstKissDate failed: $e');
    }
  }

  /// Сохраняет дату рождения текущего пользователя.
  /// Записывает в users/{uid}/birthDate И в groups/{groupId}/memberBirthdays.{uid}.
  Future<void> updateMyBirthDate(DateTime? date) async {
    final u = currentUser;
    if (u == null) return;
    try {
      await _db.collection('users').doc(u.uid).set(
        {'birthDate': date != null ? Timestamp.fromDate(date) : null},
        SetOptions(merge: true),
      );
      // Обновляем в каждой группе, чтобы партнёр видел дату рождения.
      final groupIds = <String>[];
      // Пробуем прочитать pairIds из users/{uid}
      try {
        final userDoc = await _db.collection('users').doc(u.uid).get();
        final ids = userDoc.data()?['pairIds'] as List?;
        if (ids != null) groupIds.addAll(ids.whereType<String>());
        final legacy = userDoc.data()?['pairId'] as String?;
        if (legacy != null && legacy.isNotEmpty && !groupIds.contains(legacy)) {
          groupIds.add(legacy);
        }
      } catch (_) {}
      for (final gid in groupIds) {
        await _db.collection('groups').doc(gid).update({
          'memberBirthdays.${u.uid}':
              date != null ? Timestamp.fromDate(date) : FieldValue.delete(),
        });
      }
    } catch (e) {
      debugPrint('updateMyBirthDate failed: $e');
    }
  }

  /// Add a custom relationship type to the group's shared list
  Future<void> addCustomRelationshipType(
    String groupId,
    Map<String, String> entry,
  ) async {
    try {
      await _db.runTransaction((tx) async {
        final ref = _db.collection('groups').doc(groupId);
        final snap = await tx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};
        final list = List<Map<String, dynamic>>.from(
          (data['customRelationshipTypes'] as List<dynamic>? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        if (!list.any((e) => e['id'] == entry['id'])) {
          list.add(Map<String, dynamic>.from(entry));
        }
        tx.set(ref, {'customRelationshipTypes': list}, SetOptions(merge: true));
      });
    } catch (e) {
      debugPrint('addCustomRelationshipType failed: $e');
    }
  }

  /// Update a custom relationship type in the group's shared list
  Future<void> updateCustomRelationshipType(
    String groupId,
    Map<String, String> entry,
  ) async {
    try {
      await _db.runTransaction((tx) async {
        final ref = _db.collection('groups').doc(groupId);
        final snap = await tx.get(ref);
        final data = snap.data();
        if (data == null) return;

        final list = List<Map<String, dynamic>>.from(
          (data['customRelationshipTypes'] as List<dynamic>? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        final idx = list.indexWhere((e) => e['id'] == entry['id']);
        if (idx == -1) return;

        final previous = Map<String, dynamic>.from(list[idx]);
        list[idx] = Map<String, dynamic>.from(entry);

        final updates = <String, dynamic>{'customRelationshipTypes': list};
        final currentLabel = data['customRelationshipLabel'] as String? ?? '';
        final currentEmoji = data['customRelationshipEmoji'] as String? ?? '';
        final prevLabel = previous['label'] as String? ?? '';
        final prevEmoji = previous['emoji'] as String? ?? '';
        if (currentLabel == prevLabel && currentEmoji == prevEmoji) {
          updates['customRelationshipLabel'] = entry['label'] ?? '';
          updates['customRelationshipEmoji'] = entry['emoji'] ?? '';
        }

        tx.update(ref, updates);
      });
    } catch (e) {
      debugPrint('updateCustomRelationshipType failed: $e');
    }
  }

  /// Delete a custom relationship type from the group's shared list
  Future<void> deleteCustomRelationshipType(String groupId, String id) async {
    try {
      await _db.runTransaction((tx) async {
        final ref = _db.collection('groups').doc(groupId);
        final snap = await tx.get(ref);
        final data = snap.data();
        if (data == null) return;

        final list = List<Map<String, dynamic>>.from(
          (data['customRelationshipTypes'] as List<dynamic>? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        final removed = list.where((e) => e['id'] == id).toList();
        list.removeWhere((e) => e['id'] == id);

        final updates = <String, dynamic>{'customRelationshipTypes': list};
        final removedLabel = removed.isNotEmpty
            ? removed.first['label'] as String? ?? ''
            : '';
        final currentType = data['relationshipType'] as String? ?? '';
        final currentLabel = data['customRelationshipLabel'] as String? ?? '';
        if (currentType == 'custom' &&
            removedLabel.isNotEmpty &&
            currentLabel == removedLabel) {
          updates['relationshipType'] = 'couple';
          updates['maxMembers'] = 2;
          updates['customRelationshipLabel'] = '';
          updates['customRelationshipEmoji'] = '';
        }

        tx.update(ref, updates);
      });
    } catch (e) {
      debugPrint('deleteCustomRelationshipType failed: $e');
    }
  }

  /// Load group data by groupId
  Future<Map<String, dynamic>?> loadPairById(String pairId) async {
    final u = currentUser;
    if (u == null || pairId.isEmpty) return null;

    try {
      final doc = await _db
          .collection('groups')
          .doc(pairId)
          .get()
          .timeout(const Duration(seconds: 10));

      if (!doc.exists) {
        // Backward compat: try 'pairs' collection
        final pairDoc = await _db
            .collection('pairs')
            .doc(pairId)
            .get()
            .timeout(const Duration(seconds: 10));
        if (!pairDoc.exists) return null;
        return _parseLegacyPairDoc(pairId, pairDoc.data()!);
      }

      final docData = doc.data()!;
      if (docData['disbanded'] == true) return null;
      return _parseGroupDoc(pairId, docData);
    } catch (e) {
      debugPrint('loadPairById($pairId) failed: $e');
      return null;
    }
  }

  Map<String, dynamic> _parseGroupDoc(
    String groupId,
    Map<String, dynamic> data,
  ) {
    final u = currentUser!;
    final rawMembers = List<String>.from(data['members'] ?? []);
    // Deduplicate in case Firestore data has become inconsistent
    final members = rawMembers.toSet().toList();
    // Кешируем участников — sendMissYou/sendVibe кладут recipientUids в event,
    // чтобы функция пуша не читала group-doc.
    _groupMembersCache[groupId] = members;
    // Миграция: переносим старые Firestore-счётчики «Я скучаю» в RTDB при первом
    // разборе группы после обновления, чтобы у обновившегося не показывало 0/0,
    // пока партнёр на старой версии (которая пишет в group-doc). Только если
    // RTDB ещё пуст — новые тапы не затираем.
    final rawMissYouCounts = data['missYouCounts'];
    if (rawMissYouCounts is Map &&
        rawMissYouCounts.isNotEmpty &&
        !_missYouSeeded.contains(groupId)) {
      _missYouSeeded.add(groupId);
      unawaited(_seedMissYouCountsIfEmpty(groupId, rawMissYouCounts));
    }
    // If duplicates found — silently repair the Firestore document
    if (members.length < rawMembers.length) {
      debugPrint(
        '_parseGroupDoc: duplicates detected in $groupId, repairing...',
      );
      _db
          .collection('groups')
          .doc(groupId)
          .update({'members': members})
          .catchError((e) => debugPrint('auto-repair members failed: $e'));
    }
    final memberNames = Map<String, dynamic>.from(data['memberNames'] ?? {});
    final memberAvatars = Map<String, dynamic>.from(
      data['memberAvatars'] ?? {},
    );

    final otherUids = members.where((m) => m != u.uid).toList();
    final partnerUid = otherUids.isNotEmpty ? otherUids.first : '';

    return {
      'pairId': groupId,
      'partnerName': memberNames[partnerUid] ?? '',
      'partnerAvatar': memberAvatars[partnerUid] ?? '',
      'startDate': (data['startDate'] as Timestamp?)?.toDate(),
      'members': members
          .map(
            (uid) => {
              'uid': uid,
              'name': memberNames[uid] ?? '',
              'avatar': memberAvatars[uid] ?? '',
            },
          )
          .toList(),
      'maxMembers': data['maxMembers'] ?? 2,
      'memberMoods': (data['memberMoods'] as Map<String, dynamic>? ?? {}).map((
        uid,
        moodData,
      ) {
        final moodMap = Map<String, dynamic>.from(moodData as Map);
        final ts = moodMap['updatedAt'];
        if (ts is Timestamp) {
          moodMap['updatedAt'] = ts.toDate();
        }
        return MapEntry(uid, moodMap);
      }),
      'currentStatus': data['currentStatus'] as Map<String, dynamic>?,
      'customStatuses': data['customStatuses'] as List<dynamic>?,
      'relationshipType': data['relationshipType'] as String?,
      'customRelationshipLabel': data['customRelationshipLabel'] as String?,
      'customRelationshipEmoji': data['customRelationshipEmoji'] as String?,
      'customRelationshipTypes':
          data['customRelationshipTypes'] as List<dynamic>?,
      'anniversaryDate':
          (data['anniversaryDate'] as Timestamp?)?.toDate(),
      'firstKissDate':
          (data['firstKissDate'] as Timestamp?)?.toDate(),
      'memberBirthdays': () {
        final raw = data['memberBirthdays'] as Map<String, dynamic>?;
        if (raw == null) return null;
        return raw.map((k, v) => MapEntry(
              k,
              v is Timestamp ? v.toDate() : null,
            ));
      }(),
      'raw': data,
    };
  }

  Map<String, dynamic> _parseLegacyPairDoc(
    String pairId,
    Map<String, dynamic> data,
  ) {
    final u = currentUser!;
    final isUser1 = data['user1'] == u.uid;
    return {
      'pairId': pairId,
      'partnerName': isUser1 ? data['user2Name'] : data['user1Name'],
      'partnerAvatar': isUser1 ? data['user2Avatar'] : data['user1Avatar'],
      'startDate': (data['startDate'] as Timestamp?)?.toDate(),
      'members': [
        {
          'uid': data['user1'],
          'name': data['user1Name'] ?? '',
          'avatar': data['user1Avatar'] ?? '',
        },
        {
          'uid': data['user2'],
          'name': data['user2Name'] ?? '',
          'avatar': data['user2Avatar'] ?? '',
        },
      ],
      'maxMembers': 2,
      'raw': data,
    };
  }

  Future<Map<String, dynamic>?> loadPairData() async {
    final u = currentUser;
    if (u == null) return null;

    try {
      final userDoc = await _db
          .collection('users')
          .doc(u.uid)
          .get()
          .timeout(const Duration(seconds: 10));
      final pairId = userDoc.data()?['pairId'] as String?;
      if (pairId == null || pairId.isEmpty) return null;

      return await loadPairById(pairId);
    } catch (e) {
      debugPrint('loadPairData failed: $e');
      return null;
    }
  }

  /// Diagnostic + cleanup for the "phantom member" bug.
  ///
  /// Symptom: header shows N+1 avatars / "Group of N+1" while Members list
  /// renders only N. Root cause: `members[]` in Firestore contains an extra
  /// UID that belongs to the same person (current user) but from an older
  /// auth session (different sign-in method or recreated account). Since
  /// `Connection.partners` filters by `uid != myUid`, the phantom-self uid
  /// passes the filter and is counted as a partner.
  ///
  /// This method prints every member's uid + email + displayName, then
  /// removes any uid that:
  ///   - has no users/{uid} document (orphan), OR
  ///   - has the same email as the current user but a different uid
  ///     (phantom-self from an earlier session).
  ///
  /// Returns the list of removed uids. Safe to call repeatedly — does nothing
  /// when no phantoms exist.
  Future<List<String>> cleanupPhantomMembersInGroup(
    String groupId, {
    bool force = false,
  }) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return const [];

    // Сначала читаем group doc (1 read) — нужно знать members/maxMembers, чтобы
    // решить, можно ли пропустить дорогой per-user скан по троттлу.
    final Map<String, dynamic> data;
    final List<String> members;
    try {
      final groupDoc = await _db.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return const [];
      data = groupDoc.data()!;
      final rawMembers = List<String>.from(data['members'] ?? []);
      members = rawMembers.toSet().toList();
    } catch (e) {
      debugPrint('cleanupPhantomMembersInGroup($groupId) group read failed: $e');
      return const [];
    }
    if (members.length <= 1) return const [];

    final maxMembers = (data['maxMembers'] as num?)?.toInt() ?? 2;
    final overCapacity = members.length > maxMembers;

    // Throttle: фантомы — редкий баг. Per-user скан (N×user.get) гоняем не чаще
    // раза в сутки. НО при переполнении группы (overCapacity) или явном force
    // лечим немедленно — это и есть видимый баг «Группа из N+1».
    if (!force && !overCapacity) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final key = 'phantom_check_last_$groupId';
        final lastMs = prefs.getInt(key) ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        const oneDayMs = 24 * 60 * 60 * 1000;
        if (now - lastMs < oneDayMs) return const [];
        await prefs.setInt(key, now);
      } catch (_) {
        // SharedPreferences недоступны — продолжаем без throttle.
      }
    }

    try {
      final memberAvatars =
          Map<String, dynamic>.from(data['memberAvatars'] ?? {});

      // Читаем user doc КАЖДОГО участника (включая себя), различая
      // «документа нет» (orphan) и «ошибка чтения» (не трогаем).
      final docExists = <String, bool>{};
      final docData = <String, Map<String, dynamic>>{};
      for (final uid in members) {
        try {
          final d = await _db.collection('users').doc(uid).get();
          docExists[uid] = d.exists;
          if (d.exists) docData[uid] = d.data() ?? const <String, dynamic>{};
        } catch (e) {
          debugPrint('  [skip] $uid — cant read user doc: $e');
          // null/unknown — не считаем orphan, чтобы не удалить при сбое сети.
        }
      }

      // Мой email — из Auth (свежий), иначе из своего user doc.
      String myEmail = (u.email ?? '').toLowerCase();
      if (myEmail.isEmpty) {
        myEmail = (docData[u.uid]?['email'] as String? ?? '').toLowerCase();
      }

      debugPrint(
        'cleanupPhantomMembersInGroup($groupId): myUid=${u.uid}, '
        'myEmail=$myEmail, members=$members, overCapacity=$overCapacity',
      );

      final phantoms = <String>[];

      // 1) Orphans: участник, у которого ТОЧНО нет user doc (get вернул !exists),
      //    и это не я. Старая логика — оставляем.
      for (final uid in members) {
        if (uid == u.uid) continue;
        if (docExists[uid] == false) {
          debugPrint('  [orphan] $uid — no users/$uid doc, will remove');
          phantoms.add(uid);
        }
      }

      // 2) Self-twins: участники с тем же email, что и у меня (включая меня).
      //    Это разные uid одного человека (Google + email/пароль). Из кластера
      //    оставляем ОДНОГО «настоящего» — детерминированно, по следам
      //    активности, НЕ по тому, кто сейчас залогинен. Тогда оригинал не
      //    удалит ни одно устройство, а планшет-фантом при необходимости
      //    выселит сам себя.
      if (myEmail.isNotEmpty) {
        final twins = <String>[];
        for (final uid in members) {
          if (phantoms.contains(uid)) continue; // уже помечен orphan
          final email = uid == u.uid
              ? myEmail
              : (docData[uid]?['email'] as String? ?? '').toLowerCase();
          if (email == myEmail) twins.add(uid);
        }

        if (twins.length >= 2) {
          // Очки «настоящести» — считаются ТОЛЬКО из Firestore-данных, поэтому
          // одинаковы на всех устройствах (детерминизм → нет гонки/двойного
          // удаления). Текущая сессия НЕ получает бонуса.
          int score(String uid) {
            var s = 0;
            final avatarInGroup =
                (memberAvatars[uid] as String? ?? '').isNotEmpty;
            if (avatarInGroup) s += 4;
            final profileAvatar =
                (docData[uid]?['avatarUrl'] as String? ?? '').isNotEmpty;
            if (profileAvatar) s += 2;
            if ((docData[uid]?['pairId'] as String?) == groupId) s += 1;
            return s;
          }

          // Победитель = max score; тай-брейк — меньший uid (стабильно).
          final winner = twins.reduce((a, b) {
            final sa = score(a), sb = score(b);
            if (sa != sb) return sa > sb ? a : b;
            return a.compareTo(b) <= 0 ? a : b;
          });

          for (final uid in twins) {
            if (uid != winner && !phantoms.contains(uid)) {
              debugPrint(
                '  [phantom-self] $uid — same email, lost to winner=$winner '
                '(score ${score(uid)} vs ${score(winner)}), will remove',
              );
              phantoms.add(uid);
            }
          }
          debugPrint(
            '  [self-twins] keeping winner=$winner of $twins',
          );
        }
      }

      if (phantoms.isEmpty) {
        debugPrint(
          'cleanupPhantomMembersInGroup($groupId): no phantoms detected',
        );
        return const [];
      }

      final updates = <String, dynamic>{
        'members': FieldValue.arrayRemove(phantoms),
      };
      for (final p in phantoms) {
        updates['memberNames.$p'] = FieldValue.delete();
        updates['memberAvatars.$p'] = FieldValue.delete();
        updates['memberMoods.$p'] = FieldValue.delete();
      }

      await _db
          .collection('groups')
          .doc(groupId)
          .update(updates)
          .timeout(const Duration(seconds: 10));
      debugPrint(
        'cleanupPhantomMembersInGroup($groupId): removed ${phantoms.length} phantom(s): $phantoms',
      );
      return phantoms;
    } catch (e) {
      debugPrint('cleanupPhantomMembersInGroup($groupId) failed: $e');
      return const [];
    }
  }

  /// Remove a stale groupId from the user's pairIds list in Firestore.
  /// Called when a group turns out to have no partners (orphaned after testing).
  Future<void> removeStaleGroupFromUser(String groupId) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return;
    try {
      await _db
          .collection('users')
          .doc(u.uid)
          .update({
            'pairIds': FieldValue.arrayRemove([groupId]),
          })
          .timeout(const Duration(seconds: 10));
      debugPrint('removeStaleGroupFromUser: removed $groupId from user doc');
    } catch (e) {
      debugPrint('removeStaleGroupFromUser failed: $e');
    }
  }

  /// Listen to group changes in real-time
  StreamSubscription? listenToPair({
    required String pairId,
    required void Function(Map<String, dynamic>? data) onData,
  }) {
    // Shared hub — every listener for this group reuses one underlying
    // Firestore subscription. `includeMetadataChanges` is intentionally OFF:
    // metadata-only updates don't change any field the UI reads, and they
    // would double-charge every consumer downstream.
    return _groupDocStream(pairId).listen((snap) async {
      if (snap.exists) {
        final rawData = snap.data()!;
        if (rawData['disbanded'] == true) {
          debugPrint('listenToPair: group disbanded, treating as deleted');
          onData(null);
          return;
        }
        final parsedData = _parseGroupDoc(pairId, rawData);
        onData(parsedData);
      } else {
        debugPrint('listenToPair: group document deleted or not found');
        try {
          final pairSnap = await _db
              .collection('pairs')
              .doc(pairId)
              .get(const GetOptions(source: Source.server));
          if (pairSnap.exists) {
            onData(_parseLegacyPairDoc(pairId, pairSnap.data()!));
          } else {
            onData(null);
          }
        } catch (_) {
          onData(null);
        }
      }
    }, onError: (e) => debugPrint('listenToPair error: $e'));
  }

  /// Remove me from a group (or delete if ≤2 members)
  Future<void> unpairById(String groupId) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return;

    var groupDoc = await _db.collection('groups').doc(groupId).get();

    if (groupDoc.exists) {
      final data = groupDoc.data()!;
      final members = List<String>.from(data['members'] ?? []);

      if (members.length <= 2) {
        // Soft-delete: mark as disbanded so data can be restored on reconnect
        final batch = _db.batch();
        batch.update(_db.collection('groups').doc(groupId), {
          'disbanded': true,
          'disbandedAt': FieldValue.serverTimestamp(),
        });
        for (final member in members) {
          batch.update(_db.collection('users').doc(member), {
            'pairIds': FieldValue.arrayRemove([groupId]),
          });
        }
        await batch.commit();

        for (final member in members) {
          final memberDoc = await _db.collection('users').doc(member).get();
          final remaining =
              (memberDoc.data()?['pairIds'] as List<dynamic>?) ?? [];
          await _db.collection('users').doc(member).update({
            'pairId': remaining.isNotEmpty ? remaining.last : '',
          });
        }
      } else {
        // Just leave the group
        debugPrint(
          'unpairById: leaving group $groupId (${members.length} members)',
        );

        // Update group document first to remove this member
        await _db.collection('groups').doc(groupId).update({
          'members': FieldValue.arrayRemove([u.uid]),
          'memberNames.${u.uid}': FieldValue.delete(),
          'memberAvatars.${u.uid}': FieldValue.delete(),
          'memberMoods.${u.uid}': FieldValue.delete(),
        });

        debugPrint('unpairById: removed from group, updating user doc');

        // Then update user's pairIds
        await _db.collection('users').doc(u.uid).update({
          'pairIds': FieldValue.arrayRemove([groupId]),
        });

        // Update user's active pairId
        final myDoc = await _db.collection('users').doc(u.uid).get();
        final remaining = (myDoc.data()?['pairIds'] as List<dynamic>?) ?? [];
        await _db.collection('users').doc(u.uid).update({
          'pairId': remaining.isNotEmpty ? remaining.last : '',
        });

        debugPrint('unpairById: successfully left group');
      }
      return;
    }

    // Fallback: legacy pairs collection
    final pairDoc = await _db.collection('pairs').doc(groupId).get();
    if (!pairDoc.exists) return;

    final pData = pairDoc.data()!;
    final partnerId = pData['user1'] == u.uid ? pData['user2'] : pData['user1'];

    final batch = _db.batch();
    batch.delete(_db.collection('pairs').doc(groupId));
    batch.update(_db.collection('users').doc(u.uid), {
      'pairId': '',
      'pairIds': FieldValue.arrayRemove([groupId]),
    });
    if (partnerId != null) {
      batch.update(_db.collection('users').doc(partnerId as String), {
        'pairId': '',
        'pairIds': FieldValue.arrayRemove([groupId]),
      });
    }
    await batch.commit();
  }

  Future<void> unpair() async {
    final u = currentUser;
    if (u == null) return;
    final userDoc = await _db.collection('users').doc(u.uid).get();
    final pairId = userDoc.data()?['pairId'] as String?;
    if (pairId == null || pairId.isEmpty) return;
    await unpairById(pairId);
  }

  // ══════════════════════════════════════════════
  //  REAL-TIME LISTENERS
  // ══════════════════════════════════════════════

  StreamSubscription? listenToUserDoc({
    required void Function(Map<String, dynamic>? data) onData,
  }) {
    final u = currentUser;
    if (u == null) return null;

    // Shared hub for users/{uid} — same dedup reasoning as the group hub.
    return _userDocStream(u.uid).listen((snap) {
      if (snap.exists) {
        onData(snap.data());
      } else {
        onData(null);
      }
    }, onError: (e) => debugPrint('listenToUserDoc error: $e'));
  }

  // ══════════════════════════════════════════════
  //  TOGETHER SESSIONS (совместные занятия)
  //  Приглашение хранится в group-doc.activeSession и доставляется через
  //  УЖЕ работающий group-doc hub-листенер → НОЛЬ новых Firestore-чтений.
  //  Сама синхронизация плеера идёт в RTDB (TogetherSessionService).
  // ══════════════════════════════════════════════

  /// Поток активного приглашения для группы. Реюзает hub-подписку group-doc,
  /// поэтому новых чтений не создаёт.
  Stream<Map<String, dynamic>?> activeSessionStream(String pairId) {
    return _groupDocStream(pairId).map(
      (snap) => snap.exists
          ? (snap.data()?['activeSession'] as Map<String, dynamic>?)
          : null,
    );
  }

  /// Объявить активный совместный сеанс (вызывает хост). Один write —
  /// партнёрский live-листенер ловит его без дополнительного чтения.
  Future<void> setActiveSession({
    required String groupId,
    required String activity,
    required String mediaId,
    required String hostName,
  }) async {
    if (groupId.isEmpty) return;
    try {
      await _db.collection('groups').doc(groupId).set({
        'activeSession': {
          'activity': activity,
          'mediaId': mediaId,
          'hostUid': uid,
          'hostName': hostName,
          'startedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('setActiveSession failed: $e');
    }
  }

  /// Убрать активный сеанс из group-doc.
  Future<void> clearActiveSession(String groupId) async {
    if (groupId.isEmpty) return;
    try {
      await _db.collection('groups').doc(groupId).update({
        'activeSession': FieldValue.delete(),
      });
    } catch (e) {
      debugPrint('clearActiveSession failed: $e');
    }
  }

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

  /// Получить временный Signed URL для gs:// пути.
  /// Результат кэшируется на 55 минут. Если путь — https:// URL, вернёт его как есть.
  Future<String?> getSignedUrl(String gsPath) async {
    if (gsPath.isEmpty) return null;
    // Обратная совместимость: старые записи хранят download URL
    if (gsPath.startsWith('http')) return gsPath;

    final cached = _signedUrlCache[gsPath];
    if (cached != null && cached.isValid) return cached.url;

    try {
      final res = await _functions
          .httpsCallable('getSignedUrl')
          .call<Map<dynamic, dynamic>>({'gsPath': gsPath})
          .timeout(const Duration(seconds: 15));
      final data = Map<String, dynamic>.from(res.data);
      final url = data['url'] as String?;
      final expiresAt = data['expiresAt'] as int?;
      if (url != null && expiresAt != null) {
        _signedUrlCache[gsPath] = _SignedUrlEntry(
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

  // ────────────────────────────────────────────────────────────────────────────

  /// Upload file to Firebase Storage and return download URL
  /// [path] - file path on device
  /// [destination] - storage path (e.g. 'memories/groupId/filename.jpg')
  Future<String?> uploadFile(String path, String destination) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('uploadFile: File does not exist: $path');
        return null;
      }

      final fileSize = await file.length();
      debugPrint(
        'uploadFile: Starting upload of $destination ($fileSize bytes)',
      );
      debugPrint('uploadFile: Storage bucket = ${_storage.bucket}');

      // Determine content type from extension
      final ext = path.split('.').last.toLowerCase();
      String? contentType;
      if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
        contentType = 'image/$ext';
      } else if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) {
        contentType = 'video/$ext';
      } else if (['mp3', 'aac', 'wav', 'ogg', 'm4a', 'flac'].contains(ext)) {
        contentType = 'audio/$ext';
      }

      // Convert raster images to WebP before upload — typically 30-60% smaller
      // than JPEG at equivalent visual quality. Storage path gets .webp extension.
      File fileToUpload = file;
      var uploadDestination = destination;
      if (['jpg', 'jpeg', 'png'].contains(ext)) {
        try {
          final tempDir = await getTemporaryDirectory();
          final targetPath =
              '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_comp.webp';
          final xFile = await FlutterImageCompress.compressAndGetFile(
            path,
            targetPath,
            quality: 87,
            format: CompressFormat.webp,
            autoCorrectionAngle: true,
            keepExif: false,
          );
          if (xFile != null) {
            final webpFile = File(xFile.path);
            final webpSize = await webpFile.length();
            debugPrint(
              'uploadFile: WebP conversion $fileSize → $webpSize bytes',
            );
            if (webpSize < fileSize) {
              fileToUpload = webpFile;
              contentType = 'image/webp';
              uploadDestination = destination.replaceAll(
                RegExp(r'\.(jpg|jpeg|png)$', caseSensitive: false),
                '.webp',
              );
            } else {
              // WebP turned out larger — keep the original
              debugPrint(
                'uploadFile: WebP larger than original, uploading original $ext',
              );
              webpFile.delete().catchError((_) => webpFile);
            }
          }
        } catch (e) {
          debugPrint('uploadFile: WebP conversion failed, uploading original: $e');
        }
      }

      // Compress video before upload — uses device hardware encoder (H.264).
      // HighestQuality keeps original resolution and framerate; typical savings
      // are 60-80% vs camera-recorded files with no perceptible quality loss.
      File? _compressedTempFile;
      if (!kIsWeb && ['mp4', 'mov', 'avi', 'mkv'].contains(ext)) {
        try {
          final info = await VideoCompress.compressVideo(
            path,
            quality: VideoQuality.HighestQuality,
            deleteOrigin: false,
            includeAudio: true,
          );
          if (info?.file != null) {
            _compressedTempFile = info!.file!;
            fileToUpload = _compressedTempFile;
            contentType = 'video/mp4';
            uploadDestination = destination.replaceAll(
              RegExp(r'\.(mov|avi|mkv)$', caseSensitive: false),
              '.mp4',
            );
            debugPrint(
              'uploadFile: Video compressed $fileSize → ${await fileToUpload.length()} bytes',
            );
          }
        } catch (e) {
          debugPrint('uploadFile: Video compression failed, uploading original: $e');
          // cancelCompression only on error — calling it after success on some
          // Android devices leaves the native codec spinning and freezes the UI.
          VideoCompress.cancelCompression();
        }
      }

      final metadata = contentType != null
          ? SettableMetadata(contentType: contentType)
          : null;

      final ref = _storage.ref().child(uploadDestination);
      final uploadTask = ref.putFile(fileToUpload, metadata);

      // Monitor upload progress
      uploadTask.snapshotEvents.listen((event) {
        final progress = event.bytesTransferred / event.totalBytes;
        debugPrint(
          'uploadFile: Progress ${(progress * 100).toStringAsFixed(1)}%',
        );
      });

      final snapshot = await uploadTask;

      // Для групповых путей возвращаем gs:// — доступ только через Signed URL.
      // Для аватарок (avatars/) оставляем download URL: они намеренно доступны
      // любому авторизованному пользователю и не несут private-данных группы.
      const privatePathPrefixes = [
        'memories/', 'groups/', 'music/', 'timer_backgrounds/', 'widget/',
      ];
      final isPrivatePath = privatePathPrefixes.any(uploadDestination.startsWith);

      String resultUrl;
      if (isPrivatePath) {
        resultUrl = 'gs://${snapshot.ref.bucket}/${snapshot.ref.fullPath}';
      } else {
        resultUrl = await snapshot.ref.getDownloadURL();
      }

      debugPrint('uploadFile: Success! result = $resultUrl');
      _compressedTempFile?.delete().catchError((_) {});
      return resultUrl;
    } on FirebaseException catch (e) {
      debugPrint(
        'uploadFile FirebaseException: code=${e.code} message=${e.message}',
      );
      if (e.code == 'object-not-found') {
        debugPrint(
          'uploadFile: Firebase Storage bucket may not be activated. '
          'Go to Firebase Console → Storage → Get Started to enable it.',
        );
      }
      return null;
    } catch (e) {
      debugPrint('uploadFile failed: $e');
      return null;
    }
  }

  /// Удалить файл из Firebase Storage по его download URL.
  Future<void> deleteFileByUrl(String url) async {
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
      debugPrint('deleteFileByUrl: deleted $url');
    } catch (e) {
      debugPrint('deleteFileByUrl failed: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // MEMORIES (CRUD)
  // ══════════════════════════════════════════════════════════════════════════════

  Future<Memory?> addMemory({
    required String groupId,
    required MemoryType type,
    String? imageUrl,
    List<String>? imageUrls,
    String? videoUrl,
    String? title,
    String? caption,
    String? locationName,
    double? latitude,
    double? longitude,
    String? musicTitle,
    String? musicArtist,
    String? musicUrl,
    String? musicCoverUrl,
    String? bookAuthor,
    String? bookCoverUrl,
    String? bookYear,
    String? bookPublisher,
    String? bookInfoUrl,
    bool isAdult = false,
    DateTime? customDate,
  }) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return null;

    await RateLimiterService().checkAndRecordMemory();

    try {
      final name = _cachedDisplayName ?? u.displayName ?? '';
      final avatar = (_cachedAvatarUrl?.isNotEmpty == true ? _cachedAvatarUrl! : u.photoURL) ?? '';

      final ref = _db
          .collection('groups')
          .doc(groupId)
          .collection('memories')
          .doc();
      // Если пользователь выбрал «дату воспоминания» в прошлом —
      // записываем её как createdAt, чтобы пин оказался на ленте
      // в нужной временной точке. По умолчанию — текущий момент.
      final createdAt = customDate ?? DateTime.now();
      final memory = Memory(
        id: ref.id,
        groupId: groupId,
        authorUid: u.uid,
        authorName: name,
        authorAvatar: avatar,
        type: type,
        createdAt: createdAt,
        imageUrl: imageUrl,
        imageUrls: imageUrls,
        videoUrl: videoUrl,
        title: title,
        caption: caption,
        locationName: locationName,
        latitude: latitude,
        longitude: longitude,
        musicTitle: musicTitle,
        musicArtist: musicArtist,
        musicUrl: musicUrl,
        musicCoverUrl: musicCoverUrl,
        bookAuthor: bookAuthor,
        bookCoverUrl: bookCoverUrl,
        bookYear: bookYear,
        bookPublisher: bookPublisher,
        bookInfoUrl: bookInfoUrl,
        isAdult: isAdult,
      );

      await ref.set(memory.toFirestore());
      unawaited(
        _db.collection('groups').doc(groupId).update({
          'memoriesCount': FieldValue.increment(1),
        }).catchError((_) {}),
      );
      unawaited(
        AnalyticsService.instance.logMemoryAdded(type: type.name),
      );
      return memory;
    } catch (e) {
      debugPrint('addMemory failed: $e');
      return null;
    }
  }

  Future<void> updateMemory({
    required String groupId,
    required String memoryId,
    String? title,
    String? caption,
    String? locationName,
    double? latitude,
    double? longitude,
    String? musicTitle,
    String? musicArtist,
    String? bookAuthor,
    String? imageUrl,
    bool? isPinned,
    bool? isAdult,
    // Если задано — перезаписываем createdAt (используется при редактировании
    // даты воспоминания). null = оставить createdAt как есть.
    DateTime? customDate,
  }) async {
    try {
      final updates = <String, dynamic>{'editedAt': Timestamp.now()};
      if (title != null) updates['title'] = title;
      if (caption != null) updates['caption'] = caption;
      if (locationName != null) updates['locationName'] = locationName;
      if (latitude != null) updates['latitude'] = latitude;
      if (longitude != null) updates['longitude'] = longitude;
      if (musicTitle != null) updates['musicTitle'] = musicTitle;
      if (musicArtist != null) updates['musicArtist'] = musicArtist;
      if (bookAuthor != null) updates['bookAuthor'] = bookAuthor;
      if (imageUrl != null) updates['imageUrl'] = imageUrl;
      if (isPinned != null) updates['isPinned'] = isPinned;
      if (isAdult != null) updates['isAdult'] = isAdult;
      if (customDate != null) {
        updates['createdAt'] = Timestamp.fromDate(customDate);
      }

      // Offline Conflict Resolution: Keep history of caption edits using arrayUnion
      // This prevents data loss if both partners edit the caption offline simultaneously.
      if (caption != null && uid != null) {
        updates['captionHistory'] = FieldValue.arrayUnion([
          {'caption': caption, 'uid': uid, 'timestamp': Timestamp.now()},
        ]);
      }

      await _db
          .collection('groups')
          .doc(groupId)
          .collection('memories')
          .doc(memoryId)
          .update(updates);
    } catch (e) {
      debugPrint('updateMemory failed: $e');
    }
  }

  Future<void> deleteMemory({
    required String groupId,
    required String memoryId,
    String? imageUrl,
    String? videoUrl,
    String? musicUrl,
    String? musicCoverUrl,
  }) async {
    try {
      // Delete associated files from Firebase Storage
      final urls = [imageUrl, videoUrl, musicUrl, musicCoverUrl];
      for (final url in urls) {
        if (url != null && url.contains('firebasestorage')) {
          try {
            await _storage.refFromURL(url).delete();
            debugPrint('Deleted storage file: $url');
          } catch (e) {
            debugPrint('Failed to delete storage file: $e');
          }
        }
      }

      // Delete Firestore document
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('memories')
          .doc(memoryId)
          .delete();
      unawaited(
        _db.collection('groups').doc(groupId).update({
          'memoriesCount': FieldValue.increment(-1),
        }).catchError((_) {}),
      );
    } catch (e) {
      debugPrint('deleteMemory failed: $e');
    }
  }

  Future<void> togglePinMemory({
    required String groupId,
    required String memoryId,
    required bool isPinned,
  }) async {
    await updateMemory(
      groupId: groupId,
      memoryId: memoryId,
      isPinned: isPinned,
    );
  }

  Future<({List<Memory> memories, DocumentSnapshot? lastDoc})> loadMemories({
    required String groupId,
    int limit = 50,
    DocumentSnapshot? startAfter,
    bool cacheFirst = false,
  }) async {
    try {
      var query = _db
          .collection('groups')
          .doc(groupId)
          .collection('memories')
          .orderBy('createdAt', descending: true)
          .limit(limit) as Query<Map<String, dynamic>>;
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }
      // cacheFirst: для начального открытия экрана сначала читаем из локального
      // persistent-кэша (его уже прогрел live-слушатель listenToMemories на home),
      // что даёт 0 серверных чтений и мгновенную отрисовку. Если кэш пуст
      // (холодный старт до запуска слушателя), падаем на сервер.
      QuerySnapshot<Map<String, dynamic>> snap;
      if (cacheFirst) {
        try {
          snap = await query
              .get(const GetOptions(source: Source.cache))
              .timeout(const Duration(seconds: 5));
          if (snap.docs.isEmpty) {
            snap = await query.get().timeout(const Duration(seconds: 10));
          }
        } catch (_) {
          snap = await query.get().timeout(const Duration(seconds: 10));
        }
      } else {
        snap = await query.get().timeout(const Duration(seconds: 10));
      }
      final docs = snap.docs;
      return (
        memories: docs.map((d) => Memory.fromFirestore(d.id, d.data())).toList(),
        lastDoc: docs.isNotEmpty ? docs.last : null,
      );
    } catch (e) {
      debugPrint('loadMemories failed: $e');
      return (memories: <Memory>[], lastDoc: null);
    }
  }

  StreamSubscription? listenToMemories({
    required String groupId,
    required void Function(List<Memory> memories) onData,
    int limit = 20,
  }) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('memories')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .listen((snap) {
          final memories = snap.docs
              .map((d) => Memory.fromFirestore(d.id, d.data()))
              .toList();
          onData(memories);
        }, onError: (e) => debugPrint('listenToMemories error: $e'));
  }

  // ══════════════════════════════════════════════
  //  COMMENTS
  // ══════════════════════════════════════════════

  CollectionReference _commentsRef(String groupId, String memoryId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('memories')
        .doc(memoryId)
        .collection('comments');
  }

  Future<void> addComment({
    required String groupId,
    required String memoryId,
    required String text,
  }) async {
    final user = currentUser;
    if (user == null) return;

    await RateLimiterService().checkAndRecordComment();

    final comment = MemoryComment(
      id: '',
      authorUid: user.uid,
      authorName: user.displayName ?? 'User',
      authorAvatar: user.photoURL ?? '',
      text: text,
      createdAt: DateTime.now(),
    );
    try {
      await _commentsRef(groupId, memoryId).add(comment.toFirestore());
    } catch (e) {
      debugPrint('addComment failed: $e');
    }
  }

  Future<void> deleteComment({
    required String groupId,
    required String memoryId,
    required String commentId,
  }) async {
    try {
      await _commentsRef(groupId, memoryId).doc(commentId).delete();
    } catch (e) {
      debugPrint('deleteComment failed: $e');
    }
  }

  Stream<List<MemoryComment>> commentsStream({
    required String groupId,
    required String memoryId,
  }) {
    return _commentsRef(groupId, memoryId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (d) => MemoryComment.fromFirestore(
                  d.id,
                  d.data() as Map<String, dynamic>,
                ),
              )
              .toList(),
        );
  }

  // ══════════════════════════════════════════════
  //  MOOD
  //  Firestore: groups/{groupId} → memberMoods.{uid}: {imagePath, label, updatedAt}
  // ══════════════════════════════════════════════

  /// Save the current user's mood to the group document
  Future<void> setMood({
    required String groupId,
    required String imagePath,
    required String label,
  }) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return;
    try {
      await _db.collection('groups').doc(groupId).update({
        'memberMoods.${u.uid}': {
          'imagePath': imagePath,
          'label': label,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      });
      unawaited(AnalyticsService.instance.logMoodSet(label: label));
    } catch (e) {
      debugPrint('setMood failed: $e');
    }
  }

  /// Clear the current user's mood
  Future<void> clearMood({required String groupId}) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return;
    try {
      await _db.collection('groups').doc(groupId).update({
        'memberMoods.${u.uid}': FieldValue.delete(),
      });
    } catch (e) {
      debugPrint('clearMood failed: $e');
    }
  }

  // ══════════════════════════════════════════════
  //  RELATIONSHIP STATUS
  //  Firestore: groups/{groupId} → currentStatus: {...}, customStatuses: [...]
  // ══════════════════════════════════════════════

  /// Set the group's current relationship status
  Future<void> setGroupStatus(String groupId, dynamic status) async {
    if (groupId.isEmpty) return;
    try {
      final statusData = status is Map<String, dynamic>
          ? status
          : (status as dynamic).toJson();
      await _db.collection('groups').doc(groupId).update({
        'currentStatus': statusData,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('setGroupStatus failed: $e');
    }
  }

  /// Clear the group's current relationship status
  Future<void> clearGroupStatus(String groupId) async {
    if (groupId.isEmpty) return;
    try {
      await _db.collection('groups').doc(groupId).update({
        'currentStatus': FieldValue.delete(),
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('clearGroupStatus failed: $e');
    }
  }

  /// Add a custom status to the group
  Future<void> addCustomStatus(String groupId, dynamic status) async {
    if (groupId.isEmpty) return;
    try {
      final statusData = status is Map<String, dynamic>
          ? status
          : (status as dynamic).toJson();
      await _db.runTransaction((tx) async {
        final ref = _db.collection('groups').doc(groupId);
        final snap = await tx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};
        final customStatuses = List<Map<String, dynamic>>.from(
          (data['customStatuses'] as List<dynamic>? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        if (!customStatuses.any((s) => s['id'] == statusData['id'])) {
          customStatuses.add(Map<String, dynamic>.from(statusData));
        }
        tx.set(ref, {
          'customStatuses': customStatuses,
        }, SetOptions(merge: true));
      });
    } catch (e) {
      debugPrint('addCustomStatus failed: $e');
    }
  }

  /// Update a custom status in the group
  Future<void> updateCustomStatus(String groupId, dynamic status) async {
    if (groupId.isEmpty) return;
    try {
      final statusData = status is Map<String, dynamic>
          ? status
          : (status as dynamic).toJson();
      await _db.runTransaction((tx) async {
        final ref = _db.collection('groups').doc(groupId);
        final snap = await tx.get(ref);
        final data = snap.data();
        if (data == null) return;

        final customStatuses = List<Map<String, dynamic>>.from(
          (data['customStatuses'] as List<dynamic>? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        final index = customStatuses.indexWhere(
          (s) => s['id'] == statusData['id'],
        );
        if (index == -1) return;

        customStatuses[index] = Map<String, dynamic>.from(statusData);
        final updates = <String, dynamic>{'customStatuses': customStatuses};
        final currentStatus = data['currentStatus'] as Map<String, dynamic>?;
        if (currentStatus != null && currentStatus['id'] == statusData['id']) {
          updates['currentStatus'] = statusData;
        }
        tx.update(ref, updates);
      });
    } catch (e) {
      debugPrint('updateCustomStatus failed: $e');
    }
  }

  /// Delete a custom status from the group
  Future<void> deleteCustomStatus(String groupId, String statusId) async {
    if (groupId.isEmpty) return;
    try {
      await _db.runTransaction((tx) async {
        final ref = _db.collection('groups').doc(groupId);
        final snap = await tx.get(ref);
        final data = snap.data();
        if (data == null) return;

        final customStatuses = List<Map<String, dynamic>>.from(
          (data['customStatuses'] as List<dynamic>? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        customStatuses.removeWhere((s) => s['id'] == statusId);

        final updates = <String, dynamic>{'customStatuses': customStatuses};
        final currentStatus = data['currentStatus'] as Map<String, dynamic>?;
        if (currentStatus != null && currentStatus['id'] == statusId) {
          updates['currentStatus'] = FieldValue.delete();
        }
        tx.update(ref, updates);
      });
    } catch (e) {
      debugPrint('deleteCustomStatus failed: $e');
    }
  }

  // ══════════════════════════════════════════════
  //  TIMERS (synced across group)
  // ══════════════════════════════════════════════

  /// Save full timers list to group document
  Future<void> saveTimers({
    required String groupId,
    required List<Map<String, dynamic>> timers,
  }) async {
    try {
      debugPrint(
        'FirebaseService: сохраняю ${timers.length} таймеров в группу $groupId',
      );
      await _db.collection('groups').doc(groupId).update({'timers': timers});
      debugPrint('FirebaseService: таймеры успешно сохранены');
    } catch (e) {
      debugPrint('FirebaseService: ошибка сохранения таймеров - $e');
      // Если документ группы не существует или нет поля timers - пробуем set
      try {
        debugPrint('FirebaseService: пробую создать поле timers через set...');
        await _db.collection('groups').doc(groupId).set({
          'timers': timers,
        }, SetOptions(merge: true));
        debugPrint('FirebaseService: таймеры сохранены через set');
      } catch (e2) {
        debugPrint(
          'FirebaseService: критическая ошибка сохранения таймеров - $e2',
        );
      }
    }
  }

  Future<void> upsertGroupTimer({
    required String groupId,
    required Map<String, dynamic> timer,
  }) async {
    try {
      await _db.runTransaction((tx) async {
        final ref = _db.collection('groups').doc(groupId);
        final snap = await tx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};
        final timers = List<Map<String, dynamic>>.from(
          (data['timers'] as List<dynamic>? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );

        timers.removeWhere((t) => t['id'] == timer['id']);
        final isDefault = timer['isDefault'] as bool? ?? false;
        if (isDefault) {
          for (final existing in timers) {
            existing['isDefault'] = false;
          }
        }

        timers.add(Map<String, dynamic>.from(timer));
        if (timers.isNotEmpty && !timers.any((t) => t['isDefault'] == true)) {
          timers.first['isDefault'] = true;
        }

        tx.set(ref, {'timers': timers}, SetOptions(merge: true));
      });
    } catch (e) {
      debugPrint('upsertGroupTimer failed: $e');
    }
  }

  Future<void> deleteGroupTimer({
    required String groupId,
    required String timerId,
  }) async {
    try {
      await _db.runTransaction((tx) async {
        final ref = _db.collection('groups').doc(groupId);
        final snap = await tx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};
        final timers = List<Map<String, dynamic>>.from(
          (data['timers'] as List<dynamic>? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );

        timers.removeWhere((t) => t['id'] == timerId);
        if (timers.isNotEmpty && !timers.any((t) => t['isDefault'] == true)) {
          timers.first['isDefault'] = true;
        }

        tx.set(ref, {'timers': timers}, SetOptions(merge: true));
      });
    } catch (e) {
      debugPrint('deleteGroupTimer failed: $e');
    }
  }

  Future<void> setDefaultGroupTimer({
    required String groupId,
    required String timerId,
  }) async {
    try {
      await _db.runTransaction((tx) async {
        final ref = _db.collection('groups').doc(groupId);
        final snap = await tx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};
        final timers = List<Map<String, dynamic>>.from(
          (data['timers'] as List<dynamic>? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );

        for (final timer in timers) {
          timer['isDefault'] = timer['id'] == timerId;
        }
        if (timers.isNotEmpty && !timers.any((t) => t['isDefault'] == true)) {
          timers.first['isDefault'] = true;
        }

        tx.set(ref, {'timers': timers}, SetOptions(merge: true));
      });
    } catch (e) {
      debugPrint('setDefaultGroupTimer failed: $e');
    }
  }

  // ── Solo timers (Firestore backup for reinstall recovery) ──

  /// Сохраняет соло-таймеры в документ пользователя для восстановления после переустановки.
  Future<void> saveSoloTimers(List<Map<String, dynamic>> timers) async {
    final id = uid;
    if (id == null) return;
    try {
      await _db.collection('users').doc(id).set(
        {'soloTimers': timers},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('saveSoloTimers failed: $e');
    }
  }

  /// Загружает соло-таймеры из Firestore (вызывается после переустановки).
  Future<List<Map<String, dynamic>>?> loadSoloTimers() async {
    final id = uid;
    if (id == null) return null;
    try {
      final snap = await _db
          .collection('users')
          .doc(id)
          .get(const GetOptions(source: Source.server));
      final raw = snap.data()?['soloTimers'];
      if (raw is! List || (raw).isEmpty) return null;
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('loadSoloTimers failed: $e');
      return null;
    }
  }

  /// Listen to timers changes in real-time.
  /// Skips the callback when only other group fields changed (e.g. memberMoods)
  /// to avoid redundant _mergeRemoteTimers calls on every partner mood update.
  StreamSubscription? listenToTimers({
    required String groupId,
    required void Function(List<TimerItem> timers) onData,
  }) {
    // null = ещё не доставили ни одного снимка. Важно отличать «не доставляли»
    // от «доставили пустой список»: у только что созданной группы поля timers
    // нет, поэтому hash первого снимка == '' и при старте с prevHash='' колбэк
    // проглатывался — _mergeRemoteTimers([]) не вызывался, _hasReceivedRemoteSync
    // оставался false и отложенный системный таймер не создавался.
    String? prevHash;
    return _groupDocStream(groupId).listen((snap) {
      if (!snap.exists) return;
      final data = snap.data()!;
      final timersList = data['timers'] as List<dynamic>?;
      final hash = timersList?.toString() ?? '';
      if (hash == prevHash) return;
      prevHash = hash;
      if (timersList != null) {
        final timers = timersList
            .map((e) => TimerItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        onData(timers);
      } else {
        onData([]);
      }
    }, onError: (e) => debugPrint('listenToTimers error: $e'));
  }

  // ══════════════════════════════════════════════
  //  MOOD CALENDAR
  //  Firestore (v2): groups/{groupId}/moodCalendar/{uid}/months/{YYYY-MM}
  //    { entries: { <entryId>: {...entry...}, ... }, updatedAt }
  //  Все записи месяца лежат в ОДНОМ документе (map по entryId) — чтение
  //  истории = N документов-месяцев вместо сотен/тысяч отдельных записей.
  //  Legacy (v1): .../moodCalendar/{uid}/entries/{entryId} — по одной записи
  //  на документ. Остаётся для чтения у не-мигрированных пользователей
  //  (партнёр на старой версии) и как источник для миграции своих данных.
  // ══════════════════════════════════════════════

  String _moodMonthKey(DateTime ts) =>
      '${ts.year.toString().padLeft(4, '0')}-'
      '${ts.month.toString().padLeft(2, '0')}';

  CollectionReference<Map<String, dynamic>> _moodMonthsCol(
          String groupId, String uid) =>
      _db
          .collection('groups')
          .doc(groupId)
          .collection('moodCalendar')
          .doc(uid)
          .collection('months');

  CollectionReference<Map<String, dynamic>> _moodEntriesCol(
          String groupId, String uid) =>
      _db
          .collection('groups')
          .doc(groupId)
          .collection('moodCalendar')
          .doc(uid)
          .collection('entries');

  List<Map<String, dynamic>> _entriesFromMonthDoc(
      Map<String, dynamic>? data) {
    final map = data?['entries'];
    if (map is! Map) return const [];
    return map.values
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Add a mood entry for the current user (пишет в month-документ).
  Future<void> addMoodEntry({
    required String groupId,
    required Map<String, dynamic> entry,
  }) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return;
    final id = entry['id'] as String?;
    final ts = (entry['timestamp'] as Timestamp?)?.toDate();
    if (id == null || ts == null) return;
    try {
      // merge:true сохраняет остальные записи месяца — дописываем только свою.
      await _moodMonthsCol(groupId, u.uid).doc(_moodMonthKey(ts)).set({
        'entries': {id: entry},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('addMoodEntry failed: $e');
    }
  }

  /// Delete a mood entry. [timestamp] нужен для адресации month-документа;
  /// если не передан — выводим месяц из id (`<uid>_<millis>`).
  Future<void> deleteMoodEntry({
    required String groupId,
    required String entryId,
    DateTime? timestamp,
  }) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return;
    var ts = timestamp;
    if (ts == null) {
      final ms = int.tryParse(entryId.split('_').last);
      if (ms != null) ts = DateTime.fromMillisecondsSinceEpoch(ms);
    }
    if (ts == null) {
      debugPrint('deleteMoodEntry: cannot resolve month for $entryId');
      return;
    }
    try {
      // entryId = `<uid>_<millis>` — без точек/слэшей, безопасно как field-path.
      await _moodMonthsCol(groupId, u.uid).doc(_moodMonthKey(ts)).update({
        'entries.$entryId': FieldValue.delete(),
      });
    } catch (e) {
      debugPrint('deleteMoodEntry failed: $e');
    }
  }

  /// Live-слушатель ОДНОГО месяца (обычно текущего) — 1 документ.
  /// Срабатывает на каждое изменение настроений месяца → real-time для партнёра.
  StreamSubscription? listenMoodMonth({
    required String groupId,
    required String uid,
    required String monthKey,
    required void Function(List<Map<String, dynamic>> entries) onData,
  }) {
    return _moodMonthsCol(groupId, uid).doc(monthKey).snapshots().listen(
      (snap) => onData(_entriesFromMonthDoc(snap.data())),
      onError: (e) => debugPrint('listenMoodMonth error: $e'),
    );
  }

  /// Разовая загрузка истории: последние [months] month-документов.
  /// cacheFirst → сначала из локального кэша persistence (0 серверных чтений);
  /// при пустом кэше падаем на сервер.
  Future<List<Map<String, dynamic>>> loadMoodMonths({
    required String groupId,
    required String uid,
    int months = 14,
    bool cacheFirst = true,
  }) async {
    // Диапазон по documentId вместо orderBy(__name__, desc)+limit: убывающая
    // сортировка по имени документа требует составного индекса, а инеравенство
    // по __name__ индексируется автоматически. Ключи YYYY-MM лексикографически
    // совпадают с хронологией, поэтому `>= cutoff` = последние [months] месяцев.
    final now = DateTime.now();
    final cutoff = _moodMonthKey(DateTime(now.year, now.month - (months - 1), 1));
    final q = _moodMonthsCol(groupId, uid)
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: cutoff);
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      if (cacheFirst) {
        snap = await q.get(const GetOptions(source: Source.cache));
        if (snap.docs.isEmpty) snap = await q.get();
      } else {
        snap = await q.get();
      }
    } catch (_) {
      try {
        snap = await q.get();
      } catch (e) {
        debugPrint('loadMoodMonths failed: $e');
        return const [];
      }
    }
    final out = <Map<String, dynamic>>[];
    for (final d in snap.docs) {
      out.addAll(_entriesFromMonthDoc(d.data()));
    }
    return out;
  }

  /// Разовая загрузка LEGACY-записей в окне [since] (cache-first). Нужна как
  /// fallback для партнёра, который ещё не мигрировал (его записи в v1).
  Future<List<Map<String, dynamic>>> loadLegacyMoodEntries({
    required String groupId,
    required String uid,
    required DateTime since,
    bool cacheFirst = true,
  }) async {
    final q = _moodEntriesCol(groupId, uid)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(since));
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      if (cacheFirst) {
        snap = await q.get(const GetOptions(source: Source.cache));
        if (snap.docs.isEmpty) snap = await q.get();
      } else {
        snap = await q.get();
      }
    } catch (_) {
      try {
        snap = await q.get();
      } catch (e) {
        debugPrint('loadLegacyMoodEntries failed: $e');
        return const [];
      }
    }
    return snap.docs.map((d) => d.data()).toList();
  }

  /// Однократная миграция СВОИХ legacy-записей (v1 → month-документы).
  /// Идемпотентна (entryId как ключ map). Окно [since] ограничивает объём
  /// разового чтения. Возвращает true при успехе (в т.ч. если мигрировать
  /// нечего). Партнёрские данные мигрировать нельзя (правила: пишем только своё).
  Future<bool> migrateMoodToMonthly({
    required String groupId,
    required String uid,
    required DateTime since,
  }) async {
    try {
      final snap = await _moodEntriesCol(groupId, uid)
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .get();
      if (snap.docs.isEmpty) return true;
      final byMonth = <String, Map<String, dynamic>>{};
      for (final d in snap.docs) {
        final data = d.data();
        final ts = (data['timestamp'] as Timestamp?)?.toDate();
        if (ts == null) continue;
        (byMonth[_moodMonthKey(ts)] ??= {})[d.id] = data;
      }
      final batch = _db.batch();
      byMonth.forEach((monthKey, entries) {
        batch.set(_moodMonthsCol(groupId, uid).doc(monthKey), {
          'entries': entries,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('migrateMoodToMonthly failed: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════
  //  DAILY REFLECTION
  // ══════════════════════════════════════════════

  /// Сохранить / обновить ответ пользователя на вопрос дня.
  /// Путь: groups/{groupId}/reflections/{YYYY-MM-DD}
  Future<void> saveReflectionAnswer({
    required String groupId,
    required String question,
    required String answer,
    required String authorName,
  }) async {
    final uid = this.uid;
    if (uid == null) return;
    final dayKey = _reflectionDayKey(DateTime.now());
    try {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('reflections')
          .doc(dayKey)
          .set({
            'question': question,
            'updatedAt': FieldValue.serverTimestamp(),
            'answers.$uid': {
              'text': answer,
              'authorName': authorName,
              'createdAt': FieldValue.serverTimestamp(),
            },
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('saveReflectionAnswer failed: $e');
    }
  }

  /// Слушать рефлексию текущего дня в реальном времени.
  StreamSubscription listenToTodayReflection({
    required String groupId,
    required void Function(Map<String, dynamic>? data) onData,
  }) {
    final dayKey = _reflectionDayKey(DateTime.now());
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('reflections')
        .doc(dayKey)
        .snapshots()
        .listen(
          (snap) => onData(snap.exists ? snap.data() : null),
          onError: (e) => debugPrint('listenToReflection error: $e'),
        );
  }

  static String _reflectionDayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ══════════════════════════════════════════════
  //  I MISS YOU
  // ══════════════════════════════════════════════

  /// Отправить «Я скучаю» — записывает в Firestore.
  /// Cloud Function слушает этот документ и отправляет push-уведомление.
  /// Триггер push-уведомления о новом сообщении чата. Сам чат живёт в RTDB —
  /// здесь пишется только эфемерный документ-событие, который Cloud Function
  /// (onChatMessageEvent) читает, рассылает FCM и тут же удаляет. История
  /// чата в Firestore не хранится → ноль чтений при просмотре.
  Future<void> sendChatPush({
    required String groupId,
    required String senderName,
    required String text,
  }) async {
    final myUid = uid;
    if (myUid == null || groupId.isEmpty) return;
    try {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('chatEvents')
          .add({
            'senderUid': myUid,
            'senderName': senderName,
            'text': text.length > 120 ? '${text.substring(0, 120)}…' : text,
            'timestamp': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('sendChatPush failed: $e');
    }
  }

  Future<void> sendMissYou({
    required String groupId,
    required String senderName,
  }) async {
    final myUid = uid;
    if (myUid == null || groupId.isEmpty) return;
    await RateLimiterService().checkVibe();
    try {
      // 1. Инкремент per-user счётчика в RTDB (атомарно, серверный increment).
      // Раньше это был set в Firestore group-doc — а его живьём слушают оба
      // партнёра (listenToPair + listenToMissYouCount), поэтому каждый тап
      // стоил чтение на ОБОИХ устройствах. RTDB-счётчик читается даром и не
      // дёргает Firestore-листенеры. total считается как сумма counts.
      await _missYouCountsRef(groupId).child(myUid).set(ServerValue.increment(1));

      // 2. Добавить запись в subcollection для push-триггера.
      // recipientUids кладём из кеша, чтобы функция не читала group-doc.
      final recipients = _cachedRecipients(groupId, myUid);
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('missYouEvents')
          .add({
            'senderUid': myUid,
            'senderName': senderName,
            if (recipients.isNotEmpty) 'recipientUids': recipients,
            'timestamp': FieldValue.serverTimestamp(),
          });
      unawaited(RateLimiterService().recordVibe());
      unawaited(AnalyticsService.instance.logMissYouSent());
    } catch (e) {
      debugPrint('sendMissYou failed: $e');
    }
  }

  /// Отправить вайб-импульс (думаю о тебе, хочу обнять и др.).
  /// Пишет в ту же subcollection missYouEvents с полем vibeType,
  /// чтобы Cloud Function могла обработать новые типы без изменений схемы.
  Future<void> sendVibe({
    required String groupId,
    required String senderName,
    required String vibeType,
    String? customText,
  }) async {
    final myUid = uid;
    if (myUid == null || groupId.isEmpty) return;
    await RateLimiterService().checkVibe();
    try {
      final recipients = _cachedRecipients(groupId, myUid);
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('missYouEvents')
          .add({
            'senderUid': myUid,
            'senderName': senderName,
            'vibeType': vibeType,
            if (customText != null && customText.isNotEmpty)
              'customText': customText,
            if (recipients.isNotEmpty) 'recipientUids': recipients,
            'timestamp': FieldValue.serverTimestamp(),
          });
      unawaited(RateLimiterService().recordVibe());
      unawaited(AnalyticsService.instance.logVibeSent(vibeType: vibeType));
    } catch (e) {
      debugPrint('sendVibe failed: $e');
    }
  }

  /// Разбирает RTDB-узел counts (Map uid → число) в `Map<String,int>`.
  Map<String, int> _parseMissYouCounts(Object? value) {
    final out = <String, int>{};
    if (value is Map) {
      value.forEach((k, v) => out[k.toString()] = (v as num?)?.toInt() ?? 0);
    }
    return out;
  }

  /// Слушать общий счётчик «Я скучаю» (сумма per-user) в реальном времени.
  /// Источник — RTDB, поэтому изменения не стоят Firestore-чтений.
  StreamSubscription listenToMissYouCount({
    required String groupId,
    required void Function(int count) onData,
  }) {
    int? prev;
    return _missYouCountsRef(groupId).onValue.listen((event) {
      final counts = _parseMissYouCounts(event.snapshot.value);
      final total = counts.values.fold<int>(0, (s, v) => s + v);
      if (total == prev) return;
      prev = total;
      onData(total);
    }, onError: (e) => debugPrint('listenToMissYouCount error: $e'));
  }

  /// Сбросить свои нажатия «Я скучаю» до 0 (только свой узел в RTDB —
  /// чтения чужих счётчиков не требуется).
  Future<void> resetMyMissYouCount({required String groupId}) async {
    final myUid = uid;
    if (myUid == null || groupId.isEmpty) return;
    try {
      await _missYouCountsRef(groupId).child(myUid).set(0);
    } catch (e) {
      debugPrint('resetMyMissYouCount failed: $e');
    }
  }

  /// Слушать per-user счётчики «Я скучаю» (Map uid → count) из RTDB.
  StreamSubscription listenToMissYouCounts({
    required String groupId,
    required void Function(Map<String, int> counts) onData,
  }) {
    String prevHash = '';
    return _missYouCountsRef(groupId).onValue.listen((event) {
      final counts = _parseMissYouCounts(event.snapshot.value);
      final hash = counts.toString();
      if (hash == prevHash) return;
      prevHash = hash;
      onData(counts);
    }, onError: (e) => debugPrint('listenToMissYouCounts error: $e'));
  }

  /// Разовый снимок общего счётчика «Я скучаю» (для фонового апдейта виджета,
  /// где живой listener не нужен). RTDB-чтение — не Firestore.
  Future<int> getMissYouTotal(String groupId) async {
    if (groupId.isEmpty) return 0;
    try {
      final snap = await _missYouCountsRef(groupId).get();
      final counts = _parseMissYouCounts(snap.value);
      return counts.values.fold<int>(0, (s, v) => s + v);
    } catch (e) {
      debugPrint('getMissYouTotal failed: $e');
      return 0;
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
  // badge почти неизменен (Sponsor/Helper) — кешируем разовый get, чтобы не
  // держать Firestore-листенер на чужом user-doc ради одного поля.
  final Map<String, String?> _badgeCache = {};

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
        await ref
            .onDisconnect()
            .set({'online': false, 'lastSeen': ServerValue.timestamp});
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
    _presenceConnSub ??=
        _rtdb.ref('.info/connected').onValue.listen((event) async {
      if (event.snapshot.value != true) return;
      final u = currentUser;
      if (u == null || _lastOnlineStatus != true) return;
      final ref = _presenceRef(u.uid);
      try {
        await ref
            .onDisconnect()
            .set({'online': false, 'lastSeen': ServerValue.timestamp});
        await ref.set({'online': true, 'lastSeen': ServerValue.timestamp});
      } catch (_) {}
    });
  }

  /// Снимает watcher соединения (при выходе из аккаунта).
  void _disposePresenceWatcher() {
    _presenceConnSub?.cancel();
    _presenceConnSub = null;
  }

  /// Стрим присутствия пользователя по uid.
  /// Возвращает Map с полями isOnline (bool), lastSeen (DateTime?), badge.
  /// online/lastSeen — из RTDB (ноль Firestore-чтений); badge — разовый
  /// кешируемый Firestore-get.
  Stream<Map<String, dynamic>> streamUserPresence(String uid) {
    return _presenceRef(uid).onValue.asyncMap((event) async {
      final v = event.snapshot.value;
      bool isOnline = false;
      DateTime? lastSeen;
      if (v is Map) {
        isOnline = v['online'] == true;
        final ts = v['lastSeen'];
        if (ts is int) lastSeen = DateTime.fromMillisecondsSinceEpoch(ts);
      }
      final badge = await _badgeFor(uid);
      return {'isOnline': isOnline, 'lastSeen': lastSeen, 'badge': badge};
    });
  }

  /// Бейдж пользователя (Sponsor/Helper) — кешируемый разовый Firestore-get.
  Future<String?> _badgeFor(String uid) async {
    if (_badgeCache.containsKey(uid)) return _badgeCache[uid];
    try {
      final doc = await _db.collection('users').doc(uid).get();
      final badge = doc.data()?['badge'] as String?;
      _badgeCache[uid] = badge;
      return badge;
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════════════
  //  COLLABORATIVE DRAWING CANVAS
  //  Firestore structure:
  //    groups/{groupId}/canvas/main/strokes/{strokeId}  – completed strokes
  //    groups/{groupId}/canvas/main/live/{userId}        – in-progress stroke
  // ══════════════════════════════════════════════

  CollectionReference _strokesRef(String groupId, [String canvasId = 'main']) =>
      _db
          .collection('groups')
          .doc(groupId)
          .collection('canvas')
          .doc(canvasId)
          .collection('strokes');

  DocumentReference<Map<String, dynamic>> _canvasMainRef(
    String groupId, [
    String canvasId = 'main',
  ]) =>
      _db.collection('groups').doc(groupId).collection('canvas').doc(canvasId);

  CollectionReference _liveRef(String groupId, [String canvasId = 'main']) =>
      _db
          .collection('groups')
          .doc(groupId)
          .collection('canvas')
          .doc(canvasId)
          .collection('live');

  /// Stream of all completed strokes ordered by [orderIndex].
  Stream<List<_DrawStrokeRaw>> listenToDrawingStrokes({
    required String groupId,
    String canvasId = 'main',
  }) {
    return _strokesRef(groupId, canvasId)
        .orderBy('orderIndex')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (d) => _DrawStrokeRaw(
                  id: d.id,
                  data: Map<String, dynamic>.from(d.data() as Map),
                ),
              )
              .toList(),
        );
  }

  /// Persist a completed stroke and return its new Firestore document ID.
  Future<String> addDrawingStroke({
    required String groupId,
    required Map<String, dynamic> strokeData,
    String canvasId = 'main',
  }) async {
    try {
      final ref = await _strokesRef(groupId, canvasId).add(strokeData);
      return ref.id;
    } catch (e) {
      debugPrint('addDrawingStroke failed: $e');
      return '';
    }
  }

  /// Update specific fields of an existing stroke (used for image repositioning).
  Future<void> updateDrawingStroke({
    required String groupId,
    required String strokeId,
    required Map<String, dynamic> updates,
    String canvasId = 'main',
  }) async {
    try {
      await _strokesRef(groupId, canvasId).doc(strokeId).update(updates);
    } catch (e) {
      debugPrint('updateDrawingStroke failed: $e');
    }
  }

  /// Delete a single stroke by ID (used for undo).
  Future<void> deleteDrawingStroke({
    required String groupId,
    required String strokeId,
    String canvasId = 'main',
  }) async {
    try {
      await _strokesRef(groupId, canvasId).doc(strokeId).delete();
    } catch (e) {
      debugPrint('deleteDrawingStroke failed: $e');
    }
  }

  /// Write the current in-progress stroke of [userId] so partners can see it live.
  Future<void> updateLiveDrawingStroke({
    required String groupId,
    required String userId,
    required Map<String, dynamic> liveData,
    String canvasId = 'main',
  }) async {
    try {
      await _liveRef(groupId, canvasId).doc(userId).set(liveData);
    } catch (e) {
      debugPrint('updateLiveDrawingStroke failed: $e');
    }
  }

  /// Remove the live stroke document when the user lifts their finger.
  Future<void> clearLiveDrawingStroke({
    required String groupId,
    required String userId,
    String canvasId = 'main',
  }) async {
    try {
      await _liveRef(groupId, canvasId).doc(userId).delete();
    } catch (e) {
      debugPrint('clearLiveDrawingStroke failed: $e');
    }
  }

  /// Stream of all partners' live strokes (excludes [myUserId]).
  Stream<Map<String, Map<String, dynamic>>> listenToLiveDrawingStrokes({
    required String groupId,
    required String myUserId,
    String canvasId = 'main',
  }) {
    return _liveRef(groupId, canvasId).snapshots().map((snap) {
      final result = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        if (doc.id != myUserId) {
          result[doc.id] = Map<String, dynamic>.from(doc.data() as Map);
        }
      }
      return result;
    });
  }

  /// Delete all strokes and live cursors for a canvas and publish a clear event.
  Future<void> clearDrawingCanvas({
    required String groupId,
    int? clearVersion,
    int? bgColorValue,
    String canvasId = 'main',
  }) async {
    final version = clearVersion ?? DateTime.now().millisecondsSinceEpoch;
    try {
      final strokesSnap = await _strokesRef(groupId, canvasId).get();
      final liveSnap = await _liveRef(groupId, canvasId).get();
      final batch = _db.batch();
      for (final doc in strokesSnap.docs) {
        batch.delete(doc.reference);
      }
      for (final doc in liveSnap.docs) {
        batch.delete(doc.reference);
      }
      final data = <String, dynamic>{'clearVersion': version};
      if (bgColorValue != null) {
        data['bgColor'] = bgColorValue;
      }
      batch.set(
        _canvasMainRef(groupId, canvasId),
        data,
        SetOptions(merge: true),
      );
      await batch.commit();
    } catch (e) {
      debugPrint('clearDrawingCanvas failed: $e');
    }
  }

  /// Persist the canvas background colour so both users see the same fill.
  /// Stored as `bgColor` on the `groups/{groupId}/canvas/main` meta-document.
  Future<void> setCanvasBgColor({
    required String groupId,
    required int colorValue,
    String canvasId = 'main',
  }) async {
    try {
      await _canvasMainRef(
        groupId,
        canvasId,
      ).set({'bgColor': colorValue}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('setCanvasBgColor failed: $e');
    }
  }

  /// Combined stream of canvas meta fields (bgColor, clearVersion, rotation).
  /// Use this instead of subscribing three times to the same document — each
  /// snapshot listener is metered separately by Firestore, so a single
  /// subscription cuts canvas/main reads to ~1/3 of the previous cost.
  Stream<RemoteCanvasMeta> listenToCanvasMeta({
    required String groupId,
    String canvasId = 'main',
  }) {
    return _canvasMainRef(groupId, canvasId).snapshots().map((snap) {
      final data = snap.data();
      return RemoteCanvasMeta(
        bgColor: (data?['bgColor'] as num?)?.toInt(),
        clearVersion: (data?['clearVersion'] as num?)?.toInt(),
        rotationMilliRadians: (data?['canvasRotation'] as num?)?.toInt(),
      );
    });
  }

  /// Persist the canvas rotation so both users see the same orientation.
  /// Stored as `canvasRotation` (angle in milli-radians, int) on the canvas/main doc.
  Future<void> setCanvasRotation({
    required String groupId,
    required int rotationQuarterTurns, // actually milli-radians
    String canvasId = 'main',
  }) async {
    try {
      await _canvasMainRef(
        groupId,
        canvasId,
      ).set({'canvasRotation': rotationQuarterTurns}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('setCanvasRotation failed: $e');
    }
  }

  /// Upload a drawing image to Firebase Storage and return the download URL.
  Future<String?> uploadDrawingImage({
    required String groupId,
    required String localPath,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return uploadFile(localPath, 'groups/$groupId/canvas/img_$ts.jpg');
  }

  // ── Canvas Catalogue ─────────────────────────────────────────────────────
  // Firestore: groups/{groupId}/canvasCatalogue/{canvasId}

  /// Create or update a canvas meta entry in the shared catalogue.
  Future<void> upsertCanvasMeta({
    required String groupId,
    required String canvasId,
    required String name,
    required int createdAt,
    required int updatedAt,
    String? createdBy,
  }) async {
    try {
      final data = <String, dynamic>{
        'id': canvasId,
        'name': name,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
      if (createdBy != null) data['createdBy'] = createdBy;
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('canvasCatalogue')
          .doc(canvasId)
          .set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('upsertCanvasMeta failed: $e');
    }
  }

  /// Rename a canvas in the shared catalogue.
  Future<void> renameCanvasMeta({
    required String groupId,
    required String canvasId,
    required String newName,
  }) async {
    try {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('canvasCatalogue')
          .doc(canvasId)
          .update({
            'name': newName,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          });
    } catch (e) {
      debugPrint('renameCanvasMeta failed: $e');
    }
  }

  /// Delete a canvas meta entry from the shared catalogue.
  Future<void> deleteCanvasMeta({
    required String groupId,
    required String canvasId,
  }) async {
    try {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('canvasCatalogue')
          .doc(canvasId)
          .delete();
    } catch (e) {
      debugPrint('deleteCanvasMeta failed: $e');
    }
  }

  /// Stream of all canvas meta entries for a group.
  Stream<List<Map<String, dynamic>>> listenToCanvasCatalogue({
    required String groupId,
  }) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('canvasCatalogue')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => Map<String, dynamic>.from(d.data()))
              .toList(),
        );
  }

  /// Record / remove the current user's presence on a specific canvas.
  Future<void> setCanvasPresence({
    required String groupId,
    required String canvasId,
    required String userId,
    required bool present,
  }) async {
    try {
      final ref = _db
          .collection('groups')
          .doc(groupId)
          .collection('canvas')
          .doc(canvasId)
          .collection('presence')
          .doc(userId);
      if (present) {
        await ref.set({
          'userId': userId,
          'joinedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await ref.delete();
      }
    } catch (e) {
      debugPrint('setCanvasPresence failed: $e');
    }
  }

  // ══════════════════════════════════════════════
  //  MASCOTS
  // ══════════════════════════════════════════════

  CollectionReference<Map<String, dynamic>> _mascotsRef(String groupId) =>
      _db.collection('groups').doc(groupId).collection('mascots');

  /// Upload raw PNG bytes to Storage and return the download URL.
  Future<String?> uploadMascotImage({
    required String groupId,
    required List<int> pngBytes,
  }) async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = _storage.ref().child(
        'groups/$groupId/mascots/mascot_$ts.png',
      );
      final metadata = SettableMetadata(contentType: 'image/png');
      final task = ref.putData(Uint8List.fromList(pngBytes), metadata);
      final snapshot = await task;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint('uploadMascotImage failed: $e');
      return null;
    }
  }

  /// Save a new mascot document (or overwrite existing id).
  Future<void> saveMascot({
    required String groupId,
    required Mascot mascot,
  }) async {
    try {
      await _mascotsRef(
        groupId,
      ).doc(mascot.id).set(mascot.toFirestore(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('saveMascot failed: $e');
    }
  }

  /// Save multiple mascots in one batch (used for seeding defaults).
  Future<void> saveMascotsBatch({
    required String groupId,
    required List<Mascot> mascots,
  }) async {
    try {
      final batch = _db.batch();
      for (final m in mascots) {
        batch.set(
          _mascotsRef(groupId).doc(m.id),
          m.toFirestore(),
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    } catch (e) {
      debugPrint('saveMascotsBatch failed: $e');
    }
  }

  /// Delete a mascot and its Storage image (if remote).
  Future<void> deleteMascot({
    required String groupId,
    required String mascotId,
    String? imageUrl,
  }) async {
    try {
      await _mascotsRef(groupId).doc(mascotId).delete();
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          await _storage.refFromURL(imageUrl).delete();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('deleteMascot failed: $e');
    }
  }

  /// Rename a mascot.
  Future<void> renameMascot({
    required String groupId,
    required String mascotId,
    required String newName,
  }) async {
    try {
      await _mascotsRef(groupId).doc(mascotId).update({'name': newName});
    } catch (e) {
      debugPrint('renameMascot failed: $e');
    }
  }

  /// Update record streak for a mascot.
  Future<void> updateMascotRecord({
    required String groupId,
    required String mascotId,
    required int recordStreak,
  }) async {
    try {
      await _mascotsRef(
        groupId,
      ).doc(mascotId).update({'recordStreak': recordStreak});
    } catch (e) {
      debugPrint('updateMascotRecord failed: $e');
    }
  }

  /// Set the active mascot for the group (null = no active mascot).
  Future<void> setActiveMascot({
    required String groupId,
    required String? mascotId,
  }) async {
    try {
      await _db.collection('groups').doc(groupId).set({
        'activeMascotId': mascotId,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('setActiveMascot failed: $e');
    }
  }

  /// Update the floating mascot's position and scale.
  Future<void> updateMascotPosition({
    required String groupId,
    required double x,
    required double y,
    required double scale,
  }) async {
    try {
      await _db.collection('groups').doc(groupId).set({
        'mascotPositionX': x,
        'mascotPositionY': y,
        'mascotScale': scale,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('updateMascotPosition failed: $e');
    }
  }

  /// Record that someone from this group opened the app today.
  /// Updates the group's streak counter.
  Future<void> recordGroupActivity(String groupId) async {
    if (groupId.isEmpty) return;
    try {
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Read from local cache only — the group doc is already being listened to
      // via _listenToPair, so Firestore SDK always has fresh data in cache.
      // Using serverAndCache here triggers a network round-trip on every call
      // and causes a cascade: the streak write updates the group doc →
      // _listenToPair fires → _handlePairChanged → recordDailyActivity again.
      Map<String, dynamic> data;
      try {
        final doc = await _db
            .collection('groups')
            .doc(groupId)
            .get(const GetOptions(source: Source.cache));
        data = doc.data() ?? {};
      } catch (_) {
        // Cache miss (e.g. first launch before listener receives data) — skip.
        return;
      }
      final lastDate = data['streakLastOpenedDate'] as String?;
      final currentStreak = (data['streakDays'] as num?)?.toInt() ?? 0;

      if (lastDate == today) return; // already recorded today

      int newStreak;
      if (lastDate != null) {
        final last = DateTime.tryParse(lastDate);
        final diff = last != null ? now.difference(last).inDays : 999;
        newStreak = diff == 1 ? currentStreak + 1 : 1;
      } else {
        newStreak = 1;
      }

      // Also check if we should update mascot record streak.
      final activeMascotId = data['activeMascotId'] as String?;
      final updates = <String, dynamic>{
        'streakDays': newStreak,
        'streakLastOpenedDate': today,
      };

      await _db
          .collection('groups')
          .doc(groupId)
          .set(updates, SetOptions(merge: true));

      // Update record streak for active mascot if needed.
      if (activeMascotId != null) {
        final mascotDoc = await _mascotsRef(groupId).doc(activeMascotId).get();
        if (mascotDoc.exists) {
          final record =
              (mascotDoc.data()?['recordStreak'] as num?)?.toInt() ?? 0;
          if (newStreak > record) {
            await _mascotsRef(
              groupId,
            ).doc(activeMascotId).update({'recordStreak': newStreak});
          }
        }
      }
    } catch (e) {
      debugPrint('recordGroupActivity failed: $e');
    }
  }

  /// Real-time stream of group mascot state (active id, position, scale, streak).
  Stream<GroupMascotState> listenToGroupMascotState({required String groupId}) {
    String? prevSig;
    return _groupDocStream(groupId)
        .map(
          (snap) => snap.exists
              ? GroupMascotState.fromMap(snap.data()!)
              : const GroupMascotState(),
        )
        .where((state) {
          // De-dupe noisy group-doc updates that don't change mascot fields
          // (mood, status, timers, missYouCounts, etc.). Without this filter
          // the mascot widget rebuilds on every unrelated group-doc change.
          final sig =
              '${state.activeMascotId}|${state.positionX}|${state.positionY}|'
              '${state.scale}|${state.streakDays}|${state.streakLastOpenedDate}';
          if (sig == prevSig) return false;
          prevSig = sig;
          return true;
        });
  }

  /// Real-time stream of mascots in the group gallery.
  Stream<List<Mascot>> listenToMascots({required String groupId}) {
    return _mascotsRef(groupId).snapshots().map(
      (snap) =>
          snap.docs
              .map((d) => Mascot.fromFirestore(d.data()))
              .where((m) => m.id.isNotEmpty)
              .toList()
            ..sort((a, b) {
              // defaults first, then by creation date
              if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
              return a.createdAt.compareTo(b.createdAt);
            }),
    );
  }

  /// Count of mascots in the group.
  Future<int> getMascotCount(String groupId) async {
    try {
      final snap = await _mascotsRef(groupId).count().get();
      return snap.count ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Read denormalized memories count from group doc, falling back to count query
  /// for groups that predate the counter field. The result is written back so
  /// subsequent calls are a single doc read instead of a full index scan.
  /// Pass [groupData] to avoid an extra group doc read when the caller already has it.
  Future<int> getGroupMemoriesCount(String groupId,
      {Map<String, dynamic>? groupData}) async {
    try {
      if (groupData != null) {
        final c = groupData['memoriesCount'];
        if (c != null) return (c as num).toInt();
      } else {
        final groupDoc = await _db.collection('groups').doc(groupId).get();
        if (groupDoc.exists) {
          final c = groupDoc.data()?['memoriesCount'];
          if (c != null) return (c as num).toInt();
        }
      }
      final snap = await _db
          .collection('groups').doc(groupId)
          .collection('memories').count().get();
      final count = snap.count ?? 0;
      unawaited(
        _db.collection('groups').doc(groupId)
            .update({'memoriesCount': count}).catchError((_) {}),
      );
      return count;
    } catch (e) {
      return 0;
    }
  }

  /// Read denormalized drawings count from group doc, with the same fallback.
  /// Pass [groupData] to avoid an extra group doc read when the caller already has it.
  Future<int> getGroupDrawingsCount(String groupId,
      {Map<String, dynamic>? groupData}) async {
    try {
      if (groupData != null) {
        final c = groupData['drawingsCount'];
        if (c != null) return (c as num).toInt();
      } else {
        final groupDoc = await _db.collection('groups').doc(groupId).get();
        if (groupDoc.exists) {
          final c = groupDoc.data()?['drawingsCount'];
          if (c != null) return (c as num).toInt();
        }
      }
      final snap = await _db
          .collection('groups').doc(groupId)
          .collection('canvases').count().get();
      final count = snap.count ?? 0;
      unawaited(
        _db.collection('groups').doc(groupId)
            .update({'drawingsCount': count}).catchError((_) {}),
      );
      return count;
    } catch (e) {
      return 0;
    }
  }

  /// Atomically increment/decrement the denormalized drawings counter.
  Future<void> incrementDrawingsCount(String groupId, int delta) async {
    try {
      await _db.collection('groups').doc(groupId).update({
        'drawingsCount': FieldValue.increment(delta),
      });
    } catch (e) {
      debugPrint('incrementDrawingsCount failed: $e');
    }
  }

  // ══════════════════════════════════════════════
  //  HELPERS
  // ══════════════════════════════════════════════

  static String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}

class _LocalNotificationContent {
  final String title;
  final String body;

  const _LocalNotificationContent({required this.title, required this.body});
}

/// Internal transfer object used by [listenToDrawingStrokes].
class _DrawStrokeRaw {
  final String id;
  final Map<String, dynamic> data;
  const _DrawStrokeRaw({required this.id, required this.data});
}

/// Snapshot of the shared canvas/main meta document — merged so a single
/// Firestore listener can drive bgColor / clearVersion / rotation updates.
/// Named `RemoteCanvasMeta` to avoid collision with the local catalogue
/// entry in models/canvas_meta.dart.
class RemoteCanvasMeta {
  final int? bgColor;
  final int? clearVersion;
  final int? rotationMilliRadians;
  const RemoteCanvasMeta({this.bgColor, this.clearVersion, this.rotationMilliRadians});
}

/// Ref-counted multiplexer around a single Firestore document snapshot listener.
///
/// Each independent `.snapshots()` subscription on the same DocumentReference
/// is billed separately by Firestore. The hub lets multiple consumers share
/// ONE underlying subscription: the first listener opens it, the last cancel
/// closes it, and new listeners immediately receive the most recent snapshot
/// so they don't have to wait for the next server event.
///
/// Re-establishing a `.snapshots()` listener costs a fresh server read (the
/// initial document load is billed). Screen navigation and `StreamBuilder`
/// rebuilds briefly drop the listener count to zero, so an immediate teardown
/// would bill a new read the instant the next consumer subscribes. To avoid
/// that, the underlying subscription is kept warm for [_idleGrace] after the
/// last listener leaves: rapid re-subscription reuses the live listener and the
/// replayed [_latest] snapshot at zero extra read cost. The document changes
/// rarely, so the idle warm window is effectively free.
class _DocSnapshotHub {
  _DocSnapshotHub(this._ref);

  static const Duration _idleGrace = Duration(seconds: 90);

  final DocumentReference<Map<String, dynamic>> _ref;
  final StreamController<DocumentSnapshot<Map<String, dynamic>>> _controller =
      StreamController.broadcast();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  DocumentSnapshot<Map<String, dynamic>>? _latest;
  Timer? _idleTimer;

  bool get _isActive => _sub != null;

  void _start() {
    // A new consumer arrived — cancel any pending idle teardown so we keep
    // reusing the warm subscription instead of paying for a fresh read.
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_isActive) return;
    _sub = _ref.snapshots().listen(
      (snap) {
        _latest = snap;
        if (!_controller.isClosed) _controller.add(snap);
      },
      onError: (Object e, StackTrace st) {
        if (!_controller.isClosed) _controller.addError(e, st);
      },
    );
  }

  void _stopIfIdle() {
    if (_controller.hasListener) return;
    // Defer the actual teardown: if a consumer re-subscribes within the grace
    // window (navigation transition, StreamBuilder rebuild), _start() cancels
    // this timer and the live subscription is reused — no new read.
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleGrace, () {
      _idleTimer = null;
      if (_controller.hasListener) return;
      _sub?.cancel();
      _sub = null;
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> get stream {
    return Stream.multi((controller) {
      _start();
      // Replay the latest snapshot so consumers that subscribe mid-stream
      // (e.g. opening profile_screen while a partner has been online for a
      // while) see the current state without waiting for the next change.
      final cached = _latest;
      if (cached != null) controller.add(cached);
      final sub = _controller.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = () async {
        await sub.cancel();
        _stopIfIdle();
      };
    });
  }
}

class _SignedUrlEntry {
  final String url;
  final DateTime expiresAt;
  _SignedUrlEntry(this.url, this.expiresAt);
  // Считаем валидным пока до истечения больше 5 минут
  bool get isValid => expiresAt.difference(DateTime.now()).inMinutes > 5;
}
