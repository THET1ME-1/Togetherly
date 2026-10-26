import 'package:flutter/services.dart';

/// Окно на время режима «кино» в комнате просмотра (TOG-43, обращение 488).
///
/// Страница растягивает кадр сама, а строкой состояния, кнопками навигации и
/// поворотом распоряжается приложение. Без этого «кино» на Android шло с
/// панелями и полями, а стоя — узкой полосой посередине: телефон с выключенным
/// автоповоротом набок не ложился. Как у YouTube, ложится сам.
class CinemaChrome {
  const CinemaChrome._();

  static Future<void> enter() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  /// Пустой список — поворот снова решает телефон, как во всём приложении.
  static Future<void> leave() async {
    await SystemChrome.setPreferredOrientations(const []);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}
