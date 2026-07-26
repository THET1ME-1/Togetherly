import 'mood_entry.dart';

/// Разделы, на которые разбита сетка настроений в пикере.
///
/// Двадцать с лишним мордочек одной сплошной сеткой ищутся плохо: глаз цепляется
/// за цвет, а не за смысл. Раскладываем их по той же шкале [MoodOption.score],
/// на которой держится статистика и календарь, — новой классификации не заводим.
enum MoodBand { bright, even, sad, heavy }

/// Настроения одного раздела в порядке пака.
class MoodBandSection {
  final MoodBand band;
  final List<MoodOption> moods;

  const MoodBandSection(this.band, this.moods);
}

/// Раздел по баллу настроения: 5–4 светлое, 3 ровное, 2 грусть, 1 тяжёлое.
MoodBand bandOfScore(int score) {
  if (score >= 4) return MoodBand.bright;
  if (score == 3) return MoodBand.even;
  if (score == 2) return MoodBand.sad;
  return MoodBand.heavy;
}

/// Разбивает пак на разделы. Порядок разделов фиксирован, порядок настроений
/// внутри повторяет пак; пустые разделы отбрасываем.
List<MoodBandSection> groupMoodsByBand(List<MoodOption> moods) {
  final buckets = <MoodBand, List<MoodOption>>{
    for (final b in MoodBand.values) b: <MoodOption>[],
  };
  for (final m in moods) {
    buckets[bandOfScore(m.score)]!.add(m);
  }
  return [
    for (final b in MoodBand.values)
      if (buckets[b]!.isNotEmpty) MoodBandSection(b, buckets[b]!),
  ];
}
