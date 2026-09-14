import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Запись пары живёт в hotpath (Postgres), и поле, которого нет в его карте
/// `COLLECTIONS["groups"]`, выбрасывается МОЛЧА: ответ 200, запись без поля.
///
/// Так общий фон чата не сохранялся ни разу (жалоба 14.09.2026 с записью
/// экрана: «свои обои не ставятся, несколько раз пробовала»): приложение
/// писало `chat_background`, сервер отвечал успехом и забывал ссылку.
void main() {
  final hotpath = File('pocketbase/hotpath/hotpath.py').readAsStringSync();
  final groupsBlock =
      hotpath.split('"groups": {')[1].split('"sortable"')[0];

  Set<String> keysWrittenToGroups() {
    final keys = <String>{};
    final call = RegExp(r'updateGroupFields\([^{;]*\{([^}]*)\}');
    final key = RegExp(r"'([a-z_]+)'\s*:");
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      for (final m in call.allMatches(f.readAsStringSync())) {
        for (final k in key.allMatches(m.group(1)!)) {
          keys.add(k.group(1)!);
        }
      }
    }
    return keys;
  }

  test('каждое поле, которое приложение пишет в пару, знает hotpath', () {
    final keys = keysWrittenToGroups();
    expect(keys, contains('chat_background'),
        reason: 'сканер разучился находить вызовы updateGroupFields');
    for (final k in keys) {
      expect(groupsBlock, contains('"$k"'),
          reason: 'hotpath выбросит $k молча — добавь в COLLECTIONS и в Postgres');
    }
  });

  test('общий фон чата заведён миграцией Postgres', () {
    final sql =
        File('pocketbase/hotpath/chat_background.sql').readAsStringSync();
    expect(sql, contains('chat_background'));
  });

  test('фона нет в SQLite, поэтому зеркало его не трогает', () {
    // Зеркало пишет каждую колонку карты в SQLite PocketBase, а там такой
    // колонки нет: без исключения зеркало падало бы на каждой паре, и вместе
    // с ним закрывалась бы запись у живых людей.
    final skip = RegExp(r'НЕ_ЗЕРКАЛИМ = \{([^}]*)\}').firstMatch(hotpath);
    expect(skip, isNotNull);
    expect(skip!.group(1), contains('"chat_background"'));
    final mirror = hotpath.split('ЗЕРКАЛО_КОЛОНКИ = ')[1].split('\n\n')[0];
    expect(mirror, contains('not in НЕ_ЗЕРКАЛИМ'));
  });

  test('ставить фон — значит дождаться ответа записи', () {
    final src = File('lib/services/chat_service.dart').readAsStringSync();
    final body = src
        .split('Future<bool> setSharedBackground(')[1]
        .split('\n  }\n')[0];
    expect(body, contains('return await PbDataService().updateGroupFields'),
        reason: 'отказ записи обязан дойти до экрана, а не стать «Фон поставлен»');
  });

  test('чат читает общий фон и без своего, и рисует pb:// с токеном', () {
    final src = File('lib/screens/chat_screen.dart').readAsStringSync();
    final load = src
        .split('Future<void> _loadBackground() async {')[1]
        .split('\n  }\n')[0];
    final ifLocal = load.indexOf('if (path != null');
    final shared = load.indexOf('sharedBackground(');
    expect(shared, greaterThan(-1));
    expect(load.substring(ifLocal).contains('} else if'), isTrue);
    // Общий фон не должен сидеть внутри ветки «свой файл есть».
    final localBranch =
        load.substring(ifLocal, load.indexOf('} else if', ifLocal));
    expect(localBranch.contains('sharedBackground('), isFalse,
        reason: 'без своего фона общий не загружался вовсе');

    expect(src.contains(RegExp(r'Image\.network\(\s*_sharedBgUrl')), isFalse,
        reason: 'ссылка pb:// в Image.network не открывается: экран чёрный');
  });
}
