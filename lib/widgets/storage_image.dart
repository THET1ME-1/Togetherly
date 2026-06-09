import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/firebase_service.dart';

/// Drop-in замена [CachedNetworkImage] с поддержкой gs:// и sb:// путей.
///
/// Fast path: https:// URL → сразу [CachedNetworkImage], без FutureBuilder/мигания.
/// Slow path: gs:// (Firebase) или sb:// (Supabase) → запрашивает Signed URL
/// (55-минутный кэш в [FirebaseService]) → [CachedNetworkImage].
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

  @override
  State<StorageImage> createState() => _StorageImageState();
}

class _StorageImageState extends State<StorageImage> {
  Future<String?>? _resolvedUrl;

  // gs:// (Firebase) и sb:// (Supabase) требуют асинхронного разрешения в
  // подписанный https:// URL. https:// рендерится сразу.
  bool get _needsResolve =>
      widget.imageUrl.startsWith('gs://') || widget.imageUrl.startsWith('sb://');

  @override
  void initState() {
    super.initState();
    if (_needsResolve) _resolvedUrl = _resolve(widget.imageUrl);
  }

  @override
  void didUpdateWidget(StorageImage old) {
    super.didUpdateWidget(old);
    if (old.imageUrl != widget.imageUrl && _needsResolve) {
      _resolvedUrl = _resolve(widget.imageUrl);
    }
  }

  Future<String?> _resolve(String url) async {
    // sb:// → передаём ссылку целиком (Supabase сам её разрешит).
    if (url.startsWith('sb://')) return FirebaseService().getSignedUrl(url);
    // gs:// → снимаем префикс bucket'а, Cloud Function ждёт «голый» путь.
    final gsPath = url.replaceFirst(RegExp(r'^gs://[^/]+/'), '');
    return FirebaseService().getSignedUrl(gsPath);
  }

  Widget _buildCached(String url) => CachedNetworkImage(
        imageUrl: url,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        placeholder: widget.placeholder,
        progressIndicatorBuilder: widget.progressIndicatorBuilder,
        errorWidget: widget.errorWidget,
        memCacheWidth: widget.memCacheWidth,
        memCacheHeight: widget.memCacheHeight,
        fadeInDuration: widget.fadeInDuration,
      );

  Widget _empty() =>
      widget.errorWidget?.call(context, widget.imageUrl, 'empty') ??
      SizedBox(width: widget.width, height: widget.height);

  @override
  Widget build(BuildContext context) {
    final url = widget.imageUrl;

    if (url.isEmpty) return _empty();

    // Fast path: https:// → рендерим сразу, без async/мигания
    if (!_needsResolve) return _buildCached(url);

    // Slow path: gs:// / sb:// → ждём Signed URL
    return FutureBuilder<String?>(
      future: _resolvedUrl,
      builder: (context, snap) {
        final resolved = snap.data;
        if (resolved == null || resolved.isEmpty) {
          if (snap.connectionState == ConnectionState.waiting) {
            return widget.placeholder?.call(context, '') ??
                SizedBox(width: widget.width, height: widget.height);
          }
          return _empty();
        }
        return _buildCached(resolved);
      },
    );
  }
}
