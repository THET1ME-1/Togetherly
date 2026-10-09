import 'dart:io' as io;

import 'package:file/file.dart' hide FileSystem;
import 'package:file/local.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Долгоживущий кэш картинок для ГАРАНТИРОВАННОГО офлайн-просмотра.
///
/// Дефолтный кэш `cached_network_image` вытесняет файлы по LRU (~200 объектов /
/// 30 дней), поэтому давно виденное фото офлайн могло показать заглушку. Этот
/// менеджер с большими лимитами практически не вытесняет (потолок задан, чтобы
/// диск не рос бесконечно). Используется в [StorageImage].
///
/// Файлы лежат в [_PersistentFileSystem], а не во временной папке, как у
/// пакета по умолчанию (09.10.2026): её Android и уборщики вроде MIUI чистят
/// сами, и анимации каталога по 1–1,8 МБ качались заново — 86% трафика точки
/// входа.
class OfflineImageCacheManager extends CacheManager with ImageCacheManager {
  static const key = 'offlineImageCacheV1';

  static final OfflineImageCacheManager instance = OfflineImageCacheManager._();

  OfflineImageCacheManager._()
      : super(Config(
          key,
          stalePeriod: const Duration(days: 3650),
          maxNrOfCacheObjects: 5000,
          fileSystem: _PersistentFileSystem(key),
        ));
}

/// Папка кэша картинок. На Android — `files/offline/<key>`: её система не
/// чистит, а автобэкап её не берёт (`offline` исключён в backup_rules.xml и
/// data_extraction_rules.xml). На iPhone — прежняя Library/Caches: скачиваемое
/// заново Apple велит держать вне резервной копии, а Caches iOS трогает только
/// при нехватке места.
@visibleForTesting
String imageCacheDirFor({
  required bool android,
  required String temp,
  required String support,
  required String key,
}) =>
    android ? p.join(support, 'offline', key) : p.join(temp, key);

/// Где кэш лежал до 09.10.2026 — во временной папке пакета.
@visibleForTesting
String legacyImageCacheDir({required String temp, required String key}) =>
    p.join(temp, key);

class _PersistentFileSystem implements FileSystem {
  _PersistentFileSystem(this._key) : _dir = _open(_key);

  final String _key;
  final Future<Directory> _dir;

  static Future<Directory> _open(String key) async {
    const fs = LocalFileSystem();
    final temp = (await getTemporaryDirectory()).path;
    final android = io.Platform.isAndroid;
    final support = android ? (await getApplicationSupportDirectory()).path : temp;
    final path = imageCacheDirFor(android: android, temp: temp, support: support, key: key);
    final dir = fs.directory(path);
    if (android && !await dir.exists()) {
      // Уже скачанное переносим, а не качаем заново: обе папки на одном
      // разделе /data, переименование мгновенное. База кэша хранит путь
      // относительно папки, поэтому записи остаются верными.
      final old = fs.directory(legacyImageCacheDir(temp: temp, key: key));
      try {
        if (await old.exists()) {
          await dir.parent.create(recursive: true);
          await old.rename(path);
        }
      } catch (e) {
        debugPrint('image cache: перенос не удался — $e');
      }
    }
    await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<File> createFile(String name) async {
    final dir = await _dir;
    if (!await dir.exists()) await _open(_key);
    return dir.childFile(name);
  }
}
