import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Кэш звука и роликов: голосовые и видео-воспоминания.
///
/// Отдельный от картинок ([OfflineImageCacheManager]), потому что файлы тут
/// тяжелее и живут по другим правилам: держим 300 штук три месяца, чтобы диск
/// телефона не пух. Картинок можно хранить тысячи, роликов — нет.
///
/// Зачем вообще: до 26.08.2026 голосовые и видео игрались прямо из сети
/// (`setUrl`, `VideoPlayerController.networkUrl`), то есть каждое включение
/// качало файл заново. Замер на раздаче: голосовое просят в среднем 4,2 раза,
/// ролик — 5,7 раза, и каждый раз это был новый трафик.
class OfflineMediaCacheManager extends CacheManager {
  static const key = 'offlineMediaV1';

  static final OfflineMediaCacheManager instance = OfflineMediaCacheManager._();

  OfflineMediaCacheManager._()
      : super(Config(
          key,
          stalePeriod: const Duration(days: 90),
          maxNrOfCacheObjects: 300,
        ));
}
