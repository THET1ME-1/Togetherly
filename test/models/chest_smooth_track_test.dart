import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chest.dart';
import 'package:love_app/services/chest_sound.dart';
import 'package:love_app/widgets/chest/chest_prize_image.dart';

/// TOG-70: плавное открытие главного сундука, кадр 30 мс вместо 60.
///
/// Дорожка приза зашита в код под свой файл, и кадры обязаны означать то же
/// время, что в прежней: приз выходит около 1,4 с, весь путь 3,8 с, а вершина
/// та же, иначе приз на карточке и на экране разъедется по размеру.
void main() {
  int firstSpot(List<List<double>?> track) => track.indexWhere((s) => s != null);

  test('плавная дорожка покрывает те же 3,8 с открытия', () {
    expect(kChestPrizeTrack2.length * kChestFrameMs2, closeTo(kChestPrizeTrack.length * kChestFrameMs, kChestFrameMs));
  });

  test('приз выходит в то же время, что в прежней дорожке', () {
    final was = firstSpot(kChestPrizeTrack) * kChestFrameMs;
    final now = firstSpot(kChestPrizeTrack2) * kChestFrameMs2;
    expect((was - now).abs(), lessThanOrEqualTo(kChestFrameMs));
  });

  test('вершина подъёма та же', () {
    expect(ChestPrizeFlight.trackPeak(kChestPrizeTrack2), closeTo(ChestPrizeFlight.trackPeak(kChestPrizeTrack), 1e-6));
  });

  test('в петле приз начинает с последней точки и покачивается не дальше макета', () {
    final last = kChestPrizeTrack2.last!;
    const end = 3.78;
    expect(chestHoldSpot(last, endSeconds: end, seconds: end), last);
    var lo = 1.0, hi = 0.0;
    for (var t = end; t < end + 4; t += 0.03) {
      final y = chestHoldSpot(last, endSeconds: end, seconds: t)[1];
      lo = math.min(lo, y);
      hi = math.max(hi, y);
    }
    expect(hi - lo, closeTo(4 / 116, 0.002), reason: 'размах 2·sin, как на макете');
  });

  test('отдача на замке и призе по времени, а не по номеру кадра', () {
    expect(ChestSound.lockMs ~/ kChestFrameMs2, 30);
    expect(ChestSound.wonMs ~/ kChestFrameMs2, 66);
    expect(ChestSound.lockFrame, ChestSound.lockMs ~/ kChestFrameMs);
  });
}
