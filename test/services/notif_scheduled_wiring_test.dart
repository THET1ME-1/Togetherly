import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Свои уведомления по расписанию видом «А»: плагин рисует запланированное
/// сам, мимо обложки, поэтому эти службы обязаны ставить расписание через
/// `NotifRenderer.schedule` (на Android — `NotifAlarm`) и снимать через
/// `NotifRenderer.cancelScheduled`, иначе уведомление выйдет прежним видом,
/// а отмена не снимет своё.
void main() {
  const services = {
    'lib/services/capsule_notification_service.dart': 'capsule',
    'lib/services/celebration_notification_service.dart': 'celebration',
    'lib/services/mascot_inactivity_notification_service.dart': 'mascot_miss',
    'lib/services/invite_reminder_service.dart': 'invite',
    'lib/services/days_together_notification_service.dart': 'days',
  };

  for (final entry in services.entries) {
    test('${entry.key}: расписание через NotifRenderer, вид ${entry.value}', () {
      final src = File(entry.key).readAsStringSync();
      expect(src, isNot(contains('_plugin.zonedSchedule(')), reason: 'прямая постановка плагином');
      expect(src, isNot(contains('_plugin.cancel(')), reason: 'прямая отмена плагином');
      expect(src, contains('NotifRenderer.schedule('));
      expect(src, contains("kind: '${entry.value}'"));
    });
  }

  test('«Дни вместе»: плашка знает число на каждый день вперёд', () {
    // Прежний ежедневный повтор плагина показывал одно и то же число, пока
    // приложение не открыли.
    final src = File('lib/services/days_together_notification_service.dart').readAsStringSync();
    expect(src, contains('daily: true'));
    expect(src, contains('dailyTitles: titles'));
    expect(src, isNot(contains('matchDateTimeComponents')));
  });

  test('виды своих уведомлений знает сборщик обложки', () {
    final cover = File('lib/models/push_cover.dart').readAsStringSync();
    for (final kind in services.values) {
      expect(cover, contains("case '$kind':"), reason: kind);
    }
  });
}
