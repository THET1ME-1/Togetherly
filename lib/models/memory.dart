import 'package:cloud_firestore/cloud_firestore.dart';

/// Types of memory content
enum MemoryType {
  photo,
  video,
  location,
  music,
  text,
}

/// A single memory entry in the shared Memory Lane
class Memory {
  final String id;
  final String groupId;
  final String authorUid;
  final String authorName;
  final String authorAvatar;
  final MemoryType type;
  final DateTime createdAt;
  DateTime? editedAt;

  // Content fields (used depending on type)
  String? imageUrl; // photo / video thumbnail
  String? videoUrl; // video URL
  String? caption; // text caption
  String? locationName; // e.g. "Central Park Coffee"
  double? latitude;
  double? longitude;
  String? musicTitle; // song name
  String? musicArtist; // artist name
  String? musicCoverUrl; // album art

  bool isPinned;

  Memory({
    required this.id,
    required this.groupId,
    required this.authorUid,
    required this.authorName,
    this.authorAvatar = '',
    required this.type,
    required this.createdAt,
    this.editedAt,
    this.imageUrl,
    this.videoUrl,
    this.caption,
    this.locationName,
    this.latitude,
    this.longitude,
    this.musicTitle,
    this.musicArtist,
    this.musicCoverUrl,
    this.isPinned = false,
  });

  /// Human-friendly type label
  String get typeLabel {
    switch (type) {
      case MemoryType.photo:
        return 'Photo';
      case MemoryType.video:
        return 'Video';
      case MemoryType.location:
        return 'Location';
      case MemoryType.music:
        return 'Music';
      case MemoryType.text:
        return 'Note';
    }
  }

  String get typeEmoji {
    switch (type) {
      case MemoryType.photo:
        return '📷';
      case MemoryType.video:
        return '🎬';
      case MemoryType.location:
        return '📍';
      case MemoryType.music:
        return '🎵';
      case MemoryType.text:
        return '📝';
    }
  }

  /// Serialize to Firestore map
  Map<String, dynamic> toFirestore() {
    return {
      'groupId': groupId,
      'authorUid': authorUid,
      'authorName': authorName,
      'authorAvatar': authorAvatar,
      'type': type.name,
      'createdAt': Timestamp.fromDate(createdAt),
      if (editedAt != null) 'editedAt': Timestamp.fromDate(editedAt!),
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (videoUrl != null) 'videoUrl': videoUrl,
      if (caption != null) 'caption': caption,
      if (locationName != null) 'locationName': locationName,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (musicTitle != null) 'musicTitle': musicTitle,
      if (musicArtist != null) 'musicArtist': musicArtist,
      if (musicCoverUrl != null) 'musicCoverUrl': musicCoverUrl,
      'isPinned': isPinned,
    };
  }

  /// Deserialize from Firestore
  factory Memory.fromFirestore(String id, Map<String, dynamic> data) {
    return Memory(
      id: id,
      groupId: data['groupId'] ?? '',
      authorUid: data['authorUid'] ?? '',
      authorName: data['authorName'] ?? '',
      authorAvatar: data['authorAvatar'] ?? '',
      type: MemoryType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => MemoryType.text,
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      editedAt: (data['editedAt'] as Timestamp?)?.toDate(),
      imageUrl: data['imageUrl'],
      videoUrl: data['videoUrl'],
      caption: data['caption'],
      locationName: data['locationName'],
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      musicTitle: data['musicTitle'],
      musicArtist: data['musicArtist'],
      musicCoverUrl: data['musicCoverUrl'],
      isPinned: data['isPinned'] ?? false,
    );
  }

  /// Local JSON serialization
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'groupId': groupId,
      'authorUid': authorUid,
      'authorName': authorName,
      'authorAvatar': authorAvatar,
      'type': type.name,
      'createdAt': createdAt.toIso8601String(),
      'editedAt': editedAt?.toIso8601String(),
      'imageUrl': imageUrl,
      'videoUrl': videoUrl,
      'caption': caption,
      'locationName': locationName,
      'latitude': latitude,
      'longitude': longitude,
      'musicTitle': musicTitle,
      'musicArtist': musicArtist,
      'musicCoverUrl': musicCoverUrl,
      'isPinned': isPinned,
    };
  }

  factory Memory.fromJson(Map<String, dynamic> json) {
    return Memory(
      id: json['id'] ?? '',
      groupId: json['groupId'] ?? '',
      authorUid: json['authorUid'] ?? '',
      authorName: json['authorName'] ?? '',
      authorAvatar: json['authorAvatar'] ?? '',
      type: MemoryType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MemoryType.text,
      ),
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      editedAt: json['editedAt'] != null
          ? DateTime.tryParse(json['editedAt'])
          : null,
      imageUrl: json['imageUrl'],
      videoUrl: json['videoUrl'],
      caption: json['caption'],
      locationName: json['locationName'],
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      musicTitle: json['musicTitle'],
      musicArtist: json['musicArtist'],
      musicCoverUrl: json['musicCoverUrl'],
      isPinned: json['isPinned'] ?? false,
    );
  }
}
