import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Метаданные трека по ссылке: название, исполнитель, обложка.
///
/// Раньше эта логика жила двумя копиями — в ленте воспоминаний и в экране
/// виджетов, — и копии разошлись: в виджете Яндекс.Музыку разбирал парсер по
/// `<title>`, который подставлял в поля «Яндекс Музыка» и «собираем музыку для
/// вас». Отсюда жалоба «в парный виджет автора и название приходится вводить
/// самому», хотя в ленте то же самое подтягивалось само.
class MusicMetaService {
  MusicMetaService._();
  static final MusicMetaService instance = MusicMetaService._();

  /// Пустой ответ значит «не узнали»: поля заполнит человек.
  Future<Map<String, String?>> fetch(String url) async {
    final trimmed = url.trim();
    if (!trimmed.startsWith('http')) return {};
    if (trimmed.toLowerCase().contains('music.yandex.')) {
      final meta = await _fetchYandex(trimmed);
      if (meta.isNotEmpty) return meta;
    }
    return _fetchFromServices(trimmed);
  }

  /// Яндекс.Музыка страницу отдаёт пустой: ни `og`, ни `ld+json` в ответе нет
  /// ни для браузерного User-Agent, ни для ботов (проверено с ноутбука и с
  /// нашего VPS). Разбирать нечего, поэтому идём в их API по номеру трека.
  ///
  /// За пределами России api.music.yandex.net отвечает 451, поэтому при отказе
  /// повторяем запрос через свой сервер — он стоит в Тамбове и видит API.
  Future<Map<String, String?>> _fetchYandex(String url) async {
    final id = yandexTrackId(url);
    if (id == null) return {};
    final direct = await _yandexApi('https://api.music.yandex.net/tracks/$id');
    if (direct.isNotEmpty) return direct;
    return _yandexApi('$pbBaseUrl/api/music/yandex?track=$id');
  }

  /// Адрес своего PocketBase. Держим строкой, чтобы сервис не тянул за собой
  /// весь клиент PB ради одного запроса.
  static const String pbBaseUrl = String.fromEnvironment(
    'PB_URL',
    defaultValue: 'https://togetherly.day',
  );

  /// Номер трека из ссылки: `/album/<id>/track/<id>`, `/track/<id>`.
  static String? yandexTrackId(String url) {
    final m = RegExp(r'/track/(\d+)').firstMatch(url);
    return m?.group(1);
  }

  /// Разбор ответа api.music.yandex.net. Вынесен отдельно и без сети, чтобы
  /// формат ответа проверялся тестом, а не живым запросом к Яндексу.
  static Map<String, String?> parseYandexTrack(dynamic data) {
    final result = (data is Map ? data['result'] : null);
    final track = (result is List && result.isNotEmpty) ? result.first : null;
    if (track is! Map) return {};

    final title = track['title'] as String?;
    final artists =
        (track['artists'] as List?)
            ?.whereType<Map>()
            .map((a) => a['name'])
            .whereType<String>()
            .join(', ') ??
        '';
    // coverUri приходит с плейсхолдером размера: `…/%%` → просим 400×400.
    final rawCover = track['coverUri'] as String?;
    final cover = (rawCover == null || rawCover.isEmpty)
        ? null
        : 'https://${rawCover.replaceAll('%%', '400x400')}';

    if ((title == null || title.isEmpty) && artists.isEmpty) return {};
    return {
      'title': title,
      'artist': artists.isEmpty ? null : artists,
      'cover': cover,
    };
  }

