import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/l10n/dict/memory_lane_feed.dart';
import 'package:love_app/models/daily_task.dart';
import 'package:love_app/models/memory.dart';

/// Ответ на задание дня должен быть виден в ленте.
///
/// Просьба из поддержки 22.08.2026: «добавьте ответы на задания дня, чтобы в
/// ленте воспоминаний отмечалось, что это ответ на задание». До этого id
/// задания доезжал только до `DailyTaskService` — закрыть строку на главной, —
/// а в самой записи не оставалось ничего, и через день никто уже не помнил, на
/// какой вопрос отвечало это фото.
void main() {
  Memory _memory({String? taskId}) => Memory(
        id: 'm1',
        groupId: 'g1',
        authorUid: 'u1',
        authorName: 'Лера',
        type: MemoryType.photo,
        createdAt: DateTime(2026, 8, 22, 12, 0),
        dailyTaskId: taskId,
      );

  test('id задания переживает дорогу до сервера и обратно', () {
    final json = _memory(taskId: 'text_admire').toJson();
    expect(json['dailyTaskId'], 'text_admire');
    expect(Memory.fromJson(json).dailyTaskId, 'text_admire');
  });

  test('запись без задания остаётся без него', () {
    expect(_memory().toJson()['dailyTaskId'], isNull);
    expect(Memory.fromJson(_memory().toJson()).dailyTaskId, isNull);
  });

  test('прежние записи читаются, поля у них просто нет', () {
    final old = _memory().toJson()..remove('dailyTaskId');
    expect(Memory.fromJson(old).dailyTaskId, isNull);
  });

  test('по id достаётся сам caption задания, с именем партнёра', () {
    final id = DailyTask.all.first.id;
    final caption = dailyTaskTitleOf(id, 'Лера');
    expect(caption, isNotNull);
    expect(caption, isNot(contains('{p}')), reason: 'имя подставлено');
    expect(caption, DailyTask.all.first.title('Лера'));
  });

  test('чужой или пустой id подписи не даёт', () {
    expect(dailyTaskTitleOf('', 'Лера'), isNull);
    expect(dailyTaskTitleOf(null, 'Лера'), isNull);
    expect(dailyTaskTitleOf('такого-задания-нет', 'Лера'), isNull);
  });

  test('лента показывает подпись у каждой карточки, а не у одного типа', () {
    final feed = File('lib/screens/memory_lane_screen.dart').readAsStringSync();
    final header = RegExp(r'Widget _cardHeader\(([\s\S]*?)\n  \}\n')
        .firstMatch(feed);
    expect(header, isNotNull, reason: 'шапка карточки на месте');
    expect(header!.group(1), contains('_dailyTaskNote'),
        reason: 'подпись живёт в общей шапке — иначе её увидит только один '
            'тип записи из шести');
    expect(feed, contains('dailyTaskTitleOf'),
        reason: 'текст задания берётся из каталога, а не пишется заново');
  });

  test('подпись переведена на все семь языков', () {
    final row = memoryLaneFeedStrings['memoryDailyTaskBadge'];
    expect(row, isNotNull, reason: 'ключ подписи заведён');
    for (final lang in ['ru', 'en', 'de', 'fr', 'es', 'it', 'pt']) {
      expect(row![lang], isNotNull, reason: 'нет перевода на $lang');
      expect(row[lang]!.trim(), isNotEmpty, reason: 'пустой перевод на $lang');
    }
  });
}
