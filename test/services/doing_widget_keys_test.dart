import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/doing.dart';
import 'package:love_app/services/doing_widget_keys.dart';

void main() {
  final at = DateTime(2026, 11, 11, 19, 40);

  group('ключи виджета «Чем заняты»', () {
    test('обе половины ложатся под ключи своей пары', () {
      final keys = doingWidgetKeys(
        groupId: 'g1',
        my: DoingHalf(doing: Doing.of('shower', at), wall: const Color(0xFFCFE3FB), avatarPath: '/a/me.jpg'),
        partner: DoingHalf(doing: Doing.own('на паре', at), avatarPath: ''),
      );
      expect(keys['doing_latest_group'], 'g1');
      expect(keys['doing_g1_my_id'], 'shower');
      expect(keys['doing_g1_my_text'], '');
      expect(keys['doing_g1_my_at'], '${at.millisecondsSinceEpoch}');
      expect(keys['doing_g1_my_wall'], '#cfe3fb');
      expect(keys['doing_g1_my_avatar'], '/a/me.jpg');
      expect(keys['doing_g1_partner_id'], 'own');
      expect(keys['doing_g1_partner_text'], 'на паре');
      expect(keys['doing_g1_partner_wall'], '');
    });

    test('половина без данных не трогается', () {
      // Фон поднимают на секунды, запись партнёра могла не успеть приехать:
      // стирать его половину на рабочем столе из-за этого нельзя.
      final keys = doingWidgetKeys(groupId: 'g1', my: DoingHalf(doing: Doing.of('cook', at)));
      expect(keys.keys.where((key) => key.contains('_partner_')), isEmpty);
      expect(keys['doing_g1_my_id'], 'cook');
    });

    test('занятия нет — половина честно пустая, а не прежняя', () {
      final keys = doingWidgetKeys(groupId: 'g1', my: const DoingHalf(doing: Doing.none()));
      expect(keys['doing_g1_my_id'], '');
      expect(keys['doing_g1_my_at'], '0');
    });

    test('без пары ключи идут под solo', () {
      final keys = doingWidgetKeys(groupId: '', my: DoingHalf(doing: Doing.of('cook', at)));
      expect(keys['doing_latest_group'], 'solo');
      expect(keys.containsKey('doing_solo_my_id'), isTrue);
    });
  });

  group('справочник занятий для натива', () {
    test('имя и ссылка на кадр у каждого занятия свои ключи', () {
      expect(doingNameKey('cook'), 'doing_name_cook');
      expect(doingArtKey('cook'), 'doing_art_cook');
      expect(doingArtUrlKey('cook'), 'doing_arturl_cook');
      expect(doingArtKey(kDoingIdle), 'doing_art_idle');
    });
  });

  group('натив читает те же ключи', () {
    // Разъезд имён ничем себя не выдаёт: виджет просто стоит пустой.
    final kotlin = File('android/app/src/main/kotlin/com/togetherly/love/DoingWidgetProvider.kt').readAsStringSync();
    final swift = File('ios/TogetherlyWidget/DoingWidget.swift').readAsStringSync();

    for (final field in ['id', 'text', 'at', 'wall', 'avatar']) {
      test('поле $field', () {
        expect(kotlin, contains('_$field'), reason: 'Android не читает поле $field');
        expect(swift, contains('_$field'), reason: 'iPhone не читает поле $field');
      });
    }

    test('справочник и срок', () {
      for (final source in [kotlin, swift]) {
        expect(source, contains('doing_name_'));
        expect(source, contains('doing_art_'));
      }
      // Пару виджет находит по указателю `doing_latest_group`: на iPhone
      // читает его сам, на Android — через общий помощник привязки.
      expect(swift, contains('doing_latest_group'));
      expect(kotlin, contains('getOrBind(context, "doing"'));
      // Три часа до покоя — одно число на Dart, Kotlin и Swift.
      expect(kDoingFades.inMilliseconds, 10800000);
      expect(kotlin, contains('10_800_000'));
      expect(swift, contains('10_800_000'));
    });
  });
}
