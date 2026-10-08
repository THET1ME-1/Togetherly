import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/season_backdrop.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

Map<String, dynamic> _row({Map<String, dynamic>? data, String kind = 'backdrop'}) => {
  'id': 'backdrop_hw',
  'kind': kind,
  'data': data ??
      {
        'key': 'hw',
        'from': '2026-10-08',
        'until': '2026-11-01',
        'cycleMs': 16000,
        'inMs': 4000,
        'holdMs': 5000,
        'outMs': 4000,
        'blur': 14,
        'light': {'tone': 15, 'chroma': 40, 'opacity': 0.78},
        'dark': {'tone': 88, 'chroma': 22, 'opacity': 0.42},
        'files': {'mask': 'https://x/mask.webp', 'blur': 'https://x/blur.webp', 'hand': 'https://x/hand.webp'},
      },
};

void main() {
  group('разбор записи каталога', () {
    test('полная запись', () {
      final b = SeasonBackdrop.fromCatalog(_row())!;
      expect(b.key, 'hw');
      expect(b.maskUrl, 'https://x/mask.webp');
      expect(b.handUrl, 'https://x/hand.webp');
      expect(b.blurUrl, 'https://x/blur.webp');
      expect(b.cycleMs, 16000);
      expect(b.blur, 14);
      expect(b.light.opacity, 0.78);
      expect(b.dark.tone, 88);
    });

    test('чужой вид, нет картинки или ключа — null, а не падение', () {
      expect(SeasonBackdrop.fromCatalog(_row(kind: 'chest')), isNull);
      expect(SeasonBackdrop.fromCatalog(_row(data: {'key': 'hw', 'until': '2026-11-01', 'files': {}})), isNull);
      expect(SeasonBackdrop.fromCatalog(_row(data: {'files': {'mask': 'm'}, 'until': '2026-11-01'})), isNull);
      expect(SeasonBackdrop.fromCatalog({'kind': 'backdrop', 'data': 'мусор'}), isNull);
    });

    test('кривые числа подменяются умолчаниями, фазы влезают в петлю', () {
      final b = SeasonBackdrop.fromCatalog(_row(data: {
        'key': 'hw',
        'until': '2026-11-01',
        'cycleMs': 3000,
        'inMs': 'много',
        'holdMs': 9000,
        'files': {'mask': 'm'},
      }))!;
      expect(b.inMs + b.holdMs + b.outMs, lessThanOrEqualTo(b.cycleMs));
      expect(b.light.opacity, inInclusiveRange(0, 1));
      expect(b.handUrl, isNull);
    });
  });

  group('даты по часам человека, until не включая', () {
    final b = SeasonBackdrop.fromCatalog(_row())!;
    test('до, во время, в последний день и после', () {
      expect(b.isOn(DateTime(2026, 10, 7, 23, 59)), isFalse);
      expect(b.isOn(DateTime(2026, 10, 8, 0, 1)), isTrue);
      expect(b.isOn(DateTime(2026, 10, 31, 23, 59)), isTrue);
      expect(b.isOn(DateTime(2026, 11, 1, 0, 0)), isFalse);
    });
    test('без начала — с любого дня до конца; без конца — не показываем', () {
      final noFrom = SeasonBackdrop.fromCatalog(_row(data: {'key': 'hw', 'until': '2026-11-01', 'files': {'mask': 'm'}}))!;
      expect(noFrom.isOn(DateTime(2020, 1, 1)), isTrue);
      final noUntil = SeasonBackdrop.fromCatalog(_row(data: {'key': 'hw', 'from': '2026-10-01', 'files': {'mask': 'm'}}))!;
      expect(noUntil.isOn(DateTime(2026, 10, 9)), isFalse);
    });
    test('из нескольких выбирается тот, что идёт сейчас', () {
      final other = SeasonBackdrop.fromCatalog(_row(data: {'key': 'ny', 'from': '2026-12-20', 'until': '2027-01-10', 'files': {'mask': 'm'}}))!;
      expect(SeasonBackdrop.activeOf([other, b], DateTime(2026, 10, 20))?.key, 'hw');
      expect(SeasonBackdrop.activeOf([other, b], DateTime(2026, 12, 25))?.key, 'ny');
      expect(SeasonBackdrop.activeOf([other, b], DateTime(2026, 11, 20)), isNull);
    });
  });

  group('петля появления', () {
    final b = SeasonBackdrop.fromCatalog(_row())!;
    test('начало — невидим и размыт, середина — чёткий, конец — пусто', () {
      final s = b.phaseAt(0);
      expect(s.opacity, 0);
      expect(s.blur, closeTo(14, 0.01));
      final mid = b.phaseAt(6000);
      expect(mid.opacity, 1);
      expect(mid.blur, 0);
      expect(mid.scale, 1);
      final gone = b.phaseAt(15000);
      expect(gone.opacity, 0);
    });
    test('проявление и уход монотонны, петля повторяется', () {
      double prev = -1;
      for (var t = 0; t <= 4000; t += 250) {
        final o = b.phaseAt(t).opacity;
        expect(o, greaterThanOrEqualTo(prev));
        prev = o;
      }
      prev = 2;
      for (var t = 9000; t <= 13000; t += 250) {
        final o = b.phaseAt(t).opacity;
        expect(o, lessThanOrEqualTo(prev));
        prev = o;
      }
      expect(b.phaseAt(16000 + 6000).opacity, b.phaseAt(6000).opacity);
    });
  });

  group('цвет от темы', () {
    final b = SeasonBackdrop.fromCatalog(_row())!;
    const pink = Color(0xFFFE7E8B);
    test('светлая тема — тёмная тень оттенка темы', () {
      final c = Hct.fromInt(b.tint(Brightness.light, pink).toARGB32());
      expect(c.tone, closeTo(15, 1.5));
      expect((c.hue - Hct.fromInt(pink.toARGB32()).hue).abs(), lessThan(8));
    });
    test('тёмная тема — светлое свечение того же оттенка', () {
      final c = Hct.fromInt(b.tint(Brightness.dark, pink).toARGB32());
      expect(c.tone, closeTo(88, 1.5));
      expect(b.opacity(Brightness.dark), 0.42);
    });
    test('явный цвет с сервера сильнее расчёта', () {
      final fixed = SeasonBackdrop.fromCatalog(_row(data: {
        'key': 'hw',
        'until': '2026-11-01',
        'files': {'mask': 'm'},
        'light': {'color': '#123456', 'opacity': 0.5},
      }))!;
      expect(fixed.tint(Brightness.light, pink), const Color(0xFF123456));
    });
  });
}
