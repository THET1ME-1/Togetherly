import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож «бесконечной загрузки».
///
/// Заставка держится, пока идёт `_init`, а внутри — сетевые запросы. На медленной
/// связи люди видели вечный спиннер вместо приложения, и перезапуск не помогал:
/// запрос повисал снова. Поэтому у сетевых ожиданий на старте обязан быть
/// таймаут, а у самой заставки — страховка, снимающая её при любом раскладе.
void main() {
  test('сетевая синхронизация на старте ограничена по времени', () {
    final source = File('lib/main.dart').readAsStringSync();

    final syncAt = source.indexOf('syncFromServer()');
    expect(syncAt, isNot(-1), reason: 'вызов пропал — обновите сторожа');

    // Таймаут должен стоять рядом с вызовом, а не где-то в файле.
    final tail = source.substring(syncAt, syncAt + 220);
    expect(tail, contains('.timeout('),
        reason: 'без таймаута заставка висит, пока сервер молчит');
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