  Future<Map<String, String?>> _yandexApi(String endpoint) async {
    try {
      final resp = await http
          .get(Uri.parse(endpoint), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return {};
      return parseYandexTrack(json.decode(utf8.decode(resp.bodyBytes)));
    } catch (e) {
      debugPrint('Yandex Music API error: $e');
      return {};
    }
  }

  Future<Map<String, String?>> _fetchFromServices(String url) async {
    final lower = url.toLowerCase();

    // ── YouTube / YouTube Music (official oEmbed — no API key required) ──
    if (lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.contains('music.youtube.com')) {
      try {
        final resp = await http.get(
          Uri.parse(
            'https://www.youtube.com/oembed?url=${Uri.encodeComponent(url)}&format=json',
          ),
        );
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          return {
            'title': data['title'] as String?,
            'artist': data['author_name'] as String?,
            'cover': data['thumbnail_url'] as String?,
          };
        }
      } catch (e) {
        debugPrint('YouTube meta fetch error: $e');
      }
      return {};
    }

    // ── Spotify ──
    if (lower.contains('spotify.com')) {
      try {
        final oembedResp = await http.get(
          Uri.parse(
            'https://open.spotify.com/oembed?url=${Uri.encodeComponent(url)}',
          ),
          headers: {'User-Agent': 'Mozilla/5.0'},
        );
        String? parsedTitle;
        String? parsedArtist;
        String? cover;

        if (oembedResp.statusCode == 200) {
          final data = json.decode(oembedResp.body) as Map<String, dynamic>;
          parsedTitle = data['title'] as String?;
          cover = data['thumbnail_url'] as String?;
        }

        try {
          final pageResp = await http.get(
            Uri.parse(url),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          );
          if (pageResp.statusCode == 200) {
            final body = pageResp.body;
            final titleMatch = RegExp(
              r'<title[^>]*>(.+?)</title>',
              caseSensitive: false,
            ).firstMatch(body);
            if (titleMatch != null) {
              final pageTitle = titleMatch.group(1) ?? '';
              final byMatch = RegExp(
                r'(?:song and lyrics|[Aa]lbum|single)\s+by\s+(.+?)\s*\|\s*Spotify',
              ).firstMatch(pageTitle);
              if (byMatch != null) {
                parsedArtist = byMatch.group(1)?.trim();
              }
            }
          }
        } catch (_) {}

        return {'title': parsedTitle, 'artist': parsedArtist, 'cover': cover};
      } catch (e) {
        debugPrint('Spotify meta fetch error: $e');
      }
    }

    // ── Deezer ──
    final isDeezer =
        lower.contains('deezer.com') ||
        lower.contains('deezer.page.link') ||
        lower.contains('link.deezer.com');
    if (isDeezer) {
      try {
        // Resolve short/dynamic links → actual deezer.com/track/ URL
        String resolvedUrl = url;
        final isShortLink =
            lower.contains('deezer.page.link') ||
            lower.contains('link.deezer.com');
        if (isShortLink) {
          try {
            String current = url;
            for (int i = 0; i < 5; i++) {
              final httpClient = HttpClient();
              httpClient.connectionTimeout = const Duration(seconds: 6);
              final req = await httpClient.getUrl(Uri.parse(current));
              req.followRedirects = false;
              final resp = await req.close();
              final location = resp.headers.value('location');
              httpClient.close();
              if (location == null || location.isEmpty) break;
              current = location;
              if (current.toLowerCase().contains('deezer.com/') &&
                  current.toLowerCase().contains('/track/')) {
                resolvedUrl = current;
                break;
              }
              resolvedUrl = current;
            }
          } catch (_) {}
        }
        final resolvedLower = resolvedUrl.toLowerCase();

        final trackMatch = RegExp(
          r'deezer\.com/(?:[^/?#]+/)*track/(\d+)',
        ).firstMatch(resolvedLower);
        if (trackMatch != null) {
          final trackId = trackMatch.group(1);
          final apiResp = await http.get(
            Uri.parse('https://api.deezer.com/track/$trackId'),
            headers: {'Accept': 'application/json'},
          );
          if (apiResp.statusCode == 200) {
            final data = json.decode(apiResp.body) as Map<String, dynamic>;
            if (data['error'] == null) {
              return {
                'title': data['title'] as String?,
                'artist':
                    (data['artist'] as Map<String, dynamic>?)?['name']
                        as String?,
                'cover':
                    (data['album'] as Map<String, dynamic>?)?['cover_big']
                        as String?,
              };
            }
          }
        }
        // Fallback to oEmbed (works with both full and resolved URLs)
        final oembedResp = await http.get(
          Uri.parse(
            'https://noembed.com/embed?url=${Uri.encodeComponent(resolvedUrl)}',
          ),
        );
        if (oembedResp.statusCode == 200) {
          final data = json.decode(oembedResp.body) as Map<String, dynamic>;
          if (data['error'] == null && data['title'] != null) {
            return {
              'title': data['title'] as String?,
              'artist': data['author_name'] as String?,
              'cover': data['thumbnail_url'] as String?,
            };
          }
        }
      } catch (e) {
        debugPrint('Deezer meta fetch error: $e');
      }
    }

    // ── SoundCloud ──
    if (lower.contains('soundcloud.com')) {
      try {
        final oembedResp = await http.get(
          Uri.parse(
            'https://soundcloud.com/oembed?url=${Uri.encodeComponent(url)}&format=json',
          ),
        );
        if (oembedResp.statusCode == 200) {
          final data = json.decode(oembedResp.body) as Map<String, dynamic>;
          return {
            'title': data['title'] as String?,
            'artist': data['author_name'] as String?,
            'cover': data['thumbnail_url'] as String?,
          };
        }
      } catch (e) {
        debugPrint('SoundCloud meta fetch error: $e');
      }
    }

    // ── Яндекс Музыка ──
    if (lower.contains('music.yandex.')) {
      try {
        final pageResp = await http.get(
          Uri.parse(url),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        );
        if (pageResp.statusCode == 200) {
          final body = pageResp.body;
          String? title;
          String? artist;
          String? cover;

          // 1. Самый надёжный источник — структурированные данные ld+json
          //    (MusicRecording: name, byArtist.name, thumbnailUrl).
          for (final m in RegExp(
            r'<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>',
            caseSensitive: false,
            dotAll: true,
          ).allMatches(body)) {
            try {
              final ld = json.decode(m.group(1)!.trim());
              if (ld is! Map<String, dynamic>) continue;
              if (ld['name'] is String) title = ld['name'] as String;
              final byArtist = ld['byArtist'];
              if (byArtist is Map && byArtist['name'] is String) {
                artist = byArtist['name'] as String;
              } else if (byArtist is List && byArtist.isNotEmpty) {
                artist = byArtist
                    .whereType<Map>()
                    .map((a) => a['name'])
                    .whereType<String>()
                    .join(', ');
              }
              if (ld['thumbnailUrl'] is String) {
                cover = ld['thumbnailUrl'] as String;
              }
              if (title != null) break;
            } catch (_) {}
          }

          // 2. Fallback на Open Graph / описание.
          String? ogContent(String prop) => RegExp(
            'property="$prop"\\s+content="([^"]*)"',
            caseSensitive: false,
          ).firstMatch(body)?.group(1);

          title ??= ogContent('og:title');
          // og:image отдаёт обложку нужного размера (m1000x1000).
          final ogImage = ogContent('og:image');
          if (ogImage != null && ogImage.isNotEmpty) cover = ogImage;
          // og:description формата "Artist • Трек • 2026" → берём исполнителя.
          if (artist == null || artist.isEmpty) {
            final desc = ogContent('og:description');
            if (desc != null && desc.contains('•')) {
              artist = desc.split('•').first.trim();
            }
          }

          if ((title != null && title.isNotEmpty) ||
              (cover != null && cover.isNotEmpty)) {
            return {
              'title': title != null ? _decodeHtmlEntities(title) : null,
              'artist': artist != null ? _decodeHtmlEntities(artist) : null,
              'cover': cover,
            };
          }
        }
      } catch (e) {
        debugPrint('Yandex Music meta fetch error: $e');
      }
    }

    // ── Apple Music ──
    if (lower.contains('music.apple.com')) {
      try {
        // Extract track ID from ?i= parameter (highest priority)
        final trackIdMatch = RegExp(r'[?&]i=(\d+)').firstMatch(url);
        // Fallback: last numeric segment in the path (album/song ID)
        final pathIdMatch = RegExp(
          r'/(\d+)(?:[?#/]|$)',
        ).allMatches(url).lastOrNull;
        final lookupId = trackIdMatch?.group(1) ?? pathIdMatch?.group(1);
        if (lookupId != null) {
          final resp = await http.get(
            Uri.parse(
              'https://itunes.apple.com/lookup?id=$lookupId&entity=song',
            ),
          );
          if (resp.statusCode == 200) {
            final data = json.decode(resp.body) as Map<String, dynamic>;
            final results = data['results'] as List?;
            if (results != null && results.isNotEmpty) {
              final track =
                  results.firstWhere(
                        (r) => r['wrapperType'] == 'track',
                        orElse: () => results.first,
                      )
                      as Map<String, dynamic>;
              return {
                'title': track['trackName'] as String?,
                'artist': track['artistName'] as String?,
                'cover': track['artworkUrl100'] as String?,
              };
            }
          }
        }
      } catch (e) {
        debugPrint('Apple Music meta fetch error: $e');
      }
    }

    // ── VK Музыка ──
    if (lower.contains('vk.com/music') ||
        lower.contains('vk.com/audio') ||
        lower.contains('vk.ru/music')) {
      try {
        final pageResp = await http.get(
          Uri.parse(url),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)',
          },
        );
        if (pageResp.statusCode == 200) {
          final body = pageResp.body;
          String? ogContent(String prop) => RegExp(
            'property="$prop"\\s+content="([^"]*)"',
            caseSensitive: false,
          ).firstMatch(body)?.group(1);

          final title = ogContent('og:title');
          final image = ogContent('og:image');
          final desc = ogContent('og:description');

          String? artist;
          if (desc != null && desc.contains(' — ')) {
            artist = desc.split(' — ').first.trim();
          }

          if (title != null && title.isNotEmpty) {
            return {
              'title': _decodeHtmlEntities(title),
              'artist': artist != null ? _decodeHtmlEntities(artist) : null,
              'cover': image,
            };
          }
        }
      } catch (e) {
        debugPrint('VK Music meta fetch error: $e');
      }
    }

    // ── Tidal ──
    if (lower.contains('tidal.com')) {
      try {
        // Tidal serves pre-rendered OG tags to social media bots
        final pageResp = await http.get(
          Uri.parse(url),
          headers: {'User-Agent': 'Twitterbot/1.0'},
        );
        if (pageResp.statusCode == 200) {
          final body = pageResp.body;
          final ogTitleMatch = RegExp(
            r'property="og:title"\s+content="([^"]+)"',
            caseSensitive: false,
          ).firstMatch(body);
          final ogImageMatch = RegExp(
            r'property="og:image"\s+content="([^"]+)"',
            caseSensitive: false,
          ).firstMatch(body);
          if (ogTitleMatch != null) {
            // Format: "Artist - Title"
            final raw = _decodeHtmlEntities(ogTitleMatch.group(1) ?? '');
            final sepIdx = raw.indexOf(' - ');
            if (sepIdx != -1) {
              return {
                'title': raw.substring(sepIdx + 3).trim(),
                'artist': raw.substring(0, sepIdx).trim(),
                'cover': ogImageMatch?.group(1),
              };
            }
            return {
              'title': raw.isNotEmpty ? raw : null,
              'artist': null,
              'cover': ogImageMatch?.group(1),
            };
          }
        }
      } catch (e) {
        debugPrint('Tidal meta fetch error: $e');
      }
    }

    // ── Generic fallback — noembed.com (works for many services) ──
    try {
      final oembedResp = await http.get(
        Uri.parse('https://noembed.com/embed?url=${Uri.encodeComponent(url)}'),
      );
      if (oembedResp.statusCode == 200) {
        final data = json.decode(oembedResp.body) as Map<String, dynamic>;
        if (data['error'] == null) {
          return {
            'title': data['title'] as String?,
            'artist': data['author_name'] as String?,
            'cover': data['thumbnail_url'] as String?,
          };
        }
      }
    } catch (_) {}

    return {};
  }

  String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&nbsp;', ' ');
  }
}
