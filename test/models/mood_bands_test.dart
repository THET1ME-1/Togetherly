import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mood_band.dart';
import 'package:love_app/models/mood_entry.dart';

void main() {
  test('классический пак раскладывается на четыре раздела по порядку', () {
    final sections = groupMoodsByBand(MoodOption.all);
    expect(sections.map((s) => s.band).toList(), [
      MoodBand.bright,
      MoodBand.even,
      MoodBand.sad,
      MoodBand.heavy,
    ]);
  });

  test('ни одно настроение не теряется и не дублируется', () {
    final sections = groupMoodsByBand(MoodOption.all);
    final flat = sections.expand((s) => s.moods).toList();
    expect(flat.length, MoodOption.all.length);
    expect(flat.map((m) => m.id).toSet(), MoodOption.all.map((m) => m.id).toSet());
  });

  test('порядок внутри раздела повторяет порядок пака', () {
    final bright = groupMoodsByBand(MoodOption.all)
        .firstWhere((s) => s.band == MoodBand.bright)
        .moods
        .map((m) => m.id)
        .toList();
    expect(bright.take(4).toList(), ['happy', 'love', 'kiss', 'laugh']);
  });

  test('пустые разделы не показываем', () {
    final onlyHappy =
        MoodOption.all.where((m) => m.id == 'happy').toList();
    final sections = groupMoodsByBand(onlyHappy);
    expect(sections.length, 1);
    expect(sections.single.band, MoodBand.bright);
  });

  test('розовый пак тоже раскладывается целиком', () {
    final sections = groupMoodsByBand(MoodOption.pinkPack);
    final flat = sections.expand((s) => s.moods).toList();
    expect(flat.length, MoodOption.pinkPack.length);
  });

  test('шкала настроения ложится на разделы без дыр', () {
    expect(bandOfScore(5), MoodBand.bright);
    expect(bandOfScore(4), MoodBand.bright);
    expect(bandOfScore(3), MoodBand.even);
    expect(bandOfScore(2), MoodBand.sad);
    expect(bandOfScore(1), MoodBand.heavy);
  });
}
