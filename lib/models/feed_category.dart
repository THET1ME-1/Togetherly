import 'package:flutter/material.dart';

import 'memory.dart';

/// Тег фильтра в ленте воспоминаний.
///
/// Подпись берётся из словаря по [dictKey], а не парой `ru`/`en` внутри записи:
/// пары хватало только на два языка, а остальные пять видели английский (тот же
/// разбор, что и у каталогов достижений — см. `trKey` в `../dict_strings.dart`).
class FeedCategory {
  const FeedCategory({
    required this.key,
    required this.dictKey,
    required this.icon,
    this.types = const {},
    this.sealedOnly = false,
  });

  /// Ключ выбранного тега в состоянии экрана.
  final String key;

  /// Ключ подписи в словаре.
  final String dictKey;

  final IconData icon;

  /// Типы записей, попадающих под тег.
  final Set<MemoryType> types;

  /// Тег капсул. Капсула — не тип записи, а флаг поверх текста или фото,
  /// поэтому фильтруется отдельно и в [types] её не выразить.
  final bool sealedOnly;

  bool matches(Memory m) => sealedOnly ? m.sealed : types.contains(m.type);
}

/// Теги ленты. Капсулы первыми: за ними приходят по уведомлению об открытии,
/// а остальные записи листают и так.
const List<FeedCategory> kFeedCategories = [
  FeedCategory(
    key: 'capsules',
    dictKey: 'feedTagCapsules',
    icon: Icons.mail_rounded,
    sealedOnly: true,
  ),
  FeedCategory(
    key: 'moments',
    dictKey: 'feedTagMoments',
    icon: Icons.favorite_rounded,
    types: {MemoryType.photo, MemoryType.video},
  ),
  FeedCategory(
    key: 'places',
    dictKey: 'feedTagPlaces',
    icon: Icons.place_rounded,
    types: {MemoryType.location},
  ),
  FeedCategory(
    key: 'music',
    dictKey: 'feedTagMusic',
    icon: Icons.music_note_rounded,
    types: {MemoryType.music},
  ),
  FeedCategory(
    key: 'video',
    dictKey: 'feedTagVideo',
    icon: Icons.play_circle_fill_rounded,
    types: {MemoryType.videoLink},
  ),
  FeedCategory(
    key: 'notes',
    dictKey: 'feedTagNotes',
    icon: Icons.sticky_note_2_rounded,
    types: {MemoryType.text},
  ),
  FeedCategory(
    key: 'books',
    dictKey: 'feedTagBooks',
    icon: Icons.book_rounded,
    types: {MemoryType.book},
  ),
  FeedCategory(
    key: 'movies',
    dictKey: 'feedTagMovies',
    icon: Icons.movie_rounded,
    types: {MemoryType.movie},
  ),
];

/// Теги, которым есть что показать. Пустые в ряд не попадают: у пары с одними
/// фотографиями шесть серых тегов только мешают.
///
/// Один проход по ленте вместо прохода на каждый тег — лента бывает длинной.
List<FeedCategory> presentFeedCategories(Iterable<Memory> memories) {
  final types = <MemoryType>{};
  var hasSealed = false;
  for (final m in memories) {
    types.add(m.type);
    if (m.sealed) hasSealed = true;
  }
  return kFeedCategories
      .where((c) => c.sealedOnly ? hasSealed : c.types.any(types.contains))
      .toList();
}
