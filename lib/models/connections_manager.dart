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
  bool _loading = false;
  StreamSubscription? _userDocSub;

  // ── Getters ──
  List<Connection> get connections => List.unmodifiable(_connections);
  int get activeConnectionIndex => _activeConnectionIndex;
  Connection? get activeConnection {
    if (_connections.isEmpty) return null;
    if (_activeConnectionIndex >= _connections.length) return null;
    return _connections[_activeConnectionIndex];
  }

  bool get loading => _loading;
  bool get hasMultipleConnections => _connections.length > 1;

  // ── Initialization ──
  Future<void> init({required String myName}) async {
    _loading = true;
    notifyListeners();

    await _loadLocal();

    // If no connections exist, create a default one
    if (_connections.isEmpty) {
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
      if (connection.inviteCode.isEmpty) {
        if (_fb.isLoggedIn) {
          final firestoreCode = await _fb.generateNewInviteCode();
          connection.inviteCode = firestoreCode.isNotEmpty
              ? firestoreCode
              : Connection.generateLocalCode();
        } else {
          connection.inviteCode = Connection.generateLocalCode();
        }
      }

      // Only refresh pair status for connections that already have a pairId.
      // Don't call refreshPairStatus on unpaired connections — Firebase
      // returns the SAME pairId for all, causing duplicates.
      if (_fb.isLoggedIn && connection.pairId.isNotEmpty) {
        await connection.refreshPairStatus();
      }
    }

    // If no connection claimed the Firebase pair, let the FIRST unpaired
    // connection check (only once, to pick up the initial pairing).
    if (_fb.isLoggedIn && knownPairIds.isEmpty) {
      final firstUnpaired = _connections.firstWhere(
        (c) => !c.isPaired,
        orElse: () => _connections.first,
      );
      await firstUnpaired.refreshPairStatus();
    }

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

    // Check self-codes across ALL connections
    for (var c in _connections) {
      if (c.isSelfCode(code)) return false;
    }

    // Call Firebase
    final result = await _fb.acceptInviteCode(code);
    if (result['success'] != true) return false;

    final pairId = result['pairId'] as String? ?? '';
    if (pairId.isEmpty) return false;

    // Already have this group?
    if (_connections.any((c) => c.pairId == pairId)) return false;

    // Find first unpaired connection to reuse, or create new one
    Connection? target = _connections.cast<Connection?>().firstWhere(
      (c) => !c!.isPaired && c.pairId.isEmpty,
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

    // Apply data from result
    target.isPaired = true;
    target.pairId = pairId;
    target.partnerName = result['partnerName'] ?? '';
    target.partnerAvatarUrl = result['partnerAvatar'] ?? '';
    target.startDate = result['startDate'] as DateTime? ?? DateTime.now();

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

    // Generate a fresh invite code for the new connection
    if (_fb.isLoggedIn) {
      final newInviteCode = await _fb.generateNewInviteCode();
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
  /// Когда партнёр принимает инвайт, pairId обновляется —
  /// мы сразу подхватываем пару без перезапуска.
  void _startListeningForNewPairs() {
    _userDocSub?.cancel();
    if (!_fb.isLoggedIn) return;

    _userDocSub = _fb.listenToUserDoc(
      onData: (data) async {
        if (data == null) return;

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

          // Нашли новую пару — назначаем первому unpaired connection
          // Если unpaired нет — создаём новый connection
          Connection? unpaired = _connections.cast<Connection?>().firstWhere(
            (c) => !c!.isPaired && c.pairId.isEmpty,
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
          }

          debugPrint('Real-time: detected new pair $remotePairId');
          await unpaired.claimPair(remotePairId);
          await _saveLocal();
          notifyListeners();
        }
      },
    );
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
  }) async {
    final connection = await _createNewConnection();
    connection.relationshipType = type;

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
        final firestoreCode = await _fb.generateNewInviteCode();
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
        final firestoreCode = await _fb.generateNewInviteCode();
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

  // ── Persistence ──
  Future<void> _saveLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final connectionsJson = _connections.map((c) => c.toJson()).toList();
      await prefs.setString('connections', jsonEncode(connectionsJson));
      await prefs.setInt('activeConnectionIndex', _activeConnectionIndex);
    } catch (e) {
      debugPrint('Failed to save connections: $e');
    }
  }

  Future<void> _loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();

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

      // Ensure valid index
      if (_activeConnectionIndex >= _connections.length) {
        _activeConnectionIndex = 0;
      }
    } catch (e) {
      debugPrint('Failed to load connections: $e');
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
