import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mascot_anim.dart';
import 'package:love_app/models/mascot_widget_data.dart';

void main() {
  group('ступень маскота на рабочем столе', () {
    test('пороги те же, что у ступеней атласа', () {
      expect(mascotStageOf(0), MascotStage.baby);
      expect(mascotStageOf(6), MascotStage.baby);
      expect(mascotStageOf(7), MascotStage.teen);
      expect(mascotStageOf(29), MascotStage.teen);
      expect(mascotStageOf(30), MascotStage.adult);
      expect(mascotStageOf(400), MascotStage.adult);
    });

    test('ступень виджета и уровень атласа не расходятся', () {
      for (final streak in [0, 1, 6, 7, 8, 29, 30, 31, 400]) {
        expect(
          mascotStageOf(streak).level,
          MascotAnim.levelForStreak(streak),
          reason: 'серия $streak',
        );
      }
    });

    test('отрицательная серия считается нулём', () {
      expect(mascotStageOf(-5), MascotStage.baby);
      expect(mascotDaysToNextStage(-5), 7);
      expect(mascotStageProgress(-5), 0);
    });
  });

  group('сколько осталось до следующей ступени', () {
    test('малыш растёт до семи дней, подросток до тридцати', () {
      expect(mascotDaysToNextStage(0), 7);
      expect(mascotDaysToNextStage(2), 5);
      expect(mascotDaysToNextStage(6), 1);
      expect(mascotDaysToNextStage(7), 23);
      expect(mascotDaysToNextStage(12), 18);
      expect(mascotDaysToNextStage(29), 1);
    });

    test('взрослому расти некуда', () {
      expect(mascotDaysToNextStage(30), 0);
      expect(mascotDaysToNextStage(365), 0);
    });
  });

  group('полоса роста', () {
    test('доля считается внутри своей ступени', () {
      expect(mascotStageProgress(0), 0);
      expect(mascotStageProgress(3), closeTo(3 / 7, 0.001));
      expect(mascotStageProgress(7), 0);
      expect(mascotStageProgress(12), closeTo(5 / 23, 0.001));
    });

    test('у взрослого полоса заполнена', () {
      expect(mascotStageProgress(30), 1);
      expect(mascotStageProgress(31), 1);
    });

    test('в проценты уходит целое число от нуля до ста', () {
      expect(mascotStagePercent(0), 0);
      expect(mascotStagePercent(12), 22);
      expect(mascotStagePercent(30), 100);
    });
  });

  group('снимок для нативной стороны', () {
    const sleep = MascotSleepWindow(from: 23 * 60, to: 7 * 60);

    test('собирает всё, что рисует виджет', () {
      const data = MascotWidgetData(
        mascotId: 'pudya',
        name: 'Пудя',
        streakDays: 12,
        sad: false,
        sleep: sleep,
      );
      expect(data.stage, MascotStage.teen);
      expect(data.level, 2);
      expect(data.daysToNextStage, 18);
      expect(data.percent, 22);
    });

    test('оборванная серия просит грустный кадр', () {
      const data = MascotWidgetData(
        mascotId: 'pudya',
        name: 'Пудя',
        streakDays: 0,
        sad: true,
        sleep: sleep,
      );
      expect(data.sad, isTrue);
      expect(data.stage, MascotStage.baby);
    });

    test('персонаж без сна отдаёт минуты минус единицей', () {
      const data = MascotWidgetData(
        mascotId: 'zheleyka',
        name: 'Желейка',
        streakDays: 3,
        sad: false,
        sleep: MascotSleepWindow.none,
      );
      expect(data.sleep.from, -1);
      expect(data.sleep.to, -1);
    });
  });
}
