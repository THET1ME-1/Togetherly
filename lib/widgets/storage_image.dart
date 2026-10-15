import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../services/offline/media_cache.dart';
import '../services/offline/media_view_cache.dart';
import '../services/pb_media_service.dart';

/// Drop-in замена [CachedNetworkImage] с поддержкой pb:// / gs:// / sb:// путей.
///
/// Fast path: https:// и pb:// (PocketBase) → сразу [CachedNetworkImage] (pb://
/// резолвится синхронно в публичный HTTPS, без FutureBuilder/мигания).
/// Slow path: gs:// (Firebase) / sb:// (Supabase) → асинхронный Signed URL.
/// Старые https:// download URL работают без изменений (обратная совместимость).
class StorageImage extends StatefulWidget {
  const StorageImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.progressIndicatorBuilder,
    this.errorWidget,
    this.memCacheWidth,
    this.memCacheHeight,
    this.fadeInDuration = const Duration(milliseconds: 300),
    this.onSize,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, DownloadProgress)? progressIndicatorBuilder;
  final Widget Function(BuildContext, String, dynamic)? errorWidget;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final Duration fadeInDuration;

  /// Размер кадра в пикселях, когда он разошёлся из кэша.
  ///
  /// Нужен там, где кадр показывается ЦЕЛИКОМ, в своей пропорции: в записи
  /// воспоминания хранится одна ссылка, ширины и высоты там нет. Картинку
  /// берём из того же кэша, из которого рисуем, — повторной закачки не будет.
  final void Function(Size size)? onSize;

  /// Подмена кэша в тестах.
  @visibleForTesting
  static BaseCacheManager? debugCacheManager;

  /// Подмена получения адреса с файловым токеном в тестах.
  @visibleForTesting
  static Future<String?> Function(String ref)? debugResolve;

  /// Забыть, какие снимки уже нашлись на диске.
  @visibleForTesting
  static void debugForgetDisk() => _onDisk.clear();

  /// Ключ кэша → файл на диске: что уже находили за этот запуск.
  ///
  /// Лента пересоздаёт плитки при прокрутке, и без этой памяти каждая заново
  /// спрашивала бы кэш и мигала заглушкой.
  static final Map<String, String> _onDisk = {};
  static const int _onDiskLimit = 3000;

  static BaseCacheManager get _cache =>
      debugCacheManager ?? OfflineImageCacheManager.instance;

  static void _remember(String key, String path) {
    _onDisk.remove(key);
    _onDisk[key] = path;
    if (_onDisk.length > _onDiskLimit) _onDisk.remove(_onDisk.keys.first);
  }

  @override
  State<StorageImage> createState() => _StorageImageState();
}

/// Откуда рисовать защищённый снимок: файл с диска или адрес с токеном.
class _Source {
  const _Source.file(String this.path) : url = null;
  const _Source.url(this.url) : path = null;

  final String? path;
  final String? url;
}

class _StorageImageState extends State<StorageImage> {
  /// Ждём его, только пока снимка на диске нет.
  Future<_Source>? _source;

  /// Сеть после того, как файл на диске не открылся.
  Future<String?>? _network;

  /// Для какого файла уже сообщили размер.
  String? _sizedPath;

  // Асинхронного разрешения требуют: gs:// (Firebase signed URL), sb:// (Supabase)
  // И pb:// (PocketBase protected-файл → нужен ?token=, добываемый асинхронно).
  // https:// и локальные пути рендерятся сразу.
  // Токен нужен и готовому адресу нашего файла, а не только схеме `pb://`:
  // коллекция `media` защищённая, и без него приходит 404.
  bool get _needsResolve => PbMediaService().needsFileToken(widget.imageUrl);

  /// URL для немедленного рендера (только не-резолв-схемы: https/локальные).
  String get _fastUrl => widget.imageUrl;

  String get _cacheKey => 'v2|${widget.imageUrl}';

  @override
  void initState() {
    super.initState();
    if (_needsResolve) _source = _pick(widget.imageUrl);
  }

