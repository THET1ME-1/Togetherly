import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/launch_splash.dart';

const _heart = 'M0.0,19.0 C-3.0,19.0 -6.0,13.1 -9.0,10.0 C-12.0,6.9 -16.2,3.5 -18.0,0.4 '
    'C-19.8,-2.7 -20.2,-5.7 -19.6,-8.4 C-19.0,-11.1 -16.7,-14.6 -14.4,-16.0 '
    'C-12.1,-17.4 -8.4,-17.7 -6.0,-16.8 C-3.6,-15.9 -2.0,-10.4 0.0,-10.4 '
    'C2.0,-10.4 3.6,-15.9 6.0,-16.8 C8.4,-17.7 12.1,-17.4 14.4,-16.0 '
    'C16.7,-14.6 19.0,-11.1 19.6,-8.4 C20.2,-5.7 19.8,-2.7 18.0,0.4 '
    'C16.2,3.5 12.0,6.9 9.0,10.0 C6.0,13.1 3.0,19.0 0.0,19.0 Z';

Map<String, dynamic> _data({String until = '2026-11-01', String from = ''}) => {
      'key': 'hw_key',
      'v': 1,
      'w': 360,
      'h': 780,
      'ms': 60,
      'step': 20,
      'from': from,
      'until': until,
      'sort': 100,
      'night': '#1E1729',
      'name': {'ru': 'Хэллоуин', 'en': 'Halloween', 'zh': '万圣节'},
      'window': {
        'path': _heart,
        'frame': [12, 4],
        'ink': '#2a2d30',
        'track': [
          [180, 372, 0],
          [180, 372, 0],
          [181, 372, 2],
          [182, 372, 40],
        ],
      },
      'sprites': {
        'door': {
          'frames': ['door'],
          'box': [0, 0, 360, 780],
        },
        'key': {
          'frames': ['key0', 'key1', 'key2'],
          'box': [-17.9, -48.7, 35.8, 53.6],
        },
      },
      'layers': [
        {'sprite': 'door', 'fill': true, 'under': true},
        {
          'sprite': 'key',
          'track': [
            [430, 93.6, 6.9, -70, 0, 1],
            [430, 93.6, 6.9, -70, 1, 2],
            [300, 200, 5, -30, 1, 0],
            [180, 366, 3.2, 0, 1, 1],
          ],
        },
      ],
      'files': {
        'door': 'https://togetherly.day/api/files/catalog_items/splash_hw_key/door_a.webp',
        'key0': 'https://x/key0.webp',
        'key1': 'https://x/key1.webp',
        'key2': 'https://x/key2.webp',
        'still': 'https://x/still.webp',
      },
    };

Map<String, dynamic> _row(Map<String, dynamic> data, {String kind = 'splash'}) =>
    {'id': 'splash_hw_key', 'kind': kind, 'data': data};

