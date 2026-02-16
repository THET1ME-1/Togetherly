import 'dart:async';
import 'package:flutter/foundation.dart';
import 'connections_manager.dart';
import 'connection.dart';

// Re-export for convenience
export 'connection.dart' show RelationshipType;

/// Wrapper around ConnectionsManager for backward compatibility
/// Delegates to the active connection
class PairData extends ChangeNotifier {
  final ConnectionsManager _manager = ConnectionsManager();

  ConnectionsManager get manager => _manager;

  Connection? get _active => _manager.activeConnection;

  // ── Getters ──
  bool get isPaired => _active?.isPaired ?? false;
  DateTime? get startDate => _active?.startDate;
  String get myName => 'You';
  String get partnerName => _active?.partnerName ?? '';
  String get partnerAvatarUrl => _active?.partnerAvatarUrl ?? '';
  String get inviteCode => _active?.inviteCode ?? '';

  String get pairId => _active?.pairId ?? '';
  bool get loading => _manager.loading;
  RelationshipType get relationshipType =>
      _active?.relationshipType ?? RelationshipType.couple;

  String get inviteLink => 'https://togetherly.app/invite/$inviteCode';

  // ── Counter values ──
  int get daysInLove => _active?.daysInLove ?? 0;
  int get monthsInLove => _active?.monthsInLove ?? 0;
  Duration get timeInLove => _active?.timeInLove ?? Duration.zero;

  // ── Relationship Type Helpers ──
  String get relationshipLabel => _active?.relationshipLabel ?? 'In Love';
  String get relationshipEmoji => _active?.relationshipEmoji ?? '❤️';

  void setRelationshipType(RelationshipType type) {
    _active?.setRelationshipType(type);
    notifyListeners();
  }

  // ── Инициализация ──
  Future<void> init({required String myName}) async {
    _manager.addListener(_onManagerChanged);
    await _manager.init(myName: myName);
    notifyListeners();
  }

  void _onManagerChanged() {
    notifyListeners();
  }

  // ── Actions ──
  void setMyName(String name) {
    // Not used anymore, kept for compatibility
    notifyListeners();
  }

  /// Принять код партнёра — реальная связка через Firestore
  Future<bool> acceptCode(String code) async {
    if (_active == null) return false;
    final result = await _active!.acceptCode(code);
    if (result) notifyListeners();
    return result;
  }

  /// Свой ли код?
  bool isSelfCode(String code) {
    return _active?.isSelfCode(code) ?? false;
  }

  /// Разорвать пару
  Future<void> unpair() async {
    if (_active == null) return;
    await _active!.unpair();
    notifyListeners();
  }

  /// Перегенерация кода
  Future<void> regenerateCode() async {
    if (_active == null) return;
    await _active!.regenerateCode();
    notifyListeners();
  }

  @override
  void dispose() {
    _manager.removeListener(_onManagerChanged);
    _manager.dispose();
    super.dispose();
  }
}
