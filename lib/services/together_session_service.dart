import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'firebase_service.dart';

/// URL базы Realtime Database (регион europe-west1 — не дефолтный, поэтому
/// указываем явно, иначе плагин ищет инстанс в us-central1).
const String _kRtdbUrl =
    'https://togetherly-d4856-default-rtdb.europe-west1.firebasedatabase.app';

/// Тип совместного занятия. Сейчас реализован только youtube; music/book
/// переиспользуют тот же канал синхронизации.
enum TogetherActivity { youtube, music, book }

extension TogetherActivityX on TogetherActivity {
  String get id => name;
  static TogetherActivity fromId(String? v) =>
      TogetherActivity.values.firstWhere(
        (a) => a.name == v,
        orElse: () => TogetherActivity.youtube,
      );
}

/// Эфемерное состояние совместного сеанса, живёт в RTDB
/// (liveSessions/{pairId}). К Firestore-чтениям отношения не имеет.
@immutable
class LiveSessionState {
  final TogetherActivity activity;
  final String mediaId; // youtube videoId (или ключ контента для music/book)
  final bool isPlaying;
  final int positionMs;
  final int lastActionAt; // server epoch ms (ServerValue.timestamp)
  final String controllerUid; // кто инициировал последнее действие
  final int seq; // монотонный номер действия для отбрасывания эха

  const LiveSessionState({
    required this.activity,
    required this.mediaId,
    required this.isPlaying,
    required this.positionMs,
    required this.lastActionAt,
    required this.controllerUid,
    required this.seq,
  });

  factory LiveSessionState.fromMap(Map<dynamic, dynamic> m) {
    return LiveSessionState(
      activity: TogetherActivityX.fromId(m['activity'] as String?),
      mediaId: (m['mediaId'] as String?) ?? '',
      isPlaying: (m['isPlaying'] as bool?) ?? false,
      positionMs: (m['positionMs'] as num?)?.toInt() ?? 0,
      lastActionAt: (m['lastActionAt'] as num?)?.toInt() ?? 0,
      controllerUid: (m['controllerUid'] as String?) ?? '',
      seq: (m['seq'] as num?)?.toInt() ?? 0,
    );
  }

  /// Ожидаемая позиция «сейчас» с поправкой на прошедшее время, когда играет.
  int expectedPositionMs(int nowMs) {
    if (!isPlaying) return positionMs;
    final elapsed = nowMs - lastActionAt;
    return positionMs + (elapsed > 0 ? elapsed : 0);
  }
}

/// Сообщение эфемерного чата сеанса (живёт в RTDB, исчезает с сессией).
@immutable
class ChatMessage {
  final String id;
  final String uid;
  final String name;
  final String text;
  final int ts;

  /// Реакции: uid → эмодзи (один на пользователя). Лежат в узле сообщения.
  final Map<String, String> reactions;

  /// Ответ на сообщение: id оригинала + снимок имени/текста.
  final String? replyToId;
  final String? replyToName;
  final String? replyToText;

  const ChatMessage({
    required this.id,
    required this.uid,
    required this.name,
    required this.text,
    required this.ts,
    this.reactions = const {},
    this.replyToId,
    this.replyToName,
    this.replyToText,
  });

