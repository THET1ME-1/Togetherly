// Половину без данных нельзя затирать пустотой.
//
// Связка Android — iOS, 17.08.2026: у неё на iPhone своя половина парного
// виджета пустая — ни статуса, ни настроения, — а половина партнёра заполнена.
// Служба подписывается на свои данные по uid из сессии PocketBase и при пустом
// uid молча выходит, тогда как на партнёра подписка идёт по uid из пары. На iOS
// приложение поднимают тихим пушем на пару секунд, сессия может быть ещё не
// восстановлена, и `_myData` остаётся null — прежний код писал в контейнер
// пустые строки и обнулял свою половину.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/widget_data.dart';
import 'package:love_app/services/pair_widget_payload.dart';

void main() {
  WidgetData person(String uid, {String status = '', String mood = ''}) =>
      WidgetData(uid: uid, status: status, moodLabel: mood);

  test('есть оба — пишутся обе половины', () {
    final keys = pairWidgetPayload(
      my: person('me', status: 'на работе', mood: 'Люблю'),
      partner: person('you', status: 'дома', mood: 'Смех'),
    );
    expect(keys['my_status'], 'на работе');
    expect(keys['partner_status'], 'дома');
    expect(keys['my_mood'], 'Люблю');
    expect(keys['partner_mood'], 'Смех');
  });

  test('своих данных нет — свои ключи не трогаем', () {
    final keys =
        pairWidgetPayload(my: null, partner: person('you', status: 'дома'));
    expect(keys.keys.where((k) => k.startsWith('my_')), isEmpty,
        reason: 'иначе своя половина обнуляется при незагруженной сессии');
    expect(keys['partner_status'], 'дома');
  });

  test('данных партнёра нет — его ключи не трогаем', () {
    final keys =
        pairWidgetPayload(my: person('me', status: 'на работе'), partner: null);
    expect(keys.keys.where((k) => k.startsWith('partner_')), isEmpty);
    expect(keys['my_status'], 'на работе');
  });

  test('пустое поле пишется: человек убрал статус осознанно', () {
    final keys = pairWidgetPayload(my: person('me'), partner: person('you'));
    expect(keys.containsKey('my_status'), isTrue);
    expect(keys['my_status'], '');
  });

  test('нет никого — писать нечего', () {
    expect(pairWidgetPayload(my: null, partner: null), isEmpty);
  });

  test('имя с фолбэком, чтобы половина не осталась безымянной', () {
    final keys = pairWidgetPayload(
      my: person('me'),
      partner: person('you'),
      myFallbackName: 'Я',
      partnerFallbackName: 'Партнёр',
    );
    expect(keys['my_name'], 'Я');
    expect(keys['partner_name'], 'Партнёр');
  });
}
