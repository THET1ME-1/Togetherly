import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:app_links/app_links.dart';

/// Сервис для обработки deep links
class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._();
  factory DeepLinkService() => _instance;
  DeepLinkService._();

  final _appLinks = AppLinks();
  StreamSubscription? _sub;

  final _inviteCodeController = StreamController<String>.broadcast();
  Stream<String> get inviteCodeStream => _inviteCodeController.stream;

  /// Инициализация — проверяем начальную ссылку и слушаем новые
  Future<void> init() async {
    try {
      // Проверяем начальную ссылку (если приложение открыто из ссылки)
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleUri(initialUri);
      }

      // Слушаем входящие ссылки (когда приложение уже запущено)
      _sub = _appLinks.uriLinkStream.listen(
        _handleUri,
        onError: (err) => debugPrint('Deep link error: $err'),
      );

      debugPrint('DeepLinkService: initialized');
    } catch (e) {
      debugPrint('DeepLinkService init failed: $e');
    }
  }

  void _handleUri(Uri uri) {
    debugPrint('Deep link received: $uri');

    // Поддерживаемые форматы:
    // loveapp://invite/ABC123
    // https://togetherly.app/invite/ABC123

    if (uri.scheme == 'loveapp' && uri.host == 'invite') {
      // loveapp://invite/ABC123
      final code = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      if (code != null && code.length == 6) {
        _inviteCodeController.add(code.toUpperCase());
      }
    } else if (uri.scheme == 'https' &&
        uri.host == 'togetherly.app' &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first == 'invite') {
      // https://togetherly.app/invite/ABC123
      final code = uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
      if (code != null && code.length == 6) {
        _inviteCodeController.add(code.toUpperCase());
      }
    }
  }

  void dispose() {
    _sub?.cancel();
    _inviteCodeController.close();
  }
}
