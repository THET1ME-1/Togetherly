import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/ailment.dart';

/// Цвет недомогания говорит, насколько плохо — ровно как у настроений тир
/// говорит, насколько хорошо. Обводка ничего не сообщала: все шестнадцать
/// чипов выглядели одинаково, и «Температура» читалась как «Аллергия».
void main() {
  group('AilmentSeverity', () {
    test('у каждой болячки есть тяжесть', () {
      for (final a in kAilments) {
        expect(a.severity, isNotNull, reason: a.id);
      }
    });

    test('температура и общее недомогание — тяжёлые', () {
      expect(ailmentById('fever')!.severity, AilmentSeverity.hard);
      expect(ailmentById('unwell')!.severity, AilmentSeverity.hard);
    });

    test('усталость и аллергия — лёгкие', () {
      expect(ailmentById('fatigue')!.severity, AilmentSeverity.light);
      expect(ailmentById('allergy')!.severity, AilmentSeverity.light);
    });

    test('боль посередине', () {
      expect(ailmentById('throat')!.severity, AilmentSeverity.medium);
      expect(ailmentById('back')!.severity, AilmentSeverity.medium);
    });

    test('чем тяжелее, тем краснее', () {
      // Красный канал растёт, зелёный падает: от тёплого жёлтого к красному.
      final light = AilmentSeverity.light.color;
      final medium = AilmentSeverity.medium.color;
      final hard = AilmentSeverity.hard.color;
      expect(medium.g, lessThan(light.g));
      expect(hard.g, lessThan(medium.g));
    });

    test('уровни различимы между собой', () {
      final colors = AilmentSeverity.values.map((s) => s.color).toSet();
      expect(colors.length, AilmentSeverity.values.length);
    });
  });
}
