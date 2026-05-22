import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../services/firebase_service.dart';
import '../services/locale_service.dart';
import 'relationship_status.dart';

enum RelationshipType {
  couple, // In Love — max 2
  married, // Married — max 2
  friends, // Friends — max 10
  buddies, // Best Buddies — max 10
  custom, // Custom user-defined type
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
  final String imagePath;
  final String label;
  final DateTime? updatedAt;

  const MemberMood({this.imagePath = '', this.label = '', this.updatedAt});

  bool get isToday {
    if (updatedAt == null) return false;
    final now = DateTime.now();
    return updatedAt!.year == now.year &&
        updatedAt!.month == now.month &&
        updatedAt!.day == now.day;
  }

  bool get isEmpty => imagePath.isEmpty || !isToday;
  bool get isNotEmpty => imagePath.isNotEmpty && isToday;

  factory MemberMood.fromJson(Map<String, dynamic> json) {
    DateTime? updatedAt;
    final ts = json['updatedAt'];
    if (ts is DateTime) {
      updatedAt = ts;
    }
    return MemberMood(
      imagePath: json['imagePath'] ?? json['emoji'] ?? '',
      label: json['label'] ?? '',
      updatedAt: updatedAt,
    );
  }
}

/// Represents a single connection/group with 1-9 partners
class Connection {
  final String id;
  bool isPaired; // true if at least 1 partner joined
  bool isSolo; // true if this is the solo (single user) mode
  DateTime? startDate;

  // Legacy single-partner fields (first partner for compat)
  String partnerName;
  String partnerAvatarUrl;

  // Multi-member fields
  List<GroupMember> members; // ALL members including self

  String inviteCode;
  String pairId; // actually groupId
  RelationshipType relationshipType;

  // Custom relationship type fields
  String customRelationshipLabel;
  String customRelationshipEmoji;

  // Custom relationship types list (shared with partner)
  List<Map<String, String>> customRelationshipTypes = [];

  StreamSubscription? _pairSub;
  final FirebaseService _fb;
  final Function()? onChanged;

  // Mood data: uid -> MemberMood
  Map<String, MemberMood> memberMoods = {};

  // Relationship status
  RelationshipStatus? currentStatus;
  List<RelationshipStatus> customStatuses = [];

  Connection({
    required this.id,
    required FirebaseService firebaseService,
    this.isPaired = false,
    this.isSolo = false,
    this.startDate,
    this.partnerName = '',
    this.partnerAvatarUrl = '',
    List<GroupMember>? members,
    this.inviteCode = '',
    this.pairId = '',
    this.relationshipType = RelationshipType.couple,
    this.customRelationshipLabel = '',
    this.customRelationshipEmoji = '',
    this.onChanged,
  }) : _fb = firebaseService,
       members = members ?? [];

  String get inviteLink => 'https://togetherly-d4856.web.app/invite/$inviteCode';

  /// Max members allowed — always 2 (couples only)
  int get maxMembers => 2;

  /// Can invite more members?
  bool get canInviteMore {
    if (!isPaired) return true; // not yet connected, invite is needed
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
    final s = LocaleService.current;
    switch (relationshipType) {
      case RelationshipType.couple:
        return s.inLoveStatus;
      case RelationshipType.married:
        return s.married;
      case RelationshipType.friends:
        return s.friends;
      case RelationshipType.buddies:
        return s.bestBuddies;
      case RelationshipType.custom:
        return customRelationshipLabel.isNotEmpty
            ? customRelationshipLabel
            : s.customStatus;
    }
  }

  String get relationshipEmoji {
    switch (relationshipType) {
      case RelationshipType.couple:
        return '❤️';
      case RelationshipType.married:
        return '💍';
      case RelationshipType.friends:
        return '🤝';
      case RelationshipType.buddies:
        return '👯';
      case RelationshipType.custom:
        return customRelationshipEmoji.isNotEmpty
            ? customRelationshipEmoji
            : '✨';
    }
  }

  /// Get my mood
  MemberMood get myMood {
    final myUid = _fb.uid ?? '';
    final m = memberMoods[myUid];
    if (m == null || !m.isToday) return const MemberMood();
    return m;
  }

  /// Get partner's mood (first partner)
  MemberMood get partnerMood {
    final myUid = _fb.uid ?? '';
    for (final entry in memberMoods.entries) {
      if (entry.key != myUid && entry.value.isToday) return entry.value;
    }
    return const MemberMood();
  }