  factory ChatMessage.fromSnapshot(DataSnapshot snap) {
    final m = (snap.value as Map?) ?? const {};
    final rawReactions = m['reactions'];
    final reactions = <String, String>{};
    if (rawReactions is Map) {
      rawReactions.forEach((k, v) {
        if (v is String && v.isNotEmpty) reactions[k.toString()] = v;
      });
    }
    return ChatMessage(
      id: snap.key ?? '',
      uid: (m['uid'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      text: (m['text'] as String?) ?? '',
      ts: (m['ts'] as num?)?.toInt() ?? 0,
      reactions: reactions,
      replyToId: m['replyToId'] as String?,
      replyToName: m['replyToName'] as String?,
      replyToText: m['replyToText'] as String?,
    );
  }
}

/// Сервис совместных занятий. Синхронизация плеера идёт ТОЛЬКО через RTDB —
/// ноль Firestore-чтений. Приглашение партнёра — через поле activeSession в
/// group-doc (его ловит уже работающий live-листенер) + опционально FCM.
class TogetherSessionService {
  TogetherSessionService._();
  static final TogetherSessionService instance = TogetherSessionService._();

  final FirebaseService _fb = FirebaseService();

  FirebaseDatabase get _db =>
      FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: _kRtdbUrl);

  DatabaseReference _sessionRef(String pairId) =>
      _db.ref('liveSessions/$pairId');

  String get _uid => _fb.uid ?? '';

  /// Локальный счётчик действий — растёт быстрее серверного seq, чтобы наши
  /// собственные апдейты, вернувшиеся через onValue, можно было отбросить.
  int _localSeq = 0;
  int get lastLocalSeq => _localSeq;

  /// Создать/перезапустить сеанс (вызывает хост). Сразу прописывает обоих
  /// участников в members, чтобы партнёр прошёл security-rules без задержки.
  Future<void> startSession({
    required String pairId,
    required String partnerUid,
    required TogetherActivity activity,
    required String mediaId,
  }) async {
    if (pairId.isEmpty || _uid.isEmpty) return;
    _localSeq = 0;
    final members = <String, bool>{_uid: true};
    if (partnerUid.isNotEmpty) members[partnerUid] = true;
    await _sessionRef(pairId).set({
      'members': members,
      'activity': activity.id,
      'mediaId': mediaId,
      'isPlaying': false,
      'positionMs': 0,
      'lastActionAt': ServerValue.timestamp,
      'controllerUid': _uid,
      'seq': 0,
    });
    // Презенс: убираем себя при разрыве соединения. Сам узел сеанса НЕ удаляем
    // на disconnect, чтобы случайный обрыв у одного не выкидывал второго.
    final presence = _sessionRef(pairId).child('presence').child(_uid);
    await presence.set(true);
    presence.onDisconnect().remove();
  }

  /// Регистрирует текущего пользователя в members сеанса — нужно для
  /// security-rules RTDB (читать/писать может только участник, как в чате пары).
  /// Каждый клиент пишет СВОЁ членство сам, а не полагается на хоста: иначе при
  /// правиле «$uid === auth.uid» на members запись партнёра хостом отклоняется,
  /// и у гостя молча не проходят ни презенс, ни сообщения. Идемпотентно.
  Future<void> ensureMember(String pairId) async {
    if (pairId.isEmpty || _uid.isEmpty) return;
    try {
      await _sessionRef(pairId).child('members').child(_uid).set(true);
    } catch (e) {
      debugPrint('TogetherSessionService.ensureMember failed: $e');
    }
  }

  /// Присоединиться (вызывает приглашённый партнёр) — отмечает презенс.
  Future<void> joinPresence(String pairId) async {
    if (pairId.isEmpty || _uid.isEmpty) return;
    await ensureMember(pairId);
    final presence = _sessionRef(pairId).child('presence').child(_uid);
    await presence.set(true);
    presence.onDisconnect().remove();
  }

  /// Поток присутствия: множество uid, кто сейчас в сеансе. Отдельный листенер
  /// на presence-узле, чтобы не путаться с подавлением эха в плеер-синке.
  Stream<Set<String>> watchPresence(String pairId) {
    return _sessionRef(pairId).child('presence').onValue.map((event) {
      final v = event.snapshot.value;
      if (v is! Map) return <String>{};
      return v.keys.map((k) => k.toString()).toSet();
    });
  }

  /// Поток состояния сеанса. null — сеанса нет (узел удалён).
  Stream<LiveSessionState?> watch(String pairId) {
    return _sessionRef(pairId).onValue.map((event) {
      final v = event.snapshot.value;
      if (v is! Map || v['mediaId'] == null) return null;
      return LiveSessionState.fromMap(v);
    });
  }

  /// Запушить действие (play/pause/seek/heartbeat). Возвращает использованный seq.
  Future<int> pushAction({
    required String pairId,
    required bool isPlaying,
    required int positionMs,
    String? mediaId,
  }) async {
    if (pairId.isEmpty || _uid.isEmpty) return _localSeq;
    _localSeq++;
    final seq = _localSeq;
    final update = <String, Object?>{
      'isPlaying': isPlaying,
      'positionMs': positionMs,
      'lastActionAt': ServerValue.timestamp,
      'controllerUid': _uid,
      'seq': seq,
    };
    if (mediaId != null) update['mediaId'] = mediaId;
    try {
      await _sessionRef(pairId).update(update);
    } catch (e) {
      debugPrint('TogetherSessionService.pushAction failed: $e');
    }
    return seq;
  }

  // ── Эфемерный чат сеанса (RTDB, 0 Firestore-чтений) ──────────────────────
  DatabaseReference _chatRef(String pairId) =>
      _sessionRef(pairId).child('chat');

  /// Отправить сообщение в чат сеанса. [replyTo*] — опциональный ответ.
  Future<void> sendChatMessage({
    required String pairId,
    required String text,
    String? replyToId,
    String? replyToName,
    String? replyToText,
  }) async {
    final t = text.trim();
    if (t.isEmpty || pairId.isEmpty || _uid.isEmpty) return;
    try {
      await ensureMember(pairId);
      await _chatRef(pairId).push().set({
        'uid': _uid,
        'name': _fb.displayName,
        'text': t,
        'ts': ServerValue.timestamp,
        if (replyToId != null) 'replyToId': replyToId,
        if (replyToName != null) 'replyToName': replyToName,
        if (replyToText != null) 'replyToText': replyToText,
      });
    } catch (e) {
      debugPrint('sendChatMessage failed: $e');
    }
  }

  /// Поставить/снять свою реакцию на сообщение. [emoji] == null убирает её.
  Future<void> setChatReaction({
    required String pairId,
    required String messageId,
    required String? emoji,
  }) async {
    if (pairId.isEmpty || messageId.isEmpty || _uid.isEmpty) return;
    try {
      final ref =
          _chatRef(pairId).child(messageId).child('reactions').child(_uid);
      if (emoji == null || emoji.isEmpty) {
        await ref.remove();
      } else {
        await ref.set(emoji);
      }
    } catch (e) {
      debugPrint('setChatReaction failed: $e');
    }
  }

  /// Поток сообщений чата: при подписке отдаёт последние ≤50, далее — новые.
  /// onChildAdded экономнее onValue (только дельты).
  Stream<ChatMessage> watchChatMessages(String pairId) {
    return _chatRef(pairId)
        .limitToLast(50)
        .onChildAdded
        .map((event) => ChatMessage.fromSnapshot(event.snapshot));
  }

  /// Поток ИЗМЕНЕНИЙ сообщений (реакции мутируют существующий узел —
  /// onChildAdded их не отдаёт). UI заменяет сообщение по id.
  Stream<ChatMessage> watchChatMessageChanges(String pairId) {
    return _chatRef(pairId)
        .limitToLast(50)
        .onChildChanged
        .map((event) => ChatMessage.fromSnapshot(event.snapshot));
  }

  /// Завершить сеанс — удалить узел RTDB.
  Future<void> endSession(String pairId) async {
    if (pairId.isEmpty) return;
    try {
      await _sessionRef(pairId).remove();
    } catch (e) {
      debugPrint('TogetherSessionService.endSession failed: $e');
    }
  }

  /// Покинуть сеанс, не убивая его для партнёра (снять свой презенс).
  Future<void> leavePresence(String pairId) async {
    if (pairId.isEmpty || _uid.isEmpty) return;
    try {
      await _sessionRef(pairId).child('presence').child(_uid).remove();
    } catch (_) {}
  }
}
