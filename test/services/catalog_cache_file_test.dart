import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/catalog_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Обращение 605 (08.11.2026, iPhone 17): «каждый раз, когда я закрываю
/// приложение, вылетает аккаунт и сбрасываются настройки оформления». Кэш
/// каталога лежал в SharedPreferences и весил 4,5 МБ — больше 4 МБ, которые
/// iOS разрешает хранить в UserDefaults. iOS отказывался записывать настройки
/// целиком: вход, тему и метку «уже установлено». На следующем запуске метки
/// не было, и приложение считало себя новым — выходило из аккаунта и стирало
/// всё. На iPhone с 1.41 так за двое суток 271 человек.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('catalog_cache');
    CatalogService.cacheDir = () async => dir;
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('старый кэш из настроек переезжает в файл и уходит из настроек', () async {
    SharedPreferences.setMockInitialValues({'content_catalog_cache_v1': '[{"id":"x"}]'});

    final raw = await CatalogService.instance.debugReadCache();

    expect(raw, '[{"id":"x"}]');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('content_catalog_cache_v1'), isFalse);
    expect(File('${dir.path}/content_catalog_cache_v1.json').readAsStringSync(), '[{"id":"x"}]');
  });

  test('новый кэш пишется в файл, а не в настройки', () async {
    SharedPreferences.setMockInitialValues({});

    await CatalogService.instance.debugWriteCache('[{"id":"y"}]');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.contains('catalog')), isEmpty);
    expect(await CatalogService.instance.debugReadCache(), '[{"id":"y"}]');
  });

  test('файла и старого кэша нет — пусто, без ошибки', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await CatalogService.instance.debugReadCache(), isNull);
  });
}
