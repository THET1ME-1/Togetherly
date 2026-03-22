import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Предустановленные настроения с цветами.
class MoodOption {
  final String id;
  final String imagePath;
  final String label;
  final Color color;

  const MoodOption({
    required this.id,
    required this.imagePath,
    required this.label,
    required this.color,
  });

  int get score {
    switch (id) {
      case 'happy': case 'starstruck': case 'yummy': case 'laughing': case 'grin': case 'kiss': case 'love': case 'blessed': case 'laughing_hard':
        return 5;
      case 'winking': case 'flush': case 'smirking': case 'cool': case 'blush':
        return 4;
      case 'no_expression': case 'secret': case 'mute': case 'sleepy': case 'surprised': case 'shy':
        return 3;
      case 'sad': case 'liar': case 'greed': case 'disappointment': case 'disappointed': case 'sick': case 'tired': case 'sweating': case 'confused': case 'grimacing': case 'rolling_eyes': case 'unamused': case 'cold': case 'annoyed': case 'astonished':
        return 2;
      case 'crying': case 'crying_hard': case 'angry': case 'dead': case 'crazy': case 'angry_rage': case 'disappointed_bad': case 'devil': case 'dizzy': case 'drooling': case 'scared': case 'angry_furious': case 'sick_fever': case 'vomiting': case 'surprised_shock':
        return 1;
      default:
        return 3;
    }
  }

