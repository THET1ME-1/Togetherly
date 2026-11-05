/// Звания за часы в приложении (05.11.2026).
///
/// У каждого человека свои часы: сервер копит секунды, пока приложение на
/// экране (`/api/user/app-time`). Звание — номер ступени 0…13, эмблема лежит
/// в каталоге записью `rank_<номер>`. Пороги приходят полем
/// `app_config.rank_hours` и правятся без релиза; здесь запасные.
library;

/// Пороги ступеней в часах: Искра, Знакомство, Симпатия, Свидания,
/// Влюблённость, Пара, Неразлучные, Опора, Родные души, Серебряная пара,
/// Золотая пара, Легенда, Звёздная пара, Навсегда.
const List<num> kRankHours = [0, 1, 3, 6, 10, 15, 25, 40, 60, 90, 130, 180, 250, 365];

/// Пороги из `app_config`. Ступеней ровно столько, сколько эмблем, первая — с
/// нуля, дальше строго по возрастанию; иначе — запасные.
List<num> parseRankHours(Object? raw) {
  if (raw is! List || raw.length != kRankHours.length) return kRankHours;
  final out = <num>[];
  for (final v in raw) {
    if (v is! num || !v.isFinite || v < 0) return kRankHours;
    if (out.isNotEmpty && v <= out.last) return kRankHours;
    out.add(v);
  }
  return out.first == 0 ? out : kRankHours;
}

/// Номер звания по накопленным секундам.
int rankFor(int seconds, List<num> hours) {
  var rank = 0;
  for (var i = 0; i < hours.length; i++) {
    if (seconds >= hours[i] * 3600) rank = i;
  }
  return rank;
}

class RankProgress {
  const RankProgress(this.rank, this.next, this.fraction, this.leftSeconds);

  final int rank;

  /// Следующее звание; null — уже последнее.
  final int? next;

  /// Доля пути до следующего звания, 0…1.
  final double fraction;
  final int leftSeconds;
}

RankProgress progressOf(int seconds, List<num> hours) {
  final rank = rankFor(seconds, hours);
  if (rank >= hours.length - 1) return RankProgress(rank, null, 1, 0);
  final from = hours[rank] * 3600, to = hours[rank + 1] * 3600;
  final left = (to - seconds).ceil();
  return RankProgress(rank, rank + 1, ((seconds - from) / (to - from)).clamp(0, 1).toDouble(), left);
}
