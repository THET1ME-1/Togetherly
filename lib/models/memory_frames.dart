/// Кадры записи при правке: прежние (уже на сервере) и только что выбранные.
///
/// Ряд один, обложка — первый в нём. Обычный порядок: сперва прежние, затем
/// новые. Новый кадр можно поставить обложкой — тогда он встаёт первым, а
/// прежние идут за ним. До 10.11.2026 форма в этом случае обнуляла список
/// прежних, и при сохранении они пропадали из записи.
library;

import 'memory.dart';

/// Тип записи после правки, в которую добавили видео: заметка становится
/// видео, запись с фото остаётся фото (ролик идёт рядом с кадрами, как у
/// новой записи из фото и видео разом).
MemoryType typeWithVideo(MemoryType now) =>
    now == MemoryType.text ? MemoryType.video : now;

/// Откуда кадр на этом месте ряда: из прежних или из новых.
class FrameSlot {
  const FrameSlot.kept(this.index) : kept = true;
  const FrameSlot.fresh(this.index) : kept = false;

  /// Кадр уже лежит в записи (иначе — только что выбран).
  final bool kept;

  /// Номер в своём списке: прежних или новых.
  final int index;

  @override
  bool operator ==(Object other) =>
      other is FrameSlot && other.kept == kept && other.index == index;

  @override
  int get hashCode => Object.hash(kept, index);

  @override
  String toString() => kept ? 'прежний $index' : 'новый $index';
}

/// Какой кадр стоит на месте [position] общего ряда.
///
/// [freshCover] — первый новый кадр поставлен обложкой. Отметка работает,
/// только когда есть и прежние, и новые: иначе сдвигать нечего.
FrameSlot frameSlot(
  int position, {
  required int keptCount,
  required int freshCount,
  required bool freshCover,
}) {
  final freshFirst = freshCover && freshCount > 0 && keptCount > 0;
  if (!freshFirst) {
    return position < keptCount
        ? FrameSlot.kept(position)
        : FrameSlot.fresh(position - keptCount);
  }
  if (position == 0) return const FrameSlot.fresh(0);
  if (position <= keptCount) return FrameSlot.kept(position - 1);
  return FrameSlot.fresh(position - keptCount);
}

/// Список кадров записи после сохранения правки.
///
/// [uploaded] — ссылки новых кадров в порядке формы; `null` у кадра, который
/// не загрузился. Обложка не загрузилась — обложкой остаётся первый прежний.
List<String> framesAfterEdit({
  required List<String> kept,
  required List<String?> uploaded,
  required bool freshCover,
}) {
  final cover = freshCover && uploaded.isNotEmpty ? uploaded.first : null;
  final rest = cover == null ? uploaded : uploaded.skip(1);
  return [
    if (cover != null) cover,
    ...kept,
    ...rest.whereType<String>(),
  ];
}
