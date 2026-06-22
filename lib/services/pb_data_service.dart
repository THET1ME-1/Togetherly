import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';

import 'pocketbase_service.dart';

/// Слой данных PocketBase (миграция Firebase→PB, Этап 6, слой Данные).
///
/// Заменяет Firestore-CRUD. Плоские коллекции, поля snake_case (схема Этапа 3).
/// Никакого Firebase: даты — ISO-строки/`DateTime`, не `Timestamp`. Входные карты
/// от приложения — camelCase (как в существующем коде), здесь маппятся в колонки.
///
/// Realtime-подписки (`watch*`) — отдельный слой (PB SSE), медиа — отдельный.
class PbDataService {
  PbDataService._();
  static final PbDataService instance = PbDataService._();
  factory PbDataService() => instance;

  PocketBase get _pb => PocketBaseService().pb;

  // ── helpers ────────────────────────────────────────────────────────────
  /// firestore-данные → JSON-safe для json-полей PB: DateTime→ISO, рекурсивно.
  static dynamic _jsonSafe(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toIso8601String();
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), _jsonSafe(val)));
    }
    if (v is List) return v.map(_jsonSafe).toList();
    return v;
  }

  /// DateTime/String → ISO-строка для date-колонок, или null.
  static String? _iso(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toIso8601String();
    if (v is String) return v.isEmpty ? null : v;
    return null;
  }

  /// ISO-строка PB → DateTime, или null.
  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  /// Upsert по известному id: update → при 404 create с этим id.
  Future<bool> _upsertById(
    String col,
    String id,
    Map<String, dynamic> body, {
    String op = 'upsert',
  }) async {
    body.remove('id');
    try {
      await _pb.collection(col).update(id, body: body);
      return true;
    } on ClientException catch (e) {
      if (e.statusCode == 404) {
        try {
          await _pb.collection(col).create(body: {'id': id, ...body});
          return true;
        } catch (e2) {
          debugPrint('PbData.$op create($col/$id) failed: $e2');
          return false;
        }
      }
      debugPrint('PbData.$op update($col/$id) failed: $e');
      return false;
    } catch (e) {
      debugPrint('PbData.$op($col/$id) failed: $e');
      return false;
    }
  }

  /// Upsert по составному уникальному ключу (auto-id коллекции): найти по
  /// фильтру → update, иначе create.
  Future<bool> _upsertByFilter(
    String col,
    String filter,
    Map<String, dynamic> params,
    Map<String, dynamic> body, {
    String op = 'upsert',
  }) async {
    try {
      final f = _pb.filter(filter, params);
      try {
        final existing = await _pb.collection(col).getFirstListItem(f);
        await _pb.collection(col).update(existing.id, body: body);
      } on ClientException catch (e) {
        if (e.statusCode == 404) {
          await _pb.collection(col).create(body: body);
        } else {
          rethrow;
        }
      }
      return true;
    } catch (e) {
      debugPrint('PbData.$op($col) failed: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════ GROUP
  /// Зеркало группы из «сырого» firestore-документа (camelCase). Upsert по id.
  Future<bool> upsertGroupRaw(String groupId, Map<String, dynamic> raw) async {
    if (groupId.isEmpty) return false;
    final body = <String, dynamic>{
      'members': _jsonSafe(raw['members'] ?? []),
      'member_names': _jsonSafe(raw['memberNames'] ?? {}),
      'member_avatars': _jsonSafe(raw['memberAvatars'] ?? {}),
      'max_members': raw['maxMembers'] ?? 2,
      'relationship_type': raw['relationshipType'] ?? 'couple',
      'custom_relationship_label': raw['customRelationshipLabel'],
      'custom_relationship_emoji': raw['customRelationshipEmoji'],
      'custom_relationship_types':
          _jsonSafe(raw['customRelationshipTypes'] ?? []),
      'start_date': _iso(raw['startDate']),
      'anniversary_date': _iso(raw['anniversaryDate']),
      'first_kiss_date': _iso(raw['firstKissDate']),
      'member_birthdays': _jsonSafe(raw['memberBirthdays'] ?? {}),
      'member_moods': _jsonSafe(raw['memberMoods'] ?? {}),
      'current_status': _jsonSafe(raw['currentStatus']),
      'custom_statuses': _jsonSafe(raw['customStatuses'] ?? []),
      'memories_count': raw['memoriesCount'] ?? 0,
      'drawings_count': raw['drawingsCount'] ?? 0,
      'active_session': _jsonSafe(raw['activeSession']),
      'disbanded': raw['disbanded'] ?? false,
      'disbanded_at': _iso(raw['disbandedAt']),
      'timers': _jsonSafe(raw['timers'] ?? []),
      'mascots': _jsonSafe(raw['mascots'] ?? []),
    }..removeWhere((k, v) => v == null);
    return _upsertById('groups', groupId, body, op: 'upsertGroupRaw');
  }

  /// Точечное обновление колонок группы (snake_case→значение). update-only
  /// (нет вставки): годится и для очистки полей в null.
  Future<bool> updateGroupFields(
    String groupId,
    Map<String, dynamic> columns,
  ) async {
    if (groupId.isEmpty || columns.isEmpty) return false;
    try {
      final rec = await _pb
          .collection('groups')
          .getFirstListItem(_pb.filter('id = {:id}', {'id': groupId}));
      await _pb.collection('groups').update(rec.id, body: columns);
      return true;
    } catch (e) {
      debugPrint('PbData.updateGroupFields($groupId) failed: $e');
      return false;
    }
  }

  Future<bool> setMemberMood(String groupId, String uid, dynamic mood) =>
      _patchGroupMapField(groupId, 'member_moods', uid, _jsonSafe(mood));
  Future<bool> clearMemberMood(String groupId, String uid) =>
      _patchGroupMapField(groupId, 'member_moods', uid, null);
  Future<bool> setMemberName(String groupId, String uid, String name) =>
      _patchGroupMapField(groupId, 'member_names', uid, name);
  Future<bool> setMemberAvatar(String groupId, String uid, String url) =>
      _patchGroupMapField(groupId, 'member_avatars', uid, url);

  /// RMW по json-полю-словарю группы (member_moods/names/avatars): прочитать,
  /// поменять ключ uid, записать целиком. null-значение удаляет ключ.
  Future<bool> _patchGroupMapField(
    String groupId,
    String col,
    String uid,
    dynamic value,
  ) async {
    try {
      final rec = await _pb
          .collection('groups')
          .getFirstListItem(_pb.filter('id = {:id}', {'id': groupId}));
      final cur = rec.data[col];
      final map = cur is Map ? Map<String, dynamic>.from(cur) : <String, dynamic>{};
      if (value == null) {
        map.remove(uid);
      } else {
        map[uid] = value;
      }
      await _pb.collection('groups').update(rec.id, body: {col: map});
      return true;
    } catch (e) {
      debugPrint('PbData._patchGroupMapField($col,$uid) failed: $e');
      return false;
    }
  }

  /// Группа по id (raw данные записи, даты — DateTime). null если нет/распущена.
  Future<RecordModel?> loadGroupById(String groupId) async {
    if (groupId.isEmpty) return null;
    try {
      final rec = await _pb
          .collection('groups')
          .getFirstListItem(_pb.filter('id = {:id}', {'id': groupId}));
      if (rec.data['disbanded'] == true) return null;
      return rec;
    } catch (e) {
      if (e is ClientException && e.statusCode == 404) return null;
      debugPrint('PbData.loadGroupById($groupId) failed: $e');
      return null;
    }
  }

  /// Группа, где currentUid в members и не распущена.
  Future<RecordModel?> loadPairForUser(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final res = await _pb.collection('groups').getList(
            perPage: 1,
            filter: _pb.filter('members ~ {:u} && disbanded = false', {'u': uid}),
          );
      return res.items.isEmpty ? null : res.items.first;
    } catch (e) {
      debugPrint('PbData.loadPairForUser($uid) failed: $e');
      return null;
    }
  }

  Future<bool> incrementGroupCounter(String groupId, String col, int by) async {
    try {
      final rec = await _pb
          .collection('groups')
          .getFirstListItem(_pb.filter('id = {:id}', {'id': groupId}));
      final cur = (rec.data[col] as num?)?.toInt() ?? 0;
      await _pb.collection('groups').update(rec.id, body: {col: cur + by});
      return true;
    } catch (e) {
      debugPrint('PbData.incrementGroupCounter($col) failed: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════ MEMORIES
  Future<bool> upsertMemory(
    String groupId,
    String id,
    Map<String, dynamic> data,
  ) async {
    if (id.isEmpty) return false;
    return _upsertById('memories', id, {
      'group_id': groupId,
      'type': data['type'],
      'author_uid': data['authorUid'],
      'author_name': data['authorName'],
      'author_avatar': data['authorAvatar'],
      'created_at': _iso(data['createdAt']),
      'edited_at': _iso(data['editedAt']),
      'is_pinned': data['isPinned'] ?? false,
      'deleted': data['deleted'] ?? false,
      'data': _jsonSafe(data),
    }, op: 'upsertMemory');
  }

  Future<bool> patchMemory(String id, Map<String, dynamic> fb) async {
    if (id.isEmpty) return false;
    final cols = <String, dynamic>{};
    if (fb.containsKey('isPinned')) cols['is_pinned'] = fb['isPinned'];
    if (fb.containsKey('editedAt')) cols['edited_at'] = _iso(fb['editedAt']);
    if (fb.containsKey('createdAt')) cols['created_at'] = _iso(fb['createdAt']);
    if (cols.isEmpty) return true;
    return _upsertById('memories', id, cols, op: 'patchMemory');
  }

  Future<bool> deleteMemory(String id, {bool hard = false}) async {
    if (id.isEmpty) return false;
    try {
      if (hard) {
        final rec = await _pb
            .collection('memories')
            .getFirstListItem(_pb.filter('id = {:id}', {'id': id}));
        await _pb.collection('memories').delete(rec.id);
      } else {
        await _upsertById('memories', id, {'deleted': true}, op: 'deleteMemory');
      }
      return true;
    } catch (e) {
      debugPrint('PbData.deleteMemory($id) failed: $e');
      return false;
    }
  }

  /// Лента группы (новые сверху), soft-deleted отфильтрованы. [beforeIso] —
  /// курсор по created_at для пагинации. Возвращает raw-записи.
  Future<List<RecordModel>> loadMemories(
    String groupId, {
    int limit = 50,
    String? beforeIso,
  }) async {
    if (groupId.isEmpty) return const [];
    try {
      var filter = 'group_id = {:g} && deleted = false';
      final params = <String, dynamic>{'g': groupId};
      if (beforeIso != null) {
        filter += ' && created_at < {:b}';
        params['b'] = beforeIso;
      }
      final res = await _pb.collection('memories').getList(
            perPage: limit,
            filter: _pb.filter(filter, params),
            sort: '-created_at',
          );
      return res.items;
    } catch (e) {
      debugPrint('PbData.loadMemories($groupId) failed: $e');
      return const [];
    }
  }

  // ══════════════════════════════════════════════ MOODS
  Future<bool> upsertMood(
    String groupId,
    String uid,
    Map<String, dynamic> entry,
  ) async {
    final id = entry['id'] as String?;
    if (id == null || id.isEmpty) return false;
    return _upsertById('mood_entries', id, {
      'group_id': groupId,
      'user_uid': uid,
      'mood_id': entry['moodId'],
      'image_path': entry['imagePath'],
      'label': entry['label'],
      'timestamp': _iso(entry['timestamp']) ?? DateTime.now().toIso8601String(),
    }, op: 'upsertMood');
  }

  Future<bool> deleteMood(String entryId) async {
    if (entryId.isEmpty) return false;
    try {
      final rec = await _pb
          .collection('mood_entries')
          .getFirstListItem(_pb.filter('id = {:id}', {'id': entryId}));
      await _pb.collection('mood_entries').delete(rec.id);
      return true;
    } catch (e) {
      debugPrint('PbData.deleteMood($entryId) failed: $e');
      return false;
    }
  }

  Future<List<RecordModel>> loadMoods(String groupId, String uid) async {
    if (groupId.isEmpty) return const [];
    try {
      final res = await _pb.collection('mood_entries').getFullList(
            filter: _pb.filter('group_id = {:g} && user_uid = {:u}',
                {'g': groupId, 'u': uid}),
          );
      return res;
    } catch (e) {
      debugPrint('PbData.loadMoods($groupId) failed: $e');
      return const [];
    }
  }

  // ══════════════════════════════════════════════ COMMENTS
  Future<bool> upsertComment(
    String groupId,
    String memoryId,
    String id,
    Map<String, dynamic> data,
  ) async {
    if (id.isEmpty) return false;
    return _upsertById('memory_comments', id, {
      'group_id': groupId,
      'memory_id': memoryId,
      'author_uid': data['authorUid'],
      'author_name': data['authorName'],
      'author_avatar': data['authorAvatar'],
      'text': data['text'],
      'created_at': _iso(data['createdAt']) ?? DateTime.now().toIso8601String(),
    }, op: 'upsertComment');
  }

  Future<bool> deleteComment(String id) async {
    if (id.isEmpty) return false;
    try {
      final rec = await _pb
          .collection('memory_comments')
          .getFirstListItem(_pb.filter('id = {:id}', {'id': id}));
      await _pb.collection('memory_comments').delete(rec.id);
      return true;
    } catch (e) {
      debugPrint('PbData.deleteComment($id) failed: $e');
      return false;
    }
  }

  Future<List<RecordModel>> loadComments(String memoryId) async {
    if (memoryId.isEmpty) return const [];
    try {
      return await _pb.collection('memory_comments').getFullList(
            filter: _pb.filter('memory_id = {:m}', {'m': memoryId}),
            sort: 'created_at',
          );
    } catch (e) {
      debugPrint('PbData.loadComments($memoryId) failed: $e');
      return const [];
    }
  }

  // ══════════════════════════════════════════════ WIDGET DATA (составной ключ)
  Future<bool> upsertWidget(
    String groupId,
    String uid,
    Map<String, dynamic> d,
  ) async {
    if (groupId.isEmpty || uid.isEmpty) return false;
    final body = <String, dynamic>{
      'group_id': groupId,
      'user_uid': uid,
      'display_name': d['displayName'],
      'avatar_url': d['avatarUrl'],
      'gender': d['gender'],
      'status': d['status'],
      'mood_emoji': d['moodEmoji'],
      'mood_label': d['moodLabel'],
      'message': d['message'],
      'music_title': d['musicTitle'],
      'music_artist': d['musicArtist'],
      'music_url': d['musicUrl'],
      'music_cover_url': d['musicCoverUrl'],
      'photo_url': d['photoUrl'],
      'photo_for_partner_url': d['photoForPartnerUrl'],
      'photo_for_partner_urls': _jsonSafe(d['photoForPartnerUrls'] ?? []),
      'photo_grid_count': d['photoGridCount'] ?? 1,
      'photo_grid_urls': _jsonSafe(d['photoGridUrls'] ?? []),
      'data': _jsonSafe(d['data'] ?? {}),
      'updated_at': DateTime.now().toIso8601String(),
    }..removeWhere((k, v) => v == null);
    return _upsertByFilter(
      'widget_data',
      'group_id = {:g} && user_uid = {:u}',
      {'g': groupId, 'u': uid},
      body,
      op: 'upsertWidget',
    );
  }

  Future<RecordModel?> loadWidget(String groupId, String uid) async {
    if (groupId.isEmpty || uid.isEmpty) return null;
    try {
      return await _pb.collection('widget_data').getFirstListItem(
            _pb.filter('group_id = {:g} && user_uid = {:u}',
                {'g': groupId, 'u': uid}),
          );
    } catch (e) {
      if (e is ClientException && e.statusCode == 404) return null;
      debugPrint('PbData.loadWidget failed: $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════ CANVAS
  Future<bool> upsertStroke(
    String groupId,
    String canvasId,
    String id,
    Map<String, dynamic> data,
  ) async {
    if (id.isEmpty) return false;
    return _upsertById('canvas_strokes', id, {
      'group_id': groupId,
      'canvas_id': canvasId,
      'order_index': (data['orderIndex'] as num?)?.toInt() ?? 0,
      'data': _jsonSafe(data),
    }, op: 'upsertStroke');
  }

  Future<bool> patchStroke(String id, Map<String, dynamic> updates) async {
    if (id.isEmpty) return false;
    // RMW: PB не умеет json-merge на сервере → читаем, мёржим data, пишем.
    try {
      final rec = await _pb
          .collection('canvas_strokes')
          .getFirstListItem(_pb.filter('id = {:id}', {'id': id}));
      final cur = rec.data['data'];
      final merged = cur is Map
          ? (Map<String, dynamic>.from(cur)..addAll(_jsonSafe(updates) as Map<String, dynamic>))
          : _jsonSafe(updates);
      await _pb.collection('canvas_strokes').update(rec.id, body: {'data': merged});
      return true;
    } catch (e) {
      debugPrint('PbData.patchStroke($id) failed: $e');
      return false;
    }
  }

  Future<bool> deleteStroke(String id) async {
    if (id.isEmpty) return false;
    try {
      final rec = await _pb
          .collection('canvas_strokes')
          .getFirstListItem(_pb.filter('id = {:id}', {'id': id}));
      await _pb.collection('canvas_strokes').delete(rec.id);
      return true;
    } catch (e) {
      debugPrint('PbData.deleteStroke($id) failed: $e');
      return false;
    }
  }

  Future<bool> clearCanvas(String groupId, String canvasId, int version,
      {int? bgColor}) async {
    if (groupId.isEmpty) return false;
    try {
      final strokes = await _pb.collection('canvas_strokes').getFullList(
            filter: _pb.filter('group_id = {:g} && canvas_id = {:c}',
                {'g': groupId, 'c': canvasId}),
          );
      for (final s in strokes) {
        await _pb.collection('canvas_strokes').delete(s.id);
      }
      final body = <String, dynamic>{
        'group_id': groupId,
        'canvas_id': canvasId,
        'clear_version': version,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (bgColor != null) body['bg_color'] = bgColor;
      return _upsertByFilter('canvas_meta',
          'group_id = {:g} && canvas_id = {:c}', {'g': groupId, 'c': canvasId},
          body, op: 'clearCanvas');
    } catch (e) {
      debugPrint('PbData.clearCanvas($groupId/$canvasId) failed: $e');
      return false;
    }
  }

  Future<bool> upsertCanvasMeta(String groupId, String canvasId,
      {int? bgColor, int? rotation, int? clearVersion}) async {
    if (groupId.isEmpty) return false;
    final body = <String, dynamic>{
      'group_id': groupId,
      'canvas_id': canvasId,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (bgColor != null) body['bg_color'] = bgColor;
    if (rotation != null) body['canvas_rotation'] = rotation;
    if (clearVersion != null) body['clear_version'] = clearVersion;
    return _upsertByFilter('canvas_meta',
        'group_id = {:g} && canvas_id = {:c}', {'g': groupId, 'c': canvasId},
        body, op: 'upsertCanvasMeta');
  }

  Future<bool> upsertCanvasCatalogue(
      String groupId, String canvasId, Map<String, dynamic> data) async {
    if (groupId.isEmpty || canvasId.isEmpty) return false;
    final body = <String, dynamic>{'group_id': groupId, 'canvas_id': canvasId};
    if (data.containsKey('name')) body['name'] = data['name'];
    if (data.containsKey('createdAt')) body['created_at'] = data['createdAt'];
    if (data.containsKey('updatedAt')) body['updated_at'] = data['updatedAt'];
    if (data.containsKey('createdBy')) body['created_by'] = data['createdBy'];
    return _upsertByFilter('canvas_catalogue',
        'group_id = {:g} && canvas_id = {:c}', {'g': groupId, 'c': canvasId},
        body, op: 'upsertCanvasCatalogue');
  }

  Future<bool> deleteCanvasCatalogue(String groupId, String canvasId) async {
    if (groupId.isEmpty || canvasId.isEmpty) return false;
    try {
      final rec = await _pb.collection('canvas_catalogue').getFirstListItem(
          _pb.filter('group_id = {:g} && canvas_id = {:c}',
              {'g': groupId, 'c': canvasId}));
      await _pb.collection('canvas_catalogue').delete(rec.id);
      return true;
    } catch (e) {
      if (e is ClientException && e.statusCode == 404) return true;
      debugPrint('PbData.deleteCanvasCatalogue failed: $e');
      return false;
    }
  }

  Future<List<RecordModel>> loadStrokes(String groupId, String canvasId) async {
    if (groupId.isEmpty) return const [];
    try {
      return await _pb.collection('canvas_strokes').getFullList(
            filter: _pb.filter('group_id = {:g} && canvas_id = {:c}',
                {'g': groupId, 'c': canvasId}),
            sort: 'order_index',
          );
    } catch (e) {
      debugPrint('PbData.loadStrokes failed: $e');
      return const [];
    }
  }

  Future<List<RecordModel>> loadCanvasCatalogue(String groupId) async {
    if (groupId.isEmpty) return const [];
    try {
      return await _pb.collection('canvas_catalogue').getFullList(
          filter: _pb.filter('group_id = {:g}', {'g': groupId}));
    } catch (e) {
      debugPrint('PbData.loadCanvasCatalogue failed: $e');
      return const [];
    }
  }

  // ══════════════════════════════════════════════ MASCOTS (составной group+mascot_id)
  Map<String, dynamic> _mascotBody(String groupId, Map<String, dynamic> m) => {
        'group_id': groupId,
        'mascot_id': m['id'], // SQL-поле id маскота → колонка mascot_id в PB
        'name': m['name'],
        'image_url': m['imageUrl'],
        'default_asset': m['defaultAsset'],
        'created_by': m['createdBy'],
        'created_at': _iso(m['createdAt']),
        'is_default': m['isDefault'] ?? false,
        'record_streak': m['recordStreak'] ?? 0,
      }..removeWhere((k, v) => v == null);

  Future<bool> upsertMascot(String groupId, Map<String, dynamic> m) async {
    final mid = (m['id'] ?? '').toString();
    if (groupId.isEmpty || mid.isEmpty) return false;
    return _upsertByFilter('mascots',
        'group_id = {:g} && mascot_id = {:m}', {'g': groupId, 'm': mid},
        _mascotBody(groupId, m), op: 'upsertMascot');
  }

  Future<bool> upsertMascotsBatch(
      String groupId, List<Map<String, dynamic>> mascots) async {
    if (groupId.isEmpty || mascots.isEmpty) return false;
    var ok = true;
    for (final m in mascots) {
      ok = await upsertMascot(groupId, m) && ok;
    }
    return ok;
  }

  Future<bool> deleteMascot(String groupId, String mascotId) async {
    if (groupId.isEmpty || mascotId.isEmpty) return false;
    try {
      final rec = await _pb.collection('mascots').getFirstListItem(_pb.filter(
          'group_id = {:g} && mascot_id = {:m}', {'g': groupId, 'm': mascotId}));
      await _pb.collection('mascots').delete(rec.id);
      return true;
    } catch (e) {
      if (e is ClientException && e.statusCode == 404) return true;
      debugPrint('PbData.deleteMascot failed: $e');
      return false;
    }
  }

  Future<bool> updateMascotFields(
      String groupId, String mascotId, Map<String, dynamic> cols) async {
    if (groupId.isEmpty || mascotId.isEmpty || cols.isEmpty) return false;
    try {
      final rec = await _pb.collection('mascots').getFirstListItem(_pb.filter(
          'group_id = {:g} && mascot_id = {:m}', {'g': groupId, 'm': mascotId}));
      await _pb.collection('mascots').update(rec.id, body: cols);
      return true;
    } catch (e) {
      debugPrint('PbData.updateMascotFields failed: $e');
      return false;
    }
  }

  Future<List<RecordModel>> loadMascots(String groupId) async {
    if (groupId.isEmpty) return const [];
    try {
      return await _pb.collection('mascots').getFullList(
          filter: _pb.filter('group_id = {:g}', {'g': groupId}));
    } catch (e) {
      debugPrint('PbData.loadMascots failed: $e');
      return const [];
    }
  }

  // ══════════════════════════════════════════════ MISS YOU (составной)
  /// Инкремент «скучаю» + тип вайба (miss_you/thinking_of_you/want_hug/custom)
  /// и кастом-текст — чтобы SSE-событие у партнёра несло содержимое пуша.
  Future<bool> incrementMissYou(
    String groupId,
    String uid, {
    String vibe = 'miss_you',
    String? text,
  }) async {
    if (groupId.isEmpty || uid.isEmpty) return false;
    try {
      final f = _pb.filter('group_id = {:g} && user_uid = {:u}',
          {'g': groupId, 'u': uid});
      final extra = {'last_vibe': vibe, 'last_vibe_text': text ?? ''};
      try {
        final rec = await _pb.collection('miss_you').getFirstListItem(f);
        final cur = (rec.data['count'] as num?)?.toInt() ?? 0;
        await _pb.collection('miss_you').update(rec.id, body: {
          'count': cur + 1,
          'updated_at': DateTime.now().toIso8601String(),
          ...extra,
        });
      } on ClientException catch (e) {
        if (e.statusCode != 404) rethrow;
        await _pb.collection('miss_you').create(body: {
          'group_id': groupId,
          'user_uid': uid,
          'count': 1,
          'updated_at': DateTime.now().toIso8601String(),
          ...extra,
        });
      }
      return true;
    } catch (e) {
      debugPrint('PbData.incrementMissYou failed: $e');
      return false;
    }
  }

  Future<bool> setMissYouCount(String groupId, String uid, int count) async {
    if (groupId.isEmpty || uid.isEmpty) return false;
    return _upsertByFilter('miss_you',
        'group_id = {:g} && user_uid = {:u}', {'g': groupId, 'u': uid}, {
      'group_id': groupId,
      'user_uid': uid,
      'count': count,
      'updated_at': DateTime.now().toIso8601String(),
    }, op: 'setMissYouCount');
  }

  Future<Map<String, int>> getMissYouCounts(String groupId) async {
    if (groupId.isEmpty) return const {};
    try {
      final rows = await _pb.collection('miss_you').getFullList(
          filter: _pb.filter('group_id = {:g}', {'g': groupId}));
      return {
        for (final r in rows)
          (r.data['user_uid'] ?? '').toString():
              (r.data['count'] as num?)?.toInt() ?? 0,
      };
    } catch (e) {
      debugPrint('PbData.getMissYouCounts failed: $e');
      return const {};
    }
  }

  // ══════════════════════════════════════════════ CHAT
  Future<bool> chatSend(String groupId, String id, Map<String, dynamic> msg) async {
    if (id.isEmpty) return false;
    final body = <String, dynamic>{
      'group_id': groupId,
      'user_uid': msg['uid'],
      'user_name': msg['name'],
      'text': msg['text'],
      'ts': msg['ts'],
      'pin_id': msg['pinId'],
      'pin_title': msg['pinTitle'],
      'pin_thumb': msg['pinThumb'],
      'reply_to_id': msg['replyToId'],
      'reply_to_name': msg['replyToName'],
      'reply_to_text': msg['replyToText'],
      'face': msg['face'],
      'color': msg['color'],
      'face_x': msg['faceX'],
      'face_y': msg['faceY'],
    }..removeWhere((k, v) => v == null);
    return _upsertById('chat_messages', id, body, op: 'chatSend');
  }

  Future<bool> chatUpdate(String id, Map<String, dynamic> fields) async {
    if (id.isEmpty) return false;
    return _upsertById('chat_messages', id, Map.of(fields), op: 'chatUpdate');
  }

  Future<bool> chatRead(String groupId, String uid, int ts) async {
    if (groupId.isEmpty || uid.isEmpty) return false;
    return _upsertByFilter('chat_reads',
        'group_id = {:g} && user_uid = {:u}', {'g': groupId, 'u': uid}, {
      'group_id': groupId,
      'user_uid': uid,
      'last_read_ts': ts,
      'updated_at': DateTime.now().toIso8601String(),
    }, op: 'chatRead');
  }

  /// Ставит/снимает реакцию uid на сообщение (RMW по json-полю reactions).
  Future<bool> setChatReaction(String id, String uid, String? emoji) async {
    if (id.isEmpty || uid.isEmpty) return false;
    try {
      final rec = await _pb
          .collection('chat_messages')
          .getFirstListItem(_pb.filter('id = {:id}', {'id': id}));
      final cur = rec.data['reactions'];
      final r = cur is Map ? Map<String, dynamic>.from(cur) : <String, dynamic>{};
      if (emoji == null || emoji.isEmpty) {
        r.remove(uid);
      } else {
        r[uid] = emoji;
      }
      await _pb.collection('chat_messages').update(rec.id, body: {'reactions': r});
      return true;
    } catch (e) {
      debugPrint('PbData.setChatReaction failed: $e');
      return false;
    }
  }

  /// Последние [limit] сообщений (новые сверху; разверни на стороне UI).
  Future<List<RecordModel>> loadMessages(String groupId, {int limit = 100}) async {
    if (groupId.isEmpty) return const [];
    try {
      final res = await _pb.collection('chat_messages').getList(
            perPage: limit,
            filter: _pb.filter('group_id = {:g}', {'g': groupId}),
            sort: '-ts',
          );
      return res.items;
    } catch (e) {
      debugPrint('PbData.loadMessages failed: $e');
      return const [];
    }
  }

  Future<Map<String, int>> loadChatReads(String groupId) async {
    if (groupId.isEmpty) return const {};
    try {
      final rows = await _pb.collection('chat_reads').getFullList(
          filter: _pb.filter('group_id = {:g}', {'g': groupId}));
      return {
        for (final r in rows)
          (r.data['user_uid'] ?? '').toString():
              (r.data['last_read_ts'] as num?)?.toInt() ?? 0,
      };
    } catch (e) {
      debugPrint('PbData.loadChatReads failed: $e');
      return const {};
    }
  }

  // ══════════════════════════════════════════════ USER PROFILE / CATALOG
  /// Профиль юзера = запись users по id (= uid). Возвращает raw-данные записи.
  Future<RecordModel?> loadUserProfile(String uid) async {
    if (uid.isEmpty) return null;
    try {
      return await _pb.collection('users').getOne(uid);
    } catch (e) {
      if (e is ClientException && e.statusCode == 404) return null;
      debugPrint('PbData.loadUserProfile($uid) failed: $e');
      return null;
    }
  }

  /// Обновляет профильные поля users (camelCase→snake_case). id=uid должен
  /// существовать (создаётся при регистрации/импорте, не здесь).
  Future<bool> updateUserProfile(String uid, Map<String, dynamic> data) async {
    if (uid.isEmpty) return false;
    final row = <String, dynamic>{};
    void put(String key, String col, {bool json = false, bool ts = false}) {
      if (!data.containsKey(key)) return;
      final v = data[key];
      row[col] = ts ? _iso(v) : (json ? _jsonSafe(v) : v);
    }

    put('displayName', 'display_name');
    put('avatarUrl', 'avatar_url');
    put('gender', 'gender');
    put('birthDate', 'birth_date', ts: true);
    put('coins', 'coins');
    put('ownedThemes', 'owned_themes', json: true);
    put('ownedIcons', 'owned_icons', json: true);
    put('ownedFeatures', 'owned_features', json: true);
    put('grantedBadges', 'granted_badges', json: true);
    put('badge', 'badge');
    put('pairId', 'pair_id');
    put('pairIds', 'pair_ids', json: true);
    put('inviteCode', 'invite_code');
    put('fcmToken', 'fcm_token');
    put('fcmTokens', 'fcm_tokens', json: true);
    put('notifMissYou', 'notif_miss_you');
    put('notifNewMemory', 'notif_new_memory');
    put('notifMood', 'notif_mood');
    put('notifChat', 'notif_chat');
    put('soloTimers', 'solo_timers', json: true);
    if (row.isEmpty) return true;
    row['updated_at'] = DateTime.now().toIso8601String();
    return _upsertById('users', uid, row, op: 'updateUserProfile');
  }

  /// Каталог (mood-паки/маскоты): включённые записи нужного типа.
  Future<List<RecordModel>> loadCatalog(String kind) async {
    try {
      return await _pb.collection('catalog_items').getFullList(
            filter: _pb.filter('kind = {:k} && enabled = true', {'k': kind}),
            sort: 'sort',
          );
    } catch (e) {
      debugPrint('PbData.loadCatalog($kind) failed: $e');
      return const [];
    }
  }

  /// ISO-строка PB → DateTime (публичный хелпер для слоя моделей на cutover).
  static DateTime? parseDate(dynamic v) => _date(v);
}
