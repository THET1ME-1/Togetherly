// Баннер профиля качается с сервера один раз на ссылку, дальше только диск.
//
// Новый баннер — новая запись `media`, значит новая ссылка: по ней и качаем
// заново. Общий кэш картинок так не умел: он перекачивал файл целиком, как
// только выходил срок свежести из заголовка сервера (30 дней, ETag нет), и
// вытеснял баннер, когда лента воспоминаний набирала свои 5000 файлов.
import 'dart:async';
import 'dart:io' as io;

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/banner_cache.dart';

import '../helpers/banner_cache_fakes.dart';

void main() {
  late io.Directory tmp;
  late FakeBannerServer server;
  late CacheManager manager;
  late BannerCache cache;

  BannerCache open() {
    manager = fakeBannerManager(tmp, server);
    return fakeBannerCache(manager);
  }

  setUp(() {
    tmp = io.Directory.systemTemp.createTempSync('banner_cache');
    server = FakeBannerServer(
        (url) => 'GIF89a ${Uri.parse(url).path}'.codeUnits);
    cache = open();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  const gif = 'pb://media/rec1/profile.gif';

  test('качает один раз, дальше берёт с диска, хотя срок свежести вышел',
      () async {
    final first = await cache.file(gif);
    final second = await cache.file(gif);
    expect(server.downloads, hasLength(1));
    expect(first, isNotNull);
    expect(await second!.readAsString(),
        'GIF89a /api/files/media/rec1/profile.gif');
  });

  test('после перезапуска приложения тоже не качает', () async {
    await cache.file(gif);
    // Записи кэша ложатся на диск с задержкой; закрытие дописывает их сразу.
    await manager.dispose();
    final restarted = open();
    expect(await restarted.file(gif), isNotNull);
    expect(server.downloads, hasLength(1));
  });

  test('новый баннер — новая ссылка — качается заново', () async {
    await cache.file(gif);
    await cache.file('pb://media/rec2/profile.gif');
    expect(server.downloads, hasLength(2));
  });

  test('готовый адрес файла и pb:// — один и тот же баннер', () async {
    await cache.file(gif);
    await cache.file('https://togetherly.day/api/files/media/rec1/profile.gif');
    expect(server.downloads, hasLength(1));
  });

  test('два показа сразу ждут одно скачивание', () async {
    server.gate = Completer<void>();
    final a = cache.file(gif);
    final b = cache.file(gif);
    await Future<void>.delayed(Duration.zero);
    server.gate!.complete();
    expect(await a, isNotNull);
    expect(await b, isNotNull);
    expect(server.downloads, hasLength(1));
  });

  test('скачанный файл известен сразу, без ожидания', () async {
    expect(cache.known(gif), isNull);
    await cache.file(gif);
    expect(cache.known(gif), isNotNull);
  });

  test('свой новый баннер ложится в кэш без скачивания', () async {
    final local = io.File('${tmp.path}/picked.gif')
      ..writeAsStringSync('GIF89a мой');
    await cache.put(gif, local);
    final file = await cache.file(gif);
    expect(server.downloads, isEmpty);
    expect(await file!.readAsString(), 'GIF89a мой');
    expect(cache.known(gif), isNotNull);
  });

  test('без сети вернёт null, а следующий показ попробует снова', () async {
    server.offline = true;
    expect(await cache.file(gif), isNull);
    server.offline = false;
    expect(await cache.file(gif), isNotNull);
    expect(server.downloads, hasLength(2));
  });
}
