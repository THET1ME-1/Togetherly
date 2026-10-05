/// Обложка ролика по ссылке на площадку, когда своей у записи нет.
///
/// У ссылок на ролики обложка почти никогда не сохраняется (oEmbed на
/// шеринге её не отдаёт): за сентябрь 2026 года без неё 1540 записей из
/// 1542. Площадки отдают кадр открытым адресом по номеру ролика, без ключа:
/// YouTube — `i.ytimg.com`, Rutube — свой API с переадресацией на картинку.
/// У ВК и остальных открытой обложки нет — пустая строка.
String videoLinkThumb(String url) {
  final Uri u;
  try {
    u = Uri.parse(url.trim());
  } catch (_) {
    return '';
  }
  if (u.scheme != 'https' && u.scheme != 'http') return '';
  final host = u.host.toLowerCase().replaceFirst(RegExp(r'^(www|m)\.'), '');

  final yt = _youtubeId(host, u);
  if (yt != null) return 'https://i.ytimg.com/vi/$yt/hqdefault.jpg';

  if (host == 'rutube.ru' || host.endsWith('.rutube.ru')) {
    final m = RegExp(r'/(?:video|shorts)/([0-9a-f]{32})').firstMatch(u.path);
    if (m != null) return 'https://rutube.ru/api/video/${m.group(1)}/thumbnail/?redirect=1';
  }
  return '';
}

final _ytIdShape = RegExp(r'^[A-Za-z0-9_-]{11}$');

String? _youtubeId(String host, Uri u) {
  String? id;
  if (host == 'youtu.be') {
    id = u.pathSegments.isEmpty ? null : u.pathSegments.first;
  } else if (host == 'youtube.com' || host == 'music.youtube.com') {
    id = u.queryParameters['v'];
    if (id == null) {
      final m = RegExp(r'^/(?:shorts|embed|live)/([^/?#]+)').firstMatch(u.path);
      id = m?.group(1);
    }
  }
  return id != null && _ytIdShape.hasMatch(id) ? id : null;
}
