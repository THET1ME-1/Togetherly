import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/music_meta_service.dart';

/// Яндекс.Музыка — единственный сервис, чью страницу разобрать нельзя: она
/// рисуется скриптом и отдаёт пустой html даже боту. Метаданные берутся из их
/// API, поэтому формат ответа стережёт тест, а не живой запрос.
void main() {
  group('Номер трека из ссылки', () {
    test('ссылка с альбомом', () {
      expect(
        MusicMetaService.yandexTrackId(
          'https://music.yandex.ru/album/4809518/track/34739621',
        ),
        '34739621',
      );
    });

    test('короткая ссылка на трек', () {
      expect(
        MusicMetaService.yandexTrackId('https://music.yandex.com/track/12345'),
        '12345',
      );
    });

    test('ссылка на альбом целиком трека не даёт', () {
      expect(
        MusicMetaService.yandexTrackId(
          'https://music.yandex.ru/album/4809518',
        ),
        isNull,
      );
    });
  });

  group('Разбор ответа API', () {
    // Ответ снят живьём с api.music.yandex.net/tracks/34739621.
    const sample = '''
    {"result":[{"id":"34739621","title":"Celia",
      "artists":[{"name":"Cinzia Gizzi Trio"}],
      "coverUri":"avatars.yandex.net/get-music-content/119639/5c0841d9.a.4293870-1/%%"}]}
    ''';

    test('название, исполнитель и обложка', () {
      final meta = MusicMetaService.parseYandexTrack(json.decode(sample));
      expect(meta['title'], 'Celia');
      expect(meta['artist'], 'Cinzia Gizzi Trio');
      expect(
        meta['cover'],
        'https://avatars.yandex.net/get-music-content/119639/5c0841d9.a.4293870-1/400x400',
      );
    });

    test('несколько исполнителей идут через запятую', () {
      final meta = MusicMetaService.parseYandexTrack({
        'result': [
          {
            'title': 'Дуэт',
            'artists': [
              {'name': 'Первый'},
              {'name': 'Второй'},
            ],
          },
        ],
      });
      expect(meta['artist'], 'Первый, Второй');
      expect(meta['cover'], isNull);
    });

    test('отказ API (451 за пределами России) даёт пустоту, а не мусор', () {
      final meta = MusicMetaService.parseYandexTrack({
        'invocationInfo': {'req-id': '1'},
        'error': {'name': 'Unavailable For Legal Reasons', 'message': ''},
      });
      expect(meta, isEmpty);
    });

    test('пустой список треков — пустой ответ', () {
      expect(MusicMetaService.parseYandexTrack({'result': []}), isEmpty);
    });
  });
}
