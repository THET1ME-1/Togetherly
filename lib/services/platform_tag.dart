import 'package:flutter/foundation.dart';

import 'pocketbase_service.dart';

/// Отметка о платформе в профиле (`users.platform`).
///
/// Togetherly+ продаётся на Android и через сайт, а на iOS его не существует
/// вовсе — там нет ни витрины, ни упоминаний. Аккаунт при этом один: человек
/// покупает с телефона на Android, а заходит с iPhone, и фичи у него открыты
/// без единого слова про покупку. Чтобы такие случаи можно было объяснить, а
/// магазинный бот не звал покупать тех, у кого покупка не отобразится витриной,
/// клиент отмечает в профиле платформу последнего входа.
///
/// Пишем не чаще одного раза за запуск и только когда значение разошлось с тем,
/// что уже лежит в профиле: у пары с двумя телефонами иначе началась бы
/// перестрелка запросами.
class PlatformTag {
  const PlatformTag._();

  static const String _field = 'platform';

  /// `ios` или `android`. Прочие платформы (десктоп в отладке) не помечаем.
  static String? get current => switch (defaultTargetPlatform) {
        TargetPlatform.iOS => 'ios',
        TargetPlatform.android => 'android',
        _ => null,
      };

  static bool _syncedThisRun = false;

  /// Проставляет платформу в профиле, если она там другая.
  ///
  /// Best-effort: сбой запроса ничего не ломает и молчит в лог — отметка
  /// нужна поддержке, а не приложению.
  static Future<void> sync() async {
    if (_syncedThisRun) return;
    final value = current;
    if (value == null) return;

    final svc = PocketBaseService();
    final uid = svc.userId ?? '';
    if (uid.isEmpty) return;

    final rec = svc.currentUser;
    if (rec == null) return;
    if (rec.data[_field] == value) {
      _syncedThisRun = true;
      return;
    }

    try {
      final updated =
          await svc.pb.collection('users').update(uid, body: {_field: value});
      // update() не трогает authStore.record, а его читает currentProfile() —
      // без этого следующий запуск снова счёл бы отметку устаревшей.
      svc.pb.authStore.save(svc.pb.authStore.token, updated);
      _syncedThisRun = true;
    } catch (e) {
      debugPrint('PlatformTag.sync failed (best-effort, ignored): $e');
    }
  }

  /// Только для тестов: забыть, что отметка уже уходила.
  @visibleForTesting
  static void resetForTest() => _syncedThisRun = false;
}
