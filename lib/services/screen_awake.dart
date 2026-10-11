import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Экран не гаснет, пока человек смотрит видео.
///
/// Система считает бездействием всё, кроме касаний: человек смотрит фильм, а
/// экран гаснет по своему таймеру (жалоба 12.10.2026, Xiaomi). Ни плагин
/// `video_player`, ни встроенный браузер комнаты сами экран не держат —
/// просить об этом должно приложение.
///
/// Держателей считаем: плеер ролика открывается поверх комнаты, и закрытый
/// плеер не должен отпустить экран, пока комната ещё на нём.
///
/// Нативные половины — канал `love_app/screen_awake`: на Android это
/// `FLAG_KEEP_SCREEN_ON` у окна (`MainActivity.kt`), на iPhone —
/// `isIdleTimerDisabled` (`AppDelegate.swift`). Отдельного разрешения не
/// нужно: флаг действует, только пока приложение на экране.
abstract final class ScreenAwake {
  static const MethodChannel _channel = MethodChannel('love_app/screen_awake');

  static final Set<Object> _holders = <Object>{};

  static Future<void> Function(bool on) _apply = _native;

  static Future<void> _native(bool on) =>
      _channel.invokeMethod<void>('set', {'on': on});

  /// Держит ли кто-нибудь экран прямо сейчас.
  static bool get held => _holders.isNotEmpty;

  /// [who] просит не гасить экран. Повтор от того же держателя ничего не
  /// меняет.
  static void hold(Object who) {
    final first = _holders.isEmpty;
    if (!_holders.add(who)) return;
    if (first) _set(true);
  }

  /// [who] экран больше не нужен. Удержание снимается, когда отпустили все.
  static void release(Object who) {
    if (!_holders.remove(who)) return;
    if (_holders.isEmpty) _set(false);
  }

  /// Для плеера: держать, пока видео играет, отпустить на паузе.
  static void sync(Object who, {required bool playing}) =>
      playing ? hold(who) : release(who);

  static void _set(bool on) {
    // Отказ натива (нет окна, старая сборка без канала) плееру не помеха:
    // видео играет и без удержания.
    try {
      _apply(on).catchError((Object _) {});
    } catch (_) {}
  }

  @visibleForTesting
  static void debugReset(Future<void> Function(bool on)? apply) {
    _holders.clear();
    _apply = apply ?? _native;
  }
}
