import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Провайдер маскота один на четыре размера, поэтому набор `R.id.*` у всех
/// разметок обязан совпадать: чего нет в файле, то на устройстве вылетит
/// `InflateException` — в сборке и анализаторе при этом чисто.
void main() {
  final provider = File(
    'android/app/src/main/kotlin/com/togetherly/love/MascotWidgetProvider.kt',
  );
  final layouts = [
    'tg_mascot_4x1',
    'tg_mascot_2x2',
    'tg_mascot_4x2',
    'tg_mascot_4x4',
  ];

  test('каждый id из провайдера есть во всех четырёх разметках', () {
    expect(provider.existsSync(), isTrue, reason: 'нет ${provider.path}');
    final ids = RegExp(r'R\.id\.([a-z0-9_]+)')
        .allMatches(provider.readAsStringSync())
        .map((m) => m.group(1)!)
        .toSet();
    expect(ids, isNotEmpty);

    for (final name in layouts) {
      final file = File('android/app/src/main/res/layout/$name.xml');
      expect(file.existsSync(), isTrue, reason: 'нет ${file.path}');
      final xml = file.readAsStringSync();
      for (final id in ids) {
        expect(
          xml.contains('@+id/$id'),
          isTrue,
          reason: 'в $name.xml нет id «$id», который пишет провайдер',
        );
      }
    }
  });

  test('раскладки закреплены за размерами по одному классу', () {
    final code = provider.readAsStringSync();
    for (final size in ['4x1', '2x2', '4x2', '4x4']) {
      final cls = 'MascotWidget${size}Provider';
      expect(code.contains('class $cls'), isTrue, reason: 'нет класса $cls');
      expect(
        code.contains('R.layout.tg_mascot_$size'),
        isTrue,
        reason: 'класс $cls не закреплён за своей разметкой',
      );
    }
  });

  test('все четыре приёмника объявлены в манифесте', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    for (final size in ['4x1', '2x2', '4x2', '4x4']) {
      expect(
        manifest.contains('.MascotWidget${size}Provider'),
        isTrue,
        reason: 'в манифесте нет MascotWidget${size}Provider',
      );
      expect(
        manifest.contains('@xml/tg_mascot_${size}_info'),
        isTrue,
        reason: 'приёмник $size не ссылается на свой info.xml',
      );
    }
  });

  test('ночь выбирается по окну сна, а не по зашитым часам', () {
    final code = provider.readAsStringSync();
    expect(code.contains('sleep_from'), isTrue);
    expect(code.contains('sleep_to'), isTrue);
    // 23 и 7 часов были зашиты в старой версии маскота; в виджете их быть не
    // должно — окно приходит из настроек человека.
    expect(
      RegExp(r'\b23\s*\*\s*60\b').hasMatch(code),
      isFalse,
      reason: 'окно сна зашито в код вместо ключей',
    );
  });
}
