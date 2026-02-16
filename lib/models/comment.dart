import 'package:cloud_firestore/cloud_firestore.dart';

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
}
