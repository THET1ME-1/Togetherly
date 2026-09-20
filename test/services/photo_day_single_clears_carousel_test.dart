// Виджет «Фото партнёра» возвращался к старой карусели (обращение 12,
// 12.09.2026: «Отображает старые фото, новые не показывает»).
//
// Партнёр однажды собрал карусель, потом прислал одно фото. Одиночное фото
// писало только ключ `path`, а `paths` оставался от карусели. Нативная ротация
// (PhotoDayRotationReceiver.kt) раз в 15 минут брала кадр из `paths` и
// возвращала на стол старые снимки. То же после «Убрать у партнёра».
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/home_widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, Object?>{}; // HomeWidgetPreferences
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('pp_');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('home_widget'), (c) async {
      final a = (c.arguments as Map?) ?? {};
      switch (c.method) {
        case 'saveWidgetData':
          store[a['id'] as String] = a['data'];
          return true;
        case 'getWidgetData':
          return store[a['id'] as String] ?? a['defaultValue'];
        default:
          return true;
      }
    });
    // MainActivity.updatePhotoDayCarousel пишет в тот же HomeWidgetPreferences.
    m.setMockMethodCallHandler(const MethodChannel('love_app/widgets'), (c) async {
      if (c.method == 'updatePhotoDayCarousel') {
        final a = c.arguments as Map;
        final id = a['widgetId'];
        store['photo_day_widget_${id}_paths'] = jsonEncode(a['paths']);
        store['photo_day_widget_${id}_current_index'] = a['currentIndex'];
        return true;
      }
      return <int>[];
    });
    m.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (c) async => tmp.path);
  });

  File jpg(String name) =>
      File('${tmp.path}/$name.jpg')..writeAsBytesSync(List.filled(4096, 7));

  // Порт PhotoDayRotationReceiver.onReceive для одного экземпляра:
  // ACTION_ROTATE_TIMER, rotation_type по умолчанию «unlock», last_update давно.
  void nativeRotate(int id) {
    final raw = store['photo_day_widget_${id}_paths'] as String?;
    if (raw == null || raw.isEmpty) return;
    final paths = (jsonDecode(raw) as List).cast<String>();
    if (paths.length <= 1) return;
    var idx = (store['photo_day_widget_${id}_current_index'] as int?) ?? 0;
    idx = (idx + 1) % paths.length;
    store['photo_day_widget_${id}_current_index'] = idx;
    store['photo_day_widget_${id}_path'] = paths[idx];
  }

  test('новое одиночное фото партнёра переживает ротацию', () async {
    const id = 7;
    final hws = HomeWidgetService.instance;
    // 1. Партнёр прислал карусель из трёх кадров.
    await hws.syncPhotoOfDayCarousel(
      photoUrls: [jpg('a').path, jpg('b').path, jpg('c').path],
      widgetId: id,
      groupId: 'g',
    );

    // 2. Партнёр прислал одно новое фото (updatePhotoForPartnerUrl → список из одного).
    await hws.syncPhotoOfDay(
      photoUrl: '',
      localFile: jpg('new'),
      widgetId: id,
      groupId: 'g',
    );
    final fresh = store['photo_day_widget_${id}_path'] as String;

    // 3. Через ≤15 минут срабатывает будильник ротации.
    nativeRotate(id);
    final shown = store['photo_day_widget_${id}_path'];

    expect(shown, fresh, reason: 'виджет вернулся к кадру старой карусели');
  });

  test('после «Убрать у партнёра» старая карусель не возвращается', () async {
    const id = 8;
    final hws = HomeWidgetService.instance;
    await hws.syncPhotoOfDayCarousel(
      photoUrls: [jpg('a').path, jpg('b').path],
      widgetId: id,
      groupId: 'g',
    );
    await hws.clearPhotoDayWidget(id, 'g');
    expect(store['photo_day_widget_${id}_paths'], anyOf(isNull, ''));
    nativeRotate(id);
    expect(store['photo_day_widget_${id}_path'], anyOf(isNull, ''));
  });

  test('ротация пропускает виджет с пустым списком кадров', () {
    final kt = File(
            'android/app/src/main/kotlin/com/togetherly/love/PhotoDayRotationReceiver.kt')
        .readAsStringSync();
    expect(kt, contains('if (pathsStr.isNullOrEmpty()) continue'));
  });
}
