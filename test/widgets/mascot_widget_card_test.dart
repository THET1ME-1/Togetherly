import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/mascot/mascot_widget_keys.dart';

/// Имя провайдера живёт в четырёх местах разом: константа Dart, класс Kotlin,
/// приёмник в манифесте и карточка каталога. Разъехались — виджет либо не
/// ставится, либо стоит и не обновляется, и увидеть это можно только на
/// устройстве.
void main() {
  final screen = File('lib/screens/widget_screen.dart').readAsStringSync();
  final kotlin = File(
    'android/app/src/main/kotlin/com/togetherly/love/MascotWidgetProvider.kt',
  ).readAsStringSync();
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('каталог предлагает все четыре размера маскота', () {
    for (final provider in kMascotWidgetProviders) {
      expect(
        screen.contains('com.togetherly.love.$provider'),
        isTrue,
        reason: 'в каталоге виджетов нет размера $provider',
      );
    }
  });

  test('имена провайдеров совпадают у Dart, Kotlin и манифеста', () {
    for (final provider in kMascotWidgetProviders) {
      expect(kotlin.contains('class $provider'), isTrue, reason: 'нет класса $provider');
      expect(manifest.contains('.$provider'), isTrue, reason: 'нет приёмника $provider');
    }
  });

  test('виджет привязывается к паре своим типом', () {
    // Без этой ветки привязка уходит в timer_next_bind_group и перехватывает
    // группу у «Таймера», а сам виджет остаётся без пары.
    expect(screen.contains("'mascot' => 'mascot'"), isTrue);
    expect(kotlin.contains('"mascot"'), isTrue);
  });

  test('после установки виджет сразу получает данные', () {
    expect(screen.contains("case 'mascot':"), isTrue);
    expect(screen.contains('mascotService.resyncStreakWidget()'), isTrue);
  });

  test('у каждого размера есть превью в списке лончера', () {
    for (final size in ['4x1', '2x2', '4x2', '4x4']) {
      final png = File(
        'android/app/src/main/res/drawable-nodpi/tg_preview_mascot_$size.png',
      );
      expect(png.existsSync(), isTrue, reason: 'нет превью $size');
      expect(png.lengthSync(), greaterThan(1000), reason: 'превью $size пустое');
    }
  });
}
