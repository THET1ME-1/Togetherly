import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/l10n/dict/doing.dart';
import 'package:love_app/l10n/uk/doing.dart';
import 'package:love_app/l10n/zh/doing.dart';
import 'package:love_app/models/doing.dart';
import 'package:love_app/widgets/doing/doing_rooms.dart';
import 'package:love_app/widgets/doing/doing_sheet.dart';

void main() {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFE8556F));
  final noon = DateTime(2026, 11, 11, 12);

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('лист «Чем ты занят?»', () {
    testWidgets('нажатие на занятие сохраняет его и закрывает лист', (tester) async {
      Doing? saved;
      await tester.pumpWidget(host(DoingSheet(
        groupId: 'g1',
        scheme: scheme,
        saveDoing: (doing) async {
          saved = doing;
          return true;
        },
      )));
      await tester.ensureVisible(find.byKey(const Key('doing_tile_cook')));
      await tester.tap(find.byKey(const Key('doing_tile_cook')));
      await tester.pumpAndSettle();
      expect(saved?.id, 'cook');
    });

    testWidgets('своё слово уходит как отдельное занятие', (tester) async {
      Doing? saved;
      await tester.pumpWidget(host(DoingSheet(
        groupId: 'g1',
        scheme: scheme,
        saveDoing: (doing) async {
          saved = doing;
          return true;
        },
      )));
      await tester.enterText(find.byKey(const Key('doing_own')), 'на паре');
      await tester.ensureVisible(find.byKey(const Key('doing_own_done')));
      await tester.tap(find.byKey(const Key('doing_own_done')));
      await tester.pumpAndSettle();
      expect(saved?.isOwn, isTrue);
      expect(saved?.text, 'на паре');
    });

    testWidgets('сервер не ответил — лист остаётся и говорит об этом', (tester) async {
      await tester.pumpWidget(host(DoingSheet(groupId: 'g1', scheme: scheme, saveDoing: (_) async => false)));
      await tester.tap(find.byKey(const Key('doing_tile_sleep')));
      await tester.pumpAndSettle();
      expect(find.text(trKey('doing.failed')), findsOneWidget);
      expect(find.byKey(const Key('doing_tile_sleep')), findsOneWidget);
    });

    testWidgets('«убрать занятие» есть только когда оно стоит', (tester) async {
      await tester.pumpWidget(host(DoingSheet(groupId: 'g1', scheme: scheme, saveDoing: (_) async => true)));
      expect(find.byKey(const Key('doing_clear')), findsNothing);

      Doing? saved;
      await tester.pumpWidget(host(DoingSheet(
        key: const ValueKey('второй'),
        groupId: 'g1',
        scheme: scheme,
        current: Doing.of('gym', noon),
        saveDoing: (doing) async {
          saved = doing;
          return true;
        },
      )));
      await tester.ensureVisible(find.byKey(const Key('doing_clear')));
      await tester.tap(find.byKey(const Key('doing_clear')));
      await tester.pumpAndSettle();
      expect(saved?.isNone, isTrue);
    });

    testWidgets('цвет комнатки сохраняется по нажатию, «как в теме» его снимает', (tester) async {
      final painted = <Color?>[];
      await tester.pumpWidget(host(DoingSheet(
        groupId: 'g1',
        scheme: scheme,
        saveColor: (wall) async {
          painted.add(wall);
          return true;
        },
      )));
      await tester.ensureVisible(find.byKey(const Key('doing_color_#cfe3fb')));
      await tester.tap(find.byKey(const Key('doing_color_#cfe3fb')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('doing_color_theme')));
      await tester.pump();
      expect(painted, [const Color(0xFFCFE3FB), null]);
    });

    testWidgets('лист помещается на маленьком телефоне', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(host(DoingSheet(groupId: 'g1', scheme: scheme, current: Doing.of('gym', noon))));
      expect(tester.takeException(), isNull);
    });
  });

  group('превью «Комнатки»', () {
    DoingRooms rooms({Doing my = const Doing.none(), Doing partner = const Doing.none(), DateTime? now}) => DoingRooms(
          my: DoingRoomLook(wall: const Color(0xFFFFD9DE), doing: my),
          partner: DoingRoomLook(wall: const Color(0xFFFFDCBB), doing: partner),
          now: now ?? noon,
        );

    testWidgets('у занятия видны название и время, имён нет', (tester) async {
      await tester.pumpWidget(host(Center(child: SizedBox(width: 338, child: rooms(my: Doing.of('shower', noon), partner: Doing.own('на паре', noon))))));
      expect(find.text(trKey('doing.shower')), findsOneWidget);
      expect(find.text('на паре'), findsOneWidget);
      expect(find.text('12:00'), findsNWidgets(2));
    });

    testWidgets('погасшее занятие не показывается', (tester) async {
      await tester.pumpWidget(host(Center(child: SizedBox(width: 338, child: rooms(my: Doing.of('shower', noon), now: noon.add(const Duration(hours: 4)))))));
      expect(find.text(trKey('doing.shower')), findsNothing);
      expect(find.text('12:00'), findsNothing);
    });

    testWidgets('самое длинное название не ломает узкий виджет', (tester) async {
      await tester.pumpWidget(host(Center(child: SizedBox(width: 250, child: rooms(my: Doing.of('gym', noon), partner: Doing.own('очень длинное своё слово', noon))))));
      expect(tester.takeException(), isNull);
    });
  });

  group('строки', () {
    test('у каждого занятия есть название на всех девяти языках', () {
      for (final id in kDoingIds) {
        final key = 'doing.$id';
        expect(doingStrings[key]?.keys.toSet(), {'ru', 'en', 'pt', 'it', 'es', 'fr', 'de'}, reason: key);
        expect(doingUk[key], isNotNull, reason: 'нет украинского: $key');
        expect(doingZh[key], isNotNull, reason: 'нет китайского: $key');
      }
    });

    test('украинский и китайский покрывают весь раздел', () {
      expect(doingUk.keys.toSet(), doingStrings.keys.toSet());
      expect(doingZh.keys.toSet(), doingStrings.keys.toSet());
    });

    test('название занятия влезает в плашку виджета', () {
      // Плашка вмещает около тринадцати знаков, длиннее — многоточие.
      final long = <String>[];
      for (final id in kDoingIds) {
        final names = {...?doingStrings['doing.$id'], 'uk': doingUk['doing.$id']!, 'zh': doingZh['doing.$id']!};
        names.forEach((lang, name) {
          if (name.length > 13) long.add('$lang $id: $name');
        });
      }
      expect(long, isEmpty);
    });
  });

  group('подключено', () {
    final screen = File('lib/screens/widget_screen.dart').readAsStringSync();
    final home = File('lib/screens/home_screen.dart').readAsStringSync();
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final bundle = File('ios/TogetherlyWidget/TogetherlyWidgetBundle.swift').readAsStringSync();

    test('карточка стоит в галерее и привязывается к своей паре', () {
      expect(screen, contains('_cardDoing)'));
      expect(screen, contains("'doing' => 'doing'"));
      expect(screen, contains("case 'doing':"));
    });

    test('нажатие на виджет открывает выбор занятия', () {
      expect(home, contains("uri.host == 'doing'"));
      expect(File('lib/services/deep_link_service.dart').readAsStringSync(), contains("'doing'"));
    });

    test('виджет объявлен на обеих платформах', () {
      expect(manifest, contains('.DoingWidgetProvider'));
      expect(bundle, contains('DoingWidget()'));
    });
  });
}
