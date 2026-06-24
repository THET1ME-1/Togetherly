import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pocketbase_service.dart';

/// Аутентификация через PocketBase (миграция Firebase→PB, Этап 6, слой Auth).
///
/// Заменяет Firebase Auth. Поддерживает:
///  • email/пароль (регистрация + вход) — работает сразу;
///  • Google OAuth2 (web-flow PB) — требует настройки провайдера `google` в
///    панели PocketBase (Client ID/Secret + redirect `…/api/oauth2-redirect`).
///
/// Идентичность в данных завязана на `users.id`: `author_uid`/`user_uid`/
/// `members[]` хранят его строкой. У мигрированных юзеров `id` = их прежний uid
/// (проставляется через override поля id при импорте, Этап 5), у НОВЫХ — обычный
/// авто-id PocketBase. Отдельного «uid»-поля нет — id и есть ключ.
class PbAuthService {
  PbAuthService._();
  static final PbAuthService instance = PbAuthService._();
  factory PbAuthService() => instance;

  final PocketBaseService _svc = PocketBaseService();
  PocketBase get _pb => _svc.pb;

  /// Коллекция аккаунтов.
  static const String _usersCol = 'users';

  /// «Мой uid» для слоя данных = `users.id`.
  String? get currentUid => _svc.userId;

  bool get isLoggedIn => _svc.isLoggedIn;

  /// Регистрация по email/паролю. Создаёт запись в `users`, входит, проставляет
  /// `firebase_uid`. Возвращает запись профиля или null.
  Future<RecordModel?> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      await _pb.collection(_usersCol).create(body: {
        'email': email,
        'password': password,
        'passwordConfirm': password,
        'name': displayName,
        'display_name': displayName,
        'emailVisibility': true,
      });
      // Сразу входим (create не авторизует).
      await _pb.collection(_usersCol).authWithPassword(email, password);
      await _ensureProfile(displayName: displayName);
      return _svc.currentUser;
    } catch (e, st) {
      debugPrint('PbAuth.signUpWithEmail failed: $e');
      debugPrintStack(stackTrace: st);
      rethrow;
    }
  }

  /// Вход по email/паролю.
  Future<RecordModel?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      await _pb.collection(_usersCol).authWithPassword(email, password);
      await _ensureProfile();
      return _svc.currentUser;
    } catch (e) {
      debugPrint('PbAuth.signInWithEmail failed: $e');
      rethrow;
    }
  }

  /// Вход через Google (OAuth2 web-flow PocketBase): открывает страницу
  /// провайдера в браузере, PB ловит редирект и возвращает сессию по realtime.
  /// Требует настроенного провайдера `google` в панели PB.
  Future<RecordModel?> signInWithGoogle() async {
    try {
      final auth = await _pb.collection(_usersCol).authWithOAuth2(
        'google',
        (url) async {
          // In-app браузер держит приложение на переднем плане → realtime-
          // websocket OAuth-флоу PB выживает и сессия возвращается в приложение
          // (externalApplication уводил Flutter в фон → Completer висел).
          await launchUrl(url, mode: LaunchMode.inAppBrowserView);
        },
      );
      // OAuth завершён — закрыть in-app вьюху (iOS: SFSafariViewController;
      // Android Custom Tabs: no-op, фокус и так возвращается).
      try {
        await closeInAppWebView();
      } catch (_) {}
      // Профиль из OAuth-меты (имя/аватар), если в записи ещё пусто.
      final meta = auth.meta;
      await _ensureProfile(
        displayName: meta['name'] as String?,
        avatarUrl: meta['avatarUrl'] as String? ?? meta['avatarURL'] as String?,
      );
      return _svc.currentUser;
    } catch (e, st) {
      debugPrint('PbAuth.signInWithGoogle failed: $e');
      debugPrintStack(stackTrace: st);
      rethrow;
    }
  }

  /// Вход через Apple (OAuth2 web-flow PocketBase): открывает страницу
  /// провайдера в браузере, PB ловит редирект и возвращает сессию.
  /// Требует настроенного провайдера `apple` в панели PB (Services ID + ключ;
  /// секрет авто-обновляется кроном на VPS — см. pocketbase/apple_secret.py).
  Future<RecordModel?> signInWithApple() async {
    try {
      final auth = await _pb.collection(_usersCol).authWithOAuth2(
        'apple',
        (url) async {
          await launchUrl(url, mode: LaunchMode.inAppBrowserView);
        },
      );
      try {
        await closeInAppWebView();
      } catch (_) {}
      final meta = auth.meta;
      await _ensureProfile(
        displayName: meta['name'] as String?,
        avatarUrl: meta['avatarUrl'] as String? ?? meta['avatarURL'] as String?,
      );
      return _svc.currentUser;
    } catch (e, st) {
      debugPrint('PbAuth.signInWithApple failed: $e');
      debugPrintStack(stackTrace: st);
      rethrow;
    }
  }

  /// Письмо для сброса пароля (email-провайдер PB).
  Future<void> sendPasswordReset(String email) =>
      _pb.collection(_usersCol).requestPasswordReset(email);

  /// Профиль текущего юзера в формате camelCase — совместимо с прежним
  /// `FirebaseService.loadUserProfile` (чтобы экраны входа почти не менялись).
  /// null, если сессии нет. gender может быть null (новый OAuth-юзер до setup).
  Map<String, dynamic>? currentProfile() {
    final rec = _svc.currentUser;
    if (rec == null) return null;
    final d = rec.data;
    String s(dynamic v) => v is String ? v : '';
    final name =
        s(d['display_name']).isNotEmpty ? s(d['display_name']) : s(d['name']);
    return {
      'displayName': name,
      'email': s(d['email']).isNotEmpty ? s(d['email']) : (_svc.userEmail ?? ''),
      'gender': d['gender'],
      'avatarUrl': s(d['avatar_url']),
    };
  }

  /// «Тихий вход» — сессия уже персистится в authStore (SharedPreferences).
  /// Если валидна, освежаем токен; иначе возвращаем null.
  Future<RecordModel?> signInSilently() async {
    if (!_svc.isLoggedIn) return null;
    try {
      await _pb.collection(_usersCol).authRefresh();
    } catch (e) {
      debugPrint('PbAuth.authRefresh failed (сессия устарела?): $e');
    }
    return _svc.isLoggedIn ? _svc.currentUser : null;
  }

  void signOut() => _svc.signOut();

  /// Дозаполняет имя/аватар в профиле, если там пусто (id юзер не трогает —
  /// им управляет PocketBase). Патчит только недостающее.
  Future<void> _ensureProfile({String? displayName, String? avatarUrl}) async {
    final rec = _svc.currentUser;
    if (rec == null) return;
    final patch = <String, dynamic>{};

    final curName = rec.data['display_name'];
    if ((curName is! String || curName.isEmpty) &&
        displayName != null &&
        displayName.isNotEmpty) {
      patch['display_name'] = displayName;
    }
    final curAvatar = rec.data['avatar_url'];
    if ((curAvatar is! String || curAvatar.isEmpty) &&
        avatarUrl != null &&
        avatarUrl.isNotEmpty) {
      patch['avatar_url'] = avatarUrl;
    }
    if (patch.isEmpty) return;
    try {
      await _pb.collection(_usersCol).update(rec.id, body: patch);
    } catch (e) {
      debugPrint('PbAuth._ensureProfile patch failed: $e');
    }
  }
}
