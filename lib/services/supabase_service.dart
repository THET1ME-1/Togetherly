import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/migration_config.dart';
import '../models/chat_msg.dart';

/// Зеркало + чтение данных в Supabase для миграции (Фаза 1).
///
/// Два режима работы:
///   • mirror*()  — двойная запись: дублирует запись Firebase в Supabase
///                  (fire-and-forget, ошибки глотаются, Firebase — источник правды).
///   • load*/listen*() — чтение из Supabase в ТОМ ЖЕ формате, что отдаёт
///                  FirebaseService, чтобы слой UI не менялся.
///
/// Все методы безопасны при незаполненных credentials: гард [isReady].
class SupabaseService {
  static final SupabaseService _instance = SupabaseService._();
  factory SupabaseService() => _instance;
  SupabaseService._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// Готов ли Supabase (credentials заполнены и SDK инициализирован в main).
  bool get isReady => MigrationConfig.isConfigured;

  // ══════════════════════════════════════════════
  //  УТИЛИТЫ КОНВЕРТАЦИИ
  // ══════════════════════════════════════════════

  /// Рекурсивно превращает firestore-данные в JSON-safe для Supabase JSONB:
  /// Timestamp/DateTime → ISO-строка, вложенные Map/List — обходятся.
  static dynamic _jsonSafe(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate().toIso8601String();
    if (v is DateTime) return v.toIso8601String();
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), _jsonSafe(val)));
    }
    if (v is List) return v.map(_jsonSafe).toList();
    return v;
  }

  /// Timestamp/DateTime/String → ISO-строка (для timestamptz-колонок), или null.
  static String? _isoTs(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate().toIso8601String();
    if (v is DateTime) return v.toIso8601String();
    if (v is String) return v;
    return null;
  }

  /// ISO-строка из Supabase → Timestamp (для совместимости с *.fromFirestore).
  static Timestamp? _toTs(dynamic v) {
    if (v == null) return null;
    if (v is String) {
      final d = DateTime.tryParse(v);
      return d == null ? null : Timestamp.fromDate(d);
    }
    return null;
  }

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  // ══════════════════════════════════════════════
  //  USER
  // ══════════════════════════════════════════════

  /// Чтение профиля. Возвращает Map с camelCase-ключами (как Firestore-документ).
  Future<Map<String, dynamic>?> loadUserProfile(String uid) async {
    if (!isReady) return null;
    try {
      final row = await _client
          .from('users')
          .select()
          .eq('uid', uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
      if (row == null) return null;
      return _userRowToFirebaseMap(row);
    } catch (e) {
      debugPrint('SupabaseService.loadUserProfile failed: $e');
      return null;
    }
  }

  /// Двойная запись профиля. [data] — camelCase-ключи (как в saveUserProfile).
  Future<void> mirrorUser(String uid, Map<String, dynamic> data) async {
    if (!isReady) return;
    try {
      await _client
          .from('users')
          .upsert(_userFirebaseMapToRow(uid, data), onConflict: 'uid')
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('SupabaseService.mirrorUser failed: $e');
    }
  }

  Map<String, dynamic> _userRowToFirebaseMap(Map<String, dynamic> row) {
    List<T> asList<T>(dynamic v) =>
        v is List ? List<T>.from(v.map((e) => e as T)) : <T>[];
    return {
      'displayName': row['display_name'],
      'email': row['email'],
      'avatarUrl': row['avatar_url'],
      'gender': row['gender'],
      'birthDate': _toDate(row['birth_date']),
      'coins': row['coins'] ?? 0,
      'ownedThemes': asList<dynamic>(row['owned_themes']).map((e) => e is int ? e : int.tryParse('$e') ?? 0).toList(),
      'ownedIcons': asList<String>(row['owned_icons']),
      'ownedFeatures': asList<String>(row['owned_features']),
      'grantedBadges': asList<String>(row['granted_badges']),
      'badge': row['badge'],
      'pairId': row['pair_id'],
      'pairIds': asList<String>(row['pair_ids']),
      'inviteCode': row['invite_code'],
      'fcmToken': row['fcm_token'],
      'fcmTokens': asList<String>(row['fcm_tokens']),
      'notifMissYou': row['notif_miss_you'] ?? true,
      'notifNewMemory': row['notif_new_memory'] ?? true,
      'notifMood': row['notif_mood'] ?? true,
      'notifChat': row['notif_chat'] ?? true,
      'soloTimers': row['solo_timers'] ?? [],
      'updatedAt': _toDate(row['updated_at']),
    };
  }

  Map<String, dynamic> _userFirebaseMapToRow(
    String uid,
    Map<String, dynamic> data,
  ) {
    final row = <String, dynamic>{'uid': uid};
    void put(String key, String col, {bool ts = false, bool json = false}) {
      if (!data.containsKey(key)) return;
      final v = data[key];
      row[col] = ts ? _isoTs(v) : (json ? _jsonSafe(v) : v);
    }

    put('displayName', 'display_name');
    put('email', 'email');
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
    row['updated_at'] = DateTime.now().toIso8601String();
    return row;
  }

  // ══════════════════════════════════════════════
  //  GROUP
  // ══════════════════════════════════════════════

  Future<Map<String, dynamic>?> loadPairById(
    String pairId,
    String currentUid,
  ) async {
    if (!isReady) return null;
    try {
      final row = await _client
          .from('groups')
          .select()
          .eq('id', pairId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
      if (row == null || row['disbanded'] == true) return null;
      return _groupRowToParsed(row, currentUid);
    } catch (e) {
      debugPrint('SupabaseService.loadPairById($pairId) failed: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> loadPairData(String currentUid) async {
    if (!isReady) return null;
    try {
      final rows = await _client
          .from('groups')
          .select()
          .contains('members', [currentUid])
          .eq('disbanded', false)
          .limit(1)
          .timeout(const Duration(seconds: 10));
      if (rows.isEmpty) return null;
      return _groupRowToParsed(rows.first, currentUid);
    } catch (e) {
      debugPrint('SupabaseService.loadPairData failed: $e');
      return null;
    }
  }

  /// Двойная запись группы из «сырого» firestore-документа (data из _parseGroupDoc
  /// или прямого чтения group-doc). Конвертирует Timestamps в ISO.
  Future<void> mirrorGroupRaw(String groupId, Map<String, dynamic> raw) async {
    if (!isReady || groupId.isEmpty) return;
    try {
      final row = <String, dynamic>{
        'id': groupId,
        'members': _jsonSafe(raw['members'] ?? []),
        'member_names': _jsonSafe(raw['memberNames'] ?? {}),
        'member_avatars': _jsonSafe(raw['memberAvatars'] ?? {}),
        'max_members': raw['maxMembers'] ?? 2,
        'relationship_type': raw['relationshipType'] ?? 'couple',
        'custom_relationship_label': raw['customRelationshipLabel'],
        'custom_relationship_emoji': raw['customRelationshipEmoji'],
        'custom_relationship_types':
            _jsonSafe(raw['customRelationshipTypes'] ?? []),
        'start_date': _isoTs(raw['startDate']),
        'anniversary_date': _isoTs(raw['anniversaryDate']),
        'first_kiss_date': _isoTs(raw['firstKissDate']),
        'member_birthdays': _jsonSafe(raw['memberBirthdays'] ?? {}),
        'member_moods': _jsonSafe(raw['memberMoods'] ?? {}),
        'current_status': _jsonSafe(raw['currentStatus']),
        'custom_statuses': _jsonSafe(raw['customStatuses'] ?? []),
        'memories_count': raw['memoriesCount'] ?? 0,
        'drawings_count': raw['drawingsCount'] ?? 0,
        'active_session': _jsonSafe(raw['activeSession']),
        'disbanded': raw['disbanded'] ?? false,
        'disbanded_at': _isoTs(raw['disbandedAt']),
        'timers': _jsonSafe(raw['timers'] ?? []),
        'mascots': _jsonSafe(raw['mascots'] ?? []),
      };
      // Убираем null-ключи, чтобы upsert не затирал заполненные поля null'ами.
      row.removeWhere((k, v) => v == null && k != 'id');
      await _client
          .from('groups')
          .upsert(row, onConflict: 'id')
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('SupabaseService.mirrorGroupRaw failed: $e');
    }
  }

  /// Точечно зеркалит массив timers группы (для upsert/delete таймеров).
  Future<void> mirrorTimers(
    String groupId,
    List<Map<String, dynamic>> timers,
  ) async {
    if (!isReady || groupId.isEmpty) return;
    try {
      await _client
          .from('groups')
          .upsert({'id': groupId, 'timers': _jsonSafe(timers)},
              onConflict: 'id')
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('SupabaseService.mirrorTimers failed: $e');
    }
  }

  /// Live-подписка на timers группы. [onData] получает «сырые» json таймеров.
  StreamSubscription? listenGroupTimers(
    String groupId,
    void Function(List<Map<String, dynamic>> timers) onData,
  ) {
    if (!isReady || groupId.isEmpty) return null;
    try {
      String? prevHash;
      return _client
          .from('groups')
          .stream(primaryKey: ['id'])
          .eq('id', groupId)
          .listen((rows) {
        if (rows.isEmpty) return;
        final raw = rows.first['timers'];
        final list = raw is List
            ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : <Map<String, dynamic>>[];
        final hash = list.toString();
        if (hash == prevHash) return;
        prevHash = hash;
        onData(list);
      }, onError: (e) => debugPrint('listenGroupTimers error: $e'));
    } catch (e) {
      debugPrint('SupabaseService.listenGroupTimers failed: $e');
      return null;
    }
  }

  Map<String, dynamic> _groupRowToParsed(
    Map<String, dynamic> row,
    String currentUid,
  ) {
    final members =
        (row['members'] as List? ?? []).map((e) => e.toString()).toSet().toList();
    final memberNames = Map<String, dynamic>.from(row['member_names'] ?? {});
    final memberAvatars =
        Map<String, dynamic>.from(row['member_avatars'] ?? {});

    final otherUids = members.where((m) => m != currentUid).toList();
    final partnerUid = otherUids.isNotEmpty ? otherUids.first : '';

    final memberMoods =
        Map<String, dynamic>.from(row['member_moods'] ?? {}).map((uid, m) {
      final mm = Map<String, dynamic>.from(m as Map);
      final d = _toDate(mm['updatedAt']);
      if (d != null) mm['updatedAt'] = d;
      return MapEntry(uid, mm);
    });

    final memberBirthdays =
        Map<String, dynamic>.from(row['member_birthdays'] ?? {})
            .map((k, v) => MapEntry(k, _toDate(v)));

    return {
      'pairId': row['id'],
      'partnerName': memberNames[partnerUid] ?? '',
      'partnerAvatar': memberAvatars[partnerUid] ?? '',
      'startDate': _toDate(row['start_date']),
      'members': members
          .map((uid) => {
                'uid': uid,
                'name': memberNames[uid] ?? '',
                'avatar': memberAvatars[uid] ?? '',
              })
          .toList(),
      'maxMembers': row['max_members'] ?? 2,
      'memberMoods': memberMoods,
      'currentStatus': row['current_status'] == null
          ? null
          : Map<String, dynamic>.from(row['current_status']),
      'customStatuses': row['custom_statuses'] as List?,
      'relationshipType': row['relationship_type'],
      'customRelationshipLabel': row['custom_relationship_label'],
      'customRelationshipEmoji': row['custom_relationship_emoji'],
      'customRelationshipTypes': row['custom_relationship_types'] as List?,
      'anniversaryDate': _toDate(row['anniversary_date']),
      'firstKissDate': _toDate(row['first_kiss_date']),
      'memberBirthdays': memberBirthdays,
      'raw': {
        ...row,
        'startDate': _toDate(row['start_date']),
        'anniversaryDate': _toDate(row['anniversary_date']),
        'firstKissDate': _toDate(row['first_kiss_date']),
        'timers': row['timers'] ?? [],
        'mascots': row['mascots'] ?? [],
        'disbanded': row['disbanded'] ?? false,
      },
    };
  }

  // ══════════════════════════════════════════════
  //  MOOD
  // ══════════════════════════════════════════════

  /// Чтение всех записей настроений пользователя в группе.
  /// Возвращает Map'ы с 'timestamp' как Timestamp — совместимо с
  /// MoodEntry.fromFirestore.
  Future<List<Map<String, dynamic>>> loadMoodEntries(
    String groupId,
    String uid,
  ) async {
    if (!isReady) return const [];
    try {
      final rows = await _client
          .from('mood_entries')
          .select()
          .eq('group_id', groupId)
          .eq('user_uid', uid)
          .timeout(const Duration(seconds: 10));
      return rows.map(_moodRowToFirestore).toList();
    } catch (e) {
      debugPrint('SupabaseService.loadMoodEntries failed: $e');
      return const [];
    }
  }

  /// Live-подписка на записи настроений пользователя в группе.
  StreamSubscription? listenMoodEntries(
    String groupId,
    String uid,
    void Function(List<Map<String, dynamic>> entries) onData,
  ) {
    if (!isReady || groupId.isEmpty) return null;
    try {
      return _client
          .from('mood_entries')
          .stream(primaryKey: ['id'])
          .eq('group_id', groupId)
          .listen((rows) {
        final mine = rows.where((r) => r['user_uid'] == uid);
        onData(mine.map(_moodRowToFirestore).toList());
      }, onError: (e) => debugPrint('listenMoodEntries error: $e'));
    } catch (e) {
      debugPrint('SupabaseService.listenMoodEntries failed: $e');
      return null;
    }
  }

  Map<String, dynamic> _moodRowToFirestore(Map<String, dynamic> row) => {
        'id': row['id'] ?? '',
        'moodId': row['mood_id'] ?? '',
        'imagePath': row['image_path'] ?? '',
        'label': row['label'] ?? '',
        'timestamp': _toTs(row['timestamp']) ?? Timestamp.now(),
      };

  /// Двойная запись записи настроения. [entry] — формат toFirestore (с Timestamp).
  Future<void> mirrorMoodEntry(
    String groupId,
    String uid,
    Map<String, dynamic> entry,
  ) async {
    if (!isReady) return;
    final id = entry['id'] as String?;
    if (id == null) return;
    try {
      await _client.from('mood_entries').upsert({
        'id': id,
        'group_id': groupId,
        'user_uid': uid,
        'mood_id': entry['moodId'],
        'image_path': entry['imagePath'],
        'label': entry['label'],
        'timestamp': _isoTs(entry['timestamp']) ??
            DateTime.now().toIso8601String(),
      }, onConflict: 'id').timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('SupabaseService.mirrorMoodEntry failed: $e');
    }
  }

  Future<void> mirrorMoodDelete(String entryId) async {
    if (!isReady) return;
    try {
      await _client
          .from('mood_entries')
          .delete()
          .eq('id', entryId)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('SupabaseService.mirrorMoodDelete failed: $e');
    }
  }

  // ══════════════════════════════════════════════
  //  MEMORIES (dual-write; чтение пока из Firebase)
  // ══════════════════════════════════════════════

  /// Двойная запись воспоминания. [data] — полный firestore-map воспоминания.
  Future<void> mirrorMemory(
    String groupId,
    String id,
    Map<String, dynamic> data,
  ) async {
    if (!isReady || id.isEmpty) return;
    try {
      await _client.from('memories').upsert({
        'id': id,
        'group_id': groupId,
        'type': data['type'],
        'author_uid': data['authorUid'],
        'author_name': data['authorName'],
        'author_avatar': data['authorAvatar'],
        'created_at': _isoTs(data['createdAt']),
        'edited_at': _isoTs(data['editedAt']),
        'is_pinned': data['isPinned'] ?? false,
        'deleted': data['deleted'] ?? false,
        'data': _jsonSafe(data),
      }, onConflict: 'id').timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('SupabaseService.mirrorMemory failed: $e');
    }
  }

  /// Частичное обновление зеркала воспоминания (известные колонки).
  /// [fb] — те же camelCase-ключи, что updateMemory пишет в Firestore.
  Future<void> mirrorMemoryPatch(String id, Map<String, dynamic> fb) async {
    if (!isReady || id.isEmpty) return;
    final cols = <String, dynamic>{};
    if (fb.containsKey('isPinned')) cols['is_pinned'] = fb['isPinned'];
    if (fb.containsKey('editedAt')) cols['edited_at'] = _isoTs(fb['editedAt']);
    if (fb.containsKey('createdAt')) cols['created_at'] = _isoTs(fb['createdAt']);
    if (cols.isEmpty) return;
    try {
      await _client.from('memories').update(cols).eq('id', id);
    } catch (e) {
      debugPrint('SupabaseService.mirrorMemoryPatch failed: $e');
    }
  }

  Future<void> mirrorMemoryDelete(String id, {bool hard = false}) async {
    if (!isReady || id.isEmpty) return;
    try {
      if (hard) {
        await _client.from('memories').delete().eq('id', id);
      } else {
        await _client.from('memories').update({'deleted': true}).eq('id', id);
      }
    } catch (e) {
      debugPrint('SupabaseService.mirrorMemoryDelete failed: $e');
    }
  }

  // ══════════════════════════════════════════════
  //  MISS YOU
  // ══════════════════════════════════════════════

  Future<Map<String, int>> getMissYouCounts(String groupId) async {
    if (!isReady) return {};
    try {
      final rows = await _client
          .from('miss_you')
          .select('user_uid, count')
          .eq('group_id', groupId)
          .timeout(const Duration(seconds: 10));
      return {
        for (final r in rows)
          (r['user_uid'] as String): ((r['count'] as num?)?.toInt() ?? 0),
      };
    } catch (e) {
      debugPrint('SupabaseService.getMissYouCounts failed: $e');
      return {};
    }
  }

  StreamSubscription? listenMissYouCounts(
    String groupId,
    void Function(Map<String, int> counts) onData,
  ) {
    if (!isReady || groupId.isEmpty) return null;
    try {
      String prevHash = '';
      return _client
          .from('miss_you')
          .stream(primaryKey: ['group_id', 'user_uid'])
          .eq('group_id', groupId)
          .listen((rows) {
        final counts = <String, int>{
          for (final r in rows)
            (r['user_uid'] as String): ((r['count'] as num?)?.toInt() ?? 0),
        };
        final hash = counts.toString();
        if (hash == prevHash) return;
        prevHash = hash;
        onData(counts);
      }, onError: (e) => debugPrint('listenMissYouCounts error: $e'));
    } catch (e) {
      debugPrint('SupabaseService.listenMissYouCounts failed: $e');
      return null;
    }
  }

  Future<void> mirrorMissYouIncrement(String groupId, String uid) async {
    if (!isReady) return;
    try {
      await _client.rpc('increment_miss_you', params: {
        'p_group_id': groupId,
        'p_user_uid': uid,
      }).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('SupabaseService.mirrorMissYouIncrement failed: $e');
    }
  }

  /// Сидирование/синхронизация ПОЛНОГО набора счётчиков из RTDB в Supabase.
  /// Берёт max(существующее, RTDB), чтобы не откатить живой счётчик.
  /// Нужно для подтягивания исторических тапов (накопленных до dual-write).
  Future<void> mirrorMissYouCountsFull(
    String groupId,
    Map<String, int> counts,
  ) async {
    if (!isReady || counts.isEmpty) return;
    try {
      // Текущие значения в Supabase, чтобы не понизить.
      final existing = await getMissYouCounts(groupId);
      final rows = <Map<String, dynamic>>[];
      counts.forEach((uid, rtdbVal) {
        final cur = existing[uid] ?? 0;
        final val = rtdbVal > cur ? rtdbVal : cur;
        rows.add({
          'group_id': groupId,
          'user_uid': uid,
          'count': val,
          'updated_at': DateTime.now().toIso8601String(),
        });
      });
      if (rows.isNotEmpty) {
        await _client
            .from('miss_you')
            .upsert(rows, onConflict: 'group_id,user_uid')
            .timeout(const Duration(seconds: 10));
      }
    } catch (e) {
      debugPrint('SupabaseService.mirrorMissYouCountsFull failed: $e');
    }
  }

  Future<void> mirrorMissYouReset(String groupId, String uid) async {
    if (!isReady) return;
    try {
      await _client.from('miss_you').upsert({
        'group_id': groupId,
        'user_uid': uid,
        'count': 0,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'group_id,user_uid');
    } catch (e) {
      debugPrint('SupabaseService.mirrorMissYouReset failed: $e');
    }
  }

  // ══════════════════════════════════════════════
  //  WIDGET DATA (dual-write; чтение пока из Firebase)
  // ══════════════════════════════════════════════

  Future<void> mirrorWidgetData(
    String groupId,
    String uid,
    Map<String, dynamic> fields,
  ) async {
    if (!isReady || groupId.isEmpty) return;
    try {
      const colMap = {
        'displayName': 'display_name',
        'avatarUrl': 'avatar_url',
        'gender': 'gender',
        'status': 'status',
        'moodEmoji': 'mood_emoji',
        'moodLabel': 'mood_label',
        'message': 'message',
        'musicTitle': 'music_title',
        'musicArtist': 'music_artist',
        'musicUrl': 'music_url',
        'musicCoverUrl': 'music_cover_url',
        'photoUrl': 'photo_url',
      };
      final row = <String, dynamic>{
        'group_id': groupId,
        'user_uid': uid,
        'updated_at': DateTime.now().toIso8601String(),
      };
      fields.forEach((k, v) {
        final col = colMap[k];
        if (col != null) row[col] = v;
      });
      // Полный снимок полей — в data JSONB (на случай чтения позже).
      row['data'] = _jsonSafe(fields);
      await _client
          .from('widget_data')
          .upsert(row, onConflict: 'group_id,user_uid')
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('SupabaseService.mirrorWidgetData failed: $e');
    }
  }

  // ══════════════════════════════════════════════
  //  CHAT
  // ══════════════════════════════════════════════

  /// Live-поток последних [limit] сообщений группы.
  Stream<List<ChatMsg>> watchMessages(String groupId, {int limit = 100}) {
    if (!isReady || groupId.isEmpty) return const Stream.empty();
    try {
      return _client
          .from('chat_messages')
          .stream(primaryKey: ['id'])
          .eq('group_id', groupId)
          .order('ts')
          .limit(limit)
          .map((rows) => rows.map(_chatRowToMsg).toList());
    } catch (e) {
      debugPrint('SupabaseService.watchMessages failed: $e');
      return const Stream.empty();
    }
  }

  ChatMsg _chatRowToMsg(Map<String, dynamic> row) {
    final rawReactions = row['reactions'];
    final reactions = <String, String>{};
    if (rawReactions is Map) {
      rawReactions.forEach((k, v) {
        if (v is String && v.isNotEmpty) reactions[k.toString()] = v;
      });
    }
    return ChatMsg(
      id: (row['id'] ?? '').toString(),
      uid: (row['user_uid'] ?? '').toString(),
      name: (row['user_name'] ?? '').toString(),
      text: (row['text'] ?? '').toString(),
      ts: (row['ts'] as num?)?.toInt() ?? 0,
      editedTs: (row['edited_ts'] as num?)?.toInt(),
      deleted: (row['deleted'] as bool?) ?? false,
      pinId: row['pin_id'] as String?,
      pinTitle: row['pin_title'] as String?,
      pinThumb: row['pin_thumb'] as String?,
      reactions: reactions,
    );
  }

  /// Двойная запись отправки сообщения.
  Future<void> mirrorChatSend({
    required String groupId,
    required String id,
    required String uid,
    required String name,
    required String text,
    required int ts,
    String? pinId,
    String? pinTitle,
    String? pinThumb,
  }) async {
    if (!isReady) return;
    try {
      await _client.from('chat_messages').upsert({
        'id': id,
        'group_id': groupId,
        'user_uid': uid,
        'user_name': name,
        'text': text,
        'ts': ts,
        if (pinId != null) 'pin_id': pinId,
        if (pinTitle != null) 'pin_title': pinTitle,
        if (pinThumb != null) 'pin_thumb': pinThumb,
      }, onConflict: 'id').timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('SupabaseService.mirrorChatSend failed: $e');
    }
  }

  /// Двойная запись правки/удаления/реакции сообщения.
  Future<void> mirrorChatUpdate(String id, Map<String, dynamic> fields) async {
    if (!isReady || id.isEmpty) return;
    try {
      await _client.from('chat_messages').update(fields).eq('id', id);
    } catch (e) {
      debugPrint('SupabaseService.mirrorChatUpdate failed: $e');
    }
  }

  /// Проверка соединения (для диагностики).
  Future<bool> checkConnection() async {
    if (!isReady) return false;
    try {
      await _client.from('users').select('uid').limit(1).timeout(
            const Duration(seconds: 5),
          );
      return true;
    } catch (_) {
      return false;
    }
  }
}
