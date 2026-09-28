import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/catalog_service.dart';
import '../../services/offline/media_view_cache.dart';

/// Значок самочувствия той же рукой, что значки профиля (манера Overrule,
/// макет https://claude.ai/artifact/M3UZu6LaLaASi6TFXXFimC).
///
/// Анимация — из серверного каталога (`catalog_items`, вид `ailment`,
/// `ailment_<id>`), поэтому перерисованный значок доезжает без обновления.
/// Пока она грузится или сети нет — неподвижный кадр из сборки
/// (`assets/images/ailments/<id>.webp`). Незнакомый сборке id (новое
/// самочувствие, заведённое позже) — прежний эмодзи.
class AilmentIcon extends StatelessWidget {
  const AilmentIcon({super.key, required this.id, required this.emoji, this.size = 28, this.animated = true});

  final String id;

  /// Запасной знак — тот, что лежит в записи самочувствия.
  final String emoji;
  final double size;
  final bool animated;

  /// Самочувствия, чей неподвижный кадр есть в сборке.
  static const Set<String> bundled = {
    'unwell', 'headache', 'heartburn', 'nausea', 'cold', 'fever', 'stomach', 'throat',
    'cough', 'tooth', 'back', 'cramps', 'dizzy', 'fatigue', 'insomnia', 'allergy',
  };

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final decode = (size * dpr).round();
    final fallback = bundled.contains(id)
        ? Image.asset(
            'assets/images/ailments/$id.webp',
            width: size,
            height: size,
            fit: BoxFit.contain,
            cacheWidth: decode,
            errorBuilder: (_, _, _) => _emoji(),
          )
        : _emoji();
    return SizedBox.square(
      dimension: size,
      child: ListenableBuilder(
        listenable: CatalogService.instance,
        builder: (context, _) {
          final still = !animated || (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
          final url = CatalogService.instance.ailmentArt(id)?.urlFor(size, animated: !still);
          if (url == null) return fallback;
          return CachedNetworkImage(
            cacheManager: OfflineImageCacheManager.instance,
            imageUrl: url,
            width: size,
            height: size,
            fit: BoxFit.contain,
            memCacheWidth: decode,
            fadeInDuration: Duration.zero,
            placeholder: (_, _) => fallback,
            errorWidget: (_, _, _) => fallback,
          );
        },
      ),
    );
  }

  Widget _emoji() => Center(child: Text(emoji, style: TextStyle(fontSize: size * 0.64)));
}
