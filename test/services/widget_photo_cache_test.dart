// Кэш фото виджета обязан смотреть на файл, а не только на свои записи.
//
// Связка Android — iOS, 17.08.2026: в приложении обе половины парного виджета с
// фотографиями, а на рабочем столе обе пустые. Сеть и токен тут не при чём —
// приложение те же снимки показывает. Ломается повторная выдача: файл для
// расширения кладётся в контейнер App Group, а решение «качать или нет»
// принималось по двум записям в SharedPreferences (`<key>_cached_url` и
// `<key>_cached_wpath`). Стоит контейнеру опустеть — смена аккаунта чистит его
// целиком (`wipeWidgetData`, жалоба 14.08.2026), — и путь в записях остаётся, а
// файла нет: виджет получает ссылку в пустоту и рисует плейсхолдер, повторное
// скачивание не запускается никогда.
//
// Второе правило: сбой сети не должен затирать прежнее фото. Раньше на любой
// ошибке в ключ писалась пустая строка, и рабочий снимок исчезал со стола.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/widget_photo_cache.dart';

void main() {
  group('решение о скачивании', () {
    test('та же ссылка и файл на месте — берём кэш', () {
      expect(
        photoCacheDecision(
          url: 'pb://media/abc',
          cachedUrl: 'pb://media/abc',
          cachedPath: '/container/my_photo_path_1f.jpg',
          cachedFileExists: true,
        ),
        PhotoCacheAction.useCached,
      );
    });

    test('файла нет — качаем заново, даже если ссылка та же', () {
      expect(
        photoCacheDecision(
          url: 'pb://media/abc',
          cachedUrl: 'pb://media/abc',
          cachedPath: '/container/my_photo_path_1f.jpg',
          cachedFileExists: false,
        ),
        PhotoCacheAction.download,
        reason: 'иначе виджет навсегда остаётся с путём в пустоту',
      );
    });

    test('ссылка сменилась — качаем', () {
      expect(
        photoCacheDecision(
          url: 'pb://media/new',
          cachedUrl: 'pb://media/old',
          cachedPath: '/container/my_photo_path_1f.jpg',
          cachedFileExists: true,
        ),
        PhotoCacheAction.download,
      );
    });

    test('пустой путь в записях — качаем', () {
      expect(
        photoCacheDecision(
          url: 'pb://media/abc',
          cachedUrl: 'pb://media/abc',
          cachedPath: '',
          cachedFileExists: false,
        ),
        PhotoCacheAction.download,
      );
    });
  });

  group('что делать при сбое', () {
    test('есть живой прежний файл — оставляем его', () {
      expect(
        photoFallbackOnFailure(
          cachedPath: '/container/my_photo_path_1f.jpg',
          cachedFileExists: true,
        ),
        '/container/my_photo_path_1f.jpg',
      );
    });

    test('прежнего файла нет — честно пусто', () {
      expect(
        photoFallbackOnFailure(
          cachedPath: '/container/my_photo_path_1f.jpg',
          cachedFileExists: false,
        ),
        '',
      );
    });

    test('пути не было вовсе — пусто', () {
      expect(
        photoFallbackOnFailure(cachedPath: '', cachedFileExists: false),
        '',
      );
    });
  });
}
