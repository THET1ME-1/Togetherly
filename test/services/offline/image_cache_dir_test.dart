import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/offline/media_view_cache.dart';

void main() {
  group('папка кэша картинок', () {
    test('на Android кэш живёт в files/offline, а не во временной папке', () {
      final dir = imageCacheDirFor(
        android: true,
        temp: '/data/user/0/app/cache',
        support: '/data/user/0/app/files',
        key: 'offlineImageCacheV1',
      );
      // Временную папку Android и программы-уборщики чистят сами, и
      // анимации каталога качались заново. files/offline не чистит никто и
      // не уносит в автобэкап (backup_rules.xml).
      expect(dir, '/data/user/0/app/files/offline/offlineImageCacheV1');
    });

    test('на iPhone остаётся Library/Caches', () {
      final dir = imageCacheDirFor(
        android: false,
        temp: '/var/app/Library/Caches',
        support: '/var/app/Library/Application Support',
        key: 'offlineImageCacheV1',
      );
      // Скачиваемое заново Apple велит держать вне резервной копии.
      expect(dir, '/var/app/Library/Caches/offlineImageCacheV1');
    });

    test('прежняя папка — та, где кэш лежал до переезда', () {
      expect(
        legacyImageCacheDir(temp: '/data/user/0/app/cache', key: 'k'),
        '/data/user/0/app/cache/k',
      );
    });
  });
}
