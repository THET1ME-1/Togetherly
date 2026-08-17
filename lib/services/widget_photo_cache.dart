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

/// Что делать с фото по ключу виджета.
PhotoCacheAction photoCacheDecision({
  required String url,
  required String cachedUrl,
  required String cachedPath,
  required bool cachedFileExists,
}) {
  if (url.isEmpty) return PhotoCacheAction.download;
  if (cachedUrl != url) return PhotoCacheAction.download;
  if (cachedPath.isEmpty || !cachedFileExists) return PhotoCacheAction.download;
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
}) {
  if (cachedPath.isNotEmpty && cachedFileExists) return cachedPath;
  return '';
}
