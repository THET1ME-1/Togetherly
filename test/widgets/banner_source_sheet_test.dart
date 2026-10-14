// Лист смены баннера: строка GIF — вещь Togetherly+. Без Плюса она с замком
// и подписью, с Плюсом без них, а там, где Плюса нет вовсе, её нет.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/profile/banner_source_sheet.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/plus_access.dart';

void main() {
  final cs = ColorScheme.fromSeed(seedColor: const Color(0xFFFF7E8B));

  setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  Future<void> pumpSheet(
    WidgetTester tester,
    PlusGate gate, {
    double width = 393,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: BannerSourceSheet(cs: cs, gifGate: gate),
        ),
      ),
    ));
  }

  testWidgets('без Плюса GIF с замком и подписью Togetherly+', (tester) async {
    await pumpSheet(tester, PlusGate.locked);
    expect(find.text('Анимированный GIF'), findsOneWidget);
    expect(find.text('Togetherly+'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
  });

  testWidgets('с Плюсом GIF без замка', (tester) async {
    await pumpSheet(tester, PlusGate.open);
    expect(find.text('Анимированный GIF'), findsOneWidget);
    expect(find.text('Togetherly+'), findsNothing);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
  });

  testWidgets('где Плюса нет, строки GIF нет', (tester) async {
    await pumpSheet(tester, PlusGate.hidden);
    expect(find.text('Анимированный GIF'), findsNothing);
    expect(find.text(LocaleService.current.photoFromGallery), findsOneWidget);
  });

  testWidgets('нажатие на строку отдаёт выбор', (tester) async {
    BannerSource? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showBannerSourceSheet(
              context,
              cs: cs,
              gifGate: PlusGate.locked,
            ),
            child: const Text('баннер'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('баннер'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Анимированный GIF'));
    await tester.pumpAndSettle();
    expect(picked, BannerSource.gif);
  });

  testWidgets('немецкий на 320 dp при шрифте 1.3 влезает', (tester) async {
    LocaleService.instance.setLanguage(AppLanguage.de);
    await pumpSheet(tester, PlusGate.locked, width: 320, scale: 1.3);
    expect(tester.takeException(), isNull);
    expect(find.text('Animiertes GIF'), findsOneWidget);
  });
}
