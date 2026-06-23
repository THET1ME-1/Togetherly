import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

import 'pocketbase_service.dart';

/// Медиа-слой PocketBase (миграция Firebase→PB, Этап 6).
///
/// Заменяет Firebase Storage. В PB файлы крепятся к записям через file-поле —
/// один блоб = одна запись коллекции `media`. В текстовые поля сущностей
/// (photo_url/image_url/music_url/...) кладём ссылку схемы `pb://media/<id>/<file>`,
/// которая резолвится в `<baseUrl>/api/files/media/<id>/<file>`.
///
/// (Схема `pb://` зеркалит прежнюю `sb://` из supabase-слоя — на cutover
/// резолвер медиа в виджетах распознаёт `pb://` так же, как раньше `sb://`.)
class PbMediaService {
  PbMediaService._();
  static final PbMediaService instance = PbMediaService._();
  factory PbMediaService() => instance;

  PocketBase get _pb => PocketBaseService().pb;
  static const String _col = 'media';
  static const String scheme = 'pb://';

  /// Загружает байты как новый media-файл. Возвращает ссылку
  /// `pb://media/<recordId>/<filename>` или null при ошибке.
  Future<String?> uploadBytes(
    List<int> bytes,
    String filename, {
    String? uid,
    String? groupId,
    String? kind,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (uid != null) body['uid'] = uid;
      if (groupId != null) body['group_id'] = groupId;
      if (kind != null) body['kind'] = kind;
      final rec = await _pb.collection(_col).create(
        body: body,
        files: [
          http.MultipartFile.fromBytes('file', bytes, filename: filename),
        ],
      );
      // PB мог переименовать файл (суффикс против коллизий) → берём фактическое.
      final stored = (rec.data['file'] ?? filename).toString();
      return '$scheme$_col/${rec.id}/$stored';
    } catch (e) {
      debugPrint('PbMedia.uploadBytes failed: $e');
      return null;
    }
  }

  /// Загружает локальный файл по пути. Читает байты, имя — из пути. Возвращает
  /// `pb://`-ссылку или null. Удобная обёртка над [uploadBytes] для call-site'ов,
  /// которые раньше звали `FirebaseService.uploadFile(path, dest)`.
  Future<String?> uploadFile(
    String localPath, {
    String? uid,
    String? groupId,
    String? kind,
  }) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        debugPrint('PbMedia.uploadFile: файла нет: $localPath');
        return null;
      }
      final bytes = await file.readAsBytes();
      final filename = localPath.split('/').last;
      return uploadBytes(bytes, filename, uid: uid, groupId: groupId, kind: kind);
    } catch (e) {
      debugPrint('PbMedia.uploadFile($localPath) failed: $e');
      return null;
    }
  }

  /// `true`, если ссылка — наша PB-схема.
  bool isPbRef(String? url) => url != null && url.startsWith(scheme);

  /// Резолвит `pb://media/<id>/<file>` → публичный HTTPS-URL PB. Не-pb ссылки
  /// (http/gs/локальные) возвращает как есть (переходный период).
  String? resolveUrl(String? ref) {
    if (ref == null || ref.isEmpty) return ref;
    if (!isPbRef(ref)) return ref;
    final path = ref.substring(scheme.length); // media/<id>/<file>
    return '${PocketBaseService.baseUrl}/api/files/$path';
  }

  /// Удаляет media-запись по `pb://`-ссылке (или по recordId).
  Future<bool> delete(String refOrId) async {
    try {
      String id = refOrId;
      if (isPbRef(refOrId)) {
        final parts = refOrId.substring(scheme.length).split('/');
        if (parts.length >= 2) id = parts[1]; // media/<id>/<file>
      }
      if (id.isEmpty) return false;
      await _pb.collection(_col).delete(id);
      return true;
    } catch (e) {
      if (e is ClientException && e.statusCode == 404) return true;
      debugPrint('PbMedia.delete($refOrId) failed: $e');
      return false;
    }
  }
}
