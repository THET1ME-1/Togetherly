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
  bool _isLoading = false;

  List<Mascot> get mascots => _mascots;
  GroupMascotState get state => _state;
  bool get isLoading => _isLoading;

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
    _isLoading = true;
    notifyListeners();

    _mascotsSub = _fb
        .listenToMascots(groupId: groupId)
        .listen(
          _onMascotsUpdate,
          onError: (e) => debugPrint('[MascotService] mascots error: $e'),
        );
  }

  void unbind() {
    _mascotsSub?.cancel();
    _groupId = '';
    _mascots = [];
    _state = const GroupMascotState();
    _isLoading = false;
    notifyListeners();
  }

  // Called from the pair listener in Connection._listenToPair via MascotService.applyGroupData
  void applyGroupData(Map<String, dynamic> data) {
    _state = GroupMascotState.fromMap(data);
    notifyListeners();
  }

  // IDs of the old SVG system mascots that need to be replaced.
  static const _kOldDefaultIds = {
    'default_boy_happy',
    'default_boy_sad',
    'default_boy_very_sad',
    'default_girl_happy',
    'default_girl_sad',
    'default_girl_very_sad',
  };

  void _onMascotsUpdate(List<Mascot> mascots) {
    _mascots = mascots;

    // Seed defaults if gallery is empty (first time).
    if (_mascots.isEmpty && _groupId.isNotEmpty) {
      _seedDefaults();
      return;
    }

    // One-time migration: replace the old 6 SVG defaults with the new 2.
    final oldOnes = _mascots
        .where((m) => _kOldDefaultIds.contains(m.id))
        .toList();
    if (oldOnes.isNotEmpty) {
      _migrateOldDefaults(oldOnes);
      return; // wait for Firestore stream to re-fire after writes
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _migrateOldDefaults(List<Mascot> oldOnes) async {
    debugPrint('[MascotService] Migrating ${oldOnes.length} old defaults…');
    // Clear active if it was an old default.
    if (_kOldDefaultIds.contains(_state.activeMascotId)) {
      await setActive(null);
    }
    // Delete every old default from Firestore.
    for (final m in oldOnes) {
      await _fb.deleteMascot(
        groupId: _groupId,
        mascotId: m.id,
        imageUrl: null, // old defaults had no Storage image
      );
    }
    // Write new defaults — stream will re-fire and gallery updates.
    await _fb.saveMascotsBatch(
      groupId: _groupId,
      mascots: DefaultMascots.asMascots(),
    );
  }

  Future<void> _seedDefaults() async {
    final defaults = DefaultMascots.asMascots();
    // saveMascotsBatch catches its own errors internally and never throws,
    // so we cannot rely on try/catch here. After the call, if Firestore
    // wrote successfully the stream will fire again with the seeded data.
    // If it failed silently the stream won't update - so we show defaults
    // locally right now to prevent infinite loading.
    await _fb.saveMascotsBatch(groupId: _groupId, mascots: defaults);
    if (_mascots.isEmpty) {
      _mascots = List.from(defaults);
      _isLoading = false;
      notifyListeners();
    }
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
    await _fb.updateMascotPosition(groupId: _groupId, x: x, y: y, scale: scale);
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
    // Optimistically add to local list so the gallery updates immediately
    // without waiting for the Firestore stream to echo back.
    if (!_mascots.any((m) => m.id == mascot.id)) {
      _mascots = [..._mascots, mascot];
      notifyListeners();
    }
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
    final updated = mascot.copyWith(imageUrl: url);
    await _fb.saveMascot(groupId: _groupId, mascot: updated);
    // Optimistically update local list.
    final idx = _mascots.indexWhere((m) => m.id == mascot.id);
    if (idx != -1) {
      final list = List<Mascot>.from(_mascots);
      list[idx] = updated;
      _mascots = list;
      notifyListeners();
    }
  }

  // ── Mood state helper for display ─────────────────────────────────────────

  /// Returns the asset path for [mascot], or null for user-drawn (URL-based) ones.
  String? resolvedAssetForMood(Mascot mascot) => mascot.defaultAsset;

  @override
  void dispose() {
    _mascotsSub?.cancel();
    super.dispose();
  }
}
