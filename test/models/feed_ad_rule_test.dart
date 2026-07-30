// Первый баннер в ленте показывался только после шестого воспоминания, а до
// него долистывали не все: запросов в РСЯ втрое больше показов. Правило
// переписано на «после первого, дальше каждые шесть».

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/feed_ad_rule.dart';

void main() {
  group('adAfterMemory', () {
    test('первый баннер идёт сразу после первого воспоминания', () {
      expect(adAfterMemory(1), isTrue);
    });

    test('со второго по шестое баннеров нет', () {
      for (var i = 2; i <= 6; i++) {
        expect(adAfterMemory(i), isFalse, reason: 'воспоминание $i');
      }
    });

    test('дальше каждое шестое', () {
      expect(adAfterMemory(7), isTrue);
      expect(adAfterMemory(13), isTrue);
      expect(adAfterMemory(19), isTrue);
    });

    test('между баннерами ровно шесть воспоминаний', () {
      final positions = [
        for (var i = 1; i <= 40; i++)
          if (adAfterMemory(i)) i,
      ];
      for (var i = 1; i < positions.length; i++) {
        expect(positions[i] - positions[i - 1], kAdEveryNMemories);
      }
    });

    test('на первой странице ленты выходит четыре баннера', () {
      final count = [
        for (var i = 1; i <= 20; i++)
          if (adAfterMemory(i)) i,
      ].length;
      expect(count, 4);
    });

    test('нулевая и отрицательная позиция баннера не дают', () {
      expect(adAfterMemory(0), isFalse);
      expect(adAfterMemory(-3), isFalse);
    });
  });
}
