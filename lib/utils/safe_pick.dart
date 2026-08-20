import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart' show XFile;

import 'photo_orientation.dart';

/// Безопасная обёртка над image_picker.
///
/// Когда пользователь отказывает в доступе к камере/галерее, плагин кидает
/// `PlatformException` (`camera_access_denied`, `photo_access_denied` и пр.).
/// Если вызов пикера не обёрнут, это исключение улетает в Crashlytics как
/// **Fatal** — хотя это нормальное действие пользователя, а не краш.
///
/// [safePick] глотает такие сбои пикера и возвращает `null` — вызывающий код
/// уже трактует `null` как «отмена». Для информирования пользователя можно
/// передать [onError] (например, показать снэкбар с подсказкой про настройки).
Future<T?> safePick<T>(
  Future<T?> Function() pick, {
  void Function(PlatformException e)? onError,
}) async {
  try {
    return await _upright(await pick());
  } on PlatformException catch (e) {
    debugPrint('safePick: image_picker failed (${e.code})');
    onError?.call(e);
    return null;
  } catch (e) {
    // Напр. TypeError/«Null check» из нативного пути пикера при пересоздании
    // активити (потерянный результат) — тоже не краш, трактуем как отмену.
    debugPrint('safePick: image_picker error: $e');
    return null;
  }
}

/// Выправляет то, что вернул пикер.
///
/// Фронтальная камера отдаёт кадр зеркальным и лишь помечает это в EXIF, а
/// пометку теряли все дальнейшие шаги — снимок так и уходил в чат, в аватар и
/// в воспоминание отражённым («фотография получается отзеркаленной», жалоба
/// 20.08.2026). Правка стоит здесь, потому что это единственное место, через
/// которое фотографии попадают в приложение; в `cropPhoto` её мало — там
/// проходят не все.
///
/// Всё, что не помеченный зеркальным снимок (видео, обычное фото, чужой
/// формат), возвращается тем же объектом и не переписывается.
Future<T?> _upright<T>(T? picked) async {
  if (picked is XFile) {
    final fixed = await uprightPhotoFile(picked.path);
    return (fixed == null ? picked : XFile(fixed)) as T;
  }
  if (picked is List<XFile>) {
    final out = <XFile>[];
    for (final file in picked) {
      final fixed = await uprightPhotoFile(file.path);
      out.add(fixed == null ? file : XFile(fixed));
    }
    return out as T;
  }
  return picked;
}
