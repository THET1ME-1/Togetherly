// Какой лист раскраски предложить вместо нового.
//
// Живой случай 13.09.2026, пара rc3eb70972c9644: Арсений выбрал «Кафе» и
// получил canvas_1789307787542, Дарья через 17 секунд выбрала то же «Кафе» и
// получила СВОЙ canvas_1789307804408. Каждый красил половину своего листа,
// вторая половина у обоих осталась пустой. За неделю так разошлись 319 пар из
// 1238. Правило ниже решает, в какой уже начатый лист вести человека.

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/coloring_join.dart';

void main() {
  const me = 'mx1snkelc3c8hie';
  const partner = 'kofli0u2x99ccxz';
  const members = [me, partner];

  final arseniyStart = DateTime.fromMillisecondsSinceEpoch(1789307787542);
  final dariaPick = arseniyStart.add(const Duration(seconds: 17));

  ColoringSheet sheet(
    String canvasId, {
    String picture = 'cafe',
    DateTime? at,
    Map<String, bool> done = const {},
  }) =>
      ColoringSheet(
        canvasId: canvasId,
        pictureId: picture,
        lastActivity: at ?? arseniyStart,
        done: done,
      );

  ColoringSheet? pick(
    List<ColoringSheet> sheets, {
    String picture = 'cafe',
    Set<String>? listed,
    DateTime? now,
  }) =>
      coloringSheetToJoin(
        sheets,
        pictureId: picture,
        members: members,
        listed: listed ?? {for (final s in sheets) s.canvasId},
        now: now ?? dariaPick,
      );

  group('coloringSheetToJoin', () {
    test('лист партнёра, начатый 17 секунд назад, — туда и ведём', () {
      final got = pick([sheet('canvas_1789307787542')]);
      expect(got?.canvasId, 'canvas_1789307787542');
    });

    test('другая картинка не годится', () {
      expect(pick([sheet('canvas_1', picture: 'castle')]), isNull);
    });

    test('лист старше окна не предлагаем', () {
      final old = sheet('canvas_1',
          at: dariaPick.subtract(coloringJoinWindow + const Duration(minutes: 1)));
      expect(pick([old]), isNull);
    });

    test('лист внутри окна предлагаем', () {
      final recent = sheet('canvas_1',
          at: dariaPick.subtract(coloringJoinWindow - const Duration(minutes: 1)));
      expect(pick([recent])?.canvasId, 'canvas_1');
    });

    test('оба нажали «Готово» — раскраска закончена, заводим новую', () {
      final finished = sheet('canvas_1', done: {me: true, partner: true});
      expect(pick([finished]), isNull);
    });

    test('готов только один — вторая половина ещё ждёт', () {
      final half = sheet('canvas_1', done: {partner: true});
      expect(pick([half])?.canvasId, 'canvas_1');
    });

    test('«false» в карте готовности готовностью не считается', () {
      final undone = sheet('canvas_1', done: {me: true, partner: false});
      expect(pick([undone])?.canvasId, 'canvas_1');
    });

    test('удалённый из каталога лист не воскрешаем', () {
      // canvas_meta после удаления холста остаётся: удаление чистит только
      // каталог. Такой лист в галерее уже не виден.
      expect(pick([sheet('canvas_1')], listed: {}), isNull);
    });

    test('из нескольких берём самый свежий', () {
      final got = pick([
        sheet('canvas_old', at: arseniyStart),
        sheet('canvas_new', at: arseniyStart.add(const Duration(seconds: 5))),
        sheet('canvas_mid', at: arseniyStart.add(const Duration(seconds: 2))),
      ]);
      expect(got?.canvasId, 'canvas_new');
    });

    test('лист из будущего (часы разъехались) всё равно подходит', () {
      final ahead = sheet('canvas_1',
          at: dariaPick.add(const Duration(minutes: 3)));
      expect(pick([ahead])?.canvasId, 'canvas_1');
    });

    test('пустой список — новый лист', () {
      expect(pick(const []), isNull);
    });
  });

  group('ColoringSheet.fromMetaRow', () {
    test('строка canvas_meta из hotpath', () {
      final s = ColoringSheet.fromMetaRow({
        'canvas_id': 'canvas_1789307787542',
        'coloring_id': 'cafe',
        'updated_at': '2026-09-22 17:28:17.325524Z',
        'coloring_done': {partner: true},
      });
      expect(s, isNotNull);
      expect(s!.canvasId, 'canvas_1789307787542');
      expect(s.pictureId, 'cafe');
      expect(s.done, {partner: true});
      expect(s.lastActivity.toUtc(), DateTime.utc(2026, 9, 22, 17, 28, 17, 325, 524));
    });

    test('карта готовности строкой JSON тоже читается', () {
      final s = ColoringSheet.fromMetaRow({
        'canvas_id': 'canvas_1',
        'coloring_id': 'cafe',
        'updated_at': '2026-09-22 17:28:17Z',
        'coloring_done': '{"$me": true}',
      });
      expect(s!.done, {me: true});
    });

    test('без updated_at время берём из id холста', () {
      final s = ColoringSheet.fromMetaRow({
        'canvas_id': 'canvas_1789307787542',
        'coloring_id': 'cafe',
        'updated_at': '',
      });
      expect(s!.lastActivity, DateTime.fromMillisecondsSinceEpoch(1789307787542));
    });

    test('холст без раскраски — не кандидат', () {
      expect(
          ColoringSheet.fromMetaRow({
            'canvas_id': 'canvas_1',
            'coloring_id': '',
            'updated_at': '2026-09-22 17:28:17Z',
          }),
          isNull);
    });
  });
}
