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

    test('своё имя уезжает комнате: партнёр не «Гость»', () {
      // Комната знает только код, поэтому в чате обе стороны подписывались
      // «Гость» и «Вы» (жалоба тестера 13 августа 2026). Имя передаём адресом.
      final url = WatchRoomService.siteUrl('abcd2345', name: 'Виктория');
      expect(Uri.parse(url).queryParameters['name'], 'Виктория');
      expect(url, endsWith('#abcd2345'));
    });

    test('имя живёт рядом с роликом, не вытесняя его', () {
      final url = WatchRoomService.siteUrl(
        'abcd2345',
        src: 'https://example.org/v.mp4',
        name: 'Саша',
      );
      final q = Uri.parse(url).queryParameters;
      expect(q['src'], 'https://example.org/v.mp4');
      expect(q['name'], 'Саша');
    });

    test('пустое имя в адрес не попадает', () {
      expect(
        WatchRoomService.siteUrl('abcd2345', name: '   '),
        WatchRoomService.siteUrl('abcd2345'),
      );
    });

    test('длинное имя обрезается: в чате оно всё равно не поместится', () {
      final url = WatchRoomService.siteUrl('abcd2345', name: 'я' * 80);
      expect(Uri.parse(url).queryParameters['name']!.length, 32);
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

  group('WatchVideosService.playsInRoom', () {
    // Комната открывается анонимной вкладкой браузера: там нет ни нашей
    // сессии, ни файлового токена. Всё, что без них не отдаётся, играем
    // нативно — иначе у партнёра вечный спиннер, а у себя пустой экран
    // (жалоба со скриншотом: «воспоминание-видео не прогружается»).
    test('свой ролик пары отдаётся комнате', () {
      expect(
        WatchVideosService.playsInRoom(
          'https://togetherly.duckdns.org/api/files/watch_videos/rec1/v.mp4',
        ),
        isTrue,
      );
    });

    test('файл воспоминания комнате не отдать', () {
      for (final url in [
        'pb://media/abc123/clip.mp4',
        'https://togetherly.duckdns.org/api/files/media/abc123/clip.mp4',
        'https://togetherly.duckdns.org/api/files/media/abc123/clip.mp4?token=xyz',
        'localfile:///data/user/0/clip.mp4',
        'file:///storage/emulated/0/clip.mp4',
      ]) {
        expect(WatchVideosService.playsInRoom(url), isFalse, reason: url);
      }
    });

    test('мёртвые ссылки прошлых хранилищ играем у себя', () {
      for (final url in [
        'https://firebasestorage.googleapis.com/v0/b/love/o/clip.mp4?alt=media',
        'sb://videos/clip.mp4',
        'https://abcd.supabase.co/storage/v1/object/public/videos/clip.mp4',
      ]) {
        expect(WatchVideosService.playsInRoom(url), isFalse, reason: url);
      }
    });

    test('площадки и прямые файлы комната открывает сама', () {
      for (final url in [
        'https://youtu.be/dQw4w9WgXcQ',
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://rutube.ru/video/abc123def456/',
        'https://vk.com/video-1_2',
        'https://disk.yandex.ru/i/abc',
        'https://example.org/movie.mp4',
      ]) {
        expect(WatchVideosService.playsInRoom(url), isTrue, reason: url);
      }
    });

    test('чужая страница без видео комнате не годится', () {
      expect(WatchVideosService.playsInRoom('https://example.org/page'), isFalse);
      expect(WatchVideosService.playsInRoom(''), isFalse);
      expect(WatchVideosService.playsInRoom('не ссылка'), isFalse);
    });
  });

  group('WatchVideosService.limitFor', () {
    test('Togetherly+ поднимает потолок, и он совпадает с коллекцией', () {
      expect(WatchVideosService.limitFor(plus: false), 100 * 1024 * 1024);
      expect(WatchVideosService.limitFor(plus: true), 300 * 1024 * 1024);
    });
  });
}
