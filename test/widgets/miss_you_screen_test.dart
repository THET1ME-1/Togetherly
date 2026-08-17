import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:love_app/screens/miss_you_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/utils/safe_text.dart';

/// Экран открывается и без пары: на 360 dp он обязан помещаться, а не сыпать
/// overflow — на этом уже горели лист настроения и бенто виджетов.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host(AppTheme theme) => MediaQuery(
        data: const MediaQueryData(size: Size(360, 780)),
        child: MaterialApp(
          home: MissYouScreen(
            theme: theme,
            groupId: '',
            myUid: 'me',
            partnerUid: '',
            partnerName: '',
          ),
        ),
      );

  testWidgets('рисует оба счёта и пустую неделю', (tester) async {
    await tester.pumpWidget(host(AppThemes.byIndex(7)));
    await tester.pump();

    expect(find.text('0'), findsNWidgets(2));
    // Язык прогона зависит от локали устройства, поэтому строку берём из
    // словаря: проверяется ветка пустой недели, а не конкретный перевод.
    expect(find.text(LocaleService.current.missYouWeekEmpty), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('на тёмной теме тоже без переполнений', (tester) async {
    await tester.pumpWidget(host(AppThemes.byIndex(20)));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  // Жалоба со скриншотом (16.08.2026): у партнёра в кружке фото, у себя буква
  // «Т» — заглушку строило слово «Ты» из подписи, а не имя человека. Свой
  // аватар экрану вообще не передавали.
  testWidgets('свой кружок берёт букву имени, а не подписи «Ты»',
      (tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(360, 780)),
      child: MaterialApp(
        home: MissYouScreen(
          theme: AppThemes.byIndex(7),
          groupId: '',
          myUid: 'me',
          myName: 'Гуляйн',
          partnerUid: '',
          partnerName: '',
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Г'), findsOneWidget);
    expect(
      find.text(LocaleService.current.missYouYou.firstGraphemeUpper()),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
