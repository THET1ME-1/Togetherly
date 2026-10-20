import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../services/launch_splash_service.dart';
import 'launch_splash_view.dart';

/// Заставка при запуске поверх всего приложения. Играет один раз за запуск,
/// пока под ней поднимается приложение; касания к нему не пропускает и по
/// концу уходит целиком.
///
/// Картинки разжимает `main()` до `runApp` ([LaunchSplashService.prepareLaunch])
/// и кладёт в [pending]. Пока они разжимаются, на экране системная заставка
/// с иконкой, поэтому сцена начинается с первого кадра Flutter. Первый
/// вариант разжимал их здесь под тёмной ночью: на эмуляторе ночь висела две
/// секунды и уходила, сцены так и не случилось (20.10.2026).
class LaunchSplashOverlay extends StatefulWidget {
  const LaunchSplashOverlay({super.key, required this.child});

  final Widget child;

  /// Заставка этого запуска; забирается первым же оверлеем.
  static LaunchSplashReady? pending;

  @override
  State<LaunchSplashOverlay> createState() => _LaunchSplashOverlayState();
}

class _LaunchSplashOverlayState extends State<LaunchSplashOverlay> {
  LaunchSplashReady? _ready;

  @override
  void initState() {
    super.initState();
    _ready = LaunchSplashOverlay.pending;
    LaunchSplashOverlay.pending = null;
  }

  void _finish() {
    if (!mounted) return;
    final images = _ready?.images;
    setState(() => _ready = null);
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
    _free(_ready?.images);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ready;
    // Приложение всегда первым ребёнком одного и того же Stack: иначе уход
    // заставки пересоздал бы навигатор со всеми экранами.
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        if (ready != null)
          Positioned.fill(
            child: AbsorbPointer(
              child: LaunchSplashView(splash: ready.splash, images: ready.images, onDone: _finish),
            ),
          ),
      ],
    );
  }
}
