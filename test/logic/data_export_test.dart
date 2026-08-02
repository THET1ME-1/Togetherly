import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/data_export.dart';

/// Право забрать копию своих данных: закон Молдовы № 133/2011 и GDPR.
/// Здесь проверяется сборка архива — чтобы в него попадало обещанное
/// политикой и не попадали чужие секреты.
void main() {
  final now = DateTime.utc(2026, 8, 2, 15, 30);

  Map<String, dynamic> bundle({Map<String, List<Map<String, dynamic>>>? parts}) =>
      buildExportBundle(
        takenAt: now,
        appVersion: '1.23.0+158',
        uid: 'u1',
        sections: parts ??
            {
              'profile': [
                {'id': 'u1', 'name': 'Саша', 'email': 'sasha@example.com'}
              ],
              'messages': [
                {'id': 'm1', 'text': 'привет', 'ts': 1},
              ],
            },
      );

  group('buildExportBundle', () {
    test('кладёт дату, версию и владельца', () {
      final b = bundle();
      expect(b['taken_at'], '2026-08-02T15:30:00.000Z');
      expect(b['app_version'], '1.23.0+158');
      expect(b['uid'], 'u1');
    });

    test('переносит разделы как есть', () {
      final b = bundle();
      final data = b['data'] as Map<String, dynamic>;
      expect((data['messages'] as List).single['text'], 'привет');
      expect((data['profile'] as List).single['email'], 'sasha@example.com');
    });

    test('считает записи по разделам', () {
      final counts = (bundle()['counts'] as Map<String, dynamic>);
      expect(counts['profile'], 1);
      expect(counts['messages'], 1);
    });

    test('вычищает служебные токены', () {
      // Токен сессии и ключ шифрования кэша в архиве человеку не нужны, а
      // утекают из него легко: файл уходит в мессенджер одним нажатием.
      final b = bundle(parts: {
        'profile': [
          {
            'id': 'u1',
            'name': 'Саша',
            'token': 'секрет',
            'password_hash': 'x',
            'cache_key': 'y',
          }
        ]
      });
      final row = (b['data'] as Map)['profile'][0] as Map<String, dynamic>;
      expect(row.containsKey('token'), isFalse);
      expect(row.containsKey('password_hash'), isFalse);
      expect(row.containsKey('cache_key'), isFalse);
      expect(row['name'], 'Саша');
    });

    test('пустой раздел остаётся в архиве пустым списком', () {
      final b = bundle(parts: {'wishes': const []});
      expect((b['data'] as Map)['wishes'], isEmpty);
      expect((b['counts'] as Map)['wishes'], 0);
    });

    test('архив сериализуется в json', () {
      expect(() => jsonEncode(bundle()), returnsNormally);
    });
  });
}
