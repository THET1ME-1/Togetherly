import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Firebase Storage выключен давно: файлы живут в PocketBase и S3. Адрес
/// хранилища остаётся только там, где разбираются СТАРЫЕ ссылки из базы
/// (фильтр шума и плееры). Всё остальное — мёртвые запросы: обои пяти тем и
/// экрана настройки месяцами просили картинку, получали 402 и рисовали
/// запасной цвет (разбор 23.09.2026).
void main() {
  const allowed = {
    'lib/services/crash_noise.dart',
    'lib/services/watch_videos_service.dart',
    'lib/screens/memory_lane/players.dart',
  };

  test('адрес Firebase Storage живёт только в разборе старых ссылок', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll('\\', '/');
      if (allowed.contains(path)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('firebasestorage')) {
          offenders.add('$path:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('ошибка загрузки не отправляет человека в Firebase', () {
    for (final f in Directory('lib/l10n/dict').listSync()) {
      if (f is! File) continue;
      expect(f.readAsStringSync().contains('Firebase Storage'), isFalse,
          reason: '${f.path}: строка про Firebase Storage');
    }
  });
}
