import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/watch_videos_service.dart';
import 'package:love_app/utils/video_link_thumb.dart';

/// У ссылок на ролики обложка почти никогда не сохраняется: за сентябрь
/// 2026 года без неё 1540 записей из 1542. Лента воспоминаний выводила
/// обложку YouTube на лету, а «Смотрим» — нет, и «Наши видео» стояли серыми
/// плитками (жалоба 05.10.2026). Правило одно на оба экрана.
void main() {
  group('videoLinkThumb', () {
    const yt = 'https://i.ytimg.com/vi/ro0KqgvlS4Y/hqdefault.jpg';

    test('короткая ссылка YouTube', () {
      expect(videoLinkThumb('https://youtu.be/ro0KqgvlS4Y'), yt);
      expect(videoLinkThumb('https://youtu.be/ro0KqgvlS4Y?si=63ToTj-Jgj_an5CT'), yt);
    });

    test('полная ссылка, Shorts, встраивание и эфир YouTube', () {
      expect(videoLinkThumb('https://www.youtube.com/watch?v=ro0KqgvlS4Y&t=12'), yt);
      expect(videoLinkThumb('https://m.youtube.com/watch?feature=share&v=ro0KqgvlS4Y'), yt);
      expect(videoLinkThumb('https://youtube.com/shorts/ro0KqgvlS4Y?feature=share'), yt);
      expect(videoLinkThumb('https://www.youtube.com/embed/ro0KqgvlS4Y'), yt);
      expect(videoLinkThumb('https://www.youtube.com/live/ro0KqgvlS4Y'), yt);
    });

    test('Rutube — обложка его открытым адресом', () {
      const id = 'c6cc4d620b1d4338901770a44b3e82f4';
      const thumb = 'https://rutube.ru/api/video/$id/thumbnail/?redirect=1';
      expect(videoLinkThumb('https://rutube.ru/video/$id/'), thumb);
      expect(videoLinkThumb('https://rutube.ru/shorts/$id/'), thumb);
    });

    test('площадки без открытой обложки и не ссылки — пусто', () {
      expect(videoLinkThumb('https://vk.com/video-220754053_456239310'), '');
      expect(videoLinkThumb('pb://media/ugq8nbu7sf4a9pl/1786453555756_v5zdc99cy'), '');
      expect(videoLinkThumb(''), '');
      expect(videoLinkThumb('не ссылка'), '');
    });
  });

  group('видео-воспоминание в «Наших видео»', () {
    test('своя обложка главнее выведенной', () {
      final v = WatchVideosService.fromMemoryData('m1', {
        'videoUrl': 'https://youtu.be/zTd8ZN2xNG8?si=63ToTj-Jgj_an5CT',
        'imageUrl': 'https://example.com/own.jpg',
        'title': 'ДРЭДЖ',
      })!;
      expect(v.thumbUrl, 'https://example.com/own.jpg');
      expect(v.title, 'ДРЭДЖ');
    });

    test('ссылка без обложки получает обложку площадки', () {
      final v = WatchVideosService.fromMemoryData('m2', {'videoUrl': 'https://youtu.be/ro0KqgvlS4Y'})!;
      expect(v.thumbUrl, 'https://i.ytimg.com/vi/ro0KqgvlS4Y/hqdefault.jpg');
    });

    test('без названия подписью идёт подпись к воспоминанию', () {
      final v = WatchVideosService.fromMemoryData('m3', {
        'videoUrl': 'https://youtu.be/ro0KqgvlS4Y',
        'title': '',
        'caption': 'наш вечер',
      })!;
      expect(v.title, 'наш вечер');
    });

    test('запись без ролика в «Наши видео» не попадает', () {
      expect(WatchVideosService.fromMemoryData('m4', {'imageUrl': 'x'}), isNull);
    });
  });
}
