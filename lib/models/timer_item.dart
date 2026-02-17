import 'dart:convert';

/// Модель одного таймера (счётчик дней/времени с определённой даты).
class TimerItem {
  final String id;
  String title;
  DateTime startDate;
  bool isDefault;
  String emoji;
  bool isSystem; // system timers can't be deleted or renamed

  TimerItem({
    required this.id,
    required this.title,
    required this.startDate,
    this.isDefault = false,
    this.emoji = '❤️',
    this.isSystem = false,
  });

  // ── Вычисляемые значения ──

  int get daysElapsed => DateTime.now().difference(startDate).inDays;

  int get monthsElapsed {
    final now = DateTime.now();
    int months = (now.year - startDate.year) * 12 + now.month - startDate.month;
    if (now.day < startDate.day) months--;
    return months;
  }

  Duration get timeElapsed => DateTime.now().difference(startDate);

  String get formattedTime {
    final diff = timeElapsed;
    final d = diff.inDays;
    final h = diff.inHours % 24;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    if (d > 0) return '${d}d ${h}h ${m}m';
    if (h > 0) return '${h}h ${m}m ${s}s';
    return '${m}m ${s}s';
  }

  String get formattedStartDate {
    final d = startDate.day.toString().padLeft(2, '0');
    final m = startDate.month.toString().padLeft(2, '0');
    final y = startDate.year.toString();
    return '$d.$m.$y';
  }

  // ── Сериализация ──

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'startDate': startDate.toIso8601String(),
    'isDefault': isDefault,
    'emoji': emoji,
    'isSystem': isSystem,
  };

  factory TimerItem.fromJson(Map<String, dynamic> json) => TimerItem(
    id: json['id'] as String,
    title: json['title'] as String,
    startDate: DateTime.parse(json['startDate'] as String),
    isDefault: json['isDefault'] as bool? ?? false,
    emoji: json['emoji'] as String? ?? '❤️',
    isSystem: json['isSystem'] as bool? ?? false,
  );

  static String encodeList(List<TimerItem> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  static List<TimerItem> decodeList(String source) {
    final list = jsonDecode(source) as List;
    return list
        .map((e) => TimerItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  TimerItem copyWith({
    String? id,
    String? title,
    DateTime? startDate,
    bool? isDefault,
    String? emoji,
    bool? isSystem,
  }) => TimerItem(
    id: id ?? this.id,
    title: title ?? this.title,
    startDate: startDate ?? this.startDate,
    isDefault: isDefault ?? this.isDefault,
    emoji: emoji ?? this.emoji,
    isSystem: isSystem ?? this.isSystem,
  );
}
