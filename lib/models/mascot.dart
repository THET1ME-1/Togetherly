import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:love_app/services/locale_service.dart';

enum MascotMoodState { happy, sad, verySad }

/// One mascot in the group gallery.
class Mascot {
  final String id;
  String name;

  /// Remote URL (Firebase Storage) for user-drawn mascots. Null for defaults.
  final String? imageUrl;

  /// Asset path for default company mascots. Null for user-drawn.
  final String? defaultAsset;

  final String createdBy;
  final DateTime createdAt;
  final bool isDefault;

  /// Maximum streak days while this mascot was active (all-time record).
  int recordStreak;

  Mascot({
    required this.id,
    required this.name,
    this.imageUrl,
    this.defaultAsset,
    required this.createdBy,
    required this.createdAt,
    this.isDefault = false,
    this.recordStreak = 0,
  });

  bool get hasImage => imageUrl != null || defaultAsset != null;

  /// Returns the locale-aware name for built-in mascots; falls back to [name] for user-created ones.
  String get localizedName {
    if (!isDefault) return name;
    final s = LocaleService.current;
    switch (id) {
      case 'default_boy': return s.mascotBoyName;
      case 'default_girl': return s.mascotGirlName;
      default: return name;
    }
  }

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'name': name,
    'imageUrl': imageUrl,
    'defaultAsset': defaultAsset,
    'createdBy': createdBy,
    'createdAt': Timestamp.fromDate(createdAt),
    'isDefault': isDefault,
    'recordStreak': recordStreak,
  };

  factory Mascot.fromFirestore(Map<String, dynamic> data) {
    DateTime createdAt = DateTime.now();
    final ts = data['createdAt'];
    if (ts is Timestamp) createdAt = ts.toDate();

    return Mascot(
      id: data['id'] as String? ?? '',
      name: data['name'] as String? ?? '',
      imageUrl: data['imageUrl'] as String?,
      defaultAsset: data['defaultAsset'] as String?,
      createdBy: data['createdBy'] as String? ?? '',
      createdAt: createdAt,
      isDefault: data['isDefault'] as bool? ?? false,
      recordStreak: (data['recordStreak'] as num?)?.toInt() ?? 0,
    );
  }

  Mascot copyWith({String? name, String? imageUrl, int? recordStreak}) {
    return Mascot(
      id: id,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      defaultAsset: defaultAsset,
      createdBy: createdBy,
      createdAt: createdAt,
      isDefault: isDefault,
      recordStreak: recordStreak ?? this.recordStreak,
    );
  }
}

/// Shared mascot state synced via the group document.
class GroupMascotState {
  final String? activeMascotId;
  final double positionX; // 0.0–1.0 relative to screen width
  final double positionY; // 0.0–1.0 relative to screen height
  final double scale;
  final int streakDays;
  final String? streakLastOpenedDate; // "YYYY-MM-DD" local time

  const GroupMascotState({
    this.activeMascotId,
    this.positionX = 0.8,
    this.positionY = 0.7,
    this.scale = 1.0,
    this.streakDays = 0,
    this.streakLastOpenedDate,
  });

  /// Computes the current mood based on when anyone last opened the app.
  MascotMoodState get moodState {
    if (streakLastOpenedDate == null) return MascotMoodState.sad;
    final today = _localDateStr(DateTime.now());
    final yesterday = _localDateStr(
      DateTime.now().subtract(const Duration(days: 1)),
    );
    if (streakLastOpenedDate == today || streakLastOpenedDate == yesterday) {
      return MascotMoodState.happy;
    }
    final lastDate = DateTime.tryParse(streakLastOpenedDate!);
    if (lastDate == null) return MascotMoodState.sad;
    final diff = DateTime.now().difference(lastDate).inDays;
    return diff > 3 ? MascotMoodState.verySad : MascotMoodState.sad;
  }

  static String _localDateStr(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  factory GroupMascotState.fromMap(Map<String, dynamic> data) {
    return GroupMascotState(
      activeMascotId: data['activeMascotId'] as String?,
      positionX: (data['mascotPositionX'] as num?)?.toDouble() ?? 0.8,
      positionY: (data['mascotPositionY'] as num?)?.toDouble() ?? 0.7,
      scale: (data['mascotScale'] as num?)?.toDouble() ?? 1.0,
      streakDays: (data['streakDays'] as num?)?.toInt() ?? 0,
      streakLastOpenedDate: data['streakLastOpenedDate'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'activeMascotId': activeMascotId,
    'mascotPositionX': positionX,
    'mascotPositionY': positionY,
    'mascotScale': scale,
    'streakDays': streakDays,
    'streakLastOpenedDate': streakLastOpenedDate,
  };

  GroupMascotState copyWith({
    String? activeMascotId,
    double? positionX,
    double? positionY,
    double? scale,
    int? streakDays,
    String? streakLastOpenedDate,
    bool clearActiveMascot = false,
  }) {
    return GroupMascotState(
      activeMascotId: clearActiveMascot
          ? null
          : (activeMascotId ?? this.activeMascotId),
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
      scale: scale ?? this.scale,
      streakDays: streakDays ?? this.streakDays,
      streakLastOpenedDate: streakLastOpenedDate ?? this.streakLastOpenedDate,
    );
  }
}

/// The default mascots bundled with the app.
class DefaultMascots {
  static const String _base = 'assets/images/mascots';

  static List<Map<String, String>> get entries => [
    {
      'id': 'default_boy',
      'name': 'Пиксик',
      'asset': '$_base/Веселый мальчик.png',
    },
    {
      'id': 'default_girl',
      'name': 'Пикси',
      'asset': '$_base/Веселая девочка.png',
    },
  ];

  static List<Mascot> asMascots() {
    return entries
        .map(
          (e) => Mascot(
            id: e['id']!,
            name: e['name']!,
            defaultAsset: e['asset'],
            createdBy: 'system',
            createdAt: DateTime(2024),
            isDefault: true,
          ),
        )
        .toList();
  }
}
