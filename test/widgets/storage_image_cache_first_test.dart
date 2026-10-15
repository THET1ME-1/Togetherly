// Снимок, который уже лежит в кэше, рисуется сразу, без файлового токена.
//
// Жалоба 15.10.2026: «нифига не кешируется, нет фото, нет ничего» — аватарки
// пустыми кружками и лента без снимков, пока не ответит сеть. Защищённые файлы
// (`pb://`) ждали токен из сети ДО того, как спросить кэш, хотя ключ кэша
// токена не содержит. На рвущейся связи токен идёт до 12 секунд, а без сети не
// приходит вовсе — и скачанный снимок не показывался никогда.
import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:love_app/widgets/storage_image.dart';

import '../helpers/banner_cache_fakes.dart';

void main() {
  late io.Directory dir;
  late FakeBannerServer server;

  setUp(() {
    dir = io.Directory.systemTemp.createTempSync('storage_image_');
    server = FakeBannerServer((_) => img.encodePng(img.Image(width: 4, height: 4)));
  });

  tearDown(() {
    StorageImage.debugCacheManager = null;
    StorageImage.debugResolve = null;
    StorageImage.debugForgetDisk();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  const ref = 'pb://media/abc123def456ghi/photo.png';

  Widget host() => const MaterialApp(
        home: Center(
          child: StorageImage(
            imageUrl: ref,
            width: 80,
            height: 80,
            placeholder: _waiting,
          ),
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  bool drawsFromDisk(WidgetTester tester) => tester
      .widgetList<Image>(find.byType(Image))
      .any((w) {
        final p = w.image;
        final inner = p is ResizeImage ? p.imageProvider : p;
        return inner is FileImage;
      });

  // Кэш заводится вне тестовых часов: его чтение и запись файлов настоящие, и
  // внутри поддельного времени они не доходили до конца — тест висел.
  Future<CacheManager> cacheWithPhoto(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        final manager = fakeBannerManager(dir, server);
        await manager.putFile(
            'v2|$ref', img.encodePng(img.Image(width: 4, height: 4)),
            fileExtension: 'png');
        return manager;
      }))!;

  testWidgets('снимок из кэша рисуется, пока сеть молчит', (tester) async {
    StorageImage.debugCacheManager = await cacheWithPhoto(tester);
    // Токен не приходит никогда: связь рвётся.
    StorageImage.debugResolve = (_) => Completer<String?>().future;

    await tester.pumpWidget(host());
    await settle(tester);

    expect(drawsFromDisk(tester), isTrue,
        reason: 'снимок лежит на диске — ждать сеть незачем');
    expect(find.text('ждём'), findsNothing);
    expect(server.downloads, isEmpty);
  });

  testWidgets('без сети и с пустым кэшем — заглушка, не падение',
      (tester) async {
    StorageImage.debugCacheManager =
        (await tester.runAsync(() async => fakeBannerManager(dir, server)))!;
    StorageImage.debugResolve = (_) async => null;

    await tester.pumpWidget(host());
    await settle(tester);

    expect(drawsFromDisk(tester), isFalse);
    expect(tester.takeException(), isNull);
    // Промах кэша заводит его уборку через десять секунд.
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('второй показ того же снимка — с первого кадра', (tester) async {
    StorageImage.debugCacheManager = await cacheWithPhoto(tester);
    StorageImage.debugResolve = (_) => Completer<String?>().future;

    await tester.pumpWidget(host());
    await settle(tester);
    // Лента пересоздаёт плитку при прокрутке: ждать кэш второй раз не надо.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(host());

    expect(drawsFromDisk(tester), isTrue,
        reason: 'прокрутка ленты не должна мигать заглушкой');
    // Новая плитка всё равно сверяется с кэшем; даём ей ответить.
    await settle(tester);
  });
}

Widget _waiting(BuildContext context, String url) => const Text('ждём');
