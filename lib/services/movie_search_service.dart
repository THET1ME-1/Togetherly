import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'locale_service.dart';
import 'pocketbase_service.dart';

/// Поиск фильмов и сериалов.
///
/// Первым спрашиваем свой сервер (`/api/movies/search` в hotpath): он ищет в
/// Викиданных, ужимает ответ и кэширует его. Ответ приходит в той же форме,
/// что у poiskkino.dev, поэтому разбор один — [MovieResult.fromKinopoiskDoc].
///
/// Зачем (19.09.2026): раньше телефон ходил прямо в poiskkino одним общим
/// ключом из APK, а бесплатный тариф — 200 запросов в сутки на всех. К обеду
/// ключ выгорал, и фильмы не мог добавить никто. Платный тариф дорог, TMDB
/// запрещает коммерцию, Викиданные отдают всё под CC0 без ключа.
///
/// Прямой поход в poiskkino остался запасным путём: сервер старый, упал, нет
/// сессии или сети до него. Ключ по-прежнему можно подменить при сборке:
/// `--dart-define=KINOPOISK_TOKEN=...`.
class MovieSearchService {
  MovieSearchService._();

  // Токен из --dart-define имеет приоритет над захардкоженным.
  static const String _envToken = String.fromEnvironment('KINOPOISK_TOKEN');

  /// Бесплатный токен poiskkino.dev (получен через @poiskkinodev_bot).
  static const String _fallbackToken = 'TM3RQXB-DCZMAJ5-GF7RGGM-NSKB7JS';

  static String get _token => _envToken.isNotEmpty ? _envToken : _fallbackToken;

  /// `true`, если токен задан — иначе форма уходит в ручной ввод.
  static bool get isConfigured => _token.trim().isNotEmpty;

  /// Первый поиск на сервере ходит в Викиданные и может занять пару секунд.
  static const Duration _serverTimeout = Duration(seconds: 25);

  /// Ищет фильмы/сериалы по названию (на любом языке).
  ///
  /// Бросает [MovieSearchException] при сетевой/серверной ошибке, чтобы форма
  /// показала запасной путь «ввести вручную».
  static Future<List<MovieResult>> search(String query) {
    final pb = PocketBaseService.instance.pb;
    return searchWith(
      query,
      base: pb.baseURL,
      token: pb.authStore.token,
      lang: LocaleService.instance.language.code,
    );
  }

