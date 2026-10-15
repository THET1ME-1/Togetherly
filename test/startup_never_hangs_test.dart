import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож «бесконечной загрузки».
///
/// Заставка держится, пока идёт `_init`, а внутри раньше стояли сетевые
/// запросы. На медленной связи люди видели вечный спиннер вместо приложения, и
/// перезапуск не помогал: запрос повисал снова. Пределы времени не спасали: на
/// рвущейся связи заставка всё равно стояла до десяти секунд при полном кэше
/// (жалоба 15.10.2026). Теперь заставка сеть не ждёт вовсе: профиль и проверка
/// версии идут в фоне, а у самой заставки — страховка на любой расклад.
void main() {
  test('заставка не ждёт сервер', () {
    final source = File('lib/main.dart').readAsStringSync();

    final syncAt = source.indexOf('syncFromServer()');
    expect(syncAt, isNot(-1), reason: 'вызов пропал — обновите сторожа');
    expect(source.substring(syncAt - 40, syncAt), contains('unawaited('),
        reason: 'профиль с сервера догружается в фоне, заставка его не ждёт');

    final initAt = source.indexOf('Future<void> _init() async');
    final init = source.substring(initAt, source.indexOf('\n  }\n', initAt));
    expect(init.contains('await PbDataService()'), isFalse,
        reason: 'проверка версии идёт в фоне');
    expect(init.contains('unawaited(_checkMinBuild())'), isTrue);

    final user = File('lib/models/user_data.dart').readAsStringSync();
    final load = user.substring(user.indexOf('Future<void> loadFromPrefs('),
        user.indexOf('Future<void> syncFromServer('));
    expect(load.contains('await _syncFromFirestore'), isFalse,
        reason: 'чтение профиля с телефона не ждёт сервер');
    expect(load.contains('await syncFromServer'), isFalse);
  });

  test('заставка снимается страховкой, даже если старт затянулся', () {
    final source = File('lib/main.dart').readAsStringSync();
    final initAt = source.indexOf('Future<void> _init() async');
    expect(initAt, isNot(-1));

    final head = source.substring(initAt, initAt + 800);
    expect(head, contains('Timer('),
        reason: 'нужна страховка, снимающая заставку по времени');
    expect(head, contains('_loading = false'),
        reason: 'страховка обязана именно снимать заставку');
  });
}
