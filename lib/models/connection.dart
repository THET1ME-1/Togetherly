import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../services/firebase_service.dart';

enum RelationshipType {
  couple, // In Love — max 2
  friends, // Friends — max 10
  buddies, // Best Buddies — max 10
}

/// Info about one group member
class GroupMember {
  final String uid;
  final String name;
  final String avatar;

  const GroupMember({required this.uid, this.name = '', this.avatar = ''});

  Map<String, dynamic> toJson() => {'uid': uid, 'name': name, 'avatar': avatar};

  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
    uid: json['uid'] ?? '',
    name: json['name'] ?? '',
    avatar: json['avatar'] ?? '',
  );
}

/// Info about a member's mood
class MemberMood {
  final String emoji;
  final String label;
  final DateTime? updatedAt;

  const MemberMood({this.emoji = '', this.label = '', this.updatedAt});

  bool get isEmpty => emoji.isEmpty;
  bool get isNotEmpty => emoji.isNotEmpty;

  factory MemberMood.fromJson(Map<String, dynamic> json) {
    DateTime? updatedAt;
    final ts = json['updatedAt'];
    if (ts is DateTime) {
      updatedAt = ts;
    }
    return MemberMood(
      emoji: json['emoji'] ?? '',
      label: json['label'] ?? '',
      updatedAt: updatedAt,
    );
  }
}

/// Represents a single connection/group with 1-9 partners
class Connection {
  final String id;
  bool isPaired; // true if at least 1 partner joined
  DateTime? startDate;

  // Legacy single-partner fields (first partner for compat)
  String partnerName;
  String partnerAvatarUrl;

  // Multi-member fields
  List<GroupMember> members; // ALL members including self

  String inviteCode;
  String pairId; // actually groupId
  RelationshipType relationshipType;

  StreamSubscription? _pairSub;
  final FirebaseService _fb;
  final Function()? onChanged;

  // Mood data: uid -> MemberMood
  Map<String, MemberMood> memberMoods = {};

  Connection({
    required this.id,
    required FirebaseService firebaseService,
    this.isPaired = false,
    this.startDate,
    this.partnerName = '',
    this.partnerAvatarUrl = '',
    List<GroupMember>? members,
    this.inviteCode = '',
    this.pairId = '',
    this.relationshipType = RelationshipType.couple,
    this.onChanged,
  }) : _fb = firebaseService,
       members = members ?? [];

  String get inviteLink => 'https://togetherly.app/invite/$inviteCode';

  /// Max members allowed for this relationship type
  int get maxMembers {
    switch (relationshipType) {
      case RelationshipType.couple:
        return 2;
      case RelationshipType.friends:
      case RelationshipType.buddies:
        return 10;
    }
  }

  /// Can invite more members?
  bool get canInviteMore {
    if (!isPaired) return true; // not yet connected, invite is needed
    if (relationshipType == RelationshipType.couple) return false;
    return members.length < maxMembers;
  }

  /// All partner members (excluding self)
  List<GroupMember> get partners {
    final myUid = _fb.uid ?? '';
    return members.where((m) => m.uid != myUid).toList();
  }

  /// Number of partners (excluding self)
  int get partnerCount => partners.length;

  // ── Counter values ──
  int get daysInLove {
    if (!isPaired || startDate == null) return 0;
    return DateTime.now().difference(startDate!).inDays;
  }

  int get monthsInLove {
    if (!isPaired || startDate == null) return 0;
    final now = DateTime.now();
    int months =
        (now.year - startDate!.year) * 12 + now.month - startDate!.month;
    if (now.day < startDate!.day) months--;
    return months;
  }

  Duration get timeInLove {
    if (!isPaired || startDate == null) return Duration.zero;
    return DateTime.now().difference(startDate!);
  }

  // ── Relationship Type Helpers ──
  String get relationshipLabel {
    switch (relationshipType) {
      case RelationshipType.couple:
        return 'In Love';
      case RelationshipType.friends:
        return 'Friends';
      case RelationshipType.buddies:
        return 'Best Buddies';
    }
  }

  String get relationshipEmoji {
    switch (relationshipType) {
      case RelationshipType.couple:
        return '❤️';
      case RelationshipType.friends:
        return '🤝';
      case RelationshipType.buddies:
        return '👯';
    }
  }

  /// Get my mood
  MemberMood get myMood {
    final myUid = _fb.uid ?? '';
    return memberMoods[myUid] ?? const MemberMood();
  }

