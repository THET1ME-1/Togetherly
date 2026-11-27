import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/doing.dart';

void main() {
  final noon = DateTime(2026, 11, 11, 12);

  group('занятие из записи виджета', () {
    test('читается из поля data', () {
      final doing = Doing.fromData({
        'note': {'text': 'привет'},
        'doing': {'id': 'shower', 'text': '', 'at': noon.millisecondsSinceEpoch},
      });
      expect(doing.id, 'shower');
      expect(doing.atMs, noon.millisecondsSinceEpoch);
    });

    test('пустая или битая запись — занятия нет', () {
      expect(Doing.fromData(null).isNone, isTrue);
      expect(Doing.fromData('мусор').isNone, isTrue);
      expect(Doing.fromData({'doing': 'мусор'}).isNone, isTrue);
      expect(Doing.fromData({'doing': {'id': 7}}).isNone, isTrue);
    });

    test('незнакомое занятие от более новой сборки не показывается', () {
      final doing = Doing.fromData({
        'doing': {'id': 'skydiving', 'at': noon.millisecondsSinceEpoch},
      });
      expect(doing.isNone, isTrue);
    });

    test('своё слово обрезается по краям и до 24 знаков', () {
      final doing = Doing.own('  на паре по матанализу до самого вечера  ', noon);
      expect(doing.id, kDoingOwn);
      expect(doing.text, 'на паре по матанализу до');
      expect(doing.text.length, kDoingTextMax);
    });

    test('пустое своё слово занятием не считается', () {
      expect(Doing.own('   ', noon).isNone, isTrue);
    });
  });

  group('запись в поле data', () {
    test('соседние ключи остаются на месте', () {
      final data = withDoing({'note': {'text': 'привет'}, 'room': '#cfe3fb'}, Doing.of('gym', noon));
      expect(data['note'], {'text': 'привет'});
      expect(data['room'], '#cfe3fb');
      expect(data['doing'], {'id': 'gym', 'text': '', 'at': noon.millisecondsSinceEpoch});
    });

    test('снятое занятие убирает ключ', () {
      final data = withDoing({'doing': {'id': 'gym'}, 'room': '#cfe3fb'}, const Doing.none());
      expect(data.containsKey('doing'), isFalse);
      expect(data['room'], '#cfe3fb');
    });

    test('цвет комнатки пишется и снимается, не трогая занятие', () {
      final painted = withRoom({'doing': {'id': 'gym'}}, const Color(0xFFCFE3FB));
      expect(painted['room'], '#cfe3fb');
      expect(painted['doing'], {'id': 'gym'});
      expect(withRoom(painted, null).containsKey('room'), isFalse);
    });
  });

  group('цвет комнатки', () {
    test('читается только как #rrggbb', () {
      expect(roomColorOf({'room': '#CFE3FB'}), const Color(0xFFCFE3FB));
      expect(roomColorOf({'room': 'cfe3fb'}), isNull);
      expect(roomColorOf({'room': '#fff'}), isNull);
      expect(roomColorOf({'room': 12}), isNull);
      expect(roomColorOf(null), isNull);
    });

    test('у белой стены пол и горошек чуть темнее', () {
      expect(roomFloor(const Color(0xFFFFFFFF)), const Color(0xFFEFEDEE));
    });

    test('у светлой стены они светлее', () {
      expect(roomFloor(const Color(0xFFCFE3FB)), const Color(0xFFE9F2FD));
    });

    test('у тёмной стены они тоже светлее, но чуть-чуть', () {
      expect(roomFloor(const Color(0xFF26262B)), const Color(0xFF49494D));
    });
  });

  group('подписи', () {
    test('время начала — часы и минуты по часам телефона', () {
      expect(doingTime(DateTime(2026, 11, 11, 9, 5).millisecondsSinceEpoch), '09:05');
      expect(doingTime(0), '');
    });

    test('картинка занятия лежит в каталоге под ключом act_<id>', () {
      expect(Doing.of('movie', noon).artKey, 'act_movie');
      expect(Doing.own('на паре', noon).artKey, isNull);
      expect(const Doing.none().artKey, isNull);
    });

    test('занятий двадцать восемь, и все разные', () {
      expect(kDoingIds.length, 28);
      expect(kDoingIds.toSet().length, 28);
    });

    test('вторая десятка читается из записи, а не гаснет', () {
      for (final id in ['miss', 'lazy', 'sad', 'wake', 'ready', 'phone', 'together', 'read', 'music', 'draw']) {
        final doing = Doing.fromData({'doing': {'id': id, 'text': '', 'at': noon.millisecondsSinceEpoch}});
        expect(doing.id, id);
        expect(doing.artKey, 'act_$id');
      }
    });
  });
}
