import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/launch_splash.dart';
import 'package:love_app/services/launch_splash_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _heart = 'M0,19 C-10,10 -20,0 -18,-10 C-14,-18 -4,-16 0,-10 C4,-16 14,-18 18,-10 C20,0 10,10 0,19 Z';

LaunchSplash _splash({String until = '2026-11-01', String suffix = 'a'}) => LaunchSplash.fromCatalog({
      'kind': 'splash',
      'data': {
        'key': 'hw_key',
        'ms': 1800,
        'step': 20,
        'until': until,
        'night': '#1E1729',
        'window': {
          'path': _heart,
          'track': [
            [180, 372, 0],
          ],
        },
        'sprites': {
          'door': {
            'frames': ['door'],
            'box': [0, 0, 360, 780],
          },
          'key': {
            'frames': ['key0', 'key1'],
            'box': [-18, -49, 36, 54],
          },
        },
        'layers': [
          {'sprite': 'door', 'fill': true, 'under': true},
          {
            'sprite': 'key',
            'track': [
              [0, 0, 1],
            ],
          },
        ],
        'files': {
          'door': 'https://togetherly.day/api/files/catalog_items/splash_hw_key/door_$suffix.webp',
          'key0': 'https://togetherly.day/api/files/catalog_items/splash_hw_key/key0_$suffix.webp',
          'key1': 'https://togetherly.day/api/files/catalog_items/splash_hw_key/key1_$suffix.webp',
          'still': 'https://togetherly.day/api/files/catalog_items/splash_hw_key/still_$suffix.webp',
        },
      },
    })!;

void main() {
  final october = DateTime(2026, 10, 25, 12);
  late Directory root;
  late List<String> fetched;
  String? failOn;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('splash');
    fetched = [];
    failOn = null;
    final service = LaunchSplashService.instance..debugReset();
    LaunchSplashService.rootDir = () async => root;
    LaunchSplashService.fetch = (url) async {
      fetched.add(url);
      if (failOn != null && url.contains(failOn!)) return null;
      return [1, 2, 3, url.length];
    };
    expect(service.selected, '');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('выбор качает все файлы, и заставка готова к запуску', () async {
    final service = LaunchSplashService.instance;
    expect(await service.select(_splash()), isTrue);
    expect(service.selected, 'hw_key');
    expect(fetched.length, 4);
    final ready = await service.readyForLaunch(october);
    expect(ready, isNotNull);
    expect(File(ready!.files['door']!).existsSync(), isTrue);
    expect(ready.files['door']!.startsWith(root.path), isTrue, reason: 'играть с диска, не из сети');
  });

  test('обрыв посреди — заставка не играет, а повтор докачивает', () async {
    final service = LaunchSplashService.instance;
    failOn = 'key1';
    expect(await service.select(_splash()), isFalse);
    expect(await service.readyForLaunch(october), isNull);
    failOn = null;
    fetched.clear();
    expect(await service.ensureDownloaded(_splash()), isTrue);
    expect(fetched.where((u) => u.contains('door')), isEmpty, reason: 'уже лежащее заново не качаем');
    expect(await service.readyForLaunch(october), isNotNull);
  });

  test('повторный выбор не качает ничего', () async {
    final service = LaunchSplashService.instance;
    await service.select(_splash());
    fetched.clear();
    await service.select(_splash());
    expect(fetched, isEmpty);
  });

  test('новая выкладка той же заставки качается заново', () async {
    final service = LaunchSplashService.instance;
    await service.select(_splash());
    fetched.clear();
    await service.ensureDownloaded(_splash(suffix: 'b'));
    expect(fetched.length, 4);
    final ready = await service.readyForLaunch(october);
    expect(ready!.files['door']!.endsWith('door_b.webp'), isTrue);
  });

  test('после конца сезона не играет', () async {
    final service = LaunchSplashService.instance;
    await service.select(_splash());
    expect(await service.readyForLaunch(DateTime(2026, 11, 1, 9)), isNull);
  });

  test('«Без заставки» — не играет и место на диске свободно', () async {
    final service = LaunchSplashService.instance;
    await service.select(_splash());
    await service.select(null);
    expect(service.selected, '');
    expect(await service.readyForLaunch(october), isNull);
    expect(Directory('${root.path}/hw_key').existsSync(), isFalse);
  });

  test('выбор переживает перезапуск', () async {
    await LaunchSplashService.instance.select(_splash());
    LaunchSplashService.instance.debugReset();
    expect(await LaunchSplashService.instance.readyForLaunch(october), isNotNull);
  });

  test('заставку сняли с сервера — не играет', () async {
    final service = LaunchSplashService.instance;
    await service.select(_splash());
    await service.syncWithCatalog(const []);
    expect(await service.readyForLaunch(october), isNull);
  });
}