  /// Get partner's mood (first partner)
  MemberMood get partnerMood {
    final myUid = _fb.uid ?? '';
    for (final entry in memberMoods.entries) {
      if (entry.key != myUid) return entry.value;
    }
    return const MemberMood();
  }

  /// Get mood by uid
  MemberMood moodOf(String uid) {
    return memberMoods[uid] ?? const MemberMood();
  }

  /// Set my mood
  Future<void> setMood(String emoji, String label) async {
    if (pairId.isEmpty) return;
    final myUid = _fb.uid ?? '';
    memberMoods[myUid] = MemberMood(
      emoji: emoji,
      label: label,
      updatedAt: DateTime.now(),
    );
    onChanged?.call();
    await _fb.setMood(groupId: pairId, emoji: emoji, label: label);
  }

  /// Clear my mood
  Future<void> clearMood() async {
    if (pairId.isEmpty) return;
    final myUid = _fb.uid ?? '';
    memberMoods.remove(myUid);
    onChanged?.call();
    await _fb.clearMood(groupId: pairId);
  }

  void setRelationshipType(RelationshipType type) {
    relationshipType = type;
    // Update maxMembers in Firebase
    if (pairId.isNotEmpty) {
      _fb.updateGroupMaxMembers(pairId, maxMembers);
    }
    onChanged?.call();
  }

  // ── Actions ──
  Future<bool> acceptCode(String code) async {
    if (code.toUpperCase() == inviteCode.toUpperCase()) {
      return false; // Can't connect to yourself
    }

    try {
      final result = await _fb.acceptInviteCode(code.toUpperCase());
      if (result['success'] == true) {
        isPaired = true;
        pairId = result['pairId'] ?? '';
        partnerName = result['partnerName'] ?? '';
        partnerAvatarUrl = result['partnerAvatar'] ?? '';
        startDate = result['startDate'] as DateTime? ?? DateTime.now();

        // Parse members
        final membersList = result['members'] as List<dynamic>?;
        if (membersList != null) {
          members = membersList
              .map(
                (m) => GroupMember(
                  uid: m['uid'] ?? '',
                  name: m['name'] ?? '',
                  avatar: m['avatar'] ?? '',
                ),
              )
              .toList();
        }

        _listenToPair();
        onChanged?.call();
        return true;
      }
    } catch (e) {
      debugPrint('Accept code failed: $e');
    }

    return false;
  }

  bool isSelfCode(String code) {
    return code.toUpperCase() == inviteCode.toUpperCase();
  }

  Future<void> unpair() async {
    try {
      if (pairId.isNotEmpty) {
        await _fb.unpairById(pairId);
      } else {
        await _fb.unpair();
      }
    } catch (e) {
      debugPrint('Unpair failed: $e');
    }

    _pairSub?.cancel();
    isPaired = false;
    startDate = null;
    partnerName = '';
    partnerAvatarUrl = '';
    pairId = '';
    members = [];

    final oldCode = inviteCode;
    final firestoreCode = await _fb.generateNewInviteCode(oldCode: oldCode);
    inviteCode = firestoreCode.isNotEmpty
        ? firestoreCode
        : Connection.generateLocalCode();

    onChanged?.call();
  }

  Future<void> regenerateCode() async {
    final oldCode = inviteCode;
    String firestoreCode;
    if (isPaired && pairId.isNotEmpty && canInviteMore) {
      // Group invite code — tied to this group
      firestoreCode = await _fb.generateGroupInviteCode(
        pairId,
        oldCode: oldCode,
      );
    } else {
      firestoreCode = await _fb.generateNewInviteCode(oldCode: oldCode);
    }
    inviteCode = firestoreCode.isNotEmpty
        ? firestoreCode
        : Connection.generateLocalCode();
    onChanged?.call();
  }

  /// Generate a group-specific invite code (for adding more members)
  Future<String> generateInviteForGroup() async {
    if (pairId.isEmpty) return inviteCode;
    final code = await _fb.generateGroupInviteCode(pairId);
    if (code.isNotEmpty) {
      inviteCode = code;
      onChanged?.call();
    }
    return inviteCode;
  }

  /// Called when real-time listener detects a new pairId
  Future<void> claimPair(String newPairId) async {
    if (isPaired || pairId.isNotEmpty) return;
    pairId = newPairId;
    await refreshPairStatus();
  }

