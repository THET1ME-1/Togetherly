// Половина виджета «Настроение» не остаётся пустой, когда данные есть.
//
// Связка Android — iOS, 17.08.2026: у неё на iPhone половина партнёра — пустой
// контур без подписи, у него на Android оба сердца залиты, а в самом приложении
// у обоих «Оценка 5 из 5». Главный экран брал настроение партнёра только из
// MoodService (записи за сегодня) и при пустом списке отправлял в виджет ноль,
// хотя последнее известное настроение лежало в widget_data — из него и рисуется
// превью на экране «Виджеты», отсюда и расхождение.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mood_entry.dart';
import 'package:love_app/models/mood_widget_payload.dart';

void main() {
  final known = MoodOption.registry.first;

  MoodEntry entryOf(MoodOption option) => MoodEntry(
    id: 'e1',
    moodId: option.id,
    imagePath: option.imagePath,
    label: option.label,
    timestamp: DateTime(2026, 8, 17, 12),
  );

  test('запись за сегодня главнее всего', () {
    final half = moodHalfPayload(
      entry: entryOf(known),
      widgetMoodEmoji: 'assets/moods/другое.png',
      widgetMoodLabel: 'Другое',
    );
    expect(half.imagePath, known.imagePath);
    expect(half.score, known.score);
    expect(half.label, isNotEmpty);
    expect(half.colorHex, startsWith('#'));
  });

  test('без записи оценка берётся из widget_data по картинке', () {
    final half = moodHalfPayload(
      widgetMoodEmoji: known.imagePath,
      widgetMoodLabel: known.label,
    );
    expect(half.score, known.score, reason: 'сердце должно залиться, как в приложении');
    expect(half.label, isNotEmpty);
    expect(half.colorHex, startsWith('#'));
  });

  test('незнакомая картинка оставляет подпись, но не врёт про оценку', () {
    final half = moodHalfPayload(
      widgetMoodEmoji: 'assets/moods/этого-нет-в-каталоге.png',
      widgetMoodLabel: 'Люблю',
    );
    expect(half.label, 'Люблю');
    expect(half.score, 0);
    expect(half.colorHex, isEmpty);
  });

  test('только подпись без картинки тоже доезжает', () {
    final half = moodHalfPayload(widgetMoodLabel: 'Смех');
    expect(half.label, 'Смех');
    expect(half.imagePath, isEmpty);
  });

  test('нет данных — пустая половина', () {
    final half = moodHalfPayload();
    expect(half.isEmpty, isTrue);
  });
}
