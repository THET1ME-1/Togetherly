// Виджет «Дней вместе» считает от той же даты, что и приложение.
//
// Жалоба 01.09.2026: на рабочем столе «9 дней» и 22.08.2026, в приложении —
// 196 дней и 17.02.2026. Человек: «это не наша дата и другой пол... такое уже
// второй раз происходит». Пара сошлась в приложении 22 августа, а вместе они с
// 17 февраля: 22.08 — дата коннекта, и виджет падал на неё всякий раз, когда
// таймеры ещё не загрузились.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/couple_days.dart';

void main() {
  final connect = DateTime(2026, 8, 22, 9, 15);
  final anniversary = DateTime(2026, 2, 17, 14, 54);
  final editedTimer = DateTime(2026, 2, 17, 9, 32);

  group('widgetDaysStart', () {
    test('таймеры не загрузились — считаем от годовщины, не от коннекта', () {
      final start = widgetDaysStart(
        systemTimerStart: null,
        groupStart: connect,
        anniversary: anniversary,
      );
      expect(start, anniversary);
    });

    test('правленый системный таймер сильнее коннекта', () {
      final start = widgetDaysStart(
        systemTimerStart: editedTimer,
        groupStart: connect,
        anniversary: anniversary,
      );
      expect(start, editedTimer);
    });

    test('пользовательский таймер показывается как есть', () {
      final custom = DateTime(2026, 12, 31);
      final start = widgetDaysStart(
        customTimerStart: custom,
        systemTimerStart: editedTimer,
        groupStart: connect,
        anniversary: anniversary,
      );
      expect(start, custom);
    });

    test('кроме коннекта нет ничего — остаётся он', () {
      expect(widgetDaysStart(groupStart: connect), connect);
    });

    test('дат нет вовсе — считать не от чего', () {
      expect(widgetDaysStart(), isNull);
    });

    test('счёт совпадает с приложением: 196 дней, а не 9', () {
      final now = DateTime(2026, 9, 1, 12);
      expect(
        coupleDaysTogether(
          timerStart: editedTimer,
          groupStart: connect,
          anniversary: anniversary,
          now: now,
        ),
        196,
      );
      // От даты коннекта выходит десяток дней — это и стояло на виджете.
      expect(now.difference(connect).inDays, lessThan(15));
    });
  });

  group('Сервис виджетов пользуется общим правилом', () {
    final src = File('lib/services/home_widget_service.dart').readAsStringSync();

    test('дата для «Дней вместе» идёт через widgetDaysStart', () {
      final start = src.indexOf('Future<void> _syncDaysCounterWithTimer(');
      expect(start, greaterThan(0));
      final body = src.substring(start, start + 2600);
      expect(body.contains('widgetDaysStart('), isTrue);
      expect(body.contains('coupleDaysTogether('), isTrue);
    });

    test('годовщина доезжает до синхронизации', () {
      expect(src.contains('DateTime? anniversary,'), isTrue);
      final home = File('lib/screens/home_screen.dart').readAsStringSync();
      expect(home.contains('anniversary: _pairData.anniversaryDate'), isTrue,
          reason: 'без неё виджет снова посчитает от даты коннекта');
    });
  });

  // Ночь 18.09.2026, iPhone: таймер пары 440, виджет «Дней вместе» рядом — 439.
  // Готовое число пишет только открытое приложение, поэтому после полуночи
  // виджет стоит на вчерашнем, пока его не откроют. Натив считает сам от
  // метки начала — так уже живут «Вместе», экран блокировки и кольцо года.
  group('«Дней вместе» считает день сам', () {
    test('приложение кладёт метку начала рядом с числом', () {
      final src =
          File('lib/services/home_widget_service.dart').readAsStringSync();
      expect(src.contains("'days_\${g}_start_ms'"), isTrue);
      final sync = src.indexOf('Future<void> syncDaysCounter(');
      expect(src.indexOf('_saveDaysStartMs(g, start)', sync), greaterThan(sync));
      final both = src.indexOf('Future<void> syncTimerAndDays(');
      expect(src.indexOf('_saveDaysStartMs(g,', both), greaterThan(both),
          reason: 'второй писатель числа тоже обязан обновить метку, '
              'иначе натив посчитает от прежней даты');
    });

    test('iPhone и Android читают метку, а число — только запасом', () {
      final swift = File('ios/TogetherlyWidget/DaysStreakStatsWidgets.swift')
          .readAsStringSync();
      expect(swift.contains('days_\\(g)_start_ms'), isTrue);
      expect(swift.contains('daysSince(startMs: startMs, now: now)'), isTrue);
      expect(swift.contains('DaysCounterWidgetView(now: entry.date)'), isTrue,
          reason: 'день считается на момент записи ленты, а не отрисовки');
      final kt = File(
        'android/app/src/main/kotlin/com/togetherly/love/'
        'DaysCounterWidgetProvider.kt',
      ).readAsStringSync();
      expect(kt.contains('days_\${g}_start_ms'), isTrue);
      expect(kt.contains('YearMath.from(startMs).daysTotal'), isTrue);
    });
  });
}
