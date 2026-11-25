import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Живое фото в парном виджете на iPhone (обращение 649).
///
/// Android играет кадры на самом виджете (`WidgetAnimPlayer.kt`). Виджет
/// iPhone двигаться не умеет: он ставит первый кадр раскадровки на место моего
/// фото, а кадры играет превью в приложении. До 25.11.2026 виджет iPhone ключей
/// раскадровки не читал, а приложение клало файл в свою песочницу, которую
/// расширение не видит: фото не вставало вовсе. Картинку виджета проверяет
/// симулятор (`ios-widget-snapshot.yml`), здесь — что связка не разошлась.
void main() {
  test('виджет iPhone читает те же ключи раскадровки, что Android', () {
    final swift = File('ios/TogetherlyWidget/LoveWidget.swift').readAsStringSync();
    final kotlin =
        File('android/app/src/main/kotlin/com/togetherly/love/WidgetAnimPlayer.kt')
            .readAsStringSync();
    final dart = File('lib/services/widget_anim_service.dart').readAsStringSync();
    for (final key in ['anim_sheet_path', 'anim_manifest']) {
      expect(swift, contains('"$key"'), reason: 'Swift не знает ключ $key');
      expect(kotlin, contains('"$key"'), reason: 'Kotlin не знает ключ $key');
      expect(dart, contains("'$key'"), reason: 'Dart не знает ключ $key');
    }
    // первый кадр стоит на месте моего фото
    expect(swift, contains('live ?? s.uiImage(key("my_photo_path")'));
  });

  test('на iPhone раскадровка уезжает в контейнер App Group', () {
    final dart = File('lib/services/widget_anim_service.dart').readAsStringSync();
    final install = dart.substring(dart.indexOf('Future<bool> install('));
    expect(install.indexOf('appGroupReadablePath'), greaterThan(0),
        reason: 'путь из песочницы приложения виджет iPhone не прочитает');
    expect(dart, contains("clearAppGroupMedia('widget_anim_')"),
        reason: 'сброс живого фото обязан убирать и копию в App Group');
  });

  test('кнопка «Живое фото» есть на обеих платформах', () {
    final src = File('lib/screens/widget_screen.dart').readAsStringSync();
    final call = src.indexOf('_liveButton(context),');
    expect(call, greaterThan(0));
    final before = src.substring((call - 200).clamp(0, call), call);
    expect(before, isNot(contains('Platform.isIOS')));
  });
}
