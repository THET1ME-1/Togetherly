import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/unfold/unfold_math.dart';

void main() {
  const screen = Size(360, 760);
  final full = Offset.zero & screen;
  const card = Rect.fromLTWH(12, 128, 336, 320);

  group('пружина', () {
    test('до старта стоит на нуле', () {
      expect(unfoldSpring(0, omega: 18, zeta: 0.82), 0);
      expect(unfoldSpring(-40, omega: 18, zeta: 0.82), 0);
    });

    test('недодемпфированная проскакивает цель и возвращается', () {
      var peak = 0.0;
      for (var ms = 0.0; ms <= 620; ms += 4) {
        final value = unfoldSpring(ms, omega: 18, zeta: 0.82);
        if (value > peak) peak = value;
      }
      expect(peak, greaterThan(1.0), reason: 'перелёта нет — это не пружина');
      expect(peak, lessThan(1.03), reason: 'перелёт заметнее, чем в макете');
      expect(unfoldSpring(420, omega: 18, zeta: 0.82), closeTo(1, 0.01));
    });

    test('критически демпфированная цель не проскакивает', () {
      for (var ms = 0.0; ms <= 430; ms += 4) {
        expect(unfoldSpring(ms, omega: 21, zeta: 1), lessThanOrEqualTo(1.0));
      }
      expect(unfoldSpring(430, omega: 21, zeta: 1), closeTo(1, 0.01));
    });
  });

  group('открытие', () {
    test('начинается ровно на карточке и под её заливкой', () {
      final frame = unfoldOpenFrame(
          ms: 0, source: card, full: full, sourceRadius: 28);
      expect(frame.rect, card);
      expect(frame.radius, 28);
      expect(frame.tint, 1);
      expect(frame.ghost, 1);
      expect(frame.flight, 0);
    });

    test('кончается полным экраном без заливки и призрака', () {
      final frame = unfoldOpenFrame(
          ms: UnfoldTiming.openMs, source: card, full: full, sourceRadius: 28);
      expect(frame.rect.left, closeTo(0, 0.5));
      expect(frame.rect.width, closeTo(360, 0.5));
      expect(frame.rect.height, closeTo(760, 0.5));
      expect(frame.radius, closeTo(0, 0.2));
      expect(frame.tint, 0);
      expect(frame.ghost, 0);
    });

    test('содержимое карточки гаснет раньше, чем сойдёт заливка', () {
      final frame = unfoldOpenFrame(
          ms: 120, source: card, full: full, sourceRadius: 28);
      expect(frame.ghost, 0);
      expect(frame.tint, greaterThan(0));
    });
  });

  group('содержимое экрана', () {
    test('первый блок ждёт начала, потом проявляется', () {
      expect(unfoldItemIn(60, 0).opacity, 0);
      expect(unfoldItemIn(165, 0).opacity, closeTo(0.5, 0.01));
      expect(unfoldItemIn(UnfoldTiming.openMs, 0).opacity, 1);
    });

    test('каждый следующий блок отстаёт на тридцать миллисекунд', () {
      expect(unfoldItemIn(165, 3).opacity,
          closeTo(unfoldItemIn(165 - 90, 0).opacity, 1e-9));
      expect(unfoldItemIn(200, 5).opacity, lessThan(unfoldItemIn(200, 0).opacity));
    });

    test('блок приезжает снизу и встаёт на место', () {
      expect(unfoldItemIn(80, 0).shift, closeTo(18, 0.01));
      expect(unfoldItemIn(UnfoldTiming.openMs, 0).shift.abs(), lessThan(0.3));
    });

    test('при закрытии содержимое гаснет за девяносто миллисекунд', () {
      expect(unfoldItemOutOpacity(0), 1);
      expect(unfoldItemOutOpacity(45), closeTo(0.5, 1e-9));
      expect(unfoldItemOutOpacity(90), 0);
      expect(unfoldItemOutOpacity(300), 0);
    });
  });

  group('закрытие', () {
    test('с полного экрана начинается полным экраном', () {
      final frame = unfoldCloseFrame(
          ms: 0, source: card, from: full, sourceRadius: 28, fromRadius: 0);
      expect(frame.rect, full);
      expect(frame.radius, 0);
      expect(frame.tint, 0);
      expect(frame.ghost, 0);
      expect(frame.flight, 1);
    });

    test('кончается карточкой с её содержимым', () {
      final frame = unfoldCloseFrame(
          ms: UnfoldTiming.closeMs,
          source: card,
          from: full,
          sourceRadius: 28,
          fromRadius: 0);
      expect(frame.rect.left, closeTo(card.left, 0.5));
      expect(frame.rect.top, closeTo(card.top, 1.0));
      expect(frame.rect.width, closeTo(card.width, 0.5));
      expect(frame.radius, closeTo(28, 0.2));
      expect(frame.tint, 1);
      expect(frame.ghost, 1);
    });

    test('из-под пальца стартует с того места, где карточку отпустили', () {
      const dropped = Rect.fromLTWH(120, 180, 200, 420);
      final frame = unfoldCloseFrame(
          ms: 0, source: card, from: dropped, sourceRadius: 28, fromRadius: 40);
      expect(frame.rect, dropped);
      expect(frame.radius, 40);
    });
  });

  group('экран под пальцем', () {
    test('без сдвига остаётся полным экраном', () {
      final frame = unfoldDragFrame(delta: Offset.zero, screen: screen);
      expect(frame.rect, full);
      expect(frame.radius, 0);
      expect(frame.progress, 0);
    });

    test('на полном ходу сжимается до 56% и скругляется', () {
      final frame = unfoldDragFrame(delta: const Offset(210, 0), screen: screen);
      expect(frame.progress, 1);
      expect(frame.rect.width, closeTo(360 * 0.56, 0.01));
      expect(frame.rect.height, closeTo(760 * 0.56, 0.01));
      expect(frame.radius, closeTo(46, 0.01));
    });

    test('едет за пальцем вправо', () {
      final near = unfoldDragFrame(delta: const Offset(60, 0), screen: screen);
      final far = unfoldDragFrame(delta: const Offset(160, 0), screen: screen);
      expect(far.rect.left, greaterThan(near.rect.left));
      expect(near.rect.left, closeTo(60 * 0.62, 0.01));
    });

    test('по высоте за экран не выходит', () {
      for (final dy in [-900.0, -200.0, 0.0, 300.0, 900.0]) {
        final frame =
            unfoldDragFrame(delta: Offset(140, dy), screen: screen);
        expect(frame.rect.top, greaterThanOrEqualTo(0));
        expect(frame.rect.bottom, lessThanOrEqualTo(760 + 1e-6));
      }
    });

    test('от правого края зеркалится', () {
      final frame = unfoldDragFrame(
          delta: const Offset(-100, 0), screen: screen, fromRight: true);
      expect(frame.progress, closeTo(100 / 210, 1e-9));
      expect(frame.rect.right, closeTo(360 - 100 * 0.62, 0.01));
    });

    test('движение назад к краю не считается жестом', () {
      final frame =
          unfoldDragFrame(delta: const Offset(-80, 0), screen: screen);
      expect(frame.progress, 0);
      expect(frame.rect, full);
    });

    test('порог закрытия — треть хода', () {
      expect(unfoldDragCommits(0.32), isFalse);
      expect(unfoldDragCommits(0.34), isTrue);
    });
  });

  group('полёт кадра в просмотр', () {
    test('фон темнеет за 220 мс, кадр летит той же пружиной, что окно', () {
      expect(photoOpenFrame(0).flight, 0);
      expect(photoOpenFrame(0).backdrop, 0);
      expect(photoOpenFrame(110).backdrop, closeTo(0.5, 1e-9));
      expect(photoOpenFrame(220).backdrop, 1);
      expect(photoOpenFrame(180).flight,
          closeTo(unfoldSpring(180, omega: 18, zeta: 0.82), 1e-12));
      expect(photoOpenFrame(620).flight, closeTo(1, 0.002));
    });

    test('кнопки проявляются следом: с 140-й мс, шаг 60', () {
      expect(photoChromeIn(140, 0), 0);
      expect(photoChromeIn(225, 0), closeTo(0.5, 1e-9));
      expect(photoChromeIn(310, 0), 1);
      expect(photoChromeIn(200, 1), 0);
      expect(photoChromeIn(370, 1), 1);
    });

    test('обратно: без перелёта, фон светлеет за 240 мс, кнопки за 90', () {
      var last = 2.0;
      for (var ms = 0.0; ms <= 430; ms += 10) {
        final flight = photoCloseFrame(ms).flight;
        expect(flight, lessThanOrEqualTo(last));
        expect(flight, inInclusiveRange(0.0, 1.0));
        last = flight;
      }
      expect(photoCloseFrame(430).flight, lessThan(0.002));
      expect(photoCloseFrame(120).backdrop, closeTo(0.5, 1e-9));
      expect(photoCloseFrame(240).backdrop, 0);
      expect(photoChromeOut(45), closeTo(0.5, 1e-9));
      expect(photoChromeOut(90), 0);
    });

    test('закрытие из-под пальца начинает с того фона, что был', () {
      expect(photoCloseFrame(0, backdropFrom: 0.4).backdrop, 0.4);
      expect(photoCloseFrame(120, backdropFrom: 0.4).backdrop,
          closeTo(0.2, 1e-9));
      expect(photoChromeOut(0, from: 0), 0);
    });

    test('под пальцем кадр едет вниз, сжимается, фон светлеет', () {
      final rest = photoDragFrame(Offset.zero);
      expect(rest.shift, Offset.zero);
      expect(rest.scale, 1);
      expect(rest.backdrop, 1);
      expect(rest.chrome, 1);

      final pulled = photoDragFrame(const Offset(40, 150));
      expect(pulled.shift, const Offset(20, 150));
      expect(pulled.scale, closeTo(1 - 150 / 700, 1e-9));
      expect(pulled.backdrop, closeTo(1 - 0.5 * 0.85, 1e-9));
      expect(pulled.chrome, 0);

      final far = photoDragFrame(const Offset(0, 900));
      expect(far.scale, closeTo(0.7, 1e-9));
      expect(far.backdrop, closeTo(0.15, 1e-9));
    });

    test('вверх кадр не едет', () {
      final up = photoDragFrame(const Offset(30, -200));
      expect(up.shift.dy, 0);
      expect(up.scale, 1);
      expect(up.backdrop, 1);
    });

    test('порог жеста — 80 точек вниз', () {
      expect(photoDragCommits(79), isFalse);
      expect(photoDragCommits(81), isTrue);
    });

    test('цель полёта — картинка, вписанная в сцену целиком', () {
      const stage = Rect.fromLTWH(0, 60, 360, 560);
      // Горизонтальный кадр упирается в ширину.
      expect(photoFit(const Size(1600, 900), stage),
          Rect.fromCenter(center: stage.center, width: 360, height: 202.5));
      // Вертикальный — в высоту.
      expect(photoFit(const Size(900, 1600), stage),
          Rect.fromCenter(center: stage.center, width: 315, height: 560));
      // Пустую картинку вписать нельзя: сцена целиком.
      expect(photoFit(Size.zero, stage), stage);
    });
  });
}
