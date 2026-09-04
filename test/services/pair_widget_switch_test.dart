// Смена пары обязана стирать половину, о которой данных нет.
//
// Правило «нет данных — не трогаем» (17–18.08.2026) спасает от обнуления на
// холодном старте: сессия ещё не поднялась, `_myData` равно null, и записывать
// пустоту нельзя. Но у человека с двумя связями то же правило оставляет на
// рабочем столе лицо и настроение ПРЕЖНЕЙ пары: у новой записи `widget_data`
// ещё не приехали, половину не трогают, и виджет мешает две пары в одну
// картинку (жалоба 04.09.2026 со снимком: слева одна связь, справа другая).
//
// Различаем два случая с одинаковым `null`: та же пара (ждём данных, ничего не
// трогаем) и другая пара (данных прежней тут быть не должно — стираем).
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/widget_data.dart';
import 'package:love_app/services/pair_widget_payload.dart';

void main() {
  WidgetData person(
    String uid, {
    String status = '',
    String mood = '',
    String? photo,
    String avatar = '',
    String emoji = '',
  }) =>
      WidgetData(
        uid: uid,
        status: status,
        moodLabel: mood,
        photoUrl: photo,
        avatarUrl: avatar,
        moodEmoji: emoji,
      );

  group('тексты', () {
    test('пара сменилась, своих данных нет — свои ключи стираем', () {
      final keys = pairWidgetPayload(
        my: null,
        partner: person('you', status: 'дома'),
        pairChanged: true,
      );
      expect(keys['my_status'], '',
          reason: 'иначе на виджете останется статус прежней пары');
      expect(keys['my_mood'], '');
      expect(keys['my_name'], '');
      expect(keys['partner_status'], 'дома');
    });

    test('пара та же, своих данных нет — свои ключи не трогаем', () {
      final keys = pairWidgetPayload(
        my: null,
        partner: person('you', status: 'дома'),
      );
      expect(keys.keys.where((k) => k.startsWith('my_')), isEmpty);
    });

    test('пара сменилась, данных партнёра нет — его ключи стираем', () {
      final keys = pairWidgetPayload(
        my: person('me', status: 'на работе'),
        partner: null,
        pairChanged: true,
      );
      expect(keys['partner_status'], '');
      expect(keys['partner_name'], '');
      expect(keys['my_status'], 'на работе');
    });

    test('пара сменилась, данные обеих половин на месте — пишем как есть', () {
      final keys = pairWidgetPayload(
        my: person('me', status: 'на работе'),
        partner: person('you', status: 'дома'),
        pairChanged: true,
      );
      expect(keys['my_status'], 'на работе');
      expect(keys['partner_status'], 'дома');
    });
  });

  group('картинки', () {
    test('пара сменилась, своих данных нет — свои картинки стираем', () {
      final m = pairWidgetMedia(
        my: null,
        partner: person('you', photo: 'pb://media/b/2.webp'),
        pairChanged: true,
      );
      expect(m.myPhoto, '',
          reason: 'иначе на столе останется лицо прежней пары');
      expect(m.myAvatar, '');
      expect(m.myMoodEmoji, '');
      expect(m.myIosPhotos, isEmpty);
      expect(m.partnerPhoto, 'pb://media/b/2.webp');
    });

    test('пара та же, своих данных нет — свои картинки не трогаем', () {
      final m = pairWidgetMedia(
        my: null,
        partner: person('you', photo: 'pb://media/b/2.webp'),
      );
      expect(m.myPhoto, isNull);
      expect(m.myAvatar, isNull);
      expect(m.myIosPhotos, isNull);
    });

    test('пара сменилась, данных партнёра нет — его картинки стираем', () {
      final m = pairWidgetMedia(
        my: person('me', photo: 'pb://media/a/1.webp', avatar: 'pb://a/1'),
        partner: null,
        pairChanged: true,
      );
      expect(m.partnerPhoto, '');
      expect(m.partnerAvatar, '');
      expect(m.partnerMoodEmoji, '');
      expect(m.partnerIosPhotos, isEmpty);
      expect(m.myPhoto, 'pb://media/a/1.webp');
    });
  });
}
