import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/push_cover.dart';

/// Каталог примеров как у сервера: ссылка на `still_*` из файлов записи,
/// котики «Моти» из `data.moods`, радиус фото под рамкой из `data.hole`.
class _FixtureLook implements CoverLook {
  _FixtureLook(this.catalog);
  final Map<String, dynamic> catalog;

  static const _files = 'https://togetherly.day/api/files';

  @override
  String? still(String id) {
    final row = catalog[id] as List?;
    if (row == null) return null;
    for (final name in row[0] as List) {
      if ('$name'.startsWith('still_')) return '$_files/catalog_items/$id/$name';
    }
    return null;
  }

  @override
  String? moti(String moodId) {
    final row = catalog['moti'] as List?;
    for (final m in (row?[1] as Map?)?['moods'] as List? ?? const []) {
      if ((m as Map)['id'] == moodId) return m['url'] as String?;
    }
    return null;
  }

  @override
  double frameHole(String key) {
    final hole = ((catalog['frame_$key'] as List?)?[1] as Map?)?['hole'];
    return hole is num ? hole.toDouble().clamp(18, 31).toDouble() : 31;
  }
}

void main() {
  final data = jsonDecode(File('test/fixtures/push_cover_cases.json').readAsStringSync())
      as Map<String, dynamic>;
  final look = _FixtureLook(data['catalog'] as Map<String, dynamic>);

  test('обложка совпадает с серверной во всех примерах', () {
    final cases = data['cases'] as List;
    expect(cases.length, greaterThanOrEqualTo(20));
    for (final c in cases) {
      final kind = c['kind'] as String;
      final got = buildPushCover(kind, c['lang'] as String,
          Map<String, Object?>.from(c['ctx'] as Map), look);
      // Через JSON: числа и списки сравниваются так же, как их увидит Kotlin.
      expect(jsonDecode(jsonEncode(got)), c['cover'], reason: '$kind/${c['lang']}');
    }
  });

  test('незнакомый вид — без обложки, уведомление по-старому', () {
    expect(buildPushCover('wallet', 'ru', const {}, look), isNull);
  });

  test('закрытое воспоминание — без фото и названия', () {
    for (final key in ['isSecret', 'isAdult', 'sealed']) {
      final ctx = memoryCoverContext({
        'title': 'Тайна', 'imageUrl': 'pb://media/r/p.webp', 'musicCoverUrl': 'https://x/a.jpg',
        'locationName': 'Дом', key: true,
      }, 'Алина', id: 'm1');
      // Номер записи остаётся: по нему открывается лента, а не содержимое.
      expect(ctx, {'from_name': 'Алина', 'memory_id': 'm1'}, reason: key);
      final cover = buildPushCover('memory', 'ru', ctx, look)!;
      expect(cover['art'], {'app': true});
      expect(jsonEncode(cover), isNot(contains('Тайна')));
    }
    expect(memoryCoverContext({'title': ' Крыша ', 'imageUrl': 'pb://media/r/p.webp'}, 'А', id: 'm2'), {
      'from_name': 'А', 'title': 'Крыша', 'photo': 'pb://media/r/p.webp', 'cover': '', 'place': '',
      'memory_id': 'm2',
    });
  });

  test('воспоминание как у сервера: фото из списка, обложка трека, значок места', () {
    // Те же правила, что `memory_ctx` в push_cover.py.
    expect(memoryCoverContext({'imageUrls': ['pb://media/r/1.webp'], 'musicCoverUrl': 'https://x/a.jpg'}, 'А')['photo'],
        'pb://media/r/1.webp');
    final song = memoryCoverContext({'title': 'Песня', 'musicCoverUrl': 'https://x/a.jpg'}, 'А', id: 'm3');
    expect(buildPushCover('memory', 'ru', song, look)!['art'], {'url': 'https://x/a.jpg'});
    final place = memoryCoverContext({'locationName': 'Кафе', 'latitude': 47.0}, 'А', id: 'm4');
    expect(buildPushCover('memory', 'ru', place, look)!['art'], {'symbol': 'location_on'});
  });

  test('язык: незнакомый и пустой — русский, как у сервера', () {
    expect(buildPushCover('miss', 'be', const {'body': 'x'}, look)!['kicker'], 'Скучаю · Партнёр');
    expect(buildPushCover('miss', '', const {'body': 'x'}, look)!['kicker'], 'Скучаю · Партнёр');
    expect(buildPushCover('miss', 'en_US', const {'body': 'x'}, look)!['kicker'],
        'Missing you · Partner');
  });
}
