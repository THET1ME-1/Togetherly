import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/mood_entry.dart';
import '../theme/theme_scope.dart';

/// Единый рендер картинки настроения по [imagePath].
///
/// Путь может быть:
///   • бандленным ассетом  ('assets/images/...')      → [Image.asset]
///   • удалённым URL пака из каталога ('https://...')  → [CachedNetworkImage]
///     (качается один раз, лежит в дисковом кэше; публичный bucket, без подписи).
///
/// Для удалённых паков, которых нет в текущей сборке, при ошибке загрузки
/// пытаемся показать классический эквивалент по id ([MoodOption.classicFallbackFor])
/// — чтобы у партнёра на старой сборке/без сети не было «битой» картинки.
class MoodImage extends StatelessWidget {
  final String imagePath;
  final BoxFit fit;
  final double? width;
  final double? height;

  const MoodImage(
    this.imagePath, {
    super.key,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
  });

  static bool _isRemote(String p) =>
      p.startsWith('http://') || p.startsWith('https://');

  /// Во сколько пикселей разворачивать картинку.
  ///
  /// Стикеры паков — квадраты 512, а на экране они живут в 28–64 точках. Без
  /// подсказки Flutter держит в памяти полный кадр (512×512×4 — мегабайт на
  /// стикер), и сетка календаря на тридцать дней уносила тридцать мегабайт
  /// ради картинок размером с ноготь.
  ///
  /// Предел ставится ОДИН, по заданной стороне: с двумя разом кадр
  /// декодируется в прямоугольник и стикер сплющивается.
  (int?, int?) _decodeLimits(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    if (width != null && width!.isFinite) return ((width! * dpr).ceil(), null);
    if (height != null && height!.isFinite) {
      return (null, (height! * dpr).ceil());
    }
    return (null, null);
  }

  @override
  Widget build(BuildContext context) {
    if (imagePath.isEmpty) return SizedBox(width: width, height: height);

    final (decodeWidth, decodeHeight) = _decodeLimits(context);

    if (!_isRemote(imagePath)) {
      return Image.asset(
        imagePath,
        fit: fit,
        width: width,
        height: height,
        cacheWidth: decodeWidth,
        cacheHeight: decodeHeight,
        errorBuilder: (ctx, __, ___) => _fallback(ctx),
      );
    }

    // Пак могли перезалить — тогда в отметке лежит адрес удалённого файла.
    // Берём тот же стикер по актуальному адресу из каталога.
    return CachedNetworkImage(
      imageUrl: MoodOption.freshRemotePath(imagePath) ?? imagePath,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: decodeWidth,
      memCacheHeight: decodeHeight,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, __) => SizedBox(width: width, height: height),
      errorWidget: (ctx, __, ___) => _fallback(ctx),
    );
  }

  /// Фолбэк: классический ассет по id настроения, иначе нейтральная иконка.
  Widget _fallback(BuildContext context) {
    final classic = MoodOption.classicFallbackFor(imagePath);
    if (classic != null) {
      final (decodeWidth, decodeHeight) = _decodeLimits(context);
      return Image.asset(
        classic,
        fit: fit,
        width: width,
        height: height,
        cacheWidth: decodeWidth,
        cacheHeight: decodeHeight,
        errorBuilder: (ctx, __, ___) => _icon(ctx),
      );
    }
    return _icon(context);
  }

  Widget _icon(BuildContext context) => Icon(
        Icons.sentiment_satisfied_alt_rounded,
        size: (width ?? height ?? 32) * 0.7,
        color: context.appTheme.textMuted,
      );
}
