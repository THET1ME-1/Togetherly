import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_msg.dart';
import 'firebase_service.dart';

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
      await _messagesRef(groupId).push().set({
        'uid': _uid,
        'name': senderName,
        'text': trimmed,
        'ts': ServerValue.timestamp,
        if (pinId != null) 'pinId': pinId,
        if (pinTitle != null) 'pinTitle': pinTitle,
        if (pinThumb != null) 'pinThumb': pinThumb,
      });
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
    } catch (e) {
      debugPrint('ChatService.delete failed: $e');
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
