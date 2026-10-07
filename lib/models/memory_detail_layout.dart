import 'memory.dart';

/// Открывается ли запись экраном «как фото»: шапка с автором, крупная
/// обложка, реакции, комментарии и плавающий тулбар. До 07.10.2026 так
/// открывались только фото и видео с кадром, а заметка и видео по ссылке
/// шли старым листом со своей вёрсткой.
///
/// Фото без кадров остаётся листом: крупно показывать нечего.
bool opensAsMoment(MemoryType type, {required bool hasPhotos}) {
  switch (type) {
    case MemoryType.photo:
      return hasPhotos;
    case MemoryType.video:
    case MemoryType.videoLink:
    case MemoryType.text:
      return true;
    case MemoryType.location:
    case MemoryType.music:
    case MemoryType.book:
    case MemoryType.movie:
      return false;
  }
}

/// Подпись в шапке называет число кадров только у фото. У ролика обложка
/// тоже лежит кадром, и подпись «1 фото» у видео врала.
bool momentCountsPhotos(MemoryType type) => type == MemoryType.photo;
