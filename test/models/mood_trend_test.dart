import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mood_entry.dart';
import 'package:love_app/models/mood_trend.dart';

/// Жалоба владельца 08.11.2026 со снимком: «график слишком много информации,
/// налезает друг на друга» — 63 отмеченных дня с июня шли 63 кружками, а
/// кривая выезжала за 5 и под 1. И «эмоции в статистике и выбранные на дне
/// разные, на дне факт»: в паках настроения называются одинаково (`laugh`,
/// `love`), а статистика брала картинку по названию из стандартного пака.
void main() {
  MoodEntry entry(String id, String image, DateTime at) =>
      MoodEntry(id: '${at.millisecondsSinceEpoch}', moodId: id, imagePath: image, label: id, timestamp: at);

  group('точки графика', () {
    test('две недели и меньше — по дню', () {
      final days = {for (var i = 0; i < 10; i++) DateTime(2026, 11, 1 + i): 3.0};
      final points = moodTrendPoints(days);
      expect(points, hasLength(10));
      expect(points.first.start, DateTime(2026, 11, 1));
    });

    test('полгода с 63 днями — по неделям, не больше 26 точек', () {
      final days = <DateTime, double>{};
      var d = DateTime(2026, 6, 8);
      for (var i = 0; i < 63; i++) {
        days[d] = (i % 5 + 1).toDouble();
        d = DateTime(d.year, d.month, d.day + 2 + i % 2);
      }
      final points = moodTrendPoints(days);
      expect(points.length, lessThanOrEqualTo(kMoodTrendMaxPoints));
      expect(points.length, greaterThan(15), reason: 'месяцами полгода сжимались в пять точек');
      expect(points.first.start.weekday, DateTime.monday);
      for (final p in points) {
        expect(p.value, inInclusiveRange(1, 5));
      }
    });

    test('неделя — среднее её дней, начало с понедельника', () {
      final days = <DateTime, double>{
        for (var i = 0; i < 20; i++) DateTime(2026, 10, 1 + i): i < 7 ? 5.0 : 1.0,
      };
      days[DateTime(2026, 10, 4)] = 1.0; // воскресенье той же недели
      final points = moodTrendPoints(days);
      // 1–4 октября (чт–вс): пять, пять, пять, один → неделя с 28 сентября.
      expect(points.first.start, DateTime(2026, 9, 28));
      expect(points.first.value, closeTo((5 + 5 + 5 + 1) / 4, 0.001));
    });
  });

  test('год — по месяцам', () {
    final days = <DateTime, double>{
      for (var i = 0; i < 300; i += 2) DateTime(2026, 1, 1 + i): 3.0,
    };
    final points = moodTrendPoints(days);
    expect(points.length, lessThanOrEqualTo(12));
    expect(points.every((p) => p.start.day == 1), isTrue);
  });

  group('подпись точки при нажатии', () {
    const months = ['', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля',
      'августа', 'сентября', 'октября', 'ноября', 'декабря'];
    const monthsNom = ['', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль',
      'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];

    test('день', () {
      final p = MoodTrendPoint(DateTime(2026, 10, 12), 4.2);
      expect(moodTrendPointLabel(p, months, monthsNom), '12 октября · 4,2');
    });

    test('неделя внутри месяца', () {
      final p = MoodTrendPoint(DateTime(2026, 10, 12), 3, end: DateTime(2026, 10, 18));
      expect(moodTrendPointLabel(p, months, monthsNom), '12–18 октября · 3,0');
    });

    test('неделя на стыке месяцев', () {
      final p = MoodTrendPoint(DateTime(2026, 9, 28), 4.5, end: DateTime(2026, 10, 4));
      expect(moodTrendPointLabel(p, months, monthsNom), '28 сентября – 4 октября · 4,5');
    });

    test('месяц', () {
      final p = MoodTrendPoint(DateTime(2026, 3, 1), 2.25, end: DateTime(2026, 3, 31), wholeMonth: true);
      expect(moodTrendPointLabel(p, months, monthsNom), 'Март · 2,3');
    });

    test('недельные точки знают свой конец', () {
      final days = {for (var i = 0; i < 20; i++) DateTime(2026, 10, 1 + i): 3.0};
      final first = moodTrendPoints(days).first;
      expect(first.end, DateTime(2026, 10, 4));
    });
  });

  test('кружки только пока точек немного', () {
    expect(moodTrendShowsDots(12), isTrue);
    expect(moodTrendShowsDots(22), isFalse);
  });

  group('картинки отметок', () {
    test('картинка — из последней отметки с этим настроением', () {
      final images = moodImagesOf([
        entry('laugh', 'default/laugh.webp', DateTime(2026, 11, 1)),
        entry('laugh', 'kitty/laugh.webp', DateTime(2026, 11, 6)),
        entry('love', 'kitty/love.webp', DateTime(2026, 11, 7)),
      ]);
      expect(images, {'laugh': 'kitty/laugh.webp', 'love': 'kitty/love.webp'});
    });

    test('отметка без картинки картинку не затирает', () {
      final images = moodImagesOf([
        entry('laugh', 'kitty/laugh.webp', DateTime(2026, 11, 1)),
        entry('laugh', '', DateTime(2026, 11, 2)),
      ]);
      expect(images['laugh'], 'kitty/laugh.webp');
    });
  });
}
