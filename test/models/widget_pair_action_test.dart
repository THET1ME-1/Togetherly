import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/doing.dart';
import 'package:love_app/models/widget_pair_action.dart';
import 'package:love_app/services/doing_widget_keys.dart';

/// Нажатие на «Чем заняты» вело на главную, а не к выбору занятия
/// (27.11.2026): на закрытом приложении ссылка приходила раньше пары и
/// отбрасывалась, половина партнёра на Android вела на главную, а лист ждал
/// сервер и без сети не открывался.
void main() {
  final now = DateTime(2026, 11, 27, 13, 0);
  final doing = Uri.parse('loveapp://doing');

  group('нажатие ждёт пару', () {
    test('отложенное нажатие выполняется, когда пара приехала', () {
      final action = WidgetPairAction()..hold(doing, now);
      expect(action.take(now.add(const Duration(seconds: 3))), doing);
    });

    test('забирается один раз', () {
      final action = WidgetPairAction()..hold(doing, now);
      action.take(now);
      expect(action.take(now), isNull);
    });

    test('устаревшее нажатие не выполняется', () {
      final action = WidgetPairAction()..hold(doing, now);
      expect(action.take(now.add(const Duration(minutes: 2))), isNull);
    });

    test('новое нажатие заменяет прежнее', () {
      final note = Uri.parse('loveapp://note');
      final action = WidgetPairAction()
        ..hold(doing, now)
        ..hold(note, now);
      expect(action.take(now), note);
    });

    test('ждут пару только действия, которым она нужна', () {
      for (final host in ['doing', 'note', 'draw', 'map', 'miss', 'mood', 'memory_lane']) {
        expect(widgetActionNeedsPair(Uri.parse('loveapp://$host')), isTrue, reason: host);
      }
      expect(widgetActionNeedsPair(Uri.parse('loveapp://home')), isFalse);
      expect(widgetActionNeedsPair(Uri.parse('loveapp://widgets')), isFalse);
    });

    test('нажатие на уведомление «А» ждёт пару, кроме главной и Плюса', () {
      // На закрытом приложении ссылка из шторки приходит раньше пары, как у
      // виджета: без ожидания «Сообщение» открыло бы главную, а не чат.
      for (final screen in ['chat', 'miss', 'mood', 'memories', 'dates', 'draw', 'chest']) {
        expect(widgetActionNeedsPair(Uri.parse('loveapp://open/$screen')), isTrue, reason: screen);
      }
      for (final screen in ['home', 'plus', 'gifts', 'task']) {
        expect(widgetActionNeedsPair(Uri.parse('loveapp://open/$screen')), isFalse, reason: screen);
      }
    });
  });

  group('лист выбора открывается и без сервера', () {
    test('своя половина читается обратно из ключей виджета', () {
      final at = DateTime(2026, 11, 27, 9, 15);
      final keys = doingWidgetKeys(
        groupId: 'g1',
        my: DoingHalf(doing: Doing.of('work', at), wall: const Color(0xFFCFE3FB)),
      );
      final mine = myHalfFromWidgetKeys('g1', (key) => keys[key]);
      expect(mine, isNotNull);
      expect(mine!.doing.id, 'work');
      expect(mine.doing.atMs, at.millisecondsSinceEpoch);
      expect(mine.wall, const Color(0xFFCFE3FB));
    });

    test('своё слово и цвет темы', () {
      final keys = doingWidgetKeys(
        groupId: 'g1',
        my: DoingHalf(doing: Doing.own('на паре', DateTime(2026, 11, 27))),
      );
      final mine = myHalfFromWidgetKeys('g1', (key) => keys[key])!;
      expect(mine.doing.isOwn, isTrue);
      expect(mine.doing.text, 'на паре');
      expect(mine.wall, isNull);
    });

    test('ключей нет — null', () {
      expect(myHalfFromWidgetKeys('g1', (_) => null), isNull);
    });
  });

  group('весь виджет ведёт к выбору занятия', () {
    test('Android: ни одной ссылки на главную, нажатие на корне', () {
      final kotlin = File('android/app/src/main/kotlin/com/togetherly/love/DoingWidgetProvider.kt').readAsStringSync();
      expect(kotlin.contains('loveapp://home'), isFalse);
      expect(kotlin.contains('R.id.widget_root'), isTrue);
      expect(kotlin.contains('loveapp://doing'), isTrue);
    });

    test('iPhone: весь виджет — loveapp://doing', () {
      final swift = File('ios/TogetherlyWidget/DoingWidget.swift').readAsStringSync();
      expect(swift.contains('.widgetURL(URL(string: "loveapp://doing"))'), isTrue);
    });

    test('главная откладывает нажатие до пары, а не бросает его', () {
      final home = File('lib/screens/home_screen.dart').readAsStringSync();
      expect(home.contains('_pairAction.hold(uri'), isTrue);
      expect(home.contains('_pairAction.take('), isTrue);
    });
  });
}
