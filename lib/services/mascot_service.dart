import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/mascot.dart';
import 'firebase_service.dart';

/// Manages the mascot gallery and group streak for one group.
/// Bind to a group via [bindToGroup] when the user is paired.
class MascotService extends ChangeNotifier {
  final FirebaseService _fb = FirebaseService();

  String _groupId = '';
  StreamSubscription? _mascotsSub;

  List<Mascot> _mascots = [];
  GroupMascotState _state = const GroupMascotState();

  List<Mascot> get mascots => _mascots;
  GroupMascotState get state => _state;

  bool get hasActiveMascot => _state.activeMascotId != null;
  int get mascotCount => _mascots.length;
  static const int maxMascots = 20;
  bool get isGalleryFull => mascotCount >= maxMascots;

  Mascot? get activeMascot {
    final id = _state.activeMascotId;
    if (id == null) return null;
    try {
      return _mascots.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  // ── Bind / unbind ──────────────────────────────────────────────────────────

  void bindToGroup(String groupId) {
    if (_groupId == groupId) return;
    _groupId = groupId;
    _mascotsSub?.cancel();
    _mascots = [];
    _state = const GroupMascotState();
    notifyListeners();

    _mascotsSub = _fb.listenToMascots(groupId: groupId).listen(
      _onMascotsUpdate,
      onError: (e) => debugPrint('[MascotService] mascots error: $e'),
    );
  }

  void unbind() {
    _mascotsSub?.cancel();
    _groupId = '';
    _mascots = [];
    _state = const GroupMascotState();
    notifyListeners();
  }

  // Called from the pair listener in Connection._listenToPair via MascotService.applyGroupData
  void applyGroupData(Map<String, dynamic> data) {
    _state = GroupMascotState.fromMap(data);
    notifyListeners();
  }

  void _onMascotsUpdate(List<Mascot> mascots) {
    _mascots = mascots;

    // Seed defaults if gallery is empty (first time).
    if (_mascots.isEmpty && _groupId.isNotEmpty) {
      _seedDefaults();
      return;
    }

    notifyListeners();
  }

  Future<void> _seedDefaults() async {
    final defaults = DefaultMascots.asMascots();
    await _fb.saveMascotsBatch(groupId: _groupId, mascots: defaults);
    // Stream will update _mascots automatically.
  }

  // ── Streak ─────────────────────────────────────────────────────────────────

  Future<void> recordDailyActivity() async {
    if (_groupId.isEmpty) return;
    await _fb.recordGroupActivity(_groupId);
  }

  // ── Active mascot ──────────────────────────────────────────────────────────

  Future<void> setActive(String? mascotId) async {
    if (_groupId.isEmpty) return;
    _state = _state.copyWith(
      activeMascotId: mascotId,
      clearActiveMascot: mascotId == null,
    );
    notifyListeners();
    await _fb.setActiveMascot(groupId: _groupId, mascotId: mascotId);
  }

  Future<void> updatePosition({
    required double x,
    required double y,
    required double scale,
  }) async {
    if (_groupId.isEmpty) return;
    _state = _state.copyWith(positionX: x, positionY: y, scale: scale);
    notifyListeners();
    await _fb.updateMascotPosition(
      groupId: _groupId,
      x: x,
      y: y,
      scale: scale,
    );
  }

  // ── CRUD ───────────────────────────────────────────────────────────────────

  Future<void> addMascot(Mascot mascot) async {
    if (_groupId.isEmpty) return;
    await _fb.saveMascot(groupId: _groupId, mascot: mascot);
  }

  Future<void> deleteMascot(Mascot mascot) async {
    if (_groupId.isEmpty) return;
    // If it was active, clear it.
    if (_state.activeMascotId == mascot.id) {
      await setActive(null);
    }
    await _fb.deleteMascot(
      groupId: _groupId,
      mascotId: mascot.id,
      imageUrl: mascot.imageUrl,
    );
  }

  Future<void> renameMascot(Mascot mascot, String newName) async {
    if (_groupId.isEmpty) return;
    mascot.name = newName;
    notifyListeners();
    await _fb.renameMascot(
      groupId: _groupId,
      mascotId: mascot.id,
      newName: newName,
    );
  }

  /// Upload PNG bytes → Storage, create Mascot, save to Firestore.
  Future<Mascot?> uploadAndSaveMascot({
    required List<int> pngBytes,
    required String name,
    required String creatorUid,
  }) async {
    if (_groupId.isEmpty) return null;

    final url = await _fb.uploadMascotImage(
      groupId: _groupId,
      pngBytes: pngBytes,
    );
    if (url == null) return null;

    final mascot = Mascot(
      id: 'mascot_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      imageUrl: url,
      createdBy: creatorUid,
      createdAt: DateTime.now(),
      isDefault: false,
    );
    await _fb.saveMascot(groupId: _groupId, mascot: mascot);
    return mascot;
  }

  /// Update the image of an existing mascot (re-draw flow).
  Future<void> updateMascotImage({
    required Mascot mascot,
    required List<int> pngBytes,
  }) async {
    if (_groupId.isEmpty) return;
    final url = await _fb.uploadMascotImage(
      groupId: _groupId,
      pngBytes: pngBytes,
    );
    if (url == null) return;
    // Delete old image from Storage.
    if (mascot.imageUrl != null) {
      try {
        await _fb.deleteFileByUrl(mascot.imageUrl!);
      } catch (_) {}
    }
    await _fb.saveMascot(
      groupId: _groupId,
      mascot: mascot.copyWith(imageUrl: url),
    );
  }

  // ── Mood state helper for display ─────────────────────────────────────────

  /// Returns the correct asset path for a default mascot considering group mood.
  /// Returns null if [mascot] is not a default or has no variants.
  String? resolvedAssetForMood(Mascot mascot) {
    if (!mascot.isDefault) return mascot.defaultAsset;
    final mood = _state.moodState;
    // Map base mascot to correct mood variant.
    final id = mascot.id;
    if (id.startsWith('default_boy')) {
      return switch (mood) {
        MascotMoodState.happy => 'assets/mascots/boy_happy.svg',
        MascotMoodState.sad => 'assets/mascots/boy_sad.svg',
        MascotMoodState.verySad => 'assets/mascots/boy_very_sad.svg',
      };
    }
    if (id.startsWith('default_girl')) {
      return switch (mood) {
        MascotMoodState.happy => 'assets/mascots/girl_happy.svg',
        MascotMoodState.sad => 'assets/mascots/girl_sad.svg',
        MascotMoodState.verySad => 'assets/mascots/girl_very_sad.svg',
      };
    }
    return mascot.defaultAsset;
  }

  @override
  void dispose() {
    _mascotsSub?.cancel();
    super.dispose();
  }
}
