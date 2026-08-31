// Пустой файл в кэше — не кэш.
//
// Жалобы 30–31.08.2026 (пять человек за сутки, iPhone и Android): «в приложении
// фото есть, на виджете нет», «не обновляется ничего», «после последнего
// обновления». Разбор кода показал путь, на котором пустота залипает навсегда:
//
//   1. склад отдаёт содержимое файла из кэша, не глядя на его размер;
//   2. `_cachePhotoFromUrl` проверяет только «байты не null» — пустой массив
//      проходит и пишется в файл виджета;
//   3. `photoCacheDecision` видит, что файл СУЩЕСТВУЕТ, и больше никогда не
//      идёт в сеть.
//
// Дальше человек меняет фото — и ничего не происходит: ключ уже занят пустым
// файлом. Нулевой файл появляется от оборванной записи, а на iOS фоновый
// проход прибивают по таймауту регулярно.

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/widget_photo_cache.dart';

void main() {
  group('Пустой файл не считается кэшем', () {
    test('Нулевой файл на диске отправляет за фото заново', () {
      final decision = photoCacheDecision(
        url: 'pb://media/rec/photo.webp',
        cachedUrl: 'pb://media/rec/photo.webp',
        cachedPath: '/data/widget_partner.jpg',
        cachedFileExists: true,
        cachedFileSize: 0,
      );
      expect(decision, PhotoCacheAction.download);
    });

    test('Файл с байтами переиспользуется', () {
      final decision = photoCacheDecision(
        url: 'pb://media/rec/photo.webp',
        cachedUrl: 'pb://media/rec/photo.webp',
        cachedPath: '/data/widget_partner.jpg',
        cachedFileExists: true,
        cachedFileSize: 175732,
      );
      expect(decision, PhotoCacheAction.useCached);
    });

    test('Обрезок в несколько байт тоже не кэш', () {
      final decision = photoCacheDecision(
        url: 'pb://media/rec/photo.webp',
        cachedUrl: 'pb://media/rec/photo.webp',
        cachedPath: '/data/widget_partner.jpg',
        cachedFileExists: true,
        cachedFileSize: 12,
      );
      expect(decision, PhotoCacheAction.download);
    });

    test('Пустой файл не годится и как запасной снимок', () {
      expect(
        photoFallbackOnFailure(
          cachedPath: '/data/widget_partner.jpg',
          cachedFileExists: true,
          cachedFileSize: 0,
        ),
        '',
      );
      expect(
        photoFallbackOnFailure(
          cachedPath: '/data/widget_partner.jpg',
          cachedFileExists: true,
          cachedFileSize: 40000,
        ),
        '/data/widget_partner.jpg',
      );
    });
  });
}
