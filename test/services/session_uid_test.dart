// Пустая запись сессии — ещё не выход из аккаунта.
//
// 18.08.2026 виджеты стали чиститься на ровном месте: в контейнере тестера
// пропали имена и настроения, хотя на сервере они лежали. Причина — в подписке
// на сессию я брал `authStore.record?.id`, а он бывает пустым при живом токене:
// это «полумёртвая сессия», давняя болезнь iOS (см. фолбэк в
// PocketBaseService.userId). Пустой id прочитался как выход, и контейнер стёрло.
//
// Выход — это пустой ТОКЕН. Нет записи, но токен жив — берём id из самого
// токена. Не вышло и оттуда — честно «не знаю», и тогда не трогаем ничего.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/widget_owner.dart';

String _token(Map<String, dynamic> payload) {
  final body = base64Url.encode(utf8.encode(jsonEncode(payload)));
  return 'header.$body.signature';
}

void main() {
  test('пустой токен — это выход', () {
    expect(sessionUidOf(token: '', recordId: 'u1'), '');
    expect(sessionUidOf(token: '', recordId: null), '');
  });

  test('есть запись — берём её id', () {
    expect(sessionUidOf(token: _token({'id': 'from-token'}), recordId: 'u1'),
        'u1');
  });

  test('записи нет, токен жив — достаём id из токена', () {
    expect(
        sessionUidOf(token: _token({'id': 'from-token'}), recordId: null),
        'from-token',
        reason: 'полумёртвая сессия: запросы идут, а record не восстановился');
  });

  test('записи нет и в токене пусто — не знаем, трогать нельзя', () {
    expect(sessionUidOf(token: _token({'exp': 1}), recordId: null), isNull);
    expect(sessionUidOf(token: 'мусор', recordId: ''), isNull);
  });
}
