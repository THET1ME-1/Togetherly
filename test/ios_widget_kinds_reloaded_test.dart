import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Каждый виджет обязан просыпаться, когда его данные поменялись.
///
/// На iOS свежие данные в App Group сами по себе ничего не меняют: система
/// перерисует виджет, только когда ей велят — `HomeWidget.updateWidget(name:)`
/// под капотом зовёт `WidgetCenter.reloadTimelines(ofKind:)`. Kind, который в
/// приложении не упоминается, живёт на одном лишь расписании провайдера и
/// показывает вчерашние числа.
///
/// Так и вышло с экраном блокировки: три виджета (`LockDaysWidget`,
/// `LockMissWidget`, `LockMoodWidget`) читали готовые ключи `together_*`,
/// `miss_*` и `tgmood_*`, но будить их никто не будил — жалоба 19.08.2026
/// «виджеты на экране блокировки данные не обновляют».
void main() {
  test('каждый kind виджета есть в приложении', () {
    final dir = Directory('ios/TogetherlyWidget');
    final kinds = <String, String>{};
    final re = RegExp(r'(?:StaticConfiguration|AppIntentConfiguration)'
        r'\(\s*kind:\s*"([^"]+)"');
    for (final file in dir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.swift')) continue;
      final name = file.uri.pathSegments.last;
      for (final m in re.allMatches(file.readAsStringSync())) {
        kinds[m.group(1)!] = name;
      }
    }
    expect(kinds.length, greaterThanOrEqualTo(20),
        reason: 'Разобрано подозрительно мало виджетов: ${kinds.length}');

    final dart = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    final orphans = <String>[];
    kinds.forEach((kind, file) {
      if (!dart.contains(kind)) orphans.add('$kind ($file)');
    });
    expect(orphans, isEmpty,
        reason: 'Эти виджеты никто не будит, они покажут старые данные:\n'
            '${orphans.join('\n')}');
  });

  test('дни вместе считает само расширение, а не готовое число из Dart', () {
    // Число `together_<g>_days` пишет приложение. Пока оно закрыто, писать
    // некому: на экране блокировки «Вместе N дн.» застывает на том дне, когда
    // приложение открывали последний раз (жалоба 19.08.2026). Тем же приёмом
    // уже живут таймер и кольцо года — расширение считает дни от метки
    // времени старта и обновляется по своему расписанию, без приложения.
    final together =
        File('ios/TogetherlyWidget/TogetherWidget.swift').readAsStringSync();
    final lock =
        File('ios/TogetherlyWidget/LockScreenWidgets.swift').readAsStringSync();
    expect(together.contains('together_\\(g)_start_ms'), isTrue,
        reason: 'Виджет «Вместе» читает метку времени старта');
    expect(lock.contains('together_\\(g)_start_ms'), isTrue,
        reason: 'Экран блокировки читает метку времени старта');

    final dart =
        File('lib/services/home_widget_service.dart').readAsStringSync();
    expect(dart.contains("'together_\${g}_start_ms'"), isTrue,
        reason: 'Метку кладёт syncTogether');
  });
}
