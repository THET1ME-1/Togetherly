import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Цвет, найденный на снимке, и его заметность (сколько пикселей он занял).
@immutable
class SeedCandidate {
  final Color color;
  final int weight;

  const SeedCandidate(this.color, this.weight);
}

/// Насколько цвет должен быть насыщен, чтобы считаться живым, а не серым.
const double _kLivelyChroma = 12;

/// Ближе этого по оттенку и светлоте два цвета в ряду кружков неразличимы.
const double _kSameHue = 12;
const double _kSameTone = 12;

/// Ряд цветов, из которых человек выбирает свой.
///
/// Живые цвета идут первыми по заметности на кадре, серые — за ними: на
/// фотографии серого почти всегда больше всего (асфальт, стена, тень), и без
/// этого правила первым кандидатом у каждого второго снимка выходила бы
/// бетонная тема. Совсем серое не выбрасывается — иначе чёрно-белому кадру
/// нечего было бы предложить.
List<Color> pickSeedCandidates(List<SeedCandidate> found, {int limit = 6}) {
  final lively = <SeedCandidate>[];
  final dull = <SeedCandidate>[];
  for (final c in found) {
    final hct = Hct.fromInt(c.color.toARGB32());
    (hct.chroma >= _kLivelyChroma ? lively : dull).add(c);
  }
  int byWeight(SeedCandidate a, SeedCandidate b) => b.weight.compareTo(a.weight);
  lively.sort(byWeight);
  dull.sort(byWeight);

  final out = <Color>[];
  final taken = <Hct>[];
  for (final c in [...lively, ...dull]) {
    if (out.length == limit) break;
    final hct = Hct.fromInt(c.color.toARGB32());
    final duplicate = taken.any((t) =>
        _hueGap(t.hue, hct.hue) < _kSameHue &&
        (t.tone - hct.tone).abs() < _kSameTone);
    if (duplicate) continue;
    taken.add(hct);
    out.add(c.color);
  }
  return out;
}

/// Расстояние по кругу оттенков: 350° и 10° различаются на двадцать градусов,
/// а не на триста сорок.
double _hueGap(double a, double b) {
  final diff = (a - b).abs() % 360;
  return diff > 180 ? 360 - diff : diff;
}
