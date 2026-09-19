/// Пункты меню «три точки» в листе воспоминания.
///
/// До 19.09.2026 в меню было два пункта — «Указать место» и «Удалить» своей
/// записи, — а у чужой записи с уже отмеченным местом код молча выходил, и
/// кнопка выглядела декорацией. Правило вынесено сюда, чтобы его можно было
/// проверить без экрана и чтобы лист не показывал кнопку, у которой нет
/// действий.
library;

import 'memory.dart';
import 'memory_media.dart';

enum MemoryMenuAction {
  saveAll,
  pick,
  share,
  copyCaption,
  openMap,
  openLink,
  setPlace,
  delete,
}

/// Ссылка на чужую площадку, которую запись может открыть.
String? memoryExternalLink(Memory m) {
  String? pick(String? u) =>
      (u != null && u.trim().isNotEmpty && !isOwnMediaUrl(u)) ? u.trim() : null;
  switch (m.type) {
    case MemoryType.videoLink:
      return pick(m.videoUrl);
    case MemoryType.music:
      return pick(m.musicUrl);
    case MemoryType.book:
      return pick(m.bookInfoUrl);
    case MemoryType.movie:
      return pick(m.movieInfoUrl);
    default:
      return null;
  }
}

List<MemoryMenuAction> memoryMenuActions(
  Memory m, {
  required bool isOwner,
  required bool canSetPlace,
}) {
  final files = memoryMediaFiles(m);
  final hasPlace = m.latitude != null && m.longitude != null;
  return [
    if (files.isNotEmpty) MemoryMenuAction.saveAll,
    if (files.length > 1) MemoryMenuAction.pick,
    if (files.isNotEmpty) MemoryMenuAction.share,
    if (memoryExternalLink(m) != null) MemoryMenuAction.openLink,
    if ((m.caption?.trim().isNotEmpty ?? false)) MemoryMenuAction.copyCaption,
    if (hasPlace) MemoryMenuAction.openMap,
    if (canSetPlace && !hasPlace) MemoryMenuAction.setPlace,
    if (isOwner) MemoryMenuAction.delete,
  ];
}
