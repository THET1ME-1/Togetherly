import 'package:flutter/foundation.dart';

import 'locale_service.dart';
import 'pocketbase_service.dart';

/// Язык приложения в профиле (`users.lang`).
///
/// Уведомления пишет сервер, а языка, выбранного в приложении, он не знал и
/// слал всем по-русски (отзыв в App Store 19.08.2026: «The notification and
/// widgets are in Russian though the app I have set to English»). Приложение
/// пишет код языка при запуске, если в профиле другой, и при каждой смене.
class LangTag {
  const LangTag._();

  static const String _field = 'lang';

  static String? Function() _read = _readProfile;
  static Future<void> Function(String code) _write = _writeProfile;
  static bool _listening = false;

  /// Сверить язык сейчас и следить за сменой. Повторный вызов ничего не ломает.
  static Future<void> start() async {
    if (!_listening) {
      _listening = true;
      LocaleService.instance.addListener(_onLocale);
    }
    await _sync();
  }

  static void stop() {
    if (!_listening) return;
    _listening = false;
    LocaleService.instance.removeListener(_onLocale);
  }

  static void _onLocale() => _sync();

  static Future<void> _sync() async {
    final code = LocaleService.instance.language.code;
    if (_read() == code) return;
    try {
      await _write(code);
    } catch (e) {
      debugPrint('LangTag: не записался язык (повторим при следующем запуске): $e');
    }
  }

  static String? _readProfile() => PocketBaseService().currentUser?.data[_field] as String?;

  static Future<void> _writeProfile(String code) async {
    final svc = PocketBaseService();
    final uid = svc.userId ?? '';
    if (uid.isEmpty) return;
    final updated = await svc.pb.collection('users').update(uid, body: {_field: code});
    // update() не трогает authStore.record: без этого следующий запуск снова
    // счёл бы язык в профиле устаревшим.
    svc.pb.authStore.save(svc.pb.authStore.token, updated);
  }

  @visibleForTesting
  static void debugReset({
    required String? Function() read,
    required Future<void> Function(String code) write,
  }) {
    stop();
    _read = read;
    _write = write;
  }
}
