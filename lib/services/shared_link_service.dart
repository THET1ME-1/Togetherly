import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/shared_link.dart';

/// Ссылка, которой поделились в приложение из магазина или браузера.
///
/// Товар в «Хочу с тобой» обычно и приходит ссылкой, а копипаст с телефона —
/// работа на минуту, которую никто не делает. Здесь ссылка ловится из
/// системного «Поделиться» и уезжает в форму вещи.
///
/// Плагина под это нет намеренно: `receive_sharing_intent` 1.9 собран под
/// старый Kotlin-DSL и валит сборку Android на `kotlin()` в своём
/// build.gradle. Приёмник живёт в `MainActivity`, сюда текст приходит каналом.
///
/// Буфер на обеих сторонах обязателен: на холодном старте интент приходит
/// раньше, чем поднимется движок Flutter и смонтируется главная, а
/// broadcast-поток прошлых событий новым подписчикам не отдаёт — ровно та же
/// грабля, что была с инвайт-кодом в `DeepLinkService`.
class SharedLinkService {
  SharedLinkService._();
  static final SharedLinkService instance = SharedLinkService._();
  factory SharedLinkService() => instance;

  static const MethodChannel _channel = MethodChannel('love_app/shared_text');

  final _controller = StreamController<String>.broadcast();

  /// Ссылки из «Поделиться», уже очищенные от подписи магазина.
  Stream<String> get linkStream => _controller.stream;

  String? _pending;

  /// Забрать ссылку, пришедшую до того, как экран успел подписаться.
  String? consumePending() {
    final link = _pending;
    _pending = null;
    return link;
  }

  Future<void> init() async {
    // Приёмник есть только на Android: на iOS «Поделиться» требует отдельного
    // расширения в проекте Xcode, и его тут нет.
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared') _accept(call.arguments?.toString() ?? '');
      return null;
    });
    try {
      final initial = await _channel.invokeMethod<String>('consumePending');
      if (initial != null) _accept(initial);
      debugPrint('SharedLinkService: initialized');
    } catch (e) {
      debugPrint('SharedLinkService init failed: $e');
    }
  }

  void _accept(String text) {
    // Магазины шлют «название, перенос строки, адрес», браузеры — голый адрес.
    final url = extractSharedUrl(text);
    if (url.isEmpty) return;
    _pending = url;
    _controller.add(url);
  }
}
