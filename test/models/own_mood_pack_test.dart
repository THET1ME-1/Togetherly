import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/custom_mood.dart';
import 'package:love_app/models/mood_band.dart';
import 'package:love_app/models/mood_pack.dart';
import 'package:love_app/models/own_mood_pack.dart';
import 'package:love_app/services/plus_access.dart';

CustomMood _mood(String id, int score, {String emoji = '', String author = 'me'}) =>
    CustomMood(
      id: id,
      groupId: 'g',
      authorUid: author,
      moodId: 'custom_$id',
      label: id,
      emoji: emoji,
      imageUrl: 'https://x/$id.png',
      score: score,
    );

void main() {
  group('что показывает набор «Свои»', () {
    OwnPackState state({bool group = true, PlusGate gate = PlusGate.open, bool loaded = true, int count = 0}) =>
        ownPackState(hasGroup: group, gate: gate, loaded: loaded, count: count);

    test('без пары таблетки нет: настроение без группы никуда не сохранится', () {
      expect(state(group: false, count: 3), OwnPackState.hidden);
    });

    test('там, где Плюса нет вовсе, таблетки нет', () {
      expect(state(gate: PlusGate.hidden, count: 3), OwnPackState.hidden);
    });

    test('пока набор грузится, показываем ожидание, а не пустоту', () {
      expect(state(loaded: false), OwnPackState.loading);
      expect(state(loaded: false, gate: PlusGate.locked), OwnPackState.loading);
    });

    test('с Плюсом и без своих настроений зовём завести первое', () {
      expect(state(), OwnPackState.empty);
    });

    test('без Плюса и без своих настроений показываем пример и вход в Плюс', () {
      expect(state(gate: PlusGate.locked), OwnPackState.teaser);
    });

    test('без Плюса, но с настроениями партнёра набор выбирается', () {
      // Заводит тот, у кого Плюс, а выбирают оба.
      expect(state(gate: PlusGate.locked, count: 2), OwnPackState.list);
    });

    test('выбор запоминается, кроме примера без Плюса', () {
      expect(ownPackSelectable(OwnPackState.list), isTrue);
      expect(ownPackSelectable(OwnPackState.empty), isTrue);
      expect(ownPackSelectable(OwnPackState.loading), isTrue);
      expect(ownPackSelectable(OwnPackState.teaser), isFalse);
      expect(ownPackSelectable(OwnPackState.hidden), isFalse);
    });
  });

  group('какой набор подсвечен в ряду', () {
    String shown({
      String selected = 'classic',
      String resolved = 'classic',
      OwnPackState own = OwnPackState.list,
      String? preview,
      bool previewOwn = false,
    }) =>
        shownMoodPackId(
          selectedId: selected,
          resolvedId: resolved,
          own: own,
          previewId: preview,
          previewOwn: previewOwn,
        );

    test('выбранные «Свои» подсвечены, когда их можно выбрать', () {
      expect(shown(selected: kOwnMoodPackId, own: OwnPackState.list), kOwnMoodPackId);
      expect(shown(selected: kOwnMoodPackId, own: OwnPackState.loading), kOwnMoodPackId);
    });

    test('выбранные когда-то «Свои» без Плюса и без настроений уступают классическим', () {
      // Иначе человек открывает лист и видит один пример, где выбрать нечего.
      expect(shown(selected: kOwnMoodPackId, own: OwnPackState.teaser), MoodPack.classic.id);
      expect(shown(selected: kOwnMoodPackId, own: OwnPackState.hidden), MoodPack.classic.id);
    });

    test('просмотр закрытого набора важнее выбора', () {
      expect(shown(selected: kOwnMoodPackId, preview: 'moti'), 'moti');
      expect(shown(previewOwn: true, own: OwnPackState.teaser), kOwnMoodPackId);
    });

    test('незнакомый набор, ещё не приехавший из каталога, подсвечивает тот, что показан', () {
      expect(shown(selected: 'dog', resolved: 'classic'), 'classic');
    });
  });

  group('свои настроения по разделам шкалы', () {
    test('разделы идут от светлого к тяжёлому, внутри порядок заведения', () {
      final sections = groupOwnByBand([
        _mood('pug', 3),
        _mood('boom', 2),
        _mood('sleepy', 3),
        _mood('pizza', 4),
        _mood('bear', 1),
        _mood('proud', 5),
      ]);
      expect(sections.map((s) => s.band), [MoodBand.bright, MoodBand.even, MoodBand.sad, MoodBand.heavy]);
      expect(sections.first.moods.map((m) => m.id), ['pizza', 'proud']);
      expect(sections[1].moods.map((m) => m.id), ['pug', 'sleepy']);
    });

    test('пустых разделов нет', () {
      final sections = groupOwnByBand([_mood('a', 2)]);
      expect(sections.map((s) => s.band), [MoodBand.sad]);
    });
  });

  test('набор полон на двадцать четвёртом', () {
    expect(kOwnMoodLimit, 24);
    expect(ownPackFull(23), isFalse);
    expect(ownPackFull(24), isTrue);
  });

  test('эмодзи стоит на плитке цвета шкалы, фото и рисунок заполняют её сами', () {
    expect(_mood('a', 2, emoji: '🤯').onTintedTile, isTrue);
    expect(_mood('b', 2).onTintedTile, isFalse);
  });

  test('править и убирать своё настроение может только тот, кто завёл', () {
    final mine = _mood('a', 3, author: 'u1');
    expect(mine.editableBy('u1'), isTrue);
    expect(mine.editableBy('u2'), isFalse);
    expect(mine.editableBy(''), isFalse);
  });
}
