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

/// Самочувствие участника («болячки») — что у него болит/нездоровится.
/// В отличие от настроения (которое сбрасывается ежедневно) статус держится,
/// пока его не снимут вручную, но партнёру показывается только пока он
/// «свежий» ([_freshness]) — чтобы забытый статус не висел вечно.
class MemberAilment {
  final String id;
  final String label;
  final String emoji;
  final DateTime? updatedAt;

  const MemberAilment({
    this.id = '',
    this.label = '',
    this.emoji = '',
    this.updatedAt,
  });

  static const Duration _freshness = Duration(days: 7);

  bool get isFresh {
    if (updatedAt == null) return false;
    return DateTime.now().difference(updatedAt!) < _freshness;
  }

  bool get isEmpty => id.isEmpty || !isFresh;
  bool get isNotEmpty => id.isNotEmpty && isFresh;

  factory MemberAilment.fromJson(Map<String, dynamic> json) {
    final ts = json['updatedAt'];
    return MemberAilment(
      id: json['id'] ?? '',
      label: json['label'] ?? '',
      emoji: json['emoji'] ?? '',
      updatedAt: ts is DateTime ? ts : null,
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

  /// Группа была распущена партнёром (этот клиент НЕ инициировал удаление).
  /// Менеджер при следующем onChanged уберёт такую связь из локального списка,
  /// чтобы группа исчезла у ОБОИХ, а не висела пустой карточкой у партнёра.
  bool justDisbanded = false;

  // Mood data: uid -> MemberMood
  Map<String, MemberMood> memberMoods = {};

  // Ailment ("болячки") data: uid -> MemberAilment
  Map<String, MemberAilment> memberAilments = {};

  // Relationship status
  RelationshipStatus? currentStatus;
  List<RelationshipStatus> customStatuses = [];

  // Celebrations
  DateTime? anniversaryDate;
  DateTime? firstKissDate;
  Map<String, DateTime> memberBirthdays = {};

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

  /// Моё самочувствие (актуальное).
  MemberAilment get myAilment {
    final a = memberAilments[_fb.uid ?? ''];
    if (a == null || !a.isFresh) return const MemberAilment();
    return a;
  }

  /// Самочувствие конкретного участника.
  MemberAilment ailmentOf(String uid) {
    final a = memberAilments[uid];
    if (a == null || !a.isFresh) return const MemberAilment();
    return a;
  }

  /// Самочувствие первого партнёра, у которого статус актуален.
  MemberAilment get partnerAilment {
    final myUid = _fb.uid ?? '';
    for (final entry in memberAilments.entries) {
      if (entry.key != myUid && entry.value.isFresh) return entry.value;
    }
    return const MemberAilment();
  }

  /// Поставить своё самочувствие.
  Future<void> setAilment(String id, String label, String emoji) async {
    if (pairId.isEmpty) return;
    final myUid = _fb.uid ?? '';
    memberAilments[myUid] = MemberAilment(
      id: id,
      label: label,
      emoji: emoji,
      updatedAt: DateTime.now(),
    );
    onChanged?.call();
    await _fb.setAilment(groupId: pairId, id: id, label: label, emoji: emoji);
  }

  /// Снять своё самочувствие («Здоров(а)»).
  Future<void> clearAilment() async {
    if (pairId.isEmpty) return;
    final myUid = _fb.uid ?? '';
    memberAilments.remove(myUid);
    onChanged?.call();
    await _fb.clearAilment(groupId: pairId);
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
    if (firestoreCode.isNotEmpty) {
      inviteCode = firestoreCode;
    } else {
      inviteCode = '';
      _retryCodeInBackground();
    }

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
      firestoreCode = await _fb.generateGroupInviteCode(
        pairId,
        oldCode: oldCode,
      );
    } else {
      firestoreCode = await _fb.generateNewInviteCode(oldCode: oldCode);
    }
    if (firestoreCode.isNotEmpty) {
      inviteCode = firestoreCode;
    } else {
      inviteCode = '';
      _retryCodeInBackground();
    }
    onChanged?.call();
  }

  /// Запускает фоновую попытку получить Firestore-код после сбоя генерации.
  void _retryCodeInBackground() {
    const delays = [2, 5, 10, 20, 40, 60, 120];
    Future(() async {
      for (final delaySec in delays) {
        await Future.delayed(Duration(seconds: delaySec));
        if (isPaired && pairId.isNotEmpty) return;
        if (!_fb.isLoggedIn) continue;

        // Если код уже появился (предыдущая попытка дошла до сервера), выходим
        if (inviteCode.isNotEmpty) {
          final serverCheck = await _fb.isInviteCodeOnServer(inviteCode);
          if (serverCheck == true) return;
          if (serverCheck == null) continue;
        }

        final newCode = isPaired && pairId.isNotEmpty
            ? await _fb.generateGroupInviteCode(pairId)
            : await _fb.generateNewInviteCode();
        if (newCode.isNotEmpty) {
          inviteCode = newCode;
          onChanged?.call();
          debugPrint('_retryCodeInBackground: replaced local code');
          return;
        }
      }
    });
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
    if (pairId.isNotEmpty) {
      // Always fetch fresh from Firestore on app start — covers the case where
      // SharedPreferences holds stale `members` from a previous version (the
      // root cause of the "Group of 3" phantom bug). Skipping this when
      // isPaired+pairId would let the corrupt local cache survive until the
      // listener snapshot fires.
      try {
        final pairData = await _fb.loadPairById(pairId);
        if (pairData != null) {
          _applyPairData(pairData);
        }
      } catch (e) {
        debugPrint('Pair refresh by id failed: $e');
      }
      _listenToPair();
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

    // Parse ailments
    final ailmentsMap = data['memberAilments'] as Map<String, dynamic>?;
    if (ailmentsMap != null) {
      memberAilments = ailmentsMap.map(
        (uid, value) => MapEntry(
          uid,
          MemberAilment.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      );
    } else {
      memberAilments = {};
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
          // Group was deleted or disbanded
          debugPrint('_listenToPair: group deleted');
          final staleId = pairId;
          isPaired = false;
          pairId = '';
          partnerName = '';
          partnerAvatarUrl = '';
          startDate = null;
          members = [];
          // Партнёр распустил группу — помечаем связь на удаление из локального
          // списка (менеджер уберёт её в onChanged), чтобы группа исчезла у
          // обоих, а не осталась пустой карточкой.
          justDisbanded = true;
          onChanged?.call();
          if (staleId.isNotEmpty) _fb.removeStaleGroupFromUser(staleId);
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
            final staleId = pairId;
            isPaired = false;
            pairId = '';
            partnerName = '';
            partnerAvatarUrl = '';
            startDate = null;
            members = [];
            onChanged?.call();
            if (staleId.isNotEmpty) _fb.removeStaleGroupFromUser(staleId);
            return;
          }

          members = newMembers;

          // Diagnostic: log when the group is over capacity. Indicates the
          // "phantom member" bug — same person occupying multiple uid slots.
          // ConnectionsManager._cleanupStaleConnections runs a one-shot
          // auto-cleanup on app start; if it ever logs here again the bug has
          // a new reproduction path we haven't covered.
          if (newMembers.length > maxMembers) {
            final dump = newMembers
                .map((m) => '${m.uid}=${m.name}')
                .join(', ');
            debugPrint(
              '_listenToPair($pairId): OVERSIZED group — '
              '${newMembers.length} members, maxMembers=$maxMembers, myUid=$myUid, '
              'partners=${newMembers.where((m) => m.uid != myUid).length}. '
              'Members: [$dump]',
            );
            // Fire-and-forget cleanup; safe to call repeatedly.
            // force: переполнение группы — это и есть видимый баг, лечим сразу,
            // не дожидаясь снятия 24ч-троттла.
            unawaited(_fb.cleanupPhantomMembersInGroup(pairId, force: true));
          }

          // If all partners left (only me remaining), mark as unpaired
          final partnersCount = members.where((m) => m.uid != myUid).length;
          if (partnersCount == 0 && isPaired) {
            debugPrint('_listenToPair: all partners left, marking as unpaired');
            final staleId = pairId;
            isPaired = false;
            partnerName = '';
            partnerAvatarUrl = '';
            startDate = null;
            pairId = '';
            members = [];
            _pairSub?.cancel();
            _pairSub = null;
            if (staleId.isNotEmpty) _fb.removeStaleGroupFromUser(staleId);
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

        // Update ailments
        final ailmentsMap = data['memberAilments'] as Map<String, dynamic>?;
        if (ailmentsMap != null) {
          memberAilments = ailmentsMap.map(
            (uid, value) => MapEntry(
              uid,
              MemberAilment.fromJson(Map<String, dynamic>.from(value as Map)),
            ),
          );
        } else {
          memberAilments = {};
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

        // Update celebration dates (_parseGroupDoc already converts Timestamp→DateTime)
        anniversaryDate = data['anniversaryDate'] as DateTime?;
        firstKissDate = data['firstKissDate'] as DateTime?;
        final bdRaw = data['memberBirthdays'] as Map<String, dynamic>?;
        if (bdRaw != null) {
          memberBirthdays = {};
          for (final entry in bdRaw.entries) {
            if (entry.value is DateTime) {
              memberBirthdays[entry.key] = entry.value as DateTime;
            }
          }
        } else {
          memberBirthdays = {};
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
    // Sanity guard against the "Group of 3" bug. Old builds could persist a
    // members list that contains: an entry with an empty uid, duplicates of
    // the same uid, or more entries than a couple should have. Restoring such
    // a list as-is lets the bug survive across uninstalls (via Android Auto
    // Backup) and across restarts. Drop empties + dedupe by uid; if the
    // cleaned list still overflows maxMembers (=2), zero it out so the
    // Firestore listener repopulates from authoritative data.
    final rawMembers = (json['members'] as List<dynamic>?)
        ?.map((m) => GroupMember.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    final List<GroupMember> membersList;
    if (rawMembers == null) {
      membersList = [];
    } else {
      final seen = <String>{};
      final cleaned = <GroupMember>[];
      for (final m in rawMembers) {
        if (m.uid.isEmpty) continue;
        if (!seen.add(m.uid)) continue;
        cleaned.add(m);
      }
      const localMaxMembers = 2;
      if (cleaned.length > localMaxMembers) {
        debugPrint(
          'Connection.fromJson(${json['id']}): members overflow '
          '(${cleaned.length} > $localMaxMembers) — clearing local cache, '
          'will refetch from Firestore. Cached uids: '
          '${cleaned.map((m) => m.uid).toList()}',
        );
        membersList = [];
      } else if (cleaned.length != rawMembers.length) {
        debugPrint(
          'Connection.fromJson(${json['id']}): pruned '
          '${rawMembers.length - cleaned.length} bad member entry(ies) '
          '(empties/duplicates)',
        );
        membersList = cleaned;
      } else {
        membersList = cleaned;
      }
    }

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
        members: membersList,
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
