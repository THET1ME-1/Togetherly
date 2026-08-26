/// Возврат «голого» адреса файла PocketBase к схеме `pb://`.
///
/// Файлы `media` защищённые: без `?token=` сервер отвечает 404. Токен
/// подставляется только к ссылкам вида `pb://media/<id>/<файл>`, а в записях с
/// давних пор попадаются и готовые `https://togetherly.day/api/files/media/…`
/// — за две недели 152 таких запроса ушли в пустоту у 58 человек, и картинка
/// просто не открывалась. Приведя адрес обратно к схеме, показ идёт общим
/// путём и получает свежий токен.
library;

/// Домены, чьи файловые адреса наши.
///
/// `duckdns` — легаси: такие ссылки разосланы людьми и лежат в старых записях,
/// понимать их обязаны, даже когда сами больше не выдаём.
const List<String> kPbFileHosts = [
  'togetherly.day',
  'togetherly.duckdns.org',
];

/// `pb://<коллекция>/<id>/<файл>` для адреса [url], если он наш файловый.
///
/// Возвращает `null` для всего остального: чужих доменов, страниц, обрезанных
/// путей и уже готовых `pb://`-ссылок — их резолвит обычный путь.
String? pbRefFromUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (!url.startsWith('http://') && !url.startsWith('https://')) return null;

  final Uri uri;
  try {
    uri = Uri.parse(url);
  } catch (_) {
    return null;
  }
  if (!kPbFileHosts.contains(uri.host)) return null;

  final seg = uri.pathSegments;
  // /api/files/<коллекция>/<id>/<файл> — короче быть не может: без имени файла
  // адрес всё равно никуда не ведёт.
  if (seg.length < 5) return null;
  if (seg[0] != 'api' || seg[1] != 'files') return null;

  final rest = seg.sublist(2).join('/');
  return 'pb://$rest';
}
