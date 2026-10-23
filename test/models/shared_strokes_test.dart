import 'package:flutter_test/flutter_test.dart';

import 'package:love_app/models/draw_stroke.dart';
import 'package:love_app/models/shared_strokes.dart';
import 'package:love_app/models/stroke_record_id.dart';

/// Книга общего холста: что мы нарисовали, что подтвердил сервер, что убрали
/// (TOG-12, 22.10.2026). Жалоба: «ты че то нарисовал а оно удалилось или
/// наоборот какая то фигня появилась которую ты стер давно».
DrawStroke _line(String clientId, {String user = 'me', int order = 1}) =>
    DrawStroke(
      id: strokeRecordId('g', 'c', clientId),
      clientId: clientId,
      userId: user,
      colorValue: 0xFF112233,
      strokeWidth: 4,
      points: const [DrawPoint(0.1, 0.1), DrawPoint(0.3, 0.2)],
      orderIndex: order,
    );

/// Запись с id, выданным сервером, — так лежат мазки старых сборок.
DrawStroke _record(String id, DrawStroke base) => DrawStroke(
      id: id,
      clientId: base.clientId,
      userId: base.userId,
      colorValue: base.colorValue,
      strokeWidth: base.strokeWidth,
      points: base.points,
      orderIndex: base.orderIndex,
      imageUrl: base.imageUrl,
      imageX: base.imageX,
      imageY: base.imageY,
      imageWidth: base.imageWidth,
      imageHeight: base.imageHeight,
      imageRotation: base.imageRotation,
    );

DrawStroke _fill(String id, {int order = 1, String url = 'pb://media/m1/f.webp'}) =>
    DrawStroke(
      id: id,
      userId: 'me',
      colorValue: 0xFFFF0000,
      strokeWidth: 0,
      points: const [],
      orderIndex: order,
      imageUrl: url,
      imageX: 0.4,
      imageY: 0.6,
      imageWidth: 0.1,
      imageHeight: 0.12,
      imageRotation: 0,
    );

bool _never(DrawStroke a, DrawStroke b) => false;

