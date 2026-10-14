import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../models/pb_media_ref.dart';
import 'offline/media_view_cache.dart';
import 'pb_media_service.dart';

/// Баннеры профиля на диске: каждый качается с сервера один раз.
///
/// Новый баннер — новая запись `media`, то есть новая ссылка. Файл под
/// ссылкой не меняется никогда, и проверять его свежесть незачем. Общий кэш
/// картинок (`StorageImage`) так не умеет: он перекачивает файл целиком, когда
/// выходит срок из заголовка сервера (30 дней, ETag сервер не даёт), и перед
/// каждым показом ждёт файловый токен. А GIF в баннере весит до десяти
/// мегабайт, и шапку открывают каждый день.
class BannerCache {
  BannerCache({
    required BaseCacheManager manager,
    required Future<String?> Function(String ref) resolve,
  })  : _manager = manager,
        _resolve = resolve;

  static BannerCache _instance = BannerCache(
    manager: BannerCacheManager.instance,
    resolve: (ref) => PbMediaService().resolveUrlAuthed(ref),
  );

  /// Общий на приложение.
  static BannerCache get instance => _instance;

  /// Тесты подменяют общий кэш своим, на подделках.
  @visibleForTesting
  static set instance(BannerCache value) => _instance = value;

  final BaseCacheManager _manager;

  /// Адрес для скачивания, с файловым токеном. Нужен только на первый раз.
  final Future<String?> Function(String ref) _resolve;

  /// Что уже лежит на диске в этом запуске: шапка рисует файл сразу, без
  /// кадра пустого фона.
  final Map<String, io.File> _known = {};

  final Map<String, Future<io.File?>> _inflight = {};

  /// Ключ баннера — `pb://`-ссылка. Готовый адрес файла приводим к ней же, а
  /// токен в ключ не попадает: иначе каждый показ считался бы новым файлом.
  static String keyFor(String ref) => pbRefFromUrl(ref) ?? ref;

  /// Файл, если он уже известен в этом запуске.
  io.File? known(String ref) => _known[keyFor(ref)];

  /// Файл баннера: с диска, а нет на диске — один раз с сервера.
  ///
  /// null — скачать не вышло (нет сети, файла нет на сервере). В кэш такое
  /// не попадает, и следующий показ попробует снова.
  Future<io.File?> file(String ref) {
    final key = keyFor(ref);
    final hit = _known[key];
    if (hit != null) return Future.value(hit);
    // Тело в фигурных скобках не случайно: стрелка вернула бы из колбэка
    // удалённый future, то есть этот же самый, и он ждал бы сам себя вечно.
    return _inflight[key] ??= _load(key).whenComplete(() {
      _inflight.remove(key);
    });
  }

  Future<io.File?> _load(String key) async {
    try {
      final cached = await _manager.getFileFromCache(key);
      if (cached != null) return _known[key] = cached.file;
      final url = await _resolve(key);
      if (url == null || url.isEmpty) return null;
      final info = await _manager.downloadFile(url, key: key);
      return _known[key] = info.file;
    } catch (e) {
      debugPrint('BannerCache: $key не скачался: $e');
      return null;
    }
  }

  /// Кладёт свой только что залитый баннер: байты и так на телефоне, качать
  /// их обратно незачем.
  Future<void> put(String ref, io.File local) async {
    final key = keyFor(ref);
    try {
      final dot = local.path.lastIndexOf('.');
      final file = await _manager.putFile(
        key,
        await local.readAsBytes(),
        key: key,
        fileExtension: dot < 0 ? 'file' : local.path.substring(dot + 1),
      );
      _known[key] = file;
    } catch (e) {
      debugPrint('BannerCache.put: $key не лёг в кэш: $e');
    }
  }
}
