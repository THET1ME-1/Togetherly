// Живой мазок партнёра: приросты вместо целой линии.
//
// До 18.08.2026 в канал `draw:<группа>` каждые 150 мс уходил ВЕСЬ мазок со
// всеми точками: сообщение росло вместе с линией, а партнёр видел движение
// ступеньками по 150 мс. Теперь между ключевыми кадрами идут приросты по 40 мс,
// а ключевой кадр остаётся ради сборок постарше и ради потерянных пакетов.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/draw_stroke.dart';
import 'package:love_app/models/live_stroke_wire.dart';

void main() {
  const meta = LiveStrokeMeta(
    colorValue: 0xFF112233,
    strokeWidth: 6.5,
    isEraser: false,
    isFilledShape: false,
    shapeType: null,
  );

  List<DrawPoint> pts(int n, {double base = 0}) =>
      List.generate(n, (i) => DrawPoint(base + i * 0.01, base + i * 0.02));

  group('сборка пакетов', () {
    test('прирост несёт только новые точки', () {
      final all = pts(5);
      final packet = LiveStrokeWire.increment(
        sid: 's1',
        seq: 3,
        from: 3,
        points: all.sublist(3),
        meta: meta,
      );
      expect(packet['sid'], 's1');
      expect(packet['from'], 3);
      expect((packet['pts'] as List).length, 2);
      expect(packet['points'], isNull,
          reason: 'полный список в приросте — это и есть прежняя тяжесть');
    });

    test('ключевой кадр несёт всю линию — его читают старые сборки', () {
      final packet = LiveStrokeWire.keyframe(
        sid: 's1',
        seq: 4,
        points: pts(5),
        meta: meta,
      );
      expect((packet['points'] as List).length, 5);
      expect(packet['colorValue'], 0xFF112233);
      expect(packet['strokeWidth'], 6.5);
    });

    test('финал помечен и несёт номер в порядке рисования', () {
      final packet = LiveStrokeWire.done(
        sid: 's1',
        seq: 9,
        points: pts(3),
        meta: meta,
        orderIndex: 42,
      );
      expect(packet['done'], isTrue);
      expect(packet['orderIndex'], 42);
      expect((packet['points'] as List).length, 3);
    });
  });

  group('сборщик на стороне партнёра', () {
    test('склеивает приросты в одну линию', () {
      final a = LiveStrokeAssembler();
      a.accept(LiveStrokeWire.keyframe(
          sid: 's1', seq: 0, points: pts(2), meta: meta));
      a.accept(LiveStrokeWire.increment(
          sid: 's1', seq: 1, from: 2, points: pts(4).sublist(2), meta: meta));
      expect(a.points.length, 4);
      expect(a.strokeId, 's1');
    });

    test('пакет не по порядку не рвёт линию — ждём ключевой кадр', () {
      final a = LiveStrokeAssembler();
      a.accept(LiveStrokeWire.keyframe(
          sid: 's1', seq: 0, points: pts(2), meta: meta));
      // Прирост с дырой: точек 2, а пакет начинается с пятой.
      a.accept(LiveStrokeWire.increment(
          sid: 's1', seq: 5, from: 5, points: pts(6).sublist(5), meta: meta));
      expect(a.points.length, 2, reason: 'дыру не заполняем выдуманными точками');

      a.accept(LiveStrokeWire.keyframe(
          sid: 's1', seq: 6, points: pts(6), meta: meta));
      expect(a.points.length, 6, reason: 'ключевой кадр чинит потерю');
    });

    test('новый мазок сбрасывает прежний', () {
      final a = LiveStrokeAssembler();
      a.accept(LiveStrokeWire.keyframe(
          sid: 's1', seq: 0, points: pts(4), meta: meta));
      a.accept(LiveStrokeWire.keyframe(
          sid: 's2', seq: 0, points: pts(1), meta: meta));
      expect(a.strokeId, 's2');
      expect(a.points.length, 1);
    });

    test('старый формат без sid читается как раньше', () {
      final a = LiveStrokeAssembler();
      final old = {
        'userId': 'u1',
        'colorValue': 0xFF000000,
        'strokeWidth': 4.0,
        'isEraser': false,
        'isFilledShape': false,
        'points': [
          {'x': 0.1, 'y': 0.2},
          {'x': 0.3, 'y': 0.4},
        ],
        'ts': 1,
      };
      a.accept(old);
      expect(a.points.length, 2);
      expect(a.done, isFalse);
    });

    test('финал отдаёт готовый штрих партнёра', () {
      final a = LiveStrokeAssembler();
      a.accept(LiveStrokeWire.keyframe(
          sid: 's1', seq: 0, points: pts(3), meta: meta));
      a.accept(LiveStrokeWire.done(
          sid: 's1', seq: 1, points: pts(4), meta: meta, orderIndex: 7));
      expect(a.done, isTrue);
      final stroke = a.buildStroke('partner-uid');
      expect(stroke, isNotNull);
      expect(stroke!.points.length, 4);
      expect(stroke.orderIndex, 7);
      expect(stroke.id, 'live_s1',
          reason: 'по этому id запись из базы заменит оптимистичный штрих');
      expect(stroke.colorValue, 0xFF112233);
    });

    test('без финала штрих не строится', () {
      final a = LiveStrokeAssembler();
      a.accept(LiveStrokeWire.keyframe(
          sid: 's1', seq: 0, points: pts(3), meta: meta));
      expect(a.buildStroke('partner-uid'), isNull);
    });
  });
}