void main() {
  group('отмена своего мазка', () {
    test('сервер записал мазок, эхо ещё не пришло: отмена удаляет запись', () {
      final book = SharedStrokes();
      final a = _line('local_1_1_me');
      book.addPending(a);
      expect(book.createSucceeded(a.id), isFalse);

      final plan = book.remove(a.id);

      expect(plan.records, contains(a.id),
          reason: 'Запись уже есть на сервере, её некому удалить, кроме нас');
      book.applySnapshot([a], looksSame: _never);
      expect(book.all.map((s) => s.id), isNot(contains(a.id)),
          reason: 'Эхо записи не возвращает отменённый мазок');
    });

    test('отменили до ответа сервера: запись удаляется, когда он ответит', () {
      final book = SharedStrokes();
      final a = _line('local_1_2_me');
      book.addPending(a);
      final plan = book.remove(a.id);
      expect(plan.cancelQueued, isTrue);

      expect(book.createSucceeded(a.id), isTrue,
          reason: 'Сервер ответил после отмены — запись надо удалить');
    });

    test('отказ добавления у отменённого мазка не отдаётся очереди', () {
      final book = SharedStrokes();
      final a = _line('local_1_3_me');
      book.addPending(a);
      book.remove(a.id);

      expect(book.createFailed(a.id), isFalse,
          reason: 'Иначе очередь пришлёт отменённое позже');
    });

    test('неотменённый мазок при отказе уходит в очередь', () {
      final book = SharedStrokes();
      final a = _line('local_1_4_me');
      book.addPending(a);
      expect(book.createFailed(a.id), isTrue);
    });

    test('добавление стояло в очереди: удаление тоже идёт очередью', () {
      final book = SharedStrokes();
      final a = _line('local_1_5_me');
      book.addPending(a);
      book.createFailed(a.id);

      final plan = book.remove(a.id);

      expect(plan.viaQueue, isTrue,
          reason: 'Добавление может быть в полёте — удаление встанет за ним');
      expect(plan.cancelQueued, isTrue);
      expect(plan.records, contains(a.id));
    });
  });

  group('снимки сервера', () {
    test('свой мазок подтверждается по id записи', () {
      final book = SharedStrokes();
      final a = _line('local_2_1_me');
      book.addPending(a);
      book.applySnapshot([a], looksSame: _never);

      expect(book.pending, isEmpty);
      expect(book.all, hasLength(1));
    });

    test('старый снимок не возвращает убранный мазок', () {
      final book = SharedStrokes();
      final a = _line('local_2_2_me', order: 1);
      final b = _line('local_2_3_me', order: 2);
      book.applySnapshot([a, b], looksSame: _never);

      book.remove(a.id);
      // Партнёр нарисовал своё, снимок пришёл раньше события удаления.
      book.applySnapshot([a, b], looksSame: _never);

      expect(book.all.map((s) => s.id), [b.id]);
    });

    test('копии одного мазка видны один раз и убираются все вместе', () {
      final book = SharedStrokes();
      final base = _line('local_2_4_me', order: 3);
      final copies = [
        _record('r000000000000a1', base),
        _record('r000000000000a2', base),
        _record('r000000000000a3', base),
      ];
      final other = _line('local_2_5_me', order: 4);
      book.applySnapshot([...copies, other], looksSame: _never);

      expect(book.all, hasLength(2), reason: 'Двенадцать копий — один мазок');
      final shown = book.all.firstWhere((s) => s.clientId == base.clientId);
      final plan = book.remove(shown.id);

      expect(plan.records.toSet(), copies.map((s) => s.id).toSet());
      book.applySnapshot([...copies, other], looksSame: _never);
      expect(book.all.map((s) => s.id), [other.id]);
    });

    test('копии заливки — одна картинка на одном месте — сворачиваются', () {
      final book = SharedStrokes();
      final f1 = _fill('rfill0000000001', order: 7);
      final f2 = _fill('rfill0000000002', order: 109);
      final elsewhere = DrawStroke(
        id: 'rfill0000000003',
        userId: 'me',
        colorValue: 0xFFFF0000,
        strokeWidth: 0,
        points: const [],
        orderIndex: 8,
        imageUrl: 'pb://media/m1/f.webp',
        imageX: 0.9,
        imageY: 0.6,
        imageWidth: 0.1,
        imageHeight: 0.12,
        imageRotation: 0,
      );
      book.applySnapshot([f1, elsewhere, f2], looksSame: _never);

      expect(book.all, hasLength(2));
      final plan = book.remove(f1.id);
      expect(plan.records.toSet(), {f1.id, f2.id});
      expect(book.all.map((s) => s.id), [elsewhere.id]);
    });

    test('правка штриха с копиями снимает копии', () {
      // Двигаем заливку, у которой на сервере лежит вторая копия. Правка
      // уходит в одну запись, и копия на прежнем месте проступила бы.
      final book = SharedStrokes();
      final f1 = _fill('rfill0000000001', order: 7);
      final f2 = _fill('rfill0000000002', order: 109);
      book.applySnapshot([f1, f2], looksSame: _never);

      expect(book.dropCopies(f1.id), [f2.id]);
      expect(book.dropCopies(f1.id), isEmpty, reason: 'Копии сняты один раз');
      book.applySnapshot([f1, f2], looksSame: _never);
      expect(book.all.map((s) => s.id), [f1.id],
          reason: 'Снятая копия не возвращается старым снимком');
    });

    test('ожидающий мазок без id записи сверяется по clientId', () {
      final book = SharedStrokes();
      final local = DrawStroke(
        id: 'local_2_6_me',
        clientId: 'local_2_6_me',
        userId: 'me',
        colorValue: 1,
        strokeWidth: 2,
        points: const [DrawPoint(0, 0), DrawPoint(1, 1)],
        orderIndex: 5,
      );
      book.addPending(local);
      final renames = book.applySnapshot(
          [_record('rserver00000001', local)],
          looksSame: _never);

      expect(renames, {'local_2_6_me': 'rserver00000001'});
      expect(book.pending, isEmpty);
    });
  });

  group('мазки партнёра из живого канала', () {
    test('мазок без записи гаснет через 30 секунд', () {
      final book = SharedStrokes();
      final t0 = DateTime(2026, 10, 22, 20);
      final p = _line('local_3_1_pa', user: 'partner');
      book.addPartnerCommitted(p.clientId!, p, now: t0);

      expect(book.expirePartner(t0.add(const Duration(seconds: 29))), isFalse);
      expect(book.all, hasLength(1));
      expect(book.expirePartner(t0.add(const Duration(seconds: 31))), isTrue,
          reason: 'Партнёр отменил мазок до записи — у меня он не висит');
      expect(book.all, isEmpty);
    });

    test('пришла запись — живая копия снимается', () {
      final book = SharedStrokes();
      final p = _line('local_3_2_pa', user: 'partner');
      book.addPartnerCommitted(p.clientId!, p, now: DateTime(2026));
      book.applySnapshot([p], looksSame: _never);
      expect(book.all, hasLength(1));
      expect(book.partnerCommitted, isEmpty);
    });

    test('номер порядка учитывает мазки партнёра из живого канала', () {
      final book = SharedStrokes();
      book.applySnapshot([_line('local_3_3_me', order: 4)], looksSame: _never);
      final p = _line('local_3_4_pa', user: 'partner', order: 40);
      book.addPartnerCommitted(p.clientId!, p, now: DateTime(2026));
      expect(book.maxOrderIndex, 40,
          reason: 'Ластик поверх свежего мазка партнёра обязан лечь выше него');
    });
  });

  test('очистка холста забывает всё', () {
    final book = SharedStrokes();
    final a = _line('local_4_1_me');
    book.addPending(a);
    book.remove(a.id);
    book.reset();
    expect(book.all, isEmpty);
    expect(book.createSucceeded(a.id), isFalse,
        reason: 'После очистки отметки об отмене не живут');
  });
}
