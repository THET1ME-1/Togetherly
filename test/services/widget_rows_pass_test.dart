// Один фоновый проход читает записи виджетов пары один раз.
//
// TOG-90 (11.11.2026), отзыв Google Play: «91% батареи». Замер на сервере за
// две минуты: 3240 фоновых проходов от 3203 спящих телефонов, 48% всех
// запросов с токеном. В каждом проходе `widget_data` одной и той же пары
// читалась около пяти раз: парный виджет, настроение (две записи отдельно),
// заметка и фото партнёра спрашивали сервер каждый сам. Телефон держал
// радио включённым на пять запросов там, где хватает одного.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/widget_rows_pass.dart';
import 'package:pocketbase/pocketbase.dart';

RecordModel row(String uid) => RecordModel({'id': 'r$uid', 'user_uid': uid, 'group_id': 'g'});

void main() {
  test('сколько бы частей прохода ни спросили пару, запрос один', () async {
    var loads = 0;
    final pass = WidgetRowsPass((groupId) async {
      loads++;
      return [row('me'), row('partner')];
    });

    final all = await pass.rows('g');
    final mine = await pass.rowOf('g', 'me');
    final theirs = await pass.rowOf('g', 'partner');
    await pass.rows('g');

    expect(all, hasLength(2));
    expect(mine?.data['user_uid'], 'me');
    expect(theirs?.data['user_uid'], 'partner');
    expect(loads, 1, reason: 'части прохода снова ходят на сервер каждая сама');
  });

  test('части, спросившие разом, ждут один и тот же запрос', () async {
    var loads = 0;
    final pass = WidgetRowsPass((groupId) async {
      loads++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return [row('me')];
    });

    await Future.wait([pass.rows('g'), pass.rowOf('g', 'me'), pass.rows('g')]);

    expect(loads, 1);
  });

  test('у каждой пары свой запрос', () async {
    final asked = <String>[];
    final pass = WidgetRowsPass((groupId) async {
      asked.add(groupId);
      return const [];
    });

    await pass.rows('g1');
    await pass.rows('g2');
    await pass.rows('g1');

    expect(asked, ['g1', 'g2']);
  });

  test('записи человека нет — null, а не чужая запись', () async {
    final pass = WidgetRowsPass((groupId) async => [row('partner')]);

    expect(await pass.rowOf('g', 'me'), isNull);
    expect(await pass.rowOf('g', ''), isNull);
  });

  // «Не дозвонились» — не «записей нет»: пустой ответ стёр бы заметку и
  // настроение с рабочего стола. Сбой получает каждая часть прохода и
  // пропускает свой виджет, прежние данные остаются.
  test('сбой чтения доходит до каждой части прохода, повторов нет', () async {
    var loads = 0;
    final pass = WidgetRowsPass((groupId) async {
      loads++;
      throw StateError('нет сети');
    });

    await expectLater(pass.rows('g'), throwsStateError);
    await expectLater(pass.rowOf('g', 'me'), throwsStateError);
    expect(loads, 1);
  });

  // Сам проход на компьютере не запустить: он работает только на телефоне.
  // Поэтому сторож смотрит в исходник: проход открывает общие записи, а его
  // части берут их оттуда, а не ходят на сервер сами.
  group('фоновый проход в HomeWidgetService', () {
    final source = File('lib/services/home_widget_service.dart').readAsStringSync();

    String bodyOf(String signature) {
      final start = source.indexOf(signature);
      if (start < 0) throw StateError('пропал метод: $signature');
      final next = source.indexOf('\n  }\n', start);
      return source.substring(start, next);
    }

    test('открывает общие записи и закрывает их после себя', () {
      final body = bodyOf('Future<void> backgroundRefreshAll(');
      expect(body, contains('WidgetRowsPass(PbDataService().loadWidgetsForGroupOrThrow)'));
      expect(body, contains('_pass = pass;'));
      expect(body, contains('if (identical(_pass, pass)) _pass = null;'));
    });

    test('части прохода не читают widget_data мимо общих записей', () {
      for (final signature in const [
        'Future<WidgetData?> _readWidgetData(',
        'Future<void> refreshLoveWidgetFromServer(',
        'Future<void> _syncNoteFromCloud(',
        'Future<void> _refreshIosPhotoWidgetsFromServer(',
      ]) {
        final body = bodyOf(signature);
        expect(body, isNot(contains('PbDataService().loadWidget')),
            reason: '$signature снова ходит на сервер сам');
        expect(body, contains('_widgetRow'), reason: '$signature не берёт общие записи');
      }
    });
  });
}
