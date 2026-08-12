import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис для обработки deep links
class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._();
  factory DeepLinkService() => _instance;
  DeepLinkService._();

  final _appLinks = AppLinks();
  StreamSubscription? _sub;

  final _inviteCodeController = StreamController<String>.broadcast();
  Stream<String> get inviteCodeStream => _inviteCodeController.stream;

  // Буфер последнего инвайт-кода. На холодном старте ссылка/QR приходят ДО
  // того, как смонтируется экран подключения (он строится on-demand, не в
  // IndexedStack), а broadcast-стрим не отдаёт прошлые события новым
  // подписчикам → код терялся, приглашение по ссылке не принималось. Экран
  // при монтировании забирает буфер через consumePendingInviteCode().
  String? _pendingInviteCode;
  String? consumePendingInviteCode() {
    final c = _pendingInviteCode;
    _pendingInviteCode = null;
    return c;
  }

  final _emailLinkController =
      StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get emailLinkStream =>
      _emailLinkController.stream;

  // Действия с виджетов рабочего стола: отметить настроение, сказать «скучаю»,
  // открыть листик. Виджет шлёт их ссылкой `loveapp://mood?id=…`, и на Android
  // её ловит home_widget. На iPhone так не выходит: схему `loveapp://` первым
  // разбирает app_links, цепочка на этом кончается, и до `widgetClicked` ссылка
  // не доезжает — приложение просто открывалось, а настроение не ставилось.
  // Поэтому раздаём такие ссылки отсюда, из единственного места, куда они
  // приходят наверняка.
  static const _widgetHosts = {'mood', 'miss', 'note', 'memories', 'widgets'};

  /// Ссылка с виджета рабочего стола, а не приглашение и не письмо.
  static bool isWidgetAction(Uri uri) =>
      uri.scheme == 'loveapp' && _widgetHosts.contains(uri.host);

  final _widgetActionController = StreamController<Uri>.broadcast();
  Stream<Uri> get widgetActionStream => _widgetActionController.stream;

  // На холодном старте главная монтируется позже, чем приходит ссылка, а
  // broadcast-поток прошлых событий не отдаёт: без буфера тап по виджету на
  // закрытом приложении терялся целиком.
  Uri? _pendingWidgetAction;
  Uri? consumePendingWidgetAction() {
    final u = _pendingWidgetAction;
    _pendingWidgetAction = null;
    return u;
  }

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
    // https://togetherly-d4856.web.app/invite/ABC123   ← основной рабочий домен
    // https://togetherly.app/invite/ABC123             ← будущий домен
    // https://togetherly-d4856.web.app/?oobCode=...    ← email link

    if (isWidgetAction(uri)) {
      _pendingWidgetAction = uri;
      _widgetActionController.add(uri);
      return;
    }

    if (uri.scheme == 'loveapp' && uri.host == 'invite') {
      // loveapp://invite/ABC123
      final code = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      if (code != null && code.length == 6) {
        _pendingInviteCode = code.toUpperCase();
        _inviteCodeController.add(code.toUpperCase());
      }
      return;
    }

    if (uri.scheme == 'https') {
      final isFirebaseHost = uri.host == 'togetherly-d4856.web.app';
      // togetherly.duckdns.org — живой PocketBase-VPS (обслуживает инвайт-лендинг
      // после гашения Firebase Hosting). togetherly.app — будущий домен.
      final isMainHost = uri.host == 'togetherly.app' ||
          uri.host == 'togetherly.duckdns.org' ||
          uri.host == 'togetherly.day';
      final isInvitePath = uri.pathSegments.isNotEmpty &&
          uri.pathSegments.first == 'invite';

      if ((isFirebaseHost || isMainHost) && isInvitePath) {
        // https://<host>/invite/ABC123
        final code =
            uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
        if (code != null && code.length == 6) {
          debugPrint('DeepLinkService: invite code from web link: $code');
          _pendingInviteCode = code.toUpperCase();
          _inviteCodeController.add(code.toUpperCase());
        }
        return;
      }

      if (isFirebaseHost) {
        // Остальные ссылки с Firebase Hosting — email link
        debugPrint('DeepLinkService: email link from Firebase domain');
        _handleEmailLink(uri.toString());
      }
    }
  }

  Future<void> _handleEmailLink(String emailLink) async {
    try {
      // Получаем сохраненный email из SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('emailForSignIn');

      if (email != null && email.isNotEmpty) {
        debugPrint('Found saved email for sign-in: $email');
        _emailLinkController.add({'email': email, 'link': emailLink});
      } else {
        debugPrint('No saved email found, will need to prompt user');
        _emailLinkController.add({'email': '', 'link': emailLink});
      }
    } catch (e) {
      debugPrint('Error handling email link: $e');
    }
  }

  void dispose() {
    _sub?.cancel();
    _inviteCodeController.close();
    _emailLinkController.close();
  }
}