  @override
  void didUpdateWidget(StorageImage old) {
    super.didUpdateWidget(old);
    if (old.imageUrl != widget.imageUrl) {
      _network = null;
      _sizedPath = null;
      if (_needsResolve) _source = _pick(widget.imageUrl);
    }
  }

  /// Сначала диск, сеть — только за тем, чего на телефоне нет.
  ///
  /// Ключ кэша не содержит токена, а файл под `pb://`-ссылкой не меняется
  /// никогда: новый снимок — новая запись. Поэтому скачанное однажды
  /// показывается без сети и без срока свежести. Раньше перед показом
  /// спрашивался токен, и на рвущейся связи аватарки с лентой стояли пустыми
  /// до 12 секунд, а без сети не появлялись вовсе (жалоба 15.10.2026).
  Future<_Source> _pick(String url) async {
    final key = 'v2|$url';
    try {
      // База кэша изредка не отвечает вовсе (widget_photo_store.dart) — тогда
      // лучше сходить в сеть, чем стоять заглушкой.
      final hit = await StorageImage._cache
          .getFileFromCache(key)
          .timeout(const Duration(seconds: 3));
      final path = hit?.file.path;
      if (path != null) {
        // Своим File по пути: файл из пакета `file` на Android умеет не
        // ответить вовсе (там же).
        final file = File(path);
        if (await file.exists() && await file.length() > 0) {
          StorageImage._remember(key, path);
          return _Source.file(path);
        }
      }
    } catch (_) {
      // Кэш не открылся или молчит — идём в сеть, как раньше.
    }
    return _Source.url(await _resolve(url));
  }

  Future<String?> _resolve(String url) {
    final debug = StorageImage.debugResolve;
    if (debug != null) return debug(url);
    // Только pb:// (PocketBase protected media) → HTTPS с file-токеном.
    return PbMediaService().resolveUrlAuthed(url);
  }

  // Стабильный cacheKey = исходная ссылка (pb://gs://sb://), чтобы смена
  // file-токена/signed-URL НЕ сбрасывала дисковый кэш картинки.
  // Префикс версии 'v2|': прежняя версия могла закэшировать ЧУЖОЕ фото под этим
  // ключом из-за бага переиспользования элементов ленты (FutureBuilder ниже
  // отдавал предыдущий resolved-URL на connectionState=waiting). Смена префикса
  // разово сбрасывает потенциально «отравленные» записи кэша на устройствах.
  /// Во сколько пикселей разворачивать кадр.
  ///
  /// Явный предел уважаем как есть; если его не передали — считаем по размеру
  /// на экране. Снимок с телефона это 4000×3000, то есть 48 МБ в памяти на
  /// плитку в сто двадцать точек: лента из десяти таких плиток раньше
  /// разворачивала полгигабайта картинок, и слабые телефоны на этом сдавались.
  ///
  /// Предел ставится ОДИН, по заданной стороне. С двумя разом кадр
  /// декодируется в прямоугольник и сплющивается — на этом обжигались
  /// миниатюры админки.
  (int?, int?) get _decode {
    if (widget.memCacheWidth != null || widget.memCacheHeight != null) {
      return (widget.memCacheWidth, widget.memCacheHeight);
    }
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final w = widget.width;
    final h = widget.height;
    if (w != null && w.isFinite) return ((w * dpr).ceil(), null);
    if (h != null && h.isFinite) return (null, (h * dpr).ceil());
    return (null, null);
  }

  Widget _buildCached(String url) {
    final (decodeWidth, decodeHeight) = _decode;
    return CachedNetworkImage(
      imageUrl: url,
      cacheKey: _cacheKey,
      // Долгоживущий кэш → уже виденное фото гарантированно открывается офлайн.
      cacheManager: StorageImage._cache,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      imageBuilder: widget.onSize == null
          ? null
          : (ctx, provider) {
              provider
                  .resolve(const ImageConfiguration())
                  .addListener(ImageStreamListener((info, _) {
                widget.onSize!(Size(
                  info.image.width.toDouble(),
                  info.image.height.toDouble(),
                ));
              }, onError: (_, _) {}));
              return Image(
                image: provider,
                width: widget.width,
                height: widget.height,
                fit: widget.fit,
              );
            },
      placeholder: widget.placeholder,
      progressIndicatorBuilder: widget.progressIndicatorBuilder,
      errorWidget: widget.errorWidget,
      memCacheWidth: decodeWidth,
      memCacheHeight: decodeHeight,
      fadeInDuration: widget.fadeInDuration,
    );
  }

