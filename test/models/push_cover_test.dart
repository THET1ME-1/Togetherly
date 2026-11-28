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
      final ctx = memoryCoverContext(
          {'title': 'Тайна', 'imageUrl': 'pb://media/r/p.webp', key: true}, 'Алина');
      expect(ctx, {'from_name': 'Алина'}, reason: key);
      final cover = buildPushCover('memory', 'ru', ctx, look)!;
      expect(cover['art'], {'app': true});
      expect(jsonEncode(cover), isNot(contains('Тайна')));
    }
    expect(memoryCoverContext({'title': ' Крыша ', 'imageUrl': 'pb://media/r/p.webp'}, 'А'),
        {'from_name': 'А', 'title': 'Крыша', 'photo': 'pb://media/r/p.webp'});
  });

  test('язык: незнакомый и пустой — русский, как у сервера', () {
    expect(buildPushCover('miss', 'be', const {'body': 'x'}, look)!['kicker'], 'Скучаю · Партнёр');
    expect(buildPushCover('miss', '', const {'body': 'x'}, look)!['kicker'], 'Скучаю · Партнёр');
    expect(buildPushCover('miss', 'en_US', const {'body': 'x'}, look)!['kicker'],
        'Missing you · Partner');
  });
}
