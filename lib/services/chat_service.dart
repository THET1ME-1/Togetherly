import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_msg.dart';
import '../config/migration_config.dart';
import 'firebase_service.dart';
import 'supabase_service.dart';

/// URL базы Realtime Database (регион europe-west1 — не дефолтный).
const String _kChatRtdbUrl =
    'https://togetherly-d4856-default-rtdb.europe-west1.firebasedatabase.app';

/// Сервис постоянного текстового чата пары.
///
/// История сообщений хранится ТОЛЬКО в Realtime Database — это даёт ноль
/// Firestore-чтений независимо от числа сообщений и открытий чата. Firestore
/// используется лишь как разовый триггер push-уведомления (документ-событие,
/// который Cloud Function удаляет сразу после отправки FCM).
class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  final FirebaseService _fb = FirebaseService();
  final SupabaseService _sb = SupabaseService();

  /// Фаза 1: зеркалим чат в Supabase и читаем оттуда.
  bool get _mig =>
      MigrationConfig.isConfigured &&
      MigrationConfig.isPhase1User(_fb.currentUser?.email);

  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: _kChatRtdbUrl,
      );

  DatabaseReference _messagesRef(String groupId) =>
      _db.ref('chats/$groupId/messages');

  /// Узел статусов прочтения {uid: lastReadTs} — для галочек «прочитано».
  DatabaseReference _readsRef(String groupId) =>
      _db.ref('chats/$groupId/reads');

  String get _uid => _fb.uid ?? '';

  /// Регистрирует пользователя в members чата (нужно для security-rules:
  /// читать/писать может только участник). Вызывается при открытии чата и
  /// перед первой отправкой. Идемпотентно.
  Future<void> ensureMember(String groupId) async {
    if (groupId.isEmpty || _uid.isEmpty) return;
    try {
      await _db.ref('chats/$groupId/members/$_uid').set(true);
    } catch (e) {
      debugPrint('ChatService.ensureMember failed: $e');
    }
  }

  /// Поток последних [limit] сообщений, отсортированных по времени.
  Stream<List<ChatMsg>> watchMessages(String groupId, {int limit = 100}) {
    if (groupId.isEmpty) return const Stream.empty();
    // Фаза 1: читаем сообщения из Supabase (chat_messages).
    if (_mig) return _sb.watchMessages(groupId, limit: limit);
    return _messagesRef(groupId)
        .orderByChild('ts')
        .limitToLast(limit)
        .onValue
        .map((event) {
      final children = event.snapshot.children
          .map(ChatMsg.fromSnapshot)
          .toList()
        ..sort((a, b) => a.ts.compareTo(b.ts));
      return children;
    });
  }

  /// Отправить сообщение. [pinId]/[pinTitle] — опционально прикреплённый пин.
  Future<void> send({
    required String groupId,
    required String senderName,
    required String text,
    String? pinId,
    String? pinTitle,
    String? pinThumb,
  }) async {
    final trimmed = text.trim();
    if (groupId.isEmpty || _uid.isEmpty || trimmed.isEmpty) return;
    try {
      await ensureMember(groupId);
      final ref = _messagesRef(groupId).push();
      await ref.set({
        'uid': _uid,
        'name': senderName,
        'text': trimmed,
        'ts': ServerValue.timestamp,
        if (pinId != null) 'pinId': pinId,
        if (pinTitle != null) 'pinTitle': pinTitle,
        if (pinThumb != null) 'pinThumb': pinThumb,
      });
      // Двойная запись в Supabase. ts — клиентское now (RTDB ставит серверный,
      // в Supabase достаточно близкого порядкового значения для сортировки).
      if (_mig) {
        unawaited(_sb.mirrorChatSend(
          groupId: groupId,
          id: ref.key ?? DateTime.now().microsecondsSinceEpoch.toString(),
          uid: _uid,
          name: senderName,
          text: trimmed,
          ts: DateTime.now().millisecondsSinceEpoch,
          pinId: pinId,
          pinTitle: pinTitle,
          pinThumb: pinThumb,
        ));
      }
      // Триггер push-уведомления через Firestore-событие (его удаляет CF).
      unawaited(_fb.sendChatPush(
        groupId: groupId,
        senderName: senderName,
        text: trimmed,
      ));
    } catch (e) {
      debugPrint('ChatService.send failed: $e');
    }
  }

  /// Редактировать своё сообщение.
  Future<void> edit({
    required String groupId,
    required String messageId,
    required String newText,
  }) async {
    final trimmed = newText.trim();
    if (groupId.isEmpty || messageId.isEmpty || trimmed.isEmpty) return;
    try {
      await _messagesRef(groupId).child(messageId).update({
        'text': trimmed,
        'editedTs': ServerValue.timestamp,
      });
      if (_mig) {
        unawaited(_sb.mirrorChatUpdate(messageId, {
          'text': trimmed,
          'edited_ts': DateTime.now().millisecondsSinceEpoch,
        }));
      }
    } catch (e) {
      debugPrint('ChatService.edit failed: $e');
    }
  }

  /// Мягко удалить сообщение (томбстоун — партнёр видит «сообщение удалено»).
  Future<void> delete({
    required String groupId,
    required String messageId,
  }) async {
    if (groupId.isEmpty || messageId.isEmpty) return;
    try {
      await _messagesRef(groupId).child(messageId).update({
        'deleted': true,
        'text': '',
        'pinId': null,
        'pinTitle': null,
        'editedTs': ServerValue.timestamp,
      });
      if (_mig) {
        unawaited(_sb.mirrorChatUpdate(messageId, {
          'deleted': true,
          'text': '',
          'pin_id': null,
          'pin_title': null,
          'edited_ts': DateTime.now().millisecondsSinceEpoch,
        }));
      }
    } catch (e) {
      debugPrint('ChatService.delete failed: $e');
    }
  }

  /// Поставить/снять свою реакцию на сообщение. [emoji] == null убирает её.
  /// Один эмодзи на пользователя: новый перезаписывает прежний.
  /// Пишется в messages/{id}/reactions/{uid} — каскадно покрыто write-правилом
  /// чата (писать может только участник группы).
  Future<void> setReaction({
    required String groupId,
    required String messageId,
    required String? emoji,
  }) async {
    if (groupId.isEmpty || messageId.isEmpty || _uid.isEmpty) return;
    try {
      final reactionsRef =
          _messagesRef(groupId).child(messageId).child('reactions');
      final ref = reactionsRef.child(_uid);
      if (emoji == null || emoji.isEmpty) {
        await ref.remove();
      } else {
        await ref.set(emoji);
      }
      // Двойная запись: зеркалим полный набор реакций сообщения в Supabase
      // (читаем обратно из RTDB — это дёшево, не Firestore).
      if (_mig) {
        final snap = await reactionsRef.get();
        final map = <String, String>{};
        final v = snap.value;
        if (v is Map) {
          v.forEach((k, val) {
            if (val is String && val.isNotEmpty) map[k.toString()] = val;
          });
        }
        unawaited(_sb.mirrorChatUpdate(messageId, {'reactions': map}));
      }
    } catch (e) {
      debugPrint('ChatService.setReaction failed: $e');
    }
  }

  // ── Непрочитанные ──────────────────────────────────────────────────────────

  String _lastReadKey(String groupId) => 'chat_last_read_$groupId';

  // Кэш последнего опубликованного в RTDB ts прочтения по группам — markRead
  // зовётся на каждый кадр, поэтому пишем в сеть только при росте значения.
  final Map<String, int> _syncedReadTs = {};

  /// Отметить чат прочитанным: локально (ts последнего открытия) + публикуем
  /// в RTDB `chats/{groupId}/reads/{uid}`, чтобы партнёр увидел галочку.
  Future<void> markRead(String groupId, int lastMessageTs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastReadKey(groupId), lastMessageTs);

    if (groupId.isEmpty || _uid.isEmpty || lastMessageTs <= 0) return;
    if ((_syncedReadTs[groupId] ?? 0) >= lastMessageTs) return;
    _syncedReadTs[groupId] = lastMessageTs;
    try {
      await _readsRef(groupId).child(_uid).set(lastMessageTs);
    } catch (e) {
      _syncedReadTs.remove(groupId); // не вышло — позволим повторить позже
      debugPrint('ChatService.markRead publish failed: $e');
    }
  }

  /// Поток статусов прочтения {uid: lastReadTs}. Для галочек «прочитано»:
  /// своё сообщение прочитано, если его ts ≤ минимального ts среди остальных.
  Stream<Map<String, int>> watchReads(String groupId) {
    if (groupId.isEmpty) return const Stream.empty();
    return _readsRef(groupId).onValue.map((event) {
      final v = event.snapshot.value;
      if (v is! Map) return <String, int>{};
      final out = <String, int>{};
      v.forEach((k, val) => out[k.toString()] = (val as num?)?.toInt() ?? 0);
      return out;
    });
  }

  Future<int> _lastRead(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lastReadKey(groupId)) ?? 0;
  }

  /// ts последнего прочтения — публично, для разделителя «новые сообщения».
  Future<int> lastReadTs(String groupId) => _lastRead(groupId);

  // ── Фон чата (локальный, у каждого свой) ────────────────────────────────────

  String _bgKey(String groupId) => 'chat_bg_$groupId';

  /// Путь к локальному файлу фона чата (null — фон не задан).
  Future<String?> backgroundPath(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_bgKey(groupId));
  }

  Future<void> setBackgroundPath(String groupId, String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bgKey(groupId), path);
  }

  Future<void> clearBackground(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bgKey(groupId));
  }

  /// Поток: есть ли непрочитанные сообщения от партнёра (для красной точки).
  /// Слушает только последнее сообщение — минимальный трафик RTDB.
  Stream<bool> watchHasUnread(String groupId) {
    if (groupId.isEmpty) return Stream.value(false);
    return _messagesRef(groupId).orderByChild('ts').limitToLast(1).onValue.asyncMap(
      (event) async {
        if (event.snapshot.children.isEmpty) return false;
        final last = ChatMsg.fromSnapshot(event.snapshot.children.first);
        if (last.uid == _uid) return false; // своё сообщение
        if (last.deleted) return false;
        final lastRead = await _lastRead(groupId);
        return last.ts > lastRead;
      },
    );
  }
}
