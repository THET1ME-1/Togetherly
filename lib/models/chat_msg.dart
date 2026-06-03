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
  final String? pinId;
  final String? pinTitle;

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
  });

  bool get isEdited => editedTs != null && !deleted;

  factory ChatMsg.fromSnapshot(DataSnapshot snap) {
    final m = (snap.value as Map?) ?? const {};
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
    );
  }
}
