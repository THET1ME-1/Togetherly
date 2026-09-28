import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/chat_reaction.dart';
import '../../services/catalog_service.dart';
import '../../services/offline/media_view_cache.dart';

/// Реакция чата рисунком той же руки, что значки.
///
/// Анимация — из серверного каталога (`reaction_<id>`), неподвижный кадр —
/// из сборки (`assets/images/reactions/<id>.webp`). Эмодзи без рисунка
/// (поставлен старой сборкой или с клавиатуры) показывается как есть.
class ReactionArt extends StatelessWidget {
  const ReactionArt({super.key, required this.emoji, this.size = 20, this.animated = false});

  final String emoji;
  final double size;

  /// Играть анимацию. В чипах у пузырей не играем: их десятки на экране.
  final bool animated;

  @override
  Widget build(BuildContext context) {
    final r = chatReactionOf(emoji);
    if (r == null) {
      return SizedBox.square(
        dimension: size,
        child: Center(child: Text(emoji, style: TextStyle(fontSize: size * 0.8, height: 1))),
      );
    }
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final decode = (size * dpr).round();
    final still = Image.asset(
      'assets/images/reactions/${r.id}.webp',
      width: size,
      height: size,
      fit: BoxFit.contain,
      cacheWidth: decode,
      errorBuilder: (_, _, _) => Center(child: Text(emoji, style: TextStyle(fontSize: size * 0.8))),
    );
    if (!animated || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      return SizedBox.square(dimension: size, child: still);
    }
    return SizedBox.square(
      dimension: size,
      child: ListenableBuilder(
        listenable: CatalogService.instance,
        builder: (context, _) {
          final url = CatalogService.instance.reactionArt(r.id)?.urlFor(size, animated: true);
          if (url == null) return still;
          return CachedNetworkImage(
            cacheManager: OfflineImageCacheManager.instance,
            imageUrl: url,
            width: size,
            height: size,
            fit: BoxFit.contain,
            memCacheWidth: decode,
            fadeInDuration: Duration.zero,
            placeholder: (_, _) => still,
            errorWidget: (_, _, _) => still,
          );
        },
      ),
    );
  }
}

/// Сетка всех реакций: [selected] подсвечена, касание отдаёт эмодзи.
class ReactionGrid extends StatelessWidget {
  const ReactionGrid({super.key, required this.onPick, this.selected, this.size = 40});

  final ValueChanged<String> onPick;
  final String? selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final r in kChatReactions)
          Material(
            color: r.emoji == selected ? cs.secondaryContainer : Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onPick(r.emoji),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: ReactionArt(emoji: r.emoji, size: size, animated: true),
              ),
            ),
          ),
      ],
    );
  }
}

int _bursts = 0;

/// Вспышка реакции в точке касания: рисунок выпрыгивает и тает.
///
/// Двойное касание можно бить часто, поэтому вспышек одновременно не
/// больше трёх: лишние просто не показываются, реакция всё равно ставится.
/// Запись убирается по своему флагу, а не по `mounted` (урок строки копилки).
void showReactionBurst(BuildContext context, String emoji, Offset global) {
  if (_bursts >= 3) return;
  if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _bursts++;
  late final OverlayEntry entry;
  var removed = false;
  void close() {
    if (removed) return;
    removed = true;
    _bursts--;
    entry.remove();
  }

  const size = 96.0;
  entry = OverlayEntry(
    builder: (_) => Positioned(
      left: global.dx - size / 2,
      top: global.dy - size / 2,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 750),
          curve: Curves.linear,
          onEnd: close,
          builder: (_, v, child) {
            // Выпрыгнуть (0..0.3), подержаться, растаять вверх (0.6..1).
            final pop = v < 0.3 ? Curves.easeOutBack.transform(v / 0.3) : 1.0;
            final fade = v < 0.6 ? 1.0 : 1 - (v - 0.6) / 0.4;
            return Transform.translate(
              offset: Offset(0, -24 * (v < 0.6 ? 0 : (v - 0.6) / 0.4)),
              child: Opacity(
                opacity: fade.clamp(0.0, 1.0),
                child: Transform.scale(scale: 0.4 + 0.8 * pop, child: child),
              ),
            );
          },
          child: ReactionArt(emoji: emoji, size: size, animated: true),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  // Страховка: если кадры не рисуются (приложение ушло в фон), всё равно убрать.
  Timer(const Duration(seconds: 2), close);
}
