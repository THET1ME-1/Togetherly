// Раскадровка живого фото: манифест и выбор кадра.
//
// Правило одно на две стороны — Dart считает кадр так же, как нативный код
// виджета. Держим его под тестом, чтобы они не разъехались молча: разъезд виден
// только на устройстве и выглядит как рваный пульс.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/widget_anim_service.dart';

void main() {
  const m = WidgetAnimManifest(
    cols: 6, rows: 3, cell: 300, frames: 18, stepMs: 83, source: 'video',
  );

  group('Разбор манифеста', () {
    test('числа приходят и как int, и как double', () {
      final a = WidgetAnimManifest.tryParse(
          {'cols': 6, 'rows': 3, 'cell': 300, 'frames': 18, 'step_ms': 83});
      final b = WidgetAnimManifest.tryParse(
          {'cols': 6.0, 'rows': 3.0, 'cell': 300.0, 'frames': 18.0, 'step_ms': 83.0});
      expect(a?.frames, 18);
      expect(b?.cell, 300);
    });

    test('мусор и пустые значения отбрасываются', () {
      expect(WidgetAnimManifest.tryParse(null), isNull);
      expect(WidgetAnimManifest.tryParse('нет'), isNull);
      expect(WidgetAnimManifest.tryParse({'cols': 0, 'rows': 3, 'cell': 300}), isNull);
    });

    test('шаг без значения не обнуляется', () {
      // Ноль в шаге означал бы деление на ноль в цикле показа.
      final m = WidgetAnimManifest.tryParse({'cols': 2, 'rows': 2, 'cell': 100, 'step_ms': 0});
      expect(m?.stepMs, 100);
    });
  });

  group('Из чего собираем живое фото', () {
    // Кнопка открывает общий выбор медиа, а не выбор видео: гифка в галерее
    // лежит среди фотографий, и `pickVideo` её не показывал вовсе. Значит
    // отсеивать статичный снимок приходится самим.
    test('видео и анимация подходят', () {
      for (final p in [
        '/tmp/a.mp4', '/tmp/a.MOV', '/tmp/a.m4v', '/tmp/a.webm', '/tmp/a.3gp',
        '/tmp/a.gif', '/tmp/a.GIF', '/tmp/a.webp',
      ]) {
        expect(WidgetAnimService.isSupportedSource(p), isTrue, reason: p);
      }
    });

    test('статичный снимок не подходит', () {
      for (final p in ['/tmp/a.jpg', '/tmp/a.jpeg', '/tmp/a.png', '/tmp/a.heic', '/tmp/a']) {
        expect(WidgetAnimService.isSupportedSource(p), isFalse, reason: p);
      }
    });

    test('видео отличается от гифки — от этого зависит текст ошибки', () {
      expect(WidgetAnimService.isVideoSource('/tmp/a.mp4'), isTrue);
      expect(WidgetAnimService.isVideoSource('/tmp/a.gif'), isFalse);
    });
  });

  group('Выбор кадра', () {
    test('шаг гифки отличается от видео и всё равно заворачивается', () {
      // У гифки шаг считает сервер по её собственной длительности: 2,5 секунды
      // на 18 кадров дают 139 мс, а не 83 как у видео.
      const gif = WidgetAnimManifest(
        cols: 6, rows: 3, cell: 300, frames: 18, stepMs: 139, source: 'animation',
      );
      expect(WidgetAnimService.frameAt(gif, 0), 0);
      expect(WidgetAnimService.frameAt(gif, 139), 1);
      expect(WidgetAnimService.frameAt(gif, 139 * 18), 0);
    });

    test('идёт по порядку и заворачивается по кругу', () {
      expect(WidgetAnimService.frameAt(m, 0), 0);
      expect(WidgetAnimService.frameAt(m, 83), 1);
      expect(WidgetAnimService.frameAt(m, 83 * 17), 17);
      expect(WidgetAnimService.frameAt(m, 83 * 18), 0);
    });

    test('клетка атласа считается по столбцам', () {
      expect(WidgetAnimService.cellRect(m, 0), (left: 0, top: 0, size: 300));
      expect(WidgetAnimService.cellRect(m, 5), (left: 1500, top: 0, size: 300));
      expect(WidgetAnimService.cellRect(m, 6), (left: 0, top: 300, size: 300));
      expect(WidgetAnimService.cellRect(m, 17), (left: 1500, top: 600, size: 300));
    });

    test('индекс за пределами листа не уводит за край картинки', () {
      final r = WidgetAnimService.cellRect(m, 999);
      expect(r.left, lessThan(m.cols * m.cell));
      expect(r.top, lessThan(m.rows * m.cell));
    });
  });
}
