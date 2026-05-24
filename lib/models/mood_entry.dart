import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/locale_service.dart';

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

  /// Возвращает метку настроения на текущем языке приложения.
  String get localizedLabel {
    if (LocaleService.instance.isRussian) return label;
    switch (id) {
      case 'happy':     return 'Happy';
      case 'love':      return 'In Love';
      case 'kiss':      return 'Kiss';
      case 'laugh':     return 'Laughing';
      case 'pride':     return 'Pride';
      case 'cool':      return 'Cool';
      case 'winking':   return 'Winking';
      case 'drooling':  return 'Drooling';
      case 'embarrassed': return 'Embarrassed';
      case 'no_emotion': return 'No Mood';
      case 'missing':   return 'Missing You';
      case 'sad':       return 'Sad';
      case 'very_sad':  return 'Very Sad';
      case 'hurt':      return 'Hurt';
      case 'liar':      return 'Liar';
      case 'anxiety':   return 'Anxious';
      case 'sick':      return 'Sick';
      case 'surprise':  return 'Surprised';
      case 'fear':      return 'Scared';
      case 'anger':     return 'Angry';
      case 'devil':     return 'Devil';
      default:          return label;
    }
  }

  int get score {
    switch (id) {
      case 'happy':
      case 'love':
      case 'laugh':
      case 'kiss':
        return 5;
      case 'winking':
      case 'pride':
      case 'cool':
      case 'drooling':
        return 4;
      case 'no_emotion':
      case 'embarrassed':
      case 'surprise':
      case 'liar':
        return 3;
      case 'sad':
      case 'sick':
      case 'hurt':
      case 'missing':
      case 'anxiety':
        return 2;
      case 'very_sad':
      case 'anger':
      case 'devil':
      case 'fear':
        return 1;
      default:
        return 3;
    }
  }

  // Цвета соответствуют фонам картинок из папки «new emodji».
  static const _yellow  = Color(0xFFFFC800); // Счастье, Смех, Гордость, Подмигиваю, Крутой
  static const _pink    = Color(0xFFF06EAF); // Люблю, Целую, Смущен
  static const _slate   = Color(0xFF7A7FA8); // Нет эмоций, Скучаю, Болен
  static const _blue    = Color(0xFF6E8FBF); // Грустно, Очень грустно
  static const _purple  = Color(0xFFA066D8); // Тревожность, Страх, Удивление
  static const _red     = Color(0xFFFA282F); // Злость, Дьявол, Врунишка
  static const _skyBlue = Color(0xFF62B8E8); // Слюни текут

  static const List<MoodOption> all = [
    MoodOption(id: 'happy',      imagePath: 'assets/images/new emodji/Счастье.webp',      label: 'Счастье',       color: _yellow),
    MoodOption(id: 'love',       imagePath: 'assets/images/new emodji/Люблю.webp',         label: 'Люблю',         color: _pink),
    MoodOption(id: 'kiss',       imagePath: 'assets/images/new emodji/Целую.webp',         label: 'Целую',         color: _pink),
    MoodOption(id: 'laugh',      imagePath: 'assets/images/new emodji/Смех.webp',          label: 'Смех',          color: _yellow),
    MoodOption(id: 'pride',      imagePath: 'assets/images/new emodji/Гордость.webp',      label: 'Гордость',      color: _yellow),
    MoodOption(id: 'cool',       imagePath: 'assets/images/new emodji/Крутой.webp',        label: 'Крутой',        color: _yellow),
    MoodOption(id: 'winking',    imagePath: 'assets/images/new emodji/Подмигиваю.webp',    label: 'Подмигиваю',    color: _yellow),
    MoodOption(id: 'drooling',   imagePath: 'assets/images/new emodji/Слюни текут.webp',   label: 'Слюни текут',   color: _skyBlue),
    MoodOption(id: 'embarrassed',imagePath: 'assets/images/new emodji/Смущен.webp',        label: 'Смущен',        color: _pink),
    MoodOption(id: 'no_emotion', imagePath: 'assets/images/new emodji/Нет эмоций.webp',    label: 'Нет эмоций',    color: _slate),
    MoodOption(id: 'missing',    imagePath: 'assets/images/new emodji/Скучаю.webp',        label: 'Скучаю',        color: _slate),
    MoodOption(id: 'sad',        imagePath: 'assets/images/new emodji/Грустно.webp',       label: 'Грустно',       color: _blue),
    MoodOption(id: 'very_sad',   imagePath: 'assets/images/new emodji/Очень грустно.webp', label: 'Очень грустно', color: _blue),
    MoodOption(id: 'hurt',       imagePath: 'assets/images/new emodji/Обида.webp',         label: 'Обида',         color: _red),
    MoodOption(id: 'liar',       imagePath: 'assets/images/new emodji/Врунишка.webp',      label: 'Врунишка',      color: _red),
    MoodOption(id: 'anxiety',    imagePath: 'assets/images/new emodji/Тревожность.webp',   label: 'Тревожность',   color: _purple),
    MoodOption(id: 'sick',       imagePath: 'assets/images/new emodji/Болен.webp',         label: 'Болен',         color: _slate),
    MoodOption(id: 'surprise',   imagePath: 'assets/images/new emodji/Удивление.webp',     label: 'Удивление',     color: _purple),
    MoodOption(id: 'fear',       imagePath: 'assets/images/new emodji/Страх.webp',         label: 'Страх',         color: _purple),
    MoodOption(id: 'anger',      imagePath: 'assets/images/new emodji/Злость.webp',        label: 'Злость',        color: _red),
    MoodOption(id: 'devil',      imagePath: 'assets/images/new emodji/Дьявол.webp',        label: 'Дьявол',        color: _red),
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

  /// Метка на текущем языке приложения (перевод по id, не хранимая строка).
  String get localizedLabel => MoodOption.byId(moodId)?.localizedLabel ?? label;

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
