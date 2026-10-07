import 'package:flutter/material.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../connect_expressive.dart' show M3ShapeClipper;
import '../storage_image.dart';

/// Ролик снят стоя: TikTok, Shorts, Reels, клипы ВК, Rutube Shorts.
///
/// Такой кадр в 16:9 превращается в узкую полосу посередине, поэтому пин
/// показывает его 4:5.
bool isVerticalVideo(String url) {
  final u = url.toLowerCase();
  return u.contains('tiktok.com') ||
      u.contains('youtube.com/shorts/') ||
      u.contains('instagram.com/reel') ||
      RegExp(r'(vk\.com|vkvideo\.ru)/clip').hasMatch(u) ||
      u.contains('rutube.ru/shorts/') ||
      u.contains('dzen.ru/shorts/');
}

/// Пропорции кадра. Вертикальный ролик — 4:5, но только с обложкой: у роликов
/// TikTok из совместной ленты обложки нет, и пустой высокий блок занимал бы
/// пол-экрана ленты.
double videoPinAspect(String url, {required bool hasThumb}) =>
    hasThumb && isVerticalVideo(url) ? 4 / 5 : 16 / 9;

/// Видео-пин ленты воспоминаний: вариант «Подпись на кадре» из макета
/// https://claude.ai/artifact/QGsLW5j6wQ21rGpBtT6dbz (07.10.2026).
///
/// Прежний пин был карточкой в карточке с рамкой, кнопками фирменного цвета
/// площадки и, кроме YouTube, кадром 80×56. Теперь кадр лежит прямо на
/// карточке, площадку называет пилюля в углу, название — пилюля на кадре, а
/// действия собраны связанной группой кнопок M3 Expressive. Все цвета — роли
/// схемы темы.
///
/// Что происходит по нажатию, решает лента: YouTube играет прямо в карточке
/// ([player] подменяет кадр), остальные площадки открываются снаружи.
class VideoPin extends StatelessWidget {
  const VideoPin({
    super.key,
    required this.scheme,
    required this.fill,
    required this.url,
    required this.platformName,
    required this.platformIcon,
    required this.onPlay,
    required this.onOpen,
    this.onWatchTogether,
    this.thumbUrl,
    this.title,
    this.author,
    this.caption,
    this.player,
  });

  final ColorScheme scheme;

  /// Заливка главной кнопки и кнопки «играть» — `AppTheme.fillColor`.
  final Color fill;
  final String url;
  final String platformName;
  final IconData platformIcon;
  final VoidCallback onPlay;
  final VoidCallback onOpen;

  /// Совместный просмотр; null — кнопки нет, остаётся одна «Открыть в …».
  final VoidCallback? onWatchTogether;
  final String? thumbUrl;
  final String? title;
  final String? author;
  final String? caption;

  /// Плеер, когда ролик уже играет в карточке.
  final Widget? player;

  static const double _frameRadius = 20;

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final vertical = videoPinAspect(url, hasThumb: thumbUrl?.isNotEmpty == true) < 1;
    final name = title?.trim().isNotEmpty == true ? title!.trim() : s.video;
    final cap = caption?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (player != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(_frameRadius),
            child: player,
          )
        else
          _frame(name, vertical),
        if (cap.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            cap,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Onest',
              fontSize: 14,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 10),
        _actions(s),
      ],
    );
  }

  Widget _frame(String name, bool vertical) {
    // Без обложки кадр — тональная заливка. Значка площадки посередине нет:
    // он лёг бы под «играть», а площадку и так называет пилюля в углу.
    final empty = ColoredBox(color: scheme.surfaceContainerHighest);
    final thumb = thumbUrl?.isNotEmpty == true ? thumbUrl! : null;
    final aspect = videoPinAspect(url, hasThumb: thumb != null);
    return GestureDetector(
      onTap: onPlay,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_frameRadius),
        child: AspectRatio(
          aspectRatio: aspect,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumb != null)
                StorageImage(
                  imageUrl: thumb,
                  fit: BoxFit.cover,
                  memCacheWidth: 720,
                  errorWidget: (_, _, _) => empty,
                )
              else
                empty,
              Positioned(left: 10, top: 10, child: _platformPill()),
              // «Играть» выше центра: снизу кадр занимает подпись.
              Align(
                alignment: Alignment(0, vertical ? -0.22 : -0.34),
                child: _playButton(),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: _titlePill(name, vertical),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _platformPill() => Container(
        height: 28,
        padding: const EdgeInsets.only(left: 7, right: 10),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(platformIcon, size: 16, color: scheme.onSecondaryContainer),
            const SizedBox(width: 4),
            Text(
              platformName,
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      );

  Widget _playButton() {
    final onFill = AppThemes.onColor(fill, mode: scheme.brightness);
    return SizedBox(
      key: const ValueKey('video-pin-play'),
      width: 64,
      height: 64,
      child: ClipPath(
        clipper: M3ShapeClipper(MaterialShapes.cookie9Sided),
        child: ColoredBox(
          color: fill,
          child: Icon(Icons.play_arrow_rounded, size: 36, color: onFill),
        ),
      ),
    );
  }

  Widget _titlePill(String name, bool vertical) {
    final who = author?.trim() ?? '';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: vertical ? 10 : 8),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            // На горизонтальном кадре одна строка: две закрыли бы «играть».
            maxLines: vertical ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Onest',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.25,
              color: scheme.onInverseSurface,
            ),
          ),
          if (who.isNotEmpty)
            Text(
              who,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 12,
                height: 1.3,
                color: scheme.onInverseSurface.withValues(alpha: 0.8),
              ),
            ),
        ],
      ),
    );
  }

  /// Связанная группа M3E: внешние углы полные, внутренние 8, зазор 2.
  Widget _actions(AppStrings s) {
    final onFill = AppThemes.onColor(fill, mode: scheme.brightness);
    final openLabel = s.openIn(platformName);
    if (onWatchTogether == null) {
      return _GroupButton(
        color: fill,
        foreground: onFill,
        icon: Icons.open_in_new_rounded,
        label: openLabel,
        radius: const BorderRadius.all(Radius.circular(24)),
        onTap: onOpen,
      );
    }
    return Row(
      children: [
        Expanded(
          child: _GroupButton(
            color: fill,
            foreground: onFill,
            icon: Icons.people_alt_rounded,
            label: s.watchTogether,
            radius: const BorderRadius.horizontal(
              left: Radius.circular(24),
              right: Radius.circular(8),
            ),
            onTap: onWatchTogether!,
          ),
        ),
        const SizedBox(width: 2),
        Tooltip(
          message: openLabel,
          child: SizedBox(
            width: 56,
            child: _GroupButton(
              color: scheme.secondaryContainer,
              foreground: scheme.onSecondaryContainer,
              icon: Icons.open_in_new_rounded,
              radius: const BorderRadius.horizontal(
                left: Radius.circular(8),
                right: Radius.circular(24),
              ),
              onTap: onOpen,
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupButton extends StatelessWidget {
  const _GroupButton({
    required this.color,
    required this.foreground,
    required this.icon,
    required this.radius,
    required this.onTap,
    this.label,
  });

  final Color color;
  final Color foreground;
  final IconData icon;
  final BorderRadius radius;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final text = label;
    return Material(
      color: color,
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              // Крупный системный шрифт на 320 точках: надпись ужимается,
              // а не обрезается и не переносится.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20, color: foreground),
                    if (text != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        text,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: 'Onest',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: foreground,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