  /// То же, что [search], но всё нужное передаётся явно — так его проверяют
  /// тесты с подставным HTTP-клиентом.
  @visibleForTesting
  static Future<List<MovieResult>> searchWith(
    String query, {
    required String base,
    required String token,
    required String lang,
    http.Client? client,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final c = client ?? http.Client();
    try {
      if (token.isNotEmpty) {
        final viaServer = await _viaServer(c, q, base, token, lang);
        if (viaServer != null) return viaServer;
      }
      return await _viaPoiskkino(c, q);
    } finally {
      if (client == null) c.close();
    }
  }

  /// Ответ своего сервера, или `null`, если идти надо в poiskkino самим.
  static Future<List<MovieResult>?> _viaServer(
    http.Client c,
    String q,
    String base,
    String token,
    String lang,
  ) async {
    final uri = Uri.parse('$base/api/movies/search')
        .replace(queryParameters: {'q': q, 'lang': lang});
    final http.Response resp;
    try {
      resp = await c
          .get(uri, headers: {'Authorization': token, 'accept': 'application/json'})
          .timeout(_serverTimeout);
    } catch (e) {
      debugPrint('[MovieSearch] сервер не ответил: $e');
      return null;
    }
    // Слишком часто ищет — лимит на человека; 503 с `quota` — Викиданные не
    // ответили, а запасной ключ на сегодня кончился. Прямой поход в poiskkino
    // упрётся в тот же ключ, поэтому говорим про лимит сразу.
    if (resp.statusCode == 429) {
      throw const MovieSearchException(rateLimited: true);
    }
    if (resp.statusCode == 503 && _reason(resp) == 'quota') {
      throw const MovieSearchException(rateLimited: true);
    }
    if (resp.statusCode != 200) {
      debugPrint('[MovieSearch] сервер ${resp.statusCode}, иду в poiskkino');
      return null;
    }
    try {
      return _parseDocs(resp);
    } catch (e) {
      debugPrint('[MovieSearch] ответ сервера не разобрался: $e');
      return null;
    }
  }

  static String? _reason(http.Response resp) {
    try {
      final body = json.decode(utf8.decode(resp.bodyBytes));
      final data = body is Map ? body['data'] : null;
      return data is Map ? data['reason']?.toString() : null;
    } catch (_) {
      return null;
    }
  }

  static List<MovieResult> _parseDocs(http.Response resp) {
    final data = json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final docs = (data['docs'] as List?) ?? const [];
    return docs
        .whereType<Map<String, dynamic>>()
        .map(MovieResult.fromKinopoiskDoc)
        .where((m) => m.title.isNotEmpty)
        .toList();
  }

  static Future<List<MovieResult>> _viaPoiskkino(http.Client c, String q) async {
    if (!isConfigured) {
      throw const MovieSearchException(notConfigured: true);
    }

    // v1.4 /movie/search — текстовый поиск по релевантности, отдаёт и фильмы,
    // и сериалы.
    final uri = Uri.https('api.poiskkino.dev', '/v1.4/movie/search', {
      'page': '1',
      'limit': '25',
      'query': q,
    });
    debugPrint('[MovieSearch] GET $uri');
    try {
      final resp = await c.get(
        uri,
        headers: {
          'accept': 'application/json',
          'X-API-KEY': _token,
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint('[MovieSearch] ← ${resp.statusCode}, ${resp.body.length} bytes');
      // 401 — ключ не тот. 403 у poiskkino.dev значит другое: «вы израсходовали
      // ваш суточный лимит по запросам». Ключ один на всех, и к вечеру он
      // выгорает, а наутро оживает. Смешивать это с «нет ключа» нельзя:
      // человек читал «поиск недоступен» и считал, что сломано навсегда
      // (жалоба от 25.08.2026 со скриншотом «Гарри Поттер»).
      if (resp.statusCode == 401) {
        throw const MovieSearchException(unauthorized: true);
      }
      if (resp.statusCode == 403) {
        throw const MovieSearchException(rateLimited: true);
      }
      if (resp.statusCode != 200) {
        throw MovieSearchException(message: 'HTTP ${resp.statusCode}');
      }
      final parsed = _parseDocs(resp);
      debugPrint('[MovieSearch] parsed ${parsed.length} titles');
      return parsed;
    } on MovieSearchException {
      rethrow;
    } on TimeoutException {
      throw const MovieSearchException(message: 'timeout');
    } catch (e, st) {
      debugPrint('[MovieSearch] error: $e\n$st');
      throw MovieSearchException(message: e.toString());
    }
  }
}

/// Ошибка поиска — несёт причину для подходящего сообщения в UI.
class MovieSearchException implements Exception {
  final bool notConfigured; // токен не задан
  final bool unauthorized; // токен неверный / просрочен
  final bool rateLimited; // суточный лимит ключа исчерпан, завтра оживёт
  final String? message;

  const MovieSearchException({
    this.notConfigured = false,
    this.unauthorized = false,
    this.rateLimited = false,
    this.message,
  });

  @override
  String toString() =>
      'MovieSearchException(notConfigured: $notConfigured, '
      'unauthorized: $unauthorized, rateLimited: $rateLimited, '
      'message: $message)';
}

/// Один фильм/сериал из результатов поиска (свой сервер или poiskkino).
class MovieResult {
  final int id;

  /// Локализованное (русское) название. Если его нет — оригинальное.
  final String title;

  /// Оригинальное / английское название (если отличается от [title]).
  final String? originalTitle;

  final String? posterUrl;

  /// Год выпуска. Для сериалов — диапазон «2018–2022», если известен.
  final String? year;

  /// Сырой тип kinopoisk: movie / tv-series / cartoon / anime / animated-series.
  final String kind;

  final String? genres; // «драма, мелодрама»
  final String? country; // основная страна
  final String? ratingKp; // рейтинг КП, напр. «7.5»
  final String? description;

  /// Ссылка на карточку, когда номера Кинопоиска нет: IMDb или Викиданные.
  final String? link;

  const MovieResult({
    required this.id,
    required this.title,
    this.originalTitle,
    this.posterUrl,
    this.year,
    required this.kind,
    this.genres,
    this.country,
    this.ratingKp,
    this.description,
    this.link,
  });

  bool get isSeries =>
      kind == 'tv-series' || kind == 'animated-series' || kind == 'anime';

  /// `true`, если основное название на кириллице.
  bool get isRussianTitle => _cyr.hasMatch(title);

  /// Ссылка на карточку: Кинопоиск по номеру, иначе то, что дал источник.
  String? get infoUrl {
    if (link != null && link!.isNotEmpty) return link;
    return id > 0 ? 'https://www.kinopoisk.ru/film/$id/' : null;
  }

  factory MovieResult.fromKinopoiskDoc(Map<String, dynamic> doc) {
    final ruName = (doc['name'] as String?)?.trim();
    final altName = (doc['alternativeName'] as String?)?.trim();
    final enName = (doc['enName'] as String?)?.trim();
    // Приоритет — русское название. Если его нет, берём оригинальное.
    final original = (altName?.isNotEmpty == true ? altName : enName);
    final title =
        (ruName?.isNotEmpty == true ? ruName! : (original ?? '')).trim();

    final yearRaw = doc['year'];
    String? year = (yearRaw is num) ? yearRaw.toInt().toString() : null;
    // Для сериалов API может отдавать диапазон в releaseYears.
    final releaseYears = doc['releaseYears'];
    if (releaseYears is List && releaseYears.isNotEmpty) {
      final ry = releaseYears.first;
      if (ry is Map) {
        final start = ry['start'];
        final end = ry['end'];
        if (start is num) {
          year = end is num
              ? (end == start ? '$start' : '$start–$end')
              : '$start–…';
        }
      }
    }

    String? poster;
    final posterObj = doc['poster'];
    if (posterObj is Map) {
      poster = (posterObj['previewUrl'] ?? posterObj['url']) as String?;
    }

    final genres = (doc['genres'] as List?)
        ?.whereType<Map>()
        .map((g) => g['name']?.toString() ?? '')
        .where((g) => g.isNotEmpty)
        .take(3)
        .join(', ');

    String? country;
    final countries = doc['countries'];
    if (countries is List && countries.isNotEmpty) {
      final first = countries.first;
      if (first is Map) country = first['name']?.toString();
    }

    String? ratingKp;
    final rating = doc['rating'];
    if (rating is Map) {
      final kp = rating['kp'];
      if (kp is num && kp > 0) ratingKp = kp.toStringAsFixed(1);
    }

    return MovieResult(
      id: (doc['id'] as num?)?.toInt() ?? 0,
      title: title,
      // originalTitle храним только если реально отличается от заголовка.
      originalTitle: (original != null && original.isNotEmpty && original != title)
          ? original
          : null,
      posterUrl: (poster != null && poster.isNotEmpty) ? poster : null,
      year: year,
      kind: (doc['type'] as String?) ?? 'movie',
      genres: (genres != null && genres.isNotEmpty) ? genres : null,
      country: country,
      ratingKp: ratingKp,
      description: (doc['shortDescription'] as String?)?.trim().isNotEmpty == true
          ? (doc['shortDescription'] as String).trim()
          : (doc['description'] as String?)?.trim(),
      link: (doc['link'] as String?)?.trim().isNotEmpty == true
          ? (doc['link'] as String).trim()
          : null,
    );
  }

  static final RegExp _cyr = RegExp(r'[Ѐ-ӿ]');
}

/// Человекочитаемая метка типа («Фильм» / «Сериал» / «Мультфильм» / «Аниме»).
String movieKindLabel(String? kind, {required bool isRu}) {
  switch (kind) {
    case 'tv-series':
      return isRu ? 'Сериал' : 'Series';
    case 'cartoon':
      return isRu ? 'Мультфильм' : 'Cartoon';
    case 'animated-series':
      return isRu ? 'Мультсериал' : 'Animated series';
    case 'anime':
      return isRu ? 'Аниме' : 'Anime';
    case 'movie':
    default:
      return isRu ? 'Фильм' : 'Movie';
  }
}