  Future<void> refreshPairStatus() async {
    if (isPaired && pairId.isNotEmpty) {
      _listenToPair();
      return;
    }

    if (pairId.isNotEmpty) {
      try {
        final pairData = await _fb.loadPairById(pairId);
        if (pairData != null) {
          _applyPairData(pairData);
          _listenToPair();
        }
      } catch (e) {
        debugPrint('Pair refresh by id failed: $e');
      }
      onChanged?.call();
      return;
    }

    try {
      final pairData = await _fb.loadPairData();
      if (pairData != null) {
        pairId = pairData['pairId'] ?? '';
        _applyPairData(pairData);
        _listenToPair();
      }
    } catch (e) {
      debugPrint('Pair refresh failed: $e');
    }
    onChanged?.call();
  }

  void _applyPairData(Map<String, dynamic> data) {
    isPaired = true;
    startDate = data['startDate'] as DateTime?;
    partnerName = data['partnerName'] ?? '';
    partnerAvatarUrl = data['partnerAvatar'] ?? '';

    // Parse members
    final membersList = data['members'] as List<dynamic>?;
    if (membersList != null) {
      members = membersList
          .map(
            (m) => GroupMember(
              uid: (m as Map)['uid'] ?? '',
              name: m['name'] ?? '',
              avatar: m['avatar'] ?? '',
            ),
          )
          .toList();
    }

    // Parse moods
    final moodsMap = data['memberMoods'] as Map<String, dynamic>?;
    if (moodsMap != null) {
      memberMoods = moodsMap.map(
        (uid, value) => MapEntry(
          uid,
          MemberMood.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      );
    }
  }

  /// Public wrapper to start real-time listening on this connection's pair
  void startListening() => _listenToPair();

  void _listenToPair() {
    _pairSub?.cancel();
    if (pairId.isEmpty) return;

    _pairSub = _fb.listenToPair(
      pairId: pairId,
      onData: (data) {
        if (data == null) {
          isPaired = false;
          pairId = '';
          partnerName = '';
          partnerAvatarUrl = '';
          startDate = null;
          members = [];
          onChanged?.call();
          return;
        }

        partnerName = data['partnerName'] ?? partnerName;
        partnerAvatarUrl = data['partnerAvatar'] ?? partnerAvatarUrl;
        startDate = data['startDate'] as DateTime? ?? startDate;

        // Update members
        final membersList = data['members'] as List<dynamic>?;
        if (membersList != null) {
          members = membersList
              .map(
                (m) => GroupMember(
                  uid: (m as Map)['uid'] ?? '',
                  name: m['name'] ?? '',
                  avatar: m['avatar'] ?? '',
                ),
              )
              .toList();
        }

        // Update moods
        final moodsMap = data['memberMoods'] as Map<String, dynamic>?;
        if (moodsMap != null) {
          memberMoods = moodsMap.map(
            (uid, value) => MapEntry(
              uid,
              MemberMood.fromJson(Map<String, dynamic>.from(value as Map)),
            ),
          );
        }

        onChanged?.call();
      },
    );
  }

  void dispose() {
    _pairSub?.cancel();
  }

  // ── Helpers ──
  static String generateLocalCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random(DateTime.now().microsecondsSinceEpoch);
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ── Serialization ──
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'isPaired': isPaired,
      'startDate': startDate?.toIso8601String(),
      'partnerName': partnerName,
      'partnerAvatarUrl': partnerAvatarUrl,
      'members': members.map((m) => m.toJson()).toList(),
      'inviteCode': inviteCode,
      'pairId': pairId,
      'relationshipType': relationshipType.name,
    };
  }

  static Connection fromJson(
    Map<String, dynamic> json,
    FirebaseService firebaseService,
    Function()? onChanged,
  ) {
    final membersList = (json['members'] as List<dynamic>?)
        ?.map((m) => GroupMember.fromJson(Map<String, dynamic>.from(m)))
        .toList();

    return Connection(
      id: json['id'] ?? '',
      firebaseService: firebaseService,
      isPaired: json['isPaired'] ?? false,
      startDate: json['startDate'] != null
          ? DateTime.tryParse(json['startDate'])
          : null,
      partnerName: json['partnerName'] ?? '',
      partnerAvatarUrl: json['partnerAvatarUrl'] ?? '',
      members: membersList ?? [],
      inviteCode: json['inviteCode'] ?? '',
      pairId: json['pairId'] ?? '',
      relationshipType: RelationshipType.values.firstWhere(
        (e) => e.name == json['relationshipType'],
        orElse: () => RelationshipType.couple,
      ),
      onChanged: onChanged,
    );
  }
}
