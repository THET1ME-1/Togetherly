import 'package:flutter/foundation.dart';

import 'media_file_cache.dart';

/// Путь к локальной копии звука или ролика: качаем один раз, дальше играем с
/// диска.
///
/// [stableKey] — ключ кэша, и он ОБЯЗАН быть постоянным: исходная `pb://`-
/// ссылка, а не адрес с file-токеном. Токен живёт минуты, и по нему кэш
/// промахивался бы каждый раз — на этом уже обожглись с аватарками.
/// [httpUrl] — адрес, по которому файл реально качается.
///
/// Возвращает null, если скачать не вышло: зовущий тогда играет прямо из сети,
/// как раньше. Кэш — ускорение и экономия, а не условие работы.
Future<String?> cachedMediaPath(String stableKey, String httpUrl) async {
  try {
    final hit = await OfflineMediaCacheManager.instance.getFileFromCache(
      stableKey,
    );
    if (hit != null && hit.file.existsSync()) return hit.file.path;
  } catch (e) {
    debugPrint('cachedMediaPath: кэш не прочитался — $e');
  }
  try {
    final got = await OfflineMediaCacheManager.instance.downloadFile(
      httpUrl,
      key: stableKey,
    );
    return got.file.existsSync() ? got.file.path : null;
  } catch (e) {
    debugPrint('cachedMediaPath: не скачалось — $e');
    return null;
  }
}
