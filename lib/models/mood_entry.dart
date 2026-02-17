import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Предустановленные настроения с цветами.
class MoodOption {
  final String id;
  final String emoji;
  final String label;
  final Color color;

  const MoodOption({
    required this.id,
    required this.emoji,
    required this.label,
    required this.color,
  });

  static const List<MoodOption> all = [
    MoodOption(
      id: 'happy',
      emoji: '😊',
      label: 'Happy',
      color: Color(0xFFFBBF24),
    ),
    MoodOption(
      id: 'in_love',
      emoji: '🥰',
      label: 'In Love',
      color: Color(0xFFEE2B6C),
    ),
    MoodOption(
      id: 'calm',
      emoji: '😌',
      label: 'Calm',
      color: Color(0xFF60A5FA),
    ),
    MoodOption(
      id: 'sleepy',
      emoji: '😴',
      label: 'Sleepy',
      color: Color(0xFF818CF8),
    ),
    MoodOption(
      id: 'grateful',
      emoji: '🤗',
      label: 'Grateful',
      color: Color(0xFF34D399),
    ),
    MoodOption(id: 'sad', emoji: '😢', label: 'Sad', color: Color(0xFF6B7280)),
    MoodOption(
      id: 'frustrated',
      emoji: '😤',
      label: 'Frustrated',
      color: Color(0xFFEF4444),
    ),
    MoodOption(
      id: 'sick',
      emoji: '🤒',
      label: 'Sick',
      color: Color(0xFF94A3B8),
    ),
    MoodOption(
      id: 'chill',
      emoji: '😎',
      label: 'Chill',
      color: Color(0xFF06B6D4),
    ),
    MoodOption(
      id: 'excited',
      emoji: '🥳',
      label: 'Excited',
      color: Color(0xFFF97316),
    ),
    MoodOption(
      id: 'down',
      emoji: '😔',
      label: 'Down',
      color: Color(0xFF475569),
    ),
    MoodOption(
      id: 'motivated',
      emoji: '💪',
      label: 'Motivated',
      color: Color(0xFFF59E0B),
    ),
    MoodOption(
      id: 'thoughtful',
      emoji: '🤔',
      label: 'Thoughtful',
      color: Color(0xFF8B5CF6),
    ),
    MoodOption(
      id: 'hungry',
      emoji: '😋',
      label: 'Hungry',
      color: Color(0xFFEC4899),
    ),
    MoodOption(
      id: 'inspired',
      emoji: '✨',
      label: 'Inspired',
      color: Color(0xFFA78BFA),
    ),
  ];

  static MoodOption? byId(String id) {
    try {
      return all.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }
}

/// Одна запись настроения за определённое время.
class MoodEntry {
  final String id;
  final String moodId; // id из MoodOption
  final String emoji;
  final String label;
  final DateTime timestamp;

  MoodEntry({
    required this.id,
    required this.moodId,
    required this.emoji,
    required this.label,
    required this.timestamp,
  });

  Color get color => MoodOption.byId(moodId)?.color ?? const Color(0xFF9CA3AF);

  Map<String, dynamic> toJson() => {
    'id': id,
    'moodId': moodId,
    'emoji': emoji,
    'label': label,
    'timestamp': timestamp.toIso8601String(),
  };

  factory MoodEntry.fromJson(Map<String, dynamic> json) => MoodEntry(
    id: json['id'] as String,
    moodId: json['moodId'] as String,
    emoji: json['emoji'] as String,
    label: json['label'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
  );

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'moodId': moodId,
    'emoji': emoji,
    'label': label,
    'timestamp': Timestamp.fromDate(timestamp),
  };

  factory MoodEntry.fromFirestore(Map<String, dynamic> json) => MoodEntry(
    id: json['id'] as String,
    moodId: json['moodId'] as String,
    emoji: json['emoji'] as String,
    label: json['label'] as String,
    timestamp: (json['timestamp'] as Timestamp).toDate(),
  );

  /// Дневной ключ для группировки (yyyy-MM-dd)
  String get dayKey {
    final y = timestamp.year.toString().padLeft(4, '0');
    final m = timestamp.month.toString().padLeft(2, '0');
    final d = timestamp.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
