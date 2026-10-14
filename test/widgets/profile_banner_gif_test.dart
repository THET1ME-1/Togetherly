// Баннер профиля с сервера: качается один раз и дальше берётся с диска, а GIF
// в нём шевелится, только пока у владельца открыт Togetherly+
// (`ProfileBanner.animate`). Без Плюса баннер обязан остаться видимым и стоять
// первым кадром, а не пропасть и не листаться дальше.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:love_app/screens/profile/profile_banner.dart';
import 'package:love_app/services/banner_cache.dart';

import '../helpers/banner_cache_fakes.dart';

/// Два кадра по 100 мс: красный, потом синий.
List<int> _twoFrameGif() {
  img.Image frame(int r, int b) {
    final f = img.Image(width: 8, height: 8);
    img.fill(f, color: img.ColorRgb8(r, 0, b));
    f.frameDuration = 100;
    return f;
  }

  final gif = frame(255, 0)..addFrame(frame(0, 255));
  return img.encodeGif(gif);
}

void main() {
  late Directory dir;
  late FakeBannerServer server;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('banner_gif');
    final bytes = _twoFrameGif();
    server = FakeBannerServer((_) => bytes);
    BannerCache.instance = fakeBannerCache(fakeBannerManager(dir, server));
    imageCache.clear();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> pumpBanner(WidgetTester tester, {required bool animate}) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProfileBanner(
            bannerUrl: 'pb://media/rec1/profile.gif',
            background: Colors.white,
            animate: animate,
          ),
        ),
      ));

  /// Скачивание, диск и разбор кадров идут настоящим временем, смена кадров —
  /// по таймеру теста.
  Future<void> tick(WidgetTester tester) async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 60));
  }

  /// Цвет кадра на экране: «red», «blue» или null, пока кадра нет.
  Future<String?> shownColor(WidgetTester tester) async {
    final raw = find.byType(RawImage);
    if (raw.evaluate().isEmpty) return null;
    final image = tester.widget<RawImage>(raw).image;
    if (image == null) return null;
    final px = await tester.runAsync(() => image.toByteData());
    final r = px!.getUint8(0);
    final b = px.getUint8(2);
    if (r > 200 && b < 60) return 'red';
    if (b > 200 && r < 60) return 'blue';
    return null;
  }

  /// Какие цвета показал баннер за ~0,6 секунды после первого кадра.
  Future<Set<String>> shownColors(WidgetTester tester) async {
    for (var i = 0; i < 40 && await shownColor(tester) == null; i++) {
      await tick(tester);
    }
    final seen = <String>{};
    for (var i = 0; i < 10; i++) {
      final c = await shownColor(tester);
      if (c != null) seen.add(c);
      await tick(tester);
    }
    return seen;
  }

  /// Кэш оставляет таймеры уборки и записи на диск: даём им отработать,
  /// пока папка теста на месте.
  Future<void> drainCache(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 15));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
  }

  testWidgets('с Плюсом GIF идёт по кругу', (tester) async {
    await pumpBanner(tester, animate: true);
    expect(await shownColors(tester), {'red', 'blue'});
    await drainCache(tester);
  });

  testWidgets('без Плюса виден первый кадр, и дальше он не листается',
      (tester) async {
    await pumpBanner(tester, animate: false);
    expect(await shownColors(tester), {'red'});
    await drainCache(tester);
  });

  testWidgets('второй показ берёт баннер с диска, без скачивания',
      (tester) async {
    await pumpBanner(tester, animate: true);
    expect(await shownColors(tester), isNotEmpty);
    // Профиль закрыли и открыли снова.
    await tester.pumpWidget(const SizedBox());
    await pumpBanner(tester, animate: true);
    expect(await shownColors(tester), isNotEmpty);
    expect(server.downloads, hasLength(1));
    await drainCache(tester);
  });
}