  /// Get mood by uid
  MemberMood moodOf(String uid) {
    final m = memberMoods[uid];
    if (m == null) return const MemberMood();
    if (!m.isToday) return const MemberMood();
    return m;
  }

  /// Set my mood
  Future<void> setMood(String imagePath, String label) async {
    if (pairId.isEmpty) return;
    final myUid = _fb.uid ?? '';
    memberMoods[myUid] = MemberMood(
      imagePath: imagePath,
      label: label,
      updatedAt: DateTime.now(),
    );
    onChanged?.call();
    await _fb.setMood(groupId: pairId, imagePath: imagePath, label: label);
  }

  /// Clear my mood
  Future<void> clearMood() async {
    if (pairId.isEmpty) return;
    final myUid = _fb.uid ?? '';
    memberMoods.remove(myUid);
    onChanged?.call();
    await _fb.clearMood(groupId: pairId);
  }

  void setRelationshipType(
    RelationshipType type, {
    String label = '',
    String emoji = '',
  }) {
    relationshipType = type;
    if (type == RelationshipType.custom) {
      customRelationshipLabel = label;
      customRelationshipEmoji = emoji;
    } else {
      customRelationshipLabel = '';
      customRelationshipEmoji = '';
    }
    // Update in Firebase
    if (pairId.isNotEmpty) {
      _fb.updateGroupRelationshipType(
        pairId,
        type: type.name,
        maxMembers: maxMembers,
        customLabel: customRelationshipLabel,
        customEmoji: customRelationshipEmoji,
      );
    }
    onChanged?.call();
  }

  /// Add a custom relationship type to the shared list
  Future<void> addCustomRelationshipType(String label, String emoji) async {
    if (pairId.isEmpty) return;
    final entry = {
      'id': 'crt_${DateTime.now().millisecondsSinceEpoch}',
      'label': label,
      'emoji': emoji,
    };
    customRelationshipTypes.add(entry);
    onChanged?.call();
    await _fb.addCustomRelationshipType(pairId, entry);
  }

  /// Update a custom relationship type
  Future<void> updateCustomRelationshipType(
    String id,
    String label,
    String emoji,
  ) async {
    if (pairId.isEmpty) return;
    final idx = customRelationshipTypes.indexWhere((e) => e['id'] == id);
    if (idx == -1) return;
    customRelationshipTypes[idx] = {'id': id, 'label': label, 'emoji': emoji};
    // If currently using this custom type, update label/emoji
    if (relationshipType == RelationshipType.custom &&
        customRelationshipLabel == label) {
      customRelationshipLabel = label;
      customRelationshipEmoji = emoji;
    }
    onChanged?.call();
    await _fb.updateCustomRelationshipType(pairId, {
      'id': id,
      'label': label,
      'emoji': emoji,
    });
  }

  /// Delete a custom relationship type
  Future<void> deleteCustomRelationshipType(String id) async {
    if (pairId.isEmpty) return;
    final entry = customRelationshipTypes.firstWhere(
      (e) => e['id'] == id,
      orElse: () => {},
    );
    customRelationshipTypes.removeWhere((e) => e['id'] == id);
    // If currently using this type, revert to couple
    if (relationshipType == RelationshipType.custom &&
        customRelationshipLabel == (entry['label'] ?? '')) {
      setRelationshipType(RelationshipType.couple);
    }
    onChanged?.call();
    await _fb.deleteCustomRelationshipType(pairId, id);
  }

  // ── Relationship Status Management ──

  /// Get all available statuses (predefined + custom)
  List<RelationshipStatus> get allStatuses {
    return [...RelationshipStatus.predefinedStatuses, ...customStatuses];
  }

  /// Set the current relationship status
  Future<void> setStatus(RelationshipStatus status) async {
    if (pairId.isEmpty) return;
    currentStatus = status;
    onChanged?.call();
    await _fb.setGroupStatus(pairId, status);
  }

  /// Clear the current relationship status
  Future<void> clearStatus() async {
    if (pairId.isEmpty) return;
    currentStatus = null;
    onChanged?.call();
    await _fb.clearGroupStatus(pairId);
  }

