import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/models/mood_vessel.dart';
import 'package:love_app/models/vessel_sharing.dart';

/// Картинку сосуда пара выкладывает в сторис, и что в неё войдёт, решает
/// человек: галочки на экране экспорта. Здесь — как выбор превращается в
/// кладку.
final _day = DateTime(2026, 8, 1);

VesselDay _full() => VesselDay(
      date: _day,
      mineMood: const Color(0xFFFF7E8B),
      partnerMood: const Color(0xFF4CC38A),
      chatted: true,
      intimacy: true,
      period: true,
      partnerPeriod: true,
      memories: const [MemoryType.photo, MemoryType.music],
    );

void main() {
  test('снятая галочка убирает свой этаж', () {
    final out = vesselForSharing([_full()], show: {
      VesselFloor.mine,
      VesselFloor.partner,
    });
    final d = out.single;
    expect(d.mineMood, isNotNull);
    expect(d.partnerMood, isNotNull);
    expect(d.chatted, isFalse);
    expect(d.intimacy, isFalse);
    expect(d.period, isFalse);
    expect(d.memories, isEmpty);
  });

  test('свой и партнёрский цикл выбираются вместе', () {
    final out = vesselForSharing([_full()], show: {VesselFloor.cycle});
    expect(out.single.period, isTrue);
    expect(out.single.partnerPeriod, isTrue);
  });

  test('всё выбрано — кладка та же, что на экране', () {
    final out = vesselForSharing([_full()], show: VesselFloor.values.toSet());
    expect(out.single.floors, _full().floors);
  });

  test('день, у которого сняли всё, становится щербиной', () {
    final out = vesselForSharing([_full()], show: const {});
    expect(out.single.isEmpty, isTrue);
  });

  test('высота года пересчитывается, а не остаётся от снятых отметок', () {
    final year = VesselDay(
      date: _day,
      mineMood: const Color(0xFFFF7E8B),
      intimacy: true,
      floorsOverride: 9,
    );
    final out = vesselForSharing([year], show: {VesselFloor.mine});
    expect(out.single.floors, lessThan(9));
  });

  test('умолчание экрана: интимное не отмечено, остальное отмечено', () {
    expect(kDefaultSharedFloors, contains(VesselFloor.mine));
    expect(kDefaultSharedFloors, contains(VesselFloor.chat));
    expect(kDefaultSharedFloors, contains(VesselFloor.memory));
    expect(kDefaultSharedFloors, isNot(contains(VesselFloor.cycle)));
    expect(kDefaultSharedFloors, isNot(contains(VesselFloor.intimacy)));
  });
}
