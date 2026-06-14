import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/migration_config.dart';
import '../models/chat_msg.dart';
import '../models/memory.dart';
import '../models/comment.dart';
import '../models/mascot.dart';

/// Зеркало + чтение данных в Supabase для миграции (Фаза 1).
///
/// Два режима работы:
///   • mirror*()  — двойная запись: дублирует запись Firebase в Supabase
///                  (fire-and-forget, ошибки глотаются, Firebase — источник правды).
///   • load*/listen*() — чтение из Supabase в ТОМ ЖЕ формате, что отдаёт
///                  FirebaseService, чтобы слой UI не менялся.
///
/// Все методы безопасны при незаполненных credentials: гард [isReady].

class _SbSignedUrlEntry {
  final String url;
  final DateTime expiresAt;
  const _SbSignedUrlEntry(this.url, this.expiresAt);
  bool get isValid => DateTime.now().isBefore(expiresAt);
}

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._();
  factory SupabaseService() => _instance;
  SupabaseService._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// Монотонный счётчик для уникальных имён realtime-каналов (miss_you и т.п.).
  static int _channelSeq = 0;

  /// Готов ли Supabase (credentials заполнены и SDK инициализирован в main).
  bool get isReady => MigrationConfig.isConfigured;

  // ══════════════════════════════════════════════
  //  НАДЁЖНАЯ ЗАПИСЬ (повторы + экспоненциальная пауза)
  // ══════════════════════════════════════════════

  /// Выполняет запись в Supabase с ограниченными повторами и нарастающей паузой.
  ///
  /// Возвращает true при успехе, false если все попытки исчерпаны (ошибка
  /// залогирована). НЕ бросает — безопасно для fire-and-forget dual-write и для
  /// подсчёта неудач при бэкфилле. Транзиентные сбои (сеть/таймаут/5xx) лечатся
  /// сразу; то, что не вылечилось, доберёт сверочный проход (reconciliation),
  /// потому что Firebase остаётся источником правды.
  Future<bool> _write(
    String label,
    Future<void> Function() op, {
    int maxAttempts = 4,
  }) async {
    var delay = const Duration(milliseconds: 400);
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await op();
        return true;
      } catch (e) {
        if (attempt >= maxAttempts) {
          debugPrint('SupabaseService.$label failed after $attempt attempts: $e');
          return false;
        }
        await Future.delayed(delay);
        delay *= 2;
      }
    }
    return false;
  }

  // ══════════════════════════════════════════════
  //  УТИЛИТЫ КОНВЕРТАЦИИ
  // ══════════════════════════════════════════════

  /// Публичная версия [_jsonSafe] — для вызывающих сервисов, которым нужно
  /// подготовить firestore-значения к записи в JSONB-колонку.
  static dynamic jsonSafe(dynamic v) => _jsonSafe(v);

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
  /// Возвращает true при успехе (для подсчёта неудач при бэкфилле).
  Future<bool> mirrorUser(String uid, Map<String, dynamic> data) async {
    if (!isReady) return false;
    return _write('mirrorUser', () async {
      await _client
          .from('users')
          .upsert(_userFirebaseMapToRow(uid, data), onConflict: 'uid')
          .timeout(const Duration(seconds: 10));
    });
  }

  /// Вызов «коиновой» серверной логики через Postgres RPC (замена Cloud
  /// Functions). [fbName] — имя бывшей Firebase-функции, маппится на public RPC.
  /// Возвращает JSONB-ответ как Map (ключи ok/coins/owned*/awarded — те же, что
  /// отдавал callable), чтобы вызывающий код не менялся.
  Future<Map<String, dynamic>?> callCoinRpc(
    String fbName,
    String uid,
    Map<String, dynamic> data,
  ) async {
    if (!isReady) return null;
    final params = <String, dynamic>{'p_uid': uid};
    String rpc;
    switch (fbName) {
      case 'purchaseTheme':
        rpc = 'purchase_theme';
        params['p_theme_id'] = data['themeId'];
        break;
      case 'purchaseIcon':
        rpc = 'purchase_icon';
        params['p_icon_id'] = data['iconId'];
        break;
      case 'purchaseFeature':
        rpc = 'purchase_feature';
        params['p_feature_id'] = data['featureId'];
        break;
      case 'spendCoins':
        rpc = 'spend_coins';
        params['p_action_id'] = data['actionId'];
        break;
      case 'grantDailyBonus':
        rpc = 'grant_daily_bonus';
        break;
      case 'grantCoinsPurchase':
        rpc = 'grant_coins_purchase';
        params['p_product_id'] = data['productId'];
        params['p_purchase_token'] = data['purchaseToken'];
        break;
      case 'grantDevCoins':
        rpc = 'grant_dev_coins';
        break;
      case 'grantMemoryReward':
        rpc = 'grant_memory_reward';
        break;
      case 'grantAdReward':
        rpc = 'grant_ad_reward';
        break;
      case 'grantPartnerInviteReward':
        rpc = 'grant_partner_invite_reward';
        break;
      case 'grantMoodStreakReward':
        rpc = 'grant_mood_streak_reward';
        params['p_group_id'] = data['groupId'];
        break;
      default:
        debugPrint('SupabaseService.callCoinRpc: неизвестная функция $fbName');
        return null;
    }
    try {
      final res = await _client
          .rpc(rpc, params: params)
          .timeout(const Duration(seconds: 15));
      if (res is Map) return Map<String, dynamic>.from(res);
      return null;
    } catch (e) {
      debugPrint('SupabaseService.callCoinRpc($fbName) failed: $e');
      return null;
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
      'devCoinsGranted': row['dev_coins_granted'] ?? false,
      'partnerInviteRewardGranted': row['partner_invite_reward_granted'] ?? false,
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
  Future<bool> mirrorGroupRaw(String groupId, Map<String, dynamic> raw) async {
    if (!isReady || groupId.isEmpty) return false;
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
    return _write('mirrorGroupRaw', () async {
      await _client
          .from('groups')
          .upsert(row, onConflict: 'id')
          .timeout(const Duration(seconds: 10));
    });
  }

  /// Точечно обновляет отдельные колонки группы (snake_case → значение).
  /// В отличие от mirrorGroupRaw НЕ выкидывает null — поэтому годится для
  /// ОЧИСТКИ полей (current_status/active_session → null). Использует update
  /// (а не upsert): если строки нет — 0 строк, без вставки с дефолтами.
  Future<bool> mirrorGroupFields(
    String groupId,
    Map<String, dynamic> columns,
  ) async {
    if (!isReady || groupId.isEmpty || columns.isEmpty) return false;
    return _write('mirrorGroupFields', () async {
      await _client
          .from('groups')
          .update(columns)
          .eq('id', groupId)
          .timeout(const Duration(seconds: 10));
    });
  }

  /// Точечно зеркалит массив timers группы (для upsert/delete таймеров).
  Future<bool> mirrorTimers(
    String groupId,
    List<Map<String, dynamic>> timers,
  ) async {
    if (!isReady || groupId.isEmpty) return false;
    return _write('mirrorTimers', () async {
      await _client
          .from('groups')
          .upsert({'id': groupId, 'timers': _jsonSafe(timers)},
              onConflict: 'id')
          .timeout(const Duration(seconds: 10));
    });
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

  /// Live-подписка на группу (realtime). [onData] получает распарсенную карту
  /// в ТОМ ЖЕ формате, что отдаёт FirebaseService._parseGroupDoc, или null если
  /// группа распущена/удалена. Замена listenToPair при чтении из Supabase.
  StreamSubscription? listenPair(
    String groupId,
    String currentUid,
    void Function(Map<String, dynamic>? data) onData,
  ) {
    if (!isReady || groupId.isEmpty) return null;
    try {
      return _client
          .from('groups')
          .stream(primaryKey: ['id'])
          .eq('id', groupId)
          .listen((rows) {
        if (rows.isEmpty) {
          onData(null);
          return;
        }
        final row = rows.first;
        if (row['disbanded'] == true) {
          onData(null);
          return;
        }
        onData(_groupRowToParsed(row, currentUid));
      }, onError: (e) => debugPrint('listenPair error: $e'));
    } catch (e) {
      debugPrint('SupabaseService.listenPair failed: $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════
  //  GROUP — Этап 4: Supabase как первичное хранилище group-полей.
  //  JSONB-карты «uid → значение» меняются через Postgres RPC (jsonb_set):
  //  оба партнёра пишут свои ключи одновременно, read-modify-write с клиента
  //  терял бы чужой ключ. (supabase/group_ops.sql)
  // ══════════════════════════════════════════════

  /// Текущее настроение участника на карточке (groups.member_moods.{uid}).
  /// [mood] — {imagePath, label, updatedAt} c JSON-safe значениями.
  Future<bool> setMemberMood(
    String groupId,
    String uid,
    Map<String, dynamic> mood,
  ) async {
    if (!isReady || groupId.isEmpty || uid.isEmpty) return false;
    return _write('setMemberMood', () async {
      await _client.rpc('group_set_member_mood', params: {
        'p_group_id': groupId,
        'p_uid': uid,
        'p_mood': _jsonSafe(mood),
      }).timeout(const Duration(seconds: 10));
    });
  }

  Future<bool> clearMemberMood(String groupId, String uid) async {
    if (!isReady || groupId.isEmpty || uid.isEmpty) return false;
    return _write('clearMemberMood', () async {
      await _client.rpc('group_clear_member_mood', params: {
        'p_group_id': groupId,
        'p_uid': uid,
      }).timeout(const Duration(seconds: 10));
    });
  }

  Future<bool> setMemberName(String groupId, String uid, String name) async {
    if (!isReady || groupId.isEmpty || uid.isEmpty) return false;
    return _write('setMemberName', () async {
      await _client.rpc('group_set_member_name', params: {
        'p_group_id': groupId,
        'p_uid': uid,
        'p_name': name,
      }).timeout(const Duration(seconds: 10));
    });
  }

  Future<bool> setMemberAvatar(String groupId, String uid, String url) async {
    if (!isReady || groupId.isEmpty || uid.isEmpty) return false;
    return _write('setMemberAvatar', () async {
      await _client.rpc('group_set_member_avatar', params: {
        'p_group_id': groupId,
        'p_uid': uid,
        'p_url': url,
      }).timeout(const Duration(seconds: 10));
    });
  }

  /// null = убрать дату рождения участника.
  Future<bool> setMemberBirthday(
    String groupId,
    String uid,
    DateTime? date,
  ) async {
    if (!isReady || groupId.isEmpty || uid.isEmpty) return false;
    return _write('setMemberBirthday', () async {
      await _client.rpc('group_set_member_birthday', params: {
        'p_group_id': groupId,
        'p_uid': uid,
        'p_date': date?.toIso8601String(),
      }).timeout(const Duration(seconds: 10));
    });
  }

  /// Атомарный инкремент memories_count / drawings_count.
  Future<bool> incrementGroupCounters(
    String groupId, {
    int memories = 0,
    int drawings = 0,
  }) async {
    if (!isReady || groupId.isEmpty || (memories == 0 && drawings == 0)) {
      return false;
    }
    return _write('incrementGroupCounters', () async {
      await _client.rpc('group_inc_counters', params: {
        'p_group_id': groupId,
        'p_memories': memories,
        'p_drawings': drawings,
      }).timeout(const Duration(seconds: 10));
    });
  }

  /// Разовое чтение выбранных колонок группы (snake_case), или null если
  /// строки нет. Для read-modify-write редких списков (customStatuses,
  /// customRelationshipTypes, timers) и счётчиков статистики.
  Future<Map<String, dynamic>?> fetchGroupColumns(
    String groupId,
    List<String> columns,
  ) async {
    if (!isReady || groupId.isEmpty || columns.isEmpty) return null;
    try {
      final row = await _client
          .from('groups')
          .select(columns.join(', '))
          .eq('id', groupId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
      return row == null ? null : Map<String, dynamic>.from(row);
    } catch (e) {
      debugPrint('SupabaseService.fetchGroupColumns($groupId) failed: $e');
      return null;
    }
  }

  /// Серверные версии завершённого бэкфилла группы (data/media). null —
  /// ошибка чтения (вызывающий не должен трактовать как «не мигрировано»).
  /// Строки нет → (0, 0) = миграция не выполнялась.
  Future<({int dataVersion, int mediaVersion})?> fetchMigrationFlags(
    String groupId,
  ) async {
    if (!isReady || groupId.isEmpty) return null;
    try {
      final row = await _client
          .from('migration_flags')
          .select()
          .eq('group_id', groupId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
      return (
        dataVersion: (row?['data_version'] as num?)?.toInt() ?? 0,
        mediaVersion: (row?['media_version'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('SupabaseService.fetchMigrationFlags($groupId) failed: $e');
      return null;
    }
  }

  /// Помечает на сервере завершённый проход бэкфилла (data и/или media).
  Future<bool> markMigrationFlag(
    String groupId, {
    int? dataVersion,
    int? mediaVersion,
  }) async {
    if (!isReady || groupId.isEmpty) return false;
    final row = <String, dynamic>{
      'group_id': groupId,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (dataVersion != null) row['data_version'] = dataVersion;
    if (mediaVersion != null) row['media_version'] = mediaVersion;
    return _write('markMigrationFlag', () async {
      await _client
          .from('migration_flags')
          .upsert(row, onConflict: 'group_id')
          .timeout(const Duration(seconds: 10));
    });
  }

  /// Live-поток activeSession группы (или null) — замена activeSessionStream,
  /// который под `_mig` больше не может опираться на Firestore group-doc.
  Stream<Map<String, dynamic>?> watchActiveSession(String groupId) {
    if (!isReady || groupId.isEmpty) return const Stream.empty();
    try {
      return _client
          .from('groups')
          .stream(primaryKey: ['id'])
          .eq('id', groupId)
          .map((rows) {
        if (rows.isEmpty) return null;
        final raw = rows.first['active_session'];
        return raw is Map ? Map<String, dynamic>.from(raw) : null;
      });
    } catch (e) {
      debugPrint('SupabaseService.watchActiveSession failed: $e');
      return const Stream.empty();
    }
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
  Future<bool> mirrorMoodEntry(
    String groupId,
    String uid,
    Map<String, dynamic> entry,
  ) async {
    if (!isReady) return false;
    final id = entry['id'] as String?;
    if (id == null) return false;
    return _write('mirrorMoodEntry', () async {
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
    });
  }

  Future<bool> mirrorMoodDelete(String entryId) async {
    if (!isReady) return false;
    return _write('mirrorMoodDelete', () async {
      await _client
          .from('mood_entries')
          .delete()
          .eq('id', entryId)
          .timeout(const Duration(seconds: 10));
    });
  }

  // ══════════════════════════════════════════════
  //  MEMORIES (dual-write + чтение из Supabase)
  // ══════════════════════════════════════════════

  /// Live-лента воспоминаний группы (последние [limit], новые сверху).
  /// Замена listenToMemories при чтении из Supabase. Soft-deleted (deleted=true)
  /// отфильтровываются. Формат — модель Memory, как у Firestore-пути.
  Stream<List<Memory>> watchMemories(String groupId, {int limit = 20}) {
    if (!isReady || groupId.isEmpty) return const Stream.empty();
    try {
      return _client
          .from('memories')
          .stream(primaryKey: ['id'])
          .eq('group_id', groupId)
          .order('created_at', ascending: false)
          .limit(limit)
          .map((rows) => rows
              .where((r) => r['deleted'] != true)
              .map(_memoryFromRow)
              .toList());
    } catch (e) {
      debugPrint('SupabaseService.watchMemories failed: $e');
      return const Stream.empty();
    }
  }

  /// Разовая загрузка ленты с пагинацией по времени. [beforeIso] — вернуть
  /// только воспоминания старше этой метки (created_at < beforeIso). Замена
  /// loadMemories: вместо Firestore-курсора используем created_at как курсор.
  Future<List<Memory>> loadMemories(
    String groupId, {
    int limit = 50,
    String? beforeIso,
  }) async {
    if (!isReady || groupId.isEmpty) return const [];
    try {
      var q = _client
          .from('memories')
          .select()
          .eq('group_id', groupId)
          .eq('deleted', false);
      if (beforeIso != null) q = q.lt('created_at', beforeIso);
      final rows = await q
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(const Duration(seconds: 15));
      return rows.map(_memoryFromRow).toList();
    } catch (e) {
      debugPrint('SupabaseService.loadMemories failed: $e');
      return const [];
    }
  }

  /// Строка таблицы memories → модель Memory. data JSONB хранит toFirestore-карту
  /// с ISO-строками; Memory.fromFirestore ждёт Timestamp для createdAt/editedAt.
  Memory _memoryFromRow(Map<String, dynamic> row) {
    final raw = row['data'];
    final data = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    data['createdAt'] =
        _toTs(data['createdAt']) ?? _toTs(row['created_at']) ?? Timestamp.now();
    final edited = _toTs(data['editedAt']) ?? _toTs(row['edited_at']);
    if (edited != null) {
      data['editedAt'] = edited;
    } else {
      data.remove('editedAt');
    }
    return Memory.fromFirestore((row['id'] ?? '').toString(), data);
  }

  /// Двойная запись воспоминания. [data] — полный firestore-map воспоминания.
  Future<bool> mirrorMemory(
    String groupId,
    String id,
    Map<String, dynamic> data,
  ) async {
    if (!isReady || id.isEmpty) return false;
    return _write('mirrorMemory', () async {
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
    });
  }

  /// Частичное обновление зеркала воспоминания (известные колонки).
  /// [fb] — те же camelCase-ключи, что updateMemory пишет в Firestore.
  Future<bool> mirrorMemoryPatch(String id, Map<String, dynamic> fb) async {
    if (!isReady || id.isEmpty) return false;
    final cols = <String, dynamic>{};
    if (fb.containsKey('isPinned')) cols['is_pinned'] = fb['isPinned'];
    if (fb.containsKey('editedAt')) cols['edited_at'] = _isoTs(fb['editedAt']);
    if (fb.containsKey('createdAt')) cols['created_at'] = _isoTs(fb['createdAt']);
    if (cols.isEmpty) return true; // нечего обновлять — не ошибка
    return _write('mirrorMemoryPatch', () async {
      await _client
          .from('memories')
          .update(cols)
          .eq('id', id)
          .timeout(const Duration(seconds: 10));
    });
  }

  /// Этап 4: частичная правка воспоминания как ПЕРВИЧНАЯ запись (RPC
  /// memory_patch: data || patch атомарно + синк типизированных колонок).
  /// [fb] — те же camelCase-ключи, что updateMemory писал в Firestore;
  /// Timestamp'ы конвертируются в ISO.
  Future<bool> patchMemory(String id, Map<String, dynamic> fb) async {
    if (!isReady || id.isEmpty) return false;
    if (fb.isEmpty) return true;
    return _write('patchMemory', () async {
      await _client.rpc('memory_patch', params: {
        'p_id': id,
        'p_patch': _jsonSafe(fb),
      }).timeout(const Duration(seconds: 10));
    });
  }

  /// Разовое чтение одного воспоминания (пин из чата не на первой странице).
  Future<Memory?> loadMemoryById(String memoryId) async {
    if (!isReady || memoryId.isEmpty) return null;
    try {
      final row = await _client
          .from('memories')
          .select()
          .eq('id', memoryId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
      if (row == null || row['deleted'] == true) return null;
      return _memoryFromRow(row);
    } catch (e) {
      debugPrint('SupabaseService.loadMemoryById($memoryId) failed: $e');
      return null;
    }
  }

  Future<bool> mirrorMemoryDelete(String id, {bool hard = false}) async {
    if (!isReady || id.isEmpty) return false;
    return _write('mirrorMemoryDelete', () async {
      if (hard) {
        await _client
            .from('memories')
            .delete()
            .eq('id', id)
            .timeout(const Duration(seconds: 10));
      } else {
        await _client
            .from('memories')
            .update({'deleted': true})
            .eq('id', id)
            .timeout(const Duration(seconds: 10));
      }
    });
  }

  // ══════════════════════════════════════════════
  //  COMMENTS (dual-write + чтение из Supabase)
  // ══════════════════════════════════════════════

  /// Двойная запись комментария к воспоминанию. [data] — toFirestore-карта.
  Future<bool> mirrorComment(
    String groupId,
    String memoryId,
    String id,
    Map<String, dynamic> data,
  ) async {
    if (!isReady || id.isEmpty) return false;
    return _write('mirrorComment', () async {
      await _client.from('memory_comments').upsert({
        'id': id,
        'group_id': groupId,
        'memory_id': memoryId,
        'author_uid': data['authorUid'],
        'author_name': data['authorName'],
        'author_avatar': data['authorAvatar'],
        'text': data['text'],
        'created_at': _isoTs(data['createdAt']) ??
            DateTime.now().toIso8601String(),
      }, onConflict: 'id').timeout(const Duration(seconds: 10));
    });
  }

  Future<bool> mirrorCommentDelete(String id) async {
    if (!isReady || id.isEmpty) return false;
    return _write('mirrorCommentDelete', () async {
      await _client
          .from('memory_comments')
          .delete()
          .eq('id', id)
          .timeout(const Duration(seconds: 10));
    });
  }

  /// Live-поток комментариев воспоминания (старые сверху, как Firestore-путь).
  Stream<List<MemoryComment>> watchComments(String groupId, String memoryId) {
    if (!isReady || groupId.isEmpty || memoryId.isEmpty) {
      return const Stream.empty();
    }
    try {
      return _client
          .from('memory_comments')
          .stream(primaryKey: ['id'])
          .eq('memory_id', memoryId)
          .order('created_at', ascending: true)
          .map((rows) => rows
              .where((r) => r['deleted'] != true)
              .map((r) => MemoryComment.fromFirestore((r['id'] ?? '').toString(), {
                    'authorUid': r['author_uid'],
                    'authorName': r['author_name'],
                    'authorAvatar': r['author_avatar'],
                    'text': r['text'],
                    'createdAt': _toTs(r['created_at']),
                  }))
              .toList());
    } catch (e) {
      debugPrint('SupabaseService.watchComments failed: $e');
      return const Stream.empty();
    }
  }

  /// Разовая загрузка всех комментариев воспоминания (для бэкфилла подсчёта/проверок).
  Future<List<Map<String, dynamic>>> fetchComments(String memoryId) async {
    if (!isReady || memoryId.isEmpty) return const [];
    try {
      final rows = await _client
          .from('memory_comments')
          .select('id')
          .eq('memory_id', memoryId)
          .timeout(const Duration(seconds: 10));
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('SupabaseService.fetchComments failed: $e');
      return const [];
    }
  }

  // ══════════════════════════════════════════════
  //  CANVAS (холсты/рисунки: dual-write + чтение)
  // ══════════════════════════════════════════════

  /// Двойная запись завершённого штриха. [data] — toFirestore-карта штриха.
  Future<bool> mirrorStroke(
    String groupId,
    String canvasId,
    String id,
    Map<String, dynamic> data,
  ) async {
    if (!isReady || id.isEmpty) return false;
    return _write('mirrorStroke', () async {
      await _client.from('canvas_strokes').upsert({
        'id': id,
        'group_id': groupId,
        'canvas_id': canvasId,
        'order_index': (data['orderIndex'] as num?)?.toInt() ?? 0,
        'data': _jsonSafe(data),
      }, onConflict: 'id').timeout(const Duration(seconds: 10));
    });
  }

  /// Патч полей штриха (перетаскивание картинки, замена URL) через RPC —
  /// data || updates атомарно, без read-modify-write.
  Future<bool> mirrorStrokePatch(String id, Map<String, dynamic> updates) async {
    if (!isReady || id.isEmpty) return false;
    return _write('mirrorStrokePatch', () async {
      await _client.rpc('canvas_stroke_patch', params: {
        'p_id': id,
        'p_patch': _jsonSafe(updates),
      }).timeout(const Duration(seconds: 10));
    });
  }

  Future<bool> mirrorStrokeDelete(String id) async {
    if (!isReady || id.isEmpty) return false;
    return _write('mirrorStrokeDelete', () async {
      await _client
          .from('canvas_strokes')
          .delete()
          .eq('id', id)
          .timeout(const Duration(seconds: 10));
    });
  }

  /// Очистка холста: удаляем все штрихи канваса + проставляем clear_version
  /// (и опционально bg_color) в canvas_meta.
  Future<bool> mirrorCanvasClear(
    String groupId,
    String canvasId,
    int version, {
    int? bgColor,
  }) async {
    if (!isReady || groupId.isEmpty) return false;
    return _write('mirrorCanvasClear', () async {
      await _client
          .from('canvas_strokes')
          .delete()
          .eq('group_id', groupId)
          .eq('canvas_id', canvasId)
          .timeout(const Duration(seconds: 10));
      final row = <String, dynamic>{
        'group_id': groupId,
        'canvas_id': canvasId,
        'clear_version': version,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (bgColor != null) row['bg_color'] = bgColor;
      await _client
          .from('canvas_meta')
          .upsert(row, onConflict: 'group_id,canvas_id')
          .timeout(const Duration(seconds: 10));
    });
  }

  /// Запись мета-полей холста (фон/поворот/версия очистки) — только переданные.
  Future<bool> mirrorCanvasMeta(
    String groupId,
    String canvasId, {
    int? bgColor,
    int? rotation,
    int? clearVersion,
  }) async {
    if (!isReady || groupId.isEmpty) return false;
    final row = <String, dynamic>{
      'group_id': groupId,
      'canvas_id': canvasId,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (bgColor != null) row['bg_color'] = bgColor;
    if (rotation != null) row['canvas_rotation'] = rotation;
    if (clearVersion != null) row['clear_version'] = clearVersion;
    return _write('mirrorCanvasMeta', () async {
      await _client
          .from('canvas_meta')
          .upsert(row, onConflict: 'group_id,canvas_id')
          .timeout(const Duration(seconds: 10));
    });
  }

  /// Двойная запись записи каталога холстов. [data] — id/name/createdAt/updatedAt/createdBy.
  Future<bool> mirrorCanvasCatalogue(
    String groupId,
    String canvasId,
    Map<String, dynamic> data,
  ) async {
    if (!isReady || groupId.isEmpty || canvasId.isEmpty) return false;
    final row = <String, dynamic>{'group_id': groupId, 'canvas_id': canvasId};
    if (data.containsKey('name')) row['name'] = data['name'];
    if (data.containsKey('createdAt')) row['created_at'] = data['createdAt'];
    if (data.containsKey('updatedAt')) row['updated_at'] = data['updatedAt'];
    if (data.containsKey('createdBy')) row['created_by'] = data['createdBy'];
    return _write('mirrorCanvasCatalogue', () async {
      await _client
          .from('canvas_catalogue')
          .upsert(row, onConflict: 'group_id,canvas_id')
          .timeout(const Duration(seconds: 10));
    });
  }

  Future<bool> mirrorCanvasCatalogueDelete(
    String groupId,
    String canvasId,
  ) async {
    if (!isReady || groupId.isEmpty || canvasId.isEmpty) return false;
    return _write('mirrorCanvasCatalogueDelete', () async {
      await _client
          .from('canvas_catalogue')
          .delete()
          .eq('group_id', groupId)
          .eq('canvas_id', canvasId)
          .timeout(const Duration(seconds: 10));
    });
  }

  /// Live-поток штрихов холста (по order_index). Каждый элемент — {id, data}.
  /// FirebaseService оборачивает в _DrawStrokeRaw.
  Stream<List<Map<String, dynamic>>> watchCanvasStrokes(
    String groupId,
    String canvasId,
  ) {
    if (!isReady || groupId.isEmpty) return const Stream.empty();
    try {
      return _client
          .from('canvas_strokes')
          .stream(primaryKey: ['id'])
          .eq('gc', '$groupId:$canvasId')
          .order('order_index', ascending: true)
          .map((rows) => rows.where((r) => r['deleted'] != true).map((r) {
                final d = r['data'];
                return {
                  'id': (r['id'] ?? '').toString(),
                  'data': d is Map
                      ? Map<String, dynamic>.from(d)
                      : <String, dynamic>{},
                };
              }).toList());
    } catch (e) {
      debugPrint('SupabaseService.watchCanvasStrokes failed: $e');
      return const Stream.empty();
    }
  }

  /// Live-поток мета холста — {bgColor, clearVersion, rotation} (int?).
  Stream<Map<String, int?>> watchCanvasMeta(String groupId, String canvasId) {
    if (!isReady || groupId.isEmpty) return const Stream.empty();
    try {
      return _client
          .from('canvas_meta')
          .stream(primaryKey: ['group_id', 'canvas_id'])
          .eq('gc', '$groupId:$canvasId')
          .map((rows) {
        if (rows.isEmpty) {
          return {'bgColor': null, 'clearVersion': null, 'rotation': null};
        }
        final r = rows.first;
        return {
          'bgColor': (r['bg_color'] as num?)?.toInt(),
          'clearVersion': (r['clear_version'] as num?)?.toInt(),
          'rotation': (r['canvas_rotation'] as num?)?.toInt(),
        };
      });
    } catch (e) {
      debugPrint('SupabaseService.watchCanvasMeta failed: $e');
      return const Stream.empty();
    }
  }

  /// Live-поток каталога холстов группы (формат как у Firestore-пути).
  Stream<List<Map<String, dynamic>>> watchCanvasCatalogue(String groupId) {
    if (!isReady || groupId.isEmpty) return const Stream.empty();
    try {
      return _client
          .from('canvas_catalogue')
          .stream(primaryKey: ['group_id', 'canvas_id'])
          .eq('group_id', groupId)
          .map((rows) => rows.map((r) => <String, dynamic>{
                'id': r['canvas_id'],
                'name': r['name'],
                'createdAt': r['created_at'],
                'updatedAt': r['updated_at'],
                if (r['created_by'] != null) 'createdBy': r['created_by'],
              }).toList());
    } catch (e) {
      debugPrint('SupabaseService.watchCanvasCatalogue failed: $e');
      return const Stream.empty();
    }
  }

  // ══════════════════════════════════════════════
  //  МАСКОТЫ (галерея + floating + streak)
  // ══════════════════════════════════════════════

  /// Mascot.toFirestore() → строка таблицы mascots (snake_case + ISO даты).
  Map<String, dynamic> _mascotRow(String groupId, Map<String, dynamic> m) => {
        'group_id': groupId,
        'id': m['id'],
        'name': m['name'],
        'image_url': m['imageUrl'],
        'default_asset': m['defaultAsset'],
        'created_by': m['createdBy'],
        'created_at': _isoTs(m['createdAt']),
        'is_default': m['isDefault'] ?? false,
        'record_streak': m['recordStreak'] ?? 0,
      };

  Mascot _mascotFromRow(Map<String, dynamic> r) => Mascot(
        id: (r['id'] ?? '').toString(),
        name: (r['name'] ?? '').toString(),
        imageUrl: r['image_url'] as String?,
        defaultAsset: r['default_asset'] as String?,
        createdBy: (r['created_by'] ?? '').toString(),
        createdAt: _toDate(r['created_at']) ?? DateTime.now(),
        isDefault: r['is_default'] == true,
        recordStreak: (r['record_streak'] as num?)?.toInt() ?? 0,
      );

  /// Зеркалит один маскот (вставка/перезапись по PK group_id+id).
  Future<bool> mirrorMascot(String groupId, Map<String, dynamic> m) async {
    if (!isReady || groupId.isEmpty) return false;
    return _write('mirrorMascot', () async {
      await _client
          .from('mascots')
          .upsert(_mascotRow(groupId, m), onConflict: 'group_id,id')
          .timeout(const Duration(seconds: 10));
    });
  }

  /// Зеркалит несколько маскотов одним upsert (сидирование дефолтов / бэкфилл).
  Future<bool> mirrorMascotsBatch(
    String groupId,
    List<Map<String, dynamic>> mascots,
  ) async {
    if (!isReady || groupId.isEmpty || mascots.isEmpty) return false;
    return _write('mirrorMascotsBatch', () async {
      await _client
          .from('mascots')
          .upsert(
            mascots.map((m) => _mascotRow(groupId, m)).toList(),
            onConflict: 'group_id,id',
          )
          .timeout(const Duration(seconds: 10));
    });
  }

  Future<bool> deleteMascotRow(String groupId, String mascotId) async {
    if (!isReady || groupId.isEmpty || mascotId.isEmpty) return false;
    return _write('deleteMascotRow', () async {
      await _client
          .from('mascots')
          .delete()
          .eq('group_id', groupId)
          .eq('id', mascotId)
          .timeout(const Duration(seconds: 10));
    });
  }

  Future<bool> renameMascot(
    String groupId,
    String mascotId,
    String name,
  ) async {
    if (!isReady || groupId.isEmpty || mascotId.isEmpty) return false;
    return _write('renameMascot', () async {
      await _client
          .from('mascots')
          .update({'name': name})
          .eq('group_id', groupId)
          .eq('id', mascotId)
          .timeout(const Duration(seconds: 10));
    });
  }

  Future<bool> updateMascotRecord(
    String groupId,
    String mascotId,
    int recordStreak,
  ) async {
    if (!isReady || groupId.isEmpty || mascotId.isEmpty) return false;
    return _write('updateMascotRecord', () async {
      await _client
          .from('mascots')
          .update({'record_streak': recordStreak})
          .eq('group_id', groupId)
          .eq('id', mascotId)
          .timeout(const Duration(seconds: 10));
    });
  }

  /// Live-поток галереи маскотов (realtime). Дефолты первыми, затем по дате —
  /// тот же порядок, что отдаёт FirebaseService.listenToMascots.
  Stream<List<Mascot>> watchMascots(String groupId) {
    if (!isReady || groupId.isEmpty) return const Stream.empty();
    try {
      return _client
          .from('mascots')
          .stream(primaryKey: ['group_id', 'id'])
          .eq('group_id', groupId)
          .map((rows) => rows
              .map(_mascotFromRow)
              .where((m) => m.id.isNotEmpty)
              .toList()
            ..sort((a, b) {
              if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
              return a.createdAt.compareTo(b.createdAt);
            }));
    } catch (e) {
      debugPrint('SupabaseService.watchMascots failed: $e');
      return const Stream.empty();
    }
  }

  Future<int> getMascotCount(String groupId) async {
    if (!isReady || groupId.isEmpty) return 0;
    try {
      final rows = await _client
          .from('mascots')
          .select('id')
          .eq('group_id', groupId)
          .timeout(const Duration(seconds: 10));
      return rows.length;
    } catch (e) {
      debugPrint('SupabaseService.getMascotCount failed: $e');
      return 0;
    }
  }

  /// Live-поток floating-маскота + streak из group-row → GroupMascotState
  /// (замена listenToGroupMascotState при чтении из Supabase). Де-дуп по
  /// сигнатуре, чтобы не дёргать виджет на не-маскотных апдейтах группы.
  Stream<GroupMascotState> watchGroupMascotState(String groupId) {
    if (!isReady || groupId.isEmpty) return const Stream.empty();
    try {
      String? prevSig;
      return _client
          .from('groups')
          .stream(primaryKey: ['id'])
          .eq('id', groupId)
          .map((rows) {
            if (rows.isEmpty) return const GroupMascotState();
            final r = rows.first;
            return GroupMascotState(
              activeMascotId: r['active_mascot_id'] as String?,
              positionX: (r['mascot_position_x'] as num?)?.toDouble() ?? 0.8,
              positionY: (r['mascot_position_y'] as num?)?.toDouble() ?? 0.7,
              scale: (r['mascot_scale'] as num?)?.toDouble() ?? 1.0,
              streakDays: (r['streak_days'] as num?)?.toInt() ?? 0,
              streakLastOpenedDate: r['streak_last_opened_date'] as String?,
            );
          })
          .where((state) {
            final sig =
                '${state.activeMascotId}|${state.positionX}|${state.positionY}|'
                '${state.scale}|${state.streakDays}|${state.streakLastOpenedDate}';
            if (sig == prevSig) return false;
            prevSig = sig;
            return true;
          });
    } catch (e) {
      debugPrint('SupabaseService.watchGroupMascotState failed: $e');
      return const Stream.empty();
    }
  }

  /// Атомарный учёт ежедневной активности (streak). today = 'YYYY-MM-DD'.
  Future<bool> recordGroupActivity(String groupId, String today) async {
    if (!isReady || groupId.isEmpty) return false;
    return _write('recordGroupActivity', () async {
      await _client.rpc('group_record_activity', params: {
        'p_group_id': groupId,
        'p_today': today,
      }).timeout(const Duration(seconds: 10));
    });
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
      // У miss_you составной первичный ключ (group_id+user_uid) — .stream() с
      // ним ненадёжен (счётчик не обновлялся). Используем realtime-канал +
      // пере-чтение через getMissYouCounts: PK-агностично и стабильно.
      // Имя канала УНИКАЛЬНО на подписку: одну группу могут слушать сразу
      // несколько виджетов (total + per-user), а одинаковый topic конфликтует.
      getMissYouCounts(groupId).then(onData);
      final channel =
          _client.channel('miss_you_${groupId}_${_channelSeq++}');
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'miss_you',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'group_id',
              value: groupId,
            ),
            callback: (_) => getMissYouCounts(groupId).then(onData),
          )
          .subscribe();
      // StreamController как «ручка» отписки: на cancel убираем канал.
      final controller = StreamController<void>();
      controller.onCancel = () => _client.removeChannel(channel);
      return controller.stream.listen((_) {});
    } catch (e) {
      debugPrint('SupabaseService.listenMissYouCounts failed: $e');
      return null;
    }
  }

  Future<bool> mirrorMissYouIncrement(String groupId, String uid) async {
    if (!isReady) return false;
    return _write('mirrorMissYouIncrement', () async {
      await _client.rpc('increment_miss_you', params: {
        'p_group_id': groupId,
        'p_user_uid': uid,
      }).timeout(const Duration(seconds: 10));
    });
  }

  /// Синхронизация ПОЛНОГО набора счётчиков из RTDB в Supabase.
  ///
  /// [forceOverwrite] = true: RTDB всегда побеждает (одноразовый repair после
  /// рассинхрона). false (по умолчанию): берёт max(существующее, RTDB), чтобы
  /// не откатить живой счётчик при обычном сидировании.
  Future<bool> mirrorMissYouCountsFull(
    String groupId,
    Map<String, int> counts, {
    bool forceOverwrite = false,
  }) async {
    if (!isReady || counts.isEmpty) return false;
    final rows = <Map<String, dynamic>>[];
    if (forceOverwrite) {
      counts.forEach((uid, rtdbVal) {
        rows.add({
          'group_id': groupId,
          'user_uid': uid,
          'count': rtdbVal,
          'updated_at': DateTime.now().toIso8601String(),
        });
      });
    } else {
      // Не понижаем существующие значения (защита от race с live-тапом).
      final existing = await getMissYouCounts(groupId);
      counts.forEach((uid, rtdbVal) {
        final cur = existing[uid] ?? 0;
        rows.add({
          'group_id': groupId,
          'user_uid': uid,
          'count': rtdbVal > cur ? rtdbVal : cur,
          'updated_at': DateTime.now().toIso8601String(),
        });
      });
    }
    if (rows.isEmpty) return true;
    return _write('mirrorMissYouCountsFull', () async {
      await _client
          .from('miss_you')
          .upsert(rows, onConflict: 'group_id,user_uid')
          .timeout(const Duration(seconds: 10));
    });
  }

  Future<bool> mirrorMissYouReset(String groupId, String uid) async {
    if (!isReady) return false;
    return _write('mirrorMissYouReset', () async {
      await _client.from('miss_you').upsert({
        'group_id': groupId,
        'user_uid': uid,
        'count': 0,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'group_id,user_uid').timeout(const Duration(seconds: 10));
    });
  }

  // ══════════════════════════════════════════════
  //  WIDGET DATA (dual-write; чтение пока из Firebase)
  // ══════════════════════════════════════════════

  Future<bool> mirrorWidgetData(
    String groupId,
    String uid,
    Map<String, dynamic> fields,
  ) async {
    if (!isReady || groupId.isEmpty) return false;
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
      // Фото-поля парного виджета. Отдельные колонки (а не `data` JSONB),
      // т.к. upsert накапливает их между частичными апдейтами — иначе чтение
      // потеряло бы их при следующем patch'е статуса/настроения. Списки идут
      // в JSONB-колонки, photoGridCount — в INT.
      'photoForPartnerUrl': 'photo_for_partner_url',
      'photoForPartnerUrls': 'photo_for_partner_urls',
      'photoGridCount': 'photo_grid_count',
      'photoGridUrls': 'photo_grid_urls',
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
    return _write('mirrorWidgetData', () async {
      await _client
          .from('widget_data')
          .upsert(row, onConflict: 'group_id,user_uid')
          .timeout(const Duration(seconds: 10));
    });
  }

  /// Конвертирует строку widget_data (типизированные колонки) в карту
  /// firestore-формата — те же ключи, что отдаёт WidgetData.toFirestore /
  /// читает WidgetData.fromFirestore. Источник правды — КОЛОНКИ (а не `data`
  /// JSONB, который хранит лишь последний частичный патч).
  Map<String, dynamic> _widgetRowToFirestore(Map<String, dynamic> row) {
    List<String> strList(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : const <String>[];
    return {
      'uid': row['user_uid'] ?? '',
      'displayName': row['display_name'] ?? '',
      'avatarUrl': row['avatar_url'] ?? '',
      'gender': row['gender'] ?? '',
      'status': row['status'] ?? '',
      'moodEmoji': row['mood_emoji'] ?? '',
      'moodLabel': row['mood_label'] ?? '',
      'message': row['message'] ?? '',
      'photoUrl': row['photo_url'],
      'photoForPartnerUrl': row['photo_for_partner_url'],
      'photoForPartnerUrls': strList(row['photo_for_partner_urls']),
      'photoGridCount': (row['photo_grid_count'] as num?)?.toInt() ?? 1,
      'photoGridUrls': strList(row['photo_grid_urls']),
      'musicTitle': row['music_title'],
      'musicArtist': row['music_artist'],
      'musicUrl': row['music_url'],
      'musicCoverUrl': row['music_cover_url'],
      'updatedAt': _toTs(row['updated_at']),
    };
  }

  /// Разовое чтение widget_data одного участника (firestore-формат) или null.
  Future<Map<String, dynamic>?> loadWidgetData(
    String groupId,
    String userUid,
  ) async {
    if (!isReady || groupId.isEmpty || userUid.isEmpty) return null;
    try {
      final row = await _client
          .from('widget_data')
          .select()
          .eq('group_id', groupId)
          .eq('user_uid', userUid)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
      if (row == null) return null;
      return _widgetRowToFirestore(row);
    } catch (e) {
      debugPrint('SupabaseService.loadWidgetData($groupId/$userUid) failed: $e');
      return null;
    }
  }

  /// Live-подписка на widget_data одного участника. [onData] получает карту
  /// firestore-формата (как snapshot widgetData) или null, если строки нет —
  /// чтобы вызывающий код мог запустить fallback/bootstrap как и раньше.
  /// Realtime .stream() допускает один .eq(), а PK составной (group_id,
  /// user_uid) → фильтруем по group_id и выбираем нужного user_uid в коде
  /// (в группе всего 2 участника, накладные расходы ничтожны).
  StreamSubscription? listenWidgetData(
    String groupId,
    String userUid,
    void Function(Map<String, dynamic>? data) onData,
  ) {
    if (!isReady || groupId.isEmpty || userUid.isEmpty) return null;
    try {
      return _client
          .from('widget_data')
          .stream(primaryKey: ['group_id', 'user_uid'])
          .eq('group_id', groupId)
          .listen((rows) {
        Map<String, dynamic>? mine;
        for (final r in rows) {
          if (r['user_uid'] == userUid) {
            mine = r;
            break;
          }
        }
        onData(mine == null ? null : _widgetRowToFirestore(mine));
      }, onError: (e) => debugPrint('listenWidgetData error: $e'));
    } catch (e) {
      debugPrint('SupabaseService.listenWidgetData failed: $e');
      return null;
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
  Future<bool> mirrorChatSend({
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
    if (!isReady) return false;
    return _write('mirrorChatSend', () async {
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
    });
  }

  /// Двойная запись правки/удаления/реакции сообщения.
  Future<bool> mirrorChatUpdate(String id, Map<String, dynamic> fields) async {
    if (!isReady || id.isEmpty) return false;
    return _write('mirrorChatUpdate', () async {
      await _client
          .from('chat_messages')
          .update(fields)
          .eq('id', id)
          .timeout(const Duration(seconds: 10));
    });
  }

  // ── Статусы прочтения (галочки «прочитано») ──────────────────

  /// Публикует ts последнего прочитанного сообщения текущего пользователя.
  /// Монотонность (только рост) гарантирует клиент (ChatService._syncedReadTs).
  Future<bool> mirrorChatRead(String groupId, String uid, int ts) async {
    if (!isReady || groupId.isEmpty || uid.isEmpty) return false;
    return _write('mirrorChatRead', () async {
      await _client.from('chat_reads').upsert({
        'group_id': groupId,
        'user_uid': uid,
        'last_read_ts': ts,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'group_id,user_uid').timeout(const Duration(seconds: 10));
    });
  }

  /// Live-поток статусов прочтения {uid: lastReadTs} (замена RTDB watchReads).
  Stream<Map<String, int>> watchChatReads(String groupId) {
    if (!isReady || groupId.isEmpty) return const Stream.empty();
    try {
      return _client
          .from('chat_reads')
          .stream(primaryKey: ['group_id', 'user_uid'])
          .eq('group_id', groupId)
          .map((rows) {
        final out = <String, int>{};
        for (final r in rows) {
          out[(r['user_uid'] ?? '').toString()] =
              (r['last_read_ts'] as num?)?.toInt() ?? 0;
        }
        return out;
      });
    } catch (e) {
      debugPrint('SupabaseService.watchChatReads failed: $e');
      return const Stream.empty();
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

  // ══════════════════════════════════════════════════════════════════════════════
  //  STORAGE — Supabase Storage вместо Firebase Storage (Фаза 1)
  //
  //  Схема URL:
  //    Приватные файлы → 'sb://media/{storagePath}'  (подписанный URL по запросу)
  //    Публичные (аватары) → прямой https:// из Supabase
  // ══════════════════════════════════════════════════════════════════════════════

  static const _sbScheme = 'sb://';
  static const _mediaBucket = 'media';
  static const _avatarsBucket = 'avatars';

  // Пути которые хранятся приватно (доступ только через Signed URL).
  // groups/ — маскоты и рисунки холста (групповой контент);
  // canvas/ — штрихи холста (старый путь без префикса groups/).
  static const _privatePathPrefixes = [
    'memories/',
    'music/',
    'timer_backgrounds/',
    'widget/',
    'groups/',
    'canvas/',
  ];

  bool _isPrivateStoragePath(String path) =>
      _privatePathPrefixes.any(path.startsWith);

  // Кэш подписанных URL (55 мин — бакет выдаёт на 60 мин).
  final Map<String, _SbSignedUrlEntry> _sbSignedUrlCache = {};

  /// Загрузить байты в Supabase Storage.
  /// Приватные пути → возвращает 'sb://media/{path}'.
  /// Публичный путь (avatars/) → возвращает прямой https://.
  Future<String?> uploadStorageFile(
    Uint8List bytes,
    String storagePath, {
    String? contentType,
  }) async {
    if (!isReady || bytes.isEmpty || storagePath.isEmpty) return null;
    try {
      final isPrivate = _isPrivateStoragePath(storagePath);
      final bucket = isPrivate ? _mediaBucket : _avatarsBucket;
      await _client.storage.from(bucket).uploadBinary(
        storagePath,
        bytes,
        fileOptions: FileOptions(
          contentType: contentType ?? 'application/octet-stream',
          upsert: true,
        ),
      );
      if (isPrivate) {
        return '$_sbScheme$bucket/$storagePath';
      } else {
        return _client.storage.from(bucket).getPublicUrl(storagePath);
      }
    } catch (e) {
      debugPrint('SupabaseService.uploadStorageFile($storagePath) failed: $e');
      return null;
    }
  }

  /// Преобразует 'sb://media/{path}' в подписанный https:// URL (60 мин TTL).
  /// Если передан https:// — возвращает как есть (обратная совместимость).
  Future<String?> getStorageSignedUrl(String sbRef) async {
    if (sbRef.isEmpty) return null;
    if (sbRef.startsWith('http')) return sbRef;
    if (!sbRef.startsWith(_sbScheme)) return null;

    final cached = _sbSignedUrlCache[sbRef];
    if (cached != null && cached.isValid) return cached.url;

    try {
      final withoutScheme = sbRef.substring(_sbScheme.length);
      final slashIdx = withoutScheme.indexOf('/');
      if (slashIdx == -1) return null;
      final bucket = withoutScheme.substring(0, slashIdx);
      final path = withoutScheme.substring(slashIdx + 1);

      final signedUrl = await _client.storage
          .from(bucket)
          .createSignedUrl(path, 3600);

      _sbSignedUrlCache[sbRef] = _SbSignedUrlEntry(
        signedUrl,
        DateTime.now().add(const Duration(minutes: 55)),
      );
      return signedUrl;
    } catch (e) {
      debugPrint('SupabaseService.getStorageSignedUrl($sbRef) failed: $e');
      return null;
    }
  }

  /// Удалить файл из Supabase Storage по ссылке 'sb://...'.
  Future<void> deleteStorageFile(String sbRef) async {
    if (!isReady || sbRef.isEmpty || !sbRef.startsWith(_sbScheme)) return;
    try {
      final withoutScheme = sbRef.substring(_sbScheme.length);
      final slashIdx = withoutScheme.indexOf('/');
      if (slashIdx == -1) return;
      final bucket = withoutScheme.substring(0, slashIdx);
      final path = withoutScheme.substring(slashIdx + 1);
      await _client.storage.from(bucket).remove([path]);
    } catch (e) {
      debugPrint('SupabaseService.deleteStorageFile($sbRef) failed: $e');
    }
  }

  /// Скачать файл по [httpUrl] и загрузить в Supabase Storage.
  /// Возвращает 'sb://' ссылку или null при ошибке.
  Future<String?> migrateFileFromHttpUrl(
    String httpUrl,
    String storagePath, {
    String? contentType,
  }) async {
    if (!isReady || httpUrl.isEmpty || storagePath.isEmpty) return null;
    try {
      final response = await http
          .get(Uri.parse(httpUrl))
          .timeout(const Duration(minutes: 3));
      if (response.statusCode != 200) {
        debugPrint(
          'migrateFileFromHttpUrl: HTTP ${response.statusCode} for $storagePath',
        );
        return null;
      }
      final ct = contentType ?? _contentTypeFromPath(storagePath);
      return uploadStorageFile(response.bodyBytes, storagePath, contentType: ct);
    } catch (e) {
      debugPrint('SupabaseService.migrateFileFromHttpUrl($storagePath) failed: $e');
      return null;
    }
  }

  String? _contentTypeFromPath(String path) {
    final lower = path.toLowerCase().split('?').first;
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.wav')) return 'audio/wav';
    return null;
  }

  // ── Вспомогательные методы для мигратора ────────────────────────────────────

  /// Загрузить все воспоминания группы (id + data + author_avatar).
  Future<List<Map<String, dynamic>>> fetchMemoriesForMigration(
    String groupId,
  ) async {
    if (!isReady || groupId.isEmpty) return [];
    try {
      final rows = await _client
          .from('memories')
          .select('id, data, author_avatar')
          .eq('group_id', groupId)
          .eq('deleted', false)
          .timeout(const Duration(seconds: 30));
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('SupabaseService.fetchMemoriesForMigration failed: $e');
      return [];
    }
  }

  /// Обновить data JSONB воспоминания (заменить Firebase URL → sb://).
  Future<bool> updateMemoryData(
    String memoryId,
    Map<String, dynamic> data, {
    String? authorAvatar,
  }) async {
    if (!isReady || memoryId.isEmpty) return false;
    final row = <String, dynamic>{'data': _jsonSafe(data)};
    if (authorAvatar != null) row['author_avatar'] = authorAvatar;
    return _write('updateMemoryData($memoryId)', () async {
      await _client
          .from('memories')
          .update(row)
          .eq('id', memoryId)
          .timeout(const Duration(seconds: 10));
    });
  }

  /// Загрузить groups.member_avatars для миграции аватарок.
  Future<Map<String, dynamic>?> fetchGroupForMigration(
    String groupId,
  ) async {
    if (!isReady || groupId.isEmpty) return null;
    try {
      final rows = await _client
          .from('groups')
          .select('id, member_avatars, mascots')
          .eq('id', groupId)
          .limit(1)
          .timeout(const Duration(seconds: 10));
      return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
    } catch (e) {
      debugPrint('SupabaseService.fetchGroupForMigration failed: $e');
      return null;
    }
  }

  /// Обновить массив mascots группы после миграции их картинок.
  Future<bool> updateGroupMascots(
    String groupId,
    List<dynamic> mascots,
  ) async {
    if (!isReady || groupId.isEmpty) return false;
    return _write('updateGroupMascots', () async {
      await _client
          .from('groups')
          .update({'mascots': _jsonSafe(mascots)})
          .eq('id', groupId)
          .timeout(const Duration(seconds: 10));
    });
  }

  /// Обновить member_avatars группы после миграции.
  Future<bool> updateGroupMemberAvatars(
    String groupId,
    Map<String, String> avatars,
  ) async {
    if (!isReady || groupId.isEmpty) return false;
    return _write('updateGroupMemberAvatars', () async {
      await _client
          .from('groups')
          .update({'member_avatars': _jsonSafe(avatars)})
          .eq('id', groupId)
          .timeout(const Duration(seconds: 10));
    });
  }

  /// Загрузить widget_data для миграции медиа-URL.
  Future<List<Map<String, dynamic>>> fetchWidgetDataForMigration(
    String groupId,
  ) async {
    if (!isReady || groupId.isEmpty) return [];
    try {
      final rows = await _client
          .from('widget_data')
          .select('user_uid, avatar_url, photo_url, music_url, music_cover_url')
          .eq('group_id', groupId)
          .timeout(const Duration(seconds: 10));
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('SupabaseService.fetchWidgetDataForMigration failed: $e');
      return [];
    }
  }

  /// Обновить URL-поля в widget_data после миграции.
  /// widget_data использует составной PK (group_id, user_uid) — нет колонки id.
  Future<bool> updateWidgetDataUrls(
    String groupId,
    String userUid,
    Map<String, String> urls,
  ) async {
    if (!isReady || groupId.isEmpty || userUid.isEmpty || urls.isEmpty) {
      return false;
    }
    return _write('updateWidgetDataUrls($groupId/$userUid)', () async {
      await _client
          .from('widget_data')
          .update(urls)
          .eq('group_id', groupId)
          .eq('user_uid', userUid)
          .timeout(const Duration(seconds: 10));
    });
  }
}
