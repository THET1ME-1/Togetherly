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
    for (var connection in _connections) {
      if (connection.inviteCode.isEmpty) {
        if (_fb.isLoggedIn) {
          final firestoreCode = await _fb.generateInviteCode();
          connection.inviteCode = firestoreCode.isNotEmpty
              ? firestoreCode
              : Connection.generateLocalCode();
        } else {
          connection.inviteCode = Connection.generateLocalCode();
        }
      }

      if (_fb.isLoggedIn) {
        await connection.refreshPairStatus();
      }
    }

    await _saveLocal();
    _loading = false;
    notifyListeners();
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

  void switchToConnection(int index) {
    if (index < 0 || index >= _connections.length) return;
    _activeConnectionIndex = index;
    _saveLocal();
    notifyListeners();
  }

  void switchToNextConnection() {
    if (_connections.length <= 1) return;
    _activeConnectionIndex = (_activeConnectionIndex + 1) % _connections.length;
    _saveLocal();
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
    for (var connection in _connections) {
      connection.dispose();
    }
    super.dispose();
  }
}
