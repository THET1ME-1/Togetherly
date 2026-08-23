import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/pb_media_service.dart';

/// Ссылка без файлового токена гарантированно приводит в 404.
///
/// Файлы media закрыты правилом коллекции, открывает их короткий токен из
/// `POST /api/files/token`. Когда сессия протухала, запрос токена отвечал 401, а
/// клиент всё равно отдавал «голый» адрес — и телефон долбил сервер ссылками,
/// которые не могли сработать: 11 438 таких запросов за двое суток, 203 отказа
/// в токене за трое. На экране это выглядело так, что не грузится ни одно фото
/// сразу (жалоба @hi_no_kate 22.08.2026: все семь снимков фото-виджета в
/// значке ошибки).
///
/// Пусто вместо мёртвой ссылки — честнее: экран покажет заглушку и не станет
/// кэшировать отказ.
void main() {
  group('mediaUrlWithToken', () {
    const base = 'https://togetherly.day/api/files/media/abc/photo.webp';

    test('токен есть — подставляем в адрес', () {
      expect(
        mediaUrlWithToken(base: base, token: 'tok123'),
        '$base?token=tok123',
      );
    });

    test('токена нет — адреса нет', () {
      expect(mediaUrlWithToken(base: base, token: null), isNull);
    });

    test('пустой токен — тоже нет', () {
      expect(mediaUrlWithToken(base: base, token: ''), isNull);
    });
  });
}
