import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pocketbase/pocketbase.dart';

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

  Map<String, dynamic> toFirestore() {
    return {
      'authorUid': authorUid,
      'authorName': authorName,
      'authorAvatar': authorAvatar,
      'text': text,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory MemoryComment.fromFirestore(String id, Map<String, dynamic> data) {
    return MemoryComment(
      id: id,
      authorUid: data['authorUid'] ?? '',
      authorName: data['authorName'] ?? '',
      authorAvatar: data['authorAvatar'] ?? '',
      text: data['text'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

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
      createdAt:
          DateTime.tryParse((d['created_at'] ?? '').toString()) ?? DateTime.now(),
    );
  }
}
