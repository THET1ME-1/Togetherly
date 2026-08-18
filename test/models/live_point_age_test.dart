import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/live_point_age.dart';

/// Правило подписи под меткой партнёра.
///
/// Жалоба, ради которой оно заведено: «партнёр не заходил два дня, и его метка
/// не сдвинулась». Метка и не могла сдвинуться — точка последняя известная, —
/// но карта об этом молчала.
void main() {
  const now = 1787000000000;
  int ago(Duration d) => now - d.inMilliseconds;

  test('только что снятая точка подписи не требует', () {
    final age = LivePointAge.of(ago(const Duration(seconds: 30)), nowMs: now);
    expect(age.unit, LivePointAgeUnit.fresh);
    expect(age.needsCaption, isFalse);
  });

  test('человек постоял на месте четверть часа — всё ещё молчим', () {
    final age = LivePointAge.of(ago(const Duration(minutes: 14)), nowMs: now);
    expect(age.needsCaption, isFalse);
  });

  test('через сорок минут подписываем минутами', () {
    final age = LivePointAge.of(ago(const Duration(minutes: 40)), nowMs: now);
    expect(age.unit, LivePointAgeUnit.minutes);
    expect(age.value, 40);
  });

  test('через три часа — часами', () {
    final age = LivePointAge.of(ago(const Duration(hours: 3)), nowMs: now);
    expect(age.unit, LivePointAgeUnit.hours);
    expect(age.value, 3);
  });

  test('жалоба про два дня', () {
    final age = LivePointAge.of(ago(const Duration(days: 2)), nowMs: now);
    expect(age.unit, LivePointAgeUnit.days);
    expect(age.value, 2);
    expect(age.needsCaption, isTrue);
  });

  test('час без минуты остаётся минутами, а не «0 часов»', () {
    final age = LivePointAge.of(ago(const Duration(minutes: 59)), nowMs: now);
    expect(age.unit, LivePointAgeUnit.minutes);
    expect(age.value, 59);
  });

  test('сутки без часа остаются часами', () {
    final age = LivePointAge.of(ago(const Duration(hours: 23)), nowMs: now);
    expect(age.unit, LivePointAgeUnit.hours);
    expect(age.value, 23);
  });

  test('часы партнёра убежали вперёд — точка считается свежей', () {
    // На проде такие точки есть: время ставит телефон автора.
    final age = LivePointAge.of(now + const Duration(hours: 5).inMilliseconds,
        nowMs: now);
    expect(age.unit, LivePointAgeUnit.fresh);
  });

  test('у старой записи времени может не быть вовсе', () {
    final age = LivePointAge.of(0, nowMs: now);
    expect(age.unit, LivePointAgeUnit.unknown);
    expect(age.needsCaption, isFalse);
  });
}
