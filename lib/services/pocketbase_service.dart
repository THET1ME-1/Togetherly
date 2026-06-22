import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ядро клиента PocketBase — единая точка доступа к нашему self-hosted бэкенду
/// на VPS (миграция Firebase→PocketBase, Этап 6).
///
/// Никакого Firebase: данные/auth/realtime/медиа идут через этот клиент.
/// Сессия (token + запись юзера) сохраняется в SharedPreferences через
/// [AsyncAuthStore], поэтому вход переживает перезапуск процесса.
class PocketBaseService {
  PocketBaseService._();
  static final PocketBaseService instance = PocketBaseService._();
  factory PocketBaseService() => instance;

  /// Базовый URL нашего PocketBase (HTTPS, Let's Encrypt; домен держит DuckDNS).
  static const String baseUrl = 'https://togetherly.duckdns.org';

  /// Ключ хранения сериализованной auth-сессии.
  static const String _authPrefsKey = 'pb_auth';

  PocketBase? _pb;
  bool _initialized = false;

  /// Клиент. До [init] обращаться нельзя.
  PocketBase get pb {
    final c = _pb;
    if (c == null) {
      throw StateError('PocketBaseService.init() ещё не вызван');
    }
    return c;
  }

  /// Поднимает клиент и восстанавливает сессию из SharedPreferences.
  /// Идемпотентно — повторные вызовы игнорируются.
  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_authPrefsKey);

    final authStore = AsyncAuthStore(
      initial: stored,
      save: (String data) async {
        final p = await SharedPreferences.getInstance();
        await p.setString(_authPrefsKey, data);
      },
      clear: () async {
        final p = await SharedPreferences.getInstance();
        await p.remove(_authPrefsKey);
      },
    );

    _pb = PocketBase(baseUrl, authStore: authStore);
    _initialized = true;
    debugPrint('PocketBaseService: init, авторизован=$isLoggedIn');
  }

  /// Есть ли валидная сессия.
  bool get isLoggedIn => _pb?.authStore.isValid ?? false;

  /// id текущего юзера = канонический идентификатор в данных (`author_uid`,
  /// `user_uid`, `members[]` ссылаются на него строкой). У мигрированных юзеров
  /// `id` = их прежний uid (через override поля id при импорте), у новых —
  /// авто-id PocketBase. null, если не вошёл.
  String? get userId => _pb?.authStore.record?.id;

  String? get userEmail => _pb?.authStore.record?.data['email'] as String?;

  /// Запись текущего юзера (профиль из коллекции users) или null.
  RecordModel? get currentUser => _pb?.authStore.record;

  /// Сбрасывает сессию (выход). Чистит и persisted-копию (через AsyncAuthStore).
  void signOut() => _pb?.authStore.clear();
}
