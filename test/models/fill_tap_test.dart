import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/canvas_gestures.dart';

/// Заливка слушается тапа, а не касания.
///
/// Жалоба 19.08.2026 из-под ролика: «заливка работает очень плохо, заливается
/// куда попало, пока просто приближаю картинку, иногда не работает вовсе».
/// Причина ровно в этом: заливка применялась в момент, когда палец коснулся
/// холста, — то есть до того, как станет ясно, щипок это или тап. Первый палец
/// щипка уже красил область под собой, а второй приходил через десятки
/// миллисекунд, когда красить было поздно.
void main() {
  group('fillTapAccepted', () {
    test('короткий тап одним пальцем заливает', () {
      expect(
        fillTapAccepted(
          travel: 3,
          held: const Duration(milliseconds: 120),
          extraPointers: 0,
          zoomed: false,
        ),
        isTrue,
      );
    });

    test('второй палец отменяет заливку', () {
      // Щипок: человек приближает картинку, а не красит.
      expect(
        fillTapAccepted(
          travel: 2,
          held: const Duration(milliseconds: 90),
          extraPointers: 1,
          zoomed: false,
        ),
        isFalse,
      );
    });

    test('масштаб поехал — заливки нет', () {
      expect(
        fillTapAccepted(
          travel: 4,
          held: const Duration(milliseconds: 100),
          extraPointers: 0,
          zoomed: true,
        ),
        isFalse,
      );
    });

    test('палец уехал — это не тап', () {
      expect(
        fillTapAccepted(
          travel: 40,
          held: const Duration(milliseconds: 150),
          extraPointers: 0,
          zoomed: false,
        ),
        isFalse,
      );
    });

    test('долгое удержание не считается тапом', () {
      // Палец лежит на холсте секунду — человек присматривается, а не красит.
      expect(
        fillTapAccepted(
          travel: 1,
          held: const Duration(milliseconds: 900),
          extraPointers: 0,
          zoomed: false,
        ),
        isFalse,
      );
    });

    test('дрожание руки заливке не мешает', () {
      // Порог смещения должен прощать несколько пикселей: идеально неподвижно
      // палец не держит никто.
      expect(
        fillTapAccepted(
          travel: 9,
          held: const Duration(milliseconds: 200),
          extraPointers: 0,
          zoomed: false,
        ),
        isTrue,
      );
    });
  });

  group('strokeSurvivesSecondFinger', () {
    // Второй палец приходит на 20–80 мс позже первого, и за это время кисть
    // успевает поставить точку-другую. Раньше такой огрызок оставался на
    // холсте: «заливается куда попало» — это про заливку, а у кисти тем же
    // жестом сыпались случайные точки.
    test('огрызок в начале щипка не остаётся на холсте', () {
      expect(
        strokeSurvivesSecondFinger(
          travel: 5,
          held: const Duration(milliseconds: 60),
        ),
        isFalse,
      );
    });

    test('начатую линию второй палец не стирает', () {
      // Ладонь легла на экран посреди мазка — работу терять нельзя.
      expect(
        strokeSurvivesSecondFinger(
          travel: 120,
          held: const Duration(milliseconds: 800),
        ),
        isTrue,
      );
    });

    test('долгий, но короткий по пути штрих остаётся', () {
      // Точка, поставленная нарочно: палец стоял на месте почти секунду.
      expect(
        strokeSurvivesSecondFinger(
          travel: 2,
          held: const Duration(milliseconds: 700),
        ),
        isTrue,
      );
    });
  });

  group('холст слушается этих правил', () {
    final source = File('lib/screens/draw_screen.dart').readAsStringSync();

    test('заливка применяется на отпускании, а не на касании', () {
      final down = source.indexOf('void _onPointerDown');
      final move = source.indexOf('void _onPointerMove');
      final onDown = source.substring(down, move);
      expect(onDown.contains('_applyFill('), isFalse,
          reason: 'На касании ещё не известно, тап это или начало щипка');
      expect(source.contains('fillTapAccepted('), isTrue,
          reason: 'Решение принимает правило под тестами');
    });

    test('судьбу штриха при втором пальце решает путь, а не число точек', () {
      expect(source.contains('strokeSurvivesSecondFinger('), isTrue);
      expect(source.contains('_currentPoints.length > 1'), isFalse,
          reason: 'За 20–80 мс щипка точек набегает сколько угодно');
    });

    test('снимок для заливки подробнее экрана', () {
      // У пипетки снимок один к одному правильный: там читают цвет пикселя.
      // Речь только про заливку — её край при увеличении выходил ступеньками.
      final from = source.indexOf('Future<void> _applyFill(');
      final to = source.indexOf('Future<void>', from + 10);
      final body = source.substring(from, to);
      expect(body.contains('pixelRatio: 1.0'), isFalse);
      expect(body.contains('toImage(pixelRatio: ratio)'), isTrue);
    });
  });
}
