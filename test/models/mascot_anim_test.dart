import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/level.dart';
import 'package:love_app/models/mascot_anim.dart';
import 'package:love_app/models/mascot_sleep.dart';

/// Пиксельные маскоты приходят из каталога, а не из сборки: приложение знает
/// только формат атласа. Поэтому разбор манифеста и вырезка кадра покрыты
/// тестами — ошибка здесь показала бы людям простыню кадров вместо персонажа.
void main() {
  Map<String, dynamic> row({
    String id = 'pudya',
    Map<String, dynamic>? data,
  }) =>
      {
        'id': id,
        'name_ru': 'Пудя',
        'name_en': 'Pud',
        'data': data ??
            {
              'sheet': 'https://togetherly.duckdns.org/atlas.png',
              'frame': 48,
              'cols': 12,
              'fps': 10,
              'rows': ['live', 'grow', 'freeze', 'sad', 'happy'],
              'levels': 3,
              'story_ru': 'Желейный и мягкий.',
            },
      };

  group('Разбор каталога', () {
    test('Манифест доезжает целиком', () {
      final anim = MascotAnim.fromCatalog(row(), unlock: const Unlock.free())!;

      expect(anim.id, 'pudya');
      expect(anim.nameRu, 'Пудя');
      expect(anim.frame, 48);
      expect(anim.cols, 12);
      expect(anim.fps, 10);
      expect(anim.levels, 3);
      expect(anim.storyRu, 'Желейный и мягкий.');
    });

    test('Без картинки маскота нет', () {
      final anim = MascotAnim.fromCatalog(
        row(data: {'frame': 48, 'cols': 12, 'rows': ['live']}),
        unlock: const Unlock.free(),
      );
      expect(anim, isNull);
    });

    test('Без списка состояний маскота нет: рисовать нечего', () {
      final anim = MascotAnim.fromCatalog(
        row(data: {'sheet': 'https://x/a.png', 'frame': 48, 'cols': 12}),
        unlock: const Unlock.free(),
      );
      expect(anim, isNull);
    });

    test('Нулевой кадр не пройдёт — на него потом делят', () {
      final anim = MascotAnim.fromCatalog(
        row(data: {
          'sheet': 'https://x/a.png',
          'frame': 0,
          'cols': 12,
          'rows': ['live'],
        }),
        unlock: const Unlock.free(),
      );
      expect(anim, isNull);
    });
  });

  group('Вырезка кадра', () {
    final anim = MascotAnim.fromCatalog(row(), unlock: const Unlock.free())!;

    test('Первый кадр «живёт» — левый верхний угол атласа', () {
      final r = anim.rect(MascotAnimState.live, 0);
      expect(r.left, 0);
      expect(r.top, 0);
      expect(r.width, 48);
      expect(r.height, 48);
    });

    test('Состояние выбирает строку в порядке манифеста', () {
      expect(anim.rect(MascotAnimState.sad, 0).top, 48 * 3);
      expect(anim.rect(MascotAnimState.happy, 0).top, 48 * 4);
    });

    test('Кадры идут по кругу, за край атласа не уходим', () {
      expect(anim.rect(MascotAnimState.live, 12).left, 0);
      expect(anim.rect(MascotAnimState.live, 13).left, 48);
    });

    test('Неизвестное состояние падает на «живёт», а не на пустоту', () {
      expect(anim.has(MascotAnimState.drag), isFalse);
      expect(anim.rect(MascotAnimState.drag, 0).top, 0);
    });
  });

  group('Ступени роста', () {
    final anim = MascotAnim.fromCatalog(
      row(data: {
        'sheet': 'https://x/a.png',
        'frame': 48,
        'cols': 12,
        'rows': ['live', 'grow', 'freeze', 'sad', 'happy'],
        'levels': 3,
        'level_offsets': {'1': 5, '2': 10, '3': 0},
      }),
      unlock: const Unlock.free(),
    )!;

    test('Третья ступень лежит в нулевом блоке — так видят её старые сборки', () {
      expect(anim.rect(MascotAnimState.live, 0, level: 3).top, 0);
    });

    test('Первая и вторая ступени берутся со своим смещением', () {
      expect(anim.rect(MascotAnimState.live, 0, level: 1).top, 48 * 5);
      expect(anim.rect(MascotAnimState.happy, 0, level: 2).top, 48 * (10 + 4));
    });

    test('Ступень за пределами набора прижимается к допустимой', () {
      expect(anim.rect(MascotAnimState.live, 0, level: 7).top,
          anim.rect(MascotAnimState.live, 0, level: 3).top);
    });

    test('Атлас без ступеней рисует нулевой блок', () {
      final old = MascotAnim.fromCatalog(row(), unlock: const Unlock.free())!;
      expect(old.hasLevels, isFalse);
      expect(old.rect(MascotAnimState.live, 0, level: 1).top, 0);
    });

    test('Ступень считается по длине серии', () {
      expect(MascotAnim.levelForStreak(0), 1);
      expect(MascotAnim.levelForStreak(6), 1);
      expect(MascotAnim.levelForStreak(7), 2);
      expect(MascotAnim.levelForStreak(29), 2);
      expect(MascotAnim.levelForStreak(30), 3);
      expect(MascotAnim.levelForStreak(400), 3);
    });
  });

  group('Свои сцены персонажа', () {
    final anim = MascotAnim.fromCatalog(
      row(data: {
        'sheet': 'https://x/a.png',
        'frame': 96,
        'cols': 12,
        'rows': ['live', 'grow', 'freeze', 'sad', 'happy', 'preen', 'sleep'],
        'extra_idles': ['preen', 'нет-такой'],
        'night_idle': 'sleep',
        'level_offsets': {'1': 7, '2': 14, '3': 0},
      }),
      unlock: const Unlock.free(),
    )!;

    test('Сцены берутся только те, что есть в атласе', () {
      expect(anim.extraIdles, ['preen']);
    });

    test('Ночная сцена подхватывается из манифеста', () {
      expect(anim.nightIdle, 'sleep');
    });

    test('Кадр своей сцены берётся по имени строки', () {
      expect(anim.rectRow('preen', 0).top, 96 * 5);
      expect(anim.rectRow('sleep', 0, level: 2).top, 96 * (14 + 6));
    });

    test('Незнакомая строка падает на «живёт»', () {
      expect(anim.rectRow('танцует', 0).top, 0);
    });

    test('Ночь включается по окну, заданному человеком', () {
      const early = SleepWindow(from: 21 * 60, to: 5 * 60);
      expect(anim.idleRow(DateTime(2026, 8, 1, 21, 30), early), 'sleep');
      expect(anim.idleRow(DateTime(2026, 8, 1, 22, 30), SleepWindow.standard),
          'live');
    });

    test('Выключенная ночь не наступает никогда', () {
      const off = SleepWindow(from: 23 * 60, to: 7 * 60, enabled: false);
      expect(anim.idleRow(DateTime(2026, 8, 1, 3, 0), off), 'live');
    });

    test('Ночь важнее своей сцены', () {
      expect(
        anim.idleRow(DateTime(2026, 8, 1, 3, 0), SleepWindow.standard,
            scene: 'preen'),
        'sleep',
      );
    });

    test('Днём играет своя сцена', () {
      expect(
        anim.idleRow(DateTime(2026, 8, 1, 15, 0), SleepWindow.standard,
            scene: 'preen'),
        'preen',
      );
    });

    test('Без своих сцен список пуст, а не сломан', () {
      final plain = MascotAnim.fromCatalog(row(), unlock: const Unlock.free())!;
      expect(plain.extraIdles, isEmpty);
      expect(plain.nightIdle, isEmpty);
    });
  });

  group('Сезонный наряд', () {
    final anim = MascotAnim.fromCatalog(
      row(data: {
        'sheet': 'https://x/a.png',
        'frame': 96,
        'cols': 12,
        'rows': ['live', 'grow', 'freeze', 'sad', 'happy', 'winter', 'summer'],
        'season_idles': {'12': 'winter', '1': 'winter', '7': 'summer',
                         '5': 'нет-такой'},
      }),
      unlock: const Unlock.free(),
    )!;

    test('Месяцы разбираются, несуществующие сцены отбрасываются', () {
      expect(anim.seasonRow(DateTime(2026, 12, 20)), 'winter');
      expect(anim.seasonRow(DateTime(2026, 7, 4)), 'summer');
      expect(anim.seasonRow(DateTime(2026, 5, 1)), isEmpty);
    });

    test('Месяц без наряда оставляет обычный вид', () {
      expect(anim.seasonRow(DateTime(2026, 3, 8)), isEmpty);
    });

    test('Сезонный наряд надевается, когда ночь не идёт', () {
      expect(
        anim.idleRow(DateTime(2026, 12, 20, 15, 0), SleepWindow.standard),
        'winter',
      );
    });

    test('Без сезонов карта пуста', () {
      final plain = MascotAnim.fromCatalog(row(), unlock: const Unlock.free())!;
      expect(plain.seasonIdles, isEmpty);
      expect(plain.seasonRow(DateTime(2026, 1, 1)), isEmpty);
    });
  });

  group('Разовые сцены', () {
    test('Рост, радость и приземление играются один раз', () {
      expect(MascotAnimState.grow.oneShot, isTrue);
      expect(MascotAnimState.happy.oneShot, isTrue);
      expect(MascotAnimState.drop.oneShot, isTrue);
    });

    test('Жизнь и грусть крутятся по кругу', () {
      expect(MascotAnimState.live.oneShot, isFalse);
      expect(MascotAnimState.sad.oneShot, isFalse);
      expect(MascotAnimState.drag.oneShot, isFalse);
    });
  });
}
