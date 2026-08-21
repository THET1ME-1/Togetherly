import 'memory.dart';

/// Одна фотография из ленты: адрес и подпись записи, которой она принадлежит.
typedef MemoryPhoto = ({String url, String? caption});

/// Снимки из записей ленты — для выбора фото в виджет.
///
/// Правило вынесено из листа выбора, потому что мелочей тут три: у записи
/// бывает несколько кадров, обложка обычно повторяется среди них, а пустая
/// ссылка даёт битую плитку вместо фотографии.
List<MemoryPhoto> photosFromMemories(List<Memory> memories) {
  final out = <MemoryPhoto>[];
  for (final m in memories) {
    if (m.type != MemoryType.photo) continue;
    final caption = m.caption;
    final cover = m.imageUrl;
    if (cover != null && cover.isNotEmpty) {
      out.add((url: cover, caption: caption));
    }
    for (final u in m.imageUrls ?? const <String>[]) {
      if (u.isEmpty || u == cover) continue;
      out.add((url: u, caption: caption));
    }
  }
  return out;
}
