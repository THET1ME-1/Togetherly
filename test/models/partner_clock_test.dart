import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/models/partner_clock.dart';
import 'package:love_app/utils/pair_time.dart';

/// Время партнёра в шапке чата (TOG-48): пояс лежит в поле `data` записи
/// виджета, подпись видна только при разных поясах.
void main() {
  group('пояс в поле data', () {
    test('читается строкой ±HH:MM', () {
      expect(zoneFromData({'zone': '+05:00'}), '+05:00');
      expect(zoneFromData({'zone': '-03:30'}), '-03:30');
    });

    test('мусор и пустота — пояса нет', () {
      expect(zoneFromData(null), isNull);
      expect(zoneFromData({}), isNull);
      expect(zoneFromData({'zone': ''}), isNull);
      expect(zoneFromData({'zone': 'Europe/Kyiv'}), isNull);
      expect(zoneFromData({'zone': 180}), isNull);
    });

    test('запись пояса не трогает занятие и заметку', () {
      final data = withZone({'doing': {'id': 'sleep'}, 'note': 'привет'}, '+03:00');
      expect(data['doing'], {'id': 'sleep'});
      expect(data['note'], 'привет');
      expect(data['zone'], '+03:00');
    });

    test('имя пояса ложится рядом, по нему сервер шлёт напоминания дат', () {
      final data = withZone({'note': 'привет'}, '+02:00', name: 'Europe/Kyiv');
      expect(data['zone'], '+02:00');
      expect(data[kZoneNameKey], 'Europe/Kyiv');
      expect(zoneNameFromData(data), 'Europe/Kyiv');
      expect(withZone({}, '+02:00').containsKey(kZoneNameKey), isFalse);
      expect(zoneNameFromData({'tzn': ''}), isNull);
      expect(zoneNameFromData({'tzn': 5}), isNull);
    });
  });

  group('часы партнёра', () {
    final now = DateTime.now();
    final mine = PairTime.zoneOf(now.timeZoneOffset);

    test('в одном поясе подписи нет', () {
      expect(partnerClock(mine, now: now), isNull);
    });

    test('без пояса подписи нет', () {
      expect(partnerClock(null, now: now), isNull);
    });

    test('в другом поясе — его часы', () {
      final other = now.timeZoneOffset + const Duration(hours: 5);
      final there = now.toUtc().add(other);
      final want = '${there.hour.toString().padLeft(2, '0')}:${there.minute.toString().padLeft(2, '0')}';
      expect(partnerClock(PairTime.zoneOf(other), now: now), want);
    });

    test('полчаса разницы тоже считаются', () {
      final other = now.timeZoneOffset + const Duration(minutes: 30);
      expect(partnerClock(PairTime.zoneOf(other), now: now), isNotNull);
    });
  });

  test('подпись по роду, и у каждой строки есть все языки', () {
    expect(partnerClockKey('female'), 'chatPartnerClockF');
    expect(partnerClockKey('male'), 'chatPartnerClockM');
    expect(partnerClockKey(''), 'chatPartnerClockX');
    for (final key in ['chatPartnerClockF', 'chatPartnerClockM', 'chatPartnerClockX']) {
      for (final lang in ['ru', 'en', 'de', 'fr', 'es', 'it', 'pt', 'uk', 'zh']) {
        expect(kStrings[key]?[lang], contains('{t}'), reason: '$key/$lang');
      }
    }
  });
}
