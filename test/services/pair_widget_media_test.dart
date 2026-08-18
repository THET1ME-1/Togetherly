// Картинки половины без данных нельзя стирать.
//
// 17.08.2026 половину без данных перестали затирать пустотой, но правило
// накрыло только текстовые ключи. Фото, аватар и картинку настроения по-прежнему
// пересобирали на каждом проходе из `my?.photoUrl`, а при `my == null` это
// пустая строка: ключ обнулялся, файл из общего контейнера удалялся. Самоотчёт
// с iPhone тестера (сборка 1.29.1+202, ночь на 18.08) показал ровно это —
// `my_mood`, `partner_mood` и имена на месте, а все пути к файлам пусты.
//
// Разделяем три случая: данных о половине нет (не трогаем), данные есть и поле
// пустое (стираем осознанно), данные есть и ссылка на месте (качаем).
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/widget_data.dart';
import 'package:love_app/services/pair_widget_payload.dart';

void main() {
  WidgetData person(
    String uid, {
    String? photo,
    String avatar = '',
    String emoji = '',
  }) =>
      WidgetData(
        uid: uid,
        photoUrl: photo,
        avatarUrl: avatar,
        moodEmoji: emoji,
      );

  test('своих данных нет — свои картинки не трогаем', () {
    final m = pairWidgetMedia(
      my: null,
      partner: person('you', photo: 'pb://media/b/2.webp', avatar: 'pb://a/2'),
    );
    expect(m.myPhoto, isNull, reason: 'иначе фото стирается с рабочего стола');
    expect(m.myAvatar, isNull);
    expect(m.myMoodEmoji, isNull);
    expect(m.partnerPhoto, 'pb://media/b/2.webp');
  });

  test('данных партнёра нет — его картинки не трогаем', () {
    final m = pairWidgetMedia(
      my: person('me', photo: 'pb://media/a/1.webp'),
      partner: null,
    );
    expect(m.partnerPhoto, isNull);
    expect(m.partnerAvatar, isNull);
    expect(m.partnerMoodEmoji, isNull);
    expect(m.myPhoto, 'pb://media/a/1.webp');
  });

  test('данные есть, фото убрано — стираем пустой строкой', () {
    final m = pairWidgetMedia(
      my: person('me', photo: null, emoji: 'assets/mood/happy.webp'),
      partner: person('you'),
    );
    expect(m.myPhoto, '', reason: 'человек убрал фото — виджет обязан это показать');
    expect(m.myMoodEmoji, 'assets/mood/happy.webp');
    expect(m.partnerPhoto, '');
  });

  test('обеих половин нет — не трогаем ничего', () {
    final m = pairWidgetMedia(my: null, partner: null);
    expect(m.myPhoto, isNull);
    expect(m.partnerPhoto, isNull);
    expect(m.myAvatar, isNull);
    expect(m.partnerAvatar, isNull);
    expect(m.myMoodEmoji, isNull);
    expect(m.partnerMoodEmoji, isNull);
  });

  test('фото-виджеты iPhone: без данных половины список null, а не пустой', () {
    final m = pairWidgetMedia(my: null, partner: person('you'));
    expect(m.myIosPhotos, isNull,
        reason: 'пустой список стирает ios_self_photo_path и каталог выбора');
    expect(m.partnerIosPhotos, isEmpty);
  });
}
