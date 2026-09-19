// Поиск фильмов идёт через свой сервер, poiskkino остался запасным.
//
// 19.09.2026: общий ключ poiskkino (200 запросов в сутки на всех) выгорал к
// обеду, и фильмы не мог добавить никто. Сервер ищет в Викиданных и отдаёт
// ответ в той же форме, что poiskkino, — приложение читает его прежним
// разбором. Не ответил сервер (старый, упал, нет сети до него) — приложение
// идёт в poiskkino само, как раньше.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:love_app/services/movie_search_service.dart';

const _base = 'https://togetherly.day';

http.Response _json(Object body, int code) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      code,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

const _serverDoc = {
  'id': 258687,
  'name': 'Интерстеллар',
  'alternativeName': 'Interstellar',
  'year': 2014,
  'type': 'movie',
  'poster': {
    'url': 'https://st.kp.yandex.net/images/film_iphone/iphone360_258687.jpg',
    'previewUrl':
        'https://st.kp.yandex.net/images/film_iphone/iphone360_258687.jpg',
  },
  'genres': [
    {'name': 'фантастика'},
    {'name': 'драма'},
  ],
  'countries': [
    {'name': 'США'},
  ],
  'link': 'https://www.kinopoisk.ru/film/258687/',
};

const _poiskkinoDoc = {
  'id': 301,
  'name': 'Матрица',
  'alternativeName': 'The Matrix',
  'year': 1999,
  'type': 'movie',
};

class _Calls {
  final List<Uri> uris = [];
  final List<Map<String, String>> headers = [];
}

MockClient _client(_Calls calls, http.Response Function(Uri) server) =>
    MockClient((req) async {
      calls.uris.add(req.url);
      calls.headers.add(req.headers);
      if (req.url.host == 'api.poiskkino.dev') {
        return _json({
          'docs': [_poiskkinoDoc]
        }, 200);
      }
      return server(req.url);
    });

void main() {
  group('свой сервер', () {
    test('ответ сервера читается прежним разбором', () async {
      final calls = _Calls();
      final res = await MovieSearchService.searchWith(
        'интерстеллар',
        base: _base,
        token: 'tok',
        lang: 'ru',
        client: _client(calls, (_) => _json({
              'docs': [_serverDoc],
              'source': 'wikidata'
            }, 200)),
      );
      expect(res, hasLength(1));
      final m = res.single;
      expect(m.title, 'Интерстеллар');
      expect(m.originalTitle, 'Interstellar');
      expect(m.year, '2014');
      expect(m.genres, 'фантастика, драма');
      expect(m.country, 'США');
      expect(m.infoUrl, 'https://www.kinopoisk.ru/film/258687/');
      expect(calls.uris.any((u) => u.host == 'api.poiskkino.dev'), isFalse,
          reason: 'сервер ответил — в poiskkino ходить незачем');
    });

    test('запрос несёт сессию и язык человека', () async {
      final calls = _Calls();
      await MovieSearchService.searchWith(
        'друзья',
        base: _base,
        token: 'tok',
        lang: 'de',
        client: _client(calls, (_) => _json({'docs': []}, 200)),
      );
      final u = calls.uris.first;
      expect(u.path, '/api/movies/search');
      expect(u.queryParameters['q'], 'друзья');
      expect(u.queryParameters['lang'], 'de');
      expect(calls.headers.first['Authorization'], 'tok');
    });

    test('сервер ничего не нашёл — это ответ, а не повод идти в poiskkino',
        () async {
      final calls = _Calls();
      final res = await MovieSearchService.searchWith(
        'ыыыфыв',
        base: _base,
        token: 'tok',
        lang: 'ru',
        client: _client(calls, (_) => _json({'docs': [], 'source': 'none'}, 200)),
      );
      expect(res, isEmpty);
      expect(calls.uris.any((u) => u.host == 'api.poiskkino.dev'), isFalse);
    });

    test('частые поиски — это лимит, а не поломка', () async {
      await expectLater(
        MovieSearchService.searchWith(
          'гарри',
          base: _base,
          token: 'tok',
          lang: 'ru',
          client: _client(_Calls(), (_) => _json({'code': 429}, 429)),
        ),
        throwsA(isA<MovieSearchException>()
            .having((e) => e.rateLimited, 'rateLimited', isTrue)),
      );
    });

    test('источники выгорели — тоже лимит', () async {
      await expectLater(
        MovieSearchService.searchWith(
          'гарри',
          base: _base,
          token: 'tok',
          lang: 'ru',
          client: _client(
              _Calls(),
              (_) => _json({
                    'code': 503,
                    'data': {'reason': 'quota'}
                  }, 503)),
        ),
        throwsA(isA<MovieSearchException>()
            .having((e) => e.rateLimited, 'rateLimited', isTrue)),
      );
    });
  });

  group('запасной путь', () {
    for (final code in [404, 401, 500, 502]) {
      test('сервер ответил $code — ищем в poiskkino', () async {
        final calls = _Calls();
        final res = await MovieSearchService.searchWith(
          'матрица',
          base: _base,
          token: 'tok',
          lang: 'ru',
          client: _client(calls, (_) => _json({'code': code}, code)),
        );
        expect(res.single.title, 'Матрица');
        expect(res.single.infoUrl, 'https://www.kinopoisk.ru/film/301/');
      });
    }

    test('сервер недоступен — ищем в poiskkino', () async {
      final res = await MovieSearchService.searchWith(
        'матрица',
        base: _base,
        token: 'tok',
        lang: 'ru',
        client: MockClient((req) async {
          if (req.url.host == 'api.poiskkino.dev') {
            return _json({
              'docs': [_poiskkinoDoc]
            }, 200);
          }
          throw http.ClientException('connection refused');
        }),
      );
      expect(res.single.title, 'Матрица');
    });

    test('без сессии сервер не спрашиваем', () async {
      final calls = _Calls();
      await MovieSearchService.searchWith(
        'матрица',
        base: _base,
        token: '',
        lang: 'ru',
        client: _client(calls, (_) => fail('сервер без сессии ответит 401')),
      );
      expect(calls.uris.single.host, 'api.poiskkino.dev');
    });
  });

  group('ссылка на карточку', () {
    test('без номера Кинопоиска ведёт туда, куда дал сервер', () {
      final m = MovieResult.fromKinopoiskDoc({
        'id': 0,
        'name': 'Наруто',
        'type': 'movie',
        'link': 'https://www.imdb.com/title/tt1234567/',
      });
      expect(m.infoUrl, 'https://www.imdb.com/title/tt1234567/');
    });

    test('ни номера, ни ссылки — ссылки нет, а не kinopoisk.ru/film/0', () {
      final m = MovieResult.fromKinopoiskDoc({'id': 0, 'name': 'X'});
      expect(m.infoUrl, isNull);
    });
  });
}
