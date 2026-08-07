import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/pb_data_service.dart';

/// Что уезжает в `widget_data` при частичном обновлении.
///
/// Запись виджета обновляют по одному полю: сменил статус — ушёл статус.
/// Но тело запроса подставляло значения по умолчанию за все json-поля
/// (`data`, карусель «для партнёра», сетка фото), и смена статуса затирала
/// их пустотой. На проде это видно в чистом виде: 22 578 записей и ни одной
/// с непустой `data` — заметка на двоих не пережила ни одного действия.
void main() {
  group('Тело запроса widget_data', () {
    test('поля, которых не просили менять, в тело не попадают', () {
      final body = PbDataService.widgetUpsertBody('g1', 'u1', {'status': 'дома'});

      expect(body['status'], 'дома');
      expect(body.containsKey('data'), isFalse);
      expect(body.containsKey('photo_for_partner_urls'), isFalse);
      expect(body.containsKey('photo_grid_urls'), isFalse);
      expect(body.containsKey('photo_grid_count'), isFalse);
    });

    test('заметка уходит, когда её и просили сохранить', () {
      final body = PbDataService.widgetUpsertBody('g1', 'u1', {
        'data': {
          'note': {'text': 'молоко', 'author': 'Я', 'at': 1},
        },
      });

      expect((body['data'] as Map)['note'], isA<Map>());
    });

    test('явная очистка проходит: пустой список стирает карусель', () {
      final body = PbDataService.widgetUpsertBody('g1', 'u1', {
        'photoForPartnerUrls': <String>[],
        'photoForPartnerUrl': '',
      });

      expect(body['photo_for_partner_urls'], isEmpty);
      expect(body['photo_for_partner_url'], '');
    });

    test('сетка фото передаётся вместе со своим числом', () {
      final body = PbDataService.widgetUpsertBody('g1', 'u1', {
        'photoGridCount': 4,
        'photoGridUrls': ['a', 'b'],
      });

      expect(body['photo_grid_count'], 4);
      expect(body['photo_grid_urls'], ['a', 'b']);
    });

    test('связь и время правки стоят всегда', () {
      final body = PbDataService.widgetUpsertBody('g1', 'u1', const {});

      expect(body['group_id'], 'g1');
      expect(body['user_uid'], 'u1');
      expect(body['updated_at'], isA<String>());
    });
  });
}
