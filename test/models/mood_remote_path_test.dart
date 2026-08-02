import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mood_entry.dart';

/// Перезаливка пака меняет имена файлов в PocketBase, а в отметке настроения
/// лежит абсолютный адрес картинки. Без пересчёта адреса вся история пары
/// начинает ссылаться на удалённые файлы — так «пропала» анимация пёсика на
/// главном экране и в календаре 2 августа.
void main() {
  const base = 'https://togetherly.duckdns.org/api/files/catalog_items';

  setUp(() {
    MoodOption.registerRemoteMoods(const [
      MoodOption(
        id: 'pride',
        imagePath: '$base/dog/pride_bl749l1ncg.webp',
        label: 'Гордость',
        color: Color(0xFFFFC800),
      ),
      MoodOption(
        id: 'no_emotion',
        imagePath: '$base/dog/no_emotion_qqqqqqqqqq.webp',
        label: 'Нет эмоций',
        color: Color(0xFF7A7FA8),
      ),
      MoodOption(
        id: 'pride',
        imagePath: '$base/moti/pride_zzzzzzzzzz.webp',
        label: 'Гордость',
        color: Color(0xFFFFC800),
      ),
    ]);
  });

  tearDown(() => MoodOption.registerRemoteMoods(const []));

  test('старый адрес заменяется свежим из того же пака', () {
    expect(
      MoodOption.freshRemotePath('$base/dog/pride_e3u4cnatjf.webp'),
      '$base/dog/pride_bl749l1ncg.webp',
    );
  });

  test('id с подчёркиванием разбирается верно', () {
    expect(
      MoodOption.freshRemotePath('$base/dog/no_emotion_oldoldold1.webp'),
      '$base/dog/no_emotion_qqqqqqqqqq.webp',
    );
  });

  test('пак не путается с другим паком того же настроения', () {
    expect(
      MoodOption.freshRemotePath('$base/moti/pride_oooooooooo.webp'),
      '$base/moti/pride_zzzzzzzzzz.webp',
    );
  });

  test('актуальный адрес не трогаем', () {
    expect(
      MoodOption.freshRemotePath('$base/dog/pride_bl749l1ncg.webp'),
      isNull,
    );
  });

  test('ассеты сборки и чужие ссылки не задеваются', () {
    expect(MoodOption.freshRemotePath('assets/images/new emodji/Счастье.webp'),
        isNull);
    expect(MoodOption.freshRemotePath('https://example.com/a/b.webp'), isNull);
  });

  test('неизвестный пак оставляем как есть', () {
    expect(MoodOption.freshRemotePath('$base/cat/pride_aaaaaaaaaa.webp'), isNull);
  });
}