  Widget _empty() =>
      widget.errorWidget?.call(context, widget.imageUrl, 'empty') ??
      SizedBox(width: widget.width, height: widget.height);

  Widget _waiting() =>
      widget.placeholder?.call(context, '') ??
      SizedBox(width: widget.width, height: widget.height);

  /// Снимок с диска: без сети, без токена и без проявления.
  Widget _buildFile(String path) {
    final (decodeWidth, decodeHeight) = _decode;
    final provider = ResizeImage.resizeIfNeeded(
        decodeWidth, decodeHeight, FileImage(File(path)));
    final onSize = widget.onSize;
    if (onSize != null && _sizedPath != path) {
      _sizedPath = path;
      provider
          .resolve(const ImageConfiguration())
          .addListener(ImageStreamListener((info, _) {
        if (mounted) {
          onSize(Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          ));
        }
      }, onError: (_, _) {}));
    }
    return Image(
      image: provider,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => _fromNetworkAfterBrokenFile(),
    );
  }

  /// Файл на диске не открылся: забываем его и берём снимок заново из сети.
  Widget _fromNetworkAfterBrokenFile() {
    final key = _cacheKey;
    StorageImage._onDisk.remove(key);
    _network ??= () async {
      try {
        await StorageImage._cache.removeFile(key);
      } catch (_) {}
      return _resolve(widget.imageUrl);
    }();
    return FutureBuilder<String?>(
      future: _network,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return _waiting();
        final resolved = snap.data;
        if (resolved == null || resolved.isEmpty) return _empty();
        return _buildCached(resolved);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.imageUrl;

    if (url.isEmpty) return _empty();

    // Офлайн-медиа: созданное без сети показываем прямо с диска (Image.file).
    if (MediaCache.instance.isLocalRef(url)) {
      final p = MediaCache.instance.localPath(url);
      if (p != null && File(p).existsSync()) {
        final (decodeWidth, decodeHeight) = _decode;
        return Image.file(
          File(p),
          width: widget.width,
          height: widget.height,
          cacheWidth: decodeWidth,
          cacheHeight: decodeHeight,
          fit: widget.fit,
          errorBuilder: (_, _, _) => _empty(),
        );
      }
      return _empty();
    }

    // Fast path: https:// / pb:// → рендерим сразу, без async/мигания
    if (!_needsResolve) return _buildCached(_fastUrl);

    // Защищённый файл уже находили на диске за этот запуск — рисуем с первого
    // кадра: лента пересоздаёт плитки при прокрутке.
    final known = StorageImage._onDisk[_cacheKey];
    if (known != null) return _buildFile(known);

    // pb:// → сперва диск, без файла — адрес с файловым токеном.
    return FutureBuilder<_Source>(
      future: _source,
      builder: (context, snap) {
        // КРИТИЧНО: пока ищется новый снимок — показываем placeholder, а НЕ
        // snapshot.data. При смене imageUrl (элемент ленты переиспользован под
        // другое воспоминание — записи сортируются «новые сверху», индексы
        // сдвигаются) FutureBuilder временно отдаёт ПРЕДЫДУЩИЙ ответ с
        // connectionState=waiting. Если его отрендерить, плитка нового
        // воспоминания покажет фото предыдущего И закэширует его под своим
        // cacheKey. Поэтому на waiting — строго placeholder.
        if (snap.connectionState == ConnectionState.waiting) return _waiting();
        final source = snap.data;
        final path = source?.path;
        if (path != null) return _buildFile(path);
        final resolved = source?.url;
        if (resolved == null || resolved.isEmpty) return _empty();
        return _buildCached(resolved);
      },
    );
  }
}
