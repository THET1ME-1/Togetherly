import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'offline/media_view_cache.dart';
import 'widget_photo_cache.dart';

/// Один файл на телефон: качаем картинку ОДИН раз, дальше её берут все.
///
/// Раньше одну и ту же аватарку тянули порознь три хозяина: экран через
/// `StorageImage`, `widget_service` для своих виджетов и `home_widget_service`
/// для своих. У каждого был свой кэш и свои файлы, поэтому замер на эмуляторе
/// показал 13 закачек двух аватарок за один заход — по шесть-семь на файл.
///
/// Склад один и тот же для всех: это кэш [OfflineImageCacheManager], в который
/// пишет и из которого читает `StorageImage`. Ключ — ИСХОДНАЯ ссылка (`pb://`)
/// под тем же префиксом `v2|`, что у экрана: адрес с file-токеном не годится,
/// токен живёт минуты и ключ бы менялся на каждом запросе.
///
/// Отсюда следствие, ради которого всё и затевалось: показал экран аватарку —
/// виджеты возьмут её с диска; скачал первым виджет — экран не полезет в сеть.
class WidgetPhotoStore {
  WidgetPhotoStore._();

  static final WidgetPhotoStore instance = WidgetPhotoStore._();

  /// Загрузки, идущие прямо сейчас. Виджеты обновляются пачкой («дни вместе»,
  /// «скучаю», «вместе» — и каждый со своей стороной сжатия), запросы уходят
  /// вперемешку, и без этой карты все они дружно шли бы в сеть за одним и тем
  /// же файлом, пока первый ещё не дописал его на диск.
  final Map<String, Future<Uint8List?>> _inFlight = {};

  static String cacheKeyFor(String url) => 'v2|$url';

  /// Байты картинки [url]. [httpUrl] — тот же файл в виде адреса, по которому
  /// его можно скачать (с file-токеном). В сеть идём, только если на диске
  /// пусто.
  Future<Uint8List?> bytesFor(String url, String httpUrl) {
    final key = cacheKeyFor(url);
    final running = _inFlight[key];
    if (running != null) return running;

    final job = _load(key, httpUrl).whenComplete(() => _inFlight.remove(key));
    _inFlight[key] = job;
    return job;
  }

  Future<Uint8List?> _load(String key, String httpUrl) async {
    // 1. Уже лежит на диске — сеть не нужна.
    try {
      final hit = await OfflineImageCacheManager.instance.getFileFromCache(key);
      // Обрывок записи (нулевой или крошечный файл) — не кэш: отдать его
      // значило бы разложить пустоту по всем виджетам и больше никогда не
      // пойти в сеть.
      if (hit != null &&
          hit.file.existsSync() &&
          hit.file.lengthSync() >= kMinWidgetPhotoBytes) {
        return await hit.file.readAsBytes();
      }
    } catch (e) {
      // Кэш недоступен (фоновый изолят, занятая база) — не беда, качаем.
      debugPrint('WidgetPhotoStore: кэш не прочитался — $e');
    }

    // 2. Качаем один раз.
    final Uint8List bytes;
    try {
      final response = await http
          .get(Uri.parse(httpUrl))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        debugPrint('WidgetPhotoStore: ${response.statusCode} на $key');
        return null;
      }
      bytes = response.bodyBytes;
    } catch (e) {
      debugPrint('WidgetPhotoStore: не скачалось — $e');
      return null;
    }

    // 3. Кладём на общий склад, чтобы следующий (в том числе экран) не качал.
    // Падение записи не должно ронять выдачу: байты у нас уже есть.
    try {
      await OfflineImageCacheManager.instance.putFile(
        httpUrl,
        bytes,
        key: key,
        maxAge: const Duration(days: 3650),
      );
    } catch (e) {
      debugPrint('WidgetPhotoStore: на склад не легло — $e');
    }
    return bytes;
  }
}
