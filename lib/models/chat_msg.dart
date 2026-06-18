import 'package:firebase_database/firebase_database.dart';

/// Сообщение постоянного чата пары. Живёт в Realtime Database
/// (chats/{groupId}/messages/{pushId}) — НИКАКИХ Firestore-чтений.
///
/// Удаление мягкое (deleted=true + текст затирается), чтобы слушатель
/// партнёра мгновенно отрисовал «сообщение удалено», а не пустоту.
class ChatMsg {
  final String id;
  final String uid;
  final String name;
  final String text;
  final int ts;
  final int? editedTs;
  final bool deleted;

  /// Прикреплённый пин (воспоминание): id для перехода + заголовок для отрисовки.
  /// [pinThumb] — URL миниатюры (обложка/кадр/фото), опционально, для предпросмотра.
  final String? pinId;
  final String? pinTitle;
  final String? pinThumb;

  /// Реакции на сообщение: uid → эмодзи (один эмодзи на пользователя).
  /// Лежат в самом узле сообщения (reactions/{uid}), поэтому приходят вместе
  /// с сообщением — без отдельного listener'а.
  final Map<String, String> reactions;

  /// Ответ на сообщение: id оригинала + СНИМОК имени/текста на момент отправки
  /// (цитата остаётся читаемой, даже если оригинал потом отредактирован/удалён).
  final String? replyToId;
  final String? replyToName;
  final String? replyToText;

  /// Выражение мордочки, выбранное ОТПРАВИТЕЛЕМ (имя варианта). null — без лица.
  /// Лицо больше не угадывается по тексту — его осознанно ставит автор.
  final String? face;

  const ChatMsg({
    required this.id,
    required this.uid,
    required this.name,
    required this.text,
    required this.ts,
    this.editedTs,
    this.deleted = false,
    this.pinId,
    this.pinTitle,
    this.pinThumb,
    this.reactions = const {},
    this.replyToId,
    this.replyToName,
    this.replyToText,
    this.face,
  });

  bool get isEdited => editedTs != null && !deleted;

  factory ChatMsg.fromSnapshot(DataSnapshot snap) {
    final m = (snap.value as Map?) ?? const {};
    final rawReactions = m['reactions'];
    final reactions = <String, String>{};
    if (rawReactions is Map) {
      rawReactions.forEach((k, v) {
        if (v is String && v.isNotEmpty) reactions[k.toString()] = v;
      });
    }
    return ChatMsg(
      id: snap.key ?? '',
      uid: (m['uid'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      text: (m['text'] as String?) ?? '',
      ts: (m['ts'] as num?)?.toInt() ?? 0,
      editedTs: (m['editedTs'] as num?)?.toInt(),
      deleted: (m['deleted'] as bool?) ?? false,
      pinId: m['pinId'] as String?,
      pinTitle: m['pinTitle'] as String?,
      pinThumb: m['pinThumb'] as String?,
      reactions: reactions,
      replyToId: m['replyToId'] as String?,
      replyToName: m['replyToName'] as String?,
      replyToText: m['replyToText'] as String?,
      face: m['face'] as String?,
    );
  }
}
