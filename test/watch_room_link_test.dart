import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/watch_room_service.dart';
import 'package:love_app/services/watch_videos_service.dart';

/// Свой ролик открывается в комнате пары, а не локально. Комната получает его
/// адресом (`?src=`) и объявляет партнёру, поэтому ссылка и отбор форматов —
/// то место, где фича ломается молча.
void main() {
  group('WatchRoomService.siteUrl', () {
    test('без ролика отдаёт чистый адрес комнаты', () {
      expect(
        WatchRoomService.siteUrl('abcd2345'),
        'https://togetherly.day/watch/room/#abcd2345',
      );
    });

    test('код комнаты остаётся в хеше, ролик уходит в запрос', () {
      final url = WatchRoomService.siteUrl(
        'abcd2345',
        src: 'https://togetherly.duckdns.org/api/files/watch_videos/x1/v.mp4',
      );
      expect(url, startsWith('https://togetherly.day/watch/room/?src='));
      expect(url, endsWith('#abcd2345'));
      final query = Uri.parse(url).queryParameters['src'];
      expect(
        query,
        'https://togetherly.duckdns.org/api/files/watch_videos/x1/v.mp4',
      );
    });

    test('пустой ролик равен его отсутствию', () {
      expect(
        WatchRoomService.siteUrl('abcd2345', src: ''),
        WatchRoomService.siteUrl('abcd2345'),
      );
    });
  });

  group('WatchVideosService.isPlayable', () {
    test('пропускает то, что играет браузер комнаты', () {
      for (final name in ['кино.mp4', 'clip.MOV', 'a.webm', 'b.m4v']) {
        expect(WatchVideosService.isPlayable(name), isTrue, reason: name);
      }
    });

    test('отсекает контейнеры, которые партнёр не увидит', () {
      for (final name in ['film.mkv', 'old.avi', 'phone.3gp', 'x.flv']) {
        expect(WatchVideosService.isPlayable(name), isFalse, reason: name);
      }
    });

    test('имя без расширения не проходит', () {
      expect(WatchVideosService.isPlayable('video'), isFalse);
      expect(WatchVideosService.isPlayable('video.'), isFalse);
    });
  });

  group('WatchVideosService.limitFor', () {
    test('Togetherly+ поднимает потолок, и он совпадает с коллекцией', () {
      expect(WatchVideosService.limitFor(plus: false), 100 * 1024 * 1024);
      expect(WatchVideosService.limitFor(plus: true), 300 * 1024 * 1024);
    });
  });
}
