// Баланс наград за рекламу живёт в двух местах: константы клиента
// (lib/models/ad_grants.dart) и словарь RULES серверного хука
// (pocketbase/pb_hooks/coins.pb.js). Разъезд ничем себя не выдаёт — кнопка
// нажимается, сервер молча отвечает отказом, человек видит «не сработало».
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/ad_grants.dart';

void main() {
  final hook = File('pocketbase/pb_hooks/coins.pb.js').readAsStringSync();

  test('Цена награды в просмотрах совпадает с хуком', () {
    final rules = hook.substring(
      hook.indexOf('const RULES'),
      hook.indexOf('const TRIAL_THEMES'),
    );

    for (final kind in AdGrantKind.values) {
      final key = adGrantKey(kind);
      final m = RegExp('$key:\\s*\\{\\s*views:\\s*(\\d+)').firstMatch(rules);
      expect(m, isNotNull, reason: 'в хуке нет правила для $key');
      expect(int.parse(m!.group(1)!), kAdGrantViews[kind],
          reason: 'цена $key разошлась между клиентом и сервером');
    }
  });

  test('Сроки и кулдаун совпадают с хуком', () {
    final rules = hook.substring(
      hook.indexOf('const RULES'),
      hook.indexOf('const TRIAL_THEMES'),
    );

    for (final kind in AdGrantKind.values) {
      final key = adGrantKey(kind);
      final days = RegExp('$key:.*?days:\\s*(\\d+)').firstMatch(rules);
      final cooldown =
          RegExp('$key:.*?cooldownDays:\\s*(\\d+)').firstMatch(rules);
      expect(days, isNotNull, reason: 'в хуке нет срока для $key');
      expect(cooldown, isNotNull, reason: 'в хуке нет кулдауна для $key');
      expect(int.parse(days!.group(1)!), kAdGrantDuration[kind]!.inDays,
          reason: 'срок $key разошёлся');
      expect(int.parse(cooldown!.group(1)!), kAdGrantCooldown[kind]!.inDays,
          reason: 'кулдаун $key разошёлся');
    }
  });

  test('Общий потолок просмотров один на клиенте и сервере', () {
    expect(hook.contains('VIEW_CAP = $kAdDailyViewCap'), isTrue,
        reason: 'потолок просмотров в хуке не равен kAdDailyViewCap');
    // Монетная награда черпает из того же счётчика — иначе потолок обходится.
    expect(hook.contains('ad_views_today'), isTrue);
  });

  test('Витрина проб одинакова с обеих сторон', () {
    final trial = hook.substring(hook.indexOf('const TRIAL_THEMES'));
    final ids = RegExp(r'TRIAL_THEMES = \[([\d,\s]+)\]').firstMatch(trial);
    expect(ids, isNotNull, reason: 'в хуке нет списка витринных тем');
    final hookThemes = ids!
        .group(1)!
        .split(',')
        .map((s) => int.parse(s.trim()))
        .toSet();
    expect(hookThemes, kAdTrialThemes,
        reason: 'набор витринных тем разошёлся между клиентом и сервером');
  });

  test('Togetherly+ за рекламу не выдаётся ни в каком виде', () {
    final grantRoute = hook.substring(hook.indexOf('/api/coins/ad-grant'));
    final body = grantRoute.substring(0, grantRoute.indexOf('requireAuth'));
    expect(body.contains('"plus"'), isFalse);
    expect(body.contains("set(\"plus\""), isFalse);
    expect(body.contains('owned_themes'), isFalse,
        reason: 'проба не имеет права записывать владение навсегда');
  });
}
