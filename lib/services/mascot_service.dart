import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/mascot.dart';
import 'firebase_service.dart';
import 'home_widget_service.dart';

/// Manages the mascot gallery and group streak for one group.
/// Bind to a group via [bindToGroup] when the user is paired.
class MascotService extends ChangeNotifier {
  final FirebaseService _fb = FirebaseService();

  String _groupId = '';
  int _bindGeneration = 0;
  StreamSubscription? _mascotsSub;
  StreamSubscription? _groupStateSub;

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
    _bindGeneration++;
    _groupId = groupId;
    _mascotsSub?.cancel();
    _groupStateSub?.cancel();
    _mascots = [];
    _state = const GroupMascotState();
    _isLoading = true;
    notifyListeners();

    _groupStateSub = _fb.listenToGroupMascotState(groupId: groupId).listen((
      state,
    ) {
      _state = state;
      _syncStreakWidget();
      notifyListeners();
    }, onError: (e) => debugPrint('[MascotService] group state error: $e'));

    _mascotsSub = _fb
        .listenToMascots(groupId: groupId)
        .listen(
          _onMascotsUpdate,
          onError: (e) => debugPrint('[MascotService] mascots error: $e'),
        );
  }

  void unbind() {
    _bindGeneration++;
    _mascotsSub?.cancel();
    _groupStateSub?.cancel();
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
    // Record streak (stored per active mascot) may have just loaded — refresh
    // the home-screen «Огонёк» widget so its «Рекорд: N» подпись is correct.
    _syncStreakWidget();
    notifyListeners();
  }

  /// Pushes the current group streak to the native «Огонёк пары» home widget.
  void _syncStreakWidget() {
    final record = activeMascot?.recordStreak ?? 0;
    HomeWidgetService.instance.syncStreak(
      streakDays: _state.streakDays,
      recordStreak: record > _state.streakDays ? record : _state.streakDays,
      lastOpenedDate: _state.streakLastOpenedDate ?? '',
    );
  }

  Future<void> _migrateOldDefaults(List<Mascot> oldOnes) async {
    final boundGroupId = _groupId;
    final bindGeneration = _bindGeneration;
    debugPrint('[MascotService] Migrating ${oldOnes.length} old defaults…');
    // Clear active if it was an old default.
    if (_kOldDefaultIds.contains(_state.activeMascotId)) {
      await setActive(null);
    }
    // Delete every old default from Firestore.
    for (final m in oldOnes) {
      if (_groupId != boundGroupId || bindGeneration != _bindGeneration) return;
      await _fb.deleteMascot(
        groupId: boundGroupId,
        mascotId: m.id,
        imageUrl: null, // old defaults had no Storage image
      );
    }
    // Write new defaults — stream will re-fire and gallery updates.
    final newDefaults = DefaultMascots.asMascots();
    if (_groupId != boundGroupId || bindGeneration != _bindGeneration) return;
    await _fb.saveMascotsBatch(groupId: boundGroupId, mascots: newDefaults);
    // Auto-activate the first new default so the mascot stays visible.
    if (newDefaults.isNotEmpty) {
      if (_groupId != boundGroupId || bindGeneration != _bindGeneration) return;
      await setActive(newDefaults.first.id);
    }
  }

  Future<void> _seedDefaults() async {
    final boundGroupId = _groupId;
    final bindGeneration = _bindGeneration;
    final defaults = DefaultMascots.asMascots();
    await _fb.saveMascotsBatch(groupId: boundGroupId, mascots: defaults);
    // Auto-activate the first default mascot so it is visible immediately.
    if (defaults.isNotEmpty) {
      if (_groupId != boundGroupId || bindGeneration != _bindGeneration) return;
      await setActive(defaults.first.id);
    }
    if (_groupId == boundGroupId &&
        bindGeneration == _bindGeneration &&
        _mascots.isEmpty) {
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
    final boundGroupId = _groupId;
    final bindGeneration = _bindGeneration;

    final url = await _fb.uploadMascotImage(
      groupId: boundGroupId,
      pngBytes: pngBytes,
    );
    if (url == null ||
        _groupId != boundGroupId ||
        bindGeneration != _bindGeneration) {
      return null;
    }

    final mascot = Mascot(
      id: 'mascot_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      imageUrl: url,
      createdBy: creatorUid,
      createdAt: DateTime.now(),
      isDefault: false,
    );
    await _fb.saveMascot(groupId: boundGroupId, mascot: mascot);
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
    final boundGroupId = _groupId;
    final bindGeneration = _bindGeneration;
    final url = await _fb.uploadMascotImage(
      groupId: boundGroupId,
      pngBytes: pngBytes,
    );
    if (url == null ||
        _groupId != boundGroupId ||
        bindGeneration != _bindGeneration) {
      return;
    }
    // Delete old image from Storage.
    if (mascot.imageUrl != null) {
      try {
        await _fb.deleteFileByUrl(mascot.imageUrl!);
      } catch (_) {}
    }
    final updated = mascot.copyWith(imageUrl: url);
    await _fb.saveMascot(groupId: boundGroupId, mascot: updated);
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
    _groupStateSub?.cancel();
    super.dispose();
  }
}
