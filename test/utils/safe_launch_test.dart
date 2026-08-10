import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/safe_launch.dart';

/// Сторож открытия ссылок.
///
/// `url_launcher` бросает `PlatformException(ACTIVITY_NOT_FOUND)`, когда под
/// интент нет приложения, и это падение доходило до Bugsink 49 раз за 9 августа
/// 2026. Причины две: ссылка на музыку без установленного клиента и текст
/// вместо адреса — через «Поделиться → Togetherly» из музыкального приложения
/// приезжает «Listen to Koyu - Sen Benim Başımın…» без ссылки, попадает в поле
/// адреса, и `Uri.parse` отдаёт URI без схемы.
///
/// Обёртка `safeLaunchUrl` закрывает оба случая, но толк от неё есть только
/// пока её зовут все. Поэтому второй тест сканирует `lib/` и валит сборку на
/// новом голом `launchUrl(`.
void main() {
  group('safeLaunchUrl отбрасывает то, что не адрес', () {
    test('текст без схемы не уходит в систему', () async {
      expect(
        await safeLaunchString('Listen to Koyu - Sen Benim Basimin Tacisin'),
        isFalse,
      );
      expect(await safeLaunchString('просто заметка'), isFalse);
      expect(await safeLaunchString(''), isFalse);
      expect(await safeLaunchString(null), isFalse);
    });

    test('незнакомая схема тоже не уходит', () async {
      // Такие ссылки приезжают из шаринга и обрабатываются не системой, а нами.
      expect(
        await safeLaunchUrl(Uri.parse('loveapp://invite/4F2K9C')),
        isFalse,
      );
      expect(await safeLaunchUrl(Uri.parse('file:///data/x.jpg')), isFalse);
    });

    test('адрес со знакомой схемой доходит до попытки открыть', () async {
      // В тестовой среде плагина нет, поэтому попытка кончается ложью, а не
      // исключением: проверяем именно то, что обёртка не бросает наружу.
      await expectLater(
        safeLaunchString('https://togetherly.day'),
        completion(isFalse),
      );
      await expectLater(
        safeLaunchString('mailto:support@togetherly.day'),
        completion(isFalse),
      );
    });
  });

  test('в lib/ не осталось голых вызовов launchUrl', () {
    final offenders = <String>[];
    final bare = RegExp(r'(?<!safe)(?<![\w])launchUrl\(');
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      // Сама обёртка — единственное место, где голый вызов уместен.
      if (file.path.endsWith('utils/safe_launch.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (bare.hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'звать надо safeLaunchUrl:\n${offenders.join('\n')}',
    );
  });
}
