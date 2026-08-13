import 'package:pocketbase/pocketbase.dart';

import '../utils/pair_time.dart';

/// A comment on a memory entry
class MemoryComment {
  final String id;
  final String authorUid;
  final String authorName;
  final String authorAvatar;
  final String text;
  final DateTime createdAt;

  MemoryComment({
    required this.id,
    required this.authorUid,
    required this.authorName,
    this.authorAvatar = '',
    required this.text,
    required this.createdAt,
  });

  /// PocketBase-запись (коллекция `memory_comments`) → модель. Плоские
  /// snake_case колонки; id = id записи; created_at — ISO-строка.
  factory MemoryComment.fromPb(RecordModel rec) {
    final d = rec.data;
    return MemoryComment(
      id: rec.id,
      authorUid: (d['author_uid'] ?? '').toString(),
      authorName: (d['author_name'] ?? '').toString(),
      authorAvatar: (d['author_avatar'] ?? '').toString(),
      text: (d['text'] ?? '').toString(),
      createdAt: PairTime.read(d['created_at'], (d['tz'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}
