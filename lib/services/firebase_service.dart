import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../models/memory.dart';
import '../models/comment.dart';
import '../models/timer_item.dart';
import 'locale_service.dart';
import 'nickname_service.dart';

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

  // ══════════════════════════════════════════════
  //  AUTH
  // ══════════════════════════════════════════════

  User? get currentUser => _auth.currentUser;
  bool get isLoggedIn => _auth.currentUser != null;
  String? get uid => _auth.currentUser?.uid;

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
              'avatarUrl': user.photoURL ?? '',
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

  /// Сохраняет настройку уведомлений в Firestore, чтобы Cloud Functions
  /// могли проверять её перед отправкой push-уведомлений.
  Future<void> updateNotifPrefs({
    bool? missYou,
    bool? newMemory,
    bool? mood,
  }) async {
    final u = currentUser;
    if (u == null) return;
    final updates = <String, dynamic>{};
    if (missYou != null) updates['notifMissYou'] = missYou;
    if (newMemory != null) updates['notifNewMemory'] = newMemory;
    if (mood != null) updates['notifMood'] = mood;
    if (updates.isEmpty) return;
    try {
      await _db
          .collection('users')
          .doc(u.uid)
          .set(updates, SetOptions(merge: true));
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

  static Future<bool> _shouldShowNotification(RemoteMessage message) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final type = message.data['type'] ?? '';
      if (type == 'miss_you' && !(prefs.getBool(_kNotifMissYou) ?? true)) {
        debugPrint('FCM foreground: miss_you notification suppressed by user prefs');
        return false;
      }
      if (type == 'new_memory' && !(prefs.getBool(_kNotifNewMemory) ?? true)) {
        debugPrint('FCM foreground: new_memory notification suppressed by user prefs');
        return false;
      }
      if (type == 'mood' && !(prefs.getBool(_kNotifMood) ?? true)) {
        debugPrint('FCM foreground: mood notification suppressed by user prefs');
        return false;
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

    if (type == 'miss_you') {
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

      return _LocalNotificationContent(
        title: strings.missYouNotifTitle(senderName),
        body: body.isNotEmpty ? body : strings.missYouNotifBody,
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
      await _db.collection('users').doc(u.uid).set({
        // Храним актуальный токен в одном поле (для обратной совместимости)
        'fcmToken': token,
        // И в массиве — для поддержки нескольких устройств
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));
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
        androidPackageName: 'com.example.love_app',
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
      final data = {
        'displayName': displayName,
        'email': email,
        'gender': gender,
        'avatarUrl': avatarUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      };

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
    } catch (e) {
      debugPrint('saveUserProfile failed: $e');
    }
  }

  /// Updates the user's avatar URL in all groups they belong to.
  /// This ensures that partner devices receive the new avatar via the group listener.
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

      for (final groupId in pairIds) {
        await _db
            .collection('groups')
            .doc(groupId)
            .update({'memberAvatars.${u.uid}': avatarUrl})
            .timeout(const Duration(seconds: 10))
            .catchError(
              (e) => debugPrint('updateAvatarInGroups[$groupId] failed: $e'),
            );
      }
    } catch (e) {
      debugPrint('updateAvatarInGroups failed: $e');
    }
  }

  Future<Map<String, dynamic>?> loadUserProfile() async {
    final u = currentUser;
    if (u == null) return null;
    try {
      final doc = await _db
          .collection('users')
          .doc(u.uid)
          .get()
          .timeout(const Duration(seconds: 10));
      return doc.data();
    } catch (e) {
      debugPrint('loadUserProfile failed: $e');
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
          .set({'ownerUid': u.uid, 'createdAt': FieldValue.serverTimestamp()})
          .timeout(const Duration(seconds: 10));

      return code;
    } catch (e) {
      debugPrint('generateNewInviteCode failed: $e');
      return '';
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
              return _joinExistingGroup(
                groupId: ownerPairId,
                code: code,
                myData: myData,
                ownerUid: ownerUid,
                ownerData: ownerData,
              );
            }
          }
        } catch (e) {
          debugPrint('acceptInviteCode: reading owner group failed: $e');
          // Can't read group (not a member) — just create a new one
        }
      }

      // Also check owner's pairIds list for any group we can join
      final ownerPairIds = ownerData['pairIds'] as List<dynamic>?;
      if (ownerPairIds != null && ownerPairIds.isNotEmpty) {
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
        ownerUid: ownerData['displayName'] ?? 'Partner',
        u.uid: myData['displayName'] ?? u.displayName ?? 'Partner',
      },
      'memberAvatars': {
        ownerUid: ownerData['avatarUrl'] ?? '',
        u.uid: myData['avatarUrl'] ?? u.photoURL ?? '',
      },
      'maxMembers': 2,
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
      maxMembers = 10;
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

    final myName = myData['displayName'] ?? u.displayName ?? 'Partner';
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

  /// Add a custom relationship type to the group's shared list
  Future<void> addCustomRelationshipType(
    String groupId,
    Map<String, String> entry,
  ) async {
    try {
      await _db.collection('groups').doc(groupId).update({
        'customRelationshipTypes': FieldValue.arrayUnion([entry]),
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
      final doc = await _db.collection('groups').doc(groupId).get();
      final data = doc.data();
      if (data == null) return;

      final list = List<Map<String, dynamic>>.from(
        (data['customRelationshipTypes'] as List<dynamic>? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );

      final idx = list.indexWhere((e) => e['id'] == entry['id']);
      if (idx != -1) {
        list[idx] = entry;
        await _db.collection('groups').doc(groupId).update({
          'customRelationshipTypes': list,
        });
      }
    } catch (e) {
      debugPrint('updateCustomRelationshipType failed: $e');
    }
  }

  /// Delete a custom relationship type from the group's shared list
  Future<void> deleteCustomRelationshipType(String groupId, String id) async {
    try {
      final doc = await _db.collection('groups').doc(groupId).get();
      final data = doc.data();
      if (data == null) return;

      final list = List<Map<String, dynamic>>.from(
        (data['customRelationshipTypes'] as List<dynamic>? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );

      list.removeWhere((e) => e['id'] == id);
      await _db.collection('groups').doc(groupId).update({
        'customRelationshipTypes': list,
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

      return _parseGroupDoc(pairId, doc.data()!);
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

  /// Listen to group changes in real-time
  StreamSubscription? listenToPair({
    required String pairId,
    required void Function(Map<String, dynamic>? data) onData,
  }) {
    return _db
        .collection('groups')
        .doc(pairId)
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
          // Skip if data is only from cache and not yet confirmed by server
          if (snap.metadata.hasPendingWrites) {
            debugPrint('listenToPair: skipping snapshot with pending writes');
            return;
          }

          if (snap.exists) {
            final parsedData = _parseGroupDoc(pairId, snap.data()!);
            debugPrint(
              'listenToPair: updated group data, members=${parsedData['members']?.length}',
            );
            onData(parsedData);
          } else {
            debugPrint('listenToPair: group document deleted or not found');
            // Immediately notify that the group is gone
            onData(null);
            // Also check legacy pairs collection as a fallback
            _db
                .collection('pairs')
                .doc(pairId)
                .get(const GetOptions(source: Source.server))
                .then((pairSnap) {
                  if (pairSnap.exists) {
                    onData(_parseLegacyPairDoc(pairId, pairSnap.data()!));
                  }
                })
                 .catchError((_) {
                  // ignore errors from legacy fallback — onData(null) already called
                });
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
        // Delete the whole group
        final batch = _db.batch();
        batch.delete(_db.collection('groups').doc(groupId));
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

    return _db
        .collection('users')
        .doc(u.uid)
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
          // Skip if data is only from local cache and not yet confirmed by server
          if (snap.metadata.isFromCache) return;
          if (snap.exists) {
            onData(snap.data());
          } else {
            onData(null);
          }
        }, onError: (e) => debugPrint('listenToUserDoc error: $e'));
  }

  // ══════════════════════════════════════════════
  //  MEMORIES — shared timeline for each group
  //  Firestore: groups/{groupId}/memories/{memoryId}
  // ══════════════════════════════════════════════

  // ══════════════════════════════════════════════════════════════════════════════
  // FILE UPLOAD (Storage)
  // ══════════════════════════════════════════════════════════════════════════════

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

      final ref = _storage.ref().child(destination);

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

      final metadata = contentType != null
          ? SettableMetadata(contentType: contentType)
          : null;

      File fileToUpload = file;
      if (['jpg', 'jpeg', 'png'].contains(ext)) {
        try {
          final tempDir = await getTemporaryDirectory();
          final targetPath =
              '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_comp.$ext';
          final xFile = await FlutterImageCompress.compressAndGetFile(
            path,
            targetPath,
            quality: 70,
          );
          if (xFile != null) {
            fileToUpload = File(xFile.path);
            debugPrint(
              'uploadFile: Compressed image from ${await file.length()} to ${await fileToUpload.length()}',
            );
          }
        } catch (e) {
          debugPrint('uploadFile: Compression failed: $e');
        }
      }

      final uploadTask = ref.putFile(fileToUpload, metadata);

      // Monitor upload progress
      uploadTask.snapshotEvents.listen((event) {
        final progress = event.bytesTransferred / event.totalBytes;
        debugPrint(
          'uploadFile: Progress ${(progress * 100).toStringAsFixed(1)}%',
        );
      });

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      debugPrint('uploadFile: Success! URL = $downloadUrl');
      return downloadUrl;
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
    bool isAdult = false,
  }) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return null;

    try {
      final userDoc = await _db.collection('users').doc(u.uid).get();
      final name = userDoc.data()?['displayName'] ?? u.displayName ?? '';
      final avatar = userDoc.data()?['avatarUrl'] ?? u.photoURL ?? '';

      final ref = _db
          .collection('groups')
          .doc(groupId)
          .collection('memories')
          .doc();
      final memory = Memory(
        id: ref.id,
        groupId: groupId,
        authorUid: u.uid,
        authorName: name,
        authorAvatar: avatar,
        type: type,
        createdAt: DateTime.now(),
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
        isAdult: isAdult,
      );

      await ref.set(memory.toFirestore());
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
    String? musicTitle,
    String? musicArtist,
    String? imageUrl,
    bool? isPinned,
    bool? isAdult,
  }) async {
    try {
      final updates = <String, dynamic>{'editedAt': Timestamp.now()};
      if (title != null) updates['title'] = title;
      if (caption != null) updates['caption'] = caption;
      if (locationName != null) updates['locationName'] = locationName;
      if (musicTitle != null) updates['musicTitle'] = musicTitle;
      if (musicArtist != null) updates['musicArtist'] = musicArtist;
      if (imageUrl != null) updates['imageUrl'] = imageUrl;
      if (isPinned != null) updates['isPinned'] = isPinned;
      if (isAdult != null) updates['isAdult'] = isAdult;

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

  Future<List<Memory>> loadMemories({
    required String groupId,
    int limit = 50,
  }) async {
    try {
      final snap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('memories')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get()
          .timeout(const Duration(seconds: 10));

      return snap.docs
          .map((d) => Memory.fromFirestore(d.id, d.data()))
          .toList();
    } catch (e) {
      debugPrint('loadMemories failed: $e');
      return [];
    }
  }

  StreamSubscription? listenToMemories({
    required String groupId,
    required void Function(List<Memory> memories) onData,
    int limit = 100,
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
      await _db.collection('groups').doc(groupId).update({
        'customStatuses': FieldValue.arrayUnion([statusData]),
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

      // Get current custom statuses
      final doc = await _db.collection('groups').doc(groupId).get();
      final data = doc.data();
      if (data == null) return;

      final customStatuses = List<Map<String, dynamic>>.from(
        (data['customStatuses'] as List<dynamic>? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );

      // Find and update the status
      final index = customStatuses.indexWhere(
        (s) => s['id'] == statusData['id'],
      );
      if (index != -1) {
        customStatuses[index] = statusData;
        await _db.collection('groups').doc(groupId).update({
          'customStatuses': customStatuses,
        });

        // Also update currentStatus if it matches
        final currentStatus = data['currentStatus'] as Map<String, dynamic>?;
        if (currentStatus != null && currentStatus['id'] == statusData['id']) {
          await _db.collection('groups').doc(groupId).update({
            'currentStatus': statusData,
          });
        }
      }
    } catch (e) {
      debugPrint('updateCustomStatus failed: $e');
    }
  }

  /// Delete a custom status from the group
  Future<void> deleteCustomStatus(String groupId, String statusId) async {
    if (groupId.isEmpty) return;
    try {
      // Get current custom statuses
      final doc = await _db.collection('groups').doc(groupId).get();
      final data = doc.data();
      if (data == null) return;

      final customStatuses = List<Map<String, dynamic>>.from(
        (data['customStatuses'] as List<dynamic>? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );

      // Remove the status
      customStatuses.removeWhere((s) => s['id'] == statusId);

      final updates = <String, dynamic>{'customStatuses': customStatuses};

      // Also clear currentStatus if it matches
      final currentStatus = data['currentStatus'] as Map<String, dynamic>?;
      if (currentStatus != null && currentStatus['id'] == statusId) {
        updates['currentStatus'] = FieldValue.delete();
      }

      await _db.collection('groups').doc(groupId).update(updates);
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

  /// Listen to timers changes in real-time
  StreamSubscription? listenToTimers({
    required String groupId,
    required void Function(List<TimerItem> timers) onData,
  }) {
    return _db.collection('groups').doc(groupId).snapshots().listen((snap) {
      if (!snap.exists) return;
      final data = snap.data()!;
      final timersList = data['timers'] as List<dynamic>?;
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
  //  Firestore: groups/{groupId}/moodCalendar/{uid}/entries/{entryId}
  // ══════════════════════════════════════════════

  /// Add a mood entry for the current user
  Future<void> addMoodEntry({
    required String groupId,
    required Map<String, dynamic> entry,
  }) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return;
    try {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('moodCalendar')
          .doc(u.uid)
          .collection('entries')
          .doc(entry['id'] as String)
          .set(entry);
    } catch (e) {
      debugPrint('addMoodEntry failed: $e');
    }
  }

  /// Delete a mood entry
  Future<void> deleteMoodEntry({
    required String groupId,
    required String entryId,
  }) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return;
    try {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('moodCalendar')
          .doc(u.uid)
          .collection('entries')
          .doc(entryId)
          .delete();
    } catch (e) {
      debugPrint('deleteMoodEntry failed: $e');
    }
  }

  /// Listen to mood entries for a specific user in real-time
  StreamSubscription? listenToMoodEntries({
    required String groupId,
    required String uid,
    required void Function(List<Map<String, dynamic>> entries) onData,
  }) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('moodCalendar')
        .doc(uid)
        .collection('entries')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snap) {
          final entries = snap.docs.map((d) => d.data()).toList();
          onData(entries);
        }, onError: (e) => debugPrint('listenToMoodEntries error: $e'));
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
  Future<void> sendMissYou({
    required String groupId,
    required String senderName,
  }) async {
    final myUid = uid;
    if (myUid == null || groupId.isEmpty) return;
    try {
      // 1. Инкремент общего счётчика + per-user счётчик
      await _db.collection('groups').doc(groupId).set({
        'missYouCount': FieldValue.increment(1),
        'lastMissYou': {
          'senderUid': myUid,
          'senderName': senderName,
          'timestamp': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      // Per-user счётчик через dot-notation update
      await _db.collection('groups').doc(groupId).update({
        'missYouCounts.$myUid': FieldValue.increment(1),
      });

      // 2. Добавить запись в subcollection для push-триггера
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('missYouEvents')
          .add({
            'senderUid': myUid,
            'senderName': senderName,
            'timestamp': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('sendMissYou failed: $e');
    }
  }

  /// Слушать счётчик «Я скучаю» в реальном времени.
  StreamSubscription listenToMissYouCount({
    required String groupId,
    required void Function(int count) onData,
  }) {
    return _db.collection('groups').doc(groupId).snapshots().listen((snap) {
      final data = snap.data();
      final count = (data?['missYouCount'] as int?) ?? 0;
      onData(count);
    }, onError: (e) => debugPrint('listenToMissYouCount error: $e'));
  }

  /// Слушать per-user счётчики «Я скучаю» (Map uid → count).
  StreamSubscription listenToMissYouCounts({
    required String groupId,
    required void Function(Map<String, int> counts) onData,
  }) {
    return _db.collection('groups').doc(groupId).snapshots().listen((snap) {
      final data = snap.data();
      final raw = (data?['missYouCounts'] as Map<String, dynamic>?) ?? {};
      final counts = raw.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));
      onData(counts);
    }, onError: (e) => debugPrint('listenToMissYouCounts error: $e'));
  }

  // ══════════════════════════════════════════════
  //  PRESENCE — отслеживание статуса онлайн/офлайн
  //  Firestore: users/{uid}/isOnline (bool)
  //                          lastSeen (Timestamp)
  // ══════════════════════════════════════════════

  /// Обновляет статус присутствия текущего пользователя.
  /// Вызывается из AppLifecycleListener при переходе foreground/background.
  Future<void> setOnlineStatus(bool isOnline) async {
    final u = currentUser;
    if (u == null) return;
    try {
      final data = <String, dynamic>{
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      };
      await _db
          .collection('users')
          .doc(u.uid)
          .set(data, SetOptions(merge: true))
          .timeout(const Duration(seconds: 8));
      debugPrint('setOnlineStatus: uid=${u.uid}, isOnline=$isOnline');
    } catch (e) {
      debugPrint('setOnlineStatus failed: $e');
    }
  }

  /// Стрим присутствия пользователя по uid.
  /// Возвращает Map с полями isOnline (bool) и lastSeen (DateTime?).
  Stream<Map<String, dynamic>> streamUserPresence(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return {'isOnline': false, 'lastSeen': null};
      final isOnline = (data['isOnline'] as bool?) ?? false;
      final ts = data['lastSeen'];
      DateTime? lastSeen;
      if (ts is Timestamp) lastSeen = ts.toDate();
      return {'isOnline': isOnline, 'lastSeen': lastSeen};
    });
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
      batch.set(_canvasMainRef(groupId, canvasId), {
        'clearVersion': version,
        'bgColor': ?bgColorValue,
      }, SetOptions(merge: true));
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

  /// Stream of background colour changes for the shared canvas.
  Stream<int?> listenToCanvasBgColor({
    required String groupId,
    String canvasId = 'main',
  }) {
    return _canvasMainRef(
      groupId,
      canvasId,
    ).snapshots().map((snap) => (snap.data()?['bgColor'] as num?)?.toInt());
  }

  /// Stream of clear events for the shared canvas.
  Stream<int?> listenToCanvasClearVersion({required String groupId}) {
    return _canvasMainRef(groupId).snapshots().map(
      (snap) => (snap.data()?['clearVersion'] as num?)?.toInt(),
    );
  }

  /// Persist the canvas rotation so both users see the same orientation.
  /// Stored as `canvasRotation` (angle in milli-radians, int) on the canvas/main doc.
  Future<void> setCanvasRotation({
    required String groupId,
    required int rotationQuarterTurns, // actually milli-radians
  }) async {
    try {
      await _canvasMainRef(
        groupId,
      ).set({'canvasRotation': rotationQuarterTurns}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('setCanvasRotation failed: $e');
    }
  }

  /// Stream of canvas rotation changes (value is angle in milli-radians).
  Stream<int?> listenToCanvasRotation({required String groupId}) {
    return _canvasMainRef(groupId).snapshots().map(
      (snap) => (snap.data()?['canvasRotation'] as num?)?.toInt(),
    );
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

  const _LocalNotificationContent({
    required this.title,
    required this.body,
  });
}

/// Internal transfer object used by [listenToDrawingStrokes].
class _DrawStrokeRaw {
  final String id;
  final Map<String, dynamic> data;
  const _DrawStrokeRaw({required this.id, required this.data});
}