  static const List<MoodOption> all = [
    MoodOption(
      id: 'sad',
      imagePath: 'assets/images/emoji/001-sad.png',
      label: 'Грустный',
      color: Color(0xFF6B7280),
    ),
    MoodOption(
      id: 'winking',
      imagePath: 'assets/images/emoji/002-winking.png',
      label: 'Подмигиваю',
      color: Color(0xFFFBBF24),
    ),
    MoodOption(
      id: 'liar',
      imagePath: 'assets/images/emoji/003-liar.png',
      label: 'Врунишка',
      color: Color(0xFFF59E0B),
    ),
    MoodOption(
      id: 'greed',
      imagePath: 'assets/images/emoji/004-greed.png',
      label: 'Жадный',
      color: Color(0xFF10B981),
    ),
    MoodOption(
      id: 'crying',
      imagePath: 'assets/images/emoji/005-crying.png',
      label: 'Плачу',
      color: Color(0xFF3B82F6),
    ),
    MoodOption(
      id: 'starstruck',
      imagePath: 'assets/images/emoji/006-starstruck.png',
      label: 'Восхищён',
      color: Color(0xFFFBBF24),
    ),
    MoodOption(
      id: 'happy',
      imagePath: 'assets/images/emoji/007-happy.png',
      label: 'Счастливый',
      color: Color(0xFFFBBF24),
    ),
    MoodOption(
      id: 'no_expression',
      imagePath: 'assets/images/emoji/008-no-expression.png',
      label: 'Без эмоций',
      color: Color(0xFF9CA3AF),
    ),
    MoodOption(
      id: 'disappointment',
      imagePath: 'assets/images/emoji/009-disappointment.png',
      label: 'Разочарован',
      color: Color(0xFF6B7280),
    ),
    MoodOption(
      id: 'disappointed',
      imagePath: 'assets/images/emoji/010-disappointed.png',
      label: 'Расстроен',
      color: Color(0xFF6B7280),
    ),
    MoodOption(
      id: 'yummy',
      imagePath: 'assets/images/emoji/011-yummy.png',
      label: 'Вкусно',
      color: Color(0xFFEC4899),
    ),
    MoodOption(
      id: 'crying_hard',
      imagePath: 'assets/images/emoji/012-crying-1.png',
      label: 'Плачу сильно',
      color: Color(0xFF3B82F6),
    ),
    MoodOption(
      id: 'angry',
      imagePath: 'assets/images/emoji/013-angry.png',
      label: 'Злой',
      color: Color(0xFFEF4444),
    ),
    MoodOption(
      id: 'blush',
      imagePath: 'assets/images/emoji/014-blush.png',
      label: 'Смущён',
      color: Color(0xFFEC4899),
    ),
    MoodOption(
      id: 'dead',
      imagePath: 'assets/images/emoji/015-dead.png',
      label: 'Мёртв',
      color: Color(0xFF475569),
    ),
    MoodOption(
      id: 'crazy',
      imagePath: 'assets/images/emoji/016-crazy.png',
      label: 'Сумасшедший',
      color: Color(0xFFA855F7),
    ),
    MoodOption(
      id: 'cool',
      imagePath: 'assets/images/emoji/017-cool.png',
      label: 'Крутой',
      color: Color(0xFF06B6D4),
    ),
    MoodOption(
      id: 'angry_rage',
      imagePath: 'assets/images/emoji/018-angry-1.png',
      label: 'Ярость',
      color: Color(0xFFDC2626),
    ),
    MoodOption(
      id: 'disappointed_bad',
      imagePath: 'assets/images/emoji/019-disappointed-1.png',
      label: 'Очень расстроен',
      color: Color(0xFF64748B),
    ),
    MoodOption(
      id: 'laughing',
      imagePath: 'assets/images/emoji/020-laughing.png',
      label: 'Смеюсь',
      color: Color(0xFFFBBF24),
    ),
    MoodOption(
      id: 'surprised',
      imagePath: 'assets/images/emoji/021-surprised.png',
      label: 'Удивлён',
      color: Color(0xFFF59E0B),
    ),
    MoodOption(
      id: 'devil',
      imagePath: 'assets/images/emoji/022-devil.png',
      label: 'Дьявол',
      color: Color(0xFFDC2626),
    ),
    MoodOption(
      id: 'dizzy',
      imagePath: 'assets/images/emoji/023-dizzy.png',
      label: 'Кружится голова',
      color: Color(0xFF8B5CF6),
    ),
    MoodOption(
      id: 'drooling',
      imagePath: 'assets/images/emoji/024-drooling.png',
      label: 'Слюни текут',
      color: Color(0xFF10B981),
    ),
    MoodOption(
      id: 'flush',
      imagePath: 'assets/images/emoji/025-flush.png',
      label: 'Покраснел',
      color: Color(0xFFEF4444),
    ),
    MoodOption(
      id: 'grimacing',
      imagePath: 'assets/images/emoji/026-grimacing.png',
      label: 'Скривился',
      color: Color(0xFF64748B),
    ),
    MoodOption(
      id: 'grin',
      imagePath: 'assets/images/emoji/027-grin.png',
      label: 'Ухмыляюсь',
      color: Color(0xFFFBBF24),
    ),
    MoodOption(
      id: 'kiss',
      imagePath: 'assets/images/emoji/028-kiss.png',
      label: 'Целую',
      color: Color(0xFFEE2B6C),
    ),
    MoodOption(
      id: 'secret',
      imagePath: 'assets/images/emoji/029-secret.png',
      label: 'Секрет',
      color: Color(0xFF8B5CF6),
    ),
    MoodOption(
      id: 'scared',
      imagePath: 'assets/images/emoji/030-scared.png',
      label: 'Испуган',
      color: Color(0xFF6366F1),
    ),
    MoodOption(
      id: 'rolling_eyes',
      imagePath: 'assets/images/emoji/031-rolling-eyes.png',
      label: 'Закатываю глаза',
      color: Color(0xFF9CA3AF),
    ),
    MoodOption(
      id: 'mute',
      imagePath: 'assets/images/emoji/032-mute.png',
      label: 'Молчу',
      color: Color(0xFF94A3B8),
    ),
    MoodOption(
      id: 'love',
      imagePath: 'assets/images/emoji/033-love.png',
      label: 'Влюблён',
      color: Color(0xFFEE2B6C),
    ),
    MoodOption(
      id: 'angry_furious',
      imagePath: 'assets/images/emoji/034-angry-2.png',
      label: 'Взбешён',
      color: Color(0xFFB91C1C),
    ),
    MoodOption(
      id: 'laughing_hard',
      imagePath: 'assets/images/emoji/035-laughing-1.png',
      label: 'Хохочу',
      color: Color(0xFFFBBF24),
    ),
    MoodOption(
      id: 'shy',
      imagePath: 'assets/images/emoji/036-shy.png',
      label: 'Стесняюсь',
      color: Color(0xFFF472B6),
    ),
    MoodOption(
      id: 'sick',
      imagePath: 'assets/images/emoji/037-sick.png',
      label: 'Болен',
      color: Color(0xFF94A3B8),
    ),
    MoodOption(
      id: 'sick_fever',
      imagePath: 'assets/images/emoji/038-sick-1.png',
      label: 'Лихорадка',
      color: Color(0xFFEF4444),
    ),
    MoodOption(
      id: 'annoyed',
      imagePath: 'assets/images/emoji/039-annoyed.png',
      label: 'Раздражён',
      color: Color(0xFFF59E0B),
    ),
    MoodOption(
      id: 'sleepy',
      imagePath: 'assets/images/emoji/040-sleepy.png',
      label: 'Сонный',
      color: Color(0xFF818CF8),
    ),
    MoodOption(
      id: 'smirking',
      imagePath: 'assets/images/emoji/041-smirking.png',
      label: 'Усмехаюсь',
      color: Color(0xFF06B6D4),
    ),
    MoodOption(
      id: 'surprised_shock',
      imagePath: 'assets/images/emoji/042-surprised-1.png',
      label: 'Шокирован',
      color: Color(0xFFFBBF24),
    ),
    MoodOption(
      id: 'cold',
      imagePath: 'assets/images/emoji/043-cold.png',
      label: 'Холодно',
      color: Color(0xFF3B82F6),
    ),
    MoodOption(
      id: 'blessed',
      imagePath: 'assets/images/emoji/044-blessed.png',
      label: 'Благословлён',
      color: Color(0xFFFBBF24),
    ),
    MoodOption(
      id: 'astonished',
      imagePath: 'assets/images/emoji/045-astonished.png',
      label: 'Изумлён',
      color: Color(0xFFA78BFA),
    ),
    MoodOption(
      id: 'vomiting',
      imagePath: 'assets/images/emoji/046-vomiting.png',
      label: 'Тошнит',
      color: Color(0xFF10B981),
    ),
    MoodOption(
      id: 'unamused',
      imagePath: 'assets/images/emoji/047-unamused.png',
      label: 'Не впечатлён',
      color: Color(0xFF64748B),
    ),
    MoodOption(
      id: 'tired',
      imagePath: 'assets/images/emoji/048-tired.png',
      label: 'Устал',
      color: Color(0xFF94A3B8),
    ),
    MoodOption(
      id: 'sweating',
      imagePath: 'assets/images/emoji/049-sweating.png',
      label: 'Потею',
      color: Color(0xFF3B82F6),
    ),
    MoodOption(
      id: 'confused',
      imagePath: 'assets/images/emoji/050-confused.png',
      label: 'Смущён',
      color: Color(0xFF8B5CF6),
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
  final String imagePath;
  final String label;
  final DateTime timestamp;

  MoodEntry({
    required this.id,
    required this.moodId,
    required this.imagePath,
    required this.label,
    required this.timestamp,
  });

  Color get color => MoodOption.byId(moodId)?.color ?? const Color(0xFF9CA3AF);
  int get score => MoodOption.byId(moodId)?.score ?? 3;

  Map<String, dynamic> toJson() => {
    'id': id,
    'moodId': moodId,
    'imagePath': imagePath,
    'label': label,
    'timestamp': timestamp.toIso8601String(),
  };

  factory MoodEntry.fromJson(Map<String, dynamic> json) => MoodEntry(
    id: json['id'] as String,
    moodId: json['moodId'] as String,
    imagePath: json['imagePath'] as String,
    label: json['label'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
  );

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'moodId': moodId,
    'imagePath': imagePath,
    'label': label,
    'timestamp': Timestamp.fromDate(timestamp),
  };

  factory MoodEntry.fromFirestore(Map<String, dynamic> json) => MoodEntry(
    id: json['id'] as String? ?? '',
    moodId: json['moodId'] as String? ?? '',
    imagePath: json['imagePath'] as String? ?? '',
    label: json['label'] as String? ?? '',
    timestamp: (json['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
  );

  /// Дневной ключ для группировки (yyyy-MM-dd)
  String get dayKey {
    final y = timestamp.year.toString().padLeft(4, '0');
    final m = timestamp.month.toString().padLeft(2, '0');
    final d = timestamp.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
