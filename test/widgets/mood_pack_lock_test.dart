import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/level.dart';
import 'package:love_app/models/mood_entry.dart';
import 'package:love_app/models/mood_pack.dart';
import 'package:love_app/widgets/mood_pack_selector.dart';

/// Платный пак настроений виден всем, но закрыт до покупки.
///
/// Ровно этой проверки не хватало маскотам: пока владение никто не смотрел,
/// платный элемент доставался даром каждому.
void main() {
  const paid = MoodPack(
    id: 'kawaii',
    isFree: false,
    nameRu: 'Каваи',
    nameEn: 'Kawaii',
    moods: [
      MoodOption(
        id: 'happy',
        imagePath: 'https://example.test/happy.webp',
        label: 'Счастье',
        color: Color(0xFFF5C542),
      ),
    ],
    unlock: Unlock.premium(price: 120),
  );

  test('ключ владения пака отличается от маскотского', () {
    expect(Unlock.featureKey(kMoodPackFeatureKind, 'kawaii'), 'mood_pack:kawaii');
    expect(
      Unlock.featureKey(kMascotFeatureKind, 'kawaii'),
      isNot(Unlock.featureKey(kMoodPackFeatureKind, 'kawaii')),
    );
  });

  test('без покупки пак закрыт, с покупкой пары открыт', () {
    final key = Unlock.featureKey(kMoodPackFeatureKind, paid.id);

    // Без данных о человеке платный пак закрыт. Раньше он в этом случае
    // считался открытым, и на экране виджетов (пикер звался без user) платный
    // набор предлагался к выбору, хотя его никто не покупал.
    const noUser = MoodPackSelector(primary: Colors.pink);
    expect(noUser.isOpen(paid), isFalse,
        reason: 'нет кошелька — платный набор не отдаём');

    // Купленное парой открыто и без данных о человеке: покупка партнёра
    // приезжает ключами группы, а на iPhone от этого зависит, увидит ли он
    // набор вообще.
    final byPair = MoodPackSelector(primary: Colors.pink, pairOwned: {key});
    expect(byPair.isOpen(paid), isTrue,
        reason: 'партнёр купил — набор открыт обоим');

    expect(
      paid.unlock.isUnlocked(level: 99, owned: false, plus: false),
      isFalse,
      reason: 'уровень платный пак не открывает',
    );
    expect(
      paid.unlock.isUnlocked(level: 1, owned: true, plus: false),
      isTrue,
      reason: 'купленный открыт навсегда',
    );
    expect(
      paid.unlock.isUnlocked(level: 1, owned: false, plus: true),
      isFalse,
      reason: 'Togetherly+ сам по себе платный пак не даёт',
    );
    expect(key, 'mood_pack:kawaii');
  });

  test('бесплатный пак открыт без покупок', () {
    expect(
      MoodPack.classic.unlock.isUnlocked(level: 0, owned: false, plus: false),
      isTrue,
    );
  });

  test('пак с ценой ноль не продаётся и не отдаётся даром', () {
    const broken = Unlock.premium(price: 0);
    expect(broken.isForSale, isFalse);
    expect(broken.isUnlocked(level: 99, owned: false, plus: false), isFalse);
  });
}
