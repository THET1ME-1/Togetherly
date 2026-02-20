import 'package:cloud_firestore/cloud_firestore.dart';

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
  String? photoUrl; // URL фотографии
  String? musicTitle; // название песни
  String? musicArtist; // исполнитель
  String? musicUrl; // ссылка на трек
  String? musicCoverUrl; // обложка альбома
  DateTime? updatedAt;

  WidgetData({
    required this.uid,
    this.displayName = '',
    this.avatarUrl = '',
    this.status = '',
    this.moodEmoji = '',
    this.moodLabel = '',
    this.message = '',
    this.photoUrl,
    this.musicTitle,
    this.musicArtist,
    this.musicUrl,
    this.musicCoverUrl,
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
    'musicTitle': musicTitle,
    'musicArtist': musicArtist,
    'musicUrl': musicUrl,
    'musicCoverUrl': musicCoverUrl,
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
      musicTitle: data['musicTitle'],
      musicArtist: data['musicArtist'],
      musicUrl: data['musicUrl'],
      musicCoverUrl: data['musicCoverUrl'],
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
    String? musicTitle,
    String? musicArtist,
    String? musicUrl,
    String? musicCoverUrl,
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
      photoUrl: photoUrl ?? this.photoUrl,
      musicTitle: musicTitle ?? this.musicTitle,
      musicArtist: musicArtist ?? this.musicArtist,
      musicUrl: musicUrl ?? this.musicUrl,
      musicCoverUrl: musicCoverUrl ?? this.musicCoverUrl,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
