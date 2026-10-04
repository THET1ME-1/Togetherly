import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/memory.dart';
import '../../models/reel_link.dart';
import '../locale_service.dart';
import '../memory_repository.dart';
import '../pb_auth_service.dart';

/// Закладка совместной ленты: ролик ложится в ленту воспоминаний пары
/// обычной записью «видео по ссылке». Там он открывается в приложении
/// площадки, а партнёр видит его, как любое воспоминание.
class ReelSave {
  ReelSave._();

  /// Что уже сохранено с этого телефона за жизнь приложения. Кнопку страница
  /// гасит и сама, но повторный вызов моста (два касания подряд, страница
  /// перезагрузилась) не должен заводить вторую запись.
  static final Set<String> _saved = {};

  /// true — запись легла в ленту (или уже лежала).
  static Future<bool> save({required String groupId, required String key}) async {
    final link = ReelLink.parse(key);
    if (link == null || groupId.isEmpty) return false;
    if (_saved.contains('$groupId|${link.key}')) return true;

    final meta = await _meta(link);
    final p = PbAuthService().currentProfile() ?? const {};
    final memory = await MemoryRepository().add(
      groupId: groupId,
      authorName: (p['displayName'] as String?) ?? '',
      authorAvatar: (p['avatarUrl'] as String?) ?? '',
      type: MemoryType.videoLink,
      videoUrl: link.url,
      imageUrl: meta.thumb ?? link.knownThumb,
      title: meta.title ?? link.platform,
      // Карточка видео по ссылке держит автора ролика в поле музыки — так
      // её заполняет и форма воспоминания.
      musicArtist: meta.author,
      caption: LocaleService.current.reelsSavedCaption,
    );
    if (memory == null) return false;
    _saved.add('$groupId|${link.key}');
    return true;
  }

  /// Название и обложка — только если площадка ответила быстро. Без них ролик
  /// всё равно сохраняется: подписью станет имя площадки.
  static Future<ReelMeta> _meta(ReelLink link) async {
    final uri = link.metaUri;
    if (uri == null) return ReelMeta.empty;
    try {
      final r = await http
          .get(uri, headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 14) Togetherly'})
          .timeout(const Duration(seconds: 4));
      if (r.statusCode != 200) return ReelMeta.empty;
      return ReelMeta.fromJson(jsonDecode(utf8.decode(r.bodyBytes)));
    } catch (e) {
      debugPrint('ReelSave: данные ролика не пришли: $e');
      return ReelMeta.empty;
    }
  }
}
