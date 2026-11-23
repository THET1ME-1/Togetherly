import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/utils/server_message.dart';
import 'package:love_app/utils/widget_dates.dart';

/// Отзыв 23.11.2026: «текст иногда появляется на белорусском, хотя у меня
/// английский». Белорусского в приложении нет; по-русски шли дата начала пары
/// в виджете «Вместе», отказы сервера при вводе кода, уведомления, советы и
/// всё, что Android и iPhone берут не из приложения, а из своих ресурсов.
void main() {
  tearDown(() => LocaleService.instance.setLanguage(AppLanguage.en));

  group('дата начала пары в виджетах', () {
    final start = DateTime(2025, 11, 1);

    test('английское приложение пишет дату по-английски', () {
      LocaleService.instance.setLanguage(AppLanguage.en);
      expect(widgetSinceLong(start), 'Since Nov 1, 2025');
      expect(widgetDateShort(start), 'Nov 1');
      expect(widgetSince('01.11.2025'), 'since 01.11.2025');
    });

    test('русское — как раньше', () {
      LocaleService.instance.setLanguage(AppLanguage.ru);
      expect(widgetSinceLong(start), 'С 1 ноября 2025');
      expect(widgetDateShort(start), '1 ноября');
    });

    test('остальные языки без единой русской буквы', () {
      final cyrillicRu = RegExp('[ыэъё]|ноябр');
      for (final lang in AppLanguage.values) {
        if (lang == AppLanguage.ru) continue;
        LocaleService.instance.setLanguage(lang);
        final text = '${widgetSinceLong(start)} ${widgetDateShort(start)}';
        expect(cyrillicRu.hasMatch(text), isFalse, reason: '${lang.code}: $text');
        expect(text, contains('2025'), reason: lang.code);
      }
    });

    test('русских месяцев в коде виджетов не осталось', () {
      for (final path in [
        'lib/services/home_widget_service.dart',
        'lib/screens/widget_screen.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src.contains("'С \${"), isFalse, reason: path);
      }
      final sync = File('lib/services/catalog_widget_sync.dart').readAsStringSync();
      expect(sync, isNot(contains("'С \${_dayMonth")));
      expect(sync, isNot(contains("'с \${_dayMonth")));
    });
  });

  group('отказы сервера при вводе кода', () {
    test('известный отказ переводится', () {
      LocaleService.instance.setLanguage(AppLanguage.en);
      expect(
        serverMessageText('Группа заполнена', fallback: 'x'),
        'This pair is already full',
      );
      expect(
        serverMessageText(
            'Код не найден. Пусть партнёр нажмёт «Новый код» и продиктует заново',
            fallback: 'x'),
        startsWith('Code not found.'),
      );
    });

    test('украинцу — по-украински', () {
      LocaleService.instance.setLanguage(AppLanguage.uk);
      expect(serverMessageText('Код не найден', fallback: 'x'), 'Код не знайдено');
    });

    test('незнакомый русский текст заменяется общей фразой', () {
      LocaleService.instance.setLanguage(AppLanguage.en);
      expect(serverMessageText('Что-то новое на сервере', fallback: 'Oops'), 'Oops');
      expect(serverMessageText('Connected!', fallback: 'Oops'), 'Connected!');
      expect(serverMessageText('', fallback: 'Oops'), 'Oops');
    });

    test('русскому приложению текст сервера идёт как есть', () {
      LocaleService.instance.setLanguage(AppLanguage.ru);
      expect(serverMessageText('Код не найден', fallback: 'x'), 'Код не найден');
    });

    test('каждый русский отказ сервера есть в таблице', () {
      // Тексты `deny(…, "…")` и `message: "…"` маршрутов пары. Новый отказ
      // по-русски без строки в `kServerMessagesEn` показался бы английскому
      // приложению общей фразой вместо причины.
      final sources = [
        'pocketbase/pb_hooks/invite.pb.js',
        'pocketbase/pb_hooks/waiting.pb.js',
      ].map((p) => File(p).readAsStringSync()).join('\n');
      final hotpath = File('pocketbase/hotpath/hotpath.py').readAsStringSync();
      final found = <String>{
        for (final m in RegExp(r'deny\(\s*\d+,\s*"([^"]+)"').allMatches(sources)) m[1]!,
        for (final m in RegExp(r'message: "([^"]+)"').allMatches(sources)) m[1]!,
        for (final m in RegExp(r'"message": "([^"]+)"').allMatches(hotpath)) m[1]!,
      }.where((t) => RegExp('[А-Яа-я]').hasMatch(t));
      expect(found, isNotEmpty);
      for (final text in found) {
        expect(kServerMessagesEn.containsKey(text), isTrue, reason: text);
      }
    });
  });

  group('ресурсы Android', () {
    const res = 'android/app/src/main/res';

    test('по умолчанию английский, русский в своей папке', () {
      final cyrillic = RegExp('[А-Яа-яЁё]');
      for (final f in Directory('$res/values').listSync().whereType<File>()) {
        final body = f
            .readAsStringSync()
            .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
        expect(cyrillic.hasMatch(body), isFalse, reason: f.path);
      }
      expect(File('$res/values-ru/strings.xml').readAsStringSync(),
          contains('Дни вместе и аватары пары'));
    });

    test('копии русского для be, kk, ky совпадают с values-ru', () {
      for (final name in ['strings.xml', 'widget_strings.xml']) {
        final ru = File('$res/values-ru/$name').readAsStringSync();
        for (final lang in ['be', 'kk', 'ky']) {
          expect(File('$res/values-$lang/$name').readAsStringSync(), ru,
              reason: 'values-$lang/$name');
        }
      }
    });

    test('у каждого языка те же ключи, что по умолчанию', () {
      Set<String> keys(String dir) => {
            for (final f in Directory(dir).listSync().whereType<File>())
              if (f.path.endsWith('.xml'))
                for (final m in RegExp(r'<string name="([^"]+)"')
                    .allMatches(f.readAsStringSync()))
                  m[1]!,
          };
      final base = keys('$res/values');
      for (final lang in ['ru', 'be', 'kk', 'ky', 'en']) {
        expect(keys('$res/values-$lang'), base, reason: lang);
      }
    });
  });

  group('галерея виджетов iPhone', () {
    const dir = 'ios/TogetherlyWidget';
    final langs = ['en', 'ru', 'uk', 'de', 'es', 'fr', 'it', 'pt', 'zh-Hans', 'be', 'kk', 'ky'];

    Map<String, String> table(String lang) => {
          for (final m in RegExp(r'^"([^"]*)" = "([^"]*)";$', multiLine: true)
              .allMatches(File('$dir/$lang.lproj/Localizable.strings').readAsStringSync()))
            m[1]!: m[2]!,
        };

    test('каждое название и описание виджета переведено на все языки', () {
      final literals = <String>{
        for (final f in Directory(dir).listSync().whereType<File>())
          if (f.path.endsWith('.swift'))
            for (final m in RegExp(r'\.(?:configurationDisplayName|description)\("([^"]*)"\)')
                .allMatches(f.readAsStringSync()))
              m[1]!,
      };
      expect(literals.length, greaterThan(40));
      for (final lang in langs) {
        final t = table(lang);
        for (final s in literals) {
          expect(t[s], isNotNull, reason: '$lang: $s');
          expect(t[s], isNotEmpty, reason: '$lang: $s');
        }
        expect(t.keys.toSet(), literals, reason: '$lang: лишние строки');
      }
    });

    test('английский и европейские — без кириллицы', () {
      for (final lang in ['en', 'de', 'es', 'fr', 'it', 'pt', 'zh-Hans']) {
        for (final v in table(lang).values) {
          expect(RegExp('[А-Яа-я]').hasMatch(v), isFalse, reason: '$lang: $v');
        }
      }
    });

    test('файлы подключены к расширению в проекте', () {
      final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      expect(pbx, contains('Localizable.strings in Resources'));
      for (final lang in langs) {
        expect(pbx, contains('path = ${lang.contains('-') ? '"$lang.lproj/Localizable.strings"' : '$lang.lproj/Localizable.strings'};'),
            reason: lang);
      }
    });
  });
}
