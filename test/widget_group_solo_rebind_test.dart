import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Виджет, поставленный до того, как появилась пара, навсегда оставался
/// «один»: `WidgetGroupHelper.getOrBind` запоминал заглушку `solo` при первой
/// отрисовке и больше в группу не заглядывал.
///
/// Поймано на эмуляторе 14.09.2026: после входа первая синхронизация прошла
/// до загрузки пары и записала `year_ring_latest_group = solo`, оба «Кольца
/// года» привязались к ней и показывали «Укажите дату начала» при заданной
/// дате. Та же судьба у всех виджетов на этом помощнике — «Вместе», заметка,
/// «Скучаю», настроение, календарь лет — у каждого, кто ставит виджет раньше,
/// чем собирает пару.
void main() {
  final src = File(
    'android/app/src/main/kotlin/com/togetherly/love/WidgetGroupHelper.kt',
  ).readAsStringSync();
  final body = src.split('fun getOrBind(')[1].split('\n    fun ')[0];

  test('привязка к solo уступает появившейся паре', () {
    final storedCheck = body.indexOf('if (!stored.isNullOrEmpty())');
    expect(storedCheck, greaterThan(-1));
    final storedBranch = body.substring(storedCheck, body.indexOf('return stored'));
    expect(storedBranch, contains('SOLO'),
        reason: 'сохранённую заглушку solo надо перепроверять');
    expect(storedBranch, contains('_latest_group'),
        reason: 'и перепривязывать к текущей паре');
  });

  test('заглушка названа так же, как её пишет приложение', () {
    expect(src, contains('const val SOLO = "solo"'));
    final dart = File('lib/services/home_widget_service.dart').readAsStringSync();
    expect(dart, contains("groupId.isEmpty ? 'solo' : groupId"));
  });
}
