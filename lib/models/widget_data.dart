import 'package:cloud_firestore/cloud_firestore.dart';
import 'mood_entry.dart';

/// Данные, которые пользователь делится через парный виджет.
///
/// Firestore path: `groups/{groupId}/widgetData/{uid}`
class WidgetData {
  final String uid;
  final String displayName;
  final String avatarUrl;

  // ── Слоты контента ──
  String status; // текстовый статус
  String moodEmoji; // путь к изображению emoji (из MoodOption)
  String moodLabel; // текстовая метка настроения
  String message; // короткое сообщение / love note
  String photoDayMode; // 'random' or 'custom'
  String? photoUrl; // URL фотографии (для парного виджета)
  String? photoDayUrl; // URL кастомного фото для виджета "Фото дня"
  int photoGridCount; // 1, 2 или 4
  List<String> photoGridUrls; // URL фото для сетки
  String? musicTitle; // название песни
  String? musicArtist; // исполнитель
  String? musicUrl; // ссылка на трек
  String? musicCoverUrl; // обложка альбома
  String gender; // 'male' or 'female'
  DateTime? updatedAt;

  WidgetData({
    required this.uid,
    this.displayName = '',
    this.avatarUrl = '',
    this.status = '',
    this.moodEmoji = '',
    this.moodLabel = '',
    this.message = '',
    this.photoDayMode = 'random',
    this.photoUrl,
    this.photoDayUrl,
    this.photoGridCount = 1,
    this.photoGridUrls = const [],

    this.musicTitle,
    this.musicArtist,
    this.musicUrl,
    this.musicCoverUrl,
    this.gender = '',
    this.updatedAt,
  });

  /// Есть ли хоть какой-то контент
  bool get isEmpty =>
      status.isEmpty &&
      moodEmoji.isEmpty &&
      message.isEmpty &&
      photoUrl == null &&
      musicTitle == null;

  bool get hasStatus => status.isNotEmpty;
  bool get hasMood => moodEmoji.isNotEmpty;
  bool get hasMessage => message.isNotEmpty;

  /// Метка настроения на текущем языке (берётся по imagePath из MoodOption).
  String get localizedMoodLabel {
    if (moodEmoji.isEmpty) return moodLabel;
    final option = MoodOption.all.cast<MoodOption?>().firstWhere(
      (m) => m?.imagePath == moodEmoji,
      orElse: () => null,
    );
    return option?.localizedLabel ?? moodLabel;
  }

  bool get hasPhoto => photoUrl != null && photoUrl!.isNotEmpty;
  bool get hasMusic => musicTitle != null && musicTitle!.isNotEmpty;

  // ── Firestore ──

  Map<String, dynamic> toFirestore() => {
    'uid': uid,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'status': status,
    'moodEmoji': moodEmoji,
    'moodLabel': moodLabel,
    'message': message,
    'photoUrl': photoUrl,
    'photoDayUrl': photoDayUrl,
    'photoGridCount': photoGridCount,
    'photoGridUrls': photoGridUrls,
    'musicTitle': musicTitle,
    'musicArtist': musicArtist,
    'musicUrl': musicUrl,
    'musicCoverUrl': musicCoverUrl,
    'gender': gender,
    'photoDayMode': photoDayMode,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  factory WidgetData.fromFirestore(Map<String, dynamic> data) {
    return WidgetData(
      uid: data['uid'] ?? '',
      displayName: data['displayName'] ?? '',
      avatarUrl: data['avatarUrl'] ?? '',
      status: data['status'] ?? '',
      moodEmoji: data['moodEmoji'] ?? '',
      moodLabel: data['moodLabel'] ?? '',
      message: data['message'] ?? '',
      photoUrl: data['photoUrl'],
      photoDayUrl: data['photoDayUrl'],
      photoGridCount: (data['photoGridCount'] as int?) ?? 1,
      photoGridUrls: List<String>.from(data['photoGridUrls'] ?? []),
      musicTitle: data['musicTitle'],
      musicArtist: data['musicArtist'],
      musicUrl: data['musicUrl'],
      musicCoverUrl: data['musicCoverUrl'],
      gender: data['gender'] ?? '',
      photoDayMode: data['photoDayMode'] ?? 'random',
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  WidgetData copyWith({
    String? uid,
    String? displayName,
    String? avatarUrl,
    String? status,
    String? moodEmoji,
    String? moodLabel,
    String? message,
    String? photoUrl,
    String? photoDayUrl,
    String? musicTitle,
    String? musicArtist,
    String? musicUrl,
    String? musicCoverUrl,
    String? gender,
    String? photoDayMode,
    int? photoGridCount,
    List<String>? photoGridUrls,
    DateTime? updatedAt,
  }) {
    return WidgetData(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      status: status ?? this.status,
      moodEmoji: moodEmoji ?? this.moodEmoji,
      moodLabel: moodLabel ?? this.moodLabel,
      message: message ?? this.message,
      photoDayMode: photoDayMode ?? this.photoDayMode,
      photoUrl: photoUrl ?? this.photoUrl,
      photoDayUrl: photoDayUrl ?? this.photoDayUrl,
      photoGridCount: photoGridCount ?? this.photoGridCount,
      photoGridUrls: photoGridUrls ?? this.photoGridUrls,
      musicTitle: musicTitle ?? this.musicTitle,
      musicArtist: musicArtist ?? this.musicArtist,
      musicUrl: musicUrl ?? this.musicUrl,
      musicCoverUrl: musicCoverUrl ?? this.musicCoverUrl,
      gender: gender ?? this.gender,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
