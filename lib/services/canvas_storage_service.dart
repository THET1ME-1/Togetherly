import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/canvas_meta.dart';
import 'firebase_service.dart';

/// Persists a per-user list of [CanvasMeta] entries in SharedPreferences
/// **and** syncs the catalogue to Firebase when the user belongs to a group.
///
/// The actual drawing strokes live in Firebase (paired) or in-memory (solo).
class CanvasStorageService {
  CanvasStorageService._();
  static final CanvasStorageService instance = CanvasStorageService._();

  final FirebaseService _fb = FirebaseService();

  /// Active Firebase listener — cancelled in [stopListening].
  StreamSubscription? _catalogueSub;

  /// Callback notified whenever the remote catalogue changes.
  VoidCallback? onRemoteChange;

  // ── helpers ────────────────────────────────────────────────────────────────

  String _key(String uid) => 'canvases_v1_$uid';

  // ── public API ─────────────────────────────────────────────────────────────

  /// Returns all canvases for [uid], newest first.
  /// Seeds a default "main" canvas on first call.
  Future<List<CanvasMeta>> getCanvases(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(uid));
      if (raw == null) return _seedDefault(uid);
      final decoded = jsonDecode(raw) as List<dynamic>;
      final list = decoded
          .map((e) => CanvasMeta.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (list.isEmpty) return _seedDefault(uid);
      return list;
    } catch (_) {
      return _seedDefault(uid);
    }
  }

  /// Creates a new canvas entry (prepended to the list) and returns it.
  /// When [groupId] is non-empty the canvas meta is also pushed to Firebase.
  Future<CanvasMeta> createCanvas(
    String uid, {
    String? name,
    String groupId = '',
  }) async {
    final canvases = await getCanvases(uid);
    final id = 'canvas_${DateTime.now().millisecondsSinceEpoch}';
    final meta = CanvasMeta(
      id: id,
      name: name ?? 'Canvas ${canvases.length + 1}',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _save(uid, [meta, ...canvases]);

    // Push to Firebase so partner sees the new canvas
    if (groupId.isNotEmpty) {
      _fb.upsertCanvasMeta(
        groupId: groupId,
        canvasId: id,
        name: meta.name,
        createdAt: meta.createdAt.millisecondsSinceEpoch,
        updatedAt: meta.updatedAt.millisecondsSinceEpoch,
        createdBy: uid,
      );
    }

    return meta;
  }

  /// Replaces the matching entry (by id) with [updated].
  Future<void> updateCanvas(
    String uid,
    CanvasMeta updated, {
    String groupId = '',
  }) async {
    final canvases = await getCanvases(uid);
    final next = canvases.map((c) => c.id == updated.id ? updated : c).toList();
    await _save(uid, next);

    if (groupId.isNotEmpty) {
      _fb.upsertCanvasMeta(
        groupId: groupId,
        canvasId: updated.id,
        name: updated.name,
        createdAt: updated.createdAt.millisecondsSinceEpoch,
        updatedAt: updated.updatedAt.millisecondsSinceEpoch,
      );
    }
  }

  /// Rename a canvas (local + Firebase).
  Future<void> renameCanvas(
    String uid,
    String canvasId,
    String newName, {
    String groupId = '',
  }) async {
    final canvases = await getCanvases(uid);
    final idx = canvases.indexWhere((c) => c.id == canvasId);
    if (idx < 0) return;
    canvases[idx] = canvases[idx].copyWith(
      name: newName,
      updatedAt: DateTime.now(),
    );
    await _save(uid, canvases);

    if (groupId.isNotEmpty) {
      _fb.renameCanvasMeta(
        groupId: groupId,
        canvasId: canvasId,
        newName: newName,
      );
    }
  }

  /// Stores a PNG thumbnail [bytes] for the canvas identified by [canvasId]
  /// and bumps its [updatedAt] timestamp.
  Future<void> updatePreview(
    String uid,
    String canvasId,
    Uint8List bytes,
  ) async {
    final canvases = await getCanvases(uid);
    final idx = canvases.indexWhere((c) => c.id == canvasId);
    if (idx < 0) return;
    canvases[idx] = canvases[idx].copyWith(
      previewBase64: base64Encode(bytes),
      updatedAt: DateTime.now(),
    );
    await _save(uid, canvases);
  }

  /// Removes the canvas with [canvasId] from the list.
  Future<void> deleteCanvas(
    String uid,
    String canvasId, {
    String groupId = '',
  }) async {
    final canvases = await getCanvases(uid);
    await _save(uid, canvases.where((c) => c.id != canvasId).toList());

    if (groupId.isNotEmpty) {
      _fb.deleteCanvasMeta(groupId: groupId, canvasId: canvasId);
    }
  }

  // ── Firebase real-time sync ───────────────────────────────────────────────

  /// Start listening to the remote canvas catalogue.
  /// Merges remote entries into the local list, adds missing ones.
  void startListening({required String uid, required String groupId}) {
    _catalogueSub?.cancel();
    if (groupId.isEmpty) return;

    _catalogueSub = _fb.listenToCanvasCatalogue(groupId: groupId).listen((
      remoteList,
    ) async {
      await _mergeRemoteCanvases(uid, remoteList);
      onRemoteChange?.call();
    });
  }

  /// Stop the remote listener (e.g. when the gallery screen is disposed).
  void stopListening() {
    _catalogueSub?.cancel();
    _catalogueSub = null;
  }

  /// Merge remote canvas entries into local storage.
  Future<void> _mergeRemoteCanvases(
    String uid,
    List<Map<String, dynamic>> remoteList,
  ) async {
    final local = await getCanvases(uid);
    final localById = {for (final c in local) c.id: c};

    bool changed = false;
    for (final remote in remoteList) {
      final id = remote['id'] as String;
      final name = (remote['name'] as String?) ?? 'Canvas';
      final createdAt = DateTime.fromMillisecondsSinceEpoch(
        (remote['createdAt'] as num?)?.toInt() ?? 0,
      );
      final updatedAt = DateTime.fromMillisecondsSinceEpoch(
        (remote['updatedAt'] as num?)?.toInt() ?? 0,
      );

      if (!localById.containsKey(id)) {
        // New canvas from partner — add it locally
        localById[id] = CanvasMeta(
          id: id,
          name: name,
          createdAt: createdAt,
          updatedAt: updatedAt,
        );
        changed = true;
      } else {
        // Update name if remote is newer
        final existing = localById[id]!;
        if (updatedAt.isAfter(existing.updatedAt) && name != existing.name) {
          localById[id] = existing.copyWith(name: name, updatedAt: updatedAt);
          changed = true;
        }
      }
    }

    // Remove local canvases that were deleted remotely
    final remoteIds = remoteList.map((r) => r['id'] as String).toSet();
    // Keep canvases not yet in remote (freshly created locally, or 'main' default)
    // Only remove if the remote set is non-empty (i.e. we have an established catalogue)
    if (remoteList.isNotEmpty) {
      final toRemove = localById.keys
          .where((id) => !remoteIds.contains(id) && id != 'main')
          .toList();
      for (final id in toRemove) {
        localById.remove(id);
        changed = true;
      }
    }

    if (changed) {
      final merged = localById.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      await _save(uid, merged);
    }
  }

  /// Push all existing local canvases to Firebase (one-time bootstrap).
  /// Called when a user first pairs or opens the gallery while paired.
  Future<void> pushAllToFirebase(String uid, String groupId) async {
    if (groupId.isEmpty) return;
    final canvases = await getCanvases(uid);
    for (final meta in canvases) {
      await _fb.upsertCanvasMeta(
        groupId: groupId,
        canvasId: meta.id,
        name: meta.name,
        createdAt: meta.createdAt.millisecondsSinceEpoch,
        updatedAt: meta.updatedAt.millisecondsSinceEpoch,
        createdBy: uid,
      );
    }
  }

  // ── private ────────────────────────────────────────────────────────────────

  Future<List<CanvasMeta>> _seedDefault(String uid) async {
    final meta = CanvasMeta(
      id: 'main',
      name: 'Canvas 1',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _save(uid, [meta]);
    return [meta];
  }

  Future<void> _save(String uid, List<CanvasMeta> canvases) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(uid),
      jsonEncode(canvases.map((c) => c.toJson()).toList()),
    );
  }
}
