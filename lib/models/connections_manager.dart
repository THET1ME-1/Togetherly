import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/firebase_service.dart';
import 'connection.dart';

/// Manages multiple connections/groups
class ConnectionsManager extends ChangeNotifier {
  final FirebaseService _fb = FirebaseService();
  final List<Connection> _connections = [];
  int _activeConnectionIndex = 0;
  String _preferredPartnerUid = '';
  bool _loading = false;
  StreamSubscription? _userDocSub;
  // Prevents concurrent _startListeningForNewPairs callbacks from racing
  bool _processingPairUpdate = false;

  // ── Getters ──
  List<Connection> get connections => List.unmodifiable(_connections);
  int get activeConnectionIndex => _activeConnectionIndex;
  Connection? get activeConnection {
    if (_connections.isEmpty) return null;
    if (_activeConnectionIndex >= _connections.length) return null;
    return _connections[_activeConnectionIndex];
  }

  bool get loading => _loading;
  String get preferredPartnerUid => _preferredPartnerUid;

  Future<void> setPreferredPartnerUid(String uid) async {
    _preferredPartnerUid = uid;
    await _saveLocal();
    notifyListeners();
  }

  bool get hasMultipleConnections => _connections.length > 1;

  // ── Initialization ──
  Future<void> init({required String myName}) async {
    _loading = true;
    notifyListeners();

    await _loadLocal();

    // Ensure solo connection exists at index 0 (can't be deleted)
    _ensureSoloConnection();

    // If no connections exist (besides solo), create a default one
    if (_connections.length <= 1) {
      await _createNewConnection();
    }

    // Initialize each connection
    // Collect which connections already have pairId from local storage
    final Set<String> knownPairIds = {};
    for (var connection in _connections) {
      if (connection.pairId.isNotEmpty) {
        knownPairIds.add(connection.pairId);
      }
    }

    for (var connection in _connections) {
      if (_fb.isLoggedIn) {
        if (connection.pairId.isNotEmpty) {
          // Paired connection: always refresh with a group-tied code.
          final fc = await _fb.generateGroupInviteCode(connection.pairId);
          if (fc.isNotEmpty) {
            connection.inviteCode = fc;
          } else if (connection.inviteCode.isEmpty) {
            connection.inviteCode = Connection.generateLocalCode();
          }
        } else {
          // Unpaired connection: validate the stored code is actually in
          // Firestore and owned by the current user. Local fallback codes
          // (generated when Firestore was unreachable) will fail this check
          // and trigger a fresh Firestore code.
          final codeValid = await _fb.isOwnedInviteCodeValid(
            connection.inviteCode,
          );
          if (!codeValid) {
            final oldCode = connection.inviteCode.isNotEmpty
                ? connection.inviteCode
                : null;
            final fc = await _fb.generateNewInviteCode(oldCode: oldCode);
            connection.inviteCode = fc.isNotEmpty
                ? fc
                : Connection.generateLocalCode();
          }
        }
      } else if (connection.inviteCode.isEmpty) {
        connection.inviteCode = Connection.generateLocalCode();
      }

      // Only refresh pair status for connections that already have a pairId.
      // Don't call refreshPairStatus on unpaired connections — Firebase
      // returns the SAME pairId for all, causing duplicates.
      if (_fb.isLoggedIn && connection.pairId.isNotEmpty) {
        await connection.refreshPairStatus();
      }
    }

    // If no connection claimed the Firebase pair, let the FIRST unpaired
    // non-solo connection check (only once, to pick up the initial pairing).
    // Use a flag to ensure only one connection attempts to claim the Firebase pair.
    if (_fb.isLoggedIn && knownPairIds.isEmpty) {
      bool pairClaimed = false;
      for (final conn in _connections) {
        if (conn.isSolo) continue; // solo никогда не должен клеймить пару
        if (conn.isPaired || conn.pairId.isNotEmpty) {
          pairClaimed = true;
          break;
        }
        if (!pairClaimed) {
          await conn.refreshPairStatus();
          if (conn.isPaired && conn.pairId.isNotEmpty) {
            pairClaimed = true;
            knownPairIds.add(conn.pairId);
          }
          break; // Only one connection should attempt to claim
        }
      }
    }

    // Remove stale connections: paired groups that have no partners left
    // (e.g. test groups created during debug testing, or groups where the
    // only other member has since left). This runs before the real-time
    // listener starts so the UI never shows orphaned groups.
    await _cleanupStaleConnections();

    await _saveLocal();
    _loading = false;
    notifyListeners();

    // Start listening for real-time pair changes
    _startListeningForNewPairs();
  }

