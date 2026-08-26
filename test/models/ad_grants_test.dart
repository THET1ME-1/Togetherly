import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/ad_grants.dart';

void main() {
  final now = DateTime.utc(2026, 8, 26, 12);

  test('Пустая строка даёт пустой набор без падения', () {
    expect(AdGrants.parse(null).isEmpty, isTrue);
    expect(AdGrants.parse('').isEmpty, isTrue);
    expect(AdGrants.parse('{сломано').isEmpty, isTrue);
    expect(AdGrants.parse('[1,2,3]').isEmpty, isTrue);
  });

  test('Активный грант темы виден до срока и пропадает после', () {
    final until = now.add(const Duration(days: 3)).millisecondsSinceEpoch;
    final g = AdGrants.parse('{"theme":{"id":16,"until":$until,"taken":0}}');
    expect(g.themeTrialId(now), 16);
    expect(g.themeTrialId(now.add(const Duration(days: 4))), isNull);
  });

  test('Проба темы берётся раз в четырнадцать дней', () {
    final taken = now.subtract(const Duration(days: 10)).millisecondsSinceEpoch;
    final g = AdGrants.parse('{"theme":{"id":9,"until":0,"taken":$taken}}');
    expect(g.canTake(AdGrantKind.theme, now), isFalse);
    expect(g.canTake(AdGrantKind.theme, now.add(const Duration(days: 5))), isTrue);
  });

  test('Награды без кулдауна берутся всегда', () {
    final taken = now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch;
    final g = AdGrants.parse('{"chat_bg":{"id":"dots","until":0,"taken":$taken}}');
    expect(g.canTake(AdGrantKind.chatBg, now), isTrue);
  });

  test('Проба даётся только витринным темам', () {
    expect(kAdTrialThemes, contains(16));
    expect(kAdTrialThemes.length, 4);
    expect(kAdTrialThemes.contains(0), isFalse);
  });

  test('Цены и сроки заданы по согласованному балансу', () {
    expect(kAdGrantViews[AdGrantKind.theme], 2);
    expect(kAdGrantViews[AdGrantKind.chatBg], 1);
    expect(kAdGrantViews[AdGrantKind.canvasBg], 1);
    expect(kAdGrantViews[AdGrantKind.widgetPhoto], 1);
    expect(kAdGrantDuration[AdGrantKind.theme], const Duration(days: 7));
    expect(kAdGrantCooldown[AdGrantKind.theme], const Duration(days: 14));
    expect(kAdDailyViewCap, 8);
  });

  test('Фон холста живёт до конца суток', () {
    final until = DateTime(2026, 8, 26, 23, 59, 59).millisecondsSinceEpoch;
    final g = AdGrants.parse('{"canvas_bg":{"id":"rain","until":$until,"taken":0}}');
    expect(g.activeFor(AdGrantKind.canvasBg, DateTime(2026, 8, 26, 20))?.id, 'rain');
    expect(g.activeFor(AdGrantKind.canvasBg, DateTime(2026, 8, 27, 1)), isNull);
  });

  test('Ключи наград совпадают в обе стороны', () {
    for (final kind in AdGrantKind.values) {
      expect(adGrantKindOf(adGrantKey(kind)), kind);
    }
    expect(adGrantKindOf('plus'), isNull);
  });

  test('Ответ сервера несёт срок только у кулдауна', () {
    expect(AdGrantResult.ok.kind, AdGrantOutcome.ok);
    expect(AdGrantResult.ok.days, 0);
    expect(AdGrantResult.cooldown(4).days, 4);
    expect(AdGrantResult.cooldown(4).kind, AdGrantOutcome.cooldown);
  });
}
