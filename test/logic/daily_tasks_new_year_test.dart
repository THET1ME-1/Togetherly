import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/l10n/uk/daily_tasks.dart';
import 'package:love_app/l10n/zh/daily_tasks.dart';
import 'package:love_app/models/daily_task.dart';
import 'package:love_app/services/locale_service.dart';

/// Новогодний декабрь: свои задания на каждый день с 1 по 31 декабря, одни и
/// те же у всех пар, а обычная очередь до и после декабря не сбивается.
void main() {
  setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  group('набор декабря', () {
    test('31 день, в каждом три основных и бонус четырёх разных типов', () {
      expect(NewYearTasks.days.length, 31);
      for (var i = 0; i < 31; i++) {
        final day = NewYearTasks.days[i];
        expect(day.length, 4, reason: '${i + 1} декабря');
        expect(day.map((t) => t.type).toSet().length, 4,
            reason: '${i + 1} декабря');
      }
    });

    test('id и тексты не повторяются и не пересекаются с каталогом', () {
      final ids = NewYearTasks.all.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
      final regular = DailyTask.all.map((t) => t.id).toSet();
      expect(ids.where(regular.contains), isEmpty);
      final texts = NewYearTasks.all.map((t) => t.title('П')).toList();
      expect(texts.toSet().length, texts.length);
    });

    test('в общий каталог декабрь не попал: очередь пар не сдвинулась', () {
      expect(DailyTask.all.length, 400);
      expect(DailyTask.all.any((t) => t.id.startsWith('ny')), isFalse);
    });
  });

  group('выбор по дате', () {
    test('каждый день декабря — свой набор, одинаковый у разных пар', () {
      for (var d = 1; d <= 31; d++) {
        final date = DateTime.utc(2026, 12, d);
        final a = dailyTaskDayFor(day: date, pairId: 'g1');
        final b = dailyTaskDayFor(day: date, pairId: 'g2');
        final want = NewYearTasks.days[d - 1];
        expect(a.main.map((t) => t.id), want.take(3).map((t) => t.id));
        expect(a.bonus!.id, want[3].id);
        expect(b.main.map((t) => t.id), a.main.map((t) => t.id));
      }
    });

    test('следующий декабрь тот же', () {
      final a = dailyTaskDayFor(day: DateTime.utc(2027, 12, 31), pairId: 'g1');
      expect(a.main.first.id, NewYearTasks.days[30].first.id);
    });

    test('30 ноября и 1 января — обычная очередь', () {
      for (final date in [DateTime.utc(2026, 11, 30), DateTime.utc(2027, 1, 1)]) {
        final day = dailyTaskDayFor(day: date, pairId: 'g1');
        final ids = [...day.main, day.bonus!].map((t) => t.id);
        expect(ids.where((id) => id.startsWith('ny')), isEmpty, reason: '$date');
        expect(day.main.map((t) => t.type).toSet().length, 3);
      }
    });

    test('январь не повторяет обычные задания, выданные до декабря', () {
      final seen = <String>{};
      for (var d = DateTime.utc(2026, 9, 28);
          d.isBefore(DateTime.utc(2026, 12, 1));
          d = d.add(const Duration(days: 1))) {
        final day = dailyTaskDayFor(day: d, pairId: 'g5');
        seen.addAll([...day.main, day.bonus!].map((t) => t.id));
      }
      final jan = dailyTaskDayFor(day: DateTime.utc(2027, 1, 1), pairId: 'g5');
      expect([...jan.main, jan.bonus!].map((t) => t.id).where(seen.contains),
          isEmpty);
    });
  });

  group('подпись и перевод', () {
    test('ответ на задание декабря подписывается в ленте', () {
      expect(DailyTask.byId('ny31_clip'), isNotNull);
      expect(dailyTaskTitleOf('ny31_clip', 'Лера'),
          'Поздравление Лера с Новым годом');
    });

    test('украинский и китайский переводят весь декабрь, имя на месте', () {
      final broken = <String>[];
      for (final task in NewYearTasks.all) {
        final hasName = task.title('ZZ').contains('ZZ');
        for (final (lang, table) in [('uk', kDailyTasksUk), ('zh', kDailyTasksZh)]) {
          final tr = table[task.id];
          if (tr == null) {
            broken.add('$lang ${task.id}: нет перевода');
          } else if (hasName != tr.contains('{p}')) {
            broken.add('$lang ${task.id}: {p}');
          }
        }
      }
      expect(broken, isEmpty, reason: broken.take(10).join('\n'));
    });
  });
}
