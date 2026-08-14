// Устройства расширения не шире, чем у приложения.
//
// Вторая причина «виджетов нет в галерее», найденная 14.08.2026. Первая была
// про версию (расширению зашили 1.0), эта — про устройства: расширение
// собиралось для iPhone и iPad (`TARGETED_DEVICE_FAMILY = "1,2"`), а само
// приложение только для iPhone. Apple требует, чтобы список устройств
// расширения был подмножеством списка приложения; загрузку в App Store при
// этом пропускают, а iOS на телефоне расширение не активирует — Togetherly
// просто нет среди виджетов, и человек не понимает, что делать.
//
// Расхождение прожило со снапшота 1.16.3 до 1.28.2 незамеченным: до выхода в
// App Store виджеты на iPhone почти никто не пробовал.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final project =
      File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

  /// Блоки настроек сборки: `XXXX /* Release */ = { … };`
  Iterable<RegExpMatch> configs() => RegExp(
        r'\n\t\t[0-9A-F]{24} /\* (Debug|Release|Profile) \*/ = \{(.*?)\n\t\t\};',
        dotAll: true,
      ).allMatches(project);

  String? familyOf(String body) =>
      RegExp(r'TARGETED_DEVICE_FAMILY\s*=\s*"?([^";]+)"?;')
          .firstMatch(body)
          ?.group(1);

  test('расширение виджетов собирается под те же устройства, что приложение', () {
    final widgetFamilies = <String, String?>{};
    for (final m in configs()) {
      final body = m.group(2)!;
      if (!body.contains('com.togetherly.love.TogetherlyWidget')) continue;
      widgetFamilies[m.group(1)!] = familyOf(body);
    }

    expect(widgetFamilies, isNotEmpty,
        reason: 'таргет расширения пропал из проекта');

    for (final entry in widgetFamilies.entries) {
      expect(
        entry.value,
        '1',
        reason: 'конфигурация ${entry.key}: приложение собирается только под '
            'iPhone, и расширение обязано так же — иначе iOS его не '
            'активирует и виджетов не будет вовсе',
      );
    }
  });
}
