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

  /// ISO-строка PB → DateTime (публичный хелпер для слоя моделей на cutover).
  static DateTime? parseDate(dynamic v) => _date(v);
}
