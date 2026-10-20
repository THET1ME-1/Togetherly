import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../models/launch_splash.dart';
import '../../services/launch_splash_service.dart';
import 'launch_splash_view.dart';

/// Заставка при запуске поверх всего приложения. Играет один раз за запуск,
/// пока под ней поднимается приложение; касания к нему не пропускает и по
/// концу уходит целиком.
///
/// Какую заставку играть, решает `main()` до `runApp` (только диск):
/// кладёт её в [pending]. Картинки разжимаются уже здесь, и пока они
/// разжимаются, приложение закрыто ночью заставки.
class LaunchSplashOverlay extends StatefulWidget {
  const LaunchSplashOverlay({super.key, required this.child});

  final Widget child;

  /// Заставка этого запуска; забирается первым же оверлеем.
  static LaunchSplash? pending;

  /// Дольше картинки не ждём: лучше запуск без заставки, чем ночь на экране.
  static const Duration decodeLimit = Duration(milliseconds: 1500);

  @override
  State<LaunchSplashOverlay> createState() => _LaunchSplashOverlayState();
}

class _LaunchSplashOverlayState extends State<LaunchSplashOverlay> {
  LaunchSplash? _splash;
  Map<String, ui.Image>? _images;
  bool _gone = false;

  bool _started = false;

  @override
  void initState() {
    super.initState();
    _splash = LaunchSplashOverlay.pending;
    LaunchSplashOverlay.pending = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final splash = _splash;
    if (_started || splash == null) return;
    _started = true;
    // При «уменьшить движение» заставка не играет, и разжимать её незачем.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _gone = true;
      return;
    }
    unawaited(_decode(splash));
  }

  Future<void> _decode(LaunchSplash splash) async {
    Map<String, ui.Image>? images;
    try {
      images = await LaunchSplashService.decode(splash).timeout(LaunchSplashOverlay.decodeLimit);
    } catch (e) {
      debugPrint('LaunchSplash: не разжать картинки: $e');
    }
    if (!mounted || _gone) {
      _free(images);
      return;
    }
    setState(() {
      if (images == null) {
        _gone = true;
      } else {
        _images = images;
      }
    });
  }

  void _finish() {
    if (!mounted) return;
    final images = _images;
    setState(() {
      _gone = true;
      _images = null;
    });
    // Картинки отпускаем после кадра, на котором заставки уже нет.
    WidgetsBinding.instance.addPostFrameCallback((_) => _free(images));
  }

  void _free(Map<String, ui.Image>? images) {
    if (images == null) return;
    for (final image in images.values) {
      image.dispose();
    }
  }

  @override
  void dispose() {
    _free(_images);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final splash = _splash;
    final showing = splash != null && !_gone;
    final images = _images;
    // Приложение всегда первым ребёнком одного и того же Stack: иначе уход
    // заставки пересоздал бы навигатор со всеми экранами.
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        if (showing)
          Positioned.fill(
            child: AbsorbPointer(
              child: images == null
                  ? ColoredBox(color: splash.night)
                  : LaunchSplashView(splash: splash, images: images, onDone: _finish),
            ),
          ),
      ],
    );
  }
}
