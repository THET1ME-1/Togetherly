import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/cycle_entry.dart';
import 'package:love_app/services/cycle_service.dart';

/// Правило доступа к чужому циклу.
///
/// Платит та, кто ведёт календарь: Togetherly+ нужен, чтобы СТАВИТЬ отметки.
/// Партнёру, которому она разрешила их видеть, своя подписка не нужна — показ
/// входит в её покупку, ровно как купленный маскот открывается обоим. В паре
/// из двух девушек это значит, что каждая покупает Плюс под свой календарь, но
/// цикл другой видит бесплатно.
void main() {
  CycleEntry period(DateTime day) => CycleEntry(
        id: day.toIso8601String(),
        day: day,
        kind: CycleKind.period,
        shared: true,
      );

  /// Два цикла по 28 дней — минимум, на котором считается прогноз.
  List<CycleEntry> twoCycles() {
    final start = DateTime(2026, 6, 1);
    return [
      for (final shift in [0, 1, 2, 28, 29, 30, 56, 57])
        period(start.add(Duration(days: shift))),
    ];
  }

  group('цикл партнёрши', () {
    test('виден, когда отметок хватило на прогноз', () {
      expect(CycleService.partnerCycleVisible(twoCycles()), isTrue);
    });

    test('не виден, пока отметок на прогноз не хватает', () {
      expect(
        CycleService.partnerCycleVisible([period(DateTime(2026, 6, 1))]),
        isFalse,
      );
    });

    test('не виден, когда партнёрша не делится отметками', () {
      expect(CycleService.partnerCycleVisible(const []), isFalse);
    });

    test('решение не зависит от подписки смотрящего', () {
      // Функция не трогает PlusService вовсе: ответ определяют только отметки
      // владелицы. Если бы зависимость появилась, тест упал бы на обращении к
      // несобранному синглтону — здесь его никто не поднимал.
      final entries = twoCycles();
      expect(CycleService.partnerCycleVisible(entries), isTrue);
    });
  });
}
