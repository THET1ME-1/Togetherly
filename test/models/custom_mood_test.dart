import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/custom_mood.dart';
import 'package:love_app/models/mood_band.dart';

void main() {
  group('CustomMood → MoodOption', () {
    test('своя эмоция встаёт в сетку наравне со встроенными', () {
      const mood = CustomMood(
        id: 'rec1',
        groupId: 'g1',
        authorUid: 'u1',
        moodId: 'custom_ab12cd34',
        label: 'Дожил до пятницы',
        emoji: '🎉',
        imageUrl: 'https://togetherly.duckdns.org/api/files/custom/rec1/f.png',
        score: 5,
      );

      final option = mood.toMoodOption();

      expect(option.id, 'custom_ab12cd34');
      expect(option.imagePath, mood.imageUrl);
      expect(option.localizedLabel, 'Дожил до пятницы');
      expect(option.score, 5);
      // Разделы сетки считаются по тому же баллу, что у встроенных.
      expect(bandOfScore(option.score), MoodBand.bright);
    });

    test('балл держится в границах шкалы', () {
      // Шкала 1…5 общая со статистикой и достижениями: балл вне её сломал бы
      // разбивку сетки на разделы.
      expect(CustomMood.clampScore(0), 1);
      expect(CustomMood.clampScore(9), 5);
      expect(CustomMood.clampScore(3), 3);
    });

    test('цвет берётся от балла, а не задаётся руками', () {
      const sad = CustomMood(
        id: 'r', groupId: 'g', authorUid: 'u', moodId: 'custom_1',
        label: 'Тоска', emoji: '', imageUrl: 'https://x/y.png', score: 1,
      );
      const glad = CustomMood(
        id: 'r', groupId: 'g', authorUid: 'u', moodId: 'custom_2',
        label: 'Радость', emoji: '', imageUrl: 'https://x/z.png', score: 5,
      );

      expect(sad.toMoodOption().color, isNot(glad.toMoodOption().color));
    });
  });

  group('CustomMood.fromMap', () {
    test('запись PocketBase разбирается в модель', () {
      final mood = CustomMood.fromMap(
        {
          'id': 'rec9',
          'group_id': 'g7',
          'author_uid': 'u3',
          'mood_id': 'custom_zz99',
          'label': 'Наелся',
          'emoji': '🍔',
          'image': 'burger.png',
          'score': 4,
        },
        fileUrl: (id, file) => 'https://host/api/files/custom_moods/$id/$file',
      );

      expect(mood.moodId, 'custom_zz99');
      expect(mood.imageUrl, 'https://host/api/files/custom_moods/rec9/burger.png');
      expect(mood.score, 4);
    });

    test('запись без картинки не роняет разбор', () {
      final mood = CustomMood.fromMap(
        {'id': 'r', 'group_id': 'g', 'mood_id': 'custom_1', 'label': 'Так себе'},
        fileUrl: (id, file) => 'https://host/$id/$file',
      );

      expect(mood.imageUrl, '');
      expect(mood.score, 3); // без балла настроение считается ровным
    });
  });

  group('CustomMood.newMoodId', () {
    test('идентификатор помечен как свой и не повторяется', () {
      final a = CustomMood.newMoodId();
      final b = CustomMood.newMoodId();

      expect(a.startsWith('custom_'), isTrue);
      expect(a.length, greaterThan(10));
      expect(a, isNot(b));
    });

    test('своё настроение узнаётся по идентификатору', () {
      expect(CustomMood.isCustom('custom_ab12'), isTrue);
      expect(CustomMood.isCustom('happy'), isFalse);
    });
  });
}
