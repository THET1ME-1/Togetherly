import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/custom_mood.dart';
import 'package:love_app/models/mood_entry.dart';
import 'package:love_app/models/mood_summary.dart';

// Своё настроение пары, отмеченное «Светлое», в кольце календаря считалось
// тёмным и подписывалось голым id (обращение 550, 01.11.2026): поиск по id
// знал только встроенные и каталожные настроения.
void main() {
  final cat = CustomMood.fromMap({
    'id': 'rec1',
    'group_id': 'g1',
    'author_uid': 'u1',
    'mood_id': 'custom_e0dkgabc',
    'label': 'Бебебябя',
    'score': 5,
  }, fileUrl: (id, file) => '');

  tearDown(() => MoodOption.registerCustomMoods(const []));

  test('своё светлое настроение считается светлым', () {
    MoodOption.registerCustomMoods([cat.toMoodOption()]);
    final summary = MoodSummary.of({'custom_e0dkgabc': 1});
    expect(summary.brightPercent, 100);
  });

  test('у своего настроения в кольце его название, а не id', () {
    MoodOption.registerCustomMoods([cat.toMoodOption()]);
    final summary = MoodSummary.of({'custom_e0dkgabc': 1});
    expect(summary.slices.single.option?.label, 'Бебебябя');
  });

  test('встроенные настроения находятся по-прежнему', () {
    MoodOption.registerCustomMoods([cat.toMoodOption()]);
    expect(MoodOption.byId('happy')?.score, 5);
  });
}
