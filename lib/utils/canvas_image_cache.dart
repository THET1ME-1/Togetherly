import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../models/draw_stroke.dart';
import '../services/offline/media_view_cache.dart';
import '../services/pb_media_service.dart';

/// Растры картинок-штрихов холста: заливок ведром и вставленных фотографий.
///
/// Зачем отдельный кэш: до 25.08.2026 картинки рисовались виджетами `Image`
/// поверх `CustomPaint`, и порядок с ними не работал вовсе — пятно заливки
/// лежало сверху всего рисунка, а ластик его не брал. Чтобы картинка встала на
/// своё место в порядке, её должен рисовать тот же painter, а ему нужен
/// готовый [ui.Image] — виджеты умеют ждать загрузку, painter не умеет.
///
/// Кэш живёт в состоянии сцены. Пока растра нет, картинка просто не рисуется;
/// как загрузится — [notifyListeners], и холст перерисовывается.
class CanvasImageCache extends ChangeNotifier {
  CanvasImageCache();

  final Map<String, ui.Image> _ready = {};
  final Set<String> _loading = {};
  final Map<String, int> _failures = {};
  bool _disposed = false;

  /// Сколько раз пробуем один и тот же адрес. Полумёртвая сессия PocketBase
  /// отдаёт 403 на первый заход и открывает файл со второго — с одной попытки
  /// заливка партнёра осталась бы дырой до перезахода на холст.
  static const int _maxAttempts = 4;

  /// Во сколько пикселей разворачивать растр по длинной стороне.
  ///
  /// Заливка и так режется до 1600 при создании, а вставленное фото приходит с
  /// камеры в 4000 — это 48 МБ в памяти на одну картинку.
  static const int _decodeSide = 1600;

  /// Готовый растр штриха или null, если он ещё едет.
  ///
  /// [localPath] — свой только что сделанный файл: качать своё же изображение
  /// из сети незачем.
  ui.Image? imageFor(DrawStroke stroke, {String? localPath}) {
    final key = sourceOf(stroke, localPath: localPath);
    if (key == null) return null;
    final ready = _ready[key];
    if (ready != null) return ready;
    _start(key);
    return null;
  }

  /// Забыть всё, чего в рисунке больше нет: растр держит память до гигабайта
  /// на десятке заливок.
  void retainOnly(Iterable<String> keys) {
    final keep = keys.toSet();
    final gone = _ready.keys.where((k) => !keep.contains(k)).toList();
    for (final key in gone) {
      _ready.remove(key)?.dispose();
      _failures.remove(key);
    }
  }

  /// Откуда брать картинку штриха: локальный файл важнее сетевого адреса.
  static String? sourceOf(DrawStroke stroke, {String? localPath}) {
    if (localPath != null && localPath.isNotEmpty) {
      if (File(localPath).existsSync()) return 'file://$localPath';
    }
    final url = stroke.imageUrl;
    if (url == null || url.isEmpty) return null;
    return url;
  }

  Future<void> _start(String key) async {
    if (_disposed || _loading.contains(key)) return;
    if ((_failures[key] ?? 0) >= _maxAttempts) return;
    _loading.add(key);
    try {
      final provider = await _providerFor(key);
      if (provider == null) {
        _fail(key);
        return;
      }
      final image = await _resolve(provider);
      if (_disposed) {
        image?.dispose();
        return;
      }
      if (image == null) {
        _fail(key);
        return;
      }
      _ready[key]?.dispose();
      _ready[key] = image;
      _failures.remove(key);
      notifyListeners();
    } catch (_) {
      _fail(key);
    } finally {
      _loading.remove(key);
    }
  }

  void _fail(String key) {
    final attempts = (_failures[key] ?? 0) + 1;
    _failures[key] = attempts;
    if (attempts >= _maxAttempts || _disposed) return;
    // Повтор не сразу: 403 полумёртвой сессии проходит, когда та поднимется.
    Timer(Duration(seconds: attempts * 2), () {
      if (_disposed) return;
      _failures.remove(key);
      notifyListeners();
    });
  }

  Future<ImageProvider?> _providerFor(String key) async {
    if (key.startsWith('file://')) {
      final file = File(key.substring(7));
      if (!file.existsSync()) return null;
      return _sized(FileImage(file));
    }
    // pb:// — защищённый файл PocketBase: адрес живёт с file-токеном, и
    // добывается он асинхронно.
    final resolved =
        PbMediaService().isPbRef(key) ? await PbMediaService().resolveUrlAuthed(key) : key;
    if (resolved == null || resolved.isEmpty) return null;
    if (!resolved.startsWith('http')) return null;
    return _sized(CachedNetworkImageProvider(
      resolved,
      // Ключ по исходной ссылке — тот же, что у `StorageImage`: смена токена не
      // должна сбрасывать уже скачанный файл.
      cacheKey: 'v2|$key',
      cacheManager: OfflineImageCacheManager.instance,
    ));
  }

  ImageProvider _sized(ImageProvider provider) => ResizeImage(
        provider,
        width: _decodeSide,
        height: _decodeSide,
        policy: ResizeImagePolicy.fit,
        allowUpscaling: false,
      );

  Future<ui.Image?> _resolve(ImageProvider provider) {
    final completer = Completer<ui.Image?>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) {
          // Клон: `ImageInfo` уйдёт вместе с записью кэша Flutter, а painter
          // держит растр столько, сколько картинка лежит в рисунке. Клон — своя
          // ссылка на тот же растр, чужой `dispose` его не уносит.
          completer.complete(info.image.clone());
        }
        info.dispose();
        stream.removeListener(listener);
      },
      onError: (_, _) {
        if (!completer.isCompleted) completer.complete(null);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final image in _ready.values) {
      image.dispose();
    }
    _ready.clear();
    super.dispose();
  }
}
