import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/avatar_frame.dart';
import '../models/push_cover.dart';
import 'catalog_service.dart';

/// Своё уведомление видом «А» (28.11.2026): обложку рисует Android
/// (`notif/NotifCover.kt`, канал `love_app/notif`), как у пуша сервера.
///
/// Канал есть только у движка приложения: в изоляте фоновой службы (телефоны
/// без сервисов Google) его нет, и уведомление уходит прежним видом.
class NotifRenderer {
  NotifRenderer._();

  static const MethodChannel _channel = MethodChannel('love_app/notif');

  /// Версия отрисовки этой сборки: с ней сервер шлёт пуш данными
  /// (`users.notif_v`, см. `NotifPrefsSync`). 0 — сборка рисовать не умеет.
  static int get version => !kIsWeb && Platform.isAndroid ? 1 : 0;

  /// Показать [cover]. false — не вышло (нет канала, ошибка), тогда звать
  /// прежний показ.
  static Future<bool> show({
    required Map<String, Object?> cover,
    required String title,
    required String body,
    required String tag,
    required int id,
    String channel = 'partner_notifications',
  }) async {
    if (version == 0) return false;
    try {
      final shown = await _channel.invokeMethod<bool>('show', {
        'cover': jsonEncode(cover),
        'title': title,
        'body': body,
        'tag': tag,
        'id': id,
        'channel': channel,
      });
      return shown ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('NotifRenderer: ${e.code} ${e.message}');
      return false;
    }
  }
}

/// Картинки обложки из каталога приложения — те же записи, что у сервера.
class CatalogCoverLook implements CoverLook {
  const CatalogCoverLook();

  @override
  String? still(String catalogId) {
    final catalog = CatalogService.instance;
    if (catalogId.startsWith('frame_')) {
      final key = catalogId.substring('frame_'.length);
      for (final f in catalog.frames) {
        if (f.key == key) return _https(f.stillUrl);
      }
      return null;
    }
    // Ключ картинки в каталоге — `data.key`: `art_act_miss` → `act_miss`,
    // `gift_heart` → `heart`.
    final key = catalogId.startsWith('art_')
        ? catalogId.substring('art_'.length)
        : catalogId.startsWith('gift_')
            ? catalogId.substring('gift_'.length)
            : catalogId;
    return _https(catalog.giftArt(key)?.stillUrl);
  }

  @override
  String? moti(String moodId) {
    // Только «Моти»: запасной набор с розовыми рожицами в уведомление не
    // ставим (слово владельца), лучше иконка приложения.
    final pack = CatalogService.instance.packById('moti');
    if (pack.id != 'moti') return null;
    for (final m in pack.moods) {
      if (m.id == moodId) return _https(m.imagePath);
    }
    return null;
  }

  @override
  double frameHole(String key) =>
      AvatarFrame.byKey(key)?.hole ?? AvatarFrame.bundledHole[key] ?? AvatarFrame.avatarR;

  static String? _https(String? url) => (url != null && url.startsWith('https://')) ? url : null;
}
