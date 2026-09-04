// Своя карточка обязана догонять запись сразу, не дожидаясь realtime.
//
// `_updateField` пишет на сервер и тут же зовёт синхронизацию виджета, а та
// собирает ключи из `_myData` — локальной копии, которую обновляет ТОЛЬКО
// SSE-событие. Между записью и событием на рабочий стол уезжал прежний снимок,
// а если событие не долетало (сокет оборвался, процесс убит), фото не
// появлялось до перезахода в приложение. Жалоба @Zukotto4ka 01.09.2026:
// «ставлю фотку в виджете, а она отображается только в приложении».
//
// Поля приходят в camelCase — теми же именами, что уходят в `upsertWidget`.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/widget_data.dart';

void main() {
  final base = WidgetData(
    uid: 'me',
    displayName: 'Саша',
    status: 'на работе',
    moodLabel: 'Смех',
    moodEmoji: 'assets/mood/smile.webp',
    photoUrl: 'pb://media/a/старое.webp',
  );

  test('новое фото ложится в карточку сразу', () {
    final next = base.withFields({'photoUrl': 'pb://media/a/новое.webp'});
    expect(next.photoUrl, 'pb://media/a/новое.webp');
  });

  test('поля, которых нет в записи, остаются прежними', () {
    final next = base.withFields({'photoUrl': 'pb://media/a/новое.webp'});
    expect(next.status, 'на работе');
    expect(next.moodLabel, 'Смех');
    expect(next.uid, 'me');
  });

  test('пустая строка стирает поле: человек убрал фото осознанно', () {
    final next = base.withFields({'photoUrl': ''});
    expect(next.photoUrl, '');
    expect(next.hasPhoto, isFalse);
  });

  test('настроение, статус и сообщение доезжают тем же путём', () {
    final next = base.withFields({
      'status': 'дома',
      'moodLabel': 'Люблю',
      'moodEmoji': 'assets/mood/love.webp',
      'message': 'скучаю',
    });
    expect(next.status, 'дома');
    expect(next.moodLabel, 'Люблю');
    expect(next.moodEmoji, 'assets/mood/love.webp');
    expect(next.message, 'скучаю');
  });

  test('карусель «для партнёра» и сетка приходят списками', () {
    final next = base.withFields({
      'photoForPartnerUrls': ['pb://media/b/1.webp', 'pb://media/b/2.webp'],
      'photoGridUrls': ['pb://media/c/1.webp'],
      'photoGridCount': 2,
    });
    expect(next.photoForPartnerUrls, hasLength(2));
    expect(next.photoGridUrls, ['pb://media/c/1.webp']);
    expect(next.photoGridCount, 2);
  });

  // `upsertWidget` выбрасывает null-поля ради частичного апдейта: `updateMusic`
  // зовут без ссылки и обложки, и сервер их не трогает. Локальная копия обязана
  // вести себя так же, иначе она разойдётся с записью на сервере.
  test('null поле не трогает — как и запись на сервере', () {
    final withMusic = base.withFields({
      'musicTitle': 'Я тебя люблю',
      'musicUrl': 'https://example/track',
    });
    final next = withMusic.withFields({
      'musicTitle': 'Другая',
      'musicArtist': 'Кто-то',
      'musicUrl': null,
      'musicCoverUrl': null,
    });
    expect(next.musicTitle, 'Другая');
    expect(next.musicUrl, 'https://example/track');
  });

  test('незнакомый ключ ничего не ломает', () {
    final next = base.withFields({'какая-то_новинка': 'значение'});
    expect(next.status, 'на работе');
    expect(next.photoUrl, 'pb://media/a/старое.webp');
  });

  test('пустая карта возвращает те же данные', () {
    final next = base.withFields(const {});
    expect(next.status, base.status);
    expect(next.photoUrl, base.photoUrl);
    expect(next.moodEmoji, base.moodEmoji);
  });
}