void main() {
  group('запись каталога', () {
    test('разбирает заставку целиком', () {
      final s = LaunchSplash.fromCatalog(_row(_data()))!;
      expect(s.key, 'hw_key');
      expect(s.ms, 60);
      expect(s.step, 20);
      expect(s.design, const Size(360, 780));
      expect(s.night, const Color(0xFF1E1729));
      expect(s.layers.map((l) => l.sprite), ['door', 'key']);
      expect(s.layers.first.fill, isTrue);
      expect(s.layers.first.under, isTrue);
      expect(s.layers.last.under, isFalse);
      expect(s.sprites['key']!.frames, ['key0', 'key1', 'key2']);
      expect(s.sprites['key']!.box, const Rect.fromLTWH(-17.9, -48.7, 35.8, 53.6));
      expect(s.window.frameWidth, 12);
      expect(s.window.inkWidth, 4);
      expect(s.window.track.length, 4);
      expect(s.stillUrl, 'https://x/still.webp');
      expect(s.fileNames.toSet(), {'door', 'key0', 'key1', 'key2', 'still'});
    });

    test('чужой вид и битые записи не разбираются', () {
      expect(LaunchSplash.fromCatalog(_row(_data(), kind: 'backdrop')), isNull);
      expect(LaunchSplash.fromCatalog({'kind': 'splash', 'data': 'нет'}), isNull);
      expect(LaunchSplash.fromCatalog(_row({..._data(), 'key': ''})), isNull);
      expect(LaunchSplash.fromCatalog(_row({..._data(), 'layers': []})), isNull);
      expect(LaunchSplash.fromCatalog(_row({..._data(), 'ms': 0})), isNull);
    });

    test('слой без рисунка или рисунок без файла — запись не годится', () {
      final noSprite = _data()
        ..['layers'] = [
          {'sprite': 'moon', 'under': true},
        ];
      expect(LaunchSplash.fromCatalog(_row(noSprite)), isNull);
      final noFile = _data();
      (noFile['files'] as Map).remove('key1');
      expect(LaunchSplash.fromCatalog(_row(noFile)), isNull);
    });

    test('окно без пути — запись не годится', () {
      final d = _data();
      (d['window'] as Map)['path'] = 'X1,2';
      expect(LaunchSplash.fromCatalog(_row(d)), isNull);
    });

    test('сохранённая на диске копия разбирается так же', () {
      final s = LaunchSplash.fromCatalog(_row(_data()))!;
      final back = LaunchSplash.fromJson(s.toJson())!;
      expect(back.key, s.key);
      expect(back.layers.last.track[2].x, 300);
      expect(back.window.track.last.scale, 40);
      expect(back.files, s.files);
    });

    test('имя на языке человека, иначе английское', () {
      final s = LaunchSplash.fromCatalog(_row(_data()))!;
      expect(s.nameFor('ru'), 'Хэллоуин');
      expect(s.nameFor('zh'), '万圣节');
      expect(s.nameFor('de'), 'Halloween');
    });
  });

  group('даты', () {
    test('до 1 ноября не включая', () {
      final s = LaunchSplash.fromCatalog(_row(_data()))!;
      expect(s.isOn(DateTime(2026, 10, 31, 23, 59)), isTrue);
      expect(s.isOn(DateTime(2026, 11, 1, 0, 1)), isFalse);
    });

    test('начало включая, пустой конец — без конца', () {
      final s = LaunchSplash.fromCatalog(_row(_data(from: '2026-10-20', until: '')))!;
      expect(s.isOn(DateTime(2026, 10, 19, 23)), isFalse);
      expect(s.isOn(DateTime(2026, 10, 20, 0, 1)), isTrue);
      expect(s.isOn(DateTime(2030, 1, 1)), isTrue);
    });
  });

  group('поза на момент', () {
    final track = LaunchSplash.fromCatalog(_row(_data()))!.layers.last.track;

    test('в узле — ровно узел', () {
      final p = splashPoseAt(track, 20, 40);
      expect(p.x, 300);
      expect(p.scale, 5);
      expect(p.frame, 0);
    });

    test('между узлами — по прямой, кадр нижнего узла', () {
      final p = splashPoseAt(track, 20, 50);
      expect(p.x, closeTo(240, 1e-9));
      expect(p.y, closeTo(283, 1e-9));
      expect(p.rotation, closeTo(-15, 1e-9));
      expect(p.frame, 0);
    });

    test('до начала — первый узел, после конца — последний', () {
      expect(splashPoseAt(track, 20, -5).opacity, 0);
      expect(splashPoseAt(track, 20, 999).x, 180);
    });

    test('появление в одном месте: прозрачность растёт, место не едет', () {
      final p = splashPoseAt(track, 20, 10);
      expect(p.x, 430);
      expect(p.opacity, closeTo(0.5, 1e-9));
    });
  });

  test('запечённый «Ключ» из мастерской разбирается целиком', () {
    final dir = Directory('${Platform.environment['HOME']}/Projects/togetherly-badges-hand/out_splash/hw_key');
    if (!dir.existsSync()) return;
    final spec = jsonDecode(File('${dir.path}/splash.json').readAsStringSync()) as Map<String, dynamic>;
    final files = {
      for (final f in dir.listSync().whereType<File>())
        if (!f.path.endsWith('.json')) f.uri.pathSegments.last.split('.').first: f.path,
    };
    final s = LaunchSplash.fromJson({...spec, 'files': files});
    expect(s, isNotNull);
    expect(s!.ms, 1800);
    expect(s.layers.length, 6);
    expect(s.layers.where((l) => l.under).length, 5, reason: 'дверь, накладка, скважины и щелчок лежат в ночи');
    expect(s.layers.last.sprite, 'key', reason: 'ключ падает поверх открытого окна');
    expect(s.window.track.length, 91);
    expect(s.fileNames.length, 17);
  });

  test('путь сердца замкнут и лежит в своём габарите', () {
    final path = parseSplashPath(_heart)!;
    final b = path.getBounds();
    expect(b.left, closeTo(-20, 0.6));
    expect(b.right, closeTo(20, 0.6));
    expect(b.top, closeTo(-17.5, 0.6));
    expect(b.bottom, closeTo(19, 0.1));
    expect(path.contains(Offset.zero), isTrue);
    expect(parseSplashPath(''), isNull);
    expect(parseSplashPath('M0,0 C1,2'), isNull);
  });
}
