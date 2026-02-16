import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../services/firebase_service.dart';

enum RelationshipType {
  couple, // In Love
  friends, // Friends
  buddies, // Best Buddies
}

/// Represents a single connection/group with one partner
class Connection {
  final String id;
  bool isPaired;
  DateTime? startDate;
  String partnerName;
  String partnerAvatarUrl;
  String inviteCode;
  String pairId;
  RelationshipType relationshipType;

  StreamSubscription? _pairSub;
  final FirebaseService _fb;
  final Function()? onChanged;

  Connection({
    required this.id,
    required FirebaseService firebaseService,
    this.isPaired = false,
    this.startDate,
    this.partnerName = '',
    this.partnerAvatarUrl = '',
    this.inviteCode = '',
    this.pairId = '',
    this.relationshipType = RelationshipType.couple,
    this.onChanged,
  }) : _fb = firebaseService;

  String get inviteLink => 'https://togetherly.app/invite/$inviteCode';

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

  void setRelationshipType(RelationshipType type) {
    relationshipType = type;
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
        // Apply pair data directly from the result — don't use
        // refreshPairStatus which would load the global pairId and
        // could leak into other connections.
        isPaired = true;
        pairId = result['pairId'] ?? '';
        partnerName = result['partnerName'] ?? '';
        partnerAvatarUrl = result['partnerAvatar'] ?? '';
        startDate = result['startDate'] as DateTime? ?? DateTime.now();
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

    // Generate new code
    final oldCode = inviteCode;
    final firestoreCode = await _fb.generateNewInviteCode(oldCode: oldCode);
    inviteCode = firestoreCode.isNotEmpty
        ? firestoreCode
        : Connection.generateLocalCode();

    onChanged?.call();
  }

  Future<void> regenerateCode() async {
    final oldCode = inviteCode;
    final firestoreCode = await _fb.generateNewInviteCode(oldCode: oldCode);
    inviteCode = firestoreCode.isNotEmpty
        ? firestoreCode
        : Connection.generateLocalCode();
    onChanged?.call();
  }

  /// Вызывается когда real-time listener обнаружил новый pairId.
  /// Присваивает pairId и загружает данные пары.
  Future<void> claimPair(String newPairId) async {
    if (isPaired || pairId.isNotEmpty) return;
    pairId = newPairId;
    // refreshPairStatus handles the case: pairId set, isPaired false
    await refreshPairStatus();
  }

  Future<void> refreshPairStatus() async {
    // Already paired with a known pair? Just re-subscribe.
    if (isPaired && pairId.isNotEmpty) {
      _listenToPair();
      return;
    }

    // Has pairId saved locally but not yet marked paired — load directly.
    if (pairId.isNotEmpty) {
      try {
        final pairData = await _fb.loadPairById(pairId);
        if (pairData != null) {
          isPaired = true;
          startDate = pairData['startDate'] as DateTime?;
          partnerName = pairData['partnerName'] ?? '';
          partnerAvatarUrl = pairData['partnerAvatar'] ?? '';
          _listenToPair();
        }
      } catch (e) {
        debugPrint('Pair refresh by id failed: $e');
      }
      onChanged?.call();
      return;
    }

    // No pairId at all — check Firebase for first-time discovery.
    // This is ONLY called on the first unpaired connection.
    try {
      final pairData = await _fb.loadPairData();
      if (pairData != null) {
        isPaired = true;
        pairId = pairData['pairId'] ?? '';
        startDate = pairData['startDate'] as DateTime?;
        partnerName = pairData['partnerName'] ?? '';
        partnerAvatarUrl = pairData['partnerAvatar'] ?? '';
        _listenToPair();
      }
    } catch (e) {
      debugPrint('Pair refresh failed: $e');
    }
    onChanged?.call();
  }

  void _listenToPair() {
    _pairSub?.cancel();
    if (pairId.isEmpty) return;

    _pairSub = _fb.listenToPair(
      pairId: pairId,
      onData: (data) {
        if (data == null) {
          // Pair deleted
          isPaired = false;
          pairId = '';
          partnerName = '';
          partnerAvatarUrl = '';
          startDate = null;
          onChanged?.call();
          return;
        }

        partnerName = data['partnerName'] ?? partnerName;
        partnerAvatarUrl = data['partnerAvatar'] ?? partnerAvatarUrl;
        startDate = data['startDate'] as DateTime? ?? startDate;
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
    // Use microsecondsSinceEpoch as seed to ensure unique codes even when generated rapidly
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
    return Connection(
      id: json['id'] ?? '',
      firebaseService: firebaseService,
      isPaired: json['isPaired'] ?? false,
      startDate: json['startDate'] != null
          ? DateTime.tryParse(json['startDate'])
          : null,
      partnerName: json['partnerName'] ?? '',
      partnerAvatarUrl: json['partnerAvatarUrl'] ?? '',
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
