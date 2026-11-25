import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Живое фото в парном виджете есть только на Android: кадры подсовывает
/// `WidgetAnimPlayer.kt`, а расширение виджетов iPhone ключей раскадровки
/// (`anim_sheet_path`, `anim_manifest`) не читает. Обращение 649: на айфоне
/// кнопка была, фото не вставало, приложение писало «Живое фото в виджете».
void main() {
  test('кнопка «Живое фото» в листе выбора закрыта на iPhone', () {
    final src = File('lib/screens/widget_screen.dart').readAsStringSync();
    final call = src.indexOf('_liveButton(context),');
    expect(call, greaterThan(0), reason: 'вызов кнопки живого фото пропал');
    final before = src.substring(0, call);
    final guard = before.lastIndexOf('if (!Platform.isIOS)');
    expect(guard, greaterThan(0), reason: 'кнопка живого фото без проверки платформы');
    // проверка стоит прямо над вызовом, а не где-то выше в файле
    expect(call - guard, lessThan(120));
  });

  test('виджет iPhone и правда не читает раскадровку', () {
    final dir = Directory('ios');
    final hits = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.swift'))
        .where((f) => f.readAsStringSync().contains('anim_sheet_path'));
    // Появится чтение раскадровки в Swift — снять запрет кнопки выше.
    expect(hits, isEmpty);
  });
}
