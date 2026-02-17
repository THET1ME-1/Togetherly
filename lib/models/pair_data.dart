import 'dart:async';
import 'package:flutter/foundation.dart';
import 'connections_manager.dart';
import 'connection.dart';

// Re-export for convenience
export 'connection.dart' show RelationshipType, GroupMember, MemberMood;

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

  // ── Multi-member getters ──
  List<GroupMember> get members => _active?.members ?? [];
  List<GroupMember> get partners => _active?.partners ?? [];
  int get partnerCount => _active?.partnerCount ?? 0;
  int get maxMembers => _active?.maxMembers ?? 2;
  bool get canInviteMore => _active?.canInviteMore ?? false;

  // ── Counter values ──
  int get daysInLove => _active?.daysInLove ?? 0;
  int get monthsInLove => _active?.monthsInLove ?? 0;
  Duration get timeInLove => _active?.timeInLove ?? Duration.zero;

  // ── Relationship Type Helpers ──
  String get relationshipLabel => _active?.relationshipLabel ?? 'In Love';
  String get relationshipEmoji => _active?.relationshipEmoji ?? '❤️';

  // ── Mood ──
  MemberMood get myMood => _active?.myMood ?? const MemberMood();
  MemberMood get partnerMood => _active?.partnerMood ?? const MemberMood();
  MemberMood moodOf(String uid) => _active?.moodOf(uid) ?? const MemberMood();

  Future<void> setMood(String emoji, String label) async {
    if (_active == null) return;
    await _active!.setMood(emoji, label);
    notifyListeners();
  }

  Future<void> clearMood() async {
    if (_active == null) return;
    await _active!.clearMood();
    notifyListeners();
  }

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

  /// Принять код партнёра — создаёт/вступает в группу через Firestore.
  /// Работает независимо от того, есть ли уже активная группа.
  Future<bool> acceptCode(String code) async {
    final result = await _manager.acceptCodeAndCreateGroup(code);
    if (result) notifyListeners();
    return result;
  }

  /// Свой ли код? Проверяет по ВСЕМ connections.
  bool isSelfCode(String code) {
    return _manager.isSelfCodeAny(code);
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

  /// Generate group invite code (for adding more members)
  Future<String> generateGroupInvite() async {
    if (_active == null) return '';
    return await _active!.generateInviteForGroup();
  }

  @override
  void dispose() {
    _manager.removeListener(_onManagerChanged);
    _manager.dispose();
    super.dispose();
  }
}