  /// Add a new custom status
  Future<void> addCustomStatus(String label, String emoji) async {
    if (pairId.isEmpty) return;
    final newStatus = RelationshipStatus(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      label: label,
      emoji: emoji,
      isPredefined: false,
    );
    customStatuses.add(newStatus);
    onChanged?.call();
    await _fb.addCustomStatus(pairId, newStatus);
  }

  /// Update an existing custom status
  Future<void> updateCustomStatus(
    String statusId,
    String label,
    String emoji,
  ) async {
    if (pairId.isEmpty) return;
    final index = customStatuses.indexWhere((s) => s.id == statusId);
    if (index == -1) return;

    final updatedStatus = RelationshipStatus(
      id: statusId,
      label: label,
      emoji: emoji,
      isPredefined: false,
    );
    customStatuses[index] = updatedStatus;

    // Update current status if it's the one being edited
    if (currentStatus?.id == statusId) {
      currentStatus = updatedStatus;
    }

    onChanged?.call();
    await _fb.updateCustomStatus(pairId, updatedStatus);
  }

  /// Delete a custom status
  Future<void> deleteCustomStatus(String statusId) async {
    if (pairId.isEmpty) return;
    customStatuses.removeWhere((s) => s.id == statusId);

    // Clear current status if it's the one being deleted
    if (currentStatus?.id == statusId) {
      currentStatus = null;
    }

    onChanged?.call();
    await _fb.deleteCustomStatus(pairId, statusId);
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

        final rtStr = result['relationshipType'] as String?;
        if (rtStr != null) {
          relationshipType = RelationshipType.values.firstWhere(
            (e) => e.name == rtStr,
            orElse: () => RelationshipType.couple,
          );
        }
        customRelationshipLabel =
            result['customRelationshipLabel'] as String? ?? '';
        customRelationshipEmoji =
            result['customRelationshipEmoji'] as String? ?? '';
        final crtList = result['customRelationshipTypes'] as List<dynamic>?;
        if (crtList != null) {
          customRelationshipTypes = crtList
              .map(
                (e) => Map<String, String>.from(
                  (e as Map).map(
                    (k, v) => MapEntry(k.toString(), v.toString()),
                  ),
                ),
              )
              .toList();
        }

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

  /// Marks this connection as unpaired locally (remote event: partner left).
  /// Does NOT write to Firestore — the partner already did that.
  void markUnpaired() {
    _pairSub?.cancel();
    _pairSub = null;
    isPaired = false;
    startDate = null;
    partnerName = '';
    partnerAvatarUrl = '';
    pairId = '';
    members = [];
    onChanged?.call();
  }

  Future<void> regenerateCode() async {
    final oldCode = inviteCode;
    String firestoreCode;
    if (isPaired && pairId.isNotEmpty) {
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
    if (isSolo) return; // solo-connection никогда не должен становиться парным
    if (isPaired || pairId.isNotEmpty) return;
    pairId = newPairId;
    await refreshPairStatus();

    // Regenerate invite code as a group invite code (linked to the group)
    if (_fb.isLoggedIn && pairId.isNotEmpty) {
      final oldCode = inviteCode;
      final groupCode = await _fb.generateGroupInviteCode(
        pairId,
        oldCode: oldCode.isNotEmpty ? oldCode : null,
      );
      if (groupCode.isNotEmpty) {
        inviteCode = groupCode;
        onChanged?.call();
      }
    }
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

    // Parse relationship type
    final rtStr = data['relationshipType'] as String?;
    if (rtStr != null) {
      relationshipType = RelationshipType.values.firstWhere(
        (e) => e.name == rtStr,
        orElse: () => RelationshipType.couple,
      );
    }
    customRelationshipLabel = data['customRelationshipLabel'] as String? ?? '';
    customRelationshipEmoji = data['customRelationshipEmoji'] as String? ?? '';

    // Parse custom relationship types list
    final crtList = data['customRelationshipTypes'] as List<dynamic>?;
    if (crtList != null) {
      customRelationshipTypes = crtList
          .map(
            (e) => Map<String, String>.from(
              (e as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
            ),
          )
          .toList();
    } else {
      customRelationshipTypes = [];
    }

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
    } else {
      memberMoods = {};
    }

    // Parse current status
    final statusData = data['currentStatus'] as Map<String, dynamic>?;
    if (statusData != null) {
      currentStatus = RelationshipStatus.fromJson(statusData);
    } else {
      currentStatus = null;
    }

    // Parse custom statuses
    final customStatusesList = data['customStatuses'] as List<dynamic>?;
    if (customStatusesList != null) {
      customStatuses = customStatusesList
          .map(
            (s) => RelationshipStatus.fromJson(
              Map<String, dynamic>.from(s as Map),
            ),
          )
          .toList();
    } else {
      customStatuses = [];
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
          // Group was deleted
          debugPrint('_listenToPair: group deleted');
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
          final newMembers = membersList
              .map(
                (m) => GroupMember(
                  uid: (m as Map)['uid'] ?? '',
                  name: m['name'] ?? '',
                  avatar: m['avatar'] ?? '',
                ),
              )
              .toList();

          // Check if we're still in the group
          final myUid = _fb.uid ?? '';
          final imInGroup = newMembers.any((m) => m.uid == myUid);

          if (!imInGroup) {
            // I've been removed from the group (shouldn't happen, but handle it)
            debugPrint('_listenToPair: removed from group');
            isPaired = false;
            pairId = '';
            partnerName = '';
            partnerAvatarUrl = '';
            startDate = null;
            members = [];
            onChanged?.call();
            return;
          }

          members = newMembers;

          // If all partners left (only me remaining), mark as unpaired
          final partnersCount = members.where((m) => m.uid != myUid).length;
          if (partnersCount == 0 && isPaired) {
            debugPrint('_listenToPair: all partners left, marking as unpaired');
            isPaired = false;
            partnerName = '';
            partnerAvatarUrl = '';
            startDate = null;
            pairId = '';
            members = [];
            _pairSub?.cancel();
            _pairSub = null;
          }
        }

        // Update relationship type
        final rtStr = data['relationshipType'] as String?;
        if (rtStr != null) {
          relationshipType = RelationshipType.values.firstWhere(
            (e) => e.name == rtStr,
            orElse: () => RelationshipType.couple,
          );
        }
        customRelationshipLabel =
            data['customRelationshipLabel'] as String? ??
            customRelationshipLabel;
        customRelationshipEmoji =
            data['customRelationshipEmoji'] as String? ??
            customRelationshipEmoji;

        // Update custom relationship types list
        final crtList = data['customRelationshipTypes'] as List<dynamic>?;
        if (crtList != null) {
          customRelationshipTypes = crtList
              .map(
                (e) => Map<String, String>.from(
                  (e as Map).map(
                    (k, v) => MapEntry(k.toString(), v.toString()),
                  ),
                ),
              )
              .toList();
        } else {
          customRelationshipTypes = [];
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
        } else {
          memberMoods = {};
        }

        // Update status
        final statusData = data['currentStatus'] as Map<String, dynamic>?;
        if (statusData != null) {
          currentStatus = RelationshipStatus.fromJson(statusData);
        } else {
          currentStatus = null;
        }

        // Update custom statuses
        final customStatusesList = data['customStatuses'] as List<dynamic>?;
        if (customStatusesList != null) {
          customStatuses = customStatusesList
              .map(
                (s) => RelationshipStatus.fromJson(
                  Map<String, dynamic>.from(s as Map),
                ),
              )
              .toList();
        } else {
          customStatuses = [];
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
      'isSolo': isSolo,
      'startDate': startDate?.toIso8601String(),
      'partnerName': partnerName,
      'partnerAvatarUrl': partnerAvatarUrl,
      'members': members.map((m) => m.toJson()).toList(),
      'inviteCode': inviteCode,
      'pairId': pairId,
      'relationshipType': relationshipType.name,
      'customRelationshipLabel': customRelationshipLabel,
      'customRelationshipEmoji': customRelationshipEmoji,
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
        isSolo: json['isSolo'] ?? false,
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
        customRelationshipLabel: json['customRelationshipLabel'] ?? '',
        customRelationshipEmoji: json['customRelationshipEmoji'] ?? '',
        onChanged: onChanged,
      )
      ..customRelationshipTypes =
          (json['customRelationshipTypes'] as List<dynamic>?)
              ?.map(
                (e) => Map<String, String>.from(
                  (e as Map).map(
                    (k, v) => MapEntry(k.toString(), v.toString()),
                  ),
                ),
              )
              .toList() ??
          [];
  }
}
