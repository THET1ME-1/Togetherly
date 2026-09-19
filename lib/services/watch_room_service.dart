import 'dart:convert';

import 'package:http/http.dart' as http;

import 'pocketbase_service.dart';

/// Комната совместного просмотра.
///
/// Код комнаты выдаёт сервер по связи пары, а не придумывает клиент: оба
/// устройства спрашивают его сами и молча оказываются в одной комнате. Тот же
/// код зовёт партнёра в браузер — на сайте комната ровно та же.
class WatchRoomService {
  WatchRoomService._();

  static final Map<String, String> _cache = {};

  /// Сколько букв имени доезжает до комнаты. Длиннее в строке сообщения всё
  /// равно не помещается, а адрес раздувает.
  static const int maxNameLength = 32;

  /// Сайт с играми для пары — «Правда или действие» и прочее на одном
  /// телефоне. Живёт отдельной статикой на первом сервере, кода комнаты не
  /// спрашивает: играют вдвоём с одного экрана, а не по сети.
  static const String gamesUrl = 'https://games.togetherly.day/';

  /// Адрес комнаты на сайте для кода [room].
  ///
  /// [src] — ссылка на ролик, который надо включить сразу после входа. Комната
  /// применит её, когда поднимется канал, и объявит партнёру. Ссылку для
  /// партнёра (копирование, «поделиться») берём без [src] — там свой выбор.
  ///
  /// [name] — как подписывать свои сообщения в чате комнаты. Без него страница
  /// подставляет «Гость» обоим, и человек не понимает, кто с ним смотрит
  /// (жалоба тестера: «партнёр отображается как гость»).
  static String siteUrl(String room, {String? src, String? name}) {
    final base = 'https://$siteHost/watch/room/';
    final query = <String, String>{};
    if (src != null && src.isNotEmpty) query['src'] = src;
    final trimmed = (name ?? '').trim();
    if (trimmed.isNotEmpty) {
      query['name'] = trimmed.length > maxNameLength
          ? trimmed.substring(0, maxNameLength)
          : trimmed;
    }
    if (query.isEmpty) return '$base#$room';
    final encoded = query.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$base?$encoded#$room';
  }

  /// Скрипт, который отдаёт странице комнаты нашу сессию.
  ///
  /// С 16.09.2026 в комнату пары пускают только её участников: к паре зашли
  /// посторонние, узнавшие код. Браузер доказывает участие входом, а
  /// встроенному браузеру приложения входить незачем — сессия у нас уже есть.
  /// Страница читает `window.__togetherlyAuth` и шлёт токен при запросе
  /// пропуска (`storedAuth` в `room.js`).
  ///
  /// Скрипт срабатывает только на нашем домене: если WebView уведут на чужую
  /// страницу, токен туда не попадёт.
  static String authScript({required String token, String? name}) {
    final data = jsonEncode({'token': token, 'name': (name ?? '').trim()});
    return '(function(){'
        "if(location.hostname!=='$siteHost')return;"
        'window.__togetherlyAuth=$data;'
        '})();';
  }

  /// Домен страницы комнаты — единственный, которому отдаём сессию.
  static const String siteHost = 'togetherly.day';

  /// Код комнаты пары. Пустая строка означает отказ сервера — вызывающий
  /// показывает ошибку и не открывает просмотр.
  static Future<String> roomCode(String groupId) async {
    if (groupId.isEmpty) return '';
    final cached = _cache[groupId];
    if (cached != null) return cached;

    final pb = PocketBaseService.instance.pb;
    final token = pb.authStore.token;
    if (token.isEmpty) return '';

    try {
      final res = await http
          .post(
            Uri.parse('${PocketBaseService.baseUrl}/api/watch/room'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': token,
            },
            body: jsonEncode({'groupId': groupId}),
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) return '';
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final room = (data['room'] ?? '').toString();
      if (room.isNotEmpty) _cache[groupId] = room;
      return room;
    } catch (_) {
      return '';
    }
  }
}
