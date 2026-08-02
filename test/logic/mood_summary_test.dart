import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mood_summary.dart';

/// Сводка настроений за месяц для кольца в календаре.
///
/// Прежний блок показывал девять долей подряд, семь из них по девять
/// процентов — это шум. Кольцу нужны три вещи: доли по убыванию, тройка
/// лидеров и одно число в центре.
void main() {
  group('MoodSummary', () {
    test('считает доли и сортирует по убыванию', () {
      final s = MoodSummary.of(const {'kiss': 4, 'happy': 2, 'sad': 2});
      expect(s.total, 8);
      expect(s.slices.map((e) => e.id).toList(), ['kiss', 'happy', 'sad']);
      expect(s.slices.first.percent, 50);
    });

    test('одинаковые доли идут в стабильном порядке', () {
      // Иначе кольцо перекрашивается на каждой перерисовке.
      final first = MoodSummary.of(const {'sad': 1, 'happy': 1, 'anger': 1});
      final again = MoodSummary.of(const {'anger': 1, 'happy': 1, 'sad': 1});
      expect(first.slices.map((e) => e.id), again.slices.map((e) => e.id));
    });

    test('тройка лидеров и хвост', () {
      final s = MoodSummary.of(
          const {'kiss': 5, 'happy': 4, 'sad': 3, 'anger': 2, 'fear': 1});
      expect(s.top.map((e) => e.id).toList(), ['kiss', 'happy', 'sad']);
      expect(s.restCount, 2);
    });

    test('доля светлых настроений — число в центре', () {
      // Светлыми считаем тир 4 и выше: «Целую» и «Счастье» — пятёрки,
      // «Грустно» — двойка.
      final s = MoodSummary.of(const {'kiss': 1, 'happy': 1, 'sad': 2});
      expect(s.brightPercent, 50);
    });

    test('пустой месяц не делит на ноль', () {
      final s = MoodSummary.of(const {});
      expect(s.total, 0);
      expect(s.slices, isEmpty);
      expect(s.brightPercent, 0);
      expect(s.isEmpty, isTrue);
    });

    test('проценты округляются, но сумма остаётся сотней', () {
      // Три трети дают 33-33-33 и дырку в проценте; последнюю долю
      // дотягиваем, иначе кольцо не сходится.
      final s = MoodSummary.of(const {'kiss': 1, 'happy': 1, 'sad': 1});
      expect(s.slices.fold<int>(0, (a, e) => a + e.percent), 100);
    });
  });
}