  // ══════════════════════════════════════════════
  //  ACCEPT CODE — universal entry point
  // ══════════════════════════════════════════════

  /// Accept an invite code and create / join a group.
  /// Works regardless of whether the active connection is already paired.
  /// Returns true on success.
  Future<bool> acceptCodeAndCreateGroup(String code) async {
    code = code.toUpperCase().trim();
    debugPrint('acceptCodeAndCreateGroup: code=$code');

    // Check self-codes across ALL connections
    for (var c in _connections) {
      if (c.isSelfCode(code)) {
        debugPrint('acceptCodeAndCreateGroup: self code, ignoring');
        return false;
      }
    }

    // Call Firebase
    final result = await _fb.acceptInviteCode(code);
    debugPrint(
      'acceptCodeAndCreateGroup: result=${result['success']}, msg=${result['message']}',
    );
    if (result['success'] != true) return false;

    final pairId = result['pairId'] as String? ?? '';
    if (pairId.isEmpty) return false;

    // Already have this group? (real-time listener might have picked it up)
    final existingConn = _connections.cast<Connection?>().firstWhere(
      (c) => c!.pairId == pairId,
      orElse: () => null,
    );
    if (existingConn != null) {
      // Already claimed — just switch to it and consider it a success
      debugPrint(
        'acceptCodeAndCreateGroup: already have group $pairId, switching to it',
      );
      _activeConnectionIndex = _connections.indexOf(existingConn);
      await _saveLocal();
      notifyListeners();
      return true;
    }

    // Find first unpaired non-solo connection to reuse, or create new one.
    // Solo connection никогда не должен становиться парным — он существует
    // только для одиночного режима и всегда должен оставаться solo.
    Connection? target = _connections.cast<Connection?>().firstWhere(
      (c) => !c!.isSolo && !c.isPaired && c.pairId.isEmpty,
      orElse: () => null,
    );

    if (target == null) {
      target = Connection(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        firebaseService: _fb,
        onChanged: () {
          _saveLocal();
          notifyListeners();
        },
      );
      _connections.add(target);
    }

    // Delete old invite code for the connection we're reusing
    final oldInviteCode = target.inviteCode;

    // Apply data from result
    target.isPaired = true;
    target.pairId = pairId;
    target.partnerName = result['partnerName'] ?? '';
    target.partnerAvatarUrl = result['partnerAvatar'] ?? '';
    target.startDate = result['startDate'] as DateTime? ?? DateTime.now();

    final rtStr = result['relationshipType'] as String?;
    if (rtStr != null) {
      target.relationshipType = RelationshipType.values.firstWhere(
        (e) => e.name == rtStr,
        orElse: () => RelationshipType.couple,
      );
    }
    target.customRelationshipLabel =
        result['customRelationshipLabel'] as String? ?? '';
    target.customRelationshipEmoji =
        result['customRelationshipEmoji'] as String? ?? '';
    final customTypes = result['customRelationshipTypes'] as List<dynamic>?;
    if (customTypes != null) {
      target.customRelationshipTypes = customTypes
          .map(
            (e) => Map<String, String>.from(
              (e as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
            ),
          )
          .toList();
    }

    final membersList = result['members'] as List<dynamic>?;
    if (membersList != null) {
      target.members = membersList
          .map(
            (m) => GroupMember(
              uid: (m as Map)['uid']?.toString() ?? '',
              name: m['name']?.toString() ?? '',
              avatar: m['avatar']?.toString() ?? '',
            ),
          )
          .toList();
    }

    // Generate a fresh invite code linked to the group
    if (_fb.isLoggedIn) {
      final newInviteCode = await _fb.generateGroupInviteCode(
        pairId,
        oldCode: oldInviteCode.isNotEmpty ? oldInviteCode : null,
      );
      target.inviteCode = newInviteCode.isNotEmpty
          ? newInviteCode
          : Connection.generateLocalCode();
    } else {
      target.inviteCode = Connection.generateLocalCode();
    }

    // Switch to the new connection
    _activeConnectionIndex = _connections.indexOf(target);

    // Start real-time listening
    target.startListening();

    await _saveLocal();
    notifyListeners();
    debugPrint('acceptCodeAndCreateGroup: SUCCESS, paired=$pairId');
    return true;
  }

  /// Check if code is self-code for any connection
  bool isSelfCodeAny(String code) {
    for (var c in _connections) {
      if (c.isSelfCode(code)) return true;
    }
    return false;
  }

  /// Слушаем документ юзера в реальном времени.
  /// Remove connections that are paired but have no partners (orphaned groups).
  /// This handles stale groups created during debug testing sessions where the
  /// group only has the current user as a member.
  Future<void> _cleanupStaleConnections() async {
    final toRemove = <Connection>[];

    for (final conn in _connections) {
      if (conn.isSolo) continue;
      if (!conn.isPaired || conn.pairId.isEmpty) continue;
      if (conn.partners.isNotEmpty) continue;

      debugPrint(
        '_cleanupStaleConnections: removing orphaned group ${conn.pairId}',
      );
      await _fb.removeStaleGroupFromUser(conn.pairId);
      toRemove.add(conn);
    }

    for (final conn in toRemove) {
      conn.dispose();
      _connections.remove(conn);
    }

    if (toRemove.isNotEmpty) {
      // Ensure at least one non-solo connection exists
      if (_connections.where((c) => !c.isSolo).isEmpty) {
        await _createNewConnection();
      }
      // Keep active index in bounds
      if (_activeConnectionIndex >= _connections.length) {
        _activeConnectionIndex =
            _connections.length > 1 ? 1 : _connections.length - 1;
      }
    }
  }

  /// Когда партнёр принимает инвайт, pairId обновляется —
  /// мы сразу подхватываем пару без перезапуска.
  void _startListeningForNewPairs() {
    _userDocSub?.cancel();
    if (!_fb.isLoggedIn) return;

    _userDocSub = _fb.listenToUserDoc(
      onData: (data) async {
        if (data == null) return;
        // Prevent concurrent callbacks from racing (Firestore may fire twice
        // in quick succession — once from cache, once from server).
        if (_processingPairUpdate) return;
        _processingPairUpdate = true;
        try {
          await _handlePairUpdate(data);
        } finally {
          _processingPairUpdate = false;
        }
      },
    );
  }

  Future<void> _handlePairUpdate(Map<String, dynamic> data) async {
    // Собираем все pairId из user-документа
    final Set<String> remotePairIds = {};
    final pairId = data['pairId'] as String?;
    if (pairId != null && pairId.isNotEmpty) {
      remotePairIds.add(pairId);
    }
    final pairIdsRaw = data['pairIds'] as List<dynamic>?;
    if (pairIdsRaw != null) {
      for (var id in pairIdsRaw) {
        final s = id.toString();
        if (s.isNotEmpty) remotePairIds.add(s);
      }
    }

    // Ищем pairId, которые ещё не привязаны ни к одному connection
    final claimedIds = _connections
        .where((c) => c.pairId.isNotEmpty)
        .map((c) => c.pairId)
        .toSet();

    for (var remotePairId in remotePairIds) {
      if (claimedIds.contains(remotePairId)) continue;

      // Нашли новую пару — назначаем первому unpaired non-solo connection.
      // Solo connection пропускаем: он существует только для одиночного режима.
      bool wasNewlyCreated = false;
      Connection? unpaired = _connections.cast<Connection?>().firstWhere(
        (c) => !c!.isSolo && !c.isPaired && c.pairId.isEmpty,
        orElse: () => null,
      );

      if (unpaired == null) {
        unpaired = Connection(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          firebaseService: _fb,
          onChanged: () {
            _saveLocal();
            notifyListeners();
          },
        );
        _connections.add(unpaired);
        wasNewlyCreated = true;
      }

      debugPrint('Real-time: detected new pair $remotePairId');
      await unpaired.claimPair(remotePairId);

      // Validate: a claimed group must have at least one partner besides us.
      // A group with only the current user is stale (e.g. from debug testing).
      if (!unpaired.isPaired || unpaired.partners.isEmpty) {
        debugPrint(
          'Real-time: stale/invalid group $remotePairId (no partners), cleaning up',
        );
        unpaired.markUnpaired();
        if (wasNewlyCreated) {
          _connections.remove(unpaired);
        }
        await _fb.removeStaleGroupFromUser(remotePairId);
        continue;
      }

      await _saveLocal();
      notifyListeners();
    }

    // Обрабатываем удалённые pairId — партнёр мог выйти из группы
    // и groupId исчез из нашего user doc
    bool removedAny = false;
    for (var connection in _connections) {
      if (connection.pairId.isNotEmpty &&
          !remotePairIds.contains(connection.pairId) &&
          connection.isPaired) {
        debugPrint(
          'Real-time: pairId ${connection.pairId} removed from user doc, marking as unpaired',
        );
        connection.markUnpaired();
        removedAny = true;
      }
    }
    if (removedAny) {
      await _saveLocal();
      notifyListeners();
    }
  }

  /// Ensures solo connection exists at index 0 (for single user mode)
  void _ensureSoloConnection() {
    // Check if solo connection already exists
    final existingSolo = _connections.cast<Connection?>().firstWhere(
      (c) => c!.isSolo,
      orElse: () => null,
    );

    if (existingSolo != null) {
      // Лечим повреждённый соло-коннекшн: если у него есть pairId, значит
      // старый баг записал туда партнёрскую группу. Переселяем её в новый
      // нормальный коннекшн, а соло очищаем.
      if (existingSolo.pairId.isNotEmpty || existingSolo.isPaired) {
        final orphanedPairId = existingSolo.pairId;
        final alreadyExists = orphanedPairId.isNotEmpty &&
            _connections.any(
              (c) => !c.isSolo && c.pairId == orphanedPairId,
            );

        if (!alreadyExists && orphanedPairId.isNotEmpty) {
          // Создаём новый нормальный коннекшн и переносим все данные соло
          final rescued = Connection(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            firebaseService: _fb,
            isPaired: existingSolo.isPaired,
            pairId: orphanedPairId,
            startDate: existingSolo.startDate,
            partnerName: existingSolo.partnerName,
            partnerAvatarUrl: existingSolo.partnerAvatarUrl,
            members: List.of(existingSolo.members),
            inviteCode: existingSolo.inviteCode,
            relationshipType: existingSolo.relationshipType,
            onChanged: () {
              _saveLocal();
              notifyListeners();
            },
          );
          _connections.add(rescued);
          debugPrint(
            '_ensureSoloConnection: rescued orphaned pairId=$orphanedPairId into new connection',
          );
        }

        // Сбрасываем соло до чистого состояния
        existingSolo.isPaired = false;
        existingSolo.pairId = '';
        existingSolo.startDate = null;
        existingSolo.partnerName = '';
        existingSolo.partnerAvatarUrl = '';
        existingSolo.members.clear();
        existingSolo.inviteCode = '';
        debugPrint('_ensureSoloConnection: reset corrupted solo connection');
      }

      // Move solo to index 0 if not already there
      if (_connections.first != existingSolo) {
        _connections.remove(existingSolo);
        _connections.insert(0, existingSolo);
      }
      return;
    }

    // Create new solo connection
    final soloConnection = Connection(
      id: 'solo',
      firebaseService: _fb,
      isSolo: true,
      onChanged: () {
        _saveLocal();
        notifyListeners();
      },
    );

    _connections.insert(0, soloConnection);

    // Adjust active index if needed (if we had active non-solo, keep it offset by 1)
    if (_activeConnectionIndex > 0) {
      _activeConnectionIndex++;
    } else if (_activeConnectionIndex == 0 && _connections.length > 1) {
      // Default to first real connection, not solo
      _activeConnectionIndex = 1;
    }
  }

  // ── Connection Management ──
  Future<Connection> _createNewConnection() async {
    final newConnection = Connection(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      firebaseService: _fb,
      onChanged: () {
        _saveLocal();
        notifyListeners();
      },
    );

    _connections.add(newConnection);
    await _saveLocal();
    notifyListeners();
    return newConnection;
  }

  Future<Connection> addNewConnection({
    RelationshipType type = RelationshipType.friends,
    String customLabel = '',
    String customEmoji = '',
  }) async {
    final connection = await _createNewConnection();
    connection.relationshipType = type;
    if (type == RelationshipType.custom) {
      connection.customRelationshipLabel = customLabel;
      connection.customRelationshipEmoji = customEmoji;
    }

    // Always generate a fresh unique invite code for the new connection
    if (_fb.isLoggedIn) {
      final firestoreCode = await _fb.generateNewInviteCode();
      connection.inviteCode = firestoreCode.isNotEmpty
          ? firestoreCode
          : Connection.generateLocalCode();
    } else {
      connection.inviteCode = Connection.generateLocalCode();
    }

    // Auto-switch to the new connection
    _activeConnectionIndex = _connections.length - 1;

    await _saveLocal();
    notifyListeners();
    return connection;
  }

  Future<void> removeConnection(String connectionId) async {
    final index = _connections.indexWhere((c) => c.id == connectionId);
    if (index == -1) return;

    // Can't remove solo connection
    if (_connections[index].isSolo) return;

    // Can't remove the last connection
    if (_connections.length == 1) return;

    final connection = _connections[index];

    // Unpair if paired
    if (connection.isPaired) {
      await connection.unpair();
    }

    connection.dispose();
    _connections.removeAt(index);

    // Adjust active index if needed
    if (_activeConnectionIndex >= _connections.length) {
      _activeConnectionIndex = _connections.length - 1;
    }

    await _saveLocal();
    notifyListeners();
  }

  Future<void> switchToConnection(int index) async {
    if (index < 0 || index >= _connections.length) return;
    _activeConnectionIndex = index;

    // Generate invite code if the connection doesn't have one
    final connection = _connections[index];
    if (connection.inviteCode.isEmpty) {
      if (_fb.isLoggedIn) {
        final firestoreCode = connection.pairId.isNotEmpty
            ? await _fb.generateGroupInviteCode(connection.pairId)
            : await _fb.generateNewInviteCode();
        connection.inviteCode = firestoreCode.isNotEmpty
            ? firestoreCode
            : Connection.generateLocalCode();
      } else {
        connection.inviteCode = Connection.generateLocalCode();
      }
    }

    await _saveLocal();
    notifyListeners();
  }

  Future<void> switchToNextConnection() async {
    if (_connections.length <= 1) return;
    _activeConnectionIndex = (_activeConnectionIndex + 1) % _connections.length;

    // Generate invite code if the connection doesn't have one
    final connection = _connections[_activeConnectionIndex];
    if (connection.inviteCode.isEmpty) {
      if (_fb.isLoggedIn) {
        final firestoreCode = connection.pairId.isNotEmpty
            ? await _fb.generateGroupInviteCode(connection.pairId)
            : await _fb.generateNewInviteCode();
        connection.inviteCode = firestoreCode.isNotEmpty
            ? firestoreCode
            : Connection.generateLocalCode();
      } else {
        connection.inviteCode = Connection.generateLocalCode();
      }
    }

    await _saveLocal();
    notifyListeners();
  }

  /// Switch to solo mode (single user, no group)
  Future<void> switchToSolo() async {
    // Find solo connection index
    final soloIndex = _connections.indexWhere((c) => c.isSolo);
    if (soloIndex == -1) return;
    
    _activeConnectionIndex = soloIndex;
    await _saveLocal();
    notifyListeners();
    debugPrint('ConnectionsManager: switched to solo mode');
  }

  /// Check if currently in solo mode
  bool get isSoloMode {
    if (_connections.isEmpty) return false;
    if (_activeConnectionIndex >= _connections.length) return false;
    return _connections[_activeConnectionIndex].isSolo;
  }

  // ── Persistence ──
  Future<void> _saveLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final connectionsJson = _connections.map((c) => c.toJson()).toList();
      await prefs.setString('connections', jsonEncode(connectionsJson));
      await prefs.setInt('activeConnectionIndex', _activeConnectionIndex);
      await prefs.setString('preferredPartnerUid', _preferredPartnerUid);
    } catch (e) {
      debugPrint('Failed to save connections: $e');
    }
  }

  Future<void> _loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if stored uid matches current Firebase Auth uid
      final storedUid = prefs.getString('uid') ?? '';
      final currentUid = _fb.uid ?? '';

      // If uids don't match, clear all connection data
      if (storedUid.isNotEmpty &&
          currentUid.isNotEmpty &&
          storedUid != currentUid) {
        debugPrint(
          'UID mismatch: stored=$storedUid, current=$currentUid. Clearing connections.',
        );
        await clearAllData();
        return;
      }

      final connectionsStr = prefs.getString('connections');
      if (connectionsStr != null) {
        final List<dynamic> connectionsJson = jsonDecode(connectionsStr);
        _connections.clear();
        for (var json in connectionsJson) {
          final connection = Connection.fromJson(json, _fb, () {
            _saveLocal();
            notifyListeners();
          });
          _connections.add(connection);
        }
      }

      _activeConnectionIndex = prefs.getInt('activeConnectionIndex') ?? 0;
      _preferredPartnerUid = prefs.getString('preferredPartnerUid') ?? '';

      // Ensure valid index
      if (_activeConnectionIndex >= _connections.length) {
        _activeConnectionIndex = 0;
      }
    } catch (e) {
      debugPrint('Failed to load connections: $e');
    }
  }

  /// Clear all connection data from SharedPreferences
  Future<void> clearAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('connections');
      await prefs.remove('activeConnectionIndex');
      await prefs.remove('preferredPartnerUid');
      _connections.clear();
      _activeConnectionIndex = 0;
      _preferredPartnerUid = '';
      notifyListeners();
      debugPrint('Cleared all connection data');
    } catch (e) {
      debugPrint('Failed to clear connection data: $e');
    }
  }

  @override
  void dispose() {
    _userDocSub?.cancel();
    for (var connection in _connections) {
      connection.dispose();
    }
    super.dispose();
  }
}
