import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';

/// Сезонная палитра (решение владельца 19.10.2026): «Хэллоуин» бесплатен
/// всем, кто пришёл в приложение до 1 ноября, и остаётся у них навсегда.
/// Пришедшим позже темы не видно до следующего Хэллоуина.
void main() {
  final hw = kPalettes.firstWhere((p) => p.name == 'Хэллоуин');
  DateTime at(int y, int m, int d) => DateTime.utc(y, m, d, 12);

  test('тема бесплатная и сезонная', () {
    expect(hw.isPremium, isFalse);
    expect(hw.price, 0);
    expect(hw.season, isNotNull);
  });

  test('в сезон открыта всем, даже тем, кто пришёл сегодня', () {
    final now = at(2026, 10, 25);
    expect(paletteOpen(hw, registeredAt: at(2026, 10, 25), now: now), isTrue);
    expect(paletteOpen(hw, registeredAt: null, now: now), isTrue);
  });

  test('после 1 ноября остаётся у пришедших до него', () {
    final now = at(2026, 11, 5);
    expect(paletteOpen(hw, registeredAt: at(2025, 3, 1), now: now), isTrue);
    expect(paletteOpen(hw, registeredAt: DateTime.utc(2026, 10, 31, 23, 59),
        now: now), isTrue);
    expect(paletteOpen(hw, registeredAt: DateTime.utc(2026, 11, 1, 0, 1),
        now: now), isFalse);
  });

  test('пришедший после сезона ждёт следующего Хэллоуина', () {
    final late = at(2026, 11, 3);
    expect(paletteOpen(hw, registeredAt: late, now: at(2027, 9, 30)), isFalse);
    expect(paletteOpen(hw, registeredAt: late, now: at(2027, 10, 1)), isTrue);
    // Застал Хэллоуин 2027 — тема остаётся и после него.
    expect(paletteOpen(hw, registeredAt: late, now: at(2027, 11, 20)), isTrue);
    expect(paletteOpen(hw, registeredAt: at(2027, 11, 2), now: at(2027, 11, 20)),
        isFalse);
  });

  test('до первого сезона темы не было ни у кого', () {
    expect(paletteOpen(hw, registeredAt: at(2024, 1, 1), now: at(2026, 9, 20)),
        isFalse);
  });

  test('неизвестная дата регистрации тему не отнимает', () {
    // Запись профиля иногда не поднимается с диска при живой сессии: лучше
    // показать тему лишний раз, чем отнять её у того, кто её застал.
    expect(paletteOpen(hw, registeredAt: null, now: at(2027, 3, 1)), isTrue);
  });

  test('обычные палитры открыты всегда', () {
    for (final p in kPalettes.where((p) => p.season == null)) {
      expect(
        paletteOpen(p, registeredAt: at(2030, 1, 1), now: at(2030, 1, 2)),
        isTrue,
        reason: p.name,
      );
    }
  });
}
