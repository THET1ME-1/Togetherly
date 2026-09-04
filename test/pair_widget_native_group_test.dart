// Нативные парные виджеты читают ключи СВОЕЙ пары.
//
// Ключи в контейнере — единственный договор между приложением и виджетом, и
// проверить его на этой машине больше нечем: ни Android, ни iOS тут не
// запускаются. Разъедется — виджет молча покажет чужую пару или опустеет.
//
// До 04.09.2026 парный виджет читал общий набор без пары в имени. У человека с
// двумя связями на столе оказывалась половина одной пары рядом с половиной
// другой: чья синхронизация прошла последней, ту и рисовало.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final kotlin = File(
    'android/app/src/main/kotlin/com/togetherly/love/LoveWidgetProvider.kt',
  ).readAsStringSync();
  final swift =
      File('ios/TogetherlyWidget/LoveWidget.swift').readAsStringSync();
  final dart = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.readAsStringSync())
      .join('\n');

  test('Android берёт пару экземпляра, а не последнюю синхронизацию', () {
    expect(kotlin.contains('WidgetGroupHelper.getOrBind'), isTrue,
        reason: 'иначе два виджета для двух связей покажут одну и ту же');
    expect(kotlin.contains('"pair"'), isTrue);
  });

  test('Android читает ключи пары', () {
    expect(kotlin.contains(r'"love_${groupId}_$name"'), isTrue);
    for (final k in const [
      'my_photo_path',
      'partner_photo_path',
      'my_mood_emoji_path',
      'partner_status',
    ]) {
      expect(kotlin.contains('key("$k")'), isTrue,
          reason: '$k читается мимо пары');
    }
  });

  test('iPhone находит пару по указателю', () {
    expect(swift.contains('latestGroup("love_latest_group")'), isTrue,
        reason: 'привязки к экземпляру на iOS нет — только указатель');
    expect(swift.contains(r'"love_\(group)_\(name)"'), isTrue);
  });

  test('iPhone читает ключи пары', () {
    for (final k in const [
      'my_photo_path',
      'partner_photo_path',
      'my_mood_emoji_path',
      'partner_status',
    ]) {
      expect(swift.contains('key("$k")'), isTrue,
          reason: '$k читается мимо пары');
    }
  });

  test('обе платформы ждут отметку готовности от приложения', () {
    expect(kotlin.contains('_ready'), isTrue);
    expect(swift.contains('_ready'), isTrue);
    expect(dart.contains("'love_\${groupId}_ready'"), isTrue,
        reason: 'без отметки виджет опустеет сразу после обновления сборки');
  });

  test('приложение пишет указатель на открытую пару', () {
    expect(dart.contains("'love_latest_group'"), isTrue);
  });

  // Имя ключа привязки должно совпадать буква в букву: Kotlin ждёт
  // `<тип>_next_bind_group` по типу виджета, а данные лежат под `love_`. Пока
  // они расходились, виджет при постановке брал не ту пару.
  test('привязка при постановке зовётся так же, как её ищет Android', () {
    final helper = File(
      'android/app/src/main/kotlin/com/togetherly/love/WidgetGroupHelper.kt',
    ).readAsStringSync();
    expect(helper.contains(r'"${widgetType}_next_bind_group"'), isTrue);
    expect(dart.contains("'pair' => 'pair'"), isTrue,
        reason: 'Kotlin читает pair_next_bind_group, а не love_next_bind_group');
  });
}
