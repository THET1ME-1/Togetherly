import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/banner_cache.dart';

/// Баннер профиля со скруглённым низом. Один виджет для своего профиля
/// (с кнопкой смены) и профиля партнёра (только показ). Источник по приоритету:
/// сетевой URL (синк, виден партнёру) → локальный файл (легаси) → тональный фон.
///
/// Сетевой баннер идёт через [BannerCache]: с сервера он качается один раз,
/// дальше берётся с диска, пока человек не поставит новый.
class ProfileBanner extends StatelessWidget {
  final String bannerUrl;
  final String? localPath;
  final Color background;
  final double height;
  final VoidCallback? onPick; // задан → показываем кнопку смены (свой профиль)

  /// Идёт ли GIF по кругу.
  ///
  /// Анимированный баннер — вещь Togetherly+ (`BannerGif`): пока у владельца
  /// Плюс открыт (куплен или идёт неделя из сундука), GIF шевелится, без него
  /// стоит первым кадром. Картинку человек не теряет, а неделя из сундука не
  /// оставляет платное навсегда. Обычной картинке флаг ничего не делает.
  final bool animate;

  const ProfileBanner({
    super.key,
    this.bannerUrl = '',
    this.localPath,
    required this.background,
    this.height = 168,
    this.onPick,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget? img;
    if (bannerUrl.isNotEmpty) {
      img = _CachedBanner(url: bannerUrl);
    } else if (localPath != null) {
      img = Image.file(
        File(localPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        color: background,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Под выключенным TickerMode Flutter показывает первый кадр GIF и
          // дальше не листает.
          if (img != null) TickerMode(enabled: animate, child: img),
          if (onPick != null)
            Positioned(
              top: 12,
              right: 12,
              child: GestureDetector(
                onTap: onPick,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.30),
                  ),
                  child: const Icon(Icons.photo_camera_rounded,
                      size: 18, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Баннер с сервера через [BannerCache].
///
/// Без проявления: оно тикало бы от того же TickerMode, что и кадры GIF, и под
/// остановленным застывший баннер остался бы прозрачным. С диска файл и так
/// приходит сразу.
class _CachedBanner extends StatefulWidget {
  const _CachedBanner({required this.url});

  final String url;

  @override
  State<_CachedBanner> createState() => _CachedBannerState();
}

class _CachedBannerState extends State<_CachedBanner> {
  File? _file;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_CachedBanner old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _load();
  }

  /// Уже виденный в этом запуске файл ставим сразу. Новый ждём, не убирая
  /// прежний: при смене баннера шапка не мигает пустым фоном.
  void _load() {
    final url = widget.url;
    final known = BannerCache.instance.known(url);
    if (known != null) {
      _file = known;
      return;
    }
    BannerCache.instance.file(url).then((file) {
      if (!mounted || widget.url != url || file == null) return;
      setState(() => _file = file);
    });
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file == null) return const SizedBox.shrink();
    return Image.file(
      file,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}
