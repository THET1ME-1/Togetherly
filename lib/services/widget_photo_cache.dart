/// Правила выдачи фото нативному виджету.
///
/// Файл для расширения лежит в общем контейнере (на iOS — App Group), а решение
/// «качать заново или взять готовое» раньше принималось по двум записям в
/// SharedPreferences: прежняя ссылка и прежний путь. Записи переживают всё, а
/// файл — нет: контейнер чистится при смене аккаунта (`wipeWidgetData`), фоновый
/// проход мог записать пустоту, iOS может вымести кэш. Путь в записях
/// оставался, файла не было, повторное скачивание не запускалось никогда — и
/// виджет держал ссылку в пустоту, показывая плейсхолдер.
library;

enum PhotoCacheAction {
  /// Файл на месте и ссылка та же — переиспользуем.
  useCached,

  /// Качаем заново.
  download,
}

/// Меньше этого файл картинкой быть не может: обрывок записи, а не фото.
const int kMinWidgetPhotoBytes = 1024;

/// Что делать с фото по ключу виджета.
///
/// [cachedFileSize] — размер файла на диске. Существования мало: оборванная
/// запись оставляет НУЛЕВОЙ файл, и он залипал навсегда — «файл на месте»
/// значило «в сеть не идём», виджет показывал пустоту, и смена фото ничего не
/// меняла (пять жалоб за сутки 30–31.08.2026). На iOS фоновый проход прибивают
/// по таймауту, так что обрывок — обычное дело, а не редкость.
PhotoCacheAction photoCacheDecision({
  required String url,
  required String cachedUrl,
  required String cachedPath,
  required bool cachedFileExists,
  int cachedFileSize = kMinWidgetPhotoBytes,
}) {
  if (url.isEmpty) return PhotoCacheAction.download;
  if (cachedUrl != url) return PhotoCacheAction.download;
  if (cachedPath.isEmpty || !cachedFileExists) return PhotoCacheAction.download;
  if (cachedFileSize < kMinWidgetPhotoBytes) return PhotoCacheAction.download;
  return PhotoCacheAction.useCached;
}

/// Что записать в ключ, когда скачать не удалось.
///
/// Прежде на любой ошибке писалась пустая строка, и рабочий снимок исчезал со
/// стола из-за одного неудачного запроса. Живой прежний файл лучше пустоты:
/// человек увидит вчерашнее фото, а не серый прямоугольник.
String photoFallbackOnFailure({
  required String cachedPath,
  required bool cachedFileExists,
  int cachedFileSize = kMinWidgetPhotoBytes,
}) {
  if (cachedPath.isEmpty || !cachedFileExists) return '';
  // Пустой файл не «вчерашнее фото», а серый прямоугольник: отдавать его
  // незачем — пусть виджет останется с прежним значением ключа.
  if (cachedFileSize < kMinWidgetPhotoBytes) return '';
  return cachedPath;
}

/// Показывать ли на виджете «Дни вместе» фото пары вместо рисунка.
///
/// Обе аватарки должны лежать на диске: виджет рисует их из файлов, и одной
/// половины ему мало. Ответ — это ещё и то, что видит человек в тумблере:
/// пока состояние писалось по просьбе, а не по факту, тумблер обещал фото,
/// которых на рабочем столе нет (жалоба 01.09.2026).
bool daysPhotosApplied({
  required bool requested,
  required String myPath,
  required String partnerPath,
}) =>
    requested && myPath.isNotEmpty && partnerPath.isNotEmpty;
